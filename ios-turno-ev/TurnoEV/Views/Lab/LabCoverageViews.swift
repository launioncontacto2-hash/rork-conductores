import SwiftUI

/// Laboratorio → Cobertura de turnos. The console that feeds the module from zero:
/// absences, emergencies, guards, swaps, cancellations, no-shows and every failure the
/// station will eventually hit — expired documents, clashing schedules, nobody eligible,
/// three people fighting over the same seat.
struct LabCoverageView: View {
    @Environment(LabStore.self) private var lab
    @Environment(CoverageStore.self) private var coverage

    @State private var sheet: CoverageSheet?

    private enum CoverageSheet: String, Identifiable {
        case absence
        case emergency
        case guardOffer
        case swap
        case policy
        case flags

        var id: String { rawValue }
    }

    private var stations: [Station] { StaffDirectory.stations }

    private var drivers: [CoverageDriverProfile] { coverage.roster }

    var body: some View {
        LabScreen(section: .coverage) {
            LabSectionTitle(
                title: "Cobertura de turnos",
                subtitle: "Alimenta el módulo desde cero y provoca cada situación que la estación tendrá que resolver. Nada de lo que crees aquí toca un registro real.",
                symbol: "calendar.badge.clock"
            )

            if drivers.isEmpty {
                LabEmptyState(
                    title: "Sin conductores en el mundo de pruebas",
                    message: "El motor de cobertura necesita conductores con estación y bloque asignado. Crea usuarios con rol conductor antes de generar ausencias o guardias.",
                    symbol: "person.2.slash"
                )
            } else {
                counters
                creationTools
                policyCard
                LabAbsenceResolutionView()
                scenarios
                board
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .absence: LabAbsenceSheet(isEmergency: false)
            case .emergency: LabAbsenceSheet(isEmergency: true)
            case .guardOffer: LabGuardSheet()
            case .swap: LabSwapSheet()
            case .policy: LabCoveragePolicySheet()
            case .flags: LabDriverFlagsSheet()
            }
        }
    }

    // MARK: - Counters

    private var counters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabCaps(text: "Estado del módulo")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                LabStat(
                    label: "Ausencias",
                    value: "\(coverage.absences.count)",
                    tint: coverage.absences.isEmpty ? LabTone.muted : .white,
                    symbol: "calendar.badge.minus"
                )
                LabStat(
                    label: "Vacantes",
                    value: "\(coverage.vacancies.count)",
                    tint: coverage.vacancies.isEmpty ? LabTone.muted : .white,
                    symbol: "magnifyingglass"
                )
                LabStat(
                    label: "Intercambios",
                    value: "\(coverage.swaps.count)",
                    tint: coverage.swaps.isEmpty ? LabTone.muted : .white,
                    symbol: "arrow.left.arrow.right"
                )
                LabStat(
                    label: "Confirmadas",
                    value: "\(coverage.vacancies.filter { $0.status == .confirmed }.count)",
                    tint: LabTone.good,
                    symbol: "checkmark.seal.fill"
                )
                LabStat(
                    label: "Sin cubrir",
                    value: "\(coverage.vacancies.filter { $0.status == .uncovered }.count)",
                    tint: coverage.vacancies.contains { $0.status == .uncovered } ? LabTone.bad : LabTone.muted,
                    symbol: "exclamationmark.triangle.fill"
                )
                LabStat(
                    label: "Auditoría",
                    value: "\(coverage.audit.count)",
                    tint: coverage.audit.isEmpty ? LabTone.muted : .white,
                    symbol: "list.bullet.rectangle.portrait.fill"
                )
            }
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Creation

    private var creationTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabCaps(text: "Crear manualmente")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tool("Ausencia", "calendar.badge.minus") { sheet = .absence }
                tool("Emergencia", "exclamationmark.triangle.fill") { sheet = .emergency }
                tool("Guardia", "hand.raised.fill") { sheet = .guardOffer }
                tool("Intercambio", "arrow.left.arrow.right") { sheet = .swap }
                tool("Estado del conductor", "person.badge.shield.exclamationmark") { sheet = .flags }
                tool("Reglas configurables", "slider.horizontal.3") { sheet = .policy }
            }
            Text("El estado del conductor es lo que provoca licencia vencida, documentación incompleta, suspensión, vacaciones o incapacidad en el motor de elegibilidad.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
        }
        .padding(16)
        .labPanel()
    }

    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LabTone.accent)
                    .frame(width: 28, height: 28)
                    .background(LabTone.accent.opacity(0.13), in: .rect(cornerRadius: 10))
                Text(title)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(10)
            .labFlat(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Policy summary

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabCaps(text: "Reglas activas")
                Spacer(minLength: 0)
                LabChip(
                    text: coverage.policy.automation.label,
                    symbol: coverage.policy.automation.symbol,
                    tint: LabTone.accent
                )
            }
            LabRow(
                title: "Descanso mínimo \(coverage.policy.minimumRestHours) h",
                subtitle: "Máximo \(coverage.policy.maxShiftsPerWeek) jornadas y \(coverage.policy.maxGuardsPerWeek) guardias por semana",
                detail: "Emergencia bajo \(coverage.policy.emergencyThresholdHours) h · bono base \(Fmt.mxn(coverage.policy.defaultBonusMxn))",
                symbol: "slider.horizontal.3"
            )
            Text("Ningún valor legal está fijo en el código: Administración y Recursos Humanos los ajustan y el motor los aplica tal cual.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Scenarios

    private var scenarios: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Escenarios automáticos")
            ForEach(LabCoverageScenario.allCases) { scenario in
                Button {
                    run(scenario)
                } label: {
                    LabRow(
                        title: "\(scenario.letter) · \(scenario.title)",
                        subtitle: scenario.detail,
                        symbol: scenario.symbol,
                        tint: scenario.isFailure ? LabTone.bad : LabTone.accent
                    ) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LabTone.accent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .labPanel()
    }

    private func run(_ scenario: LabCoverageScenario) {
        let runner = LabCoverageRunner(coverage: coverage, lab: lab)
        let result = runner.run(scenario)
        lab.notify(result.message, tone: result.tone)
    }

    // MARK: - Board

    @ViewBuilder
    private var board: some View {
        if coverage.vacancies.isEmpty && coverage.absences.isEmpty {
            LabEmptyState(
                title: "Cobertura en cero",
                message: "No existe ninguna ausencia, vacante ni guardia. Todo lo que aparezca aquí lo habrás creado tú.",
                symbol: "circle.dashed"
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                LabCaps(text: "Vacantes del entorno de pruebas")
                ForEach(coverage.vacancies.prefix(12)) { vacancy in
                    LabRow(
                        title: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
                        subtitle: "\(vacancy.stationCode) · \(vacancy.origin.label)\(vacancy.titularName.map { " · titular \($0)" } ?? "")",
                        detail: "\(vacancy.status.label)\(vacancy.substituteName.map { " · \($0)" } ?? "")",
                        symbol: vacancy.status.symbol,
                        tint: vacancy.status == .uncovered || vacancy.status == .noShow ? LabTone.bad : LabTone.accent
                    )
                }

                Button("Vaciar cobertura de turnos") {
                    coverage.clear()
                    lab.notify("Cobertura de turnos en cero.", tone: .success)
                }
                .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
            }
            .padding(16)
            .labPanel()
        }
    }
}

// MARK: - Scenarios

/// The ten runs the module has to survive. Each one writes real records through the same
/// API the app uses, so what the test proves is the actual behaviour.
nonisolated enum LabCoverageScenario: String, CaseIterable, Identifiable, Sendable {
    case noticeSevenDays
    case lastMinute
    case noEligible
    case threeClaimants
    case acceptThenCancel
    case incompatibleShifts
    case expiredLicense
    case rejectedSubstitute
    case completedWithBonus
    case acceptedNoShow

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .noticeSevenDays: "A"
        case .lastMinute: "B"
        case .noEligible: "C"
        case .threeClaimants: "D"
        case .acceptThenCancel: "E"
        case .incompatibleShifts: "F"
        case .expiredLicense: "G"
        case .rejectedSubstitute: "H"
        case .completedWithBonus: "I"
        case .acceptedNoShow: "J"
        }
    }

    var title: String {
        switch self {
        case .noticeSevenDays: "Ausencia con 7 días de anticipación"
        case .lastMinute: "Ausencia 30 minutos antes del turno"
        case .noEligible: "Ningún conductor elegible"
        case .threeClaimants: "Tres conductores quieren la misma guardia"
        case .acceptThenCancel: "Acepta y después cancela"
        case .incompatibleShifts: "Intenta tomar dos turnos incompatibles"
        case .expiredLicense: "Licencia vencida intenta tomar guardia"
        case .rejectedSubstitute: "Supervisor rechaza al sustituto"
        case .completedWithBonus: "Guardia completada y bono aplicado"
        case .acceptedNoShow: "Acepta pero no se presenta"
        }
    }

    var detail: String {
        switch self {
        case .noticeSevenDays: "Flujo normal: solicitud, búsqueda, oferta y reserva"
        case .lastMinute: "Alerta crítica y búsqueda urgente inmediata"
        case .noEligible: "Todos bloqueados: la vacante queda descubierta"
        case .threeClaimants: "Uno reserva, dos quedan en lista de espera"
        case .acceptThenCancel: "La vacante se reabre y pasa al siguiente"
        case .incompatibleShifts: "El motor bloquea por turno simultáneo"
        case .expiredLicense: "El motor bloquea por documentación"
        case .rejectedSubstitute: "Vuelve a búsqueda con la razón registrada"
        case .completedWithBonus: "El bono existe solo al completar el turno"
        case .acceptedNoShow: "Sin bono, con registro en confiabilidad"
        }
    }

    var symbol: String {
        switch self {
        case .noticeSevenDays: "calendar.badge.clock"
        case .lastMinute: "exclamationmark.octagon.fill"
        case .noEligible: "person.2.slash"
        case .threeClaimants: "person.3.fill"
        case .acceptThenCancel: "arrow.uturn.backward.circle.fill"
        case .incompatibleShifts: "clock.badge.exclamationmark.fill"
        case .expiredLicense: "doc.badge.gearshape.fill"
        case .rejectedSubstitute: "xmark.seal.fill"
        case .completedWithBonus: "flag.checkered"
        case .acceptedNoShow: "person.fill.questionmark"
        }
    }

    var isFailure: Bool {
        switch self {
        case .noEligible, .incompatibleShifts, .expiredLicense, .rejectedSubstitute, .acceptedNoShow: true
        default: false
        }
    }
}

/// Executes a scenario against the live store. It writes through the same public API the
/// interfaces use — never straight into the arrays — so a passing run means the real
/// path works.
@MainActor
struct LabCoverageRunner {
    let coverage: CoverageStore
    let lab: LabStore

    struct Outcome {
        let message: String
        let tone: LabMessage.Tone
    }

    private var supervisorAccount: StaffAccount? {
        StaffDirectory.accounts.first { $0.role == .supervisor }
    }

    func run(_ scenario: LabCoverageScenario) -> Outcome {
        let roster = coverage.roster
        guard let titular = roster.first else {
            return Outcome(message: "No hay conductores en el entorno de pruebas.", tone: .failure)
        }
        let calendar = ShiftRules.calendar
        let now = coverage.now

        switch scenario {
        case .noticeSevenDays:
            let date = calendar.date(byAdding: .day, value: 7, to: now) ?? now
            let request = coverage.requestAbsence(
                driver: titular,
                date: date,
                slot: titular.slot,
                kind: .scheduled,
                reason: "Escenario A: aviso con una semana de anticipación",
                comments: "Generado por el laboratorio.",
                evidence: nil
            )
            let offered = coverage.vacancy(id: request.vacancyId).map { coverage.eligibleCandidates(for: $0).count } ?? 0
            return Outcome(
                message: "Escenario A listo: vacante abierta y ofrecida a \(offered) conductor(es) elegible(s).",
                tone: offered > 0 ? .success : .warning
            )

        case .lastMinute:
            // 30 minutes before the start: the request lands inside the emergency window.
            let start = ShiftRules.scheduledStart(slot: titular.slot, on: now)
            let day = start.timeIntervalSince(now) > 1800 ? now : (calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            let request = coverage.requestAbsence(
                driver: titular,
                date: day,
                slot: titular.slot,
                kind: .emergency,
                reason: "Escenario B: emergencia a 30 minutos del inicio",
                comments: "Generado por el laboratorio.",
                evidence: nil
            )
            _ = request
            return Outcome(message: "Escenario B listo: alerta crítica enviada a supervisión.", tone: .success)

        case .noEligible:
            // Everybody else is blocked, so the engine has to close the seat uncovered.
            for profile in roster where profile.id != titular.id {
                var flags = profile.flags
                flags.documentsValid = false
                coverage.setFlags(flags, for: profile.id)
            }
            let date = calendar.date(byAdding: .day, value: 3, to: now) ?? now
            let request = coverage.requestAbsence(
                driver: titular,
                date: date,
                slot: titular.slot,
                kind: .scheduled,
                reason: "Escenario C: nadie elegible",
                comments: "Toda la plantilla quedó con documentación vencida.",
                evidence: nil
            )
            let status = coverage.absence(id: request.id)?.status ?? .searching
            return Outcome(
                message: status == .uncovered
                    ? "Escenario C listo: la vacante quedó SIN COBERTURA, como debía."
                    : "Escenario C ejecutado, pero aún hay candidatos elegibles.",
                tone: status == .uncovered ? .success : .warning
            )

        case .threeClaimants:
            guard let vacancy = openVacancy(titular: titular, reason: "Escenario D: tres conductores la quieren") else {
                return Outcome(message: "No se pudo abrir la vacante del escenario D.", tone: .failure)
            }
            let takers = coverage.eligibleCandidates(for: vacancy).prefix(3)
            guard takers.count >= 2 else {
                return Outcome(message: "El escenario D necesita al menos dos conductores elegibles.", tone: .warning)
            }
            var reserved = 0
            var waitlisted = 0
            for taker in takers {
                guard let profile = coverage.profile(id: taker.driverId) else { continue }
                switch coverage.claimGuard(vacancyId: vacancy.id, by: profile) {
                case .reserved: reserved += 1
                case .waitlisted: waitlisted += 1
                default: break
                }
            }
            return Outcome(
                message: "Escenario D listo: \(reserved) reservó y \(waitlisted) quedaron en lista de espera.",
                tone: reserved == 1 ? .success : .failure
            )

        case .acceptThenCancel:
            guard let vacancy = openVacancy(titular: titular, reason: "Escenario E: acepta y luego cancela"),
                  let taker = coverage.eligibleCandidates(for: vacancy).first,
                  let profile = coverage.profile(id: taker.driverId) else {
                return Outcome(message: "El escenario E necesita un conductor elegible.", tone: .warning)
            }
            _ = coverage.claimGuard(vacancyId: vacancy.id, by: profile)
            coverage.cancelClaim(vacancyId: vacancy.id, driverId: profile.id, reason: "Escenario E: cancelación posterior")
            let reopened = coverage.vacancy(id: vacancy.id)?.status
            return Outcome(
                message: "Escenario E listo: la vacante quedó en \(reopened?.label.lowercased() ?? "—").",
                tone: .success
            )

        case .incompatibleShifts:
            // Same day, the block the person already holds: the engine must refuse.
            guard let other = roster.first(where: { $0.id != titular.id }) ?? roster.first else {
                return Outcome(message: "No hay conductores para el escenario F.", tone: .warning)
            }
            let day = nextDay(matching: other.group, from: now)
            guard let vacancy = openVacancy(
                titular: titular,
                reason: "Escenario F: turno simultáneo",
                date: day,
                slot: other.slot
            ) else {
                return Outcome(message: "No se pudo abrir la vacante del escenario F.", tone: .failure)
            }
            let outcome = coverage.claimGuard(vacancyId: vacancy.id, by: other)
            if case .notEligible(let blockers) = outcome {
                return Outcome(
                    message: "Escenario F listo: bloqueado por \(blockers.map(\.rule.label).joined(separator: ", ")).",
                    tone: .success
                )
            }
            return Outcome(message: "Escenario F: el motor NO bloqueó el turno simultáneo.", tone: .failure)

        case .expiredLicense:
            guard let other = roster.first(where: { $0.id != titular.id }) else {
                return Outcome(message: "El escenario G necesita un segundo conductor.", tone: .warning)
            }
            var flags = other.flags
            flags.licenseValidUntil = calendar.date(byAdding: .day, value: -5, to: now)
            coverage.setFlags(flags, for: other.id)
            guard let vacancy = openVacancy(titular: titular, reason: "Escenario G: licencia vencida"),
                  let refreshed = coverage.profile(id: other.id) else {
                return Outcome(message: "No se pudo abrir la vacante del escenario G.", tone: .failure)
            }
            let outcome = coverage.claimGuard(vacancyId: vacancy.id, by: refreshed)
            if case .notEligible(let blockers) = outcome {
                return Outcome(
                    message: "Escenario G listo: bloqueado por \(blockers.map(\.rule.label).joined(separator: ", ")).",
                    tone: .success
                )
            }
            return Outcome(message: "Escenario G: el motor NO bloqueó la licencia vencida.", tone: .failure)

        case .rejectedSubstitute:
            guard let account = supervisorAccount else {
                return Outcome(message: "No hay supervisor en el entorno para firmar.", tone: .warning)
            }
            guard let vacancy = openVacancy(titular: titular, reason: "Escenario H: supervisor rechaza"),
                  let taker = coverage.eligibleCandidates(for: vacancy).first,
                  let profile = coverage.profile(id: taker.driverId) else {
                return Outcome(message: "El escenario H necesita un conductor elegible.", tone: .warning)
            }
            _ = coverage.claimGuard(vacancyId: vacancy.id, by: profile)
            coverage.rejectSubstitute(vacancyId: vacancy.id, by: account, reason: "Escenario H: no procede el sustituto.")
            return Outcome(message: "Escenario H listo: sustituto rechazado y vacante reabierta.", tone: .success)

        case .completedWithBonus:
            guard let account = supervisorAccount else {
                return Outcome(message: "No hay supervisor en el entorno para firmar.", tone: .warning)
            }
            guard let vacancy = openVacancy(titular: titular, reason: "Escenario I: guardia completada"),
                  let taker = coverage.eligibleCandidates(for: vacancy).first,
                  let profile = coverage.profile(id: taker.driverId) else {
                return Outcome(message: "El escenario I necesita un conductor elegible.", tone: .warning)
            }
            _ = coverage.claimGuard(vacancyId: vacancy.id, by: profile)
            coverage.approveVacancy(id: vacancy.id, by: account)
            coverage.markCompleted(vacancyId: vacancy.id, by: account)
            let earned = coverage.earnedGuardBonusMxn(driverId: profile.id)
            return Outcome(
                message: "Escenario I listo: \(profile.shortName) acumula \(Fmt.mxn(earned)) en bonos por guardia.",
                tone: .success
            )

        case .acceptedNoShow:
            guard let account = supervisorAccount else {
                return Outcome(message: "No hay supervisor en el entorno para firmar.", tone: .warning)
            }
            guard let vacancy = openVacancy(titular: titular, reason: "Escenario J: aceptó y no se presentó"),
                  let taker = coverage.eligibleCandidates(for: vacancy).first,
                  let profile = coverage.profile(id: taker.driverId) else {
                return Outcome(message: "El escenario J necesita un conductor elegible.", tone: .warning)
            }
            _ = coverage.claimGuard(vacancyId: vacancy.id, by: profile)
            coverage.approveVacancy(id: vacancy.id, by: account)
            coverage.markNoShow(vacancyId: vacancy.id, by: account, note: "Escenario J del laboratorio.")
            let reliability = coverage.reliability(driverId: profile.id)
            return Outcome(
                message: "Escenario J listo: sin bono. Confiabilidad de \(profile.shortName): \(reliability?.score ?? 0).",
                tone: .success
            )
        }
    }

    /// Opens a seat through the absence path so the whole chain is exercised, not just
    /// the vacancy record.
    private func openVacancy(
        titular: CoverageDriverProfile,
        reason: String,
        date: Date? = nil,
        slot: ShiftSlot? = nil
    ) -> CoverageVacancy? {
        let day = date ?? ShiftRules.calendar.date(byAdding: .day, value: 5, to: coverage.now) ?? coverage.now
        let request = coverage.requestAbsence(
            driver: titular,
            date: day,
            slot: slot ?? titular.slot,
            kind: .scheduled,
            reason: reason,
            comments: "Generado por el laboratorio.",
            evidence: nil
        )
        return coverage.vacancy(id: request.vacancyId)
    }

    /// Next date whose group matches the driver's, so their own block really exists there.
    private func nextDay(matching group: ShiftGroup, from date: Date) -> Date {
        let calendar = ShiftRules.calendar
        for offset in 1...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if ShiftRules.group(for: day) == group { return day }
        }
        return date
    }
}

// MARK: - Absence sheet

struct LabAbsenceSheet: View {
    let isEmergency: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(LabStore.self) private var lab
    @Environment(CoverageStore.self) private var coverage

    @State private var driverId: String = ""
    @State private var date: Date = Date()
    @State private var slot: ShiftSlot = .morning
    @State private var kind: AbsenceKind = .scheduled
    @State private var reason: String = ""

    private var drivers: [CoverageDriverProfile] { coverage.roster }
    private var driver: CoverageDriverProfile? { drivers.first { $0.id == driverId } }

    var body: some View {
        LabSheet(
            title: isEmergency ? "Ausencia de emergencia" : "Ausencia programada",
            subtitle: "El motor detectará solo la estación, la fecha, el horario y el titular, y abrirá la vacante temporal.",
            confirmTitle: "Generar",
            isConfirmEnabled: driver != nil,
            onConfirm: create
        ) {
            LabOptionRow(
                label: "Conductor titular",
                options: drivers.map(\.id),
                selection: $driverId,
                title: { id in drivers.first { $0.id == id }?.shortName ?? id }
            )

            VStack(alignment: .leading, spacing: 6) {
                LabCaps(text: "Fecha")
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(LabTone.accent)
            }

            LabOptionRow(
                label: "Turno",
                options: ShiftSlot.allCases,
                selection: $slot,
                title: { $0.label }
            )

            LabOptionRow(
                label: "Tipo",
                options: AbsenceKind.allCases,
                selection: $kind,
                title: { $0.shortLabel }
            )

            LabField(label: "Motivo", placeholder: "Motivo de la ausencia", text: $reason)
        }
        .onAppear {
            driverId = drivers.first?.id ?? ""
            slot = drivers.first?.slot ?? .morning
            if isEmergency { kind = .emergency }
        }
    }

    private func create() {
        guard let driver else { return }
        let request = coverage.requestAbsence(
            driver: driver,
            date: date,
            slot: slot,
            kind: kind,
            reason: reason.isEmpty ? kind.label : reason,
            comments: "Creada desde el laboratorio de pruebas.",
            evidence: nil
        )
        let status = coverage.absence(id: request.id)?.status ?? .searching
        lab.notify("Ausencia creada. Estado: \(status.label).", tone: status == .uncovered ? .warning : .success)
        dismiss()
    }
}

// MARK: - Guard sheet

struct LabGuardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LabStore.self) private var lab
    @Environment(CoverageStore.self) private var coverage

    @State private var stationId: String = ""
    @State private var date: Date = Date()
    @State private var slot: ShiftSlot = .morning
    @State private var seats: Int = 1
    @State private var bonusMode: GuardBonusMode = .fixed
    @State private var bonusMxn: Int = 450
    @State private var reason: String = "Demanda extraordinaria"

    private var stations: [Station] { StaffDirectory.stations }
    private var station: Station? { stations.first { $0.id == stationId } }

    var body: some View {
        LabSheet(
            title: "Guardia extraordinaria",
            subtitle: "Abre cobertura sin que exista ninguna ausencia y observa a quién se la ofrece el motor.",
            confirmTitle: "Abrir",
            isConfirmEnabled: station != nil,
            onConfirm: create
        ) {
            LabOptionRow(
                label: "Estación",
                options: stations.map(\.id),
                selection: $stationId,
                title: { id in stations.first { $0.id == id }?.code ?? id }
            )

            VStack(alignment: .leading, spacing: 6) {
                LabCaps(text: "Fecha")
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(LabTone.accent)
            }

            LabOptionRow(label: "Turno", options: ShiftSlot.allCases, selection: $slot, title: { $0.label })
            LabNumberField(label: "Conductores", value: $seats, range: 1...20)
            LabOptionRow(label: "Bono", options: GuardBonusMode.allCases, selection: $bonusMode, title: { $0.label })

            if bonusMode != .none {
                LabNumberField(label: "Monto del bono", value: $bonusMxn, range: 0...5000, step: 50, suffix: "MXN")
            }

            LabField(label: "Motivo", placeholder: "Evento, demanda, unidad adicional…", text: $reason)
        }
        .onAppear {
            stationId = stations.first?.id ?? ""
            bonusMxn = coverage.policy.defaultBonusMxn
        }
    }

    private func create() {
        guard let station,
              let account = StaffDirectory.accounts.first(where: { $0.role == .supervisor && $0.stationId == station.id })
                ?? StaffDirectory.accounts.first(where: { $0.role == .supervisor }) else {
            lab.notify("No hay supervisor que pueda abrir la guardia.", tone: .failure)
            return
        }
        let created = coverage.createExtraordinaryVacancy(
            station: station,
            date: date,
            slot: slot,
            seats: seats,
            bonusMode: bonusMode,
            bonusMxn: bonusMxn,
            reason: reason,
            by: account
        )
        let offered = created.first.map { coverage.eligibleCandidates(for: $0).count } ?? 0
        lab.notify("\(created.count) guardia(s) abierta(s), ofrecida(s) a \(offered) elegible(s).", tone: .success)
        dismiss()
    }
}

// MARK: - Swap sheet

struct LabSwapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LabStore.self) private var lab
    @Environment(CoverageStore.self) private var coverage

    @State private var fromId: String = ""
    @State private var toId: String = ""
    @State private var fromDate: Date = Date()
    @State private var toDate: Date = Date()
    @State private var autoAccept: Bool = true

    private var drivers: [CoverageDriverProfile] { coverage.roster }

    var body: some View {
        LabSheet(
            title: "Intercambio de turnos",
            subtitle: "Propone el cambio y, si lo pides, hace que la contraparte acepte para dejarlo listo ante el supervisor.",
            confirmTitle: "Generar",
            isConfirmEnabled: !fromId.isEmpty && !toId.isEmpty && fromId != toId,
            onConfirm: create
        ) {
            LabOptionRow(
                label: "Propone",
                options: drivers.map(\.id),
                selection: $fromId,
                title: { id in drivers.first { $0.id == id }?.shortName ?? id }
            )
            LabOptionRow(
                label: "Contraparte",
                options: drivers.map(\.id),
                selection: $toId,
                title: { id in drivers.first { $0.id == id }?.shortName ?? id }
            )

            VStack(alignment: .leading, spacing: 6) {
                LabCaps(text: "Turno que cede")
                DatePicker("", selection: $fromDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(LabTone.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                LabCaps(text: "Turno que toma")
                DatePicker("", selection: $toDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(LabTone.accent)
            }

            LabToggleRow(
                title: "La contraparte acepta",
                subtitle: "Deja la solicitud esperando la firma del supervisor",
                isOn: $autoAccept
            )
        }
        .onAppear {
            fromId = drivers.first?.id ?? ""
            toId = drivers.dropFirst().first?.id ?? drivers.first?.id ?? ""
        }
    }

    private func create() {
        guard let from = drivers.first(where: { $0.id == fromId }),
              let to = drivers.first(where: { $0.id == toId }) else { return }
        let request = coverage.proposeSwap(
            from: from,
            fromDate: fromDate,
            fromSlot: from.slot,
            to: to,
            toDate: toDate,
            toSlot: to.slot,
            note: "Intercambio creado desde el laboratorio."
        )
        if autoAccept {
            coverage.respondToSwap(id: request.id, accepted: true, by: to)
        }
        lab.notify("Intercambio generado entre \(from.shortName) y \(to.shortName).", tone: .success)
        dismiss()
    }
}

// MARK: - Driver flags

/// The switches that make the eligibility engine say no. Everything the employee file and
/// the document vault will eventually provide is faked here, one driver at a time.
struct LabDriverFlagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LabStore.self) private var lab
    @Environment(CoverageStore.self) private var coverage

    @State private var driverId: String = ""
    @State private var documentsValid: Bool = true
    @State private var isSuspended: Bool = false
    @State private var licenseExpired: Bool = false
    @State private var onVacation: Bool = false
    @State private var incapacitated: Bool = false
    @State private var acceptsExtraordinary: Bool = false

    private var drivers: [CoverageDriverProfile] { coverage.roster }

    var body: some View {
        LabSheet(
            title: "Estado del conductor",
            subtitle: "Provoca licencia vencida, documentación incompleta, suspensión, vacaciones o incapacidad y comprueba cómo responde el motor.",
            confirmTitle: "Aplicar",
            isConfirmEnabled: !driverId.isEmpty,
            onConfirm: apply
        ) {
            LabOptionRow(
                label: "Conductor",
                options: drivers.map(\.id),
                selection: $driverId,
                title: { id in drivers.first { $0.id == id }?.shortName ?? id }
            )

            LabToggleRow(title: "Documentación vigente", isOn: $documentsValid)
            LabToggleRow(title: "Licencia vencida", subtitle: "Vencida hace cinco días", isOn: $licenseExpired)
            LabToggleRow(title: "Suspendido", isOn: $isSuspended)
            LabToggleRow(title: "De vacaciones", subtitle: "Por los próximos 15 días", isOn: $onVacation)
            LabToggleRow(title: "Incapacitado", subtitle: "Por los próximos 10 días", isOn: $incapacitated)
            LabToggleRow(
                title: "Declaró disponibilidad extraordinaria",
                subtitle: "Sube su prioridad al ofrecer guardias",
                isOn: $acceptsExtraordinary
            )
        }
        .onAppear {
            driverId = drivers.first?.id ?? ""
            loadCurrent()
        }
        .onChange(of: driverId) { _, _ in loadCurrent() }
    }

    private func loadCurrent() {
        let flags = coverage.flags[driverId] ?? .clear
        documentsValid = flags.documentsValid
        isSuspended = flags.isSuspended
        licenseExpired = flags.licenseValidUntil.map { $0 < coverage.now } ?? false
        onVacation = flags.vacationUntil.map { $0 > coverage.now } ?? false
        incapacitated = flags.incapacityUntil.map { $0 > coverage.now } ?? false
        acceptsExtraordinary = flags.acceptsExtraordinary
    }

    private func apply() {
        let calendar = ShiftRules.calendar
        let flags = CoverageDriverFlags(
            licenseValidUntil: licenseExpired ? calendar.date(byAdding: .day, value: -5, to: coverage.now) : nil,
            documentsValid: documentsValid,
            isSuspended: isSuspended,
            vacationUntil: onVacation ? calendar.date(byAdding: .day, value: 15, to: coverage.now) : nil,
            incapacityUntil: incapacitated ? calendar.date(byAdding: .day, value: 10, to: coverage.now) : nil,
            acceptsExtraordinary: acceptsExtraordinary
        )
        coverage.setFlags(flags, for: driverId)
        let name = drivers.first { $0.id == driverId }?.shortName ?? "conductor"
        lab.notify("Estado de \(name) actualizado.", tone: .success)
        dismiss()
    }
}

// MARK: - Policy

struct LabCoveragePolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LabStore.self) private var lab
    @Environment(CoverageStore.self) private var coverage

    @State private var minimumRestHours: Int = 8
    @State private var maxShiftsPerWeek: Int = 6
    @State private var maxGuardsPerWeek: Int = 3
    @State private var emergencyThresholdHours: Int = 12
    @State private var defaultBonusMxn: Int = 450
    @State private var allowsCrossStation: Bool = false
    @State private var absenceRequiresAuthorization: Bool = true
    @State private var automation: CoverageAutomation = .semiAutomatic

    var body: some View {
        LabSheet(
            title: "Reglas configurables",
            subtitle: "Ningún valor legal está fijo en el código. Esto es lo que Administración y Recursos Humanos ajustarán en producción.",
            confirmTitle: "Guardar",
            onConfirm: save
        ) {
            LabNumberField(label: "Descanso mínimo entre jornadas", value: $minimumRestHours, range: 0...24, suffix: "h")
            LabNumberField(label: "Máximo de jornadas por semana", value: $maxShiftsPerWeek, range: 1...14)
            LabNumberField(label: "Máximo de guardias por semana", value: $maxGuardsPerWeek, range: 0...7)
            LabNumberField(label: "Umbral de emergencia", value: $emergencyThresholdHours, range: 1...48, suffix: "h")
            LabNumberField(label: "Bono base de guardia", value: $defaultBonusMxn, range: 0...5000, step: 50, suffix: "MXN")

            LabOptionRow(
                label: "Automatización",
                options: CoverageAutomation.allCases,
                selection: $automation,
                title: { $0.label },
                symbol: { $0.symbol }
            )

            LabToggleRow(
                title: "Permitir conductores de otra estación",
                subtitle: "Amplía el pool más allá de la estación de la vacante",
                isOn: $allowsCrossStation
            )
            LabToggleRow(
                title: "La ausencia requiere autorización",
                subtitle: "Cubrir el turno nunca autoriza la falta por sí solo",
                isOn: $absenceRequiresAuthorization
            )
        }
        .onAppear {
            let policy = coverage.policy
            minimumRestHours = policy.minimumRestHours
            maxShiftsPerWeek = policy.maxShiftsPerWeek
            maxGuardsPerWeek = policy.maxGuardsPerWeek
            emergencyThresholdHours = policy.emergencyThresholdHours
            defaultBonusMxn = policy.defaultBonusMxn
            allowsCrossStation = policy.allowsCrossStation
            absenceRequiresAuthorization = policy.absenceRequiresAuthorization
            automation = policy.automation
        }
    }

    private func save() {
        coverage.updatePolicy(
            CoveragePolicy(
                minimumRestHours: minimumRestHours,
                maxShiftsPerWeek: maxShiftsPerWeek,
                maxGuardsPerWeek: maxGuardsPerWeek,
                maxConsecutiveDays: coverage.policy.maxConsecutiveDays,
                emergencyThresholdHours: emergencyThresholdHours,
                claimHoldMinutes: coverage.policy.claimHoldMinutes,
                allowsCrossStation: allowsCrossStation,
                absenceRequiresAuthorization: absenceRequiresAuthorization,
                automation: automation,
                defaultBonusMxn: defaultBonusMxn
            )
        )
        lab.notify("Reglas de cobertura actualizadas.", tone: .success)
        dismiss()
    }
}
