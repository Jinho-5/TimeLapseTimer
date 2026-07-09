import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session:    AVCaptureSession
    let device:     AVCaptureDevice?  // RotationCoordinator에 필요
    let isMirrored: Bool

    func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        uiView.update(device: device, isMirrored: isMirrored)
    }
}

// MARK: -

final class VideoPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue; previewLayer.videoGravity = .resizeAspectFill }
    }

    private var isMirrored: Bool = false

    // iOS 17+: RotationCoordinator — 각도 계산 완전 자동화
    // AnyObject? 로 감싸야 @available 없이 stored property 선언 가능
    private var _rotationCoordinator: AnyObject?
    private var rotationObservation: NSKeyValueObservation?

    // iOS 16: 기기 방향 알림
    private var orientationObserver: NSObjectProtocol?
    private var legacySetupDone = false

    // MARK: - Public

    func update(device: AVCaptureDevice?, isMirrored: Bool) {
        self.isMirrored = isMirrored
        applyMirroring()

        if #available(iOS 17.0, *) {
            if let device { setupRotationCoordinator(device: device) }
        }
    }

    // MARK: - iOS 17+ RotationCoordinator

    @available(iOS 17.0, *)
    private func setupRotationCoordinator(device: AVCaptureDevice) {
        rotationObservation = nil   // 이전 KVO 해제

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device, previewLayer: previewLayer)
        _rotationCoordinator = coordinator

        applyAngle(coordinator.videoRotationAngleForHorizonLevelPreview)

        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] c, _ in
            DispatchQueue.main.async {
                self?.applyAngle(c.videoRotationAngleForHorizonLevelPreview)
            }
        }
    }

    @available(iOS 17.0, *)
    private func applyAngle(_ angle: CGFloat) {
        guard let conn = previewLayer.connection else { return }
        if conn.isVideoRotationAngleSupported(angle) {
            conn.videoRotationAngle = angle
        }
        applyMirroring()
    }

    // MARK: - iOS 16 알림 기반

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !legacySetupDone else { return }
        if #available(iOS 17.0, *) { return }   // RotationCoordinator가 처리
        setupLegacyTracking()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if #available(iOS 17.0, *) { return }
        updateOrientationLegacy()
    }

    private func setupLegacyTracking() {
        legacySetupDone = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateOrientationLegacy() }
        updateOrientationLegacy()
    }

    private func updateOrientationLegacy() {
        guard let conn = previewLayer.connection,
              conn.isVideoOrientationSupported else { return }
        applyMirroring()
        // UIDeviceOrientation과 AVCaptureVideoOrientation은 landscape 명칭이 반대
        switch UIDevice.current.orientation {
        case .landscapeLeft:      conn.videoOrientation = .landscapeRight
        case .landscapeRight:     conn.videoOrientation = .landscapeLeft
        case .portraitUpsideDown: conn.videoOrientation = .portraitUpsideDown
        case .portrait:           conn.videoOrientation = .portrait
        default: break
        }
    }

    // MARK: - 공통

    private func applyMirroring() {
        guard let conn = previewLayer.connection else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = isMirrored
    }

    deinit {
        if let obs = orientationObserver {
            NotificationCenter.default.removeObserver(obs)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }
}
