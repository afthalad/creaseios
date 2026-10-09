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
    var banners: [Banner]?
    var failed = false

    func watch(_ repo: MatchRepository, uid: String?) async {
        failed = false
        do {
            for try await m in repo.watchMatches(uid: uid) { matches = m }
        } catch {
            failed = true
        }
    }

    func watchBanners(_ repo: BannerRepository) async {
        do {
            for try await b in repo.watch() { banners = b }
        } catch {
            banners = []
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

    /// Testing a header with no background: the logo, bell and filters scroll away with the matches.
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                filterBar
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .smoothChange(model.failed)
                    .smoothChange(model.matches?.map(\.id))
                    .smoothChange(model.banners)
                    .smoothChange(model.filter)
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Wordmark(color: Palette.ink)
            Spacer()
            if session.isSignedIn {
                Button { router.push(.notifications) } label: {
                    IconBadge(systemName: "bell", count: env.inbox.unreadCount)
                }
                .foregroundStyle(Palette.ink)
                .accessibilityLabel(Text("notificationsTitle"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder private var content: some View {
        if model.filter == .all { hero }
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

    /// Banners show on the All filter only, and hide when there are none.
    @ViewBuilder private var hero: some View {
        if let banners = model.banners {
            if !banners.isEmpty { HeroCarousel(banners: banners).padding(.top, 16) }
        } else {
            HeroPlaceholder().padding(.top, 16)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeModel.Filter.allCases, id: \.self) { f in
                    ChoiceChip(title: f.label, selected: model.filter == f) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.filter = f }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

#if DEBUG
@MainActor private func previewModel(_ matches: [Match]?, failed: Bool = false) -> HomeModel {
    let m = HomeModel()
    m.matches = matches
    m.banners = Banner.samples
    m.failed = failed
    return m
}

#Preview("Home") {
    NavigationStack { HomeView(model: previewModel([.live, .pending, .upcoming, .completed])) }.previewEnvironment()
}

#Preview("Home empty") {
    NavigationStack { HomeView(model: previewModel([])) }.previewEnvironment()
}

#Preview("Home loading") {
    NavigationStack { HomeView(model: previewModel(nil)) }.previewEnvironment(signedIn: false)
}

#Preview("Home error") {
    NavigationStack { HomeView(model: previewModel(nil, failed: true)) }.previewEnvironment()
}
#endif
