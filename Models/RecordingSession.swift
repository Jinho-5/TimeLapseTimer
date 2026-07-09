import Foundation

enum TimerMode: Equatable {
    case stopwatch
    case countdown(goal: TimeInterval)

    var goalDuration: TimeInterval? {
        if case .countdown(let goal) = self { return goal }
        return nil
    }
}

extension TimerMode: Codable {
    private enum Key: String, CodingKey { case type, goal }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        if type == "countdown" {
            let goal = try c.decode(TimeInterval.self, forKey: .goal)
            self = .countdown(goal: goal)
        } else {
            self = .stopwatch
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .stopwatch:
            try c.encode("stopwatch", forKey: .type)
        case .countdown(let goal):
            try c.encode("countdown", forKey: .type)
            try c.encode(goal, forKey: .goal)
        }
    }
}

struct RecordingSession: Identifiable {
    let id: UUID
    let startDate: Date
    var endDate: Date?

    let timerMode: TimerMode
    let targetOutputDuration: TimeInterval
    var usedFrontCamera: Bool

    var timerLogs: [TimerLogEntry]
    var videoFileName: String?

    init(timerMode: TimerMode,
         targetOutputDuration: TimeInterval = 20,
         usedFrontCamera: Bool = false) {
        self.id                   = UUID()
        self.startDate            = Date()
        self.endDate              = nil
        self.timerMode            = timerMode
        self.targetOutputDuration = targetOutputDuration
        self.usedFrontCamera      = usedFrontCamera
        self.timerLogs            = []
    }

    var recordingDuration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }

    func computedSpeed(rawVideoDuration: TimeInterval) -> Double {
        rawVideoDuration / targetOutputDuration
    }

    var autoLabel: String { "Auto\(Int(targetOutputDuration))" }

    var videoFileURL: URL? {
        guard let name = videoFileName else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    // MARK: - 디스크 직렬화

    var jsonURL: URL { RecordingSession.makeJSONURL(for: id) }

    func saveJSON() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: jsonURL, options: .atomic)
    }

    func deleteJSON() {
        try? FileManager.default.removeItem(at: jsonURL)
    }

    static func load(id: UUID) throws -> RecordingSession {
        let data = try Data(contentsOf: makeJSONURL(for: id))
        return try JSONDecoder().decode(RecordingSession.self, from: data)
    }

    // MARK: - 크래시 복구: 미완료 세션 탐지

    /// 앱 비정상 종료 후 남아있는 로그 JSON + 임시 영상 파일을 반환 (최신 순)
    static func orphanedSessions() -> [(session: RecordingSession, videoURL: URL?)] {
        let tmp = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil
        ) else { return [] }

        return contents
            .filter { $0.lastPathComponent.hasSuffix("-log.json") }
            .compactMap { jsonFile in
                guard let data    = try? Data(contentsOf: jsonFile),
                      let session = try? JSONDecoder().decode(RecordingSession.self, from: data)
                else { return nil }
                let videoURL: URL? = session.videoFileName.flatMap { name in
                    let url = tmp.appendingPathComponent(name)
                    return FileManager.default.fileExists(atPath: url.path) ? url : nil
                }
                return (session, videoURL)
            }
            .sorted { $0.session.startDate > $1.session.startDate }
    }

    static func makeJSONURL(for id: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(id.uuidString)-log.json")
    }
}

// MARK: - Codable (usedFrontCamera에 기본값 적용을 위해 직접 구현)

extension RecordingSession: Codable {
    private enum CK: String, CodingKey {
        case id, startDate, endDate, timerMode, targetOutputDuration
        case usedFrontCamera, timerLogs, videoFileName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        id                   = try c.decode(UUID.self,            forKey: .id)
        startDate            = try c.decode(Date.self,            forKey: .startDate)
        endDate              = try c.decodeIfPresent(Date.self,   forKey: .endDate)
        timerMode            = try c.decode(TimerMode.self,       forKey: .timerMode)
        targetOutputDuration = try c.decode(TimeInterval.self,    forKey: .targetOutputDuration)
        usedFrontCamera      = (try? c.decode(Bool.self,          forKey: .usedFrontCamera)) ?? false
        timerLogs            = try c.decode([TimerLogEntry].self, forKey: .timerLogs)
        videoFileName        = try c.decodeIfPresent(String.self, forKey: .videoFileName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        try c.encode(id,                     forKey: .id)
        try c.encode(startDate,              forKey: .startDate)
        try c.encodeIfPresent(endDate,       forKey: .endDate)
        try c.encode(timerMode,              forKey: .timerMode)
        try c.encode(targetOutputDuration,   forKey: .targetOutputDuration)
        try c.encode(usedFrontCamera,        forKey: .usedFrontCamera)
        try c.encode(timerLogs,              forKey: .timerLogs)
        try c.encodeIfPresent(videoFileName, forKey: .videoFileName)
    }
}
