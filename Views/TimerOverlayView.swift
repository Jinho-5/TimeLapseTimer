import SwiftUI

struct TimerOverlayView: View {
    let currentDate: Date
    let timerMode: TimerMode
    let displayValue: TimeInterval
    let isGoalReached: Bool
    let recordingState: RecordingState
    let targetOutputDuration: TimeInterval

    /// 카운트다운 일시정지 중 시간 조정 콜백 — 양수: 추가, 음수: 차감 (초 단위). nil이면 버튼 미표시.
    var onAdjustTime: ((TimeInterval) -> Void)? = nil

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            // ── 상단: 날짜/시각(좌) + Auto배지(우) ──
            VStack {
                HStack(alignment: .top) {
                    dateSection
                    Spacer()
                    autoBadge
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, isLandscape ? 10 : 16)

            // ── 중앙: 타이머 ──
            timerSection
                .offset(y: isLandscape ? 0 : -50)
        }
    }

    // MARK: - 날짜/시각

    private var dateSection: some View {
        Group {
            if isLandscape {
                HStack(spacing: 8) {
                    Text(currentDate, format: .dateTime.year().month().day())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(currentDate, format: .dateTime.hour().minute().second())
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentDate, format: .dateTime.year().month(.wide).day())
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(currentDate, format: .dateTime.hour().minute().second())
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
        }
        .textShadow()
    }

    // MARK: - 타이머

    private var timerSection: some View {
        VStack(spacing: 6) {
            Text(modeLabelText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .textCase(.uppercase)
                .tracking(1.5)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(formattedTimerValue)
                    .font(.system(size: timerFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerForegroundColor)
                    .shadow(color: timerGlowColor, radius: isGoalReached ? 18 : 0)
                    .contentTransition(.numericText())

                if isGoalReached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: timerFontSize * 0.36))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isGoalReached)

            if recordingState == .paused {
                pauseBadge
                    .transition(.opacity.combined(with: .scale))

                // 카운트다운 모드에서만 시간 조정 버튼 표시
                if case .countdown = timerMode, let onAdjust = onAdjustTime {
                    timeAdjustButtons(onAdjust: onAdjust)
                        .transition(.opacity.combined(with: .scale))
                        .padding(.top, 4)
                }
            }
        }
        .textShadow()
        .animation(.easeInOut(duration: 0.2), value: recordingState == .paused)
    }

    // MARK: - 일시정지 배지

    private var pauseBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "pause.circle.fill")
            Text("일시정지")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.yellow)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.black.opacity(0.35), in: Capsule())
    }

    // MARK: - 시간 조정 버튼 (분 + 초)

    private func timeAdjustButtons(onAdjust: @escaping (TimeInterval) -> Void) -> some View {
        VStack(spacing: 8) {
            // 분 단위 (크게)
            HStack(spacing: 12) {
                timeAdjustButton(label: "−1분", delta: -60, isMinute: true,  onAdjust: onAdjust)
                timeAdjustButton(label: "+1분", delta:  60, isMinute: true,  onAdjust: onAdjust)
            }
            // 초 단위 (작게)
            HStack(spacing: 12) {
                timeAdjustButton(label: "−1초", delta:  -1, isMinute: false, onAdjust: onAdjust)
                timeAdjustButton(label: "+1초", delta:   1, isMinute: false, onAdjust: onAdjust)
            }
        }
    }

    private func timeAdjustButton(label: String, delta: TimeInterval, isMinute: Bool,
                                   onAdjust: @escaping (TimeInterval) -> Void) -> some View {
        Button { onAdjust(delta) } label: {
            Text(label)
                .font(.system(size: isMinute ? 15 : 13,
                              weight: isMinute ? .semibold : .medium,
                              design: .monospaced))
                .foregroundStyle(isMinute ? .white : .white.opacity(0.8))
                .padding(.horizontal, isMinute ? 18 : 14)
                .padding(.vertical,   isMinute ?  9 :  7)
                .background(.black.opacity(isMinute ? 0.45 : 0.30), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(isMinute ? 0.35 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed

    private var autoBadge: some View {
        Text("Auto\(Int(targetOutputDuration))")
            .font(.system(size: isLandscape ? 11 : 13, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.30), in: Capsule())
            .textShadow()
    }

    private var timerFontSize: CGFloat { isLandscape ? 56 : 76 }

    private var timerForegroundColor: Color {
        guard case .countdown = timerMode else { return .white }
        if isGoalReached { return displayValue < 0 ? .orange : .green }
        if let goal = timerMode.goalDuration, goal > 0, displayValue / goal < 0.1 {
            return .red
        }
        return .white
    }

    private var timerGlowColor: Color { timerForegroundColor.opacity(0.65) }

    private var modeLabelText: String {
        switch timerMode {
        case .stopwatch: return "타이머"
        case .countdown:
            if isGoalReached { return displayValue < 0 ? "초과 중" : "목표 달성" }
            return "카운트다운"
        }
    }

    private var formattedTimerValue: String {
        let isOverrun: Bool
        if case .countdown = timerMode, displayValue < 0 { isOverrun = true }
        else { isOverrun = false }

        let abs = Swift.abs(displayValue)
        let h = Int(abs) / 3600
        let m = (Int(abs) % 3600) / 60
        let s = Int(abs) % 60
        let prefix = isOverrun ? "+" : ""

        return h > 0
            ? String(format: "%@%d:%02d:%02d", prefix, h, m, s)
            : String(format: "%@%02d:%02d", prefix, m, s)
    }
}

// MARK: - View Modifier

private extension View {
    func textShadow() -> some View {
        shadow(color: .black.opacity(0.8), radius: 4, x: 1, y: 1)
    }
}

// MARK: - Preview

#Preview("일시정지 + 카운트다운") {
    ZStack {
        Color.black.ignoresSafeArea()
        TimerOverlayView(
            currentDate: Date(),
            timerMode: .countdown(goal: 300),
            displayValue: 142,
            isGoalReached: false,
            recordingState: .paused,
            targetOutputDuration: 20,
            onAdjustTime: { _ in }
        )
    }
}

#Preview("녹화 중 스톱워치") {
    ZStack {
        Color.black.ignoresSafeArea()
        TimerOverlayView(
            currentDate: Date(),
            timerMode: .stopwatch,
            displayValue: 67,
            isGoalReached: false,
            recordingState: .recording,
            targetOutputDuration: 30
        )
    }
}
