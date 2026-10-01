import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// Flutter stores colours as 32-bit ARGB ints.
    init(argb: Int) {
        let v = UInt32(truncatingIfNeeded: argb)
        self.init(hex: v & 0xFFFFFF, alpha: Double((v >> 24) & 0xFF) / 255)
    }

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
    static let liveScore = Color.dynamic(0x17503A, 0xC9F24B)
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
    static let darkBg = Color(hex: 0x0B0E0C)
}

enum AppFont {
    static func heading(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Bricolage Grotesque", size: size).weight(weight)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("Geist Mono", size: size).weight(weight)
    }
    static let score = mono(40, .semibold)
}

extension View {
    /// Main action: system `.borderedProminent`, large, filling the available width.
    func primaryButton(tint: Color = Palette.btn) -> some View {
        buttonStyle(.borderedProminent).tint(tint).controlSize(.large).flexibleButtonSizing()
    }

    /// Secondary action: system `.bordered`, large, filling the available width.
    func secondaryButton(tint: Color = Palette.ink) -> some View {
        buttonStyle(.bordered).tint(tint).controlSize(.large).flexibleButtonSizing()
    }

    @ViewBuilder
    func flexibleButtonSizing() -> some View {
        if #available(iOS 26.0, *) {
            buttonSizing(.flexible)
        } else {
            self
        }
    }

    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.surface))
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
    }

    func fieldStyle() -> some View {
        self.font(AppFont.body(15))
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.sunk))
    }

    func appear(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .animation(.easeOut(duration: 0.6).delay(delay), value: shown)
    }

    /// On iOS 26, taps on empty parts of a pushed screen fall through to the screen below; claim them here.
    func claimsBackgroundTaps() -> some View {
        contentShape(Rectangle()).onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    func screenBackground() -> some View {
        background(Palette.bg.ignoresSafeArea())
    }

    /// A left-aligned screen title next to the back button, as on Android.
    /// Pass `onClose` to swap the back button for a close (X) button in front of the title.
    func brandTitle(_ title: LocalizedStringKey, onClose: (() -> Void)? = nil) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 20) {
                    if let onClose {
                        Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 18, weight: .medium)) }
                    }
                    Text(title)
                        .font(AppFont.heading(20, .bold))
                        .foregroundStyle(Palette.onBrand)
                }
                .fixedSize()
            }
            .withoutGlass()
        }
        .navigationBarBackButtonHidden(onClose != nil)
        .navigationBarTitleDisplayMode(.inline)
    }

    func brandNavBar() -> some View {
        modifier(BrandNavBar())
    }
}

/// `.toolbarColorScheme(.dark)` puts the bar in dark mode, which would resolve the adaptive brand
/// green to its darker dark-mode shade. Resolving it against the screen's own appearance first keeps
/// the bar the same green as the content under it.
private struct BrandNavBar: ViewModifier {
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        content
            .toolbarBackground(Color(Palette.brand.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension ToolbarContent {
    /// Drops the iOS 26 glass capsule behind a toolbar item.
    @ToolbarContentBuilder
    func withoutGlass() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
