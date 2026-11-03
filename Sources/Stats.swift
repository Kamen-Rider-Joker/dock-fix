import Foundation

/// Fix counters kept in UserDefaults and shown in the menu bar.
final class FixStats {
    static let shared = FixStats()
    static let didChange = Notification.Name("FixStatsDidChange")

    private let defaults = UserDefaults.standard

    var total: Int { defaults.integer(forKey: "stats.total") }
    var failed: Int { defaults.integer(forKey: "stats.failed") }
    var lastFix: Date? { defaults.object(forKey: "stats.lastFix") as? Date }
    var today: Int {
        defaults.string(forKey: "stats.day") == Self.dayKey(Date()) ? defaults.integer(forKey: "stats.today") : 0
    }

    func record(fixed: Bool) {
        if fixed {
            defaults.set(today + 1, forKey: "stats.today")
            defaults.set(Self.dayKey(Date()), forKey: "stats.day")
            defaults.set(total + 1, forKey: "stats.total")
            defaults.set(Date(), forKey: "stats.lastFix")
        } else {
            defaults.set(failed + 1, forKey: "stats.failed")
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func reset() {
        for key in ["stats.total", "stats.failed", "stats.lastFix", "stats.today", "stats.day"] {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
}
