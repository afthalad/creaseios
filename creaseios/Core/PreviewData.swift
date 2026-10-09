#if DEBUG
import SwiftUI
import FirebaseCore
import FirebaseFirestore

// Sample data and environment for SwiftUI previews. Firebase stays offline, so nothing is read or written.

extension AppEnvironment {
    static func preview(signedIn: Bool = true) -> AppEnvironment {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            Firestore.firestore().disableNetwork { _ in }
        }
        let env = AppEnvironment()
        env.settings.onboardingSeen = true
        env.session.preview(signedIn ? .sample : nil, player: signedIn ? .sample : nil)
        env.inbox.preview(signedIn ? AppNotification.samples : nil)
        return env
    }
}

extension View {
    func previewEnvironment(signedIn: Bool = true) -> some View {
        previewEnvironment(.preview(signedIn: signedIn))
    }

    func previewEnvironment(_ env: AppEnvironment) -> some View {
        environment(env).environment(env.router).environment(env.session).environment(env.settings)
    }
}

private func ago(_ minutes: Double) -> String { ISODate.string(.now.addingTimeInterval(-minutes * 60)) }

private let kandyNames = ["Kasun Perera", "Dilan Fernando", "Nuwan Silva", "Ashen Jayasuriya", "Chamika Bandara",
                          "Ravindu Wickramasinghe", "Tharindu Gunasekara", "Lahiru Dissanayake", "Pasindu Rajapaksha",
                          "Sahan Herath", "Isuru Kumara"]
private let galleNames = ["Malinda Weerasinghe", "Oshada Senanayake", "Janith Karunaratne", "Dasun Abeysekara",
                          "Kavindu Ranasinghe", "Hasitha Mendis", "Vishwa Liyanage", "Dhananjaya Samarawickrama",
                          "Akila Pathirana", "Nimesh Hettiarachchi", "Shehan Gamage"]

private func sampleID(_ name: String) -> String { name.split(separator: " ")[0].lowercased() }

// MARK: - People and teams

extension UserProfile {
    static let sample = UserProfile(uid: "kasun", phone: "+94770000001", name: "Kasun Perera", createdAt: "2026-01-12T10:00:00.000Z")
}

extension PlayerProfile {
    static let sample = PlayerProfile(uid: "kasun", name: "Kasun Perera", gender: .male, photoUrl: nil, role: .allRounder,
                                      battingStyle: .rhb, bowlingStyle: .rightArmMedium)

    static let samples: [PlayerProfile] = [
        PlayerProfile(uid: "dilan", name: "Dilan Fernando", gender: .male, photoUrl: nil, role: .wicketKeeper, battingStyle: .rhb, bowlingStyle: .none),
        PlayerProfile(uid: "sahan", name: "Sahan Herath", gender: .male, photoUrl: nil, role: .bowler, battingStyle: .rhb, bowlingStyle: .rightArmSpin),
        PlayerProfile(uid: "isuru", name: "Isuru Kumara", gender: .male, photoUrl: nil, role: .bowler, battingStyle: .rhb, bowlingStyle: .rightArmMedium),
        PlayerProfile(uid: "nethmi", name: "Nethmi Rathnayake", gender: .female, photoUrl: nil, role: .allRounder, battingStyle: .rhb, bowlingStyle: .leftArmSpin),
    ]
}

extension Team {
    static let sample = Team(id: "kandy", name: "Kandy Kings", shortName: "KK", ownerId: "kasun", ownerName: "Kasun Perera",
                             createdAt: "2026-03-01T09:00:00.000Z", captainId: "kasun", viceCaptainId: "dilan")
    static let samples: [Team] = [
        sample,
        Team(id: "galle", name: "Galle Gladiators", shortName: "GG", ownerId: "malinda", ownerName: "Malinda Weerasinghe", createdAt: ago(9000)),
    ]
}

extension TeamMember {
    static func sample(_ player: String, team: String = "Kandy Kings", owner: String = "Kasun Perera",
                       status: MemberStatus = .accepted, reason: String? = nil, minutesAgo: Double = 600) -> TeamMember {
        TeamMember(teamId: sampleID(team), teamName: team, ownerId: sampleID(owner), ownerName: owner,
                   playerId: sampleID(player), playerName: player, playerGender: .male, status: status,
                   invitedAt: ago(minutesAgo), respondedAt: status == .pending ? nil : ago(minutesAgo / 2), declineReason: reason)
    }

    /// Everyone on Kandy Kings, plus one pending and one declined invite.
    static let teamSamples: [TeamMember] = kandyNames.prefix(8).map { sample($0) } + [
        sample("Sahan Herath", status: .pending, minutesAgo: 30),
        sample("Isuru Kumara", status: .declined, reason: "Playing for my office team this season.", minutesAgo: 1500),
    ]

    /// Invites Kasun has received from other teams.
    static let receivedSamples: [TeamMember] = [
        sample("Kasun Perera", team: "Galle Gladiators", owner: "Malinda Weerasinghe", status: .pending, minutesAgo: 10),
        sample("Kasun Perera", team: "Colombo Strikers", owner: "Oshada Senanayake", minutesAgo: 4000),
        sample("Kasun Perera", team: "Jaffna Stallions", owner: "Janith Karunaratne", status: .declined, reason: "Too far to travel.", minutesAgo: 9000),
    ]

    /// Invites Kasun has sent as the Kandy Kings owner.
    static let sentSamples: [TeamMember] = [
        sample("Sahan Herath", status: .pending, minutesAgo: 30),
        sample("Dilan Fernando", minutesAgo: 600),
        sample("Isuru Kumara", status: .declined, reason: "Playing for my office team this season.", minutesAgo: 1500),
    ]
}

extension AppNotification {
    static let samples: [AppNotification] = [
        AppNotification(id: "1", userId: "kasun", kind: .teamInvite, teamId: "galle", teamName: "Galle Gladiators",
                        fromName: "Malinda Weerasinghe", createdAt: ago(10)),
        AppNotification(id: "2", userId: "kasun", kind: .inviteAccepted, teamId: "kandy", teamName: "Kandy Kings",
                        fromName: "Dilan Fernando", createdAt: ago(300)),
        AppNotification(id: "3", userId: "kasun", kind: .inviteDeclined, teamId: "kandy", teamName: "Kandy Kings",
                        fromName: "Isuru Kumara", reason: "Playing for my office team this season.", createdAt: ago(1500), read: true),
    ]
}

extension Banner {
    static let samples: [Banner] = [
        Banner(id: "1", imageUrl: "https://picsum.photos/seed/crease-hero-1/1600/800", linkUrl: "https://www.espncricinfo.com", order: 1),
        Banner(id: "2", imageUrl: "https://picsum.photos/seed/crease-hero-2/1600/800", linkUrl: "https://www.srilankacricket.lk", order: 2),
        Banner(id: "3", imageUrl: "https://picsum.photos/seed/crease-hero-3/1600/800", order: 3),
    ]
}

// MARK: - Matches

extension MatchTeam {
    static let sampleA = MatchTeam(side: "A", name: "Kandy Kings", shortName: "KK", color: 0xFF0B2D5B,
                                   squad: kandyNames.map { Player(id: sampleID($0), name: $0) }, captainId: "kasun", wicketKeeperId: "dilan")
    static let sampleB = MatchTeam(side: "B", name: "Galle Gladiators", shortName: "GG", color: 0xFF2E7DD1,
                                   squad: galleNames.map { Player(id: sampleID($0), name: $0) }, captainId: "malinda", wicketKeeperId: "janith")
}

extension Match {
    static let upcoming = sample("upcoming", .upcoming)
    static let pending = sample("pending", .pending)
    static let live = sample("live", .live)
    static let completed = sample("completed", .completed, overs: 2)

    /// Runs per ball for each innings; -1 is a wicket.
    private static let sampleBalls: [String: [[Int]]] = [
        "live": [[1, 4, 0, 6, -1, 2, 1, 0, 4]],
        "completed": [[1, 4, 0, 6, -1, 2, 1, 0, 4, 1, -1, 6], [4, 1, 0, 6, 1, -1, 4, 2, 6, 0, 1, 4]],
    ]

    var sampleEvents: [MatchEvent] { MatchEvent.build(self, balls: Match.sampleBalls[id] ?? []) }
    var sampleState: MatchState { CreaseEngine().replay(events: sampleEvents, config: config, inningsBattingTeam: inningsBattingOrder) }

    private static func sample(_ id: String, _ status: MatchStatus, overs: Int = 20) -> Match {
        var m = Match(format: overs == 20 ? .t20 : .custom, config: MatchConfig(oversPerInnings: overs, playersPerSide: 11),
                      teamA: .sampleA, teamB: .sampleB, createdAt: ago(120))
        m.id = id
        m.status = status
        m.venueName = "Pallekele Stadium"
        m.toss = Toss(winnerSide: "A", decision: .bat)
        m.createdBy = "kasun"
        m.scheduledAt = status == .upcoming ? ISODate.string(.now.addingTimeInterval(26 * 3600)) : nil
        m.pendingOwnerIds = status == .pending ? ["kasun"] : []

        let state = m.sampleState
        for inn in state.innings {
            m.scores[inn.battingTeam] = TeamScore(runs: inn.runs, wickets: inn.wickets, balls: inn.legalBalls)
        }
        m.battingSide = state.current?.battingTeam
        m.resultText = state.result?.text
        m.winnerSide = state.result?.winner
        return m
    }
}

extension MatchEvent {
    /// Plays the given balls through the engine, so strike and bowling changes stay valid.
    fileprivate static func build(_ match: Match, balls: [[Int]]) -> [MatchEvent] {
        let engine = CreaseEngine()
        var events: [MatchEvent] = []
        for (inn, runs) in balls.enumerated() {
            let bat = match.team(match.inningsBattingOrder[inn]), bowl = match.team(match.inningsBattingOrder[1 - inn])
            for r in runs {
                let state = engine.replay(events: events, config: match.config, inningsBattingTeam: match.inningsBattingOrder)
                let cur = state.innings.first { $0.index == inn }
                let striker = cur?.strikerId ?? bat.squad[0].id
                let bowler = bowl.squad[10 - ((cur?.legalBalls ?? 0) / 6) % 4].id
                var ball = BallEvent(strikerId: striker, nonStrikerId: cur?.nonStrikerId ?? bat.squad[1].id, bowlerId: bowler)
                if r < 0 {
                    ball.dismissal = Dismissal(type: .bowled, bowlerId: bowler)
                    ball.dismissedPlayerId = striker
                    ball.incomingBatterId = bat.squad[2 + (cur?.wickets ?? 0)].id
                } else {
                    ball.runsOffBat = r
                }
                events.append(MatchEvent(seq: events.count + 1, inningsIndex: inn, kind: .ball(ball)))
            }
        }
        return events
    }
}
#endif
