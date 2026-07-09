import AVFoundation
import Combine
import CoreMotion
import CoreText
import Photos
import SwiftUI
import UIKit

enum RecordingState {
    case idle
    case recording
    case paused      // 타이머만 정지, 카메라는 계속 대기 중
    case processing  // 합성 중
}

struct TimerSnapshot {
    var displayValue: TimeInterval
    var phase: TimerPhase
    var realWorldDate: Date
    var isCountdown: Bool
}

@MainActor
final class CameraViewModel: NSObject, ObservableObject {

    // MARK: - Camera Core
    let captureSession = AVCaptureSession()
    @Published private(set) var videoDevice: AVCaptureDevice?

    // MARK: - Capture Outputs
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.timelapse.capture", qos: .userInitiated)

    // 💡 [Photo 기반 추가] 임시 보관 프레임 버퍼 및 타이머 카운터
    nonisolated(unsafe) var currentPixelBuffer: CVPixelBuffer?
    private var photoTimer: Timer?
    private var photoCount: Int = 0
    private var lastStopDisplayValue: TimeInterval?  // stopRecording 호출 순간의 displayValue

    // MARK: - State
    @Published var recordingState: RecordingState = .idle
    @Published var timerMode: TimerMode = .countdown(goal: 300)
    @Published var goalDuration: TimeInterval = 300
    @Published var useFrontCamera: Bool = false
    @Published var selectedCategory: TimerCategory? = nil

    // MARK: - Timer Display
    @Published var currentDate: Date = Date()
    @Published var timerDisplayValue: TimeInterval = 300
    @Published var isGoalReached: Bool = false

    // MARK: - 합성 / 저장 상태
    @Published var isCompositing    = false
    @Published var showSavedAlert   = false
    @Published var compositorError: String?

    // MARK: - 크래시 복구
    @Published private(set) var orphanedSession: RecordingSession?
    @Published private(set) var orphanedVideoURL: URL?
    @Published var showRecoveryAlert: Bool = false

    // MARK: - Session
    private(set) var currentSession: RecordingSession?
    private var recordingStartDate: Date?

    // 타이머 상태 스냅샷 (기존 브릿지 유지)
    private let _timerSnapshotLock = NSLock()
        nonisolated(unsafe) private var _timerSnapshot = TimerSnapshot(
            displayValue: 300, phase: .running, realWorldDate: Date(), isCountdown: true
        )
    nonisolated var timerSnapshot: TimerSnapshot {
        get {
            _timerSnapshotLock.lock()
            defer { _timerSnapshotLock.unlock() }
            return _timerSnapshot
        }
        set {
            _timerSnapshotLock.lock()
            defer { _timerSnapshotLock.unlock() }
            _timerSnapshot = newValue
        }
    }

    @Published var targetOutputDuration: TimeInterval = 20

    // MARK: - Combine
    private var clockCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    private var logCancellable: AnyCancellable?
    private var orientationCancellable: AnyCancellable?
    private var lifecycleCancellables = Set<AnyCancellable>()

    private var logFlushCounter: Int = 0

    // MARK: - CoreMotion
    private let motionManager = CMMotionManager()
    private var lastMotionOrientation: UIDeviceOrientation = .unknown

    // 💡 사진들이 프레임 단위로 임시 저장될 안전한 내장 샌드박스 경로
    private var timelapseFolderURL: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let folder = paths[0].appendingPathComponent("TimelapseFrames", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Init
    override init() {
        super.init()
        setupCaptureSession(position: .back)
        startWallClock()
        startObservingPhysicalOrientation()
        startMotionOrientationDetection()
        subscribeToLifecycleEvents()
        Task { @MainActor [weak self] in self?.checkForOrphanedSessions() }
    }

    // MARK: - Setup
    private func setupCaptureSession(position: AVCaptureDevice.Position) {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        for input in captureSession.inputs {
            if let vi = input as? AVCaptureDeviceInput, vi.device.hasMediaType(.video) {
                captureSession.removeInput(vi)
            }
        }

        guard
            let device   = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let videoIn  = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(videoIn)
        else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(videoIn)
        videoDevice = device

        // 하드웨어 캡처 자체는 안정적인 프리뷰 재생을 위해 30fps 정속으로 시동
        let d = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.activeVideoMinFrameDuration = d
        device.activeVideoMaxFrameDuration = d
        device.unlockForConfiguration()

        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if !captureSession.outputs.contains(where: { $0 === videoDataOutput }),
           captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        videoDataOutput.setSampleBufferDelegate(self, queue: captureQueue)

        captureSession.commitConfiguration()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let session = await self?.captureSession else { return }
            if !session.isRunning { session.startRunning() }
        }
    }

    func switchCamera() {
        guard recordingState == .idle else { return }
        let newPosition: AVCaptureDevice.Position = useFrontCamera ? .back : .front

        guard
            let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
            let newInput  = try? AVCaptureDeviceInput(device: newDevice),
            let oldInput  = captureSession.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) })
        else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let session = await self.captureSession
            session.beginConfiguration()
            session.removeInput(oldInput)
            if session.canAddInput(newInput) { session.addInput(newInput) }
            session.commitConfiguration()

            await MainActor.run { [weak self] in
                self?.videoDevice    = newDevice
                self?.useFrontCamera.toggle()
            }
        }
    }

    private func startWallClock() {
        clockCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.currentDate = date }
    }

    // MARK: - 물리 방향 감지 및 자동회전 잠금 우회
    private func startObservingPhysicalOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationCancellable = NotificationCenter.default
            .publisher(for: UIDevice.orientationDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handlePhysicalOrientationChange() }
    }

    private func handlePhysicalOrientationChange() {
        guard recordingState == .idle else { return }
        let o = UIDevice.current.orientation
        guard o == .portrait || o == .portraitUpsideDown || o.isLandscape else { return }
        lastMotionOrientation = o
        forceInterfaceRotation(matchingDevice: o)
    }

    private func forceInterfaceRotation(matchingDevice o: UIDeviceOrientation) {
        guard #available(iOS 16.0, *) else { return }
        let mask: UIInterfaceOrientationMask
        switch o {
        case .landscapeLeft:      mask = .landscapeRight
        case .landscapeRight:     mask = .landscapeLeft
        case .portraitUpsideDown: mask = .portraitUpsideDown
        default:                  mask = .portrait
        }
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func startMotionOrientationDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.recordingState == .idle,
                      let detected = self.physicalOrientation(from: data.acceleration),
                      detected != self.lastMotionOrientation else { return }
                self.lastMotionOrientation = detected
                self.forceInterfaceRotation(matchingDevice: detected)
            }
        }
    }

    private func stopMotionOrientationDetection() {
        motionManager.stopAccelerometerUpdates()
    }

    private func physicalOrientation(from a: CMAcceleration) -> UIDeviceOrientation? {
        let t = 0.65
        if abs(a.x) > abs(a.y) {
            if a.x >  t { return .landscapeRight }
            if a.x < -t { return .landscapeLeft }
        } else {
            if a.y < -t { return .portrait }
            if a.y >  t { return .portraitUpsideDown }
        }
        return nil
    }

    // MARK: - Recording Control (순정 사진 기반 최적화 기동)
    func startRecording() {
        UIApplication.shared.isIdleTimerDisabled = true
        selectedCategory = nil
        resetTimerState()
        lockOrientation()

        // 임시 이미지 저장 스토리지 초기 청소
        try? FileManager.default.removeItem(at: timelapseFolderURL)
        try? FileManager.default.createDirectory(at: timelapseFolderURL, withIntermediateDirectories: true)

        photoCount = 0
        recordingStartDate = Date()

        var session = RecordingSession(timerMode: timerMode,
                                       targetOutputDuration: targetOutputDuration,
                                       usedFrontCamera: useFrontCamera)
        currentSession = session
        try? currentSession?.saveJSON()

        recordingState = .recording
        startTimerTick()
        startLogTick()

        // 💡 [핵심] 1초에 한 번씩 하드웨어 스냅샷을 찍는 완벽한 저전력 사진 동기화 루프 작동
        photoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureCurrentFrameToDisk()
            }
        }
    }

    private func lockOrientation() {
        orientationCancellable?.cancel()
        stopMotionOrientationDetection()

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        let mask: UIInterfaceOrientationMask
        switch scene?.interfaceOrientation {
        case .landscapeLeft:      mask = .landscapeLeft
        case .landscapeRight:     mask = .landscapeRight
        case .portraitUpsideDown: mask = .portraitUpsideDown
        default:                  mask = .portrait
        }
        AppDelegate.orientationLock = mask
    }

    private func unlockOrientation() {
        AppDelegate.orientationLock = .all
        startObservingPhysicalOrientation()
        startMotionOrientationDetection()
        lastMotionOrientation = .unknown
        handlePhysicalOrientationChange()
    }

    func adjustCountdownTime(by seconds: TimeInterval) {
        guard recordingState == .paused, case .countdown = timerMode else { return }
        timerDisplayValue += seconds
        if timerDisplayValue > 0 { isGoalReached = false }
        // 조정 이벤트를 즉시 로그에 기록 (다음 1초 로그 틱을 기다리지 않음)
        guard var session = currentSession, let startDate = recordingStartDate else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        let entry = TimerLogEntry(
            videoTimestamp:          elapsed,
            realWorldDate:           Date(),
            displayValue:            timerDisplayValue,
            phase:                   .paused,
            adjustedCountdownDelta:  seconds,
            categoryName:            selectedCategory?.name,
            categoryColorHex:        selectedCategory?.colorHex
        )
        session.timerLogs.append(entry)
        currentSession = session
        timerSnapshot = TimerSnapshot(
            displayValue: timerDisplayValue,
            phase:        .paused,
            realWorldDate: entry.realWorldDate,
            isCountdown:  timerMode.goalDuration != nil
        )
    }

    func pauseTimer() {
        guard recordingState == .recording else { return }
        recordingState = .paused
        timerCancellable?.cancel()
    }

    func resumeTimer() {
        guard recordingState == .paused else { return }
        recordingState = .recording
        startTimerTick()
    }

    func stopRecording() {
        photoTimer?.invalidate()
        photoTimer = nil

        lastStopDisplayValue = timerDisplayValue  // 틱 취소 전에 종료 시점 값 캡처
        timerCancellable?.cancel()
        logCancellable?.cancel()
        
        recordingState = .processing
        isCompositing = true
        unlockOrientation()

        Task {
            do {
                if let session = currentSession {
                    // 비디오 빌더 호출 및 변환 마감 연동
                    let compositor = VideoCompositor.shared
                    _ = try await compositor.buildTimelapse(
                        fromFolder: timelapseFolderURL,
                        totalPhotos: photoCount,
                        targetDuration: targetOutputDuration,
                        subtitleLogs: session.timerLogs,
                        isCountdown: session.timerMode.goalDuration != nil,
                        isFront: session.usedFrontCamera
                    )
                    showSavedAlert = true
                }
            } catch {
                compositorError = error.localizedDescription
            }
            currentSession?.deleteJSON()
            isCompositing = false
            recordingState = .idle
            currentSession = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // 💡 [핵심] 현재 스냅샷 카메라 프레임을 초고속 파일로 격리 저장 (발열 및 부하 완전 해소)
    private func captureCurrentFrameToDisk() {
        guard let pixelBuffer = currentPixelBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        // 센서 네이티브 방향 = landscapeRight. 물리 방향에 따라 EXIF 태그로 기록해
        // VideoCompositor가 newPixelBuffer에서 올바른 변환을 적용할 수 있게 한다.
        let imageOrientation: UIImage.Orientation
        switch UIDevice.current.orientation {
        case .landscapeLeft:      imageOrientation = .down
        case .portrait:           imageOrientation = .right
        case .portraitUpsideDown: imageOrientation = .left
        default:                  imageOrientation = .up  // landscapeRight + unknown
        }

        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
            let fileURL = timelapseFolderURL.appendingPathComponent("\(photoCount).jpg")
            try? jpegData.write(to: fileURL, options: .atomic)
            photoCount += 1
        }
    }

    private func startTimerTick() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickTimer() }
    }

    private func tickTimer() {
        switch timerMode {
        case .stopwatch:
            timerDisplayValue += 0.1
        case .countdown:
            timerDisplayValue -= 0.1
            if timerDisplayValue <= 0 && !isGoalReached {
                isGoalReached = true
            }
        }
    }

    private func startLogTick() {
        logCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.appendLogEntry() }
    }

    private func appendLogEntry() {
        guard var session = currentSession,
              let startDate = recordingStartDate else { return }

        let realElapsed = Date().timeIntervalSince(startDate)

        let phase: TimerPhase
        switch recordingState {
        case .paused:
            phase = .paused
        default:
            if case .countdown = timerMode, timerDisplayValue < 0 {
                phase = .overrun
            } else if isGoalReached {
                phase = .goalReached
            } else {
                phase = .running
            }
        }

        let entry = TimerLogEntry(
            videoTimestamp:   realElapsed,
            realWorldDate:    Date(),
            displayValue:     timerDisplayValue,
            phase:            phase,
            categoryName:     selectedCategory?.name,
            categoryColorHex: selectedCategory?.colorHex
        )
        session.timerLogs.append(entry)
        currentSession = session

        timerSnapshot = TimerSnapshot(
            displayValue: timerDisplayValue,
            phase: phase,
            realWorldDate: entry.realWorldDate,
            isCountdown: timerMode.goalDuration != nil
        )

        logFlushCounter += 1
        if logFlushCounter % 10 == 0 {
            try? currentSession?.saveJSON()
        }
    }

    func applyStopwatchMode() {
        timerMode = .stopwatch
        resetTimerState()
    }

    func applyCountdownMode(goal: TimeInterval) {
        goalDuration = goal
        timerMode    = .countdown(goal: goal)
        resetTimerState()
    }

    private func resetTimerState() {
        isGoalReached = false
        switch timerMode {
        case .stopwatch:
            timerDisplayValue = 0
        case .countdown(let goal):
            timerDisplayValue = goal
        }
    }

    func prepareForNextRecording() {
        UIApplication.shared.isIdleTimerDisabled = false
        currentSession?.deleteJSON()
        currentSession  = nil
        showSavedAlert  = false
        compositorError = nil
        logFlushCounter = 0
        isGoalReached   = false
        // 종료 시점의 잔여 시간 + 2초를 다음 촬영 시작값으로 세팅.
        // 실제 촬영 시작(startRecording) 때는 goal로 다시 정확히 리셋된다.
        switch timerMode {
        case .stopwatch:
            timerDisplayValue = 0
        case .countdown:
            let newStart = (lastStopDisplayValue ?? timerDisplayValue) + 2
            goalDuration      = newStart
            timerMode         = .countdown(goal: newStart)
            timerDisplayValue = newStart
            lastStopDisplayValue = nil
        }
    }

    private func subscribeToLifecycleEvents() {
        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleWillResignActive() }
            .store(in: &lifecycleCancellables)

        NotificationCenter.default
            .publisher(for: UIApplication.willTerminateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleWillTerminate() }
            .store(in: &lifecycleCancellables)
    }

    private func handleWillResignActive() {
        if recordingState == .recording || recordingState == .paused {
            flushSessionLog()
        }
    }

    private func handleWillTerminate() {
        flushSessionLog()
    }

    private func flushSessionLog() {
        guard var session = currentSession else { return }
        session.endDate = Date()
        try? session.saveJSON()
        currentSession = session
    }

    private func checkForOrphanedSessions() {
        let orphans = RecordingSession.orphanedSessions()
        guard let first = orphans.first else { return }
        orphanedSession  = first.session
        orphanedVideoURL = first.videoURL
        showRecoveryAlert = true
    }

    func recoverOrphanedSession() {
        showRecoveryAlert = false
        orphanedSession   = nil
        orphanedVideoURL  = nil
    }

    func discardOrphanedSession() {
        if let url = orphanedVideoURL { try? FileManager.default.removeItem(at: url) }
        orphanedSession?.deleteJSON()
        orphanedSession   = nil
        orphanedVideoURL  = nil
        showRecoveryAlert = false
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let viewModel = self
            Task { @MainActor in
                viewModel.currentPixelBuffer = imageBuffer
            }
        }
    }
    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
}
