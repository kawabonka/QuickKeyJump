import Foundation

// MARK: - Language Management

enum AppLanguage: String, CaseIterable {
    case zh, en

    var displayName: String { self == .zh ? "中文" : "English" }

    static var current: AppLanguage {
        get {
            AppLanguage(rawValue: UserDefaults.standard.string(forKey: "AppLanguage") ?? "zh") ?? .zh
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "AppLanguage")
        }
    }
}

/// Localization helper: returns Chinese or English string based on current language
func L(_ zh: String, _ en: String) -> String {
    AppLanguage.current == .zh ? zh : en
}
