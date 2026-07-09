import SwiftUI

struct RecordingControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @State private var showTimerSetup = false

    @Environment(\.verticalSizeClass)   private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isWide: Bool      { horizontalSizeClass == .regular && !isLandscape }

    var body: some View {
        Group {
            if isLandscape {
                landscapeLayout
            } else if isWide {
                wideLayout
            } else {
                portraitLayout
            }
        }
        .sheet(isPresented: $showTimerSetup) {
            TimerSetupSheet(viewModel: viewModel)
        }
    }

    // MARK: - 세로 레이아웃

    private var portraitLayout: some View {
        HStack(alignment: .center, spacing: 0) {
            timerModeButton(size: 26)
                .frame(maxWidth: .infinity)

            recordButton(size: 76)
                .frame(maxWidth: .infinity)

            // 일시정지(녹화 중) / 카메라 전환+갤러리(대기 중) — 같은 자리에 조건부 표시
            ZStack {
                pauseButton(size: 46)
                HStack(spacing: 14) {
                    cameraFlipButton(size: 24)
                    galleryButton(size: 24)
                }
                .opacity(viewModel.recordingState == .idle ? 1 : 0)
                .disabled(viewModel.recordingState != .idle)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
    }

    // MARK: - 가로 레이아웃

    private var landscapeLayout: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                timerModeButton(size: 22)
                recordButton(size: 58)

                ZStack {
                    pauseButton(size: 36)
                    VStack(spacing: 10) {
                        cameraFlipButton(size: 22)
                        galleryButton(size: 22)
                    }
                    .opacity(viewModel.recordingState == .idle ? 1 : 0)
                    .disabled(viewModel.recordingState != .idle)
                }
            }
            .padding(.vertical, 16)
            .padding(.trailing, 20)
        }
    }

    // MARK: - Mac / iPad 투-칼럼 오른쪽 패널 레이아웃

    private var wideLayout: some View {
        VStack(spacing: 0) {
            Spacer()

            timerModeButton(size: 26)

            Spacer().frame(height: 36)

            recordButton(size: 76)

            Spacer().frame(height: 36)

            ZStack {
                pauseButton(size: 46)
                HStack(spacing: 14) {
                    cameraFlipButton(size: 24)
                    galleryButton(size: 24)
                }
                .opacity(viewModel.recordingState == .idle ? 1 : 0)
                .disabled(viewModel.recordingState != .idle)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 녹화 버튼

    private func recordButton(size: CGFloat) -> some View {
        let innerSize   = size * 0.82
        let squareSize  = size * 0.42

        return Button {
            switch viewModel.recordingState {
            case .idle:               viewModel.startRecording()
            case .recording, .paused: viewModel.stopRecording()
            case .processing:         break
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: size, height: size)

                if viewModel.recordingState == .idle {
                    Circle()
                        .fill(.red)
                        .frame(width: innerSize, height: innerSize)
                } else {
                    RoundedRectangle(cornerRadius: squareSize * 0.3, style: .continuous)
                        .fill(.red)
                        .frame(width: squareSize, height: squareSize)
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.recordingState == .idle)
        .buttonStyle(.plain)
    }

    // MARK: - 일시정지 버튼

    private func pauseButton(size: CGFloat) -> some View {
        let isActive = viewModel.recordingState == .recording || viewModel.recordingState == .paused
        let isPaused = viewModel.recordingState == .paused

        return Button {
            if viewModel.recordingState == .recording { viewModel.pauseTimer() }
            else if viewModel.recordingState == .paused { viewModel.resumeTimer() }
        } label: {
            Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(isPaused ? .yellow : .white)
                .shadow(radius: 4)
        }
        .opacity(isActive ? 1 : 0)
        .disabled(!isActive)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .buttonStyle(.plain)
    }

    // MARK: - 카메라 전환 버튼 (전면/후면, idle 상태에서만 활성)

    private func cameraFlipButton(size: CGFloat) -> some View {
        Button {
            viewModel.switchCamera()
        } label: {
            Image(systemName: "camera.rotate.fill")
                .font(.system(size: size))
                .foregroundStyle(.white)
                .shadow(radius: 4)
        }
        .disabled(viewModel.recordingState != .idle)
        .buttonStyle(.plain)
    }

    // MARK: - 갤러리(보관함) 버튼 (idle 상태에서만 활성)

    private func galleryButton(size: CGFloat) -> some View {
        Button {
            if let url = URL(string: "photos-redirect://") {
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: size))
                .foregroundStyle(.white)
                .shadow(radius: 4)
        }
        .disabled(viewModel.recordingState != .idle)
        .buttonStyle(.plain)
    }

    // MARK: - 타이머 모드 버튼

    private func timerModeButton(size: CGFloat) -> some View {
        Button { showTimerSetup = true } label: {
            VStack(spacing: 4) {
                Image(systemName: timerModeIcon)
                    .font(.system(size: size))
                    .foregroundStyle(.white)
                if !isLandscape {
                    Text(timerModeShortLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.recordingState != .idle)
        .opacity(viewModel.recordingState != .idle ? 0.4 : 1)
    }

    // MARK: - Computed

    private var timerModeIcon: String {
        switch viewModel.timerMode {
        case .stopwatch: return "timer"
        case .countdown: return "timer.circle.fill"
        }
    }

    private var timerModeShortLabel: String {
        switch viewModel.timerMode {
        case .stopwatch: return "타이머"
        case .countdown(let goal):
            let m = Int(goal) / 60, s = Int(goal) % 60
            return s == 0 ? "\(m)분" : "\(m)분 \(s)초"
        }
    }
}
