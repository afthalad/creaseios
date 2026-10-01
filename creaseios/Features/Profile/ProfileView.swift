import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.locale) private var locale
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var showTheme = false
    @State private var showLanguage = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let profile = session.profile {
                    signedIn(profile)
                } else if session.loading && session.uid != nil {
                    SkeletonList(count: 3)
                } else {
                    signedOut
                }
            }
            .padding(16)
        }
        .screenBackground()
        .brandTitle("profileTitle")
        .brandNavBar()
        .alert("profileEditName", isPresented: $editingName) {
            TextField("loginNameHint", text: $nameDraft).textInputAutocapitalization(.words)
            Button("cancel", role: .cancel) {}
            Button("save") { session.updateName(nameDraft) }
        }
        .alert("profileSignOutTitle", isPresented: $confirmSignOut) {
            Button("cancel", role: .cancel) {}
            Button("profileSignOut", role: .destructive) { session.signOut() }
        } message: {
            Text("profileSignOutBody")
        }
        .sheet(isPresented: $showTheme) { ThemeSheet() }
        .sheet(isPresented: $showLanguage) { LanguageSheet() }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill")
                .font(.system(size: 34))
                .foregroundStyle(Palette.ink3)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Palette.sunk))
            Text("profileJoinSubtitle")
                .font(AppFont.body(15))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
            Button("profileSignIn") { router.push(.login(redirect: nil)) }.primaryButton()
            preferences.padding(.top, 12)
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func signedIn(_ profile: UserProfile) -> some View {
        HStack(spacing: 14) {
            if let player = session.player {
                PlayerPhoto(photoURL: player.photoUrl, gender: player.gender, size: 64)
            } else {
                PlayerAvatar(name: profile.name, size: 64, highlighted: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    nameDraft = profile.name
                    editingName = true
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if profile.name.isEmpty { Text("profileNoName") } else { Text(verbatim: profile.name) }
                        }
                        .font(AppFont.heading(20, .bold))
                        .foregroundStyle(Palette.ink)
                        Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    }
                }
                .buttonStyle(.plain)
                Text(verbatim: profile.phone).font(AppFont.mono(13)).foregroundStyle(Palette.ink3)
            }
            Spacer()
        }
        .card()

        title("playerProfile")
        Group {
            if let player = session.player {
                HStack(spacing: 12) {
                    PlayerPhoto(photoURL: player.photoUrl, gender: player.gender, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: player.name).font(AppFont.body(15, .semibold)).foregroundStyle(Palette.ink)
                        Text(verbatim: player.summary(locale, includeGender: true)).font(AppFont.body(12.5)).foregroundStyle(Palette.ink3)
                    }
                    Spacer()
                    Button("edit") { router.push(.playerProfileEdit) }.font(AppFont.body(14, .semibold))
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("playerProfileEmpty").font(AppFont.body(14)).foregroundStyle(Palette.ink2)
                    Button("playerProfileCreate") { router.push(.playerProfileEdit) }.primaryButton()
                }
            }
        }
        .card()

        row("teams", icon: "person.3.fill") { router.select(.teams) }.card(padding: 4).padding(.top, 8)

        preferences

        row("profileSignOut", icon: "rectangle.portrait.and.arrow.right", tint: Palette.wkt) { confirmSignOut = true }
            .card(padding: 4)
            .padding(.top, 8)

        Text("profileMemberSince \(profile.createdDate.formatted(.dateTime.month(.wide).year().locale(locale)))")
            .font(AppFont.body(12.5))
            .foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("profilePreferences")
            VStack(spacing: 0) {
                row("appearance", icon: "circle.lefthalf.filled", value: Text(settings.theme.label)) { showTheme = true }
                Divider().padding(.leading, 48)
                row("language", icon: "globe", value: Text(verbatim: settings.languageName)) { showLanguage = true }
            }
            .card(padding: 4)
        }
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key).font(AppFont.body(13, .semibold)).foregroundStyle(Palette.ink3).padding(.top, 8)
    }

    private func row(_ title: LocalizedStringKey, icon: String, tint: Color = Palette.ink2, value: Text? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
                Text(title).font(AppFont.body(15, .medium)).foregroundStyle(tint == Palette.wkt ? Palette.wkt : Palette.ink)
                Spacer()
                if let value { value.font(AppFont.body(14)).foregroundStyle(Palette.ink3) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink3)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 4) {
            SheetTitle(title: "appearance").padding(.bottom, 8)
            ForEach(SettingsStore.Theme.allCases, id: \.self) { theme in
                Button {
                    settings.theme = theme
                    dismiss()
                } label: {
                    HStack {
                        Text(theme.label).font(AppFont.body(16, .medium))
                        Spacer()
                        if settings.theme == theme { Image(systemName: "checkmark").foregroundStyle(Palette.six) }
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }
}
