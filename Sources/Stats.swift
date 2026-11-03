import Foundation

struct FixHistoryDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

/// Fix counters kept in UserDefaults and shown in the menu bar.
final class FixStats {
    static let shared = FixStats()
    static let didChange = Notification.Name("FixStatsDidChange")

    private let defaults = UserDefaults.standard
    private let historyKey = "stats.history"

    var total: Int { defaults.integer(forKey: "stats.total") }
    var failed: Int { defaults.integer(forKey: "stats.failed") }
    var lastFix: Date? { defaults.object(forKey: "stats.lastFix") as? Date }
    var today: Int {
        defaults.string(forKey: "stats.day") == Self.dayKey(Date()) ? defaults.integer(forKey: "stats.today") : 0
    }

    var recentHistory: [FixHistoryDay] {
        let calendar = Calendar.current
        let todayKey = Self.dayKey(Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date())) else {
                return nil
            }
            let key = Self.dayKey(date)
            let stored = history[key] ?? 0
            return FixHistoryDay(date: date, count: key == todayKey ? max(stored, today) : stored)
        }
    }

    func record(fixed: Bool) {
        if fixed {
            let currentDay = Self.dayKey(Date())
            var days = history
            days[currentDay] = max(days[currentDay] ?? 0, today) + 1
            defaults.set(days, forKey: historyKey)
            defaults.set(today + 1, forKey: "stats.today")
            defaults.set(currentDay, forKey: "stats.day")
            defaults.set(total + 1, forKey: "stats.total")
            defaults.set(Date(), forKey: "stats.lastFix")
        } else {
            defaults.set(failed + 1, forKey: "stats.failed")
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func reset() {
        for key in ["stats.total", "stats.failed", "stats.lastFix", "stats.today", "stats.day", historyKey] {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private var history: [String: Int] {
        (defaults.dictionary(forKey: historyKey) ?? [:]).reduce(into: [:]) { result, entry in
            if let count = entry.value as? Int { result[entry.key] = count }
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
}
