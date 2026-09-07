import SwiftUI

struct TimerSetupSheet: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: SheetMode = .stopwatch
    @State private var pickedHours:   Int = 0
    @State private var pickedMinutes: Int = 5
    @State private var pickedSeconds: Int = 0
    @State private var selectedOutputDuration: TimeInterval = 10

    enum SheetMode { case stopwatch, countdown }

    private static let outputOptions: [TimeInterval] = [10, 20, 30]

    private var pickedGoal: TimeInterval {
        TimeInterval(pickedHours * 3600 + pickedMinutes * 60 + pickedSeconds)
    }

    private var canApply: Bool {
        selectedMode == .stopwatch || pickedGoal > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    modePicker
                        .padding(.top, 4)

                    if selectedMode == .countdown {
                        durationPicker
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    outputDurationPicker
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .animation(.easeInOut(duration: 0.2), value: selectedMode)
            }
            .navigationTitle("타이머 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { applyAndDismiss() }
                        .disabled(!canApply)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents(selectedMode == .countdown ? [.large] : [.medium])
        .presentationDragIndicator(.visible)
        .onAppear { syncPickerFromViewModel() }
        .onChange(of: selectedMode) { mode in
            // detent는 presentationDetents에서 자동 조정됨
            _ = mode
        }
    }

    // MARK: - 모드 선택

    private var modePicker: some View {
        Picker("모드", selection: $selectedMode) {
            Label("타이머", systemImage: "timer")
                .tag(SheetMode.stopwatch)
            Label("카운트다운", systemImage: "timer.circle.fill")
                .tag(SheetMode.countdown)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 카운트다운 목표 시간

    private var durationPicker: some View {
        VStack(spacing: 8) {
            Text("목표 시간 설정")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                wheelColumn(range: 0..<24, selection: $pickedHours,   label: "시간")
                wheelColumn(range: 0..<60, selection: $pickedMinutes, label: "분")
                wheelColumn(range: 0..<60, selection: $pickedSeconds, label: "초")
            }
            .frame(height: 160)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

            Text(formattedGoal)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func wheelColumn(range: Range<Int>, selection: Binding<Int>, label: String) -> some View {
        VStack(spacing: 2) {
            Picker("", selection: selection) {
                ForEach(range, id: \.self) { v in
                    Text(String(format: "%02d", v)).tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }

    // MARK: - 최종 영상 길이

    private var outputDurationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("최종 영상 길이")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("영상 길이", selection: $selectedOutputDuration) {
                ForEach(Self.outputOptions, id: \.self) { sec in
                    Text("\(Int(sec))초").tag(sec)
                }
            }
            .pickerStyle(.segmented)

            Text("실제 촬영 시간을 선택한 길이로 자동 압축합니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 적용 및 닫기

    private func applyAndDismiss() {
        viewModel.targetOutputDuration = selectedOutputDuration
        switch selectedMode {
        case .stopwatch:
            viewModel.applyStopwatchMode()
        case .countdown:
            guard pickedGoal > 0 else { return }
            viewModel.applyCountdownMode(goal: pickedGoal)
        }
        dismiss()
    }

    // MARK: - 초기 동기화

    private func syncPickerFromViewModel() {
        selectedOutputDuration = viewModel.targetOutputDuration
        switch viewModel.timerMode {
        case .stopwatch:
            selectedMode = .stopwatch
        case .countdown(let goal):
            selectedMode  = .countdown
            pickedHours   = Int(goal) / 3600
            pickedMinutes = (Int(goal) % 3600) / 60
            pickedSeconds = Int(goal) % 60
        }
    }

    private var formattedGoal: String {
        guard pickedGoal > 0 else { return "목표 시간을 선택하세요" }
        var parts: [String] = []
        if pickedHours   > 0 { parts.append("\(pickedHours)시간") }
        if pickedMinutes > 0 { parts.append("\(pickedMinutes)분") }
        if pickedSeconds > 0 { parts.append("\(pickedSeconds)초") }
        return parts.joined(separator: " ")
    }
}
