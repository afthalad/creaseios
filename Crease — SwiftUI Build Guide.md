# Crease — SwiftUI Build Guide

Oct 1, 2026 · @Afthal

## 1. Overview

This guide rebuilds Crease, the Flutter cricket scoring app in this repo, as a native iOS app in SwiftUI. It keeps the same backend (Firebase Auth, Firestore, FCM, Supabase edge functions), so the Flutter and Swift apps can run side by side on the same data.

Crease lets anyone score a cricket match ball by ball on their phone while followers watch the score update live. Every ball is stored as an event in an append-only log; the app rebuilds the scoreboard by replaying that log through a pure scoring engine.

### Features to rebuild

| Area | What it does | Flutter source |
| --- | --- | --- |
| Onboarding | Welcome screen with pitch illustration, language pick | `lib/features/onboarding` |
| Phone sign-in | SMS OTP via Firebase Auth, 6-digit code field | `lib/features/auth` |
| Home | Live, upcoming and completed match cards, favorites | `lib/features/home` |
| Create match | 4-step wizard: details, teams, squads, toss | `lib/features/create_match` |
| Scoring | Score pad, extras, wickets, openers, undo, end innings | `lib/features/scoring` |
| Match center | Summary, Live, Scorecard, Squads tabs | `lib/features/match_center` |
| Player profile | Name, gender, role, batting and bowling style, photo | `lib/features/player_profile` |
| Teams | Create teams, logos, invite players, accept invites | `lib/features/teams` |
| Profile and settings | Account, theme, language (English, Sinhala, Tamil) | `lib/features/profile`, `settings` |
| Notifications | Team invites, match requests, match start/finish, reminders | `notification_service.dart`, `supabase/functions/notify` |

### What does not change

- Firestore collections, field names and security rules (`firestore.rules`).
- Supabase edge functions `upload-photo` and `notify`, and the `player-photos` bucket.
- Firebase Cloud Functions `onMatchStatusChange` and `sendMatchReminders`.
- The event wire format (`t`, `seq`, `inn`, `clientTs`, ...). The Swift engine must produce the same state from the same events.

## 2. Tech stack and Xcode setup

Target iOS 17 or later so you can use the `@Observable` macro, `NavigationStack` and String Catalogs. Use Swift 6 with strict concurrency on.

| Concern | Flutter today | SwiftUI choice |
| --- | --- | --- |
| State management | flutter\_bloc (Cubit/Bloc) | `@Observable` view models, `@MainActor` |
| Dependency injection | get\_it | One `AppEnvironment` object injected with `.environment()` |
| Routing | go\_router | `NavigationStack` + `NavigationPath` + `Route` enum |
| Auth | firebase\_auth (phone) | FirebaseAuth `PhoneAuthProvider` |
| Database | cloud\_firestore | FirebaseFirestore (async/await + snapshot listeners) |
| Push | firebase\_messaging + local notifications | FirebaseMessaging + `UNUserNotificationCenter` |
| HTTP to edge functions | http | `URLSession` |
| Settings | shared\_preferences | `@AppStorage` / `UserDefaults` |
| Images | image\_picker, Image.network | `PhotosPicker`, `AsyncImage` (or Nuke for caching) |
| SVG illustrations | flutter\_svg | Convert SVGs to PDF vector assets in the asset catalog |
| i18n | ARB files + gen-l10n | `Localizable.xcstrings` String Catalog |
| Scoring engine | `packages/crease_engine` (Dart) | Local Swift package `CreaseEngine` |

### Step by step

1. In Xcode, create a new iOS App named `Crease`, interface SwiftUI, language Swift, storage None.
2. Set the bundle ID. The Firebase iOS app is registered as `com.example.crease1` (Firebase project `crease-scorer-app`). Either reuse it or register a new iOS app in the Firebase console and download a fresh `GoogleService-Info.plist`.
3. Drag `GoogleService-Info.plist` into the app target. Copy it from `ios/Runner/GoogleService-Info.plist` if you reuse the bundle ID.
4. File > Add Package Dependencies > `https://github.com/firebase/firebase-ios-sdk`, latest major version. Add products `FirebaseAuth`, `FirebaseFirestore`, `FirebaseMessaging`.
5. File > New > Package, name it `CreaseEngine`, save it inside the project folder, and add it to the app target. It must import only Foundation.
6. Signing and Capabilities: add Push Notifications and Background Modes > Remote notifications.
7. Info tab > URL Types: add the `REVERSED_CLIENT_ID` from the plist as a URL scheme. Phone auth needs it for the reCAPTCHA fallback.
8. Add fonts: copy `assets/fonts/BricolageGrotesque.ttf`, `Geist.ttf`, `GeistMono.ttf` into the target and list them under `UIAppFonts` (Fonts provided by application) in Info.plist.
9. Add images: `assets/images/welcome_hero.webp` (convert to PNG or HEIC), `assets/illustrations/cricketer.svg` and `cricketer_female.svg` (import as SVG or PDF with Preserve Vector Data on), `assets/icon/icon.png` as the 1024 px app icon.
10. Create `Config.xcconfig` with `FUNCTIONS_BASE_URL = https:/$()/zopovxkefvavxxlhnwzs.supabase.co/functions/v1`, expose it via Info.plist key `FunctionsBaseURL`, and read it with `Bundle.main.object(forInfoDictionaryKey:)`.

### Folder structure

```text
Crease/
  CreaseApp.swift              // @main, Firebase setup, AppDelegate adaptor
  App/
    AppEnvironment.swift       // holds repositories + services
    Router.swift               // Route enum + NavigationPath
    RootView.swift             // onboarding gate + NavigationStack
  Core/
    Theme/  Palette.swift, Typography.swift
    Components/  BallChip, PillButton, TeamBadge, PlayerAvatar, CreaseLogo, Skeleton, StateView, ExpandableCard
    Utils/  Overs.swift, SearchTokens.swift, Result+.swift
  Data/
    Models/  Match, MatchTeam, Player, PlayerProfile, Team, TeamMember, UserProfile
    Repositories/  MatchRepository, UserRepository, PlayerRepository, TeamRepository
    Services/  EdgeFunctions, NotificationService, DemoDataSeeder
  Features/
    Onboarding/  Auth/  Home/  CreateMatch/  Scoring/  MatchCenter/
    PlayerProfile/  Profile/  Settings/  Teams/
  Resources/
    Localizable.xcstrings, Assets.xcassets, Fonts/
CreaseEngine/                  // local Swift package
  Sources/CreaseEngine/  Engine.swift, Models/*.swift
  Tests/CreaseEngineTests/  GoldenFixturesTests.swift, Fixtures/*.json
```

## 3. Architecture

Use three layers, the same split the Flutter app has: Views talk to `@Observable` view models, view models talk to repositories, and repositories talk to Firestore or the edge functions. The scoring engine is a pure function that both the scorer and the match center call.

| Flutter | SwiftUI equivalent |
| --- | --- |
| `Cubit` / `Bloc` with `emit(state)` | `@Observable final class XViewModel` with stored properties |
| `BlocProvider` / `sl<T>()` | `@Environment(AppEnvironment.self)` |
| `Stream<T>` from Firestore | `AsyncThrowingStream<T, Error>` wrapping `addSnapshotListener` |
| `Result<T>` / `Failure` | Swift `throws` + a small `AppError` enum |
| `GoRouter` paths | `enum Route: Hashable` pushed onto `NavigationPath` |
| `registerFactoryParam` (per-match blocs) | Create the view model in the view's `@State` with the match ID |

&#91;embedded content: Crease architecture: iOS layers and backend services\]

View models replay events through `CreaseEngine` and read and write Firestore through repositories; the Supabase edge functions are only called for photo uploads and push requests.

### App entry

```swift
import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        // The Flutter app signs anonymous users out on launch; keep that behaviour.
        if Auth.auth().currentUser?.isAnonymous == true { try? Auth.auth().signOut() }
        NotificationService.shared.configure(application: app)
        return true
    }

    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Messaging.messaging().apnsToken = token
        Auth.auth().setAPNSToken(token, type: .unknown) // lets phone auth skip reCAPTCHA
    }

    func application(_ app: UIApplication, didReceiveRemoteNotification info: [AnyHashable: Any],
                     fetchCompletionHandler done: @escaping (UIBackgroundFetchResult) -> Void) {
        if Auth.auth().canHandleNotification(info) { done(.noData); return }
        done(.newData)
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Auth.auth().canHandle(url)
    }
}

@main
struct CreaseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.router)
                .environment(env.session)
                .environment(env.settings)
        }
    }
}
```

### Environment (replaces get\_it)

```swift
@MainActor @Observable
final class AppEnvironment {
    let db = Firestore.firestore()
    let engine = CreaseEngine()
    let functions = EdgeFunctions(baseURL: AppConfig.functionsBaseURL)
    lazy var matches = MatchRepository(db: db)
    lazy var users = UserRepository(db: db)
    lazy var players = PlayerRepository(db: db, functions: functions)
    lazy var teams = TeamRepository(db: db)

    let router = Router()
    let settings = SettingsStore()
    lazy var session = SessionStore(users: users, players: players) // replaces ProfileCubit

    init() {
        NotificationService.shared.onOpenRoute = { [router] path in router.open(path: path) }
        NotificationService.shared.flushPendingRoute()   // a tap that cold-launched the app
        // Optional demo matches, see 13.2:
        // #if DEBUG Task { await DemoDataSeeder(repo: matches, engine: engine).seedIfEmpty() } #endif
    }
}
```

### Routing (replaces go\_router)

Keep the same paths so the `route` string inside push notifications (`/teams`, `/teams/{id}`, `/match/{id}`, `/scoring/{id}`, `/`) still works.

```swift
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

@MainActor @Observable
final class Router {
    var path = NavigationPath()

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path = NavigationPath() }

    /// Maps the go_router style strings used by push notifications.
    func open(path string: String) {
        let parts = string.split(separator: "/").map(String.init)
        switch parts.count {
        case 0: popToRoot()
        case 1 where parts[0] == "teams": push(.teams)
        case 1 where parts[0] == "profile": push(.profile)
        case 2 where parts[0] == "teams": push(.team(id: parts[1]))
        case 2 where parts[0] == "match": push(.matchCenter(matchID: parts[1]))
        case 2 where parts[0] == "scoring": push(.scoring(matchID: parts[1]))
        default: break
        }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var router = router
        Group {
            if !settings.onboardingSeen {
                WelcomeView()
            } else {
                NavigationStack(path: $router.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .createMatch: CreateMatchWizard()
                            case .scoring(let id): ScoringView(matchID: id)
                            case .matchCenter(let id): MatchCenterView(matchID: id)
                            case .login(let redirect): PhoneLoginView(redirect: redirect)
                            case .profile: ProfileView()
                            case .playerProfileSetup(let r): PlayerProfileFormView(setup: true, redirect: r)
                            case .playerProfileEdit: PlayerProfileFormView(setup: false, redirect: nil)
                            case .teams: TeamsView()
                            case .team(let id): TeamView(teamID: id)
                            }
                        }
                }
            }
        }
        .preferredColorScheme(settings.colorScheme)
        .environment(\.locale, settings.locale)
    }
}
```

### Auth gate (replaces `withPhoneAuth`)

```swift
extension Router {
    func requireAuth(_ session: SessionStore, redirect: String? = nil, _ action: () -> Void) {
        session.isSignedIn ? action() : push(.login(redirect: redirect))
    }
}
```

### Firestore streams

Every repository `watch...` method follows this pattern. Cancel the task that iterates it in `.task {}` and SwiftUI stops the listener for you when the view disappears.

```swift
extension Query {
    func stream<T>(_ map: @escaping (QuerySnapshot) throws -> T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let reg = addSnapshotListener { snap, error in
                if let error { continuation.finish(throwing: error); return }
                guard let snap else { return }
                do { continuation.yield(try map(snap)) } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in reg.remove() }
        }
    }
}

extension DocumentReference {
    func stream<T: Decodable>(_ type: T.Type) -> AsyncThrowingStream<T?, Error> {
        AsyncThrowingStream { continuation in
            let reg = addSnapshotListener { snap, error in
                if let error { continuation.finish(throwing: error); return }
                guard let snap, snap.exists else { continuation.yield(nil); return }
                do { continuation.yield(try snap.data(as: T.self)) } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in reg.remove() }
        }
    }
}
```

## 4. Design system

The look is a deep pitch green brand (`#0F3B29`) with a lime accent (`#C9F24B`), off-white cards with 18 pt corners, Bricolage Grotesque headings, Geist body text and Geist Mono for every score. Copy these tokens exactly from `lib/core/theme/app_palette.dart`.

### Colour tokens

| Token | Light | Dark | Used for |
| --- | --- | --- | --- |
| bg | `#F4F5F5` | `#0B0E0C` | Screen background |
| surface | `#FFFFFF` | `#141915` | Cards, sheets, tab bar |
| surface2 | `#F6F7F6` | `#191F1A` | Skeleton highlight |
| sunk | `#EFF1F0` | `#1E251F` | Text fields, neutral ball chips |
| ink | `#141813` | `#ECEFE8` | Primary text |
| ink2 | `#4B5148` | `#B1B8AC` | Secondary text |
| ink3 | `#83887D` | `#778073` | Muted labels, section headers |
| line | `#E6E8E6` | `#232A24` | Dividers |
| line2 | `#D6DAD7` | `#2F3830` | Stronger borders |
| brand | `#0F3B29` | `#0E2A1D` | Nav bar and header band |
| brand2 | `#17503A` | `#153B29` | Batting team score |
| btn | `#0F3B29` | `#1F7A52` | Filled buttons |
| onBrand | `#F2F5EF` | `#ECF2E9` | Text on brand |
| onBrand2 | `#F2F5EF` at 62% | `#ECF2E9` at 58% | Muted text on brand |
| accent | `#C9F24B` | `#C9F24B` | FAB, selected chips, logo |
| onAccent | `#142309` | `#142309` | Text on accent |
| live | `#E5322D` | `#FF5A4E` | Live dot, reminders |
| four | `#1D5FD1` | `#5B8DEF` | Boundary 4 chip |
| six | `#0F7A4E` | `#3FBF7F` | Six chip, result text |
| wkt | `#D0263A` | `#F0556A` | Wicket chip, errors |
| extra | `#A86A12` | `#E0A640` | Extras chips, pending |
| chart1 | `#2A62D4` | `#4F82E6` | Worm/Manhattan team 1 |
| chart2 | `#C9650F` | `#C97320` | Worm/Manhattan team 2 |

```swift
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    /// Resolves per colour scheme, like Flutter's AppPalette.light / .dark.
    static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark, alpha: darkAlpha))
                : UIColor(Color(hex: light, alpha: lightAlpha))
        })
    }
}

enum Palette {
    static let bg = Color.dynamic(0xF4F5F5, 0x0B0E0C)
    static let surface = Color.dynamic(0xFFFFFF, 0x141915)
    static let surface2 = Color.dynamic(0xF6F7F6, 0x191F1A)
    static let sunk = Color.dynamic(0xEFF1F0, 0x1E251F)
    static let ink = Color.dynamic(0x141813, 0xECEFE8)
    static let ink2 = Color.dynamic(0x4B5148, 0xB1B8AC)
    static let ink3 = Color.dynamic(0x83887D, 0x778073)
    static let line = Color.dynamic(0xE6E8E6, 0x232A24)
    static let line2 = Color.dynamic(0xD6DAD7, 0x2F3830)
    static let brand = Color.dynamic(0x0F3B29, 0x0E2A1D)
    static let brand2 = Color.dynamic(0x17503A, 0x153B29)
    static let btn = Color.dynamic(0x0F3B29, 0x1F7A52)
    static let onBrand = Color.dynamic(0xF2F5EF, 0xECF2E9)
    static let onBrand2 = Color.dynamic(0xF2F5EF, 0xECF2E9, lightAlpha: 0.62, darkAlpha: 0.58)
    static let accent = Color(hex: 0xC9F24B)
    static let onAccent = Color(hex: 0x142309)
    static let live = Color.dynamic(0xE5322D, 0xFF5A4E)
    static let four = Color.dynamic(0x1D5FD1, 0x5B8DEF)
    static let six = Color.dynamic(0x0F7A4E, 0x3FBF7F)
    static let wkt = Color.dynamic(0xD0263A, 0xF0556A)
    static let extra = Color.dynamic(0xA86A12, 0xE0A640)
    static let chart1 = Color.dynamic(0x2A62D4, 0x4F82E6)
    static let chart2 = Color.dynamic(0xC9650F, 0xC97320)
}
```

### Typography

| Style | Font | Size / weight | Where |
| --- | --- | --- | --- |
| Wordmark "crease" | Bricolage Grotesque | 22, ExtraBold, tracking -0.5 | Home nav bar |
| Welcome headline | Bricolage Grotesque | 38, ExtraBold, line height 1.08, tracking -1 | Welcome screen |
| Titles | Bricolage Grotesque | 20 to 24, Bold | Screen and sheet titles |
| Body | Geist | 13 to 16, Regular / Medium / SemiBold | Everything else |
| Section header | Geist | 11.5, SemiBold, tracking 1, uppercase | "LIVE 3" headers |
| Score | Geist Mono | 40, SemiBold, line height 1 | Scoreboard |
| Mono label | Geist Mono | 11 to 14, Medium | Ball chips, overs, counts |

Sinhala and Tamil glyphs are not in these fonts. iOS falls back to its system Sinhala and Tamil fonts automatically, so no extra font files are needed.

```swift
enum AppFont {
    // PostScript names: check with UIFont.fontNames(forFamilyName:) after adding the files.
    static func heading(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("BricolageGrotesque-Regular", size: size).weight(weight)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist-Regular", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("GeistMono-Regular", size: size).weight(weight)
    }
    static let score = mono(40, .semibold)
}
```

The three `.ttf` files are variable fonts, so `.weight()` selects the weight axis.

### Shapes and spacing

- Cards: `surface` fill, corner radius 18, shadow black 25% radius 1, padding 16 (top 10 on match cards).
- Filled buttons: height 48, radius 14, `btn` fill, `onBrand` text 15 SemiBold.
- Pill buttons (welcome, sign-in): height 56, capsule, `accent` fill or white 8% for secondary, 16 Bold.
- Text fields: `sunk` fill, radius 12, no border, padding 14.
- Bottom sheets: `surface`, top radius 22. Use `.presentationDetents` + `.presentationCornerRadius(22)`.
- Screen gutters 16, list item gap 10, section header padding 22 top / 10 bottom.
- Filter chips: height 32, capsule, padding 14, selected `accent` / `onAccent`, else white 8% / `onBrand2`.

### Reusable components

```swift
/// One delivery in an over: "0", "4", "6", "W", "wd", "nb+4", "lb1" ...
struct BallChip: View {
    let token: String
    var size: CGFloat = 26

    var body: some View {
        let s = style
        Text(token)
            .font(AppFont.mono(11, .semibold))
            .foregroundStyle(s.fg)
            .padding(.horizontal, 5)
            .frame(minWidth: size, minHeight: size, maxHeight: size)
            .background(Capsule().fill(s.bg))
            .overlay { if let b = s.border { Capsule().stroke(b, lineWidth: 1.5) } }
    }

    private var style: (bg: Color, fg: Color, border: Color?) {
        switch token {
        case "W": return (Palette.wkt, .white, nil)
        case "4": return (Palette.four, .white, nil)
        case "6": return (Palette.six, .white, nil)
        case "0", "•": return (Palette.sunk, Palette.ink3, nil)
        default:
            if token.hasPrefix("wd") || token.hasPrefix("nb") || token.hasPrefix("lb") || token.hasPrefix("b") {
                return (.clear, Palette.extra, Palette.extra)
            }
            return (Palette.sunk, Palette.ink2, nil)
        }
    }
}

struct PillButton: View {
    let title: LocalizedStringKey
    var secondary = false
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if loading { ProgressView().tint(secondary ? .white : Palette.onAccent) }
                else { Text(title).font(AppFont.body(16, .bold)) }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(secondary ? .white : Palette.onAccent)
            .background(Capsule().fill(secondary ? Color.white.opacity(0.08) : Palette.accent))
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .opacity(loading ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.2), value: loading)
    }
}

struct TeamBadge: View {
    let shortName: String
    let color: Color
    var logoURL: URL? = nil
    var image: UIImage? = nil      // freshly picked logo, before upload
    var size: CGFloat = 30
    var circular = false

    var body: some View {
        let shape = circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.3))
        ZStack {
            shape.fill(color)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if let logoURL {
                AsyncImage(url: logoURL) { $0.resizable().scaledToFill() } placeholder: { label }
            } else { label }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private var label: some View {
        Text(String(shortName.prefix(3)).uppercased())
            .font(AppFont.heading(size * 0.35, .bold))
            .tracking(0.3)
            .foregroundStyle(.white)
    }
}

struct PlayerAvatar: View {
    let name: String
    var photoURL: URL? = nil
    var size: CGFloat = 40
    var highlighted = false
    var teamColor: Color? = nil

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    var body: some View {
        let tc = teamColor ?? Palette.ink2
        ZStack {
            Circle().fill(highlighted ? Palette.accent : tc.opacity(0.16))
            if let photoURL {
                AsyncImage(url: photoURL) { $0.resizable().scaledToFill() } placeholder: { label(tc) }
            } else { label(tc) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func label(_ tc: Color) -> some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(AppFont.heading(size * 0.33, .bold))
            .foregroundStyle(highlighted ? Palette.brand : tc)
    }
}

/// Falls back to the cricketer illustration matching the player's gender.
struct PlayerPhoto: View {
    var photoURL: URL? = nil
    var image: UIImage? = nil
    var gender: Gender? = nil
    var size: CGFloat = 44

    var body: some View {
        let placeholder = Image(gender == .female ? "cricketer_female" : "cricketer").resizable().scaledToFill()
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if let photoURL {
                AsyncImage(url: photoURL) { $0.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// The three-stumps-and-bails mark, drawn on a 24 x 24 grid.
struct CreaseLogo: View {
    var size: CGFloat = 24
    var color: Color = Palette.accent

    var body: some View {
        Canvas { ctx, canvas in
            let k = canvas.width / 24
            func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
                let rect = CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
                ctx.fill(Path(roundedRect: rect, cornerRadius: r * k), with: .color(color))
            }
            bar(4.6, 7, 2.6, 14, 1.3); bar(10.7, 7, 2.6, 14, 1.3); bar(16.8, 7, 2.6, 14, 1.3)
            bar(4, 3.6, 7.8, 1.9, 0.95); bar(12.2, 3.6, 7.8, 1.9, 0.95)
        }
        .frame(width: size, height: size)
    }
}

struct PulsingDot: View {
    var color: Color = Palette.live
    @State private var dim = false
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .opacity(dim ? 0.35 : 1)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

struct Skeleton: View {
    var height: CGFloat = 16
    var radius: CGFloat = 8
    @State private var phase = false
    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(phase ? Palette.surface2 : Palette.sunk)
            .frame(height: height)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: phase)
            .onAppear { phase = true }
    }
}
```

Also build these small ones from the Flutter widgets of the same name: `ExpandableCard` (title, subtitle, chevron rotating 180 degrees over 0.18 s), `StateView` (skeleton list of 4 x 84 pt while loading, error icon + Retry on failure), and `FadeSlideIn` (opacity 0 to 1 and offset 16 to 0, staggered by `start` delay).

## 5. Backend: Firebase and Supabase

The backend already exists and the SwiftUI app reuses it unchanged. Firebase holds auth, data and push; Supabase only runs two edge functions and stores photos. Every edge function call carries the user's Firebase ID token, which the function verifies against Google's public keys.

### Firestore collections

| Collection | Doc ID | Written by | Read by |
| --- | --- | --- | --- |
| `matches` | UUID | Creator (`createdBy`) | Anyone if `isPublic`, else creator and `pendingOwnerIds` |
| `matches/{id}/events` | `"{seq}"` ("1", "2", ...) | Match creator only | Same as parent match |
| `users` | Firebase UID | That user | That user |
| `players` | Firebase UID | That user | Any signed-in user |
| `teams` | UUID | Owner (`ownerId`) | Any signed-in user |
| `teamMembers` | `"{teamId}_{playerId}"` | Owner invites, player accepts | Any signed-in user |

### Document shapes

`matches/{id}` (dates are ISO 8601 strings, not Firestore timestamps):

```json
{
  "format": "t20",                // t20 | t10 | odi | custom | softball | tapeBall | sixes
  "config": { "oversPerInnings": 20, "playersPerSide": 11, "ballsPerOver": 6,
              "maxOversPerBowler": 0, "isLimitedOvers": true },
  "teamA": { "side": "A", "name": "Kandy Kings", "shortName": "KAN", "color": 4285214624,
             "squad": [ { "id": "...", "name": "...", "role": "batter", "battingStyle": "rhb",
                          "bowlingStyle": "rightArmFast", "photoUrl": "..." } ],
             "captainId": "...", "wicketKeeperId": "...", "teamId": "...", "ownerId": "...", "logoUrl": "..." },
  "teamB": { "side": "B", ... },
  "createdAt": "2026-09-30T10:15:00.000",
  "venueName": "Asgiriya Stadium, Kandy",
  "toss": { "winnerSide": "A", "decision": "bat" },   // bat | bowl
  "status": "live",                // pending | upcoming | live | completed | abandoned
  "resultText": "Team A won by 12 runs",
  "winnerSide": "A",
  "createdBy": "<uid>",
  "isPublic": true,
  "scheduledAt": "2026-10-02T15:30:00.000Z",
  "pendingOwnerIds": ["<uid>"],
  "scores": { "A": { "runs": 154, "wickets": 6, "balls": 120 } },
  "battingSide": "B",
  "reminderSent": true            // set by the Cloud Function
}
```

`color` is a 32-bit ARGB integer (Flutter `Color.toARGB32()`). Convert with `Color(argb:)` in section 6.

`matches/{id}/events/{seq}`, one of six types keyed by `t`:

| `t` | Extra fields |
| --- | --- |
| `ball` | `strikerId`, `nonStrikerId`, `bowlerId`, `runsOffBat`, `extra` (wide, noBall, bye, legBye), `extraRuns`, `dismissal {type, bowlerId, fielderId}`, `dismissedPlayerId`, `incomingBatterId` |
| `retire` | `outgoingPlayerId`, `incomingPlayerId`, `isOut` |
| `swap` | none |
| `note` | `text` |
| `inningsEnd` | `reason` |
| `void` | `voidedSeq` |

All events also carry `seq` (int), `inn` (0 or 1) and `clientTs` (ISO string). Dismissal `type` is one of `bowled`, `caught`, `lbw`, `runOut`, `stumped`, `hitWicket`, `retiredOut`, `obstructing`.

`users/{uid}`: `uid`, `phone`, `name`, `createdAt`, `favoriteMatchIds[]`, `reminderMatchIds[]`, `fcmTokens[]`.

`players/{uid}`: `uid`, `name`, `gender` (male, female), `photoUrl`, `role` (batter, bowler, allRounder, wicketKeeper), `battingStyle` (rhb, lhb), `bowlingStyle` (none, rightArmFast, rightArmMedium, rightArmSpin, leftArmFast, leftArmMedium, leftArmSpin), `searchTokens[]`.

`teams/{id}`: `id`, `name`, `shortName`, `ownerId`, `ownerName`, `createdAt`, `logoUrl`, `searchTokens[]`.

`teamMembers/{teamId}_{playerId}`: `teamId`, `teamName`, `ownerId`, `ownerName`, `playerId`, `playerName`, `playerGender`, `playerPhotoUrl`, `teamLogoUrl`, `status` (pending, accepted), `invitedAt`.

### Search tokens

Firestore has no full-text search, so names are stored with every prefix of the full name and of each word. Search is `whereField("searchTokens", arrayContains: query.lowercased()).limit(to: 20)`.

```swift
func searchTokens(_ text: String) -> [String] {
    let full = text.trimmingCharacters(in: .whitespaces).lowercased()
    let words = full.split(whereSeparator: \.isWhitespace).map(String.init)
    var set = Set<String>()
    for word in [full] + words where !word.isEmpty {
        for i in 1...word.count { set.insert(String(word.prefix(i))) }
    }
    return Array(set)
}
```

### Security rules and indexes

Keep `firestore.rules` and `firestore.indexes.json` as they are; the iOS client must respect them. The rules that shape the client code:

- Only the match creator can append events or edit a match, except a pending team owner may change only `status` and `pendingOwnerIds` (confirm or decline).
- A new match with `pendingOwnerIds` must start with `status: "pending"`.
- A `teamMembers` doc ID must equal `teamId + "_" + playerId`, and only the team owner can create it.
- A player can only flip their own invite from `pending` to `accepted`. The owner can only change `teamLogoUrl`.

The home query uses `Filter.orFilter` on `isPublic`, `createdBy` and `pendingOwnerIds`, ordered by `createdAt` desc. The composite indexes for those already exist.

### Supabase edge functions

Base URL: `https://zopovxkefvavxxlhnwzs.supabase.co/functions/v1`. Both require `Authorization: Bearer <Firebase ID token>`.

| Function | Request | Response |
| --- | --- | --- |
| `upload-photo` | POST raw JPEG bytes (max 2 MB), `Content-Type: image/jpeg`, optional `?team=<teamId>` | `{ "url": "https://.../player-photos/<uid>.jpg?v=<ms>" }` |
| `notify` | POST JSON `{ "event": "...", ...ids }` | 200 empty, 403 if the caller is not allowed |

Player photos land at `player-photos/<uid>.jpg`; team logos at `player-photos/teams/<uid>/<teamId>.jpg`. The bucket is public.

`notify` events, each checked server-side against Firestore before sending FCM:

| Event | IDs | Sent by | Push goes to | Tap opens |
| --- | --- | --- | --- | --- |
| `team_invite` | `teamId`, `playerId` | Team owner after inviting | Invited player | `/teams` |
| `invite_accepted` | `teamId`, `playerId` | Player after accepting | Team owner | `/teams/{teamId}` |
| `match_request` | `matchId` | Match creator after creating a pending match | Each pending team owner | `/match/{matchId}` |
| `match_confirmed` | `matchId` | Team owner after confirming | Match creator | `/scoring/{matchId}` |
| `match_declined` | `matchId` | Team owner before declining | Match creator | `/` |

### Firebase Cloud Functions (`functions/index.js`)

- `onMatchStatusChange`: when a match flips to `live` or `completed`, sends to FCM topic `match_{matchId}` ("Match started" / "Match finished").
- `sendMatchReminders`: every 5 minutes, finds `upcoming` matches with `scheduledAt` within 15 minutes and sends to topic `reminder_{matchId}`, then sets `reminderSent: true`.

The iOS app subscribes to these topics when the user favorites a match or taps the bell.

## 6. Scoring engine, models and repositories

Port the engine first and prove it with the two golden fixtures before building any screen. It is the heart of the app: the scorer, the live tab, the scorecard, the summary and the demo seeder all call `CreaseEngine().replay(...)`.

### 6.1 CreaseEngine package: events

Dates written by Dart look like `2026-09-30T10:15:00.000` (local, no zone) or `...Z` (UTC). Parse both.

```swift
// CreaseEngine/Sources/CreaseEngine/Events.swift
import Foundation

public enum ISODate {
    nonisolated(unsafe) static let withZone: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) static let withZoneNoFraction = ISO8601DateFormatter()
    static let local: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"; return f
    }()
    public static func parse(_ s: String) -> Date? {
        withZone.date(from: s) ?? withZoneNoFraction.date(from: s) ?? local.date(from: String(s.prefix(23)))
    }
    public static func string(_ d: Date) -> String { withZone.string(from: d) }
}

public enum ExtraType: String, Codable, Sendable { case wide, noBall, bye, legBye }

public enum DismissalType: String, Codable, Sendable, CaseIterable {
    case bowled, caught, lbw, runOut, stumped, hitWicket, retiredOut, obstructing
    public var creditsBowler: Bool { [.bowled, .caught, .lbw, .stumped, .hitWicket].contains(self) }
}

public struct Dismissal: Codable, Hashable, Sendable {
    public var type: DismissalType
    public var bowlerId: String?
    public var fielderId: String?
    public init(type: DismissalType, bowlerId: String? = nil, fielderId: String? = nil) {
        self.type = type; self.bowlerId = bowlerId; self.fielderId = fielderId
    }
}

public struct BallEvent: Hashable, Sendable {
    public var strikerId, nonStrikerId, bowlerId: String
    public var runsOffBat = 0
    public var extra: ExtraType? = nil
    public var extraRuns = 0
    public var dismissal: Dismissal? = nil
    public var dismissedPlayerId: String? = nil
    public var incomingBatterId: String? = nil

    public var isLegal: Bool { extra != .wide && extra != .noBall }
    public var battingTeamRuns: Int { runsOffBat + extraRuns + (isLegal ? 0 : 1) }
    public var bowlerConcededRuns: Int {
        switch extra {
        case .bye, .legBye: 0
        case .wide: 1 + extraRuns
        case .noBall: 1 + runsOffBat
        case nil: runsOffBat
        }
    }
    public var runsForStrikeRotation: Int {
        switch extra { case .bye, .legBye, .wide: extraRuns; default: runsOffBat }
    }
}

public enum EventKind: Hashable, Sendable {
    case ball(BallEvent)
    case retire(outgoing: String, incoming: String, isOut: Bool)
    case swap
    case note(String)
    case inningsEnd(reason: String)
    case void(seq: Int)
}

public struct MatchEvent: Hashable, Sendable, Codable {
    public var seq: Int
    public var inningsIndex: Int
    public var clientTs: Date
    public var kind: EventKind

    public init(seq: Int, inningsIndex: Int, clientTs: Date = .now, kind: EventKind) {
        self.seq = seq; self.inningsIndex = inningsIndex; self.clientTs = clientTs; self.kind = kind
    }

    enum K: String, CodingKey {
        case t, seq, inn, clientTs, strikerId, nonStrikerId, bowlerId, runsOffBat, extra, extraRuns,
             dismissal, dismissedPlayerId, incomingBatterId, outgoingPlayerId, incomingPlayerId, isOut,
             text, reason, voidedSeq
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        seq = try c.decode(Int.self, forKey: .seq)
        inningsIndex = try c.decode(Int.self, forKey: .inn)
        clientTs = ISODate.parse(try c.decode(String.self, forKey: .clientTs)) ?? .distantPast
        switch try c.decode(String.self, forKey: .t) {
        case "ball":
            kind = .ball(BallEvent(
                strikerId: try c.decode(String.self, forKey: .strikerId),
                nonStrikerId: try c.decode(String.self, forKey: .nonStrikerId),
                bowlerId: try c.decode(String.self, forKey: .bowlerId),
                runsOffBat: try c.decodeIfPresent(Int.self, forKey: .runsOffBat) ?? 0,
                extra: try c.decodeIfPresent(ExtraType.self, forKey: .extra),
                extraRuns: try c.decodeIfPresent(Int.self, forKey: .extraRuns) ?? 0,
                dismissal: try c.decodeIfPresent(Dismissal.self, forKey: .dismissal),
                dismissedPlayerId: try c.decodeIfPresent(String.self, forKey: .dismissedPlayerId),
                incomingBatterId: try c.decodeIfPresent(String.self, forKey: .incomingBatterId)))
        case "retire":
            kind = .retire(outgoing: try c.decode(String.self, forKey: .outgoingPlayerId),
                           incoming: try c.decode(String.self, forKey: .incomingPlayerId),
                           isOut: try c.decodeIfPresent(Bool.self, forKey: .isOut) ?? false)
        case "swap": kind = .swap
        case "note": kind = .note(try c.decode(String.self, forKey: .text))
        case "inningsEnd": kind = .inningsEnd(reason: try c.decode(String.self, forKey: .reason))
        case "void": kind = .void(seq: try c.decode(Int.self, forKey: .voidedSeq))
        case let t: throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "Unknown event \(t)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(seq, forKey: .seq)
        try c.encode(inningsIndex, forKey: .inn)
        try c.encode(ISODate.string(clientTs), forKey: .clientTs)
        switch kind {
        case .ball(let b):
            try c.encode("ball", forKey: .t)
            try c.encode(b.strikerId, forKey: .strikerId)
            try c.encode(b.nonStrikerId, forKey: .nonStrikerId)
            try c.encode(b.bowlerId, forKey: .bowlerId)
            try c.encode(b.runsOffBat, forKey: .runsOffBat)
            try c.encodeIfPresent(b.extra, forKey: .extra)
            try c.encode(b.extraRuns, forKey: .extraRuns)
            try c.encodeIfPresent(b.dismissal, forKey: .dismissal)
            try c.encodeIfPresent(b.dismissedPlayerId, forKey: .dismissedPlayerId)
            try c.encodeIfPresent(b.incomingBatterId, forKey: .incomingBatterId)
        case .retire(let o, let i, let out):
            try c.encode("retire", forKey: .t)
            try c.encode(o, forKey: .outgoingPlayerId); try c.encode(i, forKey: .incomingPlayerId)
            try c.encode(out, forKey: .isOut)
        case .swap: try c.encode("swap", forKey: .t)
        case .note(let text): try c.encode("note", forKey: .t); try c.encode(text, forKey: .text)
        case .inningsEnd(let r): try c.encode("inningsEnd", forKey: .t); try c.encode(r, forKey: .reason)
        case .void(let s): try c.encode("void", forKey: .t); try c.encode(s, forKey: .voidedSeq)
        }
    }
}
```

### 6.2 CreaseEngine package: state

```swift
// CreaseEngine/Sources/CreaseEngine/State.swift
public struct MatchConfig: Codable, Hashable, Sendable {
    public var oversPerInnings: Int
    public var playersPerSide: Int
    public var ballsPerOver = 6
    public var maxOversPerBowler = 0          // 0 = no limit
    public var isLimitedOvers = true
    // Custom init(from:) uses decodeIfPresent with these defaults, as MatchConfig.fromJson does.
}

public struct BatterInnings: Hashable, Sendable {
    public let playerId: String
    public var runs = 0, balls = 0, fours = 0, sixes = 0
    public var isOut = false, retiredNotOut = false
    public var dismissal: Dismissal? = nil
    public var strikeRate: Double { balls == 0 ? 0 : Double(runs) / Double(balls) * 100 }
    public var didBat: Bool { balls > 0 || runs > 0 || isOut || retiredNotOut }
}

public struct BowlerSpell: Hashable, Sendable {
    public let playerId: String
    public var legalBalls = 0, runsConceded = 0, wickets = 0, maidens = 0
    public func overs(_ bpo: Int) -> String { "\(legalBalls / bpo).\(legalBalls % bpo)" }
    public func economy(_ bpo: Int) -> Double {
        legalBalls == 0 ? 0 : Double(runsConceded) / (Double(legalBalls) / Double(bpo))
    }
}

public struct InningsState: Hashable, Sendable {
    public let index: Int
    public let battingTeam: String          // "A" or "B"
    public let bowlingTeam: String
    public var runs = 0, wickets = 0, legalBalls = 0
    public var batters: [String: BatterInnings] = [:]
    public var bowlers: [String: BowlerSpell] = [:]
    public var battingOrder: [String] = []
    public var strikerId: String?, nonStrikerId: String?, currentBowlerId: String?
    public var currentOverBalls: [String] = []
    public var overHistory: [[String]] = []
    public var closed = false
    public var endReason: String?
    public var target: Int?

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
    public var current: InningsState? { innings.first { $0.index == currentInningsIndex } }
}
```

### 6.3 CreaseEngine package: replay

This is a line-for-line port of `packages/crease_engine/lib/src/engine.dart`. Keep every rule:

- Sort by `seq`; skip any event a `void` points at, and skip `void` events themselves.
- The second innings' target is first-innings runs + 1, fixed when its first event arrives.
- Wides and no-balls are not legal and do not count as balls faced. Byes and leg byes do count as faced.
- Runs off the bat on a no-ball go to the batter; the bowler concedes 1 + bat runs on a no-ball, 1 + extra runs on a wide, nothing for byes.
- Odd runs swap strike (byes, leg byes and wides use `extraRuns`). The end of a legal over swaps strike again.
- A maiden is an over in which the bowler conceded 0.
- Auto-close an innings on all out (`playersPerSide - 1` wickets), target reached, or overs completed, in that order.
- Result text is exactly `Match tied`, `Team B won by 3 wickets` or `Team A won by 12 runs` (singular for 1). The UI later swaps `Team A` for the team name.

```swift
// CreaseEngine/Sources/CreaseEngine/CreaseEngine.swift
public struct CreaseEngine: Sendable {
    public init() {}

    public func replay(events: [MatchEvent], config: MatchConfig, inningsBattingTeam: [String]) -> MatchState {
        let voided = Set(events.compactMap { if case .void(let s) = $0.kind { s } else { nil } })
        var builders: [Int: InningsBuilder] = [:]
        var notes: [String] = []
        var current = 0

        for e in events.sorted(by: { $0.seq < $1.seq }) {
            if voided.contains(e.seq) { continue }
            if case .void = e.kind { continue }

            if builders[e.inningsIndex] == nil {
                let target = (e.inningsIndex == 1) ? builders[0].map { $0.runs + 1 } : nil
                builders[e.inningsIndex] = InningsBuilder(
                    index: e.inningsIndex,
                    battingTeam: inningsBattingTeam[e.inningsIndex],
                    bowlingTeam: inningsBattingTeam[1 - e.inningsIndex],
                    ballsPerOver: config.ballsPerOver, target: target)
            }
            current = e.inningsIndex
            var b = builders[e.inningsIndex]!

            switch e.kind {
            case .ball(let ball): b.apply(ball)
            case .retire(let o, let i, let out): b.retire(outgoing: o, incoming: i, isOut: out)
            case .swap: b.swapEnds()
            case .note(let text): notes.append(text)
            case .inningsEnd(let reason): b.close(reason)
            case .void: break
            }
            if !b.closed { autoClose(&b, config) }
            builders[e.inningsIndex] = b
        }

        let innings = builders.values.map(\.state).sorted { $0.index < $1.index }
        var state = MatchState(currentInningsIndex: current, innings: innings, notes: notes)
        state.result = result(state, config)
        return state
    }

    private func autoClose(_ b: inout InningsBuilder, _ c: MatchConfig) {
        if b.wickets >= c.playersPerSide - 1 { b.close("all out") }
        else if let t = b.target, b.runs >= t { b.close("target reached") }
        else if c.isLimitedOvers && b.legalBalls >= c.oversPerInnings * c.ballsPerOver { b.close("overs completed") }
    }

    public func result(_ s: MatchState, _ c: MatchConfig) -> MatchResult? {
        guard s.innings.count >= 2, s.innings[0].closed, s.innings[1].closed else { return nil }
        let first = s.innings[0], second = s.innings[1]
        if first.runs == second.runs { return MatchResult(type: .tie, winner: nil, text: "Match tied") }
        if second.runs > first.runs {
            let w = c.playersPerSide - 1 - second.wickets
            return MatchResult(type: .win, winner: second.battingTeam,
                               text: "Team \(second.battingTeam) won by \(w) wicket\(w == 1 ? "" : "s")")
        }
        let m = first.runs - second.runs
        return MatchResult(type: .win, winner: first.battingTeam,
                           text: "Team \(first.battingTeam) won by \(m) run\(m == 1 ? "" : "s")")
    }
}

struct InningsBuilder {
    var state: InningsState
    let ballsPerOver: Int
    var overBowlerRuns = 0
    var runs: Int { state.runs }
    var wickets: Int { state.wickets }
    var legalBalls: Int { state.legalBalls }
    var target: Int? { state.target }
    var closed: Bool { state.closed }

    init(index: Int, battingTeam: String, bowlingTeam: String, ballsPerOver: Int, target: Int?) {
        state = InningsState(index: index, battingTeam: battingTeam, bowlingTeam: bowlingTeam, target: target)
        self.ballsPerOver = ballsPerOver
    }

    private mutating func batter(_ id: String) {
        if state.batters[id] == nil { state.batters[id] = BatterInnings(playerId: id); state.battingOrder.append(id) }
    }
    private mutating func bowler(_ id: String) {
        if state.bowlers[id] == nil { state.bowlers[id] = BowlerSpell(playerId: id) }
    }
    mutating func swapEnds() { if !closed { swap(&state.strikerId, &state.nonStrikerId) } }
    mutating func close(_ reason: String) { state.closed = true; state.endReason = reason }

    mutating func apply(_ e: BallEvent) {
        guard !closed else { return }
        state.strikerId = e.strikerId; state.nonStrikerId = e.nonStrikerId; state.currentBowlerId = e.bowlerId
        batter(e.strikerId); batter(e.nonStrikerId); bowler(e.bowlerId)
        state.runs += e.battingTeamRuns

        var s = state.batters[e.strikerId]!
        if e.extra == nil || e.extra == .bye || e.extra == .legBye { s.balls += 1 }
        if e.extra == nil || (e.extra == .noBall && e.runsOffBat > 0) {
            s.runs += e.runsOffBat
            if e.runsOffBat == 4 { s.fours += 1 }
            if e.runsOffBat == 6 { s.sixes += 1 }
        }
        state.batters[e.strikerId] = s

        state.bowlers[e.bowlerId]!.runsConceded += e.bowlerConcededRuns
        if e.isLegal { state.bowlers[e.bowlerId]!.legalBalls += 1; state.legalBalls += 1 }
        overBowlerRuns += e.bowlerConcededRuns
        state.currentOverBalls.append(token(e))

        if e.runsForStrikeRotation % 2 == 1 { swap(&state.strikerId, &state.nonStrikerId) }

        if let d = e.dismissal, let outId = e.dismissedPlayerId {
            state.batters[outId]?.isOut = true
            state.batters[outId]?.dismissal = d
            state.wickets += 1
            if d.type.creditsBowler { state.bowlers[e.bowlerId]!.wickets += 1 }
            if let inc = e.incomingBatterId {
                if state.strikerId == outId { state.strikerId = inc }
                else if state.nonStrikerId == outId { state.nonStrikerId = inc }
                batter(inc)
            }
        }

        if e.isLegal && state.legalBalls % ballsPerOver == 0 {
            state.overHistory.append(state.currentOverBalls)
            state.currentOverBalls = []
            if overBowlerRuns == 0 { state.bowlers[e.bowlerId]!.maidens += 1 }
            overBowlerRuns = 0
            swap(&state.strikerId, &state.nonStrikerId)
        }
    }

    mutating func retire(outgoing: String, incoming: String, isOut: Bool) {
        guard !closed else { return }
        if state.batters[outgoing] != nil {
            state.batters[outgoing]!.retiredNotOut = !isOut
            state.batters[outgoing]!.isOut = isOut
        }
        batter(incoming)
        if state.strikerId == outgoing { state.strikerId = incoming }
        if state.nonStrikerId == outgoing { state.nonStrikerId = incoming }
    }

    private func token(_ e: BallEvent) -> String {
        if e.dismissal != nil { return "W" }
        switch e.extra {
        case .wide: return e.extraRuns > 0 ? "wd+\(e.extraRuns)" : "wd"
        case .noBall: return e.runsOffBat > 0 ? "nb+\(e.runsOffBat)" : "nb"
        case .bye: return "b\(e.extraRuns)"
        case .legBye: return "lb\(e.extraRuns)"
        case nil: return "\(e.runsOffBat)"
        }
    }
}
```

### 6.4 Golden fixture tests

Copy `packages/crease_engine/test/fixtures/*.json` into `Tests/CreaseEngineTests/Fixtures` and declare them as resources in `Package.swift` (`resources: [.copy("Fixtures")]`).

```swift
import Testing
import Foundation
@testable import CreaseEngine

struct Fixture: Decodable {
    struct Expected: Decodable {
        struct Inn: Decodable { let runs: Int; let wickets: Int; let closed: Bool; let endReason: String? }
        struct Res: Decodable { let type: String; let winner: String?; let text: String }
        let innings: [Inn]; let result: Res
    }
    let config: MatchConfig; let inningsBattingTeam: [String]; let events: [MatchEvent]; let expected: Expected
}

@Test(arguments: ["simple_result", "extras_and_tie"])
func goldenFixture(name: String) throws {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    let s = CreaseEngine().replay(events: f.events, config: f.config, inningsBattingTeam: f.inningsBattingTeam)
    #expect(s.innings.count == f.expected.innings.count)
    for (i, e) in f.expected.innings.enumerated() {
        #expect(s.innings[i].runs == e.runs); #expect(s.innings[i].wickets == e.wickets)
        #expect(s.innings[i].closed == e.closed); #expect(s.innings[i].endReason == e.endReason)
    }
    #expect(s.result?.type.rawValue == f.expected.result.type)
    #expect(s.result?.winner == f.expected.result.winner)
    #expect(s.result?.text == f.expected.result.text)
}
```

### 6.5 App models

Use `Codable` structs with the exact Firestore field names. Dates stay `String` on the wire (Dart wrote ISO strings, not Timestamps), so expose computed `Date` properties. The match document ID is not stored inside the document, so `Match.id` is left out of `CodingKeys` and filled in after decoding.

```swift
import SwiftUI
import FirebaseFirestore
import CreaseEngine

enum MatchFormat: String, Codable, CaseIterable {
    case t20, t10, odi, custom, softball, tapeBall, sixes
    var defaultOvers: Int {
        switch self { case .t20, .custom: 20; case .t10: 10; case .odi: 50; case .softball: 8; case .tapeBall: 12; case .sixes: 6 }
    }
    var defaultPlayersPerSide: Int { self == .softball ? 8 : 11 }
}
enum MatchStatus: String, Codable { case pending, upcoming, live, completed, abandoned }
enum TossDecision: String, Codable { case bat, bowl }
enum PlayerRole: String, Codable, CaseIterable { case batter, bowler, allRounder, wicketKeeper }
enum BattingStyle: String, Codable, CaseIterable { case rhb, lhb }
enum BowlingStyle: String, Codable, CaseIterable {
    case none, rightArmFast, rightArmMedium, rightArmSpin, leftArmFast, leftArmMedium, leftArmSpin
}
enum Gender: String, Codable, CaseIterable { case male, female }
enum MemberStatus: String, Codable { case pending, accepted }

extension Color {
    /// Flutter stores colours as 32-bit ARGB ints.
    init(argb: Int) {
        let v = UInt32(truncatingIfNeeded: argb)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: Double((v >> 24) & 0xFF) / 255)
    }
}

struct Player: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var role: PlayerRole = .batter
    var battingStyle: BattingStyle = .rhb
    var bowlingStyle: String?
    var photoUrl: String?
}

struct MatchTeam: Codable, Hashable {
    var side: String                 // "A" | "B"
    var name: String
    var shortName: String
    var color: Int                   // ARGB
    var squad: [Player]
    var captainId: String?
    var wicketKeeperId: String?
    var teamId: String?
    var ownerId: String?
    var logoUrl: String?
    var uiColor: Color { Color(argb: color) }
}

struct TeamScore: Codable, Hashable {
    var runs: Int, wickets: Int, balls: Int
    func overs(_ bpo: Int) -> String { "\(balls / bpo).\(balls % bpo)" }
}

struct Toss: Codable, Hashable { var winnerSide: String; var decision: TossDecision }

struct Match: Codable, Hashable, Identifiable {
    var id = ""                      // document ID, not encoded
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

    var createdDate: Date { ISODate.parse(createdAt) ?? .now }
    var scheduledDate: Date? { scheduledAt.flatMap(ISODate.parse) }
    func team(_ side: String) -> MatchTeam { side == "A" ? teamA : teamB }

    func isVisible(to uid: String?) -> Bool {
        guard status == .pending else { return true }
        guard let uid else { return false }
        return createdBy == uid || pendingOwnerIds.contains(uid)
    }

    /// Which side bats in innings 0 and 1, from the toss.
    var inningsBattingOrder: [String] {
        guard let toss else { return ["A", "B"] }
        let other = toss.winnerSide == "A" ? "B" : "A"
        let first = toss.decision == .bat ? toss.winnerSide : other
        return first == "A" ? ["A", "B"] : ["B", "A"]
    }

    /// "Team A won by 12 runs" -> "KAN won by 12 runs"
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
    func match() throws -> Match { var m = try data(as: Match.self); m.id = documentID; return m }
}

struct UserProfile: Codable, Hashable {
    var uid: String
    var phone: String = ""
    var name: String = ""
    var createdAt: String
    var favoriteMatchIds: [String] = []
    var reminderMatchIds: [String] = []
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
}

struct Team: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var shortName: String
    var ownerId: String
    var ownerName: String = ""
    var createdAt: String
    var logoUrl: String?
    var searchTokens: [String] = []
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
    static func docID(_ team: String, _ player: String) -> String { "\(team)_\(player)" }
}
```

Fields that Dart reads with a fallback (`json['x'] as String? ?? 'default'`) need the same default in Swift. Synthesized `Decodable` ignores property defaults, so write a custom `init(from:)` with `decodeIfPresent(...) ?? default` for `Match.status`, `isPublic`, `pendingOwnerIds`, `scores`, `Player.role`, `battingStyle`, `PlayerProfile.gender`, `role`, `battingStyle`, `bowlingStyle`, `UserProfile.phone`, `name`, the two ID lists, and `MatchConfig.ballsPerOver`, `maxOversPerBowler`, `isLimitedOvers`. Otherwise older documents will fail to decode.

### 6.6 Repositories

```swift
import FirebaseFirestore

struct MatchRepository {
    let db: Firestore
    var matches: CollectionReference { db.collection("matches") }
    func events(_ id: String) -> CollectionReference { matches.document(id).collection("events") }

    /// Public matches + mine + ones waiting on my confirmation, newest first.
    func watchMatches(uid: String?) -> AsyncThrowingStream<[Match], Error> {
        let base: Query
        if let uid {
            base = matches.whereFilter(.orFilter([
                .whereField("isPublic", isEqualTo: true),
                .whereField("createdBy", isEqualTo: uid),
                .whereField("pendingOwnerIds", arrayContains: uid),
            ]))
        } else {
            base = matches.whereField("isPublic", isEqualTo: true)
        }
        return base.order(by: "createdAt", descending: true).stream { snap in
            try snap.documents.map { try $0.match() }.filter { $0.isVisible(to: uid) }
        }
    }

    func watchMatch(_ id: String) -> AsyncThrowingStream<Match?, Error> {
        AsyncThrowingStream { c in
            let reg = matches.document(id).addSnapshotListener { s, e in
                if let e { c.finish(throwing: e); return }
                guard let s else { return }
                c.yield(s.exists ? try? s.match() : nil)
            }
            c.onTermination = { _ in reg.remove() }
        }
    }
    func getMatch(_ id: String) async throws -> Match? {
        let s = try await matches.document(id).getDocument()
        return s.exists ? try s.match() : nil
    }
    func create(_ m: Match) throws { try matches.document(m.id).setData(from: m) }
    func update(_ m: Match) throws { try matches.document(m.id).setData(from: m, merge: true) }

    func loadEvents(_ id: String, afterSeq: Int? = nil) async throws -> [MatchEvent] {
        var q: Query = events(id).order(by: "seq")
        if let afterSeq { q = q.whereField("seq", isGreaterThan: afterSeq) }
        return try await q.getDocuments().documents.map { try $0.data(as: MatchEvent.self) }
    }

    /// The live tab and scorecard listen to the event log directly.
    func watchEvents(_ id: String) -> AsyncThrowingStream<[MatchEvent], Error> {
        events(id).order(by: "seq").stream { try $0.documents.map { try $0.data(as: MatchEvent.self) } }
    }

    func append(_ id: String, _ e: MatchEvent) throws {
        try events(id).document("\(e.seq)").setData(from: e)
    }

    func delete(_ id: String) async throws {
        let batch = db.batch()
        for d in try await events(id).getDocuments().documents { batch.deleteDocument(d.reference) }
        batch.deleteDocument(matches.document(id))
        try await batch.commit()
    }
}

struct UserRepository {
    let db: Firestore
    func doc(_ uid: String) -> DocumentReference { db.collection("users").document(uid) }
    func watch(_ uid: String) -> AsyncThrowingStream<UserProfile?, Error> { doc(uid).stream(UserProfile.self) }
    func get(_ uid: String) async throws -> UserProfile? {
        let s = try await doc(uid).getDocument()
        // A doc that only holds fcmTokens is not a profile yet.
        return s.data()?["createdAt"] == nil ? nil : try s.data(as: UserProfile.self)
    }
    func save(_ p: UserProfile) throws { try doc(p.uid).setData(from: p, merge: true) }
    func setFavorite(_ uid: String, _ matchID: String, _ on: Bool) async throws {
        try await doc(uid).setData(["favoriteMatchIds": on ? FieldValue.arrayUnion([matchID]) : FieldValue.arrayRemove([matchID])], merge: true)
    }
    func setReminder(_ uid: String, _ matchID: String, _ on: Bool) async throws {
        try await doc(uid).setData(["reminderMatchIds": on ? FieldValue.arrayUnion([matchID]) : FieldValue.arrayRemove([matchID])], merge: true)
    }
    func addFCMToken(_ uid: String, _ token: String) async throws {
        try await doc(uid).setData(["fcmTokens": FieldValue.arrayUnion([token])], merge: true)
    }
}

struct PlayerRepository {
    let db: Firestore
    let functions: EdgeFunctions
    var players: CollectionReference { db.collection("players") }

    func watch(_ uid: String) -> AsyncThrowingStream<PlayerProfile?, Error> { players.document(uid).stream(PlayerProfile.self) }
    func get(_ uid: String) async throws -> PlayerProfile? {
        let s = try await players.document(uid).getDocument()
        return s.exists ? try s.data(as: PlayerProfile.self) : nil
    }
    func save(_ p: PlayerProfile, photo: Data? = nil) async throws {
        var p = p
        if let photo { p.photoUrl = try await functions.uploadPhoto(photo) }
        p.searchTokens = searchTokens(p.name)
        try players.document(p.uid).setData(from: p)
    }
    func search(_ query: String) async throws -> [PlayerProfile] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return [] }
        return try await players.whereField("searchTokens", arrayContains: term).limit(to: 20)
            .getDocuments().documents.map { try $0.data(as: PlayerProfile.self) }
    }
}

struct TeamRepository {
    let db: Firestore
    var teams: CollectionReference { db.collection("teams") }
    var members: CollectionReference { db.collection("teamMembers") }

    func watchTeam(_ id: String) -> AsyncThrowingStream<Team?, Error> { teams.document(id).stream(Team.self) }
    func watchMembers(team id: String) -> AsyncThrowingStream<[TeamMember], Error> {
        watch(members.whereField("teamId", isEqualTo: id))
    }
    func watchMemberships(player id: String) -> AsyncThrowingStream<[TeamMember], Error> {
        watch(members.whereField("playerId", isEqualTo: id))
    }
    private func watch(_ q: Query) -> AsyncThrowingStream<[TeamMember], Error> {
        q.stream { try $0.documents.map { try $0.data(as: TeamMember.self) }.sorted { $0.invitedAt < $1.invitedAt } }
    }
    func search(_ query: String) async throws -> [Team] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return [] }
        return try await teams.whereField("searchTokens", arrayContains: term).limit(to: 20)
            .getDocuments().documents.map { try $0.data(as: Team.self) }
    }
    func ownedBy(_ uid: String) async throws -> [Team] {
        try await teams.whereField("ownerId", isEqualTo: uid).getDocuments().documents.map { try $0.data(as: Team.self) }
    }
    func acceptedMembers(_ teamID: String) async throws -> [TeamMember] {
        try await members.whereField("teamId", isEqualTo: teamID).whereField("status", isEqualTo: "accepted")
            .getDocuments().documents.map { try $0.data(as: TeamMember.self) }.sorted { $0.invitedAt < $1.invitedAt }
    }
    /// Must be one batch: the teamMembers rule reads the new team with getAfter().
    func create(_ team: Team, owner: TeamMember) async throws {
        let b = db.batch()
        try b.setData(from: team, forDocument: teams.document(team.id))
        try b.setData(from: owner, forDocument: members.document(owner.id))
        try await b.commit()
    }
    func invite(_ m: TeamMember) throws { try members.document(m.id).setData(from: m) }
    func accept(_ m: TeamMember) async throws { try await members.document(m.id).updateData(["status": "accepted"]) }
    func remove(_ m: TeamMember) async throws { try await members.document(m.id).delete() }
    func setLogo(_ teamID: String, url: String) async throws {
        let b = db.batch()
        b.updateData(["logoUrl": url], forDocument: teams.document(teamID))
        for d in try await members.whereField("teamId", isEqualTo: teamID).getDocuments().documents {
            b.updateData(["teamLogoUrl": url], forDocument: d.reference)
        }
        try await b.commit()
    }
}
```

Firestore `setData(from:)` without `await` writes to the local cache immediately and syncs in the background. That is what keeps scoring instant on a weak signal; keep it for `append` and `update`.

### 6.7 Edge functions client

```swift
import FirebaseAuth

struct EdgeFunctions {
    let baseURL: URL

    func uploadPhoto(_ jpeg: Data, teamID: String? = nil) async throws -> String {
        var url = baseURL.appending(path: "upload-photo")
        if let teamID { url.append(queryItems: [URLQueryItem(name: "team", value: teamID)]) }
        let data = try await post(url, contentType: "image/jpeg", body: jpeg)
        struct R: Decodable { let url: String }
        return try JSONDecoder().decode(R.self, from: data).url
    }

    /// Fire and forget, like the Flutter client: a failed push never blocks the user.
    func notify(_ event: String, _ ids: [String: String]) async {
        var body = ids
        body["event"] = event
        guard let json = try? JSONEncoder().encode(body) else { return }
        _ = try? await post(baseURL.appending(path: "notify"), contentType: "application/json", body: json)
    }

    private func post(_ url: URL, contentType: String, body: Data) async throws -> Data {
        guard let token = try await Auth.auth().currentUser?.getIDToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
```

The function rejects images over 2 MB. Resize to 512 px on the long edge and encode with `jpegData(compressionQuality: 0.8)` before uploading.

## 7. Onboarding, settings and phone sign-in

A first-time user sees the welcome screen, then either signs in by SMS or browses matches signed out. Sign-in is three steps on a dark screen (phone, code, name) followed by an optional player profile. Browsing is allowed signed out; creating matches, teams, favorites and reminders asks for sign-in first.

### 7.1 Settings store (replaces SettingsCubit)

Same three keys in `UserDefaults` as the Flutter `SharedPreferences`: `themeMode`, `languageCode`, `onboardingSeen`.

```swift
@MainActor @Observable
final class SettingsStore {
    enum Theme: String, CaseIterable { case system, light, dark }
    private let d = UserDefaults.standard

    var theme: Theme { didSet { d.set(theme.rawValue, forKey: "themeMode") } }
    var languageCode: String? { didSet { d.set(languageCode, forKey: "languageCode") } }
    var onboardingSeen: Bool { didSet { d.set(onboardingSeen, forKey: "onboardingSeen") } }

    init() {
        theme = Theme(rawValue: d.string(forKey: "themeMode") ?? "") ?? .system
        languageCode = d.string(forKey: "languageCode")
        onboardingSeen = d.bool(forKey: "onboardingSeen")
    }

    var colorScheme: ColorScheme? { theme == .light ? .light : theme == .dark ? .dark : nil }
    var locale: Locale { languageCode.map(Locale.init(identifier:)) ?? .current }
}

let appLanguages: [(code: String, name: String)] = [("en", "English"), ("si", "සිංහල"), ("ta", "தமிழ்")]
```

### 7.2 Session store (replaces ProfileCubit)

Listens to Firebase auth state; while signed in it streams `users/{uid}` and `players/{uid}` and registers the FCM token.

```swift
@MainActor @Observable
final class SessionStore {
    private(set) var uid: String?
    private(set) var profile: UserProfile?
    private(set) var player: PlayerProfile?
    private(set) var loading = true
    var isSignedIn: Bool { profile != nil }

    private let users: UserRepository
    private let players: PlayerRepository
    private var handle: AuthStateDidChangeListenerHandle?
    private var tasks: [Task<Void, Never>] = []

    init(users: UserRepository, players: PlayerRepository) {
        self.users = users; self.players = players
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.userChanged(user?.uid) }
        }
    }

    private func userChanged(_ uid: String?) {
        tasks.forEach { $0.cancel() }; tasks = []
        self.uid = uid; profile = nil; player = nil
        guard let uid else { loading = false; return }
        loading = true
        tasks.append(Task { [users] in
            do { for try await p in users.watch(uid) { self.profile = p; self.loading = false } } catch {}
        })
        tasks.append(Task { [players] in
            do { for try await p in players.watch(uid) { self.player = p } } catch {}
        })
        tasks.append(Task { [users] in
            if let token = try? await Messaging.messaging().token() { try? await users.addFCMToken(uid, token) }
        })
    }

    func updateName(_ name: String) throws {
        guard var p = profile else { return }
        p.name = name.trimmingCharacters(in: .whitespaces)
        try users.save(p)
    }
    func signOut() { try? Auth.auth().signOut() }
}
```

Also register refreshed tokens from `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)` (section 12).

### 7.3 Welcome screen

Layout from top to bottom on the dark palette, 24 pt side padding:

1. Full-bleed `welcome_hero` image, aligned top, with a gradient from `bg` at 0% opacity (at 30% height) to solid `bg` (at 62% height).
2. Top row: `CreaseLogo` (26 pt, lime), "crease" wordmark 24 pt white, spacer, language pill (globe icon, current language name, chevron, white 10% capsule).
3. Spacer, then the headline in two lines: "Score every ball." white and "Follow every match." lime, Bricolage 38 ExtraBold.
4. Subtitle 16 pt white 70%, line spacing 1.4.
5. `PillButton("Get started")` then secondary `PillButton("Browse matches")`, 12 apart.
6. Footer "By continuing you agree to play fair and have fun." 12.5 pt white 38%.

Each block fades and slides up in sequence over 1.4 s (delays 0, 0.1, 0.2, 0.35, 0.45, 0.55 of the duration).

```swift
struct WelcomeView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @State private var shown = false
    @State private var showLanguages = false

    var body: some View {
        ZStack(alignment: .top) {
            Image("welcome_hero").resizable().scaledToFill().ignoresSafeArea()
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.3),
                                   .init(color: Color(hex: 0x0B0E0C), location: 0.62)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    CreaseLogo(size: 26)
                    Text(verbatim: "crease").font(AppFont.heading(24, .heavy)).foregroundStyle(.white)
                    Spacer()
                    LanguagePill { showLanguages = true }
                }
                Spacer()
                Group {
                    Text("welcomeTitleLine1").foregroundStyle(.white).appear(shown, delay: 0)
                    Text("welcomeTitleLine2").foregroundStyle(Palette.accent).appear(shown, delay: 0.14)
                }
                .font(AppFont.heading(38, .heavy)).tracking(-1)
                Text("welcomeSubtitle").font(AppFont.body(16)).foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(5).padding(.top, 14).appear(shown, delay: 0.28)
                PillButton(title: "welcomeGetStarted") { finish(signIn: true) }
                    .padding(.top, 32).appear(shown, delay: 0.49)
                PillButton(title: "welcomeBrowse", secondary: true) { finish(signIn: false) }
                    .padding(.top, 12).appear(shown, delay: 0.63)
                Text("welcomeFooter").font(AppFont.body(12.5)).foregroundStyle(.white.opacity(0.38))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .padding(.top, 18).appear(shown, delay: 0.77)
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear { shown = true }
        .sheet(isPresented: $showLanguages) { LanguageSheet() }
    }

    private func finish(signIn: Bool) {
        settings.onboardingSeen = true          // RootView swaps to the NavigationStack
        if signIn { router.push(.login(redirect: nil)) }
    }
}

extension View {
    /// FadeSlideIn equivalent.
    func appear(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : 16)
            .animation(.easeOut(duration: 0.6).delay(delay), value: shown)
    }
}
```

`LanguageSheet` is a list of the three languages with a checkmark on the current one; tapping sets `settings.languageCode` and dismisses. Use `.presentationDetents([.height(260)])` and `.presentationDragIndicator(.visible)`.

### 7.4 Phone sign-in flow

```swift
enum AuthStep: Int { case phone, code, name, createPlayer, done }

enum AuthError: Error {
    case invalidPhone, invalidCode, codeExpired, tooManyRequests, quotaExceeded, network, sendFailed, saveName, unknown
    var key: LocalizedStringKey {
        switch self {
        case .invalidPhone: "authErrorInvalidPhone"; case .invalidCode: "authErrorInvalidCode"
        case .codeExpired: "authErrorCodeExpired"; case .tooManyRequests: "authErrorTooManyRequests"
        case .quotaExceeded: "authErrorQuotaExceeded"; case .network: "authErrorNetwork"
        case .sendFailed: "authErrorSendFailed"; case .saveName: "authErrorSaveName"; case .unknown: "errorGeneric"
        }
    }
    init(_ error: Error) {
        switch AuthErrorCode(_bridgedNSError: error as NSError)?.code {
        case .invalidPhoneNumber, .missingPhoneNumber: self = .invalidPhone
        case .invalidVerificationCode: self = .invalidCode
        case .sessionExpired: self = .codeExpired
        case .tooManyRequests: self = .tooManyRequests
        case .quotaExceeded: self = .quotaExceeded
        case .networkError: self = .network
        case .internalError: self = .sendFailed
        default: self = .unknown
        }
    }
}

@MainActor @Observable
final class PhoneAuthModel {
    var step: AuthStep = .phone
    var phone = ""
    var submitting = false
    var error: AuthError?
    private var verificationID: String?
    private let users: UserRepository
    init(users: UserRepository) { self.users = users }

    func sendCode(_ e164: String) async {
        submitting = true; error = nil; phone = e164
        do {
            verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil)
            step = .code
        } catch { self.error = AuthError(error) }
        submitting = false
    }

    func submitCode(_ code: String) async {
        guard let verificationID else { return }
        submitting = true; error = nil
        do {
            let cred = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
            let uid = try await Auth.auth().signIn(with: cred).user.uid
            step = try await users.get(uid) == nil ? .name : .done
        } catch { self.error = AuthError(error) }
        submitting = false
    }

    func submitName(_ name: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try users.save(UserProfile(uid: uid, phone: phone, name: name.trimmingCharacters(in: .whitespaces),
                                       createdAt: ISODate.string(.now)))
            step = .createPlayer
        } catch { self.error = .saveName }
    }
}
```

Screen rules, copied from `phone_login_screen.dart`:

- Always dark, whatever the app theme. Top bar: 44 pt round back button (white 8%), then three 3 pt progress bars (lime when reached, white 12% otherwise). Back on the code step returns to the phone step.
- Each step: title (Bricolage 28 ExtraBold white), subtitle (16 pt white 60%), input, red error row if any, spacer, pill button pinned to the bottom. Steps cross-fade and slide 12% from the right over 0.35 s.
- Phone step: fixed "🇱🇰 +94" box, then a digits-only field (max 10, hint "77 123 4567", `.textContentType(.telephoneNumber)`). Strip a leading 0; valid only when it matches `^7\d{8}$`. Send `+94` + the 9 digits.
- Code step: a 6-box OTP field backed by one hidden `TextField` with `.textContentType(.oneTimeCode)` and `.keyboardType(.numberPad)`, so iOS can autofill from SMS. Submit automatically at 6 digits. "Resend code in 30s" countdown, then "Resend code"; "Change number" link. The invalid-code error tints the boxes red.
- Name step: circle avatar showing the first letter as you type, name field, "Let's go" button. Only shown when `users/{uid}` has no profile yet.
- When the step becomes `.createPlayer`, replace the login screen with `.playerProfileSetup(redirect:)`. When it becomes `.done`, go to the redirect route if one was given, else pop.

```swift
struct OTPField: View {
    @Binding var code: String
    var hasError = false
    var onComplete: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .focused($focused).opacity(0.01)
                .onChange(of: code) { _, v in
                    code = String(v.filter(\.isNumber).prefix(6))
                    if code.count == 6 { onComplete(code) }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let ch = i < code.count ? String(Array(code)[i]) : ""
                    Text(ch).font(AppFont.mono(24, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                            hasError ? Palette.wkt : (focused && i == code.count ? Palette.accent : .clear), lineWidth: 1.5))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
    }
}
```

Firebase setup for SMS: enable Phone in Authentication > Sign-in method, upload an APNs auth key under Project settings > Cloud Messaging so silent-push verification works, and add test numbers there for development. On the Simulator, Firebase falls back to a reCAPTCHA web view, which is why the reversed client ID URL scheme is required.

## 8. Localization: English, Sinhala, Tamil

All 221 strings already exist in `lib/l10n/app_en.arb`, `app_si.arb` and `app_ta.arb`. Convert them once into a single `Localizable.xcstrings` String Catalog with the script below, keep the same keys, and use the keys directly in SwiftUI (`Text("loginSendCode")`).

### 8.1 Project settings

1. Project > Info > Localizations: add Sinhala (`si`) and Tamil (`ta`) next to English.
2. Add `CFBundleAllowMixedLocalizations = YES` to Info.plist so the in-app language picker can override the system language.
3. The in-app picker sets `.environment(\.locale, settings.locale)` on the root view (section 3). SwiftUI `Text("key")` follows that environment locale. For strings built in code, use `String(localized: "key", locale: settings.locale)`.

### 8.2 ARB to String Catalog converter

Only 12 strings take arguments. ARB `{name}` placeholders become `%@` for strings and `%lld` for ints, in order; the one plural (`playersCount`) becomes a plural variation.

```python
# tools/arb_to_xcstrings.py  ->  python3 tools/arb_to_xcstrings.py > Crease/Resources/Localizable.xcstrings
import json, re

langs = {"en": "lib/l10n/app_en.arb", "si": "lib/l10n/app_si.arb", "ta": "lib/l10n/app_ta.arb"}
arbs = {l: json.load(open(p, encoding="utf-8")) for l, p in langs.items()}
en = arbs["en"]
plural = re.compile(r"^\{(\w+), plural, (.*)\}$", re.S)

def fmt(text, meta):
    ph = meta.get("placeholders", {})
    order = re.findall(r"\{(\w+)\}", text)
    for i, name in enumerate(order, 1):
        spec = "lld" if ph.get(name, {}).get("type") == "int" else "@"
        positional = f"%{i}${spec}" if len(order) > 1 else f"%{spec}"
        text = text.replace("{" + name + "}", positional, 1)
    return text

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

strings = {}
for key in (k for k in en if not k.startswith("@")):
    meta = en.get("@" + key, {})
    locs = {}
    for lang, arb in arbs.items():
        text = arb.get(key, en[key])
        m = plural.match(text)
        if m:
            cases = dict(re.findall(r"(=1|one|other)\{((?:[^{}]|\{\w+\})*)\}", m.group(2)))
            one = cases.get("=1") or cases.get("one") or cases["other"]
            locs[lang] = {"variations": {"plural": {
                "one": unit(one.replace("{" + m.group(1) + "}", "%lld")),
                "other": unit(cases["other"].replace("{" + m.group(1) + "}", "%lld"))}}}
        else:
            locs[lang] = unit(fmt(text, meta))
    strings[key] = {"extractionState": "manual", "localizations": locs}

print(json.dumps({"sourceLanguage": "en", "version": "1.0", "strings": strings}, ensure_ascii=False, indent=2))
```

### 8.3 Using strings with arguments

```swift
Text("loginCodeSubtitle \(phone)")                // Sent to %@
Text("loginResendIn \(secondsLeft)")              // Resend code in %llds
Text("needRunsInBalls \(team) \(runs) \(balls)")  // %1$@ need %2$lld in %3$lld balls
Text("playersCount \(count)")                     // plural
```

With interpolation the catalog key Xcode looks up is `"loginCodeSubtitle %@"`, not `"loginCodeSubtitle"`. Pick one approach and stay consistent: either rename those 12 keys in the converter to include the format specifiers (simplest), or call them through a helper such as `String(format: String(localized: "loginCodeSubtitle"), phone)`.

### 8.4 Enum labels

Port the label helpers from `lib/l10n/l10n.dart` as computed `LocalizedStringKey` properties, for example:

```swift
extension MatchFormat {
    var label: LocalizedStringKey {
        switch self {
        case .t20: "formatT20"; case .t10: "formatT10"; case .odi: "formatOdi"; case .custom: "formatCustom"
        case .softball: "formatSoftball"; case .tapeBall: "formatTapeBall"; case .sixes: "formatSixes"
        }
    }
}
```

Do the same for `PlayerRole` (`roleBatter`...), `Gender`, `BattingStyle` (`battingRhb`, `battingLhb`), `BowlingStyle` (`bowlingNone`...), `DismissalType` (`dismissalBowled`...) and `ExtraType` (`extraWide`...). The player summary line is role, batting style and (if not none) bowling style joined by " · ".

Dates and times use the selected locale: `date.formatted(.dateTime.month(.abbreviated).day().locale(settings.locale))` replaces `DateFormat.MMMd`, and `.hour().minute()` replaces `DateFormat.jm`.

## 9. Profile, player profile and photos

There are two profiles: the account (`users/{uid}`: phone, display name, favorites) and the player card (`players/{uid}`: gender, role, styles, photo) that teams search for. The player card is offered right after sign-up and can be skipped.

### 9.1 Player profile form

Used for setup (after sign-up, with a Skip button and no back button) and for edit (from Profile).

| Field | Control | Default | Rule |
| --- | --- | --- | --- |
| Photo | 112 pt `PlayerPhoto` with a 36 pt lime camera badge; tap opens `PhotosPicker` | Existing photo, else illustration by gender | Optional |
| Name | Text field, `.textInputAutocapitalization(.words)` | Player name, else account name | Required |
| Gender | Segmented: Male / Female | None selected | Required |
| Role | Wrapping chips: Batter, Bowler, All-rounder, Wicket-keeper | Batter |  |
| Batting style | Segmented: RHB / LHB | RHB |  |
| Bowling style | `Picker` menu, 7 options | None |  |

Save is enabled when name and gender are set. On failure show `playerProfileSaveError` in a toast or alert. On success go to the redirect route, else pop.

```swift
struct PlayerProfileFormView: View {
    let setup: Bool
    let redirect: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router

    @State private var name = ""
    @State private var gender: Gender?
    @State private var role: PlayerRole = .batter
    @State private var batting: BattingStyle = .rhb
    @State private var bowling: BowlingStyle = .none
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        Form {
            if setup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("playerProfileSetupTitle").font(AppFont.heading(24, .heavy))
                    Text("playerProfileSetupSubtitle").foregroundStyle(Palette.ink2)
                }.listRowBackground(Color.clear)
            }
            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    PlayerPhoto(photoURL: session.player?.photoUrl.flatMap(URL.init), image: photo, gender: gender, size: 112)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill").font(.system(size: 16))
                                .foregroundStyle(Palette.onAccent).frame(width: 36, height: 36)
                                .background(Circle().fill(Palette.accent))
                        }
                }
                .frame(maxWidth: .infinity).listRowBackground(Color.clear)
                TextField("playerName", text: $name).textInputAutocapitalization(.words)
            }
            Section("playerGender") {
                Picker("playerGender", selection: $gender) {
                    ForEach(Gender.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }.pickerStyle(.segmented)
            }
            Section("playerRoleLabel") { RoleChips(selection: $role) }
            Section("playerBattingStyle") {
                Picker("", selection: $batting) {
                    ForEach(BattingStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("playerBowlingStyle") {
                Picker("playerBowlingStyle", selection: $bowling) {
                    ForEach(BowlingStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
        }
        .navigationTitle(setup ? "playerProfile" : (session.player == nil ? "playerProfileCreate" : "playerProfileEdit"))
        .navigationBarBackButtonHidden(setup)
        .toolbar {
            if setup { ToolbarItem(placement: .topBarTrailing) { Button("skip") { finish() }.disabled(saving) } }
        }
        .safeAreaInset(edge: .bottom) {
            Button { Task { await save() } } label: {
                if saving { ProgressView() } else { Text("save") }
            }
            .buttonStyle(FilledButtonStyle())
            .disabled(saving || gender == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(20)
        }
        .onChange(of: pickerItem) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: d) } }
        }
        .onAppear {
            name = session.player?.name ?? session.profile?.name ?? ""
            gender = session.player?.gender
            role = session.player?.role ?? .batter
            batting = session.player?.battingStyle ?? .rhb
            bowling = session.player?.bowlingStyle ?? .none
        }
        .alert("playerProfileSaveError", isPresented: $failed) { Button("ok") {} }
    }

    private func save() async {
        guard let uid = session.uid, let gender else { return }
        saving = true; defer { saving = false }
        let p = PlayerProfile(uid: uid, name: name.trimmingCharacters(in: .whitespaces), gender: gender,
                              photoUrl: session.player?.photoUrl, role: role, battingStyle: batting, bowlingStyle: bowling)
        do { try await env.players.save(p, photo: photo?.jpegForUpload()); finish() } catch { failed = true }
    }

    private func finish() {
        router.pop()
        if let redirect { router.open(path: redirect) }
    }
}

extension UIImage {
    /// Max 600 px wide (the Flutter picker used maxWidth 600, quality 80). Stays well under the 2 MB limit.
    func jpegForUpload(maxSide: CGFloat = 600) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let img = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: 0.8)
    }
}
```

`FilledButtonStyle` is the 48 pt, radius 14, `btn`-coloured style from section 4. `RoleChips` is an `HStack`-wrapping set of capsule buttons (use a simple custom `Layout` or `ViewThatFits`); selected chips use `brand` fill with `onBrand` text.

The upload URL ends with `?v=<timestamp>`, so `AsyncImage` fetches the new photo instead of a cached one.

### 9.2 Profile screen

Signed out: an empty avatar circle with a person icon, `profileJoinSubtitle`, and a "Sign in with phone" button that pushes `.login`.

Signed in, top to bottom:

1. Header card: avatar (player photo or initial), display name (or "No name yet") with an edit pencil that opens an alert with a text field and calls `session.updateName`, and the phone number.
2. Player profile section: if no player card, `playerProfileEmpty` + "Create player profile"; otherwise photo, name and "Male · Batter · RHB · Right-arm fast" summary, plus an Edit button to `.playerProfileEdit`.
3. A row "Teams" (people icon, chevron) to `.teams`.
4. Preferences: Appearance (Light / Dark / System sheet with a checkmark) and Language (the language sheet).
5. Sign out row (red icon) with a confirm alert: title `profileSignOutTitle`, body `profileSignOutBody`, Cancel / Sign out.
6. Footer: "Member since September 2026" using `createdDate.formatted(.dateTime.month(.wide).year())`.

Group the rows in `surface` cards with radius 18 and 16 pt padding, section titles in `ink3` 13 SemiBold, on a `bg` background. A grouped `List` with `.listStyle(.insetGrouped)` and custom row backgrounds gets close with little code.

## 10. Teams, logos and invites

A signed-in user creates a team, becomes its owner and first member, then searches players by name and invites them. The invited player gets a push and sees the invite at the top of their Teams screen, where they accept or decline. Accepting pushes a notice back to the owner.

### 10.1 Teams list (`TeamsView`)

- Data: `teams.watchMemberships(player: uid)`, all `teamMembers` docs where `playerId == uid`.
- "Invitations" section: memberships with `status == .pending`. Each card shows the team badge, team name, "{ownerName} invited you to join", and Decline (outlined) / Accept (filled) buttons side by side.
- "My teams" section: accepted memberships. Row: `TeamBadge` with `teamLogoUrl`, team name, subtitle "Owner" when `ownerId == playerId` else the owner's name, chevron. Tap pushes `.team(id:)`.
- Empty state: `teamsEmpty`.
- Lime extended button "New team" bottom-right opens the create dialog.

```swift
@MainActor @Observable
final class TeamsModel {
    var memberships: [TeamMember] = []
    var invites: [TeamMember] { memberships.filter(\.isPending) }
    var teams: [TeamMember] { memberships.filter { !$0.isPending } }
    let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }

    func watch(uid: String) async {
        do { for try await m in env.teams.watchMemberships(player: uid) { memberships = m } } catch {}
    }

    /// Returns the new team ID, or nil on failure (show `teamCreateError`).
    func createTeam(name: String, logo: UIImage?, owner: UserProfile, player: PlayerProfile?) async -> String? {
        let id = UUID().uuidString.lowercased()
        let now = ISODate.string(.now)
        var logoURL: String?
        if let data = logo?.jpegForUpload(maxSide: 512) {
            do { logoURL = try await env.functions.uploadPhoto(data, teamID: id) } catch { return nil }
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let team = Team(id: id, name: trimmed, shortName: shortName(trimmed), ownerId: owner.uid,
                        ownerName: owner.name, createdAt: now, logoUrl: logoURL, searchTokens: searchTokens(trimmed))
        let me = TeamMember(teamId: id, teamName: trimmed, ownerId: owner.uid, ownerName: owner.name,
                            playerId: owner.uid, playerName: player?.name ?? owner.name, playerGender: player?.gender,
                            playerPhotoUrl: player?.photoUrl, teamLogoUrl: logoURL, status: .accepted, invitedAt: now)
        do { try await env.teams.create(team, owner: me); return id } catch { return nil }
    }

    func accept(_ invite: TeamMember) async {
        do {
            try await env.teams.accept(invite)
            await env.functions.notify("invite_accepted", ["teamId": invite.teamId, "playerId": invite.playerId])
        } catch {}
    }
    func decline(_ invite: TeamMember) async { try? await env.teams.remove(invite) }
}

/// "Kandy Kings Cricket Club" -> "KKC": first letter of up to three words.
func shortName(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).prefix(3).compactMap(\.first).map(String.init).joined().uppercased()
}
```

### 10.2 New team dialog

A sheet (or alert-style card) with a tappable 72 pt logo circle (camera badge), "Choose photo" link, a "Team name" field, and Cancel / Create team. Logos are picked with `PhotosPicker` and resized to 512 px at 0.85 quality. After creation, push `.team(id:)`.

### 10.3 Team screen (`TeamView`)

- Data: `watchTeam(id)` and `watchMembers(team: id)`.
- Header: 72 pt `TeamBadge` (logo, else coloured initials). If you are the owner, tapping it picks a new logo, uploads it with `?team=<id>`, then `setLogo` writes `logoUrl` on the team and `teamLogoUrl` on every member doc in one batch.
- Title is the team name and subtitle "{n} players" (accepted only, pluralised).
- Member rows: `PlayerPhoto` (gender fallback), name, trailing "Owner" for the owner, orange "Pending" for pending invites, and for the owner an x button to remove anyone else.
- Owners get a lime "Add players" button that opens the search sheet. If the team is not found, show `errorNotFound`.

### 10.4 Player search sheet

```swift
@MainActor @Observable
final class TeamModel {
    var team: Team?
    var members: [TeamMember] = []
    var results: [PlayerProfile] = []
    var query = "" { didSet { scheduleSearch() } }
    private var searchTask: Task<Void, Never>?
    let teamID: String
    let env: AppEnvironment
    init(teamID: String, env: AppEnvironment) { self.teamID = teamID; self.env = env }

    func status(of playerID: String) -> MemberStatus? { members.first { $0.playerId == playerID }?.status }

    /// 300 ms debounce, like the Flutter cubit.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = (try? await env.players.search(query)) ?? []
        }
    }

    func invite(_ p: PlayerProfile) async {
        guard let team else { return }
        let m = TeamMember(teamId: team.id, teamName: team.name, ownerId: team.ownerId, ownerName: team.ownerName,
                           playerId: p.uid, playerName: p.name, playerGender: p.gender, playerPhotoUrl: p.photoUrl,
                           teamLogoUrl: team.logoUrl, status: .pending, invitedAt: ISODate.string(.now))
        do {
            try env.teams.invite(m)
            await env.functions.notify("team_invite", ["teamId": team.id, "playerId": p.uid])
        } catch {}
    }
}
```

The sheet has a search field (`searchPlayers` placeholder, magnifier icon) and a list of results: photo, name, the player summary line, and a trailing "In team" (grey), "Invited" (orange) or an "Invite" button. No results shows `searchNoResults`. Use `.presentationDetents([.large])`.

The Firestore rules enforce that only the owner can invite and that the document ID is `{teamId}_{playerId}`, so a player cannot be invited twice.

## 11. Matches: home, create, scoring, match center

A match moves through four screens: the creator builds it in a 4-step wizard, scores it ball by ball on the scoring screen, and everyone else follows it on the home card and in the match center. Every screen derives its numbers from the same event log via `CreaseEngine.replay`.

### 11.1 Home screen

- Nav bar on `brand`: lime `CreaseLogo` 24 + "crease" wordmark; trailing buttons Teams (`person.3.fill`, requires sign-in) and Profile (`person.fill`).
- Under it, still on `brand`, a horizontal row of filter chips: All, Live, Upcoming, Results, Mine, Favorites.
- The list, grouped into sections with uppercase headers and a mono count ("LIVE 2"): Pending, Live, Upcoming, Results (completed + abandoned). All, Mine and Favorites show every group; Live, Upcoming and Results show only their own group. Mine = `createdBy == uid`; Favorites = `profile.favoriteMatchIds`.
- Empty state per filter (`emptyAll`, `emptyLive`, ...), centred `ink3` text 64 pt from the top. Loading shows 4 skeleton cards.
- Lime extended FAB "New match" (requires sign-in) pushes `.createMatch`.
- Tapping a card: the creator of an upcoming or live match goes to `.scoring(id)`, everyone else to `.matchCenter(id)`.

```swift
@MainActor @Observable
final class HomeModel {
    enum Filter: CaseIterable { case all, live, upcoming, results, mine, favorites }
    var filter: Filter = .all
    var matches: [Match]?
    var failed = false

    func watch(_ repo: MatchRepository, uid: String?) async {
        do { for try await m in repo.watchMatches(uid: uid) { matches = m } } catch { failed = true }
    }

    func sections(uid: String?, favorites: [String]) -> [(title: LocalizedStringKey, items: [Match])] {
        guard let all = matches else { return [] }
        let scoped = switch filter {
            case .mine: all.filter { $0.createdBy == uid }
            case .favorites: all.filter { favorites.contains($0.id) }
            default: all
        }
        let grouped = [.all, .mine, .favorites].contains(filter)
        func pick(_ s: [MatchStatus]) -> [Match] { scoped.filter { s.contains($0.status) } }
        var out: [(LocalizedStringKey, [Match])] = []
        if grouped { out.append(("statusPending", pick([.pending]))) }
        if grouped || filter == .live { out.append(("sectionLive", pick([.live]))) }
        if grouped || filter == .upcoming { out.append(("sectionUpcoming", pick([.upcoming]))) }
        if grouped || filter == .results { out.append(("sectionResults", pick([.completed, .abandoned]))) }
        return out.filter { !$0.1.isEmpty }
    }
}
```

Restart `watch` when the signed-in user changes: `.task(id: session.uid) { await model.watch(env.matches, uid: session.uid) }`.

### 11.2 Match card

A `surface` card, radius 18, light shadow, padding 16 / top 10.

- Header line: "T20, Asgiriya Stadium, Kandy" (format label + venue) in `ink3` 13 Medium. Upcoming matches show a bell toggle on the right (`bell` / `bell.badge.fill` in `live` red when on).
- Body: two team rows on the left, a 1 pt vertical divider, and a 112 pt wide trailing block on the right.
- Team row: 28 pt circular `TeamBadge`, 12 gap, then either the short name (no scores yet) or `SHORT  154-6  20.0`; runs-wickets 17 Bold (`brand2` if batting, else `ink2`), overs 14 (`ink` if batting, else `ink3`), and a cricket icon after the batting side. A live team with no score yet shows "Yet to bat".
- Trailing by status: Live = pulsing red dot + "Live"; Upcoming = "Today" / "Tomorrow" / "Oct 2" (15) over the time (17 SemiBold `ink3`); Pending = "Pending" in `extra`; Completed = `shortResultText` in `six` green; Abandoned = `ink3`.
- Favorite (heart) and reminder (bell) toggles call `users.setFavorite` / `setReminder` and subscribe or unsubscribe the FCM topic `match_{id}` / `reminder_{id}` (section 12). Both require sign-in.

Scores on the card come from `match.scores` and `match.battingSide`, which the scorer writes after every ball. Cards never replay events.

### 11.3 Create match wizard

Four steps in one screen with a step indicator and Back / Next buttons. Keep the state in one `@Observable CreateMatchModel`.

| Step | Fields | Rules |
| --- | --- | --- |
| 1. Details | Format chips (T20, T10, ODI, Custom, Softball, Tape ball, Sixes), overs stepper, players per side stepper, venue text, Public toggle (default on) | Picking a format resets overs and players to its defaults (T20 20/11, T10 10/11, ODI 50/11, Custom 20/11, Softball 8/8, Tape ball 12/11, Sixes 6/11) |
| 2. Teams | For side A and B: pick one of my teams, search any team, or "Custom team". Custom lets you edit name, short name and colour | Both sides chosen and not the same team |
| 3. Squads | Per side: list of players with remove buttons and an "Add player" field. A real team pre-fills its accepted members | None enforced |
| 4. Toss | Who won (A or B) and chose to (Bat or Bowl) | Both picked to enable Start |

Defaults for custom teams: "Team A" / `TMA` / `#0F3B29` and "Team B" / `TMB` / `#2E7DD1`. Store colours as ARGB ints (`0xFF0F3B29`).

```swift
@MainActor @Observable
final class CreateMatchModel {
    struct Side { var team: Team?; var chosen = false; var name: String; var short: String; var color: Int; var squad: [Player] = [] }
    var step = 0
    var format: MatchFormat = .t20 { didSet { overs = format.defaultOvers; players = format.defaultPlayersPerSide } }
    var overs = 20, players = 11
    var venue = "", isPublic = true
    var a = Side(name: "Team A", short: "TMA", color: 0xFF0F3B29)   // unsigned ARGB, as Flutter writes it
    var b = Side(name: "Team B", short: "TMB", color: 0xFF2E7DD1)
    var tossWinner: String?, tossDecision: TossDecision?
    var submitting = false
    let env: AppEnvironment
    let creatorID: String?
    init(env: AppEnvironment, creatorID: String?) { self.env = env; self.creatorID = creatorID }

    var canProceedFromTeams: Bool { a.chosen && b.chosen && !(a.team != nil && a.team?.id == b.team?.id) }
    var canSubmit: Bool { tossWinner != nil && tossDecision != nil }
    /// Owners of picked teams other than me must confirm before play.
    var pendingOwnerIDs: [String] { Array(Set([a.team, b.team].compactMap { $0?.ownerId }.filter { $0 != creatorID })) }

    func select(_ team: Team, side: String) async {
        let members = (try? await env.teams.acceptedMembers(team.id)) ?? []
        let squad = members.map { Player(id: $0.playerId, name: $0.playerName, photoUrl: $0.playerPhotoUrl) }
        let s = Side(team: team, chosen: true, name: team.name, short: team.shortName,
                     color: side == "A" ? a.color : b.color, squad: squad)
        if side == "A" { a = s } else { b = s }
    }

    /// Returns the new match and whether it waits for other owners.
    func submit() async -> (id: String, pending: Bool)? {
        guard canSubmit, let tossWinner, let tossDecision else { return nil }
        submitting = true; defer { submitting = false }
        func team(_ s: Side, _ side: String) -> MatchTeam {
            MatchTeam(side: side, name: s.name, shortName: s.short, color: s.color, squad: s.squad,
                      teamId: s.team?.id, ownerId: s.team?.ownerId, logoUrl: s.team?.logoUrl)
        }
        let pending = pendingOwnerIDs
        var m = Match(format: format, config: MatchConfig(oversPerInnings: overs, playersPerSide: players),
                      teamA: team(a, "A"), teamB: team(b, "B"), createdAt: ISODate.string(.now))
        m.id = UUID().uuidString.lowercased()
        m.venueName = venue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : venue.trimmingCharacters(in: .whitespaces)
        m.toss = Toss(winnerSide: tossWinner, decision: tossDecision)
        m.status = pending.isEmpty ? .live : .pending
        m.createdBy = creatorID
        m.isPublic = isPublic
        m.pendingOwnerIds = pending
        do {
            try env.matches.create(m)
            if !pending.isEmpty { await env.functions.notify("match_request", ["matchId": m.id]) }
            return (m.id, !pending.isEmpty)
        } catch { return nil }
    }
}
```

On success: if pending, replace the wizard with `.matchCenter(id)` (it shows "Waiting for the other team to confirm"); otherwise replace it with `.scoring(id)`.

The team picker sheet has two parts: "My teams" (`teams.ownedBy(uid)`) and a search field over all teams. A "Custom team" row resets the side to the defaults above. Picking a team owned by someone else is what triggers the match request.

### 11.4 Scoring screen

Only the match creator opens this screen. It loads the match and all events once, then keeps the log in memory: every tap builds an event, appends it to Firestore, appends it locally, and replays. Undo appends a `void` that points at the last un-voided event; nothing is ever edited or deleted.

```swift
@MainActor @Observable
final class ScoringModel {
    enum Prompt { case none, openers, newBowler }

    private(set) var match: Match?
    private(set) var state = MatchState()
    private(set) var prompt: Prompt = .none
    private(set) var notFound = false
    private var events: [MatchEvent] = []
    private var seq = 0
    // Chosen in the openers / new-bowler sheets, used for the next ball only.
    private var openerStriker: String?, openerNonStriker: String?, nextBowler: String?

    let matchID: String
    let env: AppEnvironment
    init(matchID: String, env: AppEnvironment) { self.matchID = matchID; self.env = env }

    /// 0 or 1 while play is on, 2 once both innings are closed.
    var targetIndex: Int {
        guard let last = state.innings.last else { return 0 }
        return last.closed ? last.index + 1 : last.index
    }
    var isComplete: Bool { targetIndex >= 2 }
    var canUndo: Bool { events.contains { if case .void = $0.kind { false } else { true } } }

    /// The innings being scored, or a placeholder carrying the chosen openers before ball one.
    var current: InningsState? {
        if let i = state.innings.first(where: { $0.index == targetIndex }) { return i }
        guard let match, !isComplete, prompt == .none else { return nil }
        let bat = match.inningsBattingOrder[targetIndex]
        var i = InningsState(index: targetIndex, battingTeam: bat, bowlingTeam: bat == "A" ? "B" : "A")
        i.strikerId = openerStriker; i.nonStrikerId = openerNonStriker; i.currentBowlerId = nextBowler
        return i
    }

    func load() async {
        guard let m = try? await env.matches.getMatch(matchID) else { notFound = true; return }
        match = m
        events = (try? await env.matches.loadEvents(matchID)) ?? []
        seq = events.map(\.seq).max() ?? 0
        rebuild()
    }

    private func rebuild() {
        guard let match else { return }
        state = env.engine.replay(events: events, config: match.config, inningsBattingTeam: match.inningsBattingOrder)
        let t = state.innings.first { $0.index == targetIndex }
        if isComplete { prompt = .none }
        else if t?.strikerId == nil { prompt = (openerStriker != nil && openerNonStriker != nil && nextBowler != nil) ? .none : .openers }
        else if let t, t.legalBalls > 0, t.legalBalls % match.config.ballsPerOver == 0, nextBowler == nil { prompt = .newBowler }
        else { prompt = .none }
    }

    func confirmOpeners(striker: String, nonStriker: String, bowler: String) {
        openerStriker = striker; openerNonStriker = nonStriker; nextBowler = bowler; rebuild()
    }
    func confirmBowler(_ id: String) { nextBowler = id; rebuild() }

    func runs(_ r: Int) async { await ball { $0.runsOffBat = r } }
    func extra(_ type: ExtraType, runs: Int) async {
        // On a no-ball the chosen runs are off the bat; otherwise they are extra runs.
        await ball { $0.extra = type; if type == .noBall { $0.runsOffBat = runs } else { $0.extraRuns = runs } }
    }
    func wicket(_ d: Dismissal, out: String, incoming: String?, runsBefore: Int) async {
        await ball { $0.runsOffBat = runsBefore; $0.dismissal = d; $0.dismissedPlayerId = out; $0.incomingBatterId = incoming }
    }

    private func ball(_ fill: (inout BallEvent) -> Void) async {
        guard !isComplete else { return }
        let t = state.innings.first { $0.index == targetIndex }
        guard let striker = t?.strikerId ?? openerStriker,
              let nonStriker = t?.nonStrikerId ?? openerNonStriker,
              let bowler = nextBowler ?? t?.currentBowlerId else { return }
        var b = BallEvent(strikerId: striker, nonStrikerId: nonStriker, bowlerId: bowler)
        fill(&b)
        seq += 1
        nextBowler = nil; openerStriker = nil; openerNonStriker = nil
        await append(MatchEvent(seq: seq, inningsIndex: targetIndex, kind: .ball(b)))
    }

    func undo() async {
        let voided = Set(events.compactMap { if case .void(let s) = $0.kind { s } else { nil } })
        guard let target = events.reversed().first(where: {
            if case .void = $0.kind { return false }
            return !voided.contains($0.seq)
        }) else { return }
        seq += 1
        await append(MatchEvent(seq: seq, inningsIndex: target.inningsIndex, kind: .void(seq: target.seq)))
    }

    private func append(_ e: MatchEvent) async {
        guard var m = match else { return }
        do { try env.matches.append(matchID, e) } catch { rebuild(); return }
        events.append(e)
        rebuild()
        // Keep the summary fields on the match doc in sync for the home cards.
        let scores = Dictionary(uniqueKeysWithValues: state.innings.map {
            ($0.battingTeam, TeamScore(runs: $0.runs, wickets: $0.wickets, balls: $0.legalBalls)) })
        let batting = state.current?.battingTeam
        let finished = state.result != nil && m.status != .completed
        guard finished || scores != m.scores || batting != m.battingSide else { return }
        m.scores = scores
        m.battingSide = batting
        if finished { m.status = .completed; m.resultText = state.result?.text; m.winnerSide = state.result?.winner }
        try? env.matches.update(m)
        match = m
    }
}
```

Because `append` does not await the server, scoring works offline; Firestore syncs when the signal returns. Serialize taps by disabling the pad while an append is in flight, the way the Bloc used `sequential()`.

Layout, top to bottom:

1. Nav bar "Scoring", a Home button that pops to root, and a scorecard button that pushes `.matchCenter(id)`.
2. Crease panel (`brand` card): batting team, big mono score `154/6` (40 pt), overs `(18.3)`, meta row with CRR, Target and Need when chasing; then the striker (with a bat marker) and non-striker rows with `runs (balls)`, the bowler row with `O-M-R-W`, and this over's `BallChip`s.
3. Score pad: a 4-column grid `0 1 2 3` (aspect 1.4, gap 8); a row with `4` (text `four` blue, 60 pt tall) and `6` (`btn` fill, white text); a row with `EXTRA` (text `extra`, 54 pt) and `WICKET` (`wkt` fill, white, 2x width, letter spacing 1.5); then four small icon buttons Undo, Swap, Retire, Note. Pad keys are `surface` with radius 16.
4. When complete: a result view with the result text, "View scorecard" and "Back to home".

Sheets:

- Openers (shown when `prompt == .openers`, not dismissible): pick striker, then non-striker from the batting squad, then the opening bowler from the bowling squad.
- New bowler (when `prompt == .newBowler`): pick from the bowling squad. Exclude the bowler of the over just finished.
- Extras: chips Wide / No ball / Bye / Leg bye, then runs chips 0 1 2 3 4 6 labelled "Runs off the bat" for no-ball and "Additional runs" otherwise, then Confirm.
- Wicket: chips for all 8 dismissal types; "Who is out?" Striker / Non-striker segmented control; for run out, "Runs completed" 0 to 3; a fielder button (required for caught, stumped, run out; labelled Wicketkeeper for stumped); Confirm. Unless this wicket ends the innings, Confirm then asks for the next batter (excluding batters already out and both at the crease). Set `dismissal.bowlerId` only when the type credits the bowler.

In the Flutter app Swap, Retire and Note do nothing yet. The engine already supports `swap`, `retire` and `note` events, so wire them up: Swap appends `.swap`; Retire picks the outgoing batter, the incoming batter and retired hurt vs retired out; Note asks for text.

### 11.5 Match center

Opened by followers, by pending team owners, and from the scorer's scorecard button. It listens to the match doc; on each change it fetches events after the last known `seq` and replays.

```swift
@MainActor @Observable
final class MatchCenterModel {
    private(set) var match: Match?
    private(set) var state = MatchState()
    private(set) var notFound = false
    private var events: [MatchEvent] = []
    let matchID: String, env: AppEnvironment
    init(matchID: String, env: AppEnvironment) { self.matchID = matchID; self.env = env }

    func watch() async {
        do {
            for try await m in env.matches.watchMatch(matchID) {
                guard let m else { notFound = true; continue }
                let fresh = (try? await env.matches.loadEvents(matchID, afterSeq: events.last?.seq)) ?? []
                events += fresh
                match = m
                state = env.engine.replay(events: events, config: m.config, inningsBattingTeam: m.inningsBattingOrder)
            }
        } catch { notFound = true }
    }

    func confirm(ownerID: String) async {
        guard var m = match else { return }
        m.pendingOwnerIds.removeAll { $0 == ownerID }
        m.status = m.pendingOwnerIds.isEmpty ? .live : .pending
        do {
            try await env.matches.matches.document(matchID).updateData(["status": m.status.rawValue, "pendingOwnerIds": m.pendingOwnerIds])
            if m.pendingOwnerIds.isEmpty { await env.functions.notify("match_confirmed", ["matchId": matchID]) }
        } catch {}
    }

    func decline() async {
        await env.functions.notify("match_declined", ["matchId": matchID])   // before the doc disappears
        try? await env.matches.delete(matchID)
    }
}
```

The Firestore rule lets a pending owner change only `status` and `pendingOwnerIds`, which is why `confirm` calls `updateData` with just those two fields instead of re-saving the whole match.

Screen: `brand` header with the match title and a segmented tab bar: Live (or Summary once completed), Scorecard, Squads. A pending match shows a banner on top: for a pending owner, `matchRequestBody` with Decline / Accept; for the creator, `matchWaiting`.

**Live tab**

- Hero card: both teams with badge, name and `runs/wickets (overs)`; under the batting side "Target 155" when chasing, else "Batting"; "Yet to bat" for the other.
- Status line: before the first ball `waitingFirstBall`; when chasing "KAN need 23 in 14 balls" (balls left = overs x balls per over - legal balls); otherwise "KAN batting · CRR 7.45".
- Stat pills: CRR, RRR when chasing, partnership if you add it.
- "At the crease" card: striker and non-striker with runs, balls, 4s, 6s, SR; current bowler with O, M, R, W, Econ; this over's ball chips.
- One summary card per completed innings.
- Shows `playNotStarted` if there are no innings yet.

**Scorecard tab**, per innings:

- Batting table: Batter, R, B, 4s, 6s, SR (mono 13.5). Under each name the dismissal line: `not out`, `retired hurt`, `c Fielder b Bowler`, `run out (Fielder)`, `b Bowler` / `lbw Bowler` / `st Bowler`, from the `dismissal` fields.
- Extras row and total.
- Bowling in an `ExpandableCard`: Bowler, O, M, R, W, Econ.
- `noOversYet` when empty.

**Summary tab** (completed matches), cards on `bg`:

1. Result banner with `match.resultText` (team names substituted).
2. One card per innings: team badge, name, overs, `runs/wickets`; "Top batters" = two highest by runs (ties: fewer balls), shown as `54*` with `32b · 5x4 · 2x6`; "Top bowlers" = two most wickets (ties: fewer runs), shown as `3/24` with `4.0 ov`.
3. Match info: toss line ("Kandy Kings won the toss and chose to bat"), format and overs ("T20 · 20 overs"), venue, date.

**Squads tab**: a segmented A / B switch, then players with avatar, name, role, and C / WK tags from `captainId` and `wicketKeeperId`, with the count "11 players".

Optional extras worth adding, since `overHistory` and `chart1` / `chart2` colours already exist: a Manhattan chart (runs per over, bars per team) and a worm chart (cumulative runs) with Swift Charts on the Summary tab.

## 12. Push notifications

Pushes reach the app two ways, both through FCM: direct to a user's tokens (stored in `users/{uid}.fcmTokens`, sent by the `notify` edge function) and by topic (`match_{id}`, `reminder_{id}`, sent by the Cloud Functions). Each push carries `data.route`, and tapping it opens that route.

### 12.1 One-time setup

1. Apple Developer > Keys: create an APNs key (.p8). Upload it in Firebase console > Project settings > Cloud Messaging > Apple app configuration, with your Key ID and Team ID.
2. Xcode capabilities: Push Notifications, Background Modes > Remote notifications (section 2).
3. Info.plist: `FirebaseAppDelegateProxyEnabled` = NO, so you forward the APNs token yourself as shown in section 3.

### 12.2 Notification service

```swift
import UserNotifications
import FirebaseMessaging

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = NotificationService()
    var onOpenRoute: ((String) -> Void)?
    var onToken: ((String) -> Void)?           // SessionStore saves it to users/{uid}.fcmTokens
    private var pendingRoute: String?

    func configure(application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            application.registerForRemoteNotifications()
        }
    }

    // Token refresh (replaces FirebaseMessaging.onTokenRefresh)
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken token: String?) {
        guard let token else { return }
        Task { @MainActor in self.onToken?(token) }
    }

    // Show banners while the app is open (setForegroundNotificationPresentationOptions)
    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification)
        async -> UNNotificationPresentationOptions { [.banner, .badge, .sound] }

    // Tap on a notification, from background or cold start
    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let route = r.notification.request.content.userInfo["route"] as? String
        await MainActor.run {
            guard let route else { return }
            if let open = onOpenRoute { open(route) } else { pendingRoute = route }
        }
    }

    /// Call once the router exists, to handle a tap that launched the app.
    func flushPendingRoute() { if let r = pendingRoute { pendingRoute = nil; onOpenRoute?(r) } }

    func follow(_ matchID: String) { Messaging.messaging().subscribe(toTopic: "match_\(matchID)") }
    func unfollow(_ matchID: String) { Messaging.messaging().unsubscribe(fromTopic: "match_\(matchID)") }
    func remind(_ matchID: String) { Messaging.messaging().subscribe(toTopic: "reminder_\(matchID)") }
    func cancelReminder(_ matchID: String) { Messaging.messaging().unsubscribe(fromTopic: "reminder_\(matchID)") }
}
```

Wire `onToken` in `SessionStore` so a refreshed token is saved for the signed-in user. iOS shows foreground banners itself, so the Flutter Android-only local-notification code has no iOS equivalent to port.

### 12.3 What triggers each push

| Push | Trigger in the app | Sent by | Tap opens |
| --- | --- | --- | --- |
| Team invitation | Owner taps Invite | `notify` `team_invite` | Teams |
| Invitation accepted | Player taps Accept | `notify` `invite_accepted` | That team |
| Match request | Creator starts a match with another owner's team | `notify` `match_request` | Match center |
| Match confirmed | Last pending owner taps Accept | `notify` `match_confirmed` | Scoring |
| Match declined | Pending owner taps Decline | `notify` `match_declined` | Home |
| Match started / finished | Status changes to live / completed | Cloud Function, topic `match_{id}` | App opens (no route) |
| Starting soon | 15 minutes before `scheduledAt` | Cloud Function, topic `reminder_{id}` | App opens (no route) |

The topic pushes carry no `route`. To open the match from them, add `data: { route: "/match/" + matchId }` in `functions/index.js`; the iOS handler already supports it.

### 12.4 Testing

Pushes do not reach the Simulator from FCM reliably; test on a device. For a quick check, drag an `.apns` file onto the Simulator with `{"aps": {"alert": {"title": "Team invitation", "body": "..."}}, "route": "/teams"}` and confirm the tap opens Teams.

## 13. Build order, testing and release

Build bottom-up so every screen has real data the day you start it: engine, then data, then read-only screens, then the screens that write. Each milestone ends with something you can run.

### 13.1 Milestones

1. **Engine.** Create the `CreaseEngine` package (section 6.1 to 6.3) and get both golden fixtures green. Add tests for every scoring rule listed in 6.3, including void/undo, no-ball runs off the bat, maidens, and strike rotation on odd byes.
2. **Project skeleton.** Xcode project, Firebase packages, fonts, assets, `Palette`, `AppFont`, `AppEnvironment`, `Router`, `RootView` with empty placeholder screens for every `Route`.
3. **Data layer.** Models, `ISODate`, repositories, `EdgeFunctions`. Point the app at the existing Firebase project and decode a real match from the Flutter app to prove field compatibility.
4. **Read-only screens.** Home (signed out, public matches), match card, match center with all four tabs. Compare side by side with the Flutter app on the same match.
5. **Onboarding and auth.** Welcome, language sheet, phone sign-in (use a Firebase test number), `SessionStore`, profile screen, sign-out.
6. **Player profile.** Form, photo picking, upload through `upload-photo`.
7. **Create and score.** Wizard, scoring screen, all sheets, undo, match completion. Score a full 2-over, 3-a-side match and check the result text.
8. **Teams.** Teams list, create team with logo, team screen, search and invite, accept and decline.
9. **Match requests.** Wizard with another owner's team, pending banner, confirm, decline.
10. **Push.** APNs key, token registration, direct pushes, topics for favorites and reminders, route handling from a cold start.
11. **Localization.** Run the ARB converter, switch to Sinhala and Tamil, fix any truncated labels.
12. **Polish.** Animations (welcome stagger, pulsing live dot, sheet transitions), dark mode check on every screen, Dynamic Type check, VoiceOver labels on the score pad.

### 13.2 Demo data

`DemoDataSeeder` in Flutter writes six demo matches (two live, two completed, two upcoming) under the signed-in user if `demo-live-1` does not exist. Since the iOS app shares the same Firestore, you do not need to port it: data seeded by the Flutter app already shows up. Port it only if you want a fresh project; keep it behind `#if DEBUG`.

### 13.3 Testing checklist

- [ ] Engine golden fixtures pass
- [ ] A match scored on iOS replays to the same totals in the Flutter app, and the reverse
- [ ] Undo after a wicket restores the batter and the bowler's figures
- [ ] Innings auto-closes on all out, overs completed and target reached
- [ ] Second-innings target equals first-innings runs + 1
- [ ] Home card scores update within a second of a ball being scored on another device
- [ ] Scoring with the device in airplane mode works and syncs when back online
- [ ] Signed-out users can browse public matches but are sent to sign-in for New match, Teams, favorites and reminders
- [ ] A user who already has a profile skips the name step
- [ ] Invite, accept and decline each send the right push and the tap opens the right screen
- [ ] A pending match is invisible to people other than the creator and pending owners
- [ ] Team logo change updates every member row
- [ ] Photos over 2 MB are resized before upload
- [ ] Sinhala and Tamil render on every screen; dates use the selected language
- [ ] Light and dark mode on every screen

### 13.4 App Store release

- [ ] Final bundle ID registered and matching a Firebase iOS app; `GoogleService-Info.plist` for that ID
- [ ] App icon 1024 px from `assets/icon/icon.png` (lime mark on brand green, no transparency)
- [ ] Display name "Crease" (`CFBundleDisplayName`)
- [ ] `NSPhotoLibraryUsageDescription` is not needed with `PhotosPicker`; add it only if you use `UIImagePickerController`
- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) declaring phone number, name, photos and user ID as collected for app functionality, and `UserDefaults` as an accessed API (reason CA92.1)
- [ ] App Privacy answers in App Store Connect matching the manifest
- [ ] Account deletion inside the app (App Store guideline 5.1.1(v)): delete `users/{uid}`, `players/{uid}`, team memberships, and the Firebase Auth user
- [ ] A demo phone number and code for App Review (add it as a Firebase test number)
- [ ] Release build with push entitlement set to production
- [ ] Screenshots: home, scoring, match center summary, teams; in English, and optionally Sinhala and Tamil

Account deletion does not exist in the Flutter app yet. Apple requires it for apps with sign-up, so plan it before the first submission.
