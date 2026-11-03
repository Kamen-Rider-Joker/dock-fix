import Foundation

/// UI language. Follows the system by default: Chinese when the first preferred
/// language is Chinese, English for everything else.
enum AppLanguage: String {
    case system, zh, en

    static let didChange = Notification.Name("AppLanguageDidChange")

    static var setting: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "language")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var systemIsChinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") ?? false }
    static var isChinese: Bool { setting == .zh || (setting == .system && systemIsChinese) }
    static var locale: Locale { Locale(identifier: isChinese ? "zh_CN" : "en_US") }
}

/// Picks the string for the current UI language.
func L(_ zh: String, _ en: String) -> String { AppLanguage.isChinese ? zh : en }
