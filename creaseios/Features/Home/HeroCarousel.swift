import SwiftUI

/// Swipeable 2:1 banners. Tapping one opens its link in Safari.
struct HeroCarousel: View {
    let banners: [Banner]
    @Environment(\.openURL) private var openURL
    @State private var current: String?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(banners) { banner in
                        Group {
                            if let link = banner.link {
                                Button { openURL(link) } label: { slide(banner) }.buttonStyle(.plain)
                            } else {
                                slide(banner)
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(banner.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)

            if banners.count > 1 { dots }
        }
    }

    private func slide(_ banner: Banner) -> some View {
        Color.clear
            .aspectRatio(Banner.aspectRatio, contentMode: .fit)
            .overlay {
                if let url = banner.image {
                    RemoteImage(url: url) { Skeleton(height: nil, radius: 0) }
                } else {
                    Palette.sunk
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(banners) { banner in
                let selected = banner.id == (current ?? banners.first?.id)
                Capsule()
                    .fill(selected ? Palette.btn : Palette.line)
                    .frame(width: selected ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}

/// Holds the carousel's space while banners load.
struct HeroPlaceholder: View {
    var body: some View {
        Color.clear
            .aspectRatio(Banner.aspectRatio, contentMode: .fit)
            .overlay { Skeleton(height: nil, radius: 18) }
    }
}

#if DEBUG
#Preview("Hero carousel") {
    ScrollView { HeroCarousel(banners: Banner.samples).padding() }
        .screenBackground()
}

#Preview("Hero single") {
    HeroCarousel(banners: [Banner.samples[0]]).padding().screenBackground()
}

#Preview("Hero placeholder") {
    HeroPlaceholder().padding().screenBackground()
}
#endif
