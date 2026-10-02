import SwiftUI
import FirebaseAuth

enum AuthStep: Int { case phone, code, name, createPlayer, done }

enum AuthError: Error {
    case invalidPhone, invalidCode, codeExpired, tooManyRequests, quotaExceeded, network, sendFailed, saveName, unknown

    var key: LocalizedStringKey {
        switch self {
        case .invalidPhone: "authErrorInvalidPhone"
        case .invalidCode: "authErrorInvalidCode"
        case .codeExpired: "authErrorCodeExpired"
        case .tooManyRequests: "authErrorTooManyRequests"
        case .quotaExceeded: "authErrorQuotaExceeded"
        case .network: "authErrorNetwork"
        case .sendFailed: "authErrorSendFailed"
        case .saveName: "authErrorSaveName"
        case .unknown: "errorGeneric"
        }
    }

    init(_ error: Error) {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
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
        submitting = true
        error = nil
        phone = e164
        do {
            verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil)
            step = .code
        } catch {
            self.error = AuthError(error)
        }
        submitting = false
    }

    func submitCode(_ code: String) async {
        guard let verificationID, !submitting else { return }
        submitting = true
        error = nil
        do {
            let cred = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
            let uid = try await Auth.auth().signIn(with: cred).user.uid
            step = try await users.get(uid) == nil ? .name : .done
        } catch {
            self.error = AuthError(error)
        }
        submitting = false
    }

    func submitName(_ name: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try users.save(UserProfile(uid: uid, phone: phone, name: name.trimmed, createdAt: ISODate.string(.now)))
            step = .createPlayer
        } catch {
            self.error = .saveName
        }
    }
}

struct PhoneLoginView: View {
    let redirect: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var model: PhoneAuthModel?

    var body: some View {
        Group {
            if let model { PhoneLoginContent(model: model, redirect: redirect) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.darkBg.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if model == nil { model = PhoneAuthModel(users: env.users) } }
    }
}

private struct PhoneLoginContent: View {
    @Bindable var model: PhoneAuthModel
    let redirect: String?
    @Environment(Router.self) private var router
    @State private var digits = ""
    @State private var code = ""
    @State private var name = ""
    @State private var secondsLeft = 30
    @FocusState private var focused: Bool

    private var normalized: String { digits.hasPrefix("0") ? String(digits.dropFirst()) : digits }
    private var phoneValid: Bool { normalized.wholeMatch(of: /7\d{8}/) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Group {
                switch model.step {
                case .phone: phoneStep
                case .code: codeStep
                default: nameStep
                }
            }
            .id(model.step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 48)), removal: .opacity))
            .padding(.top, 32)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.35), value: model.step)
        .onChange(of: model.step) { _, step in
            switch step {
            case .createPlayer: router.replace(with: .playerProfileSetup(redirect: redirect))
            case .done:
                router.pop()
                if let redirect { router.open(path: redirect) }
            default: break
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                if model.step == .code { model.step = .phone; model.error = nil; code = "" } else { router.pop() }
            } label: {
                Image(systemName: "chevron.left").fontWeight(.semibold).foregroundStyle(.white)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.white)
            .controlSize(.large)
            .opacity(model.step == .name ? 0 : 1)
            .disabled(model.step == .name)
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i <= min(model.step.rawValue, 2) ? Palette.accent : .white.opacity(0.12))
                        .frame(height: 3)
                }
            }
        }
        .padding(.top, 8)
    }

    private func header(_ title: LocalizedStringKey, _ subtitle: Text) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AppFont.heading(28, .heavy)).foregroundStyle(.white)
            subtitle.font(AppFont.body(16)).foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder private var errorRow: some View {
        if let error = model.error {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(error.key)
            }
            .font(AppFont.body(14))
            .foregroundStyle(Palette.wkt)
            .padding(.top, 14)
        }
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("loginPhoneTitle", Text("loginPhoneSubtitle"))
            HStack(spacing: 10) {
                Text(verbatim: "🇱🇰  +94")
                    .font(AppFont.mono(17, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                TextField("loginPhoneHint", text: $digits)
                    .font(AppFont.mono(17, .medium))
                    .foregroundStyle(.white)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
                    .onChange(of: digits) { _, v in digits = String(v.filter(\.isNumber).prefix(10)) }
            }
            .padding(.top, 28)
            errorRow
            Spacer()
            PillButton(title: "loginSendCode", loading: model.submitting) {
                Task { await model.sendCode("+94" + normalized) }
            }
            .disabled(!phoneValid)
            .opacity(phoneValid ? 1 : 0.5)
        }
        .onAppear { focused = true }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("loginCodeTitle", Text("loginCodeSubtitle \(model.phone)"))
            OTPField(code: $code, hasError: model.error == .invalidCode) { c in
                Task { await model.submitCode(c) }
            }
            .padding(.top, 28)
            errorRow
            HStack {
                if secondsLeft > 0 {
                    Text("loginResendIn \(secondsLeft)").foregroundStyle(.white.opacity(0.5))
                } else {
                    Button("loginResend") {
                        code = ""
                        Task { await model.sendCode(model.phone); secondsLeft = 30 }
                    }
                    .foregroundStyle(Palette.accent)
                }
                Spacer()
                Button("loginChangeNumber") { model.step = .phone; model.error = nil; code = "" }
                    .foregroundStyle(.white.opacity(0.8))
            }
            .font(AppFont.body(14, .medium))
            .padding(.top, 20)
            Spacer()
            PillButton(title: "loginVerify", loading: model.submitting) {
                Task { await model.submitCode(code) }
            }
            .disabled(code.count < 6)
            .opacity(code.count < 6 ? 0.5 : 1)
        }
        .task(id: model.phone) {
            secondsLeft = 30
            while secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                secondsLeft -= 1
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("loginNameTitle", Text("loginNameSubtitle"))
            HStack(spacing: 14) {
                Text(verbatim: name.trimmed.first.map { String($0).uppercased() } ?? "")
                    .font(AppFont.heading(26, .bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Palette.accent))
                TextField("loginNameHint", text: $name)
                    .font(AppFont.body(17, .medium))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.name)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
            }
            .padding(.top, 28)
            errorRow
            Spacer()
            PillButton(title: "loginFinish") { model.submitName(name) }
                .disabled(name.trimmed.isEmpty)
                .opacity(name.trimmed.isEmpty ? 0.5 : 1)
        }
        .onAppear { focused = true }
    }
}

struct OTPField: View {
    @Binding var code: String
    var hasError = false
    var onComplete: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.01)
                .onChange(of: code) { _, v in
                    let clean = String(v.filter(\.isNumber).prefix(6))
                    if clean != code { code = clean; return }
                    if clean.count == 6 { onComplete(clean) }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let chars = Array(code)
                    Text(verbatim: i < chars.count ? String(chars[i]) : "")
                        .font(AppFont.mono(24, .semibold))
                        .foregroundStyle(.white)
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
