import SwiftUI

@MainActor @Observable
final class HomeModel {
    enum Filter: CaseIterable {
        case all, live, upcoming, results, mine, favorites

        var label: LocalizedStringKey {
            switch self {
            case .all: "filterAll"
            case .live: "filterLive"
            case .upcoming: "filterUpcoming"
            case .results: "filterResults"
            case .mine: "filterMine"
            case .favorites: "filterFavorites"
            }
        }

        var empty: LocalizedStringKey {
            switch self {
            case .all: "emptyAll"
            case .live: "emptyLive"
            case .upcoming: "emptyUpcoming"
            case .results: "emptyResults"
            case .mine: "emptyMine"
            case .favorites: "emptyFavorites"
            }
        }
    }

    struct Section: Identifiable {
        let title: LocalizedStringKey
        let items: [Match]
        var id: String { items.first?.id ?? "" }
    }

    var filter: Filter = .all
    var matches: [Match]?
    var failed = false

    func watch(_ repo: MatchRepository, uid: String?) async {
        failed = false
        do {
            for try await m in repo.watchMatches(uid: uid) { matches = m }
        } catch {
            failed = true
        }
    }

    func sections(uid: String?, favorites: [String]) -> [Section] {
        guard let all = matches else { return [] }
        let scoped = switch filter {
        case .mine: all.filter { $0.createdBy == uid }
        case .favorites: all.filter { favorites.contains($0.id) }
        default: all
        }
        let grouped = [.all, .mine, .favorites].contains(filter)
        func pick(_ s: [MatchStatus]) -> [Match] { scoped.filter { s.contains($0.status) } }

        var out: [Section] = []
        if grouped { out.append(Section(title: "statusPending", items: pick([.pending]))) }
        if grouped || filter == .live { out.append(Section(title: "sectionLive", items: pick([.live]))) }
        if grouped || filter == .upcoming { out.append(Section(title: "sectionUpcoming", items: pick([.upcoming]))) }
        if grouped || filter == .results { out.append(Section(title: "sectionResults", items: pick([.completed, .abandoned]))) }
        return out.filter { !$0.items.isEmpty }
    }
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    let model: HomeModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            ScrollView {
                content.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .screenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Wordmark().fixedSize() }.withoutGlass()
        }
        .navigationBarTitleDisplayMode(.inline)
        .brandNavBar()
        .task(id: session.uid) { await model.watch(env.matches, uid: session.uid) }
    }

    @ViewBuilder private var content: some View {
        if model.failed {
            MessageView(text: "errorGeneric", systemImage: "exclamationmark.triangle") {
                Task { await model.watch(env.matches, uid: session.uid) }
            }
        } else if model.matches == nil {
            VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 112, radius: 18) } }
                .padding(.top, 16)
        } else {
            let sections = model.sections(uid: session.uid, favorites: session.profile?.favoriteMatchIds ?? [])
            if sections.isEmpty {
                MessageView(text: model.filter.empty)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(sections) { section in
                        SectionHeader(title: section.title, count: section.items.count)
                        ForEach(section.items) { match in
                            MatchCard(match: match).onTapGesture { router.open(match, uid: session.uid) }
                        }
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeModel.Filter.allCases, id: \.self) { f in
                    ChoiceChip(title: f.label, selected: model.filter == f, onBrand: true) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.filter = f }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Palette.brand)
    }
}
