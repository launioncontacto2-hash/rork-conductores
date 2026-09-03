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

    @State private var source: IncomeSource = .uber
    @State private var amount = ""
    @State private var trips = ""
    @State private var externalReference = ""
    @State private var incomeNote = ""

    @State private var showsBankForm = false
    @State private var bankName = ""
    @State private var clabe = ""

    init(presentsCloseButton: Bool = false) {
        self.presentsCloseButton = presentsCloseButton
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
                        } else {
                            emptyCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
                .refreshable { await refresh() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cerrar") { dismiss() }
                    }
                }
            }
            .task { await refresh() }
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
                TextField("Viajes", text: $trips)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 100)
            }
            .textFieldStyle(.plain)
            .padding(13)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))

            TextField("Referencia externa (opcional)", text: $externalReference)
                .textInputAutocapitalization(.characters)
                .padding(13)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))

            TextField("Nota (opcional)", text: $incomeNote, axis: .vertical)
                .lineLimit(2...4)
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
                    .padding(13)
                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))
                SecureField("CLABE de 18 dígitos", text: $clabe)
                    .keyboardType(.numberPad)
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
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Ingresos", subtitle: "Últimos movimientos append-only")
            if value.incomes.isEmpty {
                Text("No hay ingresos registrados para este conductor.")
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(value.incomes.prefix(20)) { income in
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
