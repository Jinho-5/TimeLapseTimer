import AVFoundation
import Foundation
import UIKit

final class GalleryStore {
    static let shared = GalleryStore()
    private init() {}

    // 앱 내부 영구 저장 경로 (iCloud 백업 포함, Files 앱 미노출)
    static var videosDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeLapseVideos")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func videoURL(for item: GalleryItem) -> URL {
        Self.videosDirectory.appendingPathComponent("\(item.id.uuidString).mp4")
    }

    private func metaURL(for item: GalleryItem) -> URL {
        Self.videosDirectory.appendingPathComponent("\(item.id.uuidString).json")
    }

    // 합성 완료된 영상을 앱 내부로 복사하고 메타데이터 기록
    @discardableResult
    func save(videoAt srcURL: URL, duration: TimeInterval) -> GalleryItem {
        let item = GalleryItem(id: UUID(), date: Date(), duration: duration)
        try? FileManager.default.copyItem(at: srcURL, to: videoURL(for: item))
        if let data = try? JSONEncoder().encode(item) {
            try? data.write(to: metaURL(for: item), options: .atomic)
        }
        return item
    }

    // 저장된 항목 전체 로드 (최신순)
    func loadAll() -> [GalleryItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.videosDirectory, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(GalleryItem.self, from: Data(contentsOf: $0)) }
            .filter { FileManager.default.fileExists(atPath: videoURL(for: $0).path) }
            .sorted { $0.date > $1.date }
    }

    func delete(_ item: GalleryItem) {
        try? FileManager.default.removeItem(at: videoURL(for: item))
        try? FileManager.default.removeItem(at: metaURL(for: item))
    }

    // 영상 첫 프레임 근처에서 썸네일 생성
    func generateThumbnail(for item: GalleryItem) async -> UIImage? {
        let url = videoURL(for: item)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 270)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        return await withCheckedContinuation { cont in
            gen.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
                cont.resume(returning: cgImage.map { UIImage(cgImage: $0) })
            }
        }
    }
}
