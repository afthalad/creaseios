import SwiftUI

@MainActor @Observable
final class MatchCenterModel {
    private(set) var match: Match?
    private(set) var state = MatchState()
    private(set) var notFound = false
    private var events: [MatchEvent] = []

    let matchID: String
    let env: AppEnvironment

    init(matchID: String, env: AppEnvironment) {
        self.matchID = matchID
        self.env = env
    }

    func watch() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.watchMatch() }
            group.addTask { await self.watchEvents() }
        }
    }

    private func watchMatch() async {
        do {
            for try await m in env.matches.watchMatch(matchID) {
                guard let m else { notFound = true; continue }
                match = m
                replay()
            }
        } catch {
            if match == nil { notFound = true }
        }
    }

    private func watchEvents() async {
        do {
            for try await e in env.matches.watchEvents(matchID) {
                events = e
                replay()
            }
        } catch {}
    }

    private func replay() {
        guard let match else { return }
        state = env.engine.replay(events: events, config: match.config, inningsBattingTeam: match.inningsBattingOrder)
    }

    func confirm(ownerID: String) async {
        guard let m = match else { return }
        let remaining = m.pendingOwnerIds.filter { $0 != ownerID }
        let status: MatchStatus = remaining.isEmpty ? .live : .pending
        do {
            try await env.matches.confirm(matchID, status: status, pendingOwnerIds: remaining)
            if remaining.isEmpty { await env.functions.notify("match_confirmed", ["matchId": matchID]) }
        } catch {}
    }

    func decline() async {
        await env.functions.notify("match_declined", ["matchId": matchID])
        try? await env.matches.delete(matchID)
    }
}
