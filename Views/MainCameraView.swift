import SwiftUI
import AVFoundation

struct MainCameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showPermissionAlert = false
    @State private var showCategoryManagement = false

    @ObservedObject private var categoryStore: CategoryStore = .shared

    @Environment(\.verticalSizeClass)   private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isWide: Bool      { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            if isWide {
                wideLayout
            } else {
                narrowLayout
            }

            if viewModel.isCompositing {
                compositingOverlay
            }
        }
        .statusBarHidden(true)
        .task { await requestPermissions() }
        // 저장 완료
        .alert("저장 완료!", isPresented: $viewModel.showSavedAlert) {
            Button("확인") { viewModel.prepareForNextRecording() }
        } message: {
            Text("영상이 사진 앱에 저장되었습니다.")
        }
        // 저장 실패
        .alert("저장 실패", isPresented: Binding(
            get:  { viewModel.compositorError != nil },
            set:  { if !$0 { viewModel.compositorError = nil } }
        )) {
            Button("확인") { viewModel.prepareForNextRecording() }
        } message: {
            Text(viewModel.compositorError ?? "알 수 없는 오류가 발생했습니다.")
        }
        .sheet(isPresented: $showCategoryManagement) {
            CategoryManagementSheet()
        }
        .alert("카메라 권한 필요", isPresented: $showPermissionAlert) {
            Button("설정 열기") { openAppSettings() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("타임랩스를 녹화하려면 카메라 접근 권한이 필요합니다.")
        }
        // 크래시 복구
        .alert("미완료 녹화 발견", isPresented: $viewModel.showRecoveryAlert) {
            Button("복구하기") { viewModel.recoverOrphanedSession() }
            Button("삭제", role: .destructive) { viewModel.discardOrphanedSession() }
        } message: {
            let dateStr = viewModel.orphanedSession.map {
                let f = DateFormatter()
                f.dateStyle = .short; f.timeStyle = .short
                return f.string(from: $0.startDate)
            } ?? ""
            Text("이전 세션(\(dateStr))의 영상이 복구 가능합니다. 사진 앱에 저장하시겠습니까?")
        }
    }

    // MARK: - 아이폰(세로/가로) 레이아웃 — 카메라 전체화면 오버레이

    private var narrowLayout: some View {
        ZStack {
            CameraPreviewView(session: viewModel.captureSession,
                              device: viewModel.videoDevice,
                              isMirrored: viewModel.useFrontCamera)
                .ignoresSafeArea()

            TimerOverlayView(
                currentDate:          viewModel.currentDate,
                timerMode:            viewModel.timerMode,
                displayValue:         viewModel.timerDisplayValue,
                isGoalReached:        viewModel.isGoalReached,
                recordingState:       viewModel.recordingState,
                targetOutputDuration: viewModel.targetOutputDuration,
                onAdjustTime:         { viewModel.adjustCountdownTime(by: $0) }
            )
            .ignoresSafeArea()

            if isLandscape {
                // 가로 모드: 컨트롤은 우측, 카테고리는 Safe Area leading 밀착 + 상단 시계 아래 고정
                ZStack {
                    RecordingControlsView(viewModel: viewModel)

                    VStack(spacing: 0) {
                        // 상단 시계 영역(y≈0~34pt) + 여유분 → 카테고리는 시계 아래에서 시작
                        Spacer().frame(height: 64)
                        // HStack + trailing Spacer() 로 카테고리를 leading에 고정
                        HStack(alignment: .top, spacing: 0) {
                            if viewModel.recordingState == .idle {
                                categoryEditButton
                            } else if viewModel.recordingState != .processing {
                                categoryPickerColumn
                            }
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, -10) // 카테고리를 Safe Area 안쪽으로 더 당겨 좌측 밀착
                }
            } else {
                // 세로 모드: 컨트롤 바로 위에 카테고리 행
                VStack(spacing: 0) {
                    Spacer()
                    if viewModel.recordingState == .idle {
                        categoryEditButton
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 8)
                    } else if viewModel.recordingState != .processing {
                        categoryPickerRow
                            .padding(.bottom, 8)
                    }
                    RecordingControlsView(viewModel: viewModel)
                }
            }
        }
    }

    private var categoryEditButton: some View {
        Button { showCategoryManagement = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("카테고리")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(radius: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 카테고리 칩

    /// 세로 모드: 가로 스크롤 행
    private var categoryPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categoryStore.categories) { cat in
                    categoryChip(cat)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// 가로 모드: 좌측 수직 목록
    /// - 너비 130pt 제한: 화면 중앙 타이머(가로 중앙 ≈ 300pt+)와 충분한 간격 확보
    /// - 높이 제한 없음: 칩 전체가 잘림 없이 표시되도록 자연 높이 사용
    private var categoryPickerColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(categoryStore.categories) { cat in
                categoryChip(cat)
            }
        }
        .frame(maxWidth: 130, alignment: .leading)
    }

    /// Wide(iPad) 모드: 패널 하단 수직 목록
    private var categoryPickerWide: some View {
        VStack(spacing: 8) {
            ForEach(categoryStore.categories) { cat in
                categoryChip(cat)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    private func categoryChip(_ cat: TimerCategory) -> some View {
        let isSelected = viewModel.selectedCategory?.id == cat.id
        return Button {
            viewModel.selectedCategory = isSelected ? nil : cat
        } label: {
            Text(cat.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : cat.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(cat.color)
                    } else {
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().strokeBorder(cat.color, lineWidth: 1.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - 와이드 레이아웃 — Mac / iPad (Regular Width) 투-칼럼

    private var wideLayout: some View {
        HStack(spacing: 0) {
            // 왼쪽: 카메라 프리뷰 + 타이머 오버레이
            ZStack {
                CameraPreviewView(session: viewModel.captureSession,
                                  device: viewModel.videoDevice,
                                  isMirrored: viewModel.useFrontCamera)

                TimerOverlayView(
                    currentDate:          viewModel.currentDate,
                    timerMode:            viewModel.timerMode,
                    displayValue:         viewModel.timerDisplayValue,
                    isGoalReached:        viewModel.isGoalReached,
                    recordingState:       viewModel.recordingState,
                    targetOutputDuration: viewModel.targetOutputDuration,
                    onAdjustTime:         { viewModel.adjustCountdownTime(by: $0) }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // 구분선
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)

            // 오른쪽: 제어 버튼 패널
            RecordingControlsView(viewModel: viewModel)
                .frame(width: 280)
                .frame(maxHeight: .infinity)
                .background(Color.black)
                .overlay(alignment: .topTrailing) {
                    if viewModel.recordingState == .idle {
                        categoryEditButton
                            .padding(.top, 20)
                            .padding(.trailing, 14)
                    }
                }
                .overlay(alignment: .bottom) {
                    if viewModel.recordingState != .idle && viewModel.recordingState != .processing {
                        categoryPickerWide
                            .padding(.bottom, 36)
                    }
                }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    // MARK: - 합성 중 오버레이

    private var compositingOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.8)
                    .tint(.white)
                Text("저장 중...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - 권한

    private func requestPermissions() async {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { showPermissionAlert = true }
        case .denied, .restricted:
            showPermissionAlert = true
        default:
            break
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    MainCameraView()
}
