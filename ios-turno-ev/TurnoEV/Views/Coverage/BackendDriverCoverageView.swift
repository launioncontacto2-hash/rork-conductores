import Observation
import SwiftUI

/// Real 15F workspace for a driver proved by Supabase. It deliberately stays separate
/// from `CoverageStore`, whose rich in-memory workflow remains the demo/laboratory model.
@MainActor
@Observable
private final class BackendDriverCoverageModel {
    let principal: SessionPrincipal

    var absences: [SupabaseCoverageService.AbsenceRow] = []
    var vacancies: [SupabaseCoverageService.VacancyRow] = []
    var claims: [SupabaseCoverageService.ClaimRow] = []
    var requestDate = Date()
    var requestKind: AbsenceKind = .scheduled
    var reason = ""
    var comments = ""
    var isLoading = false
    var isRequesting = false
    var claimingVacancyId: UUID?
    var errorMessage: String?
    var successMessage: String?
    private var preparedDate = false

    init(principal: SessionPrincipal) {
        self.principal = principal
    }

    var slot: ShiftSlot { principal.shiftSlot ?? .morning }

    var openAbsences: [SupabaseCoverageService.AbsenceRow] {
        absences.filter { !["approved", "rejected", "cancelled", "uncovered"].contains($0.status) }
    }

    var availableVacancies: [SupabaseCoverageService.VacancyRow] {
        vacancies.filter { $0.status == "searching" }
    }

    var myGuards: [SupabaseCoverageService.VacancyRow] {
        let ids = Set(claims.map(\.vacancy_id))
        return vacancies.filter { ids.contains($0.id) && $0.status != "searching" }
    }

    var canRequest: Bool {
        !isRequesting && reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    func prepareDate(reference: Date) {
        guard !preparedDate else { return }
        preparedDate = true
        requestDate = Self.nextDate(after: reference, group: principal.shiftGroup ?? .weekday)
    }

    func load() async {
        guard !isLoading else { return }
        guard let stationId = principal.stationId else {
            errorMessage = "La sesión del conductor no contiene estación."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await SupabaseDriverDeviceService.heartbeat()
            let snapshot = try await SupabaseCoverageService.loadDriverSnapshot(
                stationId: stationId
            )
            absences = snapshot.absences
            vacancies = snapshot.vacancies
            claims = snapshot.claims
        } catch {
            errorMessage = SupabaseCoverageService.userMessage(for: error)
        }
    }

    func requestAbsence() async {
        guard canRequest else { return }
        isRequesting = true
        errorMessage = nil
        successMessage = nil
        defer { isRequesting = false }

        do {
            let row = try await SupabaseCoverageService.requestAbsence(
                operatingDate: Self.dateOnly.string(from: requestDate),
                shiftSlot: slot,
                kind: requestKind,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                comments: comments.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: "ios-absence-\(UUID().uuidString.lowercased())"
            )
            successMessage = "\(row.folio) fue enviada. La ausencia aún no está autorizada."
            reason = ""
            comments = ""
            await load()
        } catch {
            errorMessage = SupabaseCoverageService.userMessage(for: error)
        }
    }

    func claim(_ vacancy: SupabaseCoverageService.VacancyRow) async {
        guard claimingVacancyId == nil else { return }
        claimingVacancyId = vacancy.id
        errorMessage = nil
        successMessage = nil
        defer { claimingVacancyId = nil }

        do {
            _ = try await SupabaseCoverageService.claim(
                vacancyId: vacancy.id,
                idempotencyKey: "ios-guard-\(UUID().uuidString.lowercased())"
            )
            successMessage = "Ganaste \(vacancy.folio). Queda pendiente de aprobación."
            await load()
        } catch {
            errorMessage = SupabaseCoverageService.userMessage(for: error)
            await load()
        }
    }

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Mexico_City")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func nextDate(after reference: Date, group: ShiftGroup) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City") ?? .current
        let start = calendar.startOfDay(for: reference)
        for offset in 1...14 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: candidate)
            let isWeekday = (2...6).contains(weekday)
            if (group == .weekday && isWeekday) || (group == .weekend && !isWeekday) {
                return candidate
            }
        }
        return start
    }
}

struct BackendDriverCoverageView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BackendDriverCoverageModel

    init(principal: SessionPrincipal) {
        _model = State(initialValue: BackendDriverCoverageModel(principal: principal))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityCard
                    statusCard
                    availableGuardsCard
                    myGuardsCard
                    absenceForm
                    myAbsencesCard
                }
                .padding(18)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Turnos y guardias")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DemoClockButton()
                    SessionMenuButton()
                }
            }
            .refreshable { await model.load() }
            .task {
                model.prepareDate(reference: fleet.now)
                await model.load()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.load() }
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COBERTURA TEST")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.volt)
            Text(model.principal.name)
                .font(.title3.weight(.bold))
            Text("\(model.principal.stationName ?? "Estación") · \(model.principal.stationCode ?? "—")")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    @ViewBuilder
    private var statusCard: some View {
        if model.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Sincronizando cobertura con la estación…")
            }
            .font(.footnote)
            .foregroundStyle(Palette.textMuted)
        } else if let error = model.errorMessage {
            NoticeBanner(
                symbol: "exclamationmark.triangle.fill",
                title: "No se completó la operación",
                message: error,
                tone: .danger
            )
        } else if let success = model.successMessage {
            NoticeBanner(
                symbol: "checkmark.seal.fill",
                title: "Operación registrada",
                message: success,
                tone: .volt
            )
        }
    }

    private var availableGuardsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GUARDIAS DISPONIBLES")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text("\(model.availableVacancies.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(model.availableVacancies.isEmpty ? Palette.textMuted : Palette.amber)
            }

            if model.availableVacancies.isEmpty {
                Text("No hay guardias elegibles para tu bloque en este momento.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.availableVacancies) { vacancy in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(vacancy.folio)
                                .font(.headline)
                            Spacer()
                            if vacancy.is_critical {
                                Text("URGENTE")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(Palette.amber)
                            }
                        }
                        Text("\(vacancy.operating_date) · \(slotLabel(vacancy.shift_slot))")
                            .font(.subheadline.weight(.semibold))
                        Text("\(vacancy.reason) · bono \(Fmt.mxn(vacancy.bonus_mxn))")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)

                        BigButton(
                            title: model.claimingVacancyId == vacancy.id
                                ? "Intentando reservar…" : "Tomar guardia",
                            symbol: "hand.raised.fill",
                            isEnabled: model.claimingVacancyId == nil
                        ) {
                            Task { await model.claim(vacancy) }
                        }
                    }
                    .padding(14)
                    .panelFlat()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    @ViewBuilder
    private var myGuardsCard: some View {
        if !model.myGuards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("MIS GUARDIAS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.textMuted)
                ForEach(model.myGuards) { vacancy in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vacancy.folio)
                                .font(.subheadline.weight(.bold))
                            Text("\(vacancy.operating_date) · \(slotLabel(vacancy.shift_slot))")
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer()
                        Text(vacancy.status == "reserved" ? "POR APROBAR" : vacancy.status.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(vacancy.status == "confirmed" ? Palette.volt : Palette.amber)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .panel()
        }
    }

    private var absenceForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SOLICITAR AUSENCIA")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)

            DatePicker("Fecha", selection: $model.requestDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(Palette.volt)

            HStack {
                Text("Turno")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(model.slot.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.volt)
            }

            Picker("Tipo", selection: $model.requestKind) {
                ForEach(AbsenceKind.allCases) { kind in
                    Text(kind.shortLabel).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField("Motivo", text: $model.reason, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .panelFlat()

            TextField("Comentarios opcionales", text: $model.comments, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .panelFlat()

            BigButton(
                title: model.isRequesting ? "Enviando…" : "Enviar solicitud",
                symbol: "paperplane.fill",
                isEnabled: model.canRequest
            ) {
                Task { await model.requestAbsence() }
            }

            Text("Enviar la solicitud abre una vacante, pero no autoriza tu ausencia. Supervisión decide por separado.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    private var myAbsencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIS SOLICITUDES")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)

            if model.absences.isEmpty {
                Text("Todavía no has enviado ausencias.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.absences.prefix(8)) { absence in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(absence.folio)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text(absenceStatus(absence.status))
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(absence.status == "approved" ? Palette.volt : Palette.amber)
                        }
                        Text("\(absence.operating_date) · \(slotLabel(absence.shift_slot)) · \(absence.kind.capitalized)")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                        Text(absence.reason)
                            .font(.footnote)
                    }
                    .padding(12)
                    .panelFlat()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func slotLabel(_ raw: String) -> String {
        ShiftSlot(rawValue: raw)?.label ?? raw.capitalized
    }

    private func absenceStatus(_ raw: String) -> String {
        switch raw {
        case "searching": "BUSCANDO"
        case "covered": "CUBIERTA"
        case "awaiting_authorization": "POR AUTORIZAR"
        case "approved": "APROBADA"
        case "rejected": "RECHAZADA"
        case "cancelled": "CANCELADA"
        case "uncovered": "SIN COBERTURA"
        default: raw.uppercased()
        }
    }
}
