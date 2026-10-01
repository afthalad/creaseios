import SwiftUI

@MainActor @Observable
final class SettingsStore {
    enum Theme: String, CaseIterable {
        case system, light, dark

        var label: LocalizedStringKey {
            switch self {
            case .system: "themeSystem"
            case .light: "themeLight"
            case .dark: "themeDark"
            }
        }
    }

    private let defaults = UserDefaults.standard

    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "themeMode") } }
    var languageCode: String? { didSet { defaults.set(languageCode, forKey: "languageCode") } }
    var onboardingSeen: Bool { didSet { defaults.set(onboardingSeen, forKey: "onboardingSeen") } }

    init() {
        theme = Theme(rawValue: defaults.string(forKey: "themeMode") ?? "") ?? .system
        languageCode = defaults.string(forKey: "languageCode")
        onboardingSeen = defaults.bool(forKey: "onboardingSeen")
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var locale: Locale { languageCode.map(Locale.init(identifier:)) ?? .current }

    var languageName: String {
        let code = languageCode ?? Locale.current.language.languageCode?.identifier ?? "en"
        return appLanguages.first { $0.code == code }?.name ?? "English"
    }
}

let appLanguages: [(code: String, name: String)] = [("en", "English"), ("si", "සිංහල"), ("ta", "தமிழ்")]
