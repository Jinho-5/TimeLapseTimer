import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import Photos
import UIKit

enum CompositorError: LocalizedError {
    case folderEmpty
    case videoCreationFailed
    case exportFailed(String?)
    case photoLibraryDenied
    
    var errorDescription: String? {
        switch self {
        case .folderEmpty: return "타임랩스를 만들 촬영 이미지가 존재하지 않습니다."
        case .videoCreationFailed: return "동영상 생성기(AssetWriter) 초기화에 실패했습니다."
        case .exportFailed(let msg): return "최종 비디오 합성 내보내기 실패: \(msg ?? "알 수 없는 오류")"
        case .photoLibraryDenied: return "사진 라이브러리 접근 권한이 없습니다."
        }
    }
}

final class VideoCompositor {
    static let shared = VideoCompositor()
    private init() {}
    
    func buildTimelapse(
        fromFolder folderURL: URL,
        totalPhotos: Int,
        targetDuration: TimeInterval,
        subtitleLogs: [TimerLogEntry],
        isCountdown: Bool,
        isFront: Bool
    ) async throws -> URL {

        let targetFrameCount = Int(targetDuration * 30.0) // 20초 * 30fps = 600프레임
        guard totalPhotos > 0 else { throw CompositorError.folderEmpty }

        let step = max(1, Double(totalPhotos) / Double(targetFrameCount))

        let outputVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timelapse_composite_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputVideoURL)

        guard let assetWriter = try? AVAssetWriter(outputURL: outputVideoURL, fileType: .mp4) else {
            throw CompositorError.videoCreationFailed
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferCGImageCompatibilityKey as String: kCFBooleanTrue!,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: kCFBooleanTrue!,
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080
            ]
        )
        
        if assetWriter.canAdd(writerInput) {
            assetWriter.add(writerInput)
        } else {
            throw CompositorError.videoCreationFailed
        }
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        let queue = DispatchQueue(label: "com.timelapse.compositor.process")
        let box = UncheckedSendable(assetWriter)
        
        var currentFrameIndex = 0
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard currentFrameIndex < targetFrameCount else {
                        writerInput.markAsFinished()
                        box.value.finishWriting {
                            if box.value.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: CompositorError.exportFailed(box.value.error?.localizedDescription))
                            }
                        }
                        return
                    }
                    
                    let sourcePhotoIndex = Int(Double(currentFrameIndex) * step)
                    let imageURL = folderURL.appendingPathComponent("\(sourcePhotoIndex).jpg")
                    
                    if let image = UIImage(contentsOfFile: imageURL.path),
                       let pixelBuffer = self.newPixelBuffer(from: image, isFront: isFront) {
                        
                        let frameTime = CMTime(value: Int64(currentFrameIndex), timescale: 30)
                        
                        let realElapsedTime = Double(sourcePhotoIndex)
                        let matchedLog = subtitleLogs.first(where: { Int($0.videoTimestamp) == Int(realElapsedTime) })
                        
                        if let log = matchedLog {
                            self.drawOverlayText(on: pixelBuffer, logEntry: log, isCountdown: isCountdown)
                        }
                        
                        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
                    }
                    
                    currentFrameIndex += 1
                }
            }
        }
        
        GalleryStore.shared.save(videoAt: outputVideoURL, duration: targetDuration)
        try await saveToPhotoLibrary(url: outputVideoURL)
        return outputVideoURL
    }
    
    // MARK: - 완벽한 정방향 2층 자막 드로잉 (중앙 타이머 + 크기 확장 + 좌상단 밀착 완전체)
    private func drawOverlayText(on pixelBuffer: CVPixelBuffer, logEntry: TimerLogEntry, isCountdown: Bool) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd"
        let dateText = dateFormatter.string(from: logEntry.realWorldDate)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let realTimeText = timeFormatter.string(from: logEntry.realWorldDate)
        let topRowText = "\(dateText)  \(realTimeText)"
        
        let isOverrun = isCountdown && logEntry.displayValue < 0
        let absSeconds = Int(abs(logEntry.displayValue))
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let seconds = absSeconds % 60
        
        let prefix = isOverrun ? "+" : ""
        let timerText = String(format: "%@%02d:%02d:%02d", prefix, hours, minutes, seconds)
        let modeText = isCountdown ? "COUNTDOWN" : "STOPWATCH"
        
        let timerUIColor: UIColor
        if logEntry.phase == .paused {
            timerUIColor = .yellow
        } else if isOverrun || logEntry.phase == .overrun {
            timerUIColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        } else {
            timerUIColor = .white
        }

        let topAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 48, weight: .bold),
            .foregroundColor: UIColor(white: 1.0, alpha: 0.9)
        ]

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor(white: 1.0, alpha: 0.7),
            .kern: 2.0
        ]

        let timerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 120, weight: .bold),
            .foregroundColor: timerUIColor
        ]
        
        let topLine   = CTLineCreateWithAttributedString(NSAttributedString(string: topRowText, attributes: topAttributes))
        let labelLine = CTLineCreateWithAttributedString(NSAttributedString(string: modeText,   attributes: labelAttributes))
        let timerLine = CTLineCreateWithAttributedString(NSAttributedString(string: timerText,  attributes: timerAttributes))

        let topLineWidth = CTLineGetTypographicBounds(topLine,   nil, nil, nil)
        let labelWidth   = CTLineGetTypographicBounds(labelLine, nil, nil, nil)
        let timerWidth   = CTLineGetTypographicBounds(timerLine, nil, nil, nil)

        let centerX  = CGFloat(width)  / 2
        let centerY  = CGFloat(height) / 2
        let topBaseY = CGFloat(height) - 80

        context.saveGState()
        context.setShadow(offset: CGSize(width: 3, height: 3), blur: 10,
                          color: UIColor.black.withAlphaComponent(0.85).cgColor)

        // 좌측 상단: 날짜/시간
        context.textPosition = CGPoint(x: 40, y: topBaseY)
        CTLineDraw(topLine, context)

        // 카테고리 배지: 중앙 하단 (타이머 아래로 타이머~라벨 간격만큼 띄움)
        if let catName = logEntry.categoryName,
           let catHex  = logEntry.categoryColorHex {
            let badgeFontSz: CGFloat = 48
            let badgePadH:   CGFloat = 28
            let capsuleH:    CGFloat = 72

            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: badgeFontSz, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let badgeLine  = CTLineCreateWithAttributedString(NSAttributedString(string: catName, attributes: badgeAttrs))
            let badgeTextW = CTLineGetTypographicBounds(badgeLine, nil, nil, nil)
            let capsuleW   = CGFloat(badgeTextW) + badgePadH * 2
            let badgeTextY = centerY - 130   // 타이머 아래 150pt (라벨이 위로 떨어진 거리와 동일)
            let badgeX     = centerX - capsuleW / 2

            let capsuleRect = CGRect(x: badgeX, y: badgeTextY - 14, width: capsuleW, height: capsuleH)
            let corner      = capsuleH / 2
            let capsulePath = CGPath(roundedRect: capsuleRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

            // 배경 (shadow 없음)
            context.saveGState()
            context.setShadow(offset: .zero, blur: 0, color: CGColor(gray: 0, alpha: 0))
            context.addPath(capsulePath)
            context.setFillColor(uiColor(fromHex: catHex).cgColor)
            context.fillPath()
            context.restoreGState()

            // 흰색 텍스트 (외부 shadow 상속)
            context.textPosition = CGPoint(x: badgeX + badgePadH, y: badgeTextY)
            CTLineDraw(badgeLine, context)
        }

        // 중앙: 타이머
        context.textPosition = CGPoint(x: centerX - CGFloat(timerWidth) / 2, y: centerY - 40)
        CTLineDraw(timerLine, context)

        context.textPosition = CGPoint(x: centerX - CGFloat(labelWidth) / 2, y: centerY + 110)
        CTLineDraw(labelLine, context)

        context.restoreGState()
    }
    
    // MARK: - UIImage -> CVPixelBuffer 변환 헬퍼
    private func newPixelBuffer(from image: UIImage, isFront: Bool) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: 1920, height: 1080, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let ctx = context, let cgImage = image.cgImage else { return nil }

        // image.imageOrientation은 captureCurrentFrameToDisk에서 기록된 물리 방향.
        // 센서 네이티브 = landscapeRight(.up). 그 외 방향은 CGContext 변환으로 보정.
        switch image.imageOrientation {
        case .down:
            // landscapeLeft: 픽셀이 180° 뒤집혀 있음
            if isFront {
                // mirror-H + 180° = mirror-V (수직 반전)
                ctx.translateBy(x: 0, y: 1080)
                ctx.scaleBy(x: 1, y: -1)
            } else {
                ctx.translateBy(x: 1920, y: 1080)
                ctx.scaleBy(x: -1, y: -1)
            }
        default:
            // .up (landscapeRight), .right (portrait), .left (portraitUpsideDown)
            if isFront {
                ctx.translateBy(x: 1920, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        return buffer
    }
    
    private func uiColor(fromHex hex: String) -> UIColor {
        UIColor(hex: hex) ?? .systemOrange
    }

    private func saveToPhotoLibrary(url: URL) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw CompositorError.photoLibraryDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

private final class UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
