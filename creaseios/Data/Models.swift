import SwiftUI
import FirebaseFirestore

enum MatchFormat: String, Codable, CaseIterable {
    case t20, t10, odi, custom, softball, tapeBall, sixes

    var defaultOvers: Int {
        switch self {
        case .t20, .custom: 20
        case .t10: 10
        case .odi: 50
        case .softball: 8
        case .tapeBall: 12
        case .sixes: 6
        }
    }
    var defaultPlayersPerSide: Int { self == .softball ? 8 : 11 }
}

enum MatchStatus: String, Codable { case pending, upcoming, live, completed, abandoned }
enum TossDecision: String, Codable, CaseIterable { case bat, bowl }
enum PlayerRole: String, Codable, CaseIterable { case batter, bowler, allRounder, wicketKeeper }
enum BattingStyle: String, Codable, CaseIterable { case rhb, lhb }
enum BowlingStyle: String, Codable, CaseIterable {
    case none, rightArmFast, rightArmMedium, rightArmSpin, leftArmFast, leftArmMedium, leftArmSpin
}
enum Gender: String, Codable, CaseIterable { case male, female }
enum MemberStatus: String, Codable { case pending, accepted }

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

struct Player: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var role: PlayerRole = .batter
    var battingStyle: BattingStyle = .rhb
    var bowlingStyle: String?
    var photoUrl: String?

    init(id: String, name: String, role: PlayerRole = .batter, battingStyle: BattingStyle = .rhb,
         bowlingStyle: String? = nil, photoUrl: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.battingStyle = battingStyle
        self.bowlingStyle = bowlingStyle
        self.photoUrl = photoUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.value(.name, default: "")
        role = c.value(.role, default: .batter)
        battingStyle = c.value(.battingStyle, default: .rhb)
        bowlingStyle = c.value(.bowlingStyle, default: nil)
        photoUrl = c.value(.photoUrl, default: nil)
    }
}

struct MatchTeam: Codable, Hashable {
    var side: String
    var name: String
    var shortName: String
    var color: Int
    var squad: [Player] = []
    var captainId: String?
    var wicketKeeperId: String?
    var teamId: String?
    var ownerId: String?
    var logoUrl: String?

    var uiColor: Color { Color(argb: color) }
    func player(_ id: String?) -> Player? { squad.first { $0.id == id } }
}

struct TeamScore: Codable, Hashable {
    var runs: Int
    var wickets: Int
    var balls: Int
    func overs(_ bpo: Int) -> String { "\(balls / bpo).\(balls % bpo)" }
}

struct Toss: Codable, Hashable {
    var winnerSide: String
    var decision: TossDecision
}

struct Match: Codable, Hashable, Identifiable {
    var id = ""
    var format: MatchFormat
    var config: MatchConfig
    var teamA: MatchTeam
    var teamB: MatchTeam
    var createdAt: String
    var venueName: String?
    var toss: Toss?
    var status: MatchStatus = .upcoming
    var resultText: String?
    var winnerSide: String?
    var createdBy: String?
    var isPublic = true
    var scheduledAt: String?
    var pendingOwnerIds: [String] = []
    var scores: [String: TeamScore] = [:]
    var battingSide: String?

    enum CodingKeys: String, CodingKey {
        case format, config, teamA, teamB, createdAt, venueName, toss, status, resultText, winnerSide,
             createdBy, isPublic, scheduledAt, pendingOwnerIds, scores, battingSide
    }

    init(format: MatchFormat, config: MatchConfig, teamA: MatchTeam, teamB: MatchTeam, createdAt: String) {
        self.format = format
        self.config = config
        self.teamA = teamA
        self.teamB = teamB
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = c.value(.format, default: .custom)
        config = try c.decode(MatchConfig.self, forKey: .config)
        teamA = try c.decode(MatchTeam.self, forKey: .teamA)
        teamB = try c.decode(MatchTeam.self, forKey: .teamB)
        createdAt = c.value(.createdAt, default: "")
        venueName = c.value(.venueName, default: nil)
        toss = c.value(.toss, default: nil)
        status = c.value(.status, default: .upcoming)
        resultText = c.value(.resultText, default: nil)
        winnerSide = c.value(.winnerSide, default: nil)
        createdBy = c.value(.createdBy, default: nil)
        isPublic = c.value(.isPublic, default: true)
        scheduledAt = c.value(.scheduledAt, default: nil)
        pendingOwnerIds = c.value(.pendingOwnerIds, default: [])
        scores = c.value(.scores, default: [:])
        battingSide = c.value(.battingSide, default: nil)
    }

    var createdDate: Date { ISODate.parse(createdAt) ?? .now }
    var scheduledDate: Date? { scheduledAt.flatMap(ISODate.parse) }
    func team(_ side: String) -> MatchTeam { side == "A" ? teamA : teamB }

    func player(_ id: String?) -> Player? { teamA.player(id) ?? teamB.player(id) }
    func playerName(_ id: String?) -> String { player(id)?.name ?? "—" }

    func isVisible(to uid: String?) -> Bool {
        guard status == .pending else { return true }
        guard let uid else { return false }
        return createdBy == uid || pendingOwnerIds.contains(uid)
    }

    var inningsBattingOrder: [String] {
        guard let toss else { return ["A", "B"] }
        let other = toss.winnerSide == "A" ? "B" : "A"
        let first = toss.decision == .bat ? toss.winnerSide : other
        return first == "A" ? ["A", "B"] : ["B", "A"]
    }

    var title: String { "\(teamA.name) vs \(teamB.name)" }

    /// "Team A won by 12 runs" -> "Kandy Kings won by 12 runs"
    var displayResultText: String? {
        guard var t = resultText else { return nil }
        for team in [teamA, teamB] { t = t.replacingOccurrences(of: "Team \(team.side) ", with: "\(team.name) ") }
        return t
    }

    var shortResultText: String? {
        guard var t = resultText else { return nil }
        for team in [teamA, teamB] {
            t = t.replacingOccurrences(of: team.name, with: team.shortName)
                .replacingOccurrences(of: "Team \(team.side)", with: team.shortName)
        }
        return t
    }
}

extension DocumentSnapshot {
    func match() throws -> Match {
        var m = try data(as: Match.self)
        m.id = documentID
        return m
    }
}

struct UserProfile: Codable, Hashable {
    var uid: String
    var phone = ""
    var name = ""
    var createdAt: String
    var favoriteMatchIds: [String] = []
    var reminderMatchIds: [String] = []

    init(uid: String, phone: String, name: String, createdAt: String) {
        self.uid = uid
        self.phone = phone
        self.name = name
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = c.value(.uid, default: "")
        phone = c.value(.phone, default: "")
        name = c.value(.name, default: "")
        createdAt = c.value(.createdAt, default: "")
        favoriteMatchIds = c.value(.favoriteMatchIds, default: [])
        reminderMatchIds = c.value(.reminderMatchIds, default: [])
    }

    var createdDate: Date { ISODate.parse(createdAt) ?? .now }
}

struct PlayerProfile: Codable, Hashable, Identifiable {
    var uid: String
    var name: String
    var gender: Gender = .male
    var photoUrl: String?
    var role: PlayerRole = .batter
    var battingStyle: BattingStyle = .rhb
    var bowlingStyle: BowlingStyle = .none
    var searchTokens: [String] = []
    var id: String { uid }

    init(uid: String, name: String, gender: Gender, photoUrl: String?, role: PlayerRole,
         battingStyle: BattingStyle, bowlingStyle: BowlingStyle) {
        self.uid = uid
        self.name = name
        self.gender = gender
        self.photoUrl = photoUrl
        self.role = role
        self.battingStyle = battingStyle
        self.bowlingStyle = bowlingStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        name = c.value(.name, default: "")
        gender = c.value(.gender, default: .male)
        photoUrl = c.value(.photoUrl, default: nil)
        role = c.value(.role, default: .batter)
        battingStyle = c.value(.battingStyle, default: .rhb)
        bowlingStyle = c.value(.bowlingStyle, default: .none)
        searchTokens = c.value(.searchTokens, default: [])
    }
}

struct Team: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var shortName: String
    var ownerId: String
    var ownerName = ""
    var createdAt: String
    var logoUrl: String?
    var searchTokens: [String] = []
    var captainId: String?
    var viceCaptainId: String?
}

struct TeamMember: Codable, Hashable, Identifiable {
    var teamId: String
    var teamName: String
    var ownerId: String
    var ownerName: String
    var playerId: String
    var playerName: String
    var playerGender: Gender?
    var playerPhotoUrl: String?
    var teamLogoUrl: String?
    var status: MemberStatus
    var invitedAt: String

    var id: String { Self.docID(teamId, playerId) }
    var isPending: Bool { status == .pending }
    var isOwner: Bool { ownerId == playerId }
    static func docID(_ team: String, _ player: String) -> String { "\(team)_\(player)" }
}
