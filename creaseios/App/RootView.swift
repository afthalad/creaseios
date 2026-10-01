import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if settings.onboardingSeen {
                MainTabs()
            } else {
                NavigationStack(path: router.path(for: .matches)) {
                    WelcomeView().withRoutes()
                }
            }
        }
        .tint(Palette.btn)
        .preferredColorScheme(settings.colorScheme)
        .environment(\.locale, settings.locale)
    }
}

private extension View {
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteDestination(route: route).claimsBackgroundTaps()
        }
    }
}

private struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .createMatch: CreateMatchWizard().toolbar(.hidden, for: .tabBar)
        case .scoring(let id): ScoringView(matchID: id).toolbar(.hidden, for: .tabBar)
        case .matchCenter(let id): MatchCenterView(matchID: id)
        case .login(let redirect): PhoneLoginView(redirect: redirect).toolbar(.hidden, for: .tabBar)
        case .profile: ProfileView()
        case .playerProfileSetup(let redirect): PlayerProfileFormView(setup: true, redirect: redirect).toolbar(.hidden, for: .tabBar)
        case .playerProfileEdit: PlayerProfileFormView(setup: false, redirect: nil)
        case .teams: TeamsView()
        case .team(let id): TeamView(teamID: id)
        }
    }
}

/// The root screens in a system tab bar. The + is an action, not a screen: on iOS 18+ it takes the
/// separate glass button iOS 26 gives the search-role tab, and selecting it opens the create menu.
private struct MainTabs: View {
    @Environment(Router.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var home = HomeModel()
    @State private var showCreate = false
    @State private var pendingCreate: CreateAction?

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: selection) {
                    Tab("tabMatches", systemImage: "cricket.ball.fill", value: RootTab.matches) {
                        stack(.matches) { HomeView(model: home) }
                    }
                    Tab("teams", systemImage: "person.3.fill", value: RootTab.teams) {
                        stack(.teams) { TeamsView() }
                    }
                    Tab("profileTitle", systemImage: "person.crop.circle.fill", value: RootTab.profile) {
                        stack(.profile) { ProfileView() }
                    }
                    Tab("newMatch", systemImage: "plus", value: RootTab.newMatch, role: .search) {
                        Color.clear
                    }
                }
                .minimizesTabBarOnScroll()
            } else {
                TabView(selection: selection) {
                    stack(.matches) { HomeView(model: home) }
                        .tabItem { Label("tabMatches", systemImage: "cricket.ball.fill") }
                        .tag(RootTab.matches)
                        stack(.teams) { TeamsView() }
                        .tabItem { Label("teams", systemImage: "person.3.fill") }
                        .tag(RootTab.teams)
                    stack(.profile) { ProfileView() }
                        .tabItem { Label("profileTitle", systemImage: "person.crop.circle.fill") }
                        .tag(RootTab.profile)
                    Color.clear
                        .tabItem { Label("newMatch", systemImage: "plus.circle.fill") }
                        .tag(RootTab.newMatch)
                }
            }
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn && router.tab == .teams { router.tab = .matches }
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            guard let action = pendingCreate else { return }
            pendingCreate = nil
            switch action {
            case .match:
                // Pushed on the current tab, so backing out of the wizard returns to that tab's root.
                router.requireAuth(session) { router.push(.createMatch) }
            case .team:
                if session.isSignedIn {
                    router.select(.teams)
                    router.creatingTeam = true
                } else {
                    router.push(.login(redirect: "/teams"))
                }
            }
        }) {
            CreateMenuSheet { action in
                pendingCreate = action
                showCreate = false
            }
        }
    }

    private var selection: Binding<RootTab> {
        Binding(
            get: { router.tab },
            set: { t in
                switch t {
                case .newMatch:
                    showCreate = true
                case .teams where !session.isSignedIn:
                    router.push(.login(redirect: "/teams"))
                default:
                    router.tab = t
                }
            }
        )
    }

    private func stack<Content: View>(_ t: RootTab, @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack(path: router.path(for: t)) {
            content().withRoutes()
        }
    }
}

/// What the + button can create. Tournaments aren't built yet, so that row is shown but disabled.
private enum CreateAction { case match, team }

private struct CreateMenuSheet: View {
    let onSelect: (CreateAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetTitle(title: "createTitle").padding(.bottom, 8)
            Button { onSelect(.match) } label: {
                row("newMatch", icon: "cricket.ball.fill")
            }
            .buttonStyle(.plain)
            Button { onSelect(.team) } label: {
                row("newTeam", icon: "person.3.fill")
            }
            .buttonStyle(.plain)
            row("newTournament", icon: "trophy.fill", comingSoon: true)
                .opacity(0.5)
                .accessibilityAddTraits(.isStaticText)
        }
        .padding(24)
        .presentationDetents([.height(310)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }

    private func row(_ title: LocalizedStringKey, icon: String, comingSoon: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.onBrand)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.btn))
            Text(title).font(AppFont.body(16, .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            if comingSoon {
                Text("comingSoon")
                    .font(AppFont.body(12, .semibold))
                    .foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Palette.sunk))
            } else {
                Image(systemName: "chevron.right").foregroundStyle(Palette.ink3)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface2))
        .contentShape(Rectangle())
    }
}
