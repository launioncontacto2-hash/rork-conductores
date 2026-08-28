import SwiftUI

/// Station communication: maintenance, credit payments, station notices and reminders.
struct NoticesView: View {
    @Environment(FleetStore.self) private var store

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        // Provenance, not the raw array: a notice written by a laboratory
                        // session is not something the station said.
                        if store.visibleNotices.isEmpty {
                            emptyState
                        }
                        ForEach(store.visibleNotices) { notice in
                            Button {
                                store.markNoticeRead(id: notice.id)
                            } label: {
                                noticeRow(notice)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Avisos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.unreadNoticeCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.markAllNoticesRead()
                        } label: {
                            Label("Marcar leídos", systemImage: "checkmark.circle")
                                .font(.system(.caption, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    /// An empty bell is a legitimate state, and the honest one for a proved identity:
    /// the station has published nothing because it cannot publish yet.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
                .frame(width: 62, height: 62)
                .background(Palette.surfaceRaised.opacity(0.6), in: .circle)

            Text("Sin avisos")
                .font(.system(.subheadline, weight: .bold))

            Text(store.canPublishStationNotices
                 ? "Aquí aparecerán los avisos de tu estación."
                 : "Los avisos los publica el sistema operativo de tu estación. En cuanto la aplicación quede conectada, los verás aquí.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }

    private func noticeRow(_ notice: Notice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.kind.symbol)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(tone(notice.kind))
                .frame(width: 40, height: 40)
                .background(tone(notice.kind).opacity(0.12), in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    CapsLabel(text: notice.kind.label)
                    if !notice.read {
                        Circle()
                            .fill(Palette.danger)
                            .frame(width: 6, height: 6)
                    }
                    Spacer(minLength: 4)
                    Text(Fmt.relative(notice.createdAt, from: store.now))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }

                Text(notice.title)
                    .font(.system(.subheadline, weight: .bold))
                    .multilineTextAlignment(.leading)

                Text(notice.body)
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            notice.read ? Palette.surfaceRaised.opacity(0.5) : Palette.surface.opacity(0.9),
            in: .rect(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(notice.read ? Palette.hairline : Palette.volt.opacity(0.3), lineWidth: 1)
        }
    }

    private func tone(_ kind: NoticeKind) -> Color {
        switch kind {
        case .maintenance: Palette.info
        case .credit: Palette.amber
        case .station: Palette.volt
        case .reminder: Palette.textMuted
        }
    }
}

#Preview {
    NoticesView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
