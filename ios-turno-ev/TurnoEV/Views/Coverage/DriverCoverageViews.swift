import SwiftUI
import UIKit

/// Conductor → Turnos. Everything the driver can do about their own schedule without
/// calling anybody: read the month, ask for an absence, take a guard, follow a request
/// and check the turns they are covering for somebody else.
struct DriverShiftsView: View {
    @Environment(FleetStore.self) private var store
    @Environment(CoverageStore.self) private var coverage

    @State private var route: ShiftsRoute?

    private enum ShiftsRoute: Hashable, Identifiable {
        case calendar
        case requestAbsence
        case emergency
        case guards
        case requests
        case replacements
        case swap

        var id: Self { self }
    }

    private var profile: CoverageDriverProfile { coverage.profile(for: store.driver) }

    private var openRequests: Int {
        coverage.absences(driverId: profile.id).filter { $0.status.isOpen }.count
    }

    private var availableGuards: Int {
        coverage.availableGuards(for: profile).count
    }

    private var activeGuards: Int {
        coverage.activeGuards(driverId: profile.id).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        todayCard
                        if availableGuards > 0 { guardBanner }
                        pendingSwapBanner
                        options
                        bonusCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Turnos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SessionMenuButton() }
            }
            .fullScreenCover(item: $route) { destination in
                switch destination {
                case .calendar: DriverCoverageCalendarView(profile: profile)
                case .requestAbsence: AbsenceRequestFormView(profile: profile, isEmergency: false)
                case .emergency: AbsenceRequestFormView(profile: profile, isEmergency: true)
                case .guards: AvailableGuardsView(profile: profile)
                case .requests: MyCoverageRequestsView(profile: profile)
                case .replacements: MyReplacementsView(profile: profile)
                case .swap: SwapProposalView(profile: profile)
                }
            }
        }
    }

    // MARK: - Today

    private var todayCard: some View {
        // The day itself is what the clock decides here, and the day drives the entire
        // card: the pill, the three facts, the closing line. So the card is the smallest
        // honest unit — and the scope stops at it. The `ScrollView` above, the guard
        // banner, the option rows and the bonus card are never re-evaluated by the clock.
        TimeScope(.minute) { now in
            let today = coverage.day(for: profile, on: now)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        CapsLabel(text: "Hoy")
                        Text(Fmt.dateLong(now).capitalized)
                            .font(.system(.title3, weight: .black))
                    }
                    Spacer(minLength: 6)
                    CoveragePill(text: today.kind.label, symbol: today.kind.symbol, tone: today.kind.tone)
                }

                HStack(spacing: 8) {
                    CoverageFact(label: "Horario", value: today.slot?.rangeLabel ?? "—")
                    CoverageFact(label: "Estación", value: today.stationCode)
                    CoverageFact(label: "Bloque", value: "\(profile.slot.label) · \(profile.group.label)")
                }

                Text(today.detail)
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(16)
            .panel()
        }
    }

    private var guardBanner: some View {
        Button {
            route = .guards
        } label: {
            NoticeBanner(
                symbol: "bell.badge.fill",
                title: "\(availableGuards) guardia\(availableGuards == 1 ? "" : "s") disponible\(availableGuards == 1 ? "" : "s") para ti",
                message: "Son turnos para los que cumples todas las reglas. Tócalos para ver el bono y tomarlos.",
                tone: .volt
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pendingSwapBanner: some View {
        let incoming = coverage.swaps(driverId: profile.id).filter {
            $0.toDriverId == profile.id && $0.status == .proposed
        }
        if !incoming.isEmpty {
            Button {
                route = .requests
            } label: {
                NoticeBanner(
                    symbol: "arrow.left.arrow.right",
                    title: "Tienes \(incoming.count) intercambio\(incoming.count == 1 ? "" : "s") por responder",
                    message: "Un compañero propuso cambiar turno contigo. Nada cambia hasta que aceptes y el supervisor firme.",
                    tone: .info
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Options

    private var options: some View {
        VStack(spacing: 10) {
            optionRow(
                title: "Mi calendario",
                detail: "Turnos, guardias, ausencias, intercambios y días libres",
                symbol: "calendar",
                tint: CovTone.quiet
            ) { route = .calendar }

            optionRow(
                title: "Solicitar ausencia",
                detail: "Avisa con anticipación. Enviar no significa que quede autorizada",
                symbol: "calendar.badge.minus",
                tint: CovTone.pending
            ) { route = .requestAbsence }

            optionRow(
                title: "Ausencia de emergencia",
                detail: "El turno está por empezar y no puedes presentarte",
                symbol: "exclamationmark.triangle.fill",
                tint: CovTone.blocking
            ) { route = .emergency }

            optionRow(
                title: "Guardias disponibles",
                detail: "Solo las que puedes tomar según las reglas configuradas",
                symbol: "hand.raised.fill",
                tint: CovTone.good,
                badge: availableGuards
            ) { route = .guards }

            optionRow(
                title: "Mis solicitudes",
                detail: "Estado de tus ausencias e intercambios",
                symbol: "list.bullet.rectangle.portrait",
                tint: CovTone.closed,
                badge: openRequests
            ) { route = .requests }

            optionRow(
                title: "Mis reemplazos",
                detail: "Turnos que estás cubriendo para otro conductor",
                symbol: "person.2.badge.gearshape.fill",
                tint: CovTone.good,
                badge: activeGuards
            ) { route = .replacements }

            optionRow(
                title: "Solicitar intercambio",
                detail: "Propón cambiar tu turno con un compañero",
                symbol: "arrow.left.arrow.right",
                tint: CovTone.closed
            ) { route = .swap }
        }
    }

    private func optionRow(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.13), in: .rect(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .bold))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Palette.canvas)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(tint, in: .capsule)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(13)
            .panelFlat()
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Bonus

    @ViewBuilder
    private var bonusCard: some View {
        let earned = coverage.earnedGuardBonusMxn(driverId: profile.id)
        let completed = coverage.completedGuards(driverId: profile.id).count
        if completed > 0 {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Bonos por guardia")
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.mxn(earned))
                        .font(.system(.title2, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(CovTone.good)
                    Spacer(minLength: 6)
                    Text("\(completed) guardia\(completed == 1 ? "" : "s") completada\(completed == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Text("El bono se suma a tu liquidación solo cuando el turno queda completado, no al aceptarlo.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(16)
            .panel()
        }
    }
}

// MARK: - Calendar

/// The driver's month. Each square carries one reading, and tapping it opens the detail
/// of that day: date, window, station, unit if it is already assigned, type and state.
struct DriverCoverageCalendarView: View {
    let profile: CoverageDriverProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var monthOffset: Int = 0
    @State private var selected: CoverageCalendarDay?

    /// The day this calendar was opened on, captured once.
    ///
    /// Reading `coverage.now` from `month` made the anchor of the month, the highlight of
    /// today and the list of upcoming moves subscribe to the clock — and with them this
    /// whole sheet: its `NavigationStack`, its `ScrollView`, its forty-two cell
    /// `LazyVGrid`. None of those may sit inside a `TimeScope`, and none of them needs to:
    /// a month being browsed should not slide underneath the person browsing it. The
    /// anchor is taken when the sheet appears and holds until it is opened again.
    @State private var today: Date = AppClock.now()

    private var month: Date {
        ShiftRules.calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
    }

    private var days: [CoverageCalendarDay] { coverage.calendar(for: profile, month: month) }

    /// Blank squares before the first day so the grid lines up with the weekday header.
    private var leadingBlanks: Int {
        guard let first = days.first else { return 0 }
        let weekday = ShiftRules.calendar.component(.weekday, from: first.date)
        return (weekday + 5) % 7
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        monthHeader
                        grid
                        legend
                        upcoming
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Mi calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $selected) { day in
                CoverageDayDetailView(day: day, profile: profile)
                    .presentationDetents([.medium])
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.smooth) { monthOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(.footnote, weight: .black))
                    .frame(width: 34, height: 34)
                    .background(Palette.surfaceRaised, in: .circle)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(Fmt.monthLong(month).capitalized)
                    .font(.system(.headline, weight: .black))
                Text("\(profile.slot.label) · \(profile.group.label) · \(profile.stationCode)")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.smooth) { monthOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .black))
                    .frame(width: 34, height: 34)
                    .background(Palette.surfaceRaised, in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    private var grid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 46)
                }
                ForEach(days) { day in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        selected = day
                    } label: {
                        CoverageDaySquare(day: day, isToday: ShiftRules.isSameDay(day.date, today))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .panel()
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Qué significa cada color")
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 7) {
                ForEach(legendKinds, id: \.self) { kind in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(kind.tone)
                            .frame(width: 8, height: 8)
                        Text(kind.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .padding(14)
        .panel()
    }

    private var legendKinds: [CoverageDayKind] {
        [.regular, .rest, .guardConfirmed, .guardReserved, .absenceRequested, .absenceApproved, .swap, .extraordinary]
    }

    @ViewBuilder
    private var upcoming: some View {
        let next = days.filter {
            $0.date >= ShiftRules.calendar.startOfDay(for: today) && $0.kind != .rest && $0.kind != .regular
        }
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: "Próximos movimientos del mes")
                ForEach(next.prefix(6)) { day in
                    Button {
                        selected = day
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: day.kind.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(day.kind.tone)
                                .frame(width: 30, height: 30)
                                .background(day.kind.tone.opacity(0.13), in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.dateShort(day.date).capitalized)
                                    .font(.system(.subheadline, weight: .bold))
                                Text("\(day.kind.label) · \(day.statusLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            Spacer(minLength: 0)
                            if let bonus = day.bonusMxn {
                                Text(Fmt.mxn(bonus))
                                    .font(.system(size: 11, weight: .black))
                                    .monospacedDigit()
                                    .foregroundStyle(CovTone.good)
                            }
                        }
                        .padding(11)
                        .panelFlat()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .panel()
        }
    }
}

private struct CoverageDaySquare: View {
    let day: CoverageCalendarDay
    let isToday: Bool

    private var isMarked: Bool { day.kind != .regular && day.kind != .rest }

    var body: some View {
        VStack(spacing: 3) {
            Text(Fmt.dayNumber(day.date))
                .font(.system(size: 13, weight: isToday ? .black : .semibold))
                .monospacedDigit()
                .foregroundStyle(day.kind == .rest ? Palette.textMuted : .primary)
            Circle()
                .fill(day.kind.tone)
                .frame(width: isMarked ? 7 : 4, height: isMarked ? 7 : 4)
                .opacity(day.kind == .rest ? 0.35 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            isMarked ? day.kind.tone.opacity(0.12) : Palette.surfaceRaised.opacity(0.5),
            in: .rect(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(isToday ? Palette.volt : Color.clear, lineWidth: 1.5)
        }
    }
}

/// What a selected square actually means.
struct CoverageDayDetailView: View {
    let day: CoverageCalendarDay
    let profile: CoverageDriverProfile

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Fmt.dateLong(day.date).capitalized)
                                    .font(.system(.title3, weight: .black))
                                Text(day.detail)
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            Spacer(minLength: 6)
                            CoveragePill(text: day.kind.label, symbol: day.kind.symbol, tone: day.kind.tone, filled: true)
                        }

                        VStack(spacing: 0) {
                            DetailRow(label: "Fecha", value: Fmt.dateShort(day.date).capitalized)
                            Divider().overlay(Palette.hairline)
                            DetailRow(label: "Horario", value: day.slot?.rangeLabel ?? "Sin turno")
                            Divider().overlay(Palette.hairline)
                            DetailRow(label: "Estación", value: day.stationCode)
                            Divider().overlay(Palette.hairline)
                            DetailRow(label: "Vehículo", value: day.vehicleNumber ?? "Se asigna al iniciar")
                            Divider().overlay(Palette.hairline)
                            DetailRow(label: "Tipo de turno", value: day.kind.label)
                            Divider().overlay(Palette.hairline)
                            DetailRow(label: "Estado", value: day.statusLabel, tone: day.kind.tone)
                            if let bonus = day.bonusMxn {
                                Divider().overlay(Palette.hairline)
                                DetailRow(label: "Bono por guardia", value: Fmt.mxn(bonus), tone: CovTone.good)
                            }
                        }
                        .padding(.vertical, 4)
                        .panel()

                        if day.bonusMxn != nil {
                            Text("El bono se paga cuando el turno queda completado. Aceptar la guardia no lo genera.")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Detalle del día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Absence form

/// Asking for an absence. The screen says plainly, before and after sending, that a
/// request is not an authorization.
struct AbsenceRequestFormView: View {
    let profile: CoverageDriverProfile
    let isEmergency: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var date: Date = Date()
    @State private var slot: ShiftSlot = .morning
    @State private var kind: AbsenceKind = .scheduled
    @State private var reason: String = ""
    @State private var comments: String = ""
    @State private var hasEvidence: Bool = false
    @State private var sent: AbsenceRequest?

    private var requiresEvidence: Bool { kind == .leave }

    private var canSend: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!requiresEvidence || hasEvidence)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let sent {
                            confirmation(for: sent)
                        } else {
                            warning
                            form
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEmergency ? "Ausencia de emergencia" : "Solicitar ausencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent == nil ? "Cancelar" : "Cerrar") { dismiss() }
                }
            }
            .onAppear {
                slot = profile.slot
                if isEmergency {
                    kind = .emergency
                    date = coverage.now
                }
            }
        }
    }

    private var warning: some View {
        NoticeBanner(
            symbol: isEmergency ? "exclamationmark.octagon.fill" : "info.circle.fill",
            title: isEmergency
                ? "Esto abre una alerta crítica en la estación"
                : "Enviar una solicitud no autoriza tu ausencia",
            message: isEmergency
                ? "El supervisor recibe aviso prioritario y el sistema empieza a buscar sustituto de inmediato. Tu ausencia sigue necesitando autorización."
                : "El sistema buscará quién cubra tu unidad. Cubrir el turno y autorizar tu falta son dos decisiones distintas.",
            tone: isEmergency ? .danger : .info
        )
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Fecha")
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Palette.volt)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Turno")
                Picker("", selection: $slot) {
                    ForEach(ShiftSlot.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Tipo de ausencia")
                ForEach(AbsenceKind.allCases) { option in
                    Button {
                        kind = option
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(kind == option ? Palette.canvas : Palette.textMuted)
                                .frame(width: 32, height: 32)
                                .background(
                                    kind == option ? Palette.volt : Palette.surfaceRaised,
                                    in: .rect(cornerRadius: 11)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label)
                                    .font(.system(.subheadline, weight: .bold))
                                Text(option.hint)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            Spacer(minLength: 0)
                            if kind == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.volt)
                            }
                        }
                        .padding(11)
                        .panelFlat()
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Motivo")
                TextField("Por qué no puedes presentarte", text: $reason, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(.subheadline, weight: .semibold))
                    .padding(12)
                    .panelFlat()
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Comentarios")
                TextField("Información adicional para la estación", text: $comments, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .padding(12)
                    .panelFlat()
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Documento o evidencia")
                Button {
                    hasEvidence.toggle()
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: hasEvidence ? "checkmark.circle.fill" : "paperclip")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(hasEvidence ? CovTone.good : Palette.textMuted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hasEvidence ? "Evidencia adjunta" : "Adjuntar evidencia")
                                .font(.system(.subheadline, weight: .bold))
                            Text(requiresEvidence
                                ? "Un permiso necesita comprobante"
                                : "Opcional para este tipo de ausencia")
                                .font(.caption2)
                                .foregroundStyle(requiresEvidence && !hasEvidence ? CovTone.pending : Palette.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .panelFlat()
                }
                .buttonStyle(.plain)
            }

            BigButton(
                title: isEmergency ? "Reportar emergencia" : "Enviar solicitud",
                symbol: isEmergency ? "exclamationmark.triangle.fill" : "paperplane.fill",
                tone: isEmergency ? .danger : .volt,
                isEnabled: canSend
            ) {
                send()
            }
        }
    }

    private func send() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let request = coverage.requestAbsence(
            driver: profile,
            date: date,
            slot: slot,
            kind: kind,
            reason: reason,
            comments: comments,
            evidence: hasEvidence ? Data("evidencia".utf8) : nil
        )
        withAnimation(.smooth) { sent = request }
    }

    private func confirmation(for request: AbsenceRequest) -> some View {
        let stored = coverage.absence(id: request.id) ?? request
        return VStack(alignment: .leading, spacing: 14) {
            NoticeBanner(
                symbol: "paperplane.fill",
                title: "Solicitud enviada. Tu ausencia aún no ha sido autorizada.",
                message: "El sistema abrió una vacante temporal para tu unidad y empezó a buscar conductores elegibles.",
                tone: .info
            )

            VStack(alignment: .leading, spacing: 12) {
                CapsLabel(text: "Estado de tu solicitud")
                AbsencePipelineRail(status: stored.status)
            }
            .padding(16)
            .panel()

            if let vacancy = coverage.vacancy(id: stored.vacancyId) {
                VStack(alignment: .leading, spacing: 10) {
                    CapsLabel(text: "Vacante temporal generada")
                    // The card reads the clock for a single line — the urgency label of a
                    // critical seat. The scope covers that card and nothing around it.
                    TimeScope(.minute) { now in
                        VacancyCard(vacancy: vacancy, now: now, showsTitular: false)
                    }
                    Text("El sistema detectó la estación, la fecha, el horario, el turno y tu unidad sin que tuvieras que capturarlos.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                .padding(16)
                .panel()
            }

            BigButton(title: "Entendido", symbol: "checkmark", tone: .outline) { dismiss() }
        }
    }
}

// MARK: - Available guards

/// Only seats this person may legally take. Nothing that fails a rule reaches this list.
struct AvailableGuardsView: View {
    let profile: CoverageDriverProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var detail: CoverageVacancy?
    @State private var outcome: String?

    private var offers: [(vacancy: CoverageVacancy, verdict: EligibilityVerdict)] {
        coverage.availableGuards(for: profile)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        if let outcome {
                            NoticeBanner(symbol: "info.circle.fill", title: outcome, tone: .info)
                        }

                        if offers.isEmpty {
                            CoverageEmpty(
                                title: "No hay guardias para ti",
                                message: "Cuando alguien de tu estación falte o se abra cobertura extraordinaria, aparecerá aquí solo si cumples todas las reglas.",
                                symbol: "hand.raised"
                            )
                        } else {
                            ForEach(offers, id: \.vacancy.id) { offer in
                                Button {
                                    detail = offer.vacancy
                                } label: {
                                    guardCard(offer.vacancy)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Guardias disponibles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $detail) { vacancy in
                GuardDetailView(vacancy: vacancy, profile: profile) { message in
                    outcome = message
                }
            }
        }
    }

    private func guardCard(_ vacancy: CoverageVacancy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    CapsLabel(text: vacancy.isCritical ? "Guardia urgente" : "Guardia disponible")
                    Text(Fmt.dateShort(vacancy.date).capitalized)
                        .font(.system(.title3, weight: .black))
                    Text(vacancy.slot.rangeLabel)
                        .font(.system(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 6)
                if vacancy.isCritical {
                    CoveragePill(text: "Urgente", symbol: "exclamationmark.octagon.fill", tone: CovTone.blocking, filled: true)
                }
            }

            HStack(spacing: 8) {
                CoverageFact(label: "Estación", value: vacancy.stationCode)
                CoverageFact(label: "Duración", value: "\(vacancy.durationHours) horas")
                CoverageFact(
                    label: vacancy.bonusMode == .none ? "Bono" : "Bono extraordinario",
                    value: vacancy.bonusLabel,
                    tone: vacancy.bonusMode == .none ? Palette.textMuted : CovTone.good
                )
            }

            HStack(spacing: 10) {
                Text("Ver detalles")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(16)
        .panel()
    }
}

/// Full reading of one seat plus the button that takes it. Eligibility is checked again
/// at this exact moment, because the person's situation may have changed since the offer.
struct GuardDetailView: View {
    let vacancy: CoverageVacancy
    let profile: CoverageDriverProfile
    let onResult: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var blockers: [EligibilityCheck] = []
    @State private var message: String?

    private var verdict: EligibilityVerdict { coverage.evaluate(profile: profile, vacancy: vacancy) }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TimeScope(.minute) { now in
                            VacancyCard(vacancy: vacancy, now: now)
                        }

                        if !blockers.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                NoticeBanner(
                                    symbol: "xmark.octagon.fill",
                                    title: "No puedes tomar esta guardia",
                                    message: "Tu situación cambió desde que se te ofreció. Estas reglas no se cumplen:",
                                    tone: .danger
                                )
                                ForEach(blockers) { check in
                                    HStack(alignment: .top, spacing: 7) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .black))
                                            .foregroundStyle(CovTone.blocking)
                                        Text("\(check.rule.label): \(check.detail)")
                                            .font(.caption2)
                                            .foregroundStyle(CovTone.blocking)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .padding(14)
                            .panel()
                        }

                        if let message {
                            NoticeBanner(symbol: "checkmark.seal.fill", title: message, tone: .volt)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            CapsLabel(text: "Tu elegibilidad para este turno")
                            EligibilityChecklist(verdict: verdict)
                        }
                        .padding(16)
                        .panel()

                        if message == nil {
                            BigButton(title: "Tomar guardia", symbol: "hand.raised.fill") { take() }
                            Text("Al tomarla queda reservada a tu nombre y pasa al supervisor. No es definitiva hasta que la apruebe.")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                        } else {
                            BigButton(title: "Listo", symbol: "checkmark", tone: .outline) { dismiss() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Detalle de la guardia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func take() {
        switch coverage.claimGuard(vacancyId: vacancy.id, by: profile) {
        case .reserved:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            message = "Reservada — pendiente de aprobación del supervisor."
            onResult("Guardia reservada a tu nombre. Falta la aprobación del supervisor.")
        case .waitlisted(let position):
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            message = "Alguien la tomó primero. Quedaste en lista de espera, lugar \(position)."
            onResult("Quedaste en lista de espera en el lugar \(position).")
        case .notEligible(let checks):
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.smooth) { blockers = checks }
        case .unavailable(let reason):
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            onResult(reason)
            dismiss()
        }
    }
}

// MARK: - My requests

/// Absences and swaps of this person, with the state each one is actually in.
struct MyCoverageRequestsView: View {
    let profile: CoverageDriverProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        absencesSection
                        swapsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Mis solicitudes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var absencesSection: some View {
        let requests = coverage.absences(driverId: profile.id)
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Ausencias")
            if requests.isEmpty {
                CoverageEmpty(
                    title: "Sin solicitudes",
                    message: "Cuando pidas una ausencia aparecerá aquí con su estado real, paso por paso.",
                    symbol: "calendar.badge.minus"
                )
            } else {
                ForEach(requests) { request in
                    absenceCard(request)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func absenceCard(_ request: AbsenceRequest) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.dateShort(request.date).capitalized)
                        .font(.system(.subheadline, weight: .black))
                    Text("\(request.slot.label) · \(request.kind.label)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 6)
                CoveragePill(text: request.status.label, symbol: request.status.symbol, tone: request.status.tone)
            }

            AbsencePipelineRail(status: request.status)

            if !request.reason.isEmpty {
                Text("Motivo: \(request.reason)")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            if let vacancy = coverage.vacancy(id: request.vacancyId), let substitute = vacancy.substituteName {
                CoverageLine(label: "Cobertura", value: substitute, symbol: "person.fill.checkmark", tone: CovTone.good)
            }

            if let note = request.decisionNote, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(request.status.tone)
            }

            if request.status.isOpen {
                Button {
                    coverage.cancelAbsence(id: request.id, by: "\(profile.name) · \(profile.employeeNumber)")
                } label: {
                    Text("Cancelar solicitud")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(CovTone.blocking)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(CovTone.blocking.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .panelFlat()
    }

    @ViewBuilder
    private var swapsSection: some View {
        let requests = coverage.swaps(driverId: profile.id)
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CapsLabel(text: "Intercambios")
                ForEach(requests) { swap in
                    swapCard(swap)
                }
            }
            .padding(16)
            .panel()
        }
    }

    private func swapCard(_ swap: ShiftSwapRequest) -> some View {
        let isPartner = swap.toDriverId == profile.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPartner ? swap.fromDriverName : swap.toDriverName)
                        .font(.system(.subheadline, weight: .bold))
                    Text(swap.summary)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 6)
                CoveragePill(text: swap.status.label, symbol: swap.status.symbol, tone: swap.status.tone)
            }

            if !swap.note.isEmpty {
                Text(swap.note)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            if !swap.blockers.isEmpty {
                Text("Observaciones: \(swap.blockers.joined(separator: " · "))")
                    .font(.caption2)
                    .foregroundStyle(CovTone.pending)
            }

            if isPartner && swap.status == .proposed {
                HStack(spacing: 8) {
                    Button {
                        coverage.respondToSwap(id: swap.id, accepted: true, by: profile)
                    } label: {
                        Text("Aceptar")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Palette.canvas)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(CovTone.good, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        coverage.respondToSwap(id: swap.id, accepted: false, by: profile)
                    } label: {
                        Text("Rechazar")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(CovTone.blocking)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(CovTone.blocking.opacity(0.12), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(13)
        .panelFlat()
    }
}

// MARK: - My replacements

/// Turns this person is covering for somebody else, and what happened with the ones
/// already closed.
struct MyReplacementsView: View {
    let profile: CoverageDriverProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var cancelling: CoverageVacancy?

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        activeSection
                        historySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Mis reemplazos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $cancelling) { vacancy in
                GuardCancellationView(vacancy: vacancy, profile: profile)
                    .presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        let active = coverage.activeGuards(driverId: profile.id)
            .sorted { $0.scheduledStartAt < $1.scheduledStartAt }
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Guardias en curso")
            if active.isEmpty {
                CoverageEmpty(
                    title: "No estás cubriendo ningún turno",
                    message: "Cuando tomes una guardia y quede aprobada, la verás aquí con su horario y su bono.",
                    symbol: "person.2.badge.gearshape"
                )
            } else {
                ForEach(active) { vacancy in
                    VStack(alignment: .leading, spacing: 10) {
                        // One scope per row, wrapping that row's card only. The section
                        // heading, the empty state and the cancel button stay outside.
                        TimeScope(.minute) { now in
                            VacancyCard(vacancy: vacancy, now: now)
                        }
                        Button {
                            cancelling = vacancy
                        } label: {
                            Text("Solicitar cancelar esta guardia")
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(CovTone.blocking)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(CovTone.blocking.opacity(0.1), in: .rect(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .panel()
    }

    @ViewBuilder
    private var historySection: some View {
        let history = coverage.guards(driverId: profile.id).filter { !$0.status.isOpen }
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CapsLabel(text: "Historial de guardias")
                ForEach(history) { vacancy in
                    HStack(spacing: 11) {
                        Image(systemName: vacancy.status.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(vacancy.status.tone)
                            .frame(width: 30, height: 30)
                            .background(vacancy.status.tone.opacity(0.12), in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.dateShort(vacancy.date).capitalized)
                                .font(.system(.subheadline, weight: .bold))
                            Text("\(vacancy.slot.label) · \(vacancy.status.label)")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 0)
                        if vacancy.payableBonusMxn > 0 {
                            Text("+\(Fmt.mxn(vacancy.payableBonusMxn))")
                                .font(.system(size: 11, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(CovTone.good)
                        }
                    }
                    .padding(11)
                    .panelFlat()
                }

                let reliability = coverage.reliability(driverId: profile.id)
                if let reliability {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            CapsLabel(text: "Confiabilidad de cobertura")
                            Spacer(minLength: 0)
                            Text("\(reliability.score) · \(reliability.label)")
                                .font(.system(.caption, weight: .black))
                                .foregroundStyle(reliability.score >= 65 ? CovTone.good : CovTone.pending)
                        }
                        Text("Aceptadas \(reliability.accepted) · completadas \(reliability.completed) · canceladas \(reliability.cancelled) · sin presentarse \(reliability.noShows).")
                            .font(.caption2)
                            .foregroundStyle(Palette.textMuted)
                        Text("Es una lectura operativa de la estación, no una sanción laboral.")
                            .font(.caption2)
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(12)
                    .panelFlat()
                }
            }
            .padding(16)
            .panel()
        }
    }
}

/// Giving back a guard. The anticipation is recorded because it is the difference between
/// an inconvenience and a station without a driver.
struct GuardCancellationView: View {
    let vacancy: CoverageVacancy
    let profile: CoverageDriverProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var reason: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        NoticeBanner(
                            symbol: "exclamationmark.triangle.fill",
                            title: "La vacante se reabre de inmediato",
                            message: "Si hay alguien en lista de espera, el turno pasa a esa persona. Si no, el sistema vuelve a buscar y el supervisor recibe aviso.",
                            tone: .amber
                        )

                        VStack(spacing: 0) {
                            DetailRow(label: "Turno", value: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot))
                            Divider().overlay(Palette.hairline)
                            // Text and colour of one row. The rows above and below it, the
                            // reason field and the confirm button are outside the scope.
                            TimeScope(.minute) { now in
                                let hours = vacancy.hoursUntilStart(now: now)
                                DetailRow(
                                    label: "Anticipación",
                                    value: CoverageRules.urgencyLabel(hoursUntilStart: hours),
                                    tone: hours < 12 ? CovTone.blocking : CovTone.pending
                                )
                            }
                            Divider().overlay(Palette.hairline)
                            DetailRow(label: "Bono que pierdes", value: vacancy.bonusLabel)
                        }
                        .padding(.vertical, 4)
                        .panel()

                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: "Motivo de la cancelación")
                            TextField("Explica por qué no podrás cubrirla", text: $reason, axis: .vertical)
                                .lineLimit(2...4)
                                .font(.subheadline)
                                .padding(12)
                                .panelFlat()
                        }

                        BigButton(
                            title: "Cancelar mi guardia",
                            symbol: "xmark.circle.fill",
                            tone: .danger,
                            isEnabled: !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            coverage.cancelClaim(vacancyId: vacancy.id, driverId: profile.id, reason: reason)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Cancelar guardia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Volver") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Swap proposal

/// Proposing a trade. The app never performs the change here: it opens a proposal that
/// the partner answers and the supervisor signs.
struct SwapProposalView: View {
    let profile: CoverageDriverProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var myDate: Date = Date()
    @State private var theirDate: Date = Date()
    @State private var theirSlot: ShiftSlot = .evening
    @State private var partnerId: String?
    @State private var note: String = ""
    @State private var sent: Bool = false

    private var partners: [CoverageDriverProfile] {
        coverage.roster(stationId: profile.stationId).filter { $0.id != profile.id }
    }

    private var partner: CoverageDriverProfile? {
        partners.first { $0.id == partnerId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        NoticeBanner(
                            symbol: "arrow.left.arrow.right",
                            title: "El cambio no se hace solo porque se acuerde",
                            message: "Tu compañero acepta, el sistema revisa la elegibilidad de los dos y el supervisor aprueba. Hasta entonces los calendarios no se mueven.",
                            tone: .info
                        )

                        if sent {
                            NoticeBanner(
                                symbol: "checkmark.seal.fill",
                                title: "Propuesta enviada",
                                message: "Tu compañero recibió la solicitud. La verás en Mis solicitudes.",
                                tone: .volt
                            )
                            BigButton(title: "Cerrar", symbol: "checkmark", tone: .outline) { dismiss() }
                        } else if partners.isEmpty {
                            CoverageEmpty(
                                title: "Sin compañeros registrados",
                                message: "Todavía no hay otros conductores en tu estación con los que puedas intercambiar.",
                                symbol: "person.2.slash"
                            )
                        } else {
                            form
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Solicitar intercambio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Mi turno")
                DatePicker("", selection: $myDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Palette.volt)
                Text("\(profile.slot.label) · \(profile.slot.rangeLabel)")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Compañero")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(partners) { candidate in
                            Button {
                                partnerId = candidate.id
                                theirSlot = candidate.slot
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.shortName)
                                        .font(.system(.caption, weight: .bold))
                                        .lineLimit(1)
                                    Text("\(candidate.slot.label) · \(candidate.employeeNumber)")
                                        .font(.system(size: 9))
                                        .opacity(0.75)
                                }
                                .foregroundStyle(partnerId == candidate.id ? Palette.canvas : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    partnerId == candidate.id ? Palette.volt : Palette.surfaceRaised,
                                    in: .rect(cornerRadius: 13)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Turno que tomarías a cambio")
                DatePicker("", selection: $theirDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Palette.volt)
                Picker("", selection: $theirSlot) {
                    ForEach(ShiftSlot.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Nota para tu compañero")
                TextField("Por qué necesitas el cambio", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.subheadline)
                    .padding(12)
                    .panelFlat()
            }

            BigButton(
                title: "Enviar propuesta",
                symbol: "paperplane.fill",
                isEnabled: partner != nil
            ) {
                guard let partner else { return }
                coverage.proposeSwap(
                    from: profile,
                    fromDate: myDate,
                    fromSlot: profile.slot,
                    to: partner,
                    toDate: theirDate,
                    toSlot: theirSlot,
                    note: note
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.smooth) { sent = true }
            }
        }
    }
}
