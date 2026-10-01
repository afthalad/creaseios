import SwiftUI

struct WelcomeView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @State private var shown = false
    @State private var showLanguages = false

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                Image("welcome_hero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .clipped()
            }
            .ignoresSafeArea()

            LinearGradient(stops: [.init(color: Palette.darkBg.opacity(0), location: 0.3),
                                   .init(color: Palette.darkBg, location: 0.62)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Wordmark(size: 24)
                    Spacer()
                    Button { showLanguages = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text(verbatim: settings.languageName)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .font(AppFont.body(13, .medium))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.large)
                }
                Spacer()
                Group {
                    Text("welcomeTitleLine1").foregroundStyle(.white).appear(shown, delay: 0)
                    Text("welcomeTitleLine2").foregroundStyle(Palette.accent).appear(shown, delay: 0.14)
                }
                .font(AppFont.heading(38, .heavy))
                .tracking(-1)

                Text("welcomeSubtitle")
                    .font(AppFont.body(16))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(5)
                    .padding(.top, 14)
                    .appear(shown, delay: 0.28)

                PillButton(title: "welcomeGetStarted") { finish(signIn: true) }
                    .padding(.top, 32)
                    .appear(shown, delay: 0.49)
                PillButton(title: "welcomeBrowse", secondary: true) { finish(signIn: false) }
                    .padding(.top, 12)
                    .appear(shown, delay: 0.63)

                Text("welcomeFooter")
                    .font(AppFont.body(12.5))
                    .foregroundStyle(.white.opacity(0.38))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .appear(shown, delay: 0.77)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Palette.darkBg)
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { shown = true }
        .sheet(isPresented: $showLanguages) { LanguageSheet() }
    }

    private func finish(signIn: Bool) {
        settings.onboardingSeen = true
        if signIn { router.push(.login(redirect: nil)) }
    }
}
