import SwiftUI

extension Color {
    /// Team colours are stored as 32-bit ARGB ints, Flutter's format.
    init(argb: Int) {
        let v = UInt32(truncatingIfNeeded: argb)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: Double((v >> 24) & 0xFF) / 255)
    }
}

/// App colours (ESPNcricinfo navy and blue). Each name is a colour set with light and dark
/// variants in Assets.xcassets/Colors.
enum Palette {
    static let bg = Color("Bg")
    static let surface = Color("Surface")
    static let surface2 = Color("Surface2")
    static let sunk = Color("Sunk")
    static let ink = Color("Ink")
    static let ink2 = Color("Ink2")
    static let ink3 = Color("Ink3")
    static let line = Color("Line")
    static let brand = Color("Brand")
    static let brand2 = Color("Brand2")
    static let btn = Color("Btn")
    static let highlight = Color("Highlight")
    static let onHighlight = Color("OnHighlight")
    static let onBrand = Color("OnBrand")
    static let onBrand2 = Color("OnBrand2")
    static let allRounder = Color("AllRounder")
    static let live = Color("Live")
    static let four = Color("Four")
    static let six = Color("Six")
    static let wicket = Color("Wicket")
    static let extra = Color("Extra")
    static let darkBg = Color("DarkBg")
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

    /// Cross-fades the view when `value` changes, so loaded data eases in instead of popping.
    func smoothChange<V: Equatable>(_ value: V) -> some View {
        animation(.easeInOut(duration: 0.25), value: value)
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
                        .foregroundStyle(Palette.ink)
                }
                .fixedSize()
            }
            .withoutGlass()
        }
        .navigationBarBackButtonHidden(onClose != nil)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A transparent navigation bar; iOS blurs content as it scrolls underneath.
    func clearNavBar() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
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
