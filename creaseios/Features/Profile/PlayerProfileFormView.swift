import SwiftUI
import PhotosUI

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
    @State private var loaded = false

    private var canSave: Bool { !saving && gender != nil && !name.trimmed.isEmpty }

    var body: some View {
        let photoURL = session.player?.photoUrl
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if setup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("playerProfileSetupTitle").font(AppFont.heading(24, .heavy)).foregroundStyle(Palette.ink)
                        Text("playerProfileSetupSubtitle").font(AppFont.body(15)).foregroundStyle(Palette.ink2)
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    PlayerPhoto(photoURL: photoURL, image: photo, gender: gender, size: 112)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.onAccent)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Palette.accent))
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                section("playerName") {
                    TextField("playerName", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .fieldStyle()
                }
                section("playerGender") {
                    Picker("playerGender", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                section("playerRoleLabel") {
                    FlowLayout {
                        ForEach(PlayerRole.allCases, id: \.self) { r in
                            ChoiceChip(title: r.label, selected: role == r) { role = r }
                        }
                    }
                }
                section("playerBattingStyle") {
                    Picker("playerBattingStyle", selection: $batting) {
                        ForEach(BattingStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                section("playerBowlingStyle") {
                    Picker("playerBowlingStyle", selection: $bowling) {
                        ForEach(BowlingStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldStyle()
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            Button { Task { await save() } } label: {
                if saving { ProgressView().tint(Palette.onBrand) } else { Text("save") }
            }
            .primaryButton()
            .disabled(!canSave)
            .padding(16)
            .background(Palette.bg)
        }
        .navigationTitle(setup ? "playerProfile" : (session.player == nil ? "playerProfileCreate" : "playerProfileEdit"))
        .navigationBarTitleDisplayMode(.inline)
        .brandNavBar()
        .navigationBarBackButtonHidden(setup)
        .toolbar {
            if setup {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("skip") { finish() }.disabled(saving).tint(Palette.onBrand)
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: session.player) { _, _ in load() }
        .onChange(of: session.profile) { _, _ in load() }
        .alert("playerProfileSaveError", isPresented: $failed) { Button("ok") {} }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AppFont.body(13, .semibold)).foregroundStyle(Palette.ink3)
            content()
        }
        .card()
    }

    private func load() {
        guard !loaded, session.profile != nil || session.player != nil else { return }
        loaded = true
        name = session.player?.name ?? session.profile?.name ?? ""
        gender = session.player?.gender
        role = session.player?.role ?? .batter
        batting = session.player?.battingStyle ?? .rhb
        bowling = session.player?.bowlingStyle ?? .none
    }

    private func save() async {
        guard let uid = session.uid, let gender else { return }
        saving = true
        defer { saving = false }
        let p = PlayerProfile(uid: uid, name: name.trimmed, gender: gender, photoUrl: session.player?.photoUrl,
                              role: role, battingStyle: batting, bowlingStyle: bowling)
        do {
            try await env.players.save(p, photo: photo?.jpegForUpload())
            finish()
        } catch {
            failed = true
        }
    }

    private func finish() {
        router.pop()
        if let redirect { router.open(path: redirect) }
    }
}
