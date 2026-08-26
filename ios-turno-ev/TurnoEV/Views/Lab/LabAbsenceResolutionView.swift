import SwiftUI

/// Laboratorio → Resolver ausencias. Configures the thresholds of the module and runs the
/// twenty situations it has to survive, driving the real engine instead of printing
/// invented numbers.
struct LabAbsenceResolutionView: View {
    @Environment(LabStore.self) private var lab
    @Environment(CoverageStore.self) private var coverage
    @Environment(FleetStore.self) private var fleet

    @State private var policy: AbsencePolicy = AbsenceResolutionConfig.policy
    @State private var reserve: ReservePolicy = .standard
    @State private var stationId: String = ""
    @State private var version: Int = 0

    private var stations: [Station] { StaffDirectory.stations }

    private var station: Station? {
        stations.first { $0.id == stationId } ?? stations.first
    }

    /// Length of a block, taken from the operating window — never a literal.
    private var shiftMinutes: Int {
        let window = ShiftRules.window(for: .morning)
        return max(1, window.end - window.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabCaps(text: "Resolver ausencias")
            Text("Tolerancia, unidades de reserva y los veinte escenarios del motor automático. Todo se ejecuta contra el mismo motor que usa la estación.")
                .font(.caption)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            stationPicker
            policyCard
            reserveCard
            fleetCard
            scenarioList
        }
        .padding(16)
        .labPanel()
        .id(version)
        .onAppear(perform: load)
    }

    private func load() {
        if stationId.isEmpty { stationId = stations.first?.id ?? "" }
        policy = AbsenceResolutionConfig.policy
        reserve = AbsenceResolutionConfig.reservePolicy(stationId: stationId)
    }

    // MARK: - Station

    @ViewBuilder
    private var stationPicker: some View {
        if stations.count > 1 {
            LabOptionRow(
                label: "Estación",
                options: stations.map(\.id),
                selection: Binding(
                    get: { stationId },
                    set: {
                        stationId = $0
                        reserve = AbsenceResolutionConfig.reservePolicy(stationId: $0)
                    }
                ),
                title: { id in stations.first { $0.id == id }?.code ?? id }
            )
        }
    }

    // MARK: - Policy

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Umbrales configurables")

            LabNumberField(
                label: "Tolerancia antes de declarar ausencia",
                value: $policy.toleranceMinutes,
                range: 0...240,
                step: 5,
                suffix: "min"
            )
            LabNumberField(
                label: "Tiempo productivo mínimo",
                value: $policy.minimumProductiveMinutes,
                range: 0...480,
                step: 15,
                suffix: "min"
            )
            LabNumberField(
                label: "Ventana para confirmar",
                value: $policy.confirmationWindowMinutes,
                range: 1...120,
                step: 5,
                suffix: "min"
            )
            LabNumberField(
                label: "Meta de productividad por hora",
                value: $policy.hourlyGoalMxn,
                range: 0...2_000,
                step: 10,
                suffix: "MXN/h"
            )
            LabNumberField(
                label: "Pago del turno completo",
                value: $policy.shiftPayMxn,
                range: 0...5_000,
                step: 50,
                suffix: "MXN"
            )

            Text("Turno de \(shiftMinutes) min → \(String(format: "%.4f", policy.ratePerMinuteMxn(shiftMinutes: shiftMinutes))) MXN por minuto efectivo · meta \(String(format: "%.4f", policy.goalPerMinuteMxn)) MXN por minuto.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Guardar umbrales") {
                AbsenceResolutionConfig.setPolicy(policy)
                lab.notify("Umbrales de resolución guardados.", tone: .success)
                version += 1
            }
            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
        }
        .padding(14)
        .labFlat()
    }

    // MARK: - Reserve

    private var reserveCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Unidades de reserva de la estación")

            LabNumberField(label: "Reservas objetivo", value: $reserve.targetUnits, range: 0...20, suffix: "u")
            LabNumberField(
                label: "Máximo en producción extraordinaria",
                value: $reserve.maxInExtraordinaryUse,
                range: 0...20,
                suffix: "u"
            )
            LabNumberField(
                label: "Mínimo protegido para contingencia",
                value: $reserve.minimumProtected,
                range: 0...20,
                suffix: "u"
            )

            Text("Con \(reserve.targetUnits) reservas, el motor podrá comprometer como máximo \(reserve.usableUnits(available: reserve.targetUnits)) y siempre dejará \(reserve.minimumProtected) intacta(s).")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Guardar reservas") {
                AbsenceResolutionConfig.setReservePolicy(reserve, stationId: stationId)
                lab.notify("Política de reservas guardada para \(station?.code ?? stationId).", tone: .success)
                version += 1
            }
            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
        }
        .padding(14)
        .labFlat()
    }

    // MARK: - Approved fleet

    /// A unit is never a reserve just because it left the rotation: it has to be approved.
    private var fleetCard: some View {
        let units = LabRuntime.vehicles.filter { $0.stationId == stationId }
        return VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Aprobadas como unidad de reserva")

            if units.isEmpty {
                Text("Sin unidades instaladas en esta estación del entorno de pruebas.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(units.prefix(10)) { unit in
                    let approved = ReserveFleetRegistry.isApproved(vehicleId: unit.id)
                    Button {
                        if approved {
                            ReserveFleetRegistry.revoke(vehicleId: unit.id)
                        } else {
                            ReserveFleetRegistry.approve(vehicleId: unit.id)
                        }
                        version += 1
                    } label: {
                        LabRow(
                            title: unit.internalNumber,
                            subtitle: unit.model,
                            detail: approved ? "Aprobada como reserva" : "Rotación ordinaria",
                            symbol: approved ? "checkmark.seal.fill" : "car.side.fill",
                            tint: approved ? LabTone.good : LabTone.muted
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .labFlat()
    }

    // MARK: - Scenarios

    private var scenarioList: some View {
        VStack(alignment: .leading, spacing: 9) {
            LabCaps(text: "Escenarios del motor automático")
            ForEach(LabResolutionScenario.allCases) { scenario in
                Button {
                    run(scenario)
                } label: {
                    LabRow(
                        title: "\(scenario.number) · \(scenario.title)",
                        subtitle: scenario.expectation,
                        symbol: scenario.symbol,
                        tint: scenario.expectsEscalation ? LabTone.bad : LabTone.accent
                    ) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LabTone.accent)
                    }
                }
                .buttonStyle(.plain)
            }

            Button("Vaciar resolución de ausencias") {
                guard let station else { return }
                let store = AbsenceResolutionStore(stationId: station.id)
                store.clearAll()
                lab.notify("Casos de resolución en cero.", tone: .success)
                version += 1
            }
            .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
        }
        .padding(14)
        .labFlat()
    }

    private func run(_ scenario: LabResolutionScenario) {
        guard let station else {
            lab.notify("Crea una estación antes de ejecutar escenarios.", tone: .failure)
            return
        }
        guard let supervisorAccount = StaffDirectory.accounts.first(
            where: { $0.role == .supervisor && $0.stationId == station.id }
        ) else {
            lab.notify("Esta estación no tiene supervisor: el motor no puede reportar.", tone: .warning)
            return
        }

        let supervision = SupervisionStore(account: supervisorAccount, fleet: fleet)
        supervision.refresh()
        let store = AbsenceResolutionStore(stationId: station.id)
        store.configure(supervision: supervision, coverage: coverage)

        let runner = LabResolutionRunner(
            resolution: store,
            supervision: supervision,
            coverage: coverage,
            station: station
        )
        let outcome = runner.run(scenario)
        lab.notify(outcome.message, tone: outcome.tone)
        version += 1
    }
}

// MARK: - Scenarios

/// The twenty runs of the module, in the order the specification lists them.
nonisolated enum LabResolutionScenario: String, CaseIterable, Identifiable, Sendable {
    case withinTolerance
    case crossesTolerance
    case noReserves
    case oneReserve
    case reserveLimits
    case twoCandidates
    case conflictingCandidate
    case noConfirmation
    case confirmsThenCancels
    case twoOpportunities
    case twoAbsences
    case moreAbsencesThanCapacity
    case allReject
    case lateEta
    case fullExtraordinary
    case partialCoverage
    case aboveGoal
    case belowGoal
    case reserveTaken
    case unresolvable

    var id: String { rawValue }

    var number: String {
        guard let index = Self.allCases.firstIndex(of: self) else { return "" }
        return "\(index + 1)"
    }

    var title: String {
        switch self {
        case .withinTolerance: "Llega dentro de la tolerancia"
        case .crossesTolerance: "Cruza la tolerancia"
        case .noReserves: "Ausencia con 0 reservas"
        case .oneReserve: "Ausencia con 1 reserva"
        case .reserveLimits: "Tres reservas configuradas"
        case .twoCandidates: "Dos candidatos con distinta ETA"
        case .conflictingCandidate: "ETA menor pero con conflicto"
        case .noConfirmation: "El seleccionado no confirma"
        case .confirmsThenCancels: "Confirma y después cancela"
        case .twoOpportunities: "Dos oportunidades simultáneas"
        case .twoAbsences: "Dos ausencias simultáneas"
        case .moreAbsencesThanCapacity: "Más ausencias que capacidad"
        case .allReject: "Todos rechazan"
        case .lateEta: "ETA tardía con pocas horas"
        case .fullExtraordinary: "Guardia extraordinaria completa"
        case .partialCoverage: "Cobertura parcial"
        case .aboveGoal: "Productividad sobre la meta"
        case .belowGoal: "Productividad bajo la meta"
        case .reserveTaken: "Reserva ocupada"
        case .unresolvable: "Fallo no resoluble"
        }
    }

    var expectation: String {
        switch self {
        case .withinTolerance: "Demorado, sin sustitución"
        case .crossesTolerance: "Ausencia + búsqueda automática"
        case .noReserves: "Solo recuperación del vehículo ordinario"
        case .oneReserve: "Dos oportunidades posibles"
        case .reserveLimits: "Respeta máximo y mínimo protegido"
        case .twoCandidates: "Gana la ETA más temprana"
        case .conflictingCandidate: "Se descarta al que tiene conflicto"
        case .noConfirmation: "Pasa automáticamente al siguiente"
        case .confirmsThenCancels: "Reabre la búsqueda sola"
        case .twoOpportunities: "A al ordinario, B a la reserva"
        case .twoAbsences: "Búsquedas independientes sin doble asignación"
        case .moreAbsencesThanCapacity: "Resuelve las posibles y escala el resto"
        case .allReject: "Escala al supervisor"
        case .lateEta: "Bloqueada por tiempo útil mínimo"
        case .fullExtraordinary: "Pago por minuto efectivo"
        case .partialCoverage: "Pago proporcional"
        case .aboveGoal: "Meta dinámica cumplida"
        case .belowGoal: "Registrado sin penalización"
        case .reserveTaken: "Sale de reservas disponibles"
        case .unresolvable: "Intervención requerida"
        }
    }

    var symbol: String {
        switch self {
        case .withinTolerance: "clock.fill"
        case .crossesTolerance: "person.fill.xmark"
        case .noReserves: "car.side.fill"
        case .oneReserve: "sparkles"
        case .reserveLimits: "lock.shield.fill"
        case .twoCandidates: "person.2.fill"
        case .conflictingCandidate: "exclamationmark.triangle.fill"
        case .noConfirmation: "hourglass"
        case .confirmsThenCancels: "arrow.uturn.backward.circle.fill"
        case .twoOpportunities: "square.split.2x1.fill"
        case .twoAbsences: "person.3.fill"
        case .moreAbsencesThanCapacity: "exclamationmark.octagon.fill"
        case .allReject: "hand.thumbsdown.fill"
        case .lateEta: "timer"
        case .fullExtraordinary: "flag.checkered"
        case .partialCoverage: "chart.pie.fill"
        case .aboveGoal: "arrow.up.right.circle.fill"
        case .belowGoal: "arrow.down.right.circle.fill"
        case .reserveTaken: "car.fill"
        case .unresolvable: "xmark.octagon.fill"
        }
    }

    var expectsEscalation: Bool {
        switch self {
        case .allReject, .moreAbsencesThanCapacity, .unresolvable, .lateEta, .conflictingCandidate: true
        default: false
        }
    }
}

/// Runs a scenario through the public API of the engine, never straight into its state.
@MainActor
struct LabResolutionRunner {
    let resolution: AbsenceResolutionStore
    let supervision: SupervisionStore
    let coverage: CoverageStore
    let station: Station

    struct Outcome {
        let message: String
        let tone: LabMessage.Tone
    }

    /// Logical time as the runner reads it.
    ///
    /// This is a `struct` with a `run(_:)` method, not a `View`: it is only ever entered
    /// from a button handler, so nothing it reads registers a SwiftUI dependency. It used to
    /// re-export `SupervisionStore.now`, which reached `FleetStore.now`; going straight to
    /// `AppClock` says the same thing without pretending to be reactive. Same reasoning as
    /// `AbsenceResolutionStore.now`.
    private var now: Date { AppClock.now() }

    private var candidates: [CoverageDriverProfile] {
        coverage.roster(stationId: station.id)
    }

    /// A driver of the roster who could be declared absent.
    private func titular(skipping used: Set<String> = []) -> StationDriver? {
        supervision.allDrivers(now: now).first { !used.contains($0.id) }
    }

    func run(_ scenario: LabResolutionScenario) -> Outcome {
        switch scenario {
        case .withinTolerance:
            return runWithinTolerance()
        case .crossesTolerance:
            return runCrossesTolerance()
        case .noReserves:
            return runReserveCount(0)
        case .oneReserve:
            return runReserveCount(1)
        case .reserveLimits:
            return runReserveLimits()
        case .twoCandidates:
            return runTwoCandidates()
        case .conflictingCandidate:
            return runConflictingCandidate()
        case .noConfirmation:
            return runNoConfirmation()
        case .confirmsThenCancels:
            return runConfirmsThenCancels()
        case .twoOpportunities:
            return runTwoOpportunities()
        case .twoAbsences:
            return runTwoAbsences()
        case .moreAbsencesThanCapacity:
            return runMoreAbsencesThanCapacity()
        case .allReject:
            return runAllReject()
        case .lateEta:
            return runLateEta()
        case .fullExtraordinary:
            return runWork(minutes: 420, earnings: 1_400, label: "Guardia extraordinaria completa")
        case .partialCoverage:
            return runWork(minutes: 180, earnings: 600, label: "Cobertura parcial")
        case .aboveGoal:
            return runWork(minutes: 180, earnings: 590, label: "Productividad sobre la meta")
        case .belowGoal:
            return runWork(minutes: 180, earnings: 400, label: "Productividad bajo la meta")
        case .reserveTaken:
            return runReserveTaken()
        case .unresolvable:
            return runUnresolvable()
        }
    }

    // MARK: - Individual runs

    private func runWithinTolerance() -> Outcome {
        guard let driver = titular() else { return .init(message: "Sin conductores en la estación.", tone: .failure) }
        let policy = resolution.policy
        let inside = driver.scheduledStartAt.addingTimeInterval(TimeInterval((policy.toleranceMinutes - 5) * 60))
        let verdict = AttendanceRules.verdict(
            scheduledStart: driver.scheduledStartAt,
            checkIn: nil,
            now: inside,
            policy: policy
        )
        return Outcome(
            message: verdict == .late
                ? "Escenario 1 correcto: a los \(policy.toleranceMinutes - 5) min el estado es DEMORADO y no se abre sustitución."
                : "Escenario 1 falló: el motor devolvió \(verdict.label.uppercased()).",
            tone: verdict == .late ? .success : .failure
        )
    }

    private func runCrossesTolerance() -> Outcome {
        guard let driver = titular() else { return .init(message: "Sin conductores en la estación.", tone: .failure) }
        let policy = resolution.policy
        let after = AttendanceRules
            .absenceDeadline(scheduledStart: driver.scheduledStartAt, policy: policy)
            .addingTimeInterval(60)
        let verdict = AttendanceRules.verdict(
            scheduledStart: driver.scheduledStartAt,
            checkIn: nil,
            now: after,
            policy: policy
        )
        guard verdict == .absent else {
            return Outcome(message: "Escenario 2 falló: el estado fue \(verdict.label).", tone: .failure)
        }
        guard let record = resolution.simulateAbsence(driverId: driver.id) else {
            return Outcome(message: "Escenario 2: no se pudo declarar la ausencia.", tone: .failure)
        }
        return Outcome(
            message: "Escenario 2 correcto: ausencia registrada y \(record.opportunities.count) oportunidad(es) en búsqueda automática.",
            tone: .success
        )
    }

    private func runReserveCount(_ units: Int) -> Outcome {
        applyReserve(target: units, maxUse: units, protected: 0)
        approveReserves(units)

        guard let driver = titular() else { return .init(message: "Sin conductores en la estación.", tone: .failure) }
        guard let record = resolution.simulateAbsence(driverId: driver.id) else {
            return Outcome(message: "No se pudo declarar la ausencia.", tone: .failure)
        }
        let extraordinary = record.opportunities.filter { $0.kind == .extraordinary }.count
        let expected = units > 0 ? 1 : 0
        return Outcome(
            message: extraordinary == expected
                ? "Correcto: con \(units) reserva(s) se abrieron \(record.opportunities.count) oportunidad(es), \(extraordinary) extraordinaria(s)."
                : "Falló: se esperaban \(expected) extraordinarias y hubo \(extraordinary).",
            tone: extraordinary == expected ? .success : .failure
        )
    }

    private func runReserveLimits() -> Outcome {
        applyReserve(target: 3, maxUse: 2, protected: 1)
        approveReserves(3)
        let status = resolution.reserveStatus
        return Outcome(
            message: "Escenario 5: \(status.approved) aprobadas, \(status.available) disponibles, el motor puede comprometer \(status.usable) (máx 2, protegida 1).",
            tone: status.usable <= 2 ? .success : .failure
        )
    }

    private func runTwoCandidates() -> Outcome {
        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id),
              let opportunity = record.ordinary ?? record.opportunities.first else {
            return Outcome(message: "No se pudo abrir la oportunidad.", tone: .failure)
        }
        let pool = candidates.filter { $0.id != driver.id }
        guard pool.count >= 2 else {
            return Outcome(message: "El escenario 6 necesita dos conductores elegibles.", tone: .warning)
        }
        let early = ShiftRules.calendar.startOfDay(for: now).addingTimeInterval(7 * 3600)
        let late = early.addingTimeInterval(3600)

        resolution.simulateAcceptance(caseId: record.id, opportunityId: opportunity.id, driverId: pool[1].id, eta: late)
        resolution.simulateAcceptance(caseId: record.id, opportunityId: opportunity.id, driverId: pool[0].id, eta: early)
        resolution.confirmHold(caseId: record.id, opportunityId: opportunity.id)

        let assigned = resolution.resolutionCase(id: record.id)?
            .opportunities.first { $0.id == opportunity.id }?.assignedDriverName
        return Outcome(
            message: assigned == pool[0].name
                ? "Escenario 6 correcto: ganó \(pool[0].name) por ETA 07:00 sobre 08:00."
                : "Escenario 6: quedó asignado \(assigned ?? "nadie"), se esperaba \(pool[0].name).",
            tone: assigned == pool[0].name ? .success : .failure
        )
    }

    private func runConflictingCandidate() -> Outcome {
        let pool = candidates
        guard let blocked = pool.first else {
            return Outcome(message: "Sin conductores para el escenario 7.", tone: .warning)
        }
        var flags = blocked.flags
        flags.documentsValid = false
        coverage.setFlags(flags, for: blocked.id)

        guard let driver = titular(skipping: [blocked.id]),
              let record = resolution.simulateAbsence(driverId: driver.id),
              let opportunity = record.opportunities.first,
              let vacancyId = opportunity.vacancyId,
              let vacancy = coverage.vacancy(id: vacancyId) else {
            return Outcome(message: "No se pudo preparar el escenario 7.", tone: .failure)
        }
        let eligible = coverage.eligibleCandidates(for: vacancy).map(\.driverId)
        return Outcome(
            message: eligible.contains(blocked.id)
                ? "Escenario 7 falló: el candidato con documentación vencida sigue elegible."
                : "Escenario 7 correcto: \(blocked.name) quedó descartado pese a poder llegar antes.",
            tone: eligible.contains(blocked.id) ? .failure : .success
        )
    }

    private func runNoConfirmation() -> Outcome {
        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id),
              let opportunity = record.opportunities.first else {
            return Outcome(message: "No se pudo abrir la oportunidad.", tone: .failure)
        }
        let pool = candidates.filter { $0.id != driver.id }
        guard pool.count >= 2 else {
            return Outcome(message: "El escenario 8 necesita dos candidatos.", tone: .warning)
        }
        let early = ShiftRules.calendar.startOfDay(for: now).addingTimeInterval(7 * 3600)
        resolution.simulateAcceptance(caseId: record.id, opportunityId: opportunity.id, driverId: pool[0].id, eta: early)
        resolution.simulateAcceptance(
            caseId: record.id,
            opportunityId: opportunity.id,
            driverId: pool[1].id,
            eta: early.addingTimeInterval(1800)
        )
        // The first one lets the window pass.
        resolution.simulateHoldExpiry(caseId: record.id, opportunityId: opportunity.id)

        let held = resolution.resolutionCase(id: record.id)?
            .opportunities.first { $0.id == opportunity.id }?.heldByDriverId
        return Outcome(
            message: held == pool[1].id
                ? "Escenario 8 correcto: venció la ventana y la oportunidad pasó sola a \(pool[1].name)."
                : "Escenario 8: la oportunidad quedó en \(held ?? "nadie").",
            tone: held == pool[1].id ? .success : .warning
        )
    }

    private func runConfirmsThenCancels() -> Outcome {
        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id),
              let opportunity = record.opportunities.first,
              let taker = candidates.first(where: { $0.id != driver.id }) else {
            return Outcome(message: "No se pudo preparar el escenario 9.", tone: .warning)
        }
        let eta = ShiftRules.calendar.startOfDay(for: now).addingTimeInterval(7 * 3600)
        resolution.simulateAcceptance(caseId: record.id, opportunityId: opportunity.id, driverId: taker.id, eta: eta)
        resolution.confirmHold(caseId: record.id, opportunityId: opportunity.id)
        resolution.cancelAssignment(
            caseId: record.id,
            opportunityId: opportunity.id,
            reason: "Escenario 9: cancelación posterior"
        )

        let status = resolution.resolutionCase(id: record.id)?
            .opportunities.first { $0.id == opportunity.id }?.status
        let reopened = status == .searching || status == .held || status == .escalated
        return Outcome(
            message: reopened
                ? "Escenario 9 correcto: tras la cancelación la oportunidad quedó en \(status?.label.lowercased() ?? "—")."
                : "Escenario 9 falló: la oportunidad no se reabrió.",
            tone: reopened ? .success : .failure
        )
    }

    private func runTwoOpportunities() -> Outcome {
        applyReserve(target: 1, maxUse: 1, protected: 0)
        approveReserves(1)

        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id) else {
            return Outcome(message: "No se pudo declarar la ausencia.", tone: .failure)
        }
        guard record.opportunities.count == 2 else {
            return Outcome(
                message: "Escenario 10: se abrieron \(record.opportunities.count) oportunidad(es); hacen falta unidad ordinaria y reserva aprobada.",
                tone: .warning
            )
        }
        let pool = candidates.filter { $0.id != driver.id }
        guard pool.count >= 2 else {
            return Outcome(message: "El escenario 10 necesita dos candidatos.", tone: .warning)
        }
        let eta = ShiftRules.calendar.startOfDay(for: now).addingTimeInterval(7 * 3600)

        for (index, opportunity) in record.opportunities.enumerated() {
            resolution.simulateAcceptance(
                caseId: record.id,
                opportunityId: opportunity.id,
                driverId: pool[index].id,
                eta: eta
            )
            resolution.confirmHold(caseId: record.id, opportunityId: opportunity.id)
        }

        let updated = resolution.resolutionCase(id: record.id)
        let assignees = Set(updated?.opportunities.compactMap(\.assignedDriverId) ?? [])
        return Outcome(
            message: assignees.count == 2
                ? "Escenario 10 correcto: dos sustitutos distintos, uno al vehículo ordinario y otro a la reserva."
                : "Escenario 10: se asignaron \(assignees.count) conductor(es) distintos.",
            tone: assignees.count == 2 ? .success : .warning
        )
    }

    private func runTwoAbsences() -> Outcome {
        let drivers = supervision.allDrivers(now: now).prefix(2)
        guard drivers.count == 2 else {
            return Outcome(message: "El escenario 11 necesita dos conductores.", tone: .warning)
        }
        var opened: [AbsenceResolutionCase] = []
        for driver in drivers {
            if let record = resolution.simulateAbsence(driverId: driver.id) { opened.append(record) }
        }
        let ids = Set(opened.map(\.id))
        return Outcome(
            message: ids.count == 2
                ? "Escenario 11 correcto: dos casos independientes, cada uno con su propia búsqueda."
                : "Escenario 11: se abrieron \(ids.count) caso(s).",
            tone: ids.count == 2 ? .success : .failure
        )
    }

    private func runMoreAbsencesThanCapacity() -> Outcome {
        applyReserve(target: 0, maxUse: 0, protected: 0)
        let drivers = supervision.allDrivers(now: now)
        guard !drivers.isEmpty else {
            return Outcome(message: "Sin conductores para el escenario 12.", tone: .warning)
        }
        for driver in drivers { resolution.simulateAbsence(driverId: driver.id) }
        let open = resolution.todayCases
        let escalated = open.filter(\.needsSupervisor).count
        let resolving = open.filter { $0.status == .resolving }.count
        return Outcome(
            message: "Escenario 12: \(open.count) ausencias · \(resolving) en búsqueda · \(escalated) escaladas al supervisor.",
            tone: open.isEmpty ? .failure : .success
        )
    }

    private func runAllReject() -> Outcome {
        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id),
              let opportunity = record.opportunities.first,
              let taker = candidates.first(where: { $0.id != driver.id }) else {
            return Outcome(message: "No se pudo preparar el escenario 13.", tone: .warning)
        }
        let eta = ShiftRules.calendar.startOfDay(for: now).addingTimeInterval(7 * 3600)
        resolution.simulateAcceptance(caseId: record.id, opportunityId: opportunity.id, driverId: taker.id, eta: eta)
        resolution.simulateHoldExpiry(caseId: record.id, opportunityId: opportunity.id)

        let updated = resolution.resolutionCase(id: record.id)
        let escalated = updated?.needsSupervisor ?? false
        return Outcome(
            message: escalated
                ? "Escenario 13 correcto: sin candidatos restantes, el caso escaló al supervisor."
                : "Escenario 13: el caso quedó en \(updated?.status.label.lowercased() ?? "—").",
            tone: escalated ? .success : .warning
        )
    }

    private func runLateEta() -> Outcome {
        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id),
              let opportunity = record.ordinary,
              let taker = candidates.first(where: { $0.id != driver.id }) else {
            return Outcome(message: "El escenario 14 necesita una oportunidad ordinaria.", tone: .warning)
        }
        // An arrival so late that the useful window falls under the configured minimum.
        let lateEta = opportunity.returnBy.addingTimeInterval(TimeInterval(-(resolution.policy.minimumProductiveMinutes - 30) * 60))
        let accepted = resolution.simulateAcceptance(
            caseId: record.id,
            opportunityId: opportunity.id,
            driverId: taker.id,
            eta: lateEta
        )
        return Outcome(
            message: accepted
                ? "Escenario 14 falló: se aceptó una ETA que no alcanza el tiempo productivo mínimo."
                : "Escenario 14 correcto: rechazada por debajo de los \(resolution.policy.minimumProductiveMinutes) min mínimos.",
            tone: accepted ? .failure : .success
        )
    }

    private func runWork(minutes: Int, earnings: Int, label: String) -> Outcome {
        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id),
              let opportunity = record.opportunities.first,
              let taker = candidates.first(where: { $0.id != driver.id }) else {
            return Outcome(message: "No se pudo preparar el escenario.", tone: .warning)
        }
        let eta = now
        resolution.simulateAcceptance(caseId: record.id, opportunityId: opportunity.id, driverId: taker.id, eta: eta)
        resolution.confirmHold(caseId: record.id, opportunityId: opportunity.id)
        resolution.simulateWork(
            caseId: record.id,
            opportunityId: opportunity.id,
            minutes: minutes,
            earningsMxn: earnings
        )

        guard let entry = CoverageEarningLedger.entries(driverId: taker.id).first else {
            return Outcome(message: "\(label): no se registró el pago en el corte semanal.", tone: .failure)
        }
        let attainment = Int((entry.attainment * 100).rounded())
        return Outcome(
            message: "\(label): \(entry.effectiveMinutes) min × \(String(format: "%.4f", entry.ratePerMinuteMxn)) = \(Fmt.mxn(entry.payMxn)) · meta \(Fmt.mxn(entry.proportionalGoalMxn)) · cumplimiento \(attainment)%.",
            tone: .success
        )
    }

    private func runReserveTaken() -> Outcome {
        applyReserve(target: 1, maxUse: 1, protected: 0)
        approveReserves(1)
        let before = resolution.reserveStatus.available

        guard let driver = titular(), resolution.simulateAbsence(driverId: driver.id) != nil else {
            return Outcome(message: "No se pudo declarar la ausencia.", tone: .failure)
        }
        let after = resolution.reserveStatus.available
        return Outcome(
            message: after < before
                ? "Escenario 19 correcto: la reserva pasó de \(before) a \(after) disponibles en cuanto se comprometió."
                : "Escenario 19: las reservas disponibles no cambiaron (\(before) → \(after)).",
            tone: after < before ? .success : .warning
        )
    }

    private func runUnresolvable() -> Outcome {
        // Nobody eligible and no reserve: the engine has nothing valid to build.
        applyReserve(target: 0, maxUse: 0, protected: 0)
        for profile in candidates {
            var flags = profile.flags
            flags.documentsValid = false
            coverage.setFlags(flags, for: profile.id)
        }
        guard let driver = titular(), let record = resolution.simulateAbsence(driverId: driver.id) else {
            return Outcome(message: "No se pudo declarar la ausencia.", tone: .failure)
        }
        let escalated = resolution.resolutionCase(id: record.id)?.needsSupervisor ?? false
        return Outcome(
            message: escalated
                ? "Escenario 20 correcto: sin solución válida, el caso pide INTERVENCIÓN REQUERIDA."
                : "Escenario 20: el caso quedó en \(record.status.label.lowercased()).",
            tone: escalated ? .success : .warning
        )
    }

    // MARK: - Helpers

    private func applyReserve(target: Int, maxUse: Int, protected: Int) {
        AbsenceResolutionConfig.setReservePolicy(
            ReservePolicy(targetUnits: target, maxInExtraordinaryUse: maxUse, minimumProtected: protected),
            stationId: station.id
        )
    }

    /// Approves exactly as many units of the station as the scenario needs.
    private func approveReserves(_ count: Int) {
        let units = supervision.vehicles.filter { $0.state == .available && $0.assignedDriverId == nil }
        for unit in units { ReserveFleetRegistry.revoke(vehicleId: unit.id) }
        for unit in units.prefix(count) { ReserveFleetRegistry.approve(vehicleId: unit.id) }
    }
}
