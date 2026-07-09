import Foundation

// 타이머의 순간 상태를 기록하는 단위
// 녹화 중 매 초마다 생성되어 JSON으로 저장됨
struct TimerLogEntry: Codable, Identifiable {
    let id: UUID
    let videoTimestamp: TimeInterval   // 최종 영상 내 재생 위치 (초)
    let realWorldDate: Date            // 실제 촬영 시각 (절대값)
    let displayValue: TimeInterval     // 이 순간 화면에 표시 중인 타이머 값 (초)
    let phase: TimerPhase
    /// 일시정지 중 시간 조정 이벤트 기록 (초 단위 델타). 일반 로그는 0.
    let adjustedCountdownDelta: TimeInterval
    /// 이 순간 활성 카테고리 이름/색상. 선택 없으면 nil.
    let categoryName: String?
    let categoryColorHex: String?

    init(videoTimestamp: TimeInterval,
         realWorldDate: Date,
         displayValue: TimeInterval,
         phase: TimerPhase,
         adjustedCountdownDelta: TimeInterval = 0,
         categoryName: String? = nil,
         categoryColorHex: String? = nil) {
        self.id = UUID()
        self.videoTimestamp = videoTimestamp
        self.realWorldDate = realWorldDate
        self.displayValue = displayValue
        self.phase = phase
        self.adjustedCountdownDelta = adjustedCountdownDelta
        self.categoryName = categoryName
        self.categoryColorHex = categoryColorHex
    }
}

enum TimerPhase: String, Codable {
    case running      // 카운팅 중
    case paused       // 일시정지 (카메라는 녹화 중)
    case goalReached  // 카운트다운이 0에 도달한 시점
    case overrun      // 카운트다운 0 이후 초과 카운팅 중
}

extension TimerLogEntry {
    // 영상 합성 시 CATextLayer에 주입되는 표시 문자열
    var formattedTimerString: String {
        let isOverrun = displayValue < 0
        let abs = Swift.abs(displayValue)
        let h   = Int(abs) / 3600
        let m   = (Int(abs) % 3600) / 60
        let s   = Int(abs) % 60
        let prefix = isOverrun ? "+" : ""
        return h > 0
            ? String(format: "%@%d:%02d:%02d", prefix, h, m, s)
            : String(format: "%@%02d:%02d", prefix, m, s)
    }
}
