import SwiftUI

/// Searches the loaded match list locally and teams by name on the server.
struct SearchView: View {
    let home: HomeModel
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var teams: [Team] = []
    @State private var searching = false

    private var term: String { query.trimmed.lowercased() }

    private var matches: [Match] {
        guard !term.isEmpty else { return [] }
        return (home.matches ?? []).filter { m in
            [m.teamA.name, m.teamA.shortName, m.teamB.name, m.teamB.shortName, m.venueName ?? ""]
                .contains { $0.lowercased().contains(term) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if term.isEmpty {
                    MessageView(text: "searchPrompt", systemImage: "magnifyingglass")
                } else if searching && matches.isEmpty && teams.isEmpty {
                    ProgressView().padding(.top, 64)
                } else if matches.isEmpty && teams.isEmpty {
                    MessageView(text: "searchNothingFound", systemImage: "magnifyingglass")
                } else {
                    if !matches.isEmpty {
                        SectionHeader(title: "tabMatches", count: matches.count)
                        ForEach(matches) { match in
                            MatchCard(match: match).onTapGesture { router.open(match, uid: session.uid) }
                        }
                    }
                    if !teams.isEmpty {
                        SectionHeader(title: "teams", count: teams.count)
                        ForEach(teams) { team in
                            Button { router.push(.team(id: team.id)) } label: { teamRow(team) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .smoothChange(searching)
            .smoothChange(teams)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .brandTitle("searchTitle")
        .clearNavBar()
        .searchable(text: $query, prompt: Text("searchPrompt"))
        .task(id: term) {
            guard !term.isEmpty else { teams = []; searching = false; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            teams = (try? await env.teams.search(term)) ?? []
            searching = false
        }
    }

    private func teamRow(_ team: Team) -> some View {
        HStack(spacing: 12) {
            TeamBadge(shortName: team.shortName, color: Palette.brand2, logoURL: team.logoUrl, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: team.name).font(AppFont.body(16, .semibold)).foregroundStyle(Palette.ink)
                if !team.ownerName.isEmpty {
                    Text(verbatim: team.ownerName).font(AppFont.body(13)).foregroundStyle(Palette.ink3)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.ink3)
        }
        .card()
    }
}

#if DEBUG
#Preview("Search") {
    let home = HomeModel()
    home.matches = [.live, .upcoming, .completed]
    return NavigationStack { SearchView(home: home) }.previewEnvironment()
}
#endif
