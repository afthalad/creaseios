import Foundation

struct MatchConfig: Codable, Hashable, Sendable {
    var oversPerInnings: Int
    var playersPerSide: Int
    var ballsPerOver: Int
    var maxOversPerBowler: Int
    var isLimitedOvers: Bool

    init(oversPerInnings: Int, playersPerSide: Int, ballsPerOver: Int = 6,
                maxOversPerBowler: Int = 0, isLimitedOvers: Bool = true) {
        self.oversPerInnings = oversPerInnings
        self.playersPerSide = playersPerSide
        self.ballsPerOver = ballsPerOver
        self.maxOversPerBowler = maxOversPerBowler
        self.isLimitedOvers = isLimitedOvers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        oversPerInnings = try c.decode(Int.self, forKey: .oversPerInnings)
        playersPerSide = try c.decode(Int.self, forKey: .playersPerSide)
        ballsPerOver = try c.decodeIfPresent(Int.self, forKey: .ballsPerOver) ?? 6
        maxOversPerBowler = try c.decodeIfPresent(Int.self, forKey: .maxOversPerBowler) ?? 0
        isLimitedOvers = try c.decodeIfPresent(Bool.self, forKey: .isLimitedOvers) ?? true
    }
}

struct BatterInnings: Hashable, Sendable {
    let playerId: String
    var runs = 0, balls = 0, fours = 0, sixes = 0
    var isOut = false, retiredNotOut = false
    var dismissal: Dismissal?

    init(playerId: String) { self.playerId = playerId }

    var strikeRate: Double { balls == 0 ? 0 : Double(runs) / Double(balls) * 100 }
    var didBat: Bool { balls > 0 || runs > 0 || isOut || retiredNotOut }
}

struct BowlerSpell: Hashable, Sendable {
    let playerId: String
    var legalBalls = 0, runsConceded = 0, wickets = 0, maidens = 0

    init(playerId: String) { self.playerId = playerId }

    func overs(_ bpo: Int) -> String { "\(legalBalls / bpo).\(legalBalls % bpo)" }
    func economy(_ bpo: Int) -> Double {
        legalBalls == 0 ? 0 : Double(runsConceded) / (Double(legalBalls) / Double(bpo))
    }
}

struct InningsState: Hashable, Sendable {
    let index: Int
    let battingTeam: String
    let bowlingTeam: String
    var runs = 0, wickets = 0, legalBalls = 0
    var batters: [String: BatterInnings] = [:]
    var bowlers: [String: BowlerSpell] = [:]
    var battingOrder: [String] = []
    var strikerId: String?
    var nonStrikerId: String?
    var currentBowlerId: String?
    var currentOverBalls: [String] = []
    var overHistory: [[String]] = []
    var closed = false
    var endReason: String?
    var target: Int?

    init(index: Int, battingTeam: String, bowlingTeam: String, target: Int? = nil) {
        self.index = index
        self.battingTeam = battingTeam
        self.bowlingTeam = bowlingTeam
        self.target = target
    }

    func overs(_ bpo: Int) -> String { "\(legalBalls / bpo).\(legalBalls % bpo)" }
    var runRate: Double { legalBalls == 0 ? 0 : Double(runs) / (Double(legalBalls) / 6) }
    var runsNeeded: Int? { target.map { $0 - runs } }
}

enum ResultType: String, Sendable { case win, tie, noResult }

struct MatchResult: Hashable, Sendable {
    let type: ResultType
    let winner: String?
    let text: String
}

struct MatchState: Hashable, Sendable {
    var currentInningsIndex = 0
    var innings: [InningsState] = []
    var notes: [String] = []
    var result: MatchResult?

    init(currentInningsIndex: Int = 0, innings: [InningsState] = [], notes: [String] = [], result: MatchResult? = nil) {
        self.currentInningsIndex = currentInningsIndex
        self.innings = innings
        self.notes = notes
        self.result = result
    }

    var current: InningsState? { innings.first { $0.index == currentInningsIndex } }
}
