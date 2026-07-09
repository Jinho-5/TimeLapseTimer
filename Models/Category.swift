import Foundation
import SwiftUI

struct TimerCategory: Codable, Identifiable {
    let id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color { Color(hex: colorHex) ?? .orange }
}

// MARK: - Store

final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()

    @Published var categories: [TimerCategory] = []

    private let storageKey = "com.timelapse.categories.v1"

    private static let defaults: [TimerCategory] = [
        TimerCategory(name: "공부",  colorHex: "#FF9500"),
        TimerCategory(name: "독서",  colorHex: "#34C759"),
        TimerCategory(name: "휴식",  colorHex: "#5856D6"),
    ]

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cats  = try? JSONDecoder().decode([TimerCategory].self, from: data)
        else {
            categories = Self.defaults
            persist()
            return
        }
        categories = cats
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func add(_ category: TimerCategory) {
        categories.append(category)
        persist()
    }

    func update(_ category: TimerCategory) {
        guard let idx = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[idx] = category
        persist()
    }

    func delete(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
        persist()
    }
}

// MARK: - Color ↔ Hex

extension UIColor {
    convenience init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&rgb) else { return nil }
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >>  8) / 255.0
        let b = CGFloat( rgb & 0x0000FF        ) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

extension Color {
    init?(hex: String) {
        guard let ui = UIColor(hex: hex) else { return nil }
        self.init(ui)
    }

    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
