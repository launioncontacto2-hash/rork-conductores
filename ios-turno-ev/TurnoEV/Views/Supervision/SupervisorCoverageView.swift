import SwiftUI
import UIKit

/// Supervisor → Cobertura. The station's answer to who is driving every unit today and
/// on the days ahead: absences, seats nobody is covering, proposed substitutes, guards,
/// swaps and the trace of everything already decided.
struct SupervisorCoverageView: View {
    let supervision: SupervisionStore
    let account: StaffAccount
    let header: SupervisorHeader

    @Environment(CoverageStore.self) private var coverage

    @State private var section: CoverageSection = .summary
    @State private var route: CoverageRoute?

    enum CoverageSection: String, CaseIterable, Identifiable, Hashable {
        case summary
        case absences
        case uncovered
        case replacements
        case guards
        case swaps
        case history

        var id: String { rawValue }

        var label: String {
            switch self {
            case .summary: "Resumen"
            case .absences: "Ausencias"
            case .uncovered: "Sin cubrir"
            case .replacements: "Reemplazos"
            case .guards: "Guardias"
            case .swaps: "Intercambios"
            case .history: "Historial"
            }
        }

        var symbol: String {
            switch self {
            case .summary: "square.grid.2x2.fill"
            case .absences: "calendar.badge.minus"
            case .uncovered: "exclamationmark.triangle.fill"
            case .replacements: "person.fill.checkmark"
            case .guards: "hand.raised.fill"
            case .swaps: "arrow.left.arrow.right"
            case .history: "clock.arrow.circlepath"
            }
        }
    }

    private enum CoverageRoute: Identifiable, Hashable {
        case vacancy(String)
        case newGuard
        case forecast

        var id: String {
            switch self {
            case .vacancy(let id): "vac-\(id)"
            case .newGuard: "new-guard"
            case .forecast: "forecast"
            }
        }
    }

    private var station: Station { supervision.station }

    private var counts: [CoverageSection: Int] {
        [
            .summary: 0,
            .absences: coverage.absences(stationId: station.id).filter { $0.status.isOpen }.count,
            .uncovered: coverage.openVacancies(stationId: station.id).count,
            .replacements: coverage.vacanciesAwaitingApproval(stationId: station.id).count,
            .guards: coverage.confirmedVacancies(stationId: station.id).count,
            .swaps: coverage.swaps(stationId: station.id).filter { $0.status == .awaitingSupervisor }.count,
            .history: 0,
        ]
    }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    sectionPicker

                    switch section {
                    case .summary: summarySection
                    case .absences: absencesSection
                    case .uncovered: uncoveredSection
                    case .replacements: replacementsSection
                    case .guards: guardsSection
                    case .swaps: swapsSection
                    case .history: historySection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $route) { destination in
            switch destination {
            case .vacancy(let id):
                if let vacancy = coverage.vacancy(id: id) {
                    SupervisorVacancyDetailView(vacancy: vacancy, account: account)
                }
            case .newGuard:
                SupervisorNewGuardView(station: station, account: account)
            case .forecast:
                SupervisorCoverageForecastView(station: station) { vacancyId in
                    route = .vacancy(vacancyId)
                }
            }
        }
    }

    // MARK: - Section picker

    private var sectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(CoverageSection.allCases) { item in
                    let badge = counts[item] ?? 0
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { section = item }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 10, weight: .bold))
                            Text(item.label)
                                .font(.system(.caption, weight: .bold))
                            if badge > 0 {
                                Text("\(badge)")
                                    .font(.system(size: 9, weight: .black))
                                    .monospacedDigit()
                                    .foregroundStyle(section == item ? SupTone.accent : Palette.canvas)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(section == item ? Palette.canvas : SupTone.accent, in: .capsule)
                            }
                        }
                        .foregroundStyle(section == item ? Palette.canvas : Palette.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(section == item ? SupTone.accent : Palette.surfaceRaised.opacity(0.7), in: .capsule)
                        .overlay {
                            Capsule().stroke(section == item ? .clear : Palette.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: - Summary

    private var summarySection: some View {
        let critical = coverage.criticalVacancies(stationId: station.id)

        return VStack(spacing: 14) {
            if !critical.isEmpty {
                Button {
                    route = .vacancy(critical[0].id)
                } label: {
                    NoticeBanner(
                        symbol: "exclamationmark.octagon.fill",
                        title: "\(critical.count) alerta\(critical.count == 1 ? "" : "s") crítica\(critical.count == 1 ? "" : "s") de cobertura",
                        message: "Un turno está por empezar sin conductor. El sistema ya está buscando sustituto elegible.",
                        tone: .danger
                    )
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CapsLabel(text: "Cobertura de hoy")
                    Spacer(minLength: 0)
                    // The date of the board, alone. The heading beside it never moves.
                    TimeScope(.day) { now in
                        Text(Fmt.dateShort(now).capitalized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                StationSlotMeters(station: station)
                Text("Los requeridos salen de las \(station.vehicleCapacity) unidades autorizadas de \(station.code). Un asiento vacío no baja la meta: la reparte entre quienes sí llegaron.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(16)
            .panel()

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                UpcomingAbsencesTile(station: station)
                StatTile(
                    label: "Vacantes abiertas",
                    value: "\(coverage.openVacancies(stationId: station.id).count)",
                    hint: "Buscando reemplazo",
                    tone: coverage.openVacancies(stationId: station.id).isEmpty ? .neutral : .amber,
                    symbol: "magnifyingglass"
                )
                StatTile(
                    label: "Por aprobar",
                    value: "\(coverage.vacanciesAwaitingApproval(stationId: station.id).count)",
                    hint: "Reemplazos propuestos",
                    tone: coverage.vacanciesAwaitingApproval(stationId: station.id).isEmpty ? .neutral : .info,
                    symbol: "signature"
                )
                StatTile(
                    label: "Confirmados",
                    value: "\(coverage.confirmedVacancies(stationId: station.id).count)",
                    hint: "Cobertura asegurada",
                    tone: .volt,
                    symbol: "checkmark.seal.fill"
                )
            }

            HStack(spacing: 10) {
                Button {
                    route = .newGuard
                } label: {
                    actionTile(title: "Crear guardia", symbol: "plus.circle.fill", tint: SupTone.accent)
                }
                .buttonStyle(.plain)

                Button {
                    route = .forecast
                } label: {
                    actionTile(title: "Calendario de cobertura", symbol: "calendar.badge.exclamationmark", tint: CovTone.pending)
                }
                .buttonStyle(.plain)
            }

            automationCard
        }
    }

    private func actionTile(title: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(.caption, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 86)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.3), lineWidth: 1) }
    }

    private var automationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CapsLabel(text: "Modo de asignación")
                Spacer(minLength: 0)
                CoveragePill(
                    text: coverage.policy.automation.label,
                    symbol: coverage.policy.automation.symbol,
                    tone: SupTone.accent
                )
            }
            Text(coverage.policy.automation.detail)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
            Text("Descanso mínimo \(coverage.policy.minimumRestHours) h · máximo \(coverage.policy.maxShiftsPerWeek) jornadas y \(coverage.policy.maxGuardsPerWeek) guardias por semana. Recursos Humanos ajusta estos límites; el motor solo los aplica.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    // MARK: - Absences

    private var absencesSection: some View {
        let requests = coverage.absences(stationId: station.id)
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Ausencias",
                subtitle: "Cubrir el turno y autorizar la falta son dos decisiones distintas"
            )

            if requests.isEmpty {
                CoverageEmpty(
                    title: "Sin ausencias registradas",
                    message: "Cuando un conductor de \(station.code) solicite una ausencia, aparecerá aquí con su vacante.",
                    symbol: "calendar.badge.minus"
                )
            } else {
                ForEach(requests) { request in
                    absenceCard(request)
                }
            }
        }
    }

    private func absenceCard(_ request: AbsenceRequest) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.driverName)
                        .font(.system(.subheadline, weight: .black))
                    Text("\(request.employeeNumber) · \(CoverageRules.shiftLabel(date: request.date, slot: request.slot))")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 6)
                CoveragePill(text: request.status.label, symbol: request.status.symbol, tone: request.status.tone)
            }

            HStack(spacing: 8) {
                CoverageFact(label: "Tipo", value: request.kind.shortLabel)
                // One fact of one card: how long ago the driver gave notice.
                TimeScope(.minute) { now in
                    CoverageFact(label: "Aviso", value: Fmt.relative(request.createdAt, from: now))
                }
                CoverageFact(
                    label: "Evidencia",
                    value: request.hasEvidence ? "Adjunta" : "Sin adjuntar",
                    tone: request.hasEvidence ? CovTone.good : Palette.textMuted
                )
            }

            if !request.reason.isEmpty {
                Text("Motivo: \(request.reason)")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            if !request.comments.isEmpty {
                Text(request.comments)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            if let vacancy = coverage.vacancy(id: request.vacancyId) {
                Button {
                    route = .vacancy(vacancy.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: vacancy.status.symbol)
                            .font(.system(size: 10, weight: .bold))
                        Text("Vacante: \(vacancy.status.label)")
                            .font(.system(size: 11, weight: .bold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(vacancy.status.tone)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(vacancy.status.tone.opacity(0.1), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            // The second decision, always separate from coverage.
            if request.status == .awaitingAuthorization || request.status == .covered {
                HStack(spacing: 8) {
                    Button {
                        coverage.decideAbsence(id: request.id, approved: true, note: "Autorizada por supervisión de turno.", by: account)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        decisionButton(title: "Autorizar ausencia", tint: CovTone.good, filled: true)
                    }
                    .buttonStyle(.plain)

                    Button {
                        coverage.decideAbsence(id: request.id, approved: false, note: "No autorizada: debe presentarse.", by: account)
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    } label: {
                        decisionButton(title: "No autorizar", tint: CovTone.blocking, filled: false)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let note = request.decisionNote, !note.isEmpty {
                Text("\(request.decidedBy ?? "—"): \(note)")
                    .font(.caption2)
                    .foregroundStyle(request.status.tone)
            }
        }
        .padding(14)
        .panel()
    }

    private func decisionButton(title: String, tint: Color, filled: Bool) -> some View {
        Text(title)
            .font(.system(.caption, weight: .bold))
            .foregroundStyle(filled ? Palette.canvas : tint)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(filled ? tint : tint.opacity(0.12), in: .rect(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13).stroke(filled ? .clear : tint.opacity(0.4), lineWidth: 1)
            }
    }

    // MARK: - Uncovered

    private var uncoveredSection: some View {
        let open = coverage.vacancies(stationId: station.id).filter { $0.status == .searching || $0.status == .uncovered }
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Turnos sin cubrir",
                subtitle: "Asientos con unidad autorizada y nadie al volante"
            )

            if open.isEmpty {
                CoverageEmpty(
                    title: "Ningún turno descubierto",
                    message: "Todas las unidades de \(station.code) tienen conductor asignado o guardia confirmada.",
                    symbol: "checkmark.shield",
                    tone: CovTone.good
                )
            } else {
                ForEach(open) { vacancy in
                    Button {
                        route = .vacancy(vacancy.id)
                    } label: {
                        VacancyCard(vacancy: vacancy)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    // MARK: - Replacements

    private var replacementsSection: some View {
        let proposed = coverage.vacanciesAwaitingApproval(stationId: station.id)
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Reemplazos propuestos",
                subtitle: "Elegibilidad ya revalidada; falta tu firma"
            )

            if proposed.isEmpty {
                CoverageEmpty(
                    title: "Nada por aprobar",
                    message: "Cuando alguien tome una guardia, su propuesta llegará aquí con la revisión de reglas completa.",
                    symbol: "signature"
                )
            } else {
                ForEach(proposed) { vacancy in
                    Button {
                        route = .vacancy(vacancy.id)
                    } label: {
                        proposalCard(vacancy)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    private func proposalCard(_ vacancy: CoverageVacancy) -> some View {
        let substituteProfile = coverage.profile(id: vacancy.substituteId)
        let verdict = substituteProfile.map { coverage.evaluate(profile: $0, vacancy: vacancy) }

        return VStack(alignment: .leading, spacing: 11) {
            CapsLabel(text: "Reemplazo propuesto")

            VStack(spacing: 0) {
                DetailRow(label: "Turno", value: "\(Fmt.dateShort(vacancy.date).capitalized) \(vacancy.slot.rangeLabel)")
                Divider().overlay(Palette.hairline)
                DetailRow(label: "Titular", value: vacancy.titularName ?? "Cobertura extraordinaria")
                Divider().overlay(Palette.hairline)
                DetailRow(label: "Sustituto", value: vacancy.substituteName ?? "—", tone: CovTone.good)
                Divider().overlay(Palette.hairline)
                DetailRow(label: "Bono", value: vacancy.bonusLabel)
            }
            .padding(.vertical, 2)

            if let verdict {
                VStack(alignment: .leading, spacing: 6) {
                    CapsLabel(text: "Elegibilidad")
                    EligibilityChecklist(verdict: verdict, isCompact: true)
                }
            }

            HStack(spacing: 7) {
                Text("Abrir para aprobar o rechazar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SupTone.accent)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SupTone.accent)
            }
        }
        .padding(14)
        .panel()
    }

    // MARK: - Guards

    private var guardsSection: some View {
        let confirmed = coverage.confirmedVacancies(stationId: station.id)
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Guardias",
                subtitle: "Cobertura ya confirmada y guardias que puedes abrir",
                actionTitle: "Crear",
                action: { route = .newGuard }
            )

            if confirmed.isEmpty {
                CoverageEmpty(
                    title: "Sin guardias confirmadas",
                    message: "Puedes abrir cobertura extraordinaria aunque no exista ninguna ausencia: demanda alta, evento, unidad adicional o cobertura preventiva.",
                    symbol: "hand.raised"
                )
            } else {
                ForEach(confirmed) { vacancy in
                    Button {
                        route = .vacancy(vacancy.id)
                    } label: {
                        VacancyCard(vacancy: vacancy)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }

            reliabilityCard
        }
    }

    @ViewBuilder
    private var reliabilityCard: some View {
        let board = coverage.reliabilityBoard(stationId: station.id)
        if !board.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: "Confiabilidad de cobertura")
                ForEach(board) { entry in
                    HStack(spacing: 10) {
                        Text("\(entry.score)")
                            .font(.system(.subheadline, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(entry.score >= 65 ? CovTone.good : CovTone.pending)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.driverName)
                                .font(.system(.caption, weight: .bold))
                            Text("\(entry.completed)/\(entry.accepted) completadas · \(entry.cancelled) canceladas · \(entry.noShows) sin presentarse")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 0)
                        CoveragePill(text: entry.label, tone: entry.score >= 65 ? CovTone.good : CovTone.pending)
                    }
                    .padding(11)
                    .panelFlat()
                }
                Text("Información operativa para decidir a quién ofrecer una guardia. No es una sanción laboral ni se convierte en una por sí sola.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(16)
            .panel()
        }
    }

    // MARK: - Swaps

    private var swapsSection: some View {
        let requests = coverage.swaps(stationId: station.id)
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Intercambios",
                subtitle: "Los conductores proponen; el cambio solo ocurre con tu firma"
            )

            if requests.isEmpty {
                CoverageEmpty(
                    title: "Sin intercambios",
                    message: "Cuando dos conductores acuerden cambiar turno, la solicitud llegará aquí con la revisión de ambos.",
                    symbol: "arrow.left.arrow.right"
                )
            } else {
                ForEach(requests) { swap in
                    swapCard(swap)
                }
            }
        }
    }

    private func swapCard(_ swap: ShiftSwapRequest) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(swap.fromDriverName) ⇄ \(swap.toDriverName)")
                        .font(.system(.subheadline, weight: .bold))
                        .lineLimit(1)
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

            if swap.blockers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Ambos conductores cumplen las reglas configuradas")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(CovTone.good)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(swap.blockers, id: \.self) { blocker in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(blocker)
                                .font(.system(size: 11))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(CovTone.pending)
                    }
                }
            }

            if swap.status == .awaitingSupervisor {
                HStack(spacing: 8) {
                    Button {
                        coverage.decideSwap(id: swap.id, approved: true, by: account, note: "Intercambio autorizado por supervisión.")
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        decisionButton(title: "Aprobar", tint: CovTone.good, filled: true)
                    }
                    .buttonStyle(.plain)

                    Button {
                        coverage.decideSwap(id: swap.id, approved: false, by: account, note: "No procede el intercambio.")
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    } label: {
                        decisionButton(title: "Rechazar", tint: CovTone.blocking, filled: false)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let note = swap.decisionNote, !note.isEmpty, !swap.status.isOpen {
                Text("\(swap.resolvedBy ?? "—"): \(note)")
                    .font(.caption2)
                    .foregroundStyle(swap.status.tone)
            }
        }
        .padding(14)
        .panel()
    }

    // MARK: - History

    private var historySection: some View {
        let entries = coverage.auditTrail(stationCode: station.code)
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Historial",
                subtitle: "Registro permanente. Nada de lo que está aquí se puede editar"
            )

            if entries.isEmpty {
                CoverageEmpty(
                    title: "Sin movimientos",
                    message: "Cada solicitud, oferta, aceptación, rechazo, aprobación y cancelación queda escrita aquí de forma permanente.",
                    symbol: "clock.arrow.circlepath"
                )
            } else {
                ForEach(entries.prefix(60)) { entry in
                    auditRow(entry)
                }
            }
        }
    }

    private func auditRow(_ entry: CoverageAuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(entry.action)
                    .font(.system(.caption, weight: .black))
                Spacer(minLength: 6)
                RelativeTime(date: entry.createdAt)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
            Text(entry.shiftLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
            HStack(spacing: 5) {
                Text(entry.previousState)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Palette.textMuted)
                Text(entry.newState)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SupTone.accent)
            }
            Text(entry.detail)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(entry.actor) · \(Fmt.clock(entry.createdAt)) · \(entry.stationCode)")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textMuted.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat()
    }
}

// MARK: - Day-scoped leaves of the summary

/// The three shift meters of today, and only them.
///
/// The board of a station is derived from a day, so this reading has to stay alive across
/// midnight — and only across midnight, which is exactly what `.day` says. Extracting it
/// into its own view is what keeps the scope honest: the meters are the entire content, so
/// nothing above them — the panel, its heading, the caption, the `LazyVGrid` of tiles
/// underneath, the `ScrollView` of the whole module — is inside.
private struct StationSlotMeters: View {
    let station: Station

    @Environment(CoverageStore.self) private var coverage

    var body: some View {
        TimeScope(.day) { now in
            ForEach(coverage.slotBoards(station: station, on: now)) { board in
                CoverageMeter(board: board)
            }
        }
    }
}

/// Count of absences from today onwards. One tile, one number, and a filter anchored on
/// `startOfDay` — so the day is both the cadence and the meaning.
private struct UpcomingAbsencesTile: View {
    let station: Station

    @Environment(CoverageStore.self) private var coverage

    var body: some View {
        TimeScope(.day) { now in
            let upcoming = coverage.absences(stationId: station.id)
                .filter { $0.date >= ShiftRules.calendar.startOfDay(for: now) && $0.status.isOpen }
            StatTile(
                label: "Ausencias próximas",
                value: "\(upcoming.count)",
                hint: "En proceso",
                tone: upcoming.isEmpty ? .neutral : .amber,
                symbol: "calendar.badge.minus"
            )
        }
    }
}

// MARK: - Vacancy detail

/// The approval card: the turn, the titular, the substitute, the thirteen checks and the
/// bonus, with the two buttons that decide it.
struct SupervisorVacancyDetailView: View {
    let vacancy: CoverageVacancy
    let account: StaffAccount

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var rejectionNote: String = ""
    @State private var isRejecting: Bool = false

    private var live: CoverageVacancy { coverage.vacancy(id: vacancy.id) ?? vacancy }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VacancyCard(vacancy: live)

                        if let substituteId = live.substituteId,
                           let profile = coverage.profile(id: substituteId) {
                            let verdict = coverage.evaluate(profile: profile, vacancy: live)
                            VStack(alignment: .leading, spacing: 10) {
                                CapsLabel(text: "Elegibilidad del sustituto")
                                EligibilityChecklist(verdict: verdict)
                                Text("Prioridad: \(verdict.priorityReason).")
                                    .font(.caption2)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            .padding(16)
                            .panel()
                        }

                        if live.status == .searching {
                            candidatesCard
                        }

                        if !live.waitlist.isEmpty {
                            waitlistCard
                        }

                        actions
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Cobertura del turno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private var candidatesCard: some View {
        let candidates = coverage.candidates(for: live)
        let eligible = candidates.filter(\.isEligible)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CapsLabel(text: "Candidatos del motor")
                Spacer(minLength: 0)
                Text("\(eligible.count) elegibles de \(candidates.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(eligible.isEmpty ? CovTone.blocking : Palette.textMuted)
            }

            if candidates.isEmpty {
                Text("No hay conductores registrados en esta estación todavía.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(candidates.prefix(8)) { candidate in
                    HStack(spacing: 10) {
                        Image(systemName: candidate.isEligible ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(candidate.isEligible ? CovTone.good : CovTone.blocking)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.driverName)
                                .font(.system(.caption, weight: .bold))
                            Text(candidate.isEligible ? candidate.priorityReason : candidate.blockerSummary)
                                .font(.system(size: 10))
                                .foregroundStyle(candidate.isEligible ? Palette.textMuted : CovTone.blocking)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if candidate.isEligible {
                            Text("\(Int(candidate.score))")
                                .font(.system(size: 11, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                    .padding(11)
                    .panelFlat()
                }
            }

            Text("El orden lo fija el grupo complementario, la disponibilidad declarada, las guardias acumuladas y el historial de cumplimiento. Nunca la preferencia del titular.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    private var waitlistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Lista de espera")
            ForEach(Array(live.waitlist.enumerated()), id: \.element.id) { index, claim in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(.caption, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textMuted)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(claim.driverName)
                            .font(.system(.caption, weight: .bold))
                        TimeScope(.minute) { now in
                            Text("Se anotó \(Fmt.relative(claim.claimedAt, from: now))")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .panelFlat()
            }
            Text("Si quien tiene la guardia cancela, el turno pasa automáticamente al siguiente de la lista.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    @ViewBuilder
    private var actions: some View {
        switch live.status {
        case .reserved:
            VStack(spacing: 10) {
                BigButton(title: "Aprobar reemplazo", symbol: "checkmark.seal.fill") {
                    coverage.approveVacancy(id: live.id, by: account)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }

                if isRejecting {
                    VStack(alignment: .leading, spacing: 8) {
                        CapsLabel(text: "Motivo del rechazo")
                        TextField("Por qué no procede este sustituto", text: $rejectionNote, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.subheadline)
                            .padding(12)
                            .panelFlat()
                        BigButton(
                            title: "Confirmar rechazo",
                            symbol: "xmark.seal.fill",
                            tone: .danger,
                            isEnabled: !rejectionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            coverage.rejectSubstitute(vacancyId: live.id, by: account, reason: rejectionNote)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            dismiss()
                        }
                    }
                } else {
                    BigButton(title: "Rechazar sustituto", symbol: "xmark", tone: .outline) {
                        withAnimation(.smooth) { isRejecting = true }
                    }
                }
            }
        case .confirmed:
            VStack(spacing: 10) {
                Text("El turno está cubierto. Al cierre, marca lo que realmente ocurrió: solo un turno completado genera el bono.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                BigButton(title: "Marcar como completada", symbol: "flag.checkered") {
                    coverage.markCompleted(vacancyId: live.id, by: account)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
                BigButton(title: "No se presentó", symbol: "person.fill.questionmark", tone: .danger) {
                    coverage.markNoShow(vacancyId: live.id, by: account, note: "Registrado al cierre del turno.")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    dismiss()
                }
            }
        case .searching:
            VStack(spacing: 10) {
                Text("El sistema sigue ofreciendo este turno a los conductores elegibles. Si nadie puede tomarlo, ciérralo como descubierto para que quede constancia.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                BigButton(title: "Cerrar sin cobertura", symbol: "exclamationmark.triangle.fill", tone: .outline) {
                    coverage.markUncovered(vacancyId: live.id, reason: "Cerrado por supervisión: sin candidatos disponibles.")
                    dismiss()
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Este registro ya está cerrado y no puede modificarse.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                if let approvedBy = live.approvedBy {
                    Text("Aprobó: \(approvedBy)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .panelFlat()
        }
    }
}

// MARK: - New guard

/// Opening cover with no absence behind it: extra demand, an event, an additional unit or
/// simply staffing ahead of a day the station knows will be hard.
struct SupervisorNewGuardView: View {
    let station: Station
    let account: StaffAccount

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var date: Date = Date()
    @State private var slot: ShiftSlot = .morning
    @State private var seats: Int = 1
    @State private var bonusMode: GuardBonusMode = .fixed
    @State private var bonusMxn: Int = 450
    @State private var reason: String = ""
    @State private var created: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if created > 0 {
                            NoticeBanner(
                                symbol: "checkmark.seal.fill",
                                title: "\(created) guardia\(created == 1 ? "" : "s") abierta\(created == 1 ? "" : "s")",
                                message: "El sistema ya está buscando candidatos elegibles y les envió la oferta.",
                                tone: .volt
                            )
                            BigButton(title: "Listo", symbol: "checkmark", tone: .outline) { dismiss() }
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
            .navigationTitle("Crear guardia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { bonusMxn = coverage.policy.defaultBonusMxn }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Abre cobertura aunque nadie haya faltado: demanda extraordinaria, evento especial, vehículo adicional, cobertura preventiva o necesidad operativa.")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Fecha")
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(SupTone.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Horario")
                Picker("", selection: $slot) {
                    ForEach(ShiftSlot.allCases, id: \.self) { option in
                        Text("\(option.label) \(option.rangeLabel)").tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Cantidad de conductores")
                Stepper("\(seats) conductor\(seats == 1 ? "" : "es")", value: $seats, in: 1...20)
                    .font(.system(.subheadline, weight: .bold))
                    .tint(SupTone.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Bono")
                Picker("", selection: $bonusMode) {
                    ForEach(GuardBonusMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(bonusMode.hint)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)

                if bonusMode != .none {
                    Stepper("\(Fmt.mxn(bonusMxn))", value: $bonusMxn, in: 0...5000, step: 50)
                        .font(.system(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .tint(SupTone.accent)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Motivo")
                TextField("Por qué abres esta cobertura", text: $reason, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.subheadline)
                    .padding(12)
                    .panelFlat()
            }

            BigButton(
                title: "Abrir y buscar candidatos",
                symbol: "magnifyingglass",
                isEnabled: !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                let result = coverage.createExtraordinaryVacancy(
                    station: station,
                    date: date,
                    slot: slot,
                    seats: seats,
                    bonusMode: bonusMode,
                    bonusMxn: bonusMxn,
                    reason: reason,
                    by: account
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.smooth) { created = result.count }
            }
        }
    }
}

// MARK: - Forecast

/// Seven, fourteen or thirty days ahead. The point is to see the hole before the day
/// arrives, when there is still time to fill it.
struct SupervisorCoverageForecastView: View {
    let station: Station
    let onOpenVacancy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(CoverageStore.self) private var coverage

    @State private var horizon: Int = 7

    /// The day the projection is measured from, captured when the sheet opens.
    ///
    /// `forecast(station:days:from:)` feeds a `ForEach` of up to thirty rows inside a
    /// `ScrollView`; none of that may sit in a `TimeScope`. It does not need to: a
    /// projection is read in one sitting and re-anchored the next time it is opened.
    @State private var origin: Date = AppClock.now()

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        picker
                        list
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Calendario de cobertura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private var picker: some View {
        Picker("", selection: $horizon) {
            Text("7 días").tag(7)
            Text("14 días").tag(14)
            Text("30 días").tag(30)
        }
        .pickerStyle(.segmented)
    }

    private var list: some View {
        let days = coverage.forecast(station: station, days: horizon, from: origin)
        let deficits = days.filter(\.hasDeficit)

        return VStack(alignment: .leading, spacing: 12) {
            if deficits.isEmpty {
                CoverageEmpty(
                    title: "Sin déficit proyectado",
                    message: "Con la plantilla actual, \(station.code) cubre sus \(station.vehicleCapacity) unidades en los próximos \(horizon) días.",
                    symbol: "checkmark.shield",
                    tone: CovTone.good
                )
            } else {
                NoticeBanner(
                    symbol: "calendar.badge.exclamationmark",
                    title: "\(deficits.count) día\(deficits.count == 1 ? "" : "s") con déficit proyectado",
                    message: "Ábrelos ahora como cobertura extraordinaria y llegarás al día con la plantilla completa.",
                    tone: .amber
                )
            }

            ForEach(days) { day in
                forecastRow(day)
            }
        }
    }

    private func forecastRow(_ day: CoverageForecastDay) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.dateShort(day.date).capitalized)
                    .font(.system(.subheadline, weight: .black))
                Spacer(minLength: 6)
                if day.hasDeficit {
                    CoveragePill(
                        text: "Déficit \(day.deficit)",
                        symbol: "exclamationmark.triangle.fill",
                        tone: CovTone.blocking
                    )
                } else {
                    CoveragePill(text: "Completo", symbol: "checkmark", tone: CovTone.good)
                }
            }

            HStack(spacing: 8) {
                CoverageFact(label: "Necesarios", value: "\(day.required)")
                CoverageFact(label: "Programados", value: "\(day.scheduled)")
                CoverageFact(
                    label: "En búsqueda",
                    value: "\(day.openVacancies)",
                    tone: day.openVacancies > 0 ? CovTone.pending : Palette.textMuted
                )
            }

            if day.hasDeficit {
                Text("Faltan \(day.deficit) conductor\(day.deficit == 1 ? "" : "es") para cubrir las unidades autorizadas de ese día.")
                    .font(.caption2)
                    .foregroundStyle(CovTone.blocking)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat()
    }
}
