import Foundation

public struct MatchConfig: Codable, Hashable, Sendable {
    public var oversPerInnings: Int
    public var playersPerSide: Int
    public var ballsPerOver: Int
    public var maxOversPerBowler: Int
    public var isLimitedOvers: Bool

    public init(oversPerInnings: Int, playersPerSide: Int, ballsPerOver: Int = 6,
                maxOversPerBowler: Int = 0, isLimitedOvers: Bool = true) {
        self.oversPerInnings = oversPerInnings
        self.playersPerSide = playersPerSide
        self.ballsPerOver = ballsPerOver
        self.maxOversPerBowler = maxOversPerBowler
        self.isLimitedOvers = isLimitedOvers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        oversPerInnings = try c.decode(Int.self, forKey: .oversPerInnings)
        playersPerSide = try c.decode(Int.self, forKey: .playersPerSide)
        ballsPerOver = try c.decodeIfPresent(Int.self, forKey: .ballsPerOver) ?? 6
        maxOversPerBowler = try c.decodeIfPresent(Int.self, forKey: .maxOversPerBowler) ?? 0
        isLimitedOvers = try c.decodeIfPresent(Bool.self, forKey: .isLimitedOvers) ?? true
    }
}

public struct BatterInnings: Hashable, Sendable {
    public let playerId: String
    public var runs = 0, balls = 0, fours = 0, sixes = 0
    public var isOut = false, retiredNotOut = false
    public var dismissal: Dismissal?

    public init(playerId: String) { self.playerId = playerId }

    public var strikeRate: Double { balls == 0 ? 0 : Double(runs) / Double(balls) * 100 }
    public var didBat: Bool { balls > 0 || runs > 0 || isOut || retiredNotOut }
}

public struct BowlerSpell: Hashable, Sendable {
    public let playerId: String
    public var legalBalls = 0, runsConceded = 0, wickets = 0, maidens = 0

    public init(playerId: String) { self.playerId = playerId }

    public func overs(_ bpo: Int) -> String { "\(legalBalls / bpo).\(legalBalls % bpo)" }
    public func economy(_ bpo: Int) -> Double {
        legalBalls == 0 ? 0 : Double(runsConceded) / (Double(legalBalls) / Double(bpo))
    }
}

public struct InningsState: Hashable, Sendable {
    public let index: Int
    public let battingTeam: String
    public let bowlingTeam: String
    public var runs = 0, wickets = 0, legalBalls = 0
    public var batters: [String: BatterInnings] = [:]
    public var bowlers: [String: BowlerSpell] = [:]
    public var battingOrder: [String] = []
    public var strikerId: String?
    public var nonStrikerId: String?
    public var currentBowlerId: String?
    public var currentOverBalls: [String] = []
    public var overHistory: [[String]] = []
    public var closed = false
    public var endReason: String?
    public var target: Int?

    public init(index: Int, battingTeam: String, bowlingTeam: String, target: Int? = nil) {
        self.index = index
        self.battingTeam = battingTeam
        self.bowlingTeam = bowlingTeam
        self.target = target
    }

    public func overs(_ bpo: Int) -> String { "\(legalBalls / bpo).\(legalBalls % bpo)" }
    public var runRate: Double { legalBalls == 0 ? 0 : Double(runs) / (Double(legalBalls) / 6) }
    public var runsNeeded: Int? { target.map { $0 - runs } }
}

public enum ResultType: String, Sendable { case win, tie, noResult }

public struct MatchResult: Hashable, Sendable {
    public let type: ResultType
    public let winner: String?
    public let text: String
}

public struct MatchState: Hashable, Sendable {
    public var currentInningsIndex = 0
    public var innings: [InningsState] = []
    public var notes: [String] = []
    public var result: MatchResult?

    public init(currentInningsIndex: Int = 0, innings: [InningsState] = [], notes: [String] = [], result: MatchResult? = nil) {
        self.currentInningsIndex = currentInningsIndex
        self.innings = innings
        self.notes = notes
        self.result = result
    }

    public var current: InningsState? { innings.first { $0.index == currentInningsIndex } }
}
