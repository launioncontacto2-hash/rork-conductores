import SwiftUI

/// Financial workspace for a driver authenticated by Supabase. Every amount shown here
/// comes from RLS-protected rows and every mutation crosses an idempotent RPC.
struct BackendDriverFinanceView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let presentsCloseButton: Bool

    @State private var snapshot: SupabaseFinancialService.DriverSnapshot?
    @State private var isLoading = false
    @State private var isSavingIncome = false
    @State private var isSavingAccount = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var historyWindow: HistoryWindow = .month

    @State private var source: IncomeSource = .uber
    @State private var amount = ""
    @State private var trips = ""
    @State private var externalReference = ""
    @State private var incomeNote = ""

    @State private var showsBankForm = false
    @State private var bankName = ""
    @State private var clabe = ""
    @State private var productNotice: FinanceProductNotice?

    @FocusState private var focusedField: Field?

    init(presentsCloseButton: Bool = false) {
        self.presentsCloseButton = presentsCloseButton
    }

    /// Every editable field of this screen. The numeric keypads carry no return key, so
    /// without an explicit way out the keyboard stays up and covers the tab bar.
    private enum Field: Hashable {
        case amount
        case trips
        case externalReference
        case incomeNote
        case bankName
        case clabe
    }

    private enum IncomeSource: String, CaseIterable, Identifiable {
        case uber
        case didi
        case other

        var id: String { rawValue }
        var label: String {
            switch self {
            case .uber: "Uber"
            case .didi: "DiDi"
            case .other: "Otro"
            }
        }
    }

    private var backendShiftId: UUID? {
        guard store.activeShift?.origin == .backend else { return nil }
        return store.activeShift.flatMap { UUID(uuidString: $0.id) }
    }

    private var parsedAmount: Int { Int(amount.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var parsedTrips: Int { Int(trips.trimmingCharacters(in: .whitespaces)) ?? 0 }
    /// PostgreSQL validates CLABE with `[0-9]`, so normalize to the same ASCII alphabet
    /// instead of accepting other Unicode numeral characters that the RPC will reject.
    private var clabeDigits: String { clabe.filter { $0 >= "0" && $0 <= "9" } }
    private var hasPendingAccount: Bool {
        snapshot?.bankAccounts.contains { $0.status == "pending" } == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        header
                        identityBanner

                        if let successMessage {
                            NoticeBanner(
                                symbol: "checkmark.seal.fill",
                                title: "Operación confirmada",
                                message: successMessage,
                                tone: .volt
                            )
                        }

                        if let errorMessage {
                            NoticeBanner(
                                symbol: "exclamationmark.triangle.fill",
                                title: "No se pudo completar",
                                message: errorMessage,
                                tone: .danger
                            )
                        }

                        if isLoading, snapshot == nil {
                            ProgressView("Consultando el sistema financiero…")
                                .frame(maxWidth: .infinity)
                                .padding(28)
                                .panel()
                        } else if let snapshot {
                            summaryCard(snapshot)
                            incomeCaptureCard(snapshot)
                            bankCard(snapshot)
                            settlementsCard(snapshot)
                            incomeHistoryCard(snapshot)
                            operationalProductsCard(snapshot)
                        } else {
                            emptyCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await refresh() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cerrar") { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { focusedField = nil }
                        .font(.system(.body, weight: .bold))
                }
            }
            .task { await refresh() }
            .sheet(item: $productNotice) { notice in
                FinanceProductDetailView(notice: notice)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CapsLabel(text: "Cartera · Supabase")
                Text("Finanzas reales")
                    .font(.system(.title2, weight: .black))
            }
            Spacer(minLength: 0)
            if !presentsCloseButton {
                DemoClockButton()
                SessionMenuButton()
            }
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(.body, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(Palette.surfaceRaised, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("Actualizar finanzas")
        }
    }

    private var identityBanner: some View {
        NoticeBanner(
            symbol: "lock.shield.fill",
            title: "Cuenta financiera protegida",
            message: "Ingresos, cuenta bancaria y liquidaciones se leen directamente de TEST. La app no calcula saldos ni simula transferencias para esta sesión.",
            tone: .info
        )
    }

    private func summaryCard(_ value: SupabaseFinancialService.DriverSnapshot) -> some View {
        let income = value.incomes.reduce(0) { $0 + $1.amount_mxn }
        let charges = value.cashCharges.reduce(0) { $0 + $1.amount_mxn }
        let payable = value.settlements.filter { $0.status != "cancelled" }.reduce(0) { $0 + $1.net_mxn }

        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Resumen", subtitle: "Información confirmada por el servidor")
            HStack(spacing: 8) {
                metricTile("Ingresos", Fmt.mxn(income), Palette.volt)
                metricTile("Cargos", Fmt.mxn(charges), Palette.amber)
                metricTile("Liquidado", Fmt.mxn(payable), Palette.info)
            }
        }
        .padding(16)
        .panel()
    }

    private func metricTile(_ label: String, _ value: String, _ tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black))
                .tracking(0.7)
                .foregroundStyle(Palette.textMuted)
            Text(value)
                .font(.system(.footnote, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tone)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 13)
    }

    private func incomeCaptureCard(_ value: SupabaseFinancialService.DriverSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Registrar ingreso",
                subtitle: backendShiftId == nil
                    ? "Primero debes iniciar un turno"
                    : "Se asociará al turno abierto"
            )

            Picker("Plataforma", selection: $source) {
                ForEach(IncomeSource.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                TextField("Monto MXN", text: $amount)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .amount)
                TextField("Viajes", text: $trips)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .trips)
                    .frame(maxWidth: 100)
            }
            .textFieldStyle(.plain)
            .padding(13)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))

            TextField("Referencia externa (opcional)", text: $externalReference)
                .textInputAutocapitalization(.characters)
                .focused($focusedField, equals: .externalReference)
                .padding(13)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))

            TextField("Nota (opcional)", text: $incomeNote, axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedField, equals: .incomeNote)
                .padding(13)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))

            BigButton(
                title: isSavingIncome ? "Registrando…" : "Confirmar ingreso",
                symbol: "banknote.fill",
                isEnabled: backendShiftId != nil && parsedAmount > 0 && parsedTrips >= 0 && !isSavingIncome
            ) {
                Task { await registerIncome() }
            }

            Text("La foto de comprobante se conectará con Storage en 15H. Este registro admite únicamente la referencia externa y la nota; no guarda archivos en el teléfono.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    private func bankCard(_ value: SupabaseFinancialService.DriverSnapshot) -> some View {
        let current = value.currentBankAccount
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Cuenta bancaria",
                subtitle: current == nil ? "Sin cuenta registrada" : "Solo se muestran los últimos cuatro dígitos"
            )

            if let current {
                DetailRow(label: "Banco", value: current.bank_name)
                DetailRow(label: "CLABE", value: "•••• •••• •••• ••\(current.clabe_last4)")
                DetailRow(label: "Versión", value: "\(current.version)")
                DetailRow(
                    label: "Estado",
                    value: accountStatus(current.status),
                    tone: statusTone(current.status)
                )
            }

            if hasPendingAccount {
                NoticeBanner(
                    symbol: "person.badge.clock.fill",
                    title: "Pendiente de segundo actor",
                    message: "Gerencia debe aprobar esta cuenta antes de autorizar una transferencia.",
                    tone: .amber
                )
            } else if showsBankForm || current == nil {
                TextField("Banco", text: $bankName)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .bankName)
                    .padding(13)
                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))
                SecureField("CLABE de 18 dígitos", text: $clabe)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .clabe)
                    .padding(13)
                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))

                BigButton(
                    title: isSavingAccount ? "Enviando…" : "Enviar para aprobación",
                    symbol: "building.columns.fill",
                    isEnabled: !bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && clabeDigits.count == 18
                        && !isSavingAccount
                ) {
                    Task { await setBankAccount() }
                }
            } else {
                BigButton(title: "Solicitar cambio de cuenta", symbol: "arrow.triangle.2.circlepath", tone: .outline) {
                    showsBankForm = true
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func settlementsCard(_ value: SupabaseFinancialService.DriverSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Liquidaciones", subtitle: "Calculadas y cerradas en servidor")
            if value.settlements.isEmpty {
                Text("Todavía no hay periodos cerrados.")
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(value.settlements) { settlement in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(settlement.folio)
                                .font(.system(.footnote, weight: .black))
                            Spacer()
                            Text(Fmt.mxn(settlement.net_mxn))
                                .font(.system(.footnote, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(Palette.volt)
                        }
                        Text("\(settlement.period_start) — \(settlement.period_end)")
                            .font(.caption2)
                            .foregroundStyle(Palette.textMuted)
                        HStack {
                            Text("Ingresos \(Fmt.mxn(settlement.gross_income_mxn)) · cargos \(Fmt.mxn(settlement.cash_charges_mxn))")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                            Spacer()
                            Text(settlementStatus(settlement.status))
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(statusTone(settlement.status))
                        }
                        if let transfer = value.transfers.first(where: { $0.settlement_id == settlement.id }) {
                            Text("\(transfer.folio) · \(settlementStatus(transfer.status))")
                                .font(.caption2)
                                .foregroundStyle(Palette.info)
                        }
                    }
                    .padding(12)
                    .panelFlat(cornerRadius: 14)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func incomeHistoryCard(_ value: SupabaseFinancialService.DriverSnapshot) -> some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -historyWindow.days, to: AppClock.now()) ?? .distantPast
        let visibleIncomes = value.incomes.filter { $0.reported_at >= cutoff }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SupSectionHeader(title: "Historial", subtitle: "Movimientos append-only del servidor")
                Spacer()
                Picker("Periodo", selection: $historyWindow) {
                    ForEach(HistoryWindow.allCases) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 138)
            }
            if visibleIncomes.isEmpty {
                Text("No hay ingresos registrados en este periodo.")
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(visibleIncomes.prefix(20)) { income in
                    HStack(spacing: 10) {
                        Image(systemName: income.reversal_of == nil ? "plus.circle.fill" : "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(income.amount_mxn >= 0 ? Palette.volt : Palette.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(income.folio) · \(sourceLabel(income.source))")
                                .font(.system(.footnote, weight: .bold))
                            Text("\(Fmt.dateShort(income.reported_at)) · \(income.trips) viajes")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer()
                        Text(Fmt.mxn(income.amount_mxn))
                            .font(.system(.footnote, weight: .black))
                            .monospacedDigit()
                    }
                    .padding(11)
                    .panelFlat(cornerRadius: 13)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private enum HistoryWindow: String, CaseIterable, Identifiable {
        case month
        case week

        var id: String { rawValue }
        var label: String { self == .month ? "Mes" : "Semana" }
        var days: Int { self == .month ? 30 : 7 }
    }

    /// Makes the remaining financial product boundaries explicit without routing a
    /// backend-authenticated driver into the legacy Wallet/Credit demo state.
    private func operationalProductsCard(_ value: SupabaseFinancialService.DriverSnapshot) -> some View {
        let income = value.incomes.reduce(0) { $0 + $1.amount_mxn }
        let charges = value.cashCharges.reduce(0) { $0 + $1.amount_mxn }

        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Productos y periodos", subtitle: "Estado de contratos TEST")
            DetailRow(label: "Resumen mes", value: "\(value.incomes.count) ingresos · \(Fmt.mxn(income))", tone: Palette.info)
            DetailRow(label: "Resumen semana", value: "\(value.cashCharges.count) cargos · \(Fmt.mxn(charges))", tone: Palette.amber)
            productRow(title: "Transferir fondos a mi cuenta", message: "Disponible solo cuando exista una liquidación transferible en el contrato remoto", symbol: "arrow.up.right.square") { productNotice = .transfer }
            productRow(title: "Bonos", message: "Se consultan desde Metas; cálculo financiero pendiente", symbol: "rosette") { productNotice = .bonuses }
            productRow(title: "Crédito automotriz", message: "No disponible para esta sesión TEST", symbol: "car.side.and.exclamationmark") { productNotice = .credit }
            productRow(title: "Efectivo / Depositar a DORI", message: "Contrato de depósito pendiente; no se simula", symbol: "banknote") { productNotice = .cash }
        }
        .padding(16)
        .panel()
    }

    enum FinanceProductNotice: String, Identifiable {
        case transfer, bonuses, credit, cash
        var id: String { rawValue }
        var title: String {
            switch self {
            case .transfer: "Transferir fondos"
            case .bonuses: "Bonos"
            case .credit: "Crédito automotriz"
            case .cash: "Efectivo"
            }
        }
        var message: String {
            switch self {
            case .transfer: "La transferencia se habilitará cuando el servidor entregue una liquidación disponible y una cuenta bancaria aprobada. No se simula ningún envío local."
            case .bonuses: "La evaluación de bonos vive en Metas. Su cálculo financiero se habilitará cuando exista el contrato remoto correspondiente."
            case .credit: "El crédito y el abono a capital no están disponibles para esta sesión TEST. No se muestra una simulación ni se crea una solicitud."
            case .cash: "Depositar a DORI requiere el contrato de evidencia y almacenamiento. Esta versión no simula depósitos."
            }
        }
    }

    private func productRow(title: String, message: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            statusRow(title: title, message: message, symbol: symbol)
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.trailing, 12)
                }
        }
        .buttonStyle(.plain)
    }

    private func statusRow(title: String, message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.textMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: .bold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .panelFlat(cornerRadius: 13)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(Palette.amber)
            Text("No se pudo leer la cartera")
                .font(.system(.headline, weight: .black))
            Text("Actualiza para volver a consultar Supabase.")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .panel()
    }

    @MainActor
    private func refresh() async {
        guard let principal = store.currentPrincipal else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await SupabaseFinancialService.loadDriverSnapshot(profileId: principal.profileId)
            snapshot = loaded
            store.adoptBackendFinancialSnapshot(loaded)
            errorMessage = nil
        } catch {
            errorMessage = SupabaseFinancialService.userMessage(for: error)
        }
    }

    @MainActor
    private func registerIncome() async {
        // Released before the guard, so tapping the button always puts the keyboard away
        // — including on the paths that refuse the write and return early.
        focusedField = nil
        guard let shiftId = backendShiftId, parsedAmount > 0, parsedTrips >= 0 else { return }
        isSavingIncome = true
        successMessage = nil
        defer { isSavingIncome = false }
        do {
            let row = try await SupabaseFinancialService.registerIncome(
                shiftId: shiftId,
                source: source.rawValue,
                amountMxn: parsedAmount,
                trips: parsedTrips,
                externalReference: externalReference.nilIfBlank,
                note: incomeNote.nilIfBlank,
                idempotencyKey: "ios-income-\(UUID().uuidString.lowercased())"
            )
            amount = ""
            trips = ""
            externalReference = ""
            incomeNote = ""
            successMessage = "\(row.folio) quedó registrado por \(Fmt.mxn(row.amount_mxn))."
            await refresh()
        } catch {
            errorMessage = SupabaseFinancialService.userMessage(for: error)
        }
    }

    @MainActor
    private func setBankAccount() async {
        focusedField = nil
        guard let driverProfileId = snapshot?.driverProfileId, clabeDigits.count == 18 else { return }
        isSavingAccount = true
        successMessage = nil
        defer { isSavingAccount = false }
        do {
            let row = try await SupabaseFinancialService.setBankAccount(
                driverProfileId: driverProfileId,
                bankName: bankName.trimmingCharacters(in: .whitespacesAndNewlines),
                clabe: clabeDigits,
                idempotencyKey: "ios-bank-\(UUID().uuidString.lowercased())"
            )
            bankName = ""
            clabe = ""
            showsBankForm = false
            successMessage = "La cuenta terminada en \(row.clabe_last4) quedó pendiente de aprobación."
            await refresh()
        } catch {
            clabe = ""
            errorMessage = SupabaseFinancialService.userMessage(for: error)
        }
    }

    private func sourceLabel(_ value: String) -> String {
        switch value {
        case "uber": "Uber"
        case "didi": "DiDi"
        case "cash": "Efectivo"
        default: "Otro"
        }
    }

    private func accountStatus(_ value: String) -> String {
        switch value {
        case "active": "Activa"
        case "pending": "Pendiente"
        case "rejected": "Rechazada"
        case "superseded": "Reemplazada"
        default: value.capitalized
        }
    }

    private func settlementStatus(_ value: String) -> String {
        switch value {
        case "available": "Disponible"
        case "authorized": "Autorizada"
        case "processing": "Procesando"
        case "transferred": "Transferida"
        case "completed": "Completada"
        case "failed": "Fallida"
        case "cancelled": "Cancelada"
        default: value.capitalized
        }
    }

    private func statusTone(_ value: String) -> Color {
        switch value {
        case "active", "completed", "transferred": Palette.volt
        case "pending", "processing", "authorized": Palette.amber
        case "rejected", "failed", "cancelled": Palette.danger
        default: Palette.info
        }
    }
}

/// Second-layer product surfaces for the backend wallet. These are intentionally
/// navigable even while a remote contract is pending, but they never fabricate a
/// balance, approval, transfer, deposit or credit payment.
private struct FinanceProductDetailView: View {
    let notice: BackendDriverFinanceView.FinanceProductNotice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.info)
                    Text(notice.title)
                        .font(.system(.title2, weight: .black))
                    Text(notice.message)
                        .foregroundStyle(Palette.textMuted)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows, id: \.title) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: row.symbol)
                                    .foregroundStyle(row.isReady ? Palette.volt : Palette.neutral)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.system(.footnote, weight: .bold))
                                    Text(row.detail)
                                        .font(.caption)
                                        .foregroundStyle(Palette.textMuted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .panelFlat(cornerRadius: 13)
                        }
                    }
                    Button("Cerrar") { dismiss() }
                        .buttonStyle(.bordered)
                }
                .padding(24)
            }
            .background(StationBackground())
            .navigationTitle(notice.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var icon: String {
        switch notice {
        case .transfer: "arrow.up.right.square"
        case .bonuses: "rosette"
        case .credit: "car.side.and.exclamationmark"
        case .cash: "banknote"
        }
    }

    private struct Row {
        let title: String
        let detail: String
        let symbol: String
        let isReady: Bool
    }

    private var rows: [Row] {
        switch notice {
        case .transfer:
            return [
                Row(title: "Liquidación", detail: "Solo se puede transferir una liquidación marcada como disponible por Supabase.", symbol: "checkmark.circle", isReady: true),
                Row(title: "Cuenta destino", detail: "Requiere una cuenta bancaria aprobada para esta identidad.", symbol: "building.columns", isReady: false),
                Row(title: "Enviar", detail: "El contrato remoto de transferencia no está habilitado en esta sesión TEST.", symbol: "lock.circle", isReady: false)
            ]
        case .bonuses:
            return [
                Row(title: "Evaluación", detail: "Consulta el detalle operativo en la pestaña Bonos.", symbol: "checkmark.circle", isReady: true),
                Row(title: "Cálculo financiero", detail: "Pendiente de contrato remoto; no se muestran importes inventados.", symbol: "lock.circle", isReady: false),
                Row(title: "Recuperación", detail: "Solo se ofrece para bonos realmente perdidos según la regla vigente.", symbol: "arrow.counterclockwise.circle", isReady: true)
            ]
        case .credit:
            return [
                Row(title: "Contrato", detail: "No disponible para esta sesión TEST.", symbol: "lock.circle", isReady: false),
                Row(title: "Abono a capital", detail: "No se simula ni se registra ningún pago local.", symbol: "nosign", isReady: false),
                Row(title: "Siguiente paso", detail: "Requiere contrato remoto de crédito y autorización del backend.", symbol: "arrow.right.circle", isReady: false)
            ]
        case .cash:
            return [
                Row(title: "Efectivo recibido", detail: "Se muestra únicamente cuando existe un movimiento real en Supabase.", symbol: "banknote", isReady: true),
                Row(title: "Evidencia", detail: "El depósito requiere comprobante y almacenamiento remoto.", symbol: "photo", isReady: false),
                Row(title: "Depositar a DORI", detail: "Contrato pendiente; el botón de envío permanece deshabilitado.", symbol: "lock.circle", isReady: false)
            ]
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

#Preview {
    BackendDriverFinanceView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
