import Foundation

public enum ISODate {
    nonisolated(unsafe) private static let withZone: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let withZoneNoFraction = ISO8601DateFormatter()
    nonisolated(unsafe) private static let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()
    nonisolated(unsafe) private static let localNoFraction: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Dart writes either `2026-09-30T10:15:00.000` (local) or `...Z` (UTC).
    public static func parse(_ s: String) -> Date? {
        withZone.date(from: s)
            ?? withZoneNoFraction.date(from: s)
            ?? local.date(from: String(s.prefix(23)))
            ?? localNoFraction.date(from: String(s.prefix(19)))
    }

    public static func string(_ d: Date) -> String { withZone.string(from: d) }
}

public enum ExtraType: String, Codable, Sendable, CaseIterable { case wide, noBall, bye, legBye }

public enum DismissalType: String, Codable, Sendable, CaseIterable {
    case bowled, caught, lbw, runOut, stumped, hitWicket, retiredOut, obstructing

    public var creditsBowler: Bool { [.bowled, .caught, .lbw, .stumped, .hitWicket].contains(self) }
    public var needsFielder: Bool { [.caught, .stumped, .runOut].contains(self) }
}

public struct Dismissal: Codable, Hashable, Sendable {
    public var type: DismissalType
    public var bowlerId: String?
    public var fielderId: String?

    public init(type: DismissalType, bowlerId: String? = nil, fielderId: String? = nil) {
        self.type = type
        self.bowlerId = bowlerId
        self.fielderId = fielderId
    }
}

public struct BallEvent: Hashable, Sendable {
    public var strikerId: String
    public var nonStrikerId: String
    public var bowlerId: String
    public var runsOffBat = 0
    public var extra: ExtraType?
    public var extraRuns = 0
    public var dismissal: Dismissal?
    public var dismissedPlayerId: String?
    public var incomingBatterId: String?

    public init(strikerId: String, nonStrikerId: String, bowlerId: String, runsOffBat: Int = 0,
                extra: ExtraType? = nil, extraRuns: Int = 0, dismissal: Dismissal? = nil,
                dismissedPlayerId: String? = nil, incomingBatterId: String? = nil) {
        self.strikerId = strikerId
        self.nonStrikerId = nonStrikerId
        self.bowlerId = bowlerId
        self.runsOffBat = runsOffBat
        self.extra = extra
        self.extraRuns = extraRuns
        self.dismissal = dismissal
        self.dismissedPlayerId = dismissedPlayerId
        self.incomingBatterId = incomingBatterId
    }

    public var isLegal: Bool { extra != .wide && extra != .noBall }
    public var battingTeamRuns: Int { runsOffBat + extraRuns + (isLegal ? 0 : 1) }

    public var bowlerConcededRuns: Int {
        switch extra {
        case .bye, .legBye: 0
        case .wide: 1 + extraRuns
        case .noBall: 1 + runsOffBat
        case nil: runsOffBat
        }
    }

    public var runsForStrikeRotation: Int {
        switch extra {
        case .bye, .legBye, .wide: extraRuns
        default: runsOffBat
        }
    }
}

public enum EventKind: Hashable, Sendable {
    case ball(BallEvent)
    case retire(outgoing: String, incoming: String, isOut: Bool)
    case swap
    case note(String)
    case inningsEnd(reason: String)
    case void(seq: Int)
}

public struct MatchEvent: Hashable, Sendable, Codable {
    public var seq: Int
    public var inningsIndex: Int
    public var clientTs: Date
    public var kind: EventKind

    public init(seq: Int, inningsIndex: Int, clientTs: Date = .now, kind: EventKind) {
        self.seq = seq
        self.inningsIndex = inningsIndex
        self.clientTs = clientTs
        self.kind = kind
    }

    public var isVoid: Bool {
        if case .void = kind { return true }
        return false
    }

    enum K: String, CodingKey {
        case t, seq, inn, clientTs, strikerId, nonStrikerId, bowlerId, runsOffBat, extra, extraRuns,
             dismissal, dismissedPlayerId, incomingBatterId, outgoingPlayerId, incomingPlayerId, isOut,
             text, reason, voidedSeq
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        seq = try c.decode(Int.self, forKey: .seq)
        inningsIndex = try c.decode(Int.self, forKey: .inn)
        clientTs = ISODate.parse(try c.decodeIfPresent(String.self, forKey: .clientTs) ?? "") ?? .distantPast
        switch try c.decode(String.self, forKey: .t) {
        case "ball":
            kind = .ball(BallEvent(
                strikerId: try c.decode(String.self, forKey: .strikerId),
                nonStrikerId: try c.decode(String.self, forKey: .nonStrikerId),
                bowlerId: try c.decode(String.self, forKey: .bowlerId),
                runsOffBat: try c.decodeIfPresent(Int.self, forKey: .runsOffBat) ?? 0,
                extra: try c.decodeIfPresent(ExtraType.self, forKey: .extra),
                extraRuns: try c.decodeIfPresent(Int.self, forKey: .extraRuns) ?? 0,
                dismissal: try c.decodeIfPresent(Dismissal.self, forKey: .dismissal),
                dismissedPlayerId: try c.decodeIfPresent(String.self, forKey: .dismissedPlayerId),
                incomingBatterId: try c.decodeIfPresent(String.self, forKey: .incomingBatterId)))
        case "retire":
            kind = .retire(outgoing: try c.decode(String.self, forKey: .outgoingPlayerId),
                           incoming: try c.decode(String.self, forKey: .incomingPlayerId),
                           isOut: try c.decodeIfPresent(Bool.self, forKey: .isOut) ?? false)
        case "swap": kind = .swap
        case "note": kind = .note(try c.decode(String.self, forKey: .text))
        case "inningsEnd": kind = .inningsEnd(reason: try c.decode(String.self, forKey: .reason))
        case "void": kind = .void(seq: try c.decode(Int.self, forKey: .voidedSeq))
        case let t: throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "Unknown event \(t)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(seq, forKey: .seq)
        try c.encode(inningsIndex, forKey: .inn)
        try c.encode(ISODate.string(clientTs), forKey: .clientTs)
        switch kind {
        case .ball(let b):
            try c.encode("ball", forKey: .t)
            try c.encode(b.strikerId, forKey: .strikerId)
            try c.encode(b.nonStrikerId, forKey: .nonStrikerId)
            try c.encode(b.bowlerId, forKey: .bowlerId)
            try c.encode(b.runsOffBat, forKey: .runsOffBat)
            try c.encodeIfPresent(b.extra, forKey: .extra)
            try c.encode(b.extraRuns, forKey: .extraRuns)
            try c.encodeIfPresent(b.dismissal, forKey: .dismissal)
            try c.encodeIfPresent(b.dismissedPlayerId, forKey: .dismissedPlayerId)
            try c.encodeIfPresent(b.incomingBatterId, forKey: .incomingBatterId)
        case .retire(let outgoing, let incoming, let isOut):
            try c.encode("retire", forKey: .t)
            try c.encode(outgoing, forKey: .outgoingPlayerId)
            try c.encode(incoming, forKey: .incomingPlayerId)
            try c.encode(isOut, forKey: .isOut)
        case .swap:
            try c.encode("swap", forKey: .t)
        case .note(let text):
            try c.encode("note", forKey: .t)
            try c.encode(text, forKey: .text)
        case .inningsEnd(let reason):
            try c.encode("inningsEnd", forKey: .t)
            try c.encode(reason, forKey: .reason)
        case .void(let s):
            try c.encode("void", forKey: .t)
            try c.encode(s, forKey: .voidedSeq)
        }
    }
}
