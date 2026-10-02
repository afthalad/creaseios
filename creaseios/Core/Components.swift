import SwiftUI

struct BallChip: View {
    let token: String
    var size: CGFloat = 26

    var body: some View {
        let s = style
        Text(verbatim: token)
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
            if ["wd", "nb", "lb", "b"].contains(where: token.hasPrefix) { return (.clear, Palette.extra, Palette.extra) }
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
        Group {
            if secondary {
                Button(action: action) { label.foregroundStyle(.white) }.secondaryButton(tint: .white)
            } else {
                Button(action: action) { label.foregroundStyle(Palette.onAccent) }.primaryButton(tint: Palette.accent)
            }
        }
        .disabled(loading)
        .opacity(loading ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.2), value: loading)
    }

    private var label: some View {
        ZStack {
            if loading { ProgressView().tint(secondary ? .white : Palette.onAccent) }
            else { Text(title).font(AppFont.body(16, .bold)) }
        }
    }
}

struct TeamBadge: View {
    let shortName: String
    let color: Color
    var logoURL: String? = nil
    var image: UIImage? = nil
    var size: CGFloat = 30
    var circular = false

    var body: some View {
        let shape = circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.3))
        ZStack {
            shape.fill(color)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = logoURL.flatMap(URL.init) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { label }
            } else {
                label
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private var label: some View {
        Text(verbatim: String(shortName.prefix(3)).uppercased())
            .font(AppFont.heading(size * 0.35, .bold))
            .tracking(0.3)
            .foregroundStyle(.white)
    }
}

struct PlayerAvatar: View {
    let name: String
    var photoURL: String? = nil
    var size: CGFloat = 40
    var highlighted = false
    var teamColor: Color? = nil
    var bordered = false

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    var body: some View {
        let tc = teamColor ?? Palette.ink2
        ZStack {
            Circle().fill(highlighted ? Palette.accent : tc.opacity(0.16))
            if let url = photoURL.flatMap(URL.init) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { label(tc) }
            } else {
                label(tc)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { if bordered { Circle().stroke(tc.opacity(0.3), lineWidth: 1.5) } }
    }

    private func label(_ tc: Color) -> some View {
        Text(verbatim: initials.isEmpty ? "?" : initials)
            .font(AppFont.heading(size * 0.33, .bold))
            .foregroundStyle(highlighted ? Palette.brand : tc)
    }
}

struct PlayerPhoto: View {
    var photoURL: String? = nil
    var image: UIImage? = nil
    var gender: Gender? = nil
    var size: CGFloat = 44

    var body: some View {
        let placeholder = Image(gender == .female ? "cricketer_female" : "cricketer").resizable().scaledToFill()
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = photoURL.flatMap(URL.init) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Palette.sunk)
        .clipShape(Circle())
    }
}

/// Three stumps and bails, drawn on a 24 x 24 grid.
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

struct Wordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            CreaseLogo(size: size + 2)
            Text(verbatim: "crease")
                .font(AppFont.heading(size, .heavy))
                .tracking(-0.5)
                .foregroundStyle(.white)
        }
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

struct SkeletonList: View {
    var count = 4

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in Skeleton(height: 84, radius: 18) }
        }
        .padding(16)
    }
}

struct MessageView: View {
    let text: LocalizedStringKey
    var systemImage: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 32)).foregroundStyle(Palette.ink3)
            }
            Text(text)
                .font(AppFont.body(14))
                .foregroundStyle(Palette.ink3)
                .multilineTextAlignment(.center)
            if let retry {
                Button("retry", action: retry).buttonStyle(.borderedProminent).tint(Palette.btn).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 64)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title).textCase(.uppercase).font(AppFont.body(11.5, .semibold)).tracking(1)
            if let count { Text(verbatim: "\(count)").font(AppFont.mono(11.5, .medium)) }
        }
        .foregroundStyle(Palette.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }
}

struct ExpandableCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var initiallyExpanded = false
    @ViewBuilder let content: Content
    @State private var expanded: Bool?

    var body: some View {
        let isOpen = expanded ?? initiallyExpanded
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded = !isOpen }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(AppFont.body(17, .medium)).foregroundStyle(Palette.ink)
                        if let subtitle { Text(verbatim: subtitle).font(AppFont.body(12.5)).foregroundStyle(Palette.ink3) }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Palette.ink3)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { content }
        }
        .card()
    }
}

struct ChoiceChip: View {
    let title: LocalizedStringKey
    let selected: Bool
    var onBrand = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.body(13.5, .semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(foreground)
                .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if onBrand { return selected ? Palette.onAccent : Palette.onBrand2 }
        return selected ? Palette.onBrand : Palette.ink2
    }

    private var background: Color {
        if onBrand { return selected ? Palette.accent : .white.opacity(0.08) }
        return selected ? Palette.brand : Palette.sunk
    }
}

/// Equal-width tabs with a short accent underline, drawn on the brand header.
struct UnderlineTabs<Tab: Hashable>: View {
    let tabs: [(tab: Tab, title: LocalizedStringKey)]
    @Binding var selection: Tab
    /// Dark text and a brand-green underline, for light surfaces instead of the brand header.
    var onSurface = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tab) { item in
                let selected = item.tab == selection
                Button { selection = item.tab } label: {
                    Text(item.title)
                        .font(AppFont.body(16, .medium))
                        .foregroundStyle(onSurface ? (selected ? Palette.ink : Palette.ink3) : (selected ? Palette.onBrand : Palette.onBrand2))
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            if selected { Capsule().fill(onSurface ? Palette.btn : Palette.accent).frame(height: 3) }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(onSurface ? Palette.line : Color.white.opacity(0.08)).frame(height: 1) }
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

/// Two or more equal-width capsules, the selected one filled with ink.
struct PillSegments<Tab: Hashable>: View {
    let tabs: [(tab: Tab, title: String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tabs, id: \.tab) { item in
                let selected = item.tab == selection
                Button { selection = item.tab } label: {
                    Text(verbatim: item.title)
                        .font(AppFont.body(15, .medium))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Palette.surface : Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(selected ? Palette.ink : Palette.sunk))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A batter at the crease: striker marker, name, then runs and balls.
struct BatterLine: View {
    let name: String
    let runs: Int
    let balls: Int
    let striker: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 8))
                .foregroundStyle(Palette.six)
                .frame(width: 10)
                .opacity(striker ? 1 : 0)
            Text(verbatim: name)
                .font(AppFont.body(16, striker ? .semibold : .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "\(runs)").font(AppFont.mono(16, .semibold)).foregroundStyle(Palette.ink)
                Text(verbatim: "(\(balls))").font(AppFont.mono(13)).foregroundStyle(Palette.ink3)
            }
        }
        .padding(.vertical, 8)
    }
}

/// The current bowler with figures as overs-runs-wickets.
struct BowlerLine: View {
    let name: String
    let figures: String

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 10, height: 1)
            Text(verbatim: name).font(AppFont.body(15)).foregroundStyle(Palette.ink2).lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: figures).font(AppFont.mono(15, .medium)).foregroundStyle(Palette.ink)
        }
        .padding(.vertical, 8)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> (width: CGFloat, height: CGFloat) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return (width, y + rowHeight)
    }
}

struct SheetTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(AppFont.heading(22, .bold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LanguageSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 4) {
            SheetTitle(title: "language").padding(.bottom, 8)
            ForEach(appLanguages, id: \.code) { lang in
                Button {
                    settings.languageCode = lang.code
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: lang.name).font(AppFont.body(16, .medium))
                        Spacer()
                        if settings.languageName == lang.name { Image(systemName: "checkmark").foregroundStyle(Palette.six) }
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
