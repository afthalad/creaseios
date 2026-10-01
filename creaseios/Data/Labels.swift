import SwiftUI
import CreaseEngine

private extension String {
    var upperFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension MatchFormat {
    var label: LocalizedStringKey {
        switch self {
        case .t20: "formatT20"
        case .t10: "formatT10"
        case .odi: "formatOdi"
        case .custom: "formatCustom"
        case .softball: "formatSoftball"
        case .tapeBall: "formatTapeBall"
        case .sixes: "formatSixes"
        }
    }
}

extension PlayerRole {
    var key: String {
        switch self {
        case .batter: "roleBatter"
        case .bowler: "roleBowler"
        case .allRounder: "roleAllRounder"
        case .wicketKeeper: "roleWicketKeeper"
        }
    }
    var label: LocalizedStringKey { LocalizedStringKey(key) }
}

extension Gender {
    var key: String { self == .male ? "genderMale" : "genderFemale" }
    var label: LocalizedStringKey { LocalizedStringKey(key) }
}

extension BattingStyle {
    var key: String { self == .rhb ? "battingRhb" : "battingLhb" }
    var label: LocalizedStringKey { LocalizedStringKey(key) }
}

extension BowlingStyle {
    var key: String { "bowling" + rawValue.upperFirst }
    var label: LocalizedStringKey { LocalizedStringKey(key) }
}

extension DismissalType {
    var label: LocalizedStringKey { LocalizedStringKey("dismissal" + rawValue.upperFirst) }
}

extension ExtraType {
    var label: LocalizedStringKey { LocalizedStringKey("extra" + rawValue.upperFirst) }
}

extension TossDecision {
    var label: LocalizedStringKey { self == .bat ? "bat" : "bowl" }
}

/// Looks a key up in the language picked in-app rather than the system language.
func localized(_ key: String, _ locale: Locale) -> String {
    let code = locale.language.languageCode?.identifier ?? "en"
    let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}

extension PlayerProfile {
    /// "Male · Batter · Right-hand bat · Right-arm fast"
    func summary(_ locale: Locale, includeGender: Bool = false) -> String {
        var parts = [role.key, battingStyle.key]
        if includeGender { parts.insert(gender.key, at: 0) }
        if bowlingStyle != .none { parts.append(bowlingStyle.key) }
        return parts.map { localized($0, locale) }.joined(separator: " · ")
    }
}
