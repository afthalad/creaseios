import SwiftUI

struct MatchCard: View {
    let match: Match
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.locale) private var locale

    private var isFavorite: Bool { session.profile?.favoriteMatchIds.contains(match.id) == true }
    private var hasReminder: Bool { session.profile?.reminderMatchIds.contains(match.id) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    teamRow(match.teamA)
                    teamRow(match.teamB)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Palette.line).frame(width: 1, height: 56)
                trailing.frame(width: 100)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.surface))
        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 4) {
            (Text(match.format.label) + Text(verbatim: match.venueName.map { ", \($0)" } ?? ""))
                .lineLimit(1)
            Spacer()
            if match.status == .upcoming {
                toggle(on: hasReminder, icon: "bell", onIcon: "bell.badge.fill") { setReminder(!hasReminder) }
            }
            toggle(on: isFavorite, icon: "heart", onIcon: "heart.fill") { setFavorite(!isFavorite) }
        }
        .font(AppFont.body(10, .regular))
        .foregroundStyle(Palette.ink3)
        .frame(minHeight: 32)
    }

    private func toggle(on: Bool, icon: String, onIcon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? onIcon : icon)
                .font(.system(size: 15))
                .foregroundStyle(on ? Palette.live : Palette.ink3)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func teamRow(_ team: MatchTeam) -> some View {
        let score = match.scores[team.side]
        let batting = match.battingSide == team.side && match.status == .live
        return HStack(spacing: 8) {
            TeamBadge(shortName: team.shortName, color: team.uiColor, logoURL: team.logoUrl, size: 28, circular: true)
                .padding(.trailing, 4)
            Text(verbatim: team.shortName)
                .font(AppFont.body(12, .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            if let score {
                Text(verbatim: "\(score.runs)-\(score.wickets)")

                    .fontWeight(.bold)
                    .fontWeight(.medium)
                    .fixedSize()
                    .foregroundStyle( Palette.ink2)
                Text(verbatim: score.overs(match.config.ballsPerOver))
                    .fontWeight(.medium)
                    .font(.caption)
                    .fixedSize()
                    .foregroundStyle(batting ? Palette.ink : Palette.ink3)
                if batting { Image(systemName: "cricket.ball.fill").font(.system(size: 11)).foregroundStyle(Palette.ink) }
            } else if match.status == .live && !match.scores.isEmpty {
                Text("yetToBat").font(AppFont.body(13)).foregroundStyle(Palette.ink3)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch match.status {
        case .live:
            HStack(spacing: 6) {
                PulsingDot()
                Text("filterLive").font(AppFont.body(14, .semibold)).foregroundStyle(Palette.live)
            }
        case .upcoming:
            if let date = match.scheduledDate {
                VStack(spacing: 2) {
                    dayLabel(date).font(AppFont.body(15, .medium)).foregroundStyle(Palette.ink2)
                    Text(verbatim: date.formatted(.dateTime.hour().minute().locale(locale)))
                        .font(AppFont.body(17, .semibold))
                        .foregroundStyle(Palette.ink3)
                }
            } else {
                Text("statusUpcoming").font(AppFont.body(14, .medium)).foregroundStyle(Palette.ink3)
            }
        case .pending:
            Text("memberPending").font(AppFont.body(14, .semibold)).foregroundStyle(Palette.extra)
        case .completed:
            Text(verbatim: match.shortResultText ?? "")
                .font(AppFont.body(13.5, .semibold))
                .foregroundStyle(Palette.six)
                .multilineTextAlignment(.center)
        case .abandoned:
            Text("statusAbandoned").font(AppFont.body(14, .medium)).foregroundStyle(Palette.ink3)
        }
    }

    private func dayLabel(_ date: Date) -> Text {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return Text("dayToday") }
        if cal.isDateInTomorrow(date) { return Text("dayTomorrow") }
        return Text(verbatim: date.formatted(.dateTime.month(.abbreviated).day().locale(locale)))
    }

    private func setFavorite(_ on: Bool) {
        router.requireAuth(session) {
            guard let uid = session.uid else { return }
            NotificationService.shared.follow(match.id, on)
            Task { try? await env.users.setFavorite(uid, match.id, on) }
        }
    }

    private func setReminder(_ on: Bool) {
        router.requireAuth(session) {
            guard let uid = session.uid else { return }
            NotificationService.shared.remind(match.id, on)
            Task { try? await env.users.setReminder(uid, match.id, on) }
        }
    }
}

#if DEBUG
#Preview("Match cards") {
    ScrollView {
        VStack(spacing: 10) {
            ForEach([Match.live, .pending, .upcoming, .completed]) { MatchCard(match: $0) }
        }
        .padding()
    }
    .screenBackground()
    .previewEnvironment()
}
#endif
