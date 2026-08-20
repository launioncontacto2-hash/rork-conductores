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
                        ForEach(store.notices) { notice in
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
