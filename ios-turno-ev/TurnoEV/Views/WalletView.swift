import SwiftUI

/// Cartera del conductor: what the week produced, what was withheld and what is really
/// available. Payment is weekly; the transfer flow is simulated end to end.
struct WalletView: View {
    @Environment(FleetStore.self) private var store

    @State private var wallet: WalletStore?
    @State private var office: StationOfficeStore?
    @State private var showsBreakdown: Bool = false
    @State private var showsBankRequest: Bool = false
    @State private var showsCredit: Bool = false
    @State private var reviewNote: String = ""
    @State private var isReviewing: Bool = false
    @State private var transferError: String?

    /// Whether the dispersion flow on this device still stands for anything.
    ///
    /// The pipeline is a timer, not a bank. For a proved identity it is not shown as a
    /// slower version of the truth — it is not shown at all.
    private var canSimulateTransfer: Bool { store.canSimulateFinancialState }

    /// The week the wallet is standing in.
    ///
    /// `.day`, because a settlement is bounded by `weekStart(for:)`: on the rollover the
    /// open week closes and a new one takes the top of the list. `ClockAnchor` rather than
    /// `TimeScope` because the settlement feeds the whole screen — the balance, the status,
    /// the history and the two sheets — and a sheet builder cannot be handed a scope's
    /// closure argument.
    ///
    /// This was the last visual reader still taking its time from `FleetStore.now`.
    @State private var dayAnchor: Date = AppClock.now()

    var body: some View {
        ZStack {
            StationBackground()
            ClockAnchor(.day, date: $dayAnchor)

            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let wallet, let settlement = wallet.currentSettlement(now: dayAnchor) {
                        balanceCard(settlement, wallet: wallet)
                        statusCard(settlement)
                        creditCard
                        bankCard
                        historyCard(wallet)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            if wallet == nil { wallet = WalletStore(fleet: store) }
            if office == nil, let station = StaffDirectory.station(id: store.driver.stationId) {
                let created = StationOfficeStore(station: station, fleet: store, actor: store.currentAccount)
                created.refresh()
                office = created
            }
        }
        .sheet(isPresented: $showsBreakdown) {
            if let wallet, let settlement = wallet.currentSettlement(now: dayAnchor) {
                SettlementBreakdownView(settlement: settlement)
            }
        }
        .sheet(isPresented: $showsCredit) {
            CreditView()
        }
        .sheet(isPresented: $showsBankRequest) {
            if let office {
                BankChangeRequestView(office: office, driver: store.driver)
            }
        }
        .alert(
            "Transferencia no disponible",
            isPresented: Binding(
                get: { transferError != nil },
                set: { if !$0 { transferError = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) { transferError = nil }
        } message: {
            Text(transferError ?? "")
        }
        .alert("Solicitar revisión", isPresented: $isReviewing) {
            TextField("¿Qué no coincide?", text: $reviewNote)
            Button("Enviar") {
                if let wallet, let settlement = wallet.currentSettlement(now: dayAnchor) {
                    wallet.openReview(for: settlement.id, note: reviewNote)
                }
                reviewNote = ""
            }
            Button("Cancelar", role: .cancel) { reviewNote = "" }
        } message: {
            Text("Tu supervisor revisará el cálculo. La liquidación cerrada no se modifica: cualquier ajuste se registra como un movimiento aparte.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CapsLabel(text: "Cartera")
                Text("Liquidación semanal")
                    .font(.system(.title3, weight: .black))
            }
            Spacer(minLength: 0)
            DemoClockButton()
            SessionMenuButton()
        }
        .padding(.top, 6)
    }

    // MARK: - Balance

    private func balanceCard(_ settlement: WeeklySettlement, wallet: WalletStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CapsLabel(text: "Semana \(settlement.rangeLabel)")
                Spacer(minLength: 0)
                StatePill(
                    text: settlement.status.label,
                    symbol: settlement.status.symbol,
                    tone: settlement.status == .completed ? Palette.volt : Palette.info,
                    compact: true
                )
            }

            Text(Fmt.mxn(settlement.netMxn))
                .font(.system(size: 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.volt)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("Saldo disponible")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)

            VStack(spacing: 8) {
                amountRow("Ingresos generados", settlement.grossMxn, tone: .primary)
                if settlement.bonusMxn != 0 {
                    amountRow("Bonificaciones", settlement.bonusMxn, tone: Palette.volt)
                }
                if settlement.creditMxn != 0 {
                    amountRow("Crédito de unidad", settlement.creditMxn, tone: Palette.info)
                }
                if settlement.deductionMxn != 0 {
                    amountRow("Otras deducciones", settlement.deductionMxn, tone: Palette.amber)
                }
                if settlement.adjustmentMxn != 0 {
                    amountRow("Ajustes posteriores", settlement.adjustmentMxn, tone: Palette.amber)
                }
            }
            .padding(13)
            .panelFlat()

            HStack(spacing: 10) {
                BigButton(title: "Ver desglose", symbol: "list.bullet.rectangle.portrait", tone: .outline) {
                    showsBreakdown = true
                }
                BigButton(
                    title: transferTitle(settlement),
                    symbol: "arrow.up.right.circle.fill",
                    isEnabled: canSimulateTransfer && settlement.status == .available
                ) {
                    do {
                        try wallet.requestTransfer(for: settlement)
                    } catch {
                        transferError = error.localizedDescription
                    }
                }
            }

            // Two different sentences because they answer to two different truths. The
            // demonstration one warns that the money is not real; saying that to someone
            // authenticated against the server would be describing their pay as a mockup.
            // The other one does not promise a date — it says the connection is missing,
            // which is the only thing actually known.
            Text(
                canSimulateTransfer
                    ? "El pago es semanal. En esta versión la transferencia se simula: no se mueve dinero real."
                    : "El pago es semanal. Las transferencias estarán disponibles cuando la liquidación esté conectada al sistema financiero."
            )
            .font(.caption2)
            .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    private func transferTitle(_ settlement: WeeklySettlement) -> String {
        guard canSimulateTransfer else { return "Transferencia no disponible" }
        return settlement.status == .available ? "Solicitar transferencia" : settlement.status.label
    }

    private func amountRow(_ concept: String, _ amount: Int, tone: Color) -> some View {
        HStack {
            Text(concept)
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 8)
            Text(amount < 0 ? "-\(Fmt.mxn(abs(amount)))" : "+\(Fmt.mxn(amount))")
                .font(.system(.footnote, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tone)
        }
    }

    // MARK: - Status

    private func statusCard(_ settlement: WeeklySettlement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Estado de la liquidación", subtitle: settlement.status.hint)

            HStack(spacing: 4) {
                ForEach(SettlementStatus.allCases) { status in
                    let done = status.order <= settlement.status.order
                    VStack(spacing: 6) {
                        Circle()
                            .fill(done ? Palette.volt : Palette.surfaceRaised)
                            .frame(width: 9, height: 9)
                        Text(status.label)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(done ? Palette.volt : Palette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let note = settlement.reviewNote {
                NoticeBanner(
                    symbol: "questionmark.bubble.fill",
                    title: "Revisión solicitada",
                    message: note,
                    tone: .amber
                )
            } else {
                Button {
                    isReviewing = true
                } label: {
                    Label("Solicitar revisión por diferencias", systemImage: "questionmark.circle")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Palette.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Credit

    /// The credit lives inside the wallet: it is the biggest deduction of the week.
    private var creditCard: some View {
        Button {
            showsCredit = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Palette.volt)
                    .frame(width: 40, height: 40)
                    .background(Palette.volt.opacity(0.12), in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.hasCredit ? "Crédito de unidad" : "Programa de crédito")
                        .font(.system(.subheadline, weight: .bold))
                    Text(
                        store.credit.map { "Abono semanal de \(Fmt.mxn($0.weeklyMxn)) vía nómina" }
                            ?? "Conoce cómo obtener tu propia unidad"
                    )
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bank

    /// Bank details, and the action that only exists when there are any.
    ///
    /// There is no account to modify when there is no account. The screen used to say so
    /// and then offer "Solicitar modificación" anyway, which sent the driver into a form
    /// that asks for the reason for a change to a record that does not exist — and files
    /// the request against an empty file. Absence is a state, not a disabled button: with
    /// no account the action is not dimmed, it is not there.
    @ViewBuilder
    private var bankCard: some View {
        let bank = office?.file(id: store.driver.id)?.bank
        let requests = office?.bankRequests(driverId: store.driver.id) ?? []

        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Datos bancarios",
                subtitle: bank == nil
                    ? "Sin cuenta registrada"
                    : "Consulta; la modificación pasa por autorización"
            )

            if let bank {
                DetailRow(label: "Banco", value: bank.bank)
                DetailRow(label: "CLABE", value: bank.maskedClabe)
                DetailRow(label: "Titular", value: bank.holder)
                DetailRow(label: "Estado", value: bank.status.label, tone: bank.status.tone)
            } else {
                Text("Aún no hay una cuenta bancaria registrada para este perfil.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            if !requests.isEmpty {
                ForEach(requests) { request in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(request.status.tone)
                        Text("\(request.bank) · \(request.maskedClabe)")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 4)
                        Text(request.status.label)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(request.status.tone)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat(cornerRadius: 12)
                }
            }

            if bank != nil {
                BigButton(title: "Solicitar modificación", symbol: "building.columns.fill", tone: .outline) {
                    showsBankRequest = true
                }

                Text("Nunca podrás editar tu CLABE directamente: la solicitud la valida tu supervisor y la autoriza la gerencia de tu estación.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - History

    private func historyCard(_ wallet: WalletStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Semanas cerradas", subtitle: "Cálculo inmutable una vez cerrada la semana")
            ForEach(wallet.closedSettlements(now: dayAnchor)) { settlement in
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settlement.rangeLabel)
                            .font(.system(.footnote, weight: .bold))
                        Text("\(Fmt.mxn(settlement.grossMxn)) generados · \(settlement.status.label.lowercased())")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 4)
                    Text(Fmt.mxn(settlement.netMxn))
                        .font(.system(.footnote, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Palette.volt)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelFlat(cornerRadius: 14)
            }
        }
        .padding(16)
        .panel()
    }
}

// MARK: - Breakdown

struct SettlementBreakdownView: View {
    let settlement: WeeklySettlement

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(settlement.lines) { line in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: line.kind.symbol)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(line.amountMxn < 0 ? Palette.amber : Palette.volt)
                                    .frame(width: 30, height: 30)
                                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.concept)
                                        .font(.system(.footnote, weight: .bold))
                                    Text(line.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.textMuted)
                                }
                                Spacer(minLength: 4)
                                Text(line.amountMxn < 0 ? "-\(Fmt.mxn(abs(line.amountMxn)))" : Fmt.mxn(line.amountMxn))
                                    .font(.system(.footnote, weight: .black))
                                    .monospacedDigit()
                                    .foregroundStyle(line.amountMxn < 0 ? Palette.amber : Palette.volt)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panelFlat()
                        }

                        if !settlement.adjustments.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SupSectionHeader(title: "Ajustes posteriores", subtitle: "Movimientos separados del cálculo original")
                                ForEach(settlement.adjustments) { adjustment in
                                    VStack(alignment: .leading, spacing: 3) {
                                        DetailRow(label: adjustment.concept, value: Fmt.mxn(adjustment.amountMxn))
                                        Text("\(adjustment.reason) · \(adjustment.author) · \(Fmt.dateShort(adjustment.createdAt))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.textMuted)
                                    }
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .panelFlat(cornerRadius: 14)
                                }
                            }
                            .padding(16)
                            .panel()
                        }

                        HStack {
                            Text("Saldo disponible")
                                .font(.system(.subheadline, weight: .bold))
                            Spacer(minLength: 0)
                            Text(Fmt.mxn(settlement.netMxn))
                                .font(.system(.title3, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(Palette.volt)
                        }
                        .padding(16)
                        .panel()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Desglose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Bank change request

/// The driver asks; supervision validates; management authorizes. Nothing changes here.
struct BankChangeRequestView: View {
    let office: StationOfficeStore
    let driver: Driver

    @Environment(\.dismiss) private var dismiss

    @State private var bank: String = ""
    @State private var clabe: String = ""
    @State private var reason: String = ""
    @State private var hasOfficialId: Bool = false
    @State private var hasBankProof: Bool = false
    @State private var hasAddressProof: Bool = false
    @State private var addressMatches: Bool = true

    private var canSend: Bool {
        !bank.isEmpty && HRRules.isValidClabe(clabe) && !reason.isEmpty && hasOfficialId && hasBankProof
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva cuenta") {
                    TextField("Banco", text: $bank)
                    TextField("CLABE (18 dígitos)", text: $clabe).keyboardType(.numberPad)
                    TextField("Motivo del cambio", text: $reason, axis: .vertical).lineLimit(2...4)
                }
                Section("Documentación") {
                    Toggle("Identificación oficial", isOn: $hasOfficialId)
                    Toggle("Comprobante bancario", isOn: $hasBankProof)
                    Toggle("Comprobante de domicilio", isOn: $hasAddressProof)
                    Toggle("El domicilio coincide con mi expediente", isOn: $addressMatches)
                }
                Section {
                    Text("La cuenta debe estar a tu nombre y no puede estar registrada en otro expediente de la red. Si el domicilio no coincide exactamente, la solicitud pasa a revisión manual, no se rechaza.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(StationBackground())
            .navigationTitle("Datos bancarios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enviar") {
                        office.submitBankRequest(
                            driverId: driver.id,
                            driverName: driver.name,
                            bank: bank,
                            clabe: clabe,
                            holder: driver.name,
                            reason: reason,
                            hasOfficialId: hasOfficialId,
                            hasBankProof: hasBankProof,
                            hasAddressProof: hasAddressProof,
                            addressMatches: addressMatches
                        )
                        dismiss()
                    }
                    .disabled(!canSend)
                    .tint(Palette.volt)
                }
            }
        }
    }
}
