import SwiftUI

enum Route: Hashable {
    case createMatch
    case scoring(matchID: String)
    case matchCenter(matchID: String)
    case login(redirect: String?)
    case profile
    case playerProfileSetup(redirect: String?)
    case playerProfileEdit
    case teams
    case team(id: String)
}

enum RootTab: Hashable { case matches, teams, profile, newMatch }

@MainActor @Observable
final class Router {
    /// One navigation stack per tab; `push` and `pop` act on the selected tab's stack.
    var paths: [RootTab: NavigationPath] = [:]
    var tab: RootTab = .matches
    /// Set to open the new-team sheet on the Teams tab, e.g. from the tab bar's create menu.
    var creatingTeam = false

    var path: NavigationPath {
        get { paths[tab] ?? NavigationPath() }
        set { paths[tab] = newValue }
    }

    func path(for t: RootTab) -> Binding<NavigationPath> {
        Binding(get: { self.paths[t] ?? NavigationPath() }, set: { self.paths[t] = $0 })
    }

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path = NavigationPath() }

    func goHome() {
        popToRoot()
        tab = .matches
        popToRoot()
    }

    func select(_ t: RootTab) {
        tab = t
        popToRoot()
    }

    /// Scorers go straight to scoring for their own unfinished matches; everyone else gets the match centre.
    func open(_ match: Match, uid: String?) {
        let isScorer = match.createdBy != nil && match.createdBy == uid
        if isScorer && (match.status == .live || match.status == .upcoming) {
            push(.scoring(matchID: match.id))
        } else {
            push(.matchCenter(matchID: match.id))
        }
    }

    func replace(with r: Route) {
        pop()
        push(r)
    }

    /// Maps the go_router style paths carried by push notifications.
    func open(path string: String) {
        let parts = string.split(separator: "/").map(String.init)
        switch (parts.count, parts.first) {
        case (0, _): goHome()
        case (1, "teams"): select(.teams)
        case (1, "profile"): select(.profile)
        case (2, "teams"): push(.team(id: parts[1]))
        case (2, "match"): push(.matchCenter(matchID: parts[1]))
        case (2, "scoring"): push(.scoring(matchID: parts[1]))
        default: break
        }
    }

    func requireAuth(_ session: SessionStore, redirect: String? = nil, _ action: () -> Void) {
        session.isSignedIn ? action() : push(.login(redirect: redirect))
    }
}
