import SwiftUI
import UIKit

/// Cash capture. Cash is not an authorized way to charge, so this screen does not open
/// a free income form: it settles a specific trip the platform reported as paid in cash,
/// and it does it under two locks — the money has to be deposited before the day of the
/// trip ends, and the slip has to be printed that same day. If either lock fails the
/// registration is denied and the amount is recovered from the week.
struct IncomeView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedChargeId: String?
    @State private var amount: String = ""
    @State private var evidence: Data?
    @State private var reading: DepositSlipReader.Reading?
    @State private var isReadingSlip: Bool = false
    @State private var errorMessage: String?
    @State private var copiedField: String?
    @State private var recovered: [CashCharge] = []
    @State private var isDemoCharge: Bool = false
    /// The screen writes to the store when it opens. `onAppear` fires again every time
    /// the camera sheet closes, so the bootstrap is done once per presentation instead
    /// of once per photo — otherwise every capture minted another cash charge.
    @State private var didBootstrap: Bool = false

    private let demoAmounts = [140, 185, 220, 260]

    /// Whether this device may still stand in for the platform.
    ///
    /// The screen leans on two simulations that only make sense while nothing is
    /// connected: it mints the cash trip the platform should have reported, and filing
    /// the deposit books the income locally. Neither can be done on behalf of a proved
    /// identity — a fabricated income is what turns an empty week into a worked one,
    /// unlocking the station deduction and the whole bonus evaluation.
    private var canOperate: Bool { store.canSimulateFinancialState }

    /// The account the deposit has to land in, when one exists.
    ///
    /// Optional now: the network account is published by the national desk of this same
    /// app and defaults to a fictitious BBVA. Under a proved identity there is nothing
    /// authoritative to print at the counter, and a plausible CLABE is worse than none —
    /// the driver would deposit real cash into it.
    private var account: CashDepositAccount? { store.cashDepositAccount }

    private var charges: [CashCharge] { store.openCashCharges }

    private var charge: CashCharge? {
        charges.first { $0.id == selectedChargeId } ?? charges.first
    }

    private var declared: Int { Int(amount.trimmingCharacters(in: .whitespaces)) ?? 0 }

    private var amountMatch: DepositMatch {
        guard evidence != nil, let reading, !isReadingSlip else { return .notChecked }
        return DepositSlipReader.match(declared: declared, detected: reading.detectedMxn)
    }

    /// Lock 1 · the clock. The deposit is only good until the day of the trip ends.
    private var isWithinDeadline: Bool {
        guard let charge else { return false }
        return CashChargeRules.state(for: charge, now: store.now).isDepositable
    }

    /// Lock 3 · the destination printed on the slip has to be the account of the network.
    ///
    /// With no published account there is nothing to compare against, so the lock stays
    /// shut rather than opening by default.
    private var accountMatch: DepositMatch {
        guard evidence != nil, let reading, !isReadingSlip, let account else { return .notChecked }
        return DepositSlipReader.accountMatch(expected: account, reading: reading)
    }

    /// Lock 2 · the date printed on the slip has to be the day of the trip.
    private var slipDateCheck: SlipDateCheck {
        guard let charge, evidence != nil, let reading, !isReadingSlip else { return .pending }
        guard let printed = reading.detectedDate else { return .unreadable }
        return CashChargeRules.isSameOperatingDay(printed, as: charge) ? .valid(printed) : .otherDay(printed)
    }

    private enum SlipDateCheck {
        case pending
        case unreadable
        case valid(Date)
        case otherDay(Date)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    private var canSave: Bool {
        charge != nil
            && declared > 0
            && evidence != nil
            && !isReadingSlip
            && isWithinDeadline
            && amountMatch == .matched
            && slipDateCheck.isValid
            && accountMatch == .matched
            && canOperate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        cashRuleBanner

                        if !canOperate {
                            backendPendingBanner
                        }

                        if !recovered.isEmpty {
                            recoveredBanner
                        }

                        if let charge {
                            if isDemoCharge {
                                demoBanner
                            }
                            chargeCard(charge)
                            amountCard
                            accountCard
                            slipCard(charge)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.danger)
                            }

                            BigButton(
                                title: "Guardar ingreso",
                                symbol: "tray.and.arrow.down.fill",
                                isEnabled: canSave
                            ) {
                                save()
                            }

                            Text("Al guardar se envía un aviso al gerente de \(store.driver.station) con el monto, la unidad y el comprobante.")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Registro de ingresos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DemoClockButton()
                }
            }
            .onAppear(perform: bootstrap)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Rules

    private var cashRuleBanner: some View {
        NoticeBanner(
            symbol: "banknote.fill",
            title: "El cobro en efectivo no está autorizado.",
            message: "Si por una emergencia el usuario cambia su método de pago como efectivo, recíbelo y deposítalo en la cuenta autorizada. El depósito sólo será válido el mismo día, de lo contrario se descontará de tus ingresos al final de la semana.",
            tone: .amber
        )
    }

    /// Shown to an identity the server proved, where nothing on this screen can be
    /// simulated on its behalf.
    private var backendPendingBanner: some View {
        NoticeBanner(
            symbol: "clock.badge.exclamationmark",
            title: "Registro de ingresos aún no disponible",
            message: "Tus viajes en efectivo llegarán aquí cuando la plataforma esté conectada. Hasta entonces esta pantalla no registra ingresos ni genera cobros de prueba en tu cuenta.",
            tone: .info
        )
    }

    /// Visible only while the network is not connected to the platform yet.
    private var demoBanner: some View {
        NoticeBanner(
            symbol: "hammer.fill",
            title: "Cobro de demostración",
            message: "La plataforma aún no está conectada: se generó un viaje en efectivo de prueba para que puedas recorrer el registro completo.",
            tone: .info
        )
    }

    private var recoveredBanner: some View {
        NoticeBanner(
            symbol: "exclamationmark.octagon.fill",
            title: "\(CashChargeRules.recoveryConcept) · \(Fmt.mxn(recovered.reduce(0) { $0 + $1.amountMxn }))",
            message: recovered.count == 1
                ? "El viaje \(recovered[0].tripReference) del \(Fmt.dateShort(recovered[0].generatedAt)) ya no admite comprobante: venció su plazo y el monto se descuenta de tus ingresos al cierre de la semana."
                : "\(recovered.count) cobros en efectivo vencieron sin depósito. Los montos se descuentan de tus ingresos al cierre de la semana.",
            tone: .danger
        )
    }

    // MARK: - Charge

    /// The trip the platform reported in cash, with the clock running against it.
    private func chargeCard(_ charge: CashCharge) -> some View {
        let state = CashChargeRules.state(for: charge, now: store.now)
        let deadline = CashChargeRules.deadline(for: charge)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "car.side.arrowtriangle.up.fill")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.volt)
                    .frame(width: 34, height: 34)
                    .background(Palette.volt.opacity(0.12), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Viaje cobrado en efectivo")
                        .font(.system(.subheadline, weight: .black))
                    Text("\(charge.tripReference) · \(Fmt.dateShort(charge.generatedAt)) · \(Fmt.clock(charge.generatedAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
                Text(Fmt.mxn(charge.amountMxn))
                    .font(.system(.title3, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(Palette.volt)
            }

            if charges.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(charges) { item in
                            Button {
                                selectedChargeId = item.id
                                resetCapture()
                            } label: {
                                Text("\(item.tripReference) · \(Fmt.mxn(item.amountMxn))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(item.id == charge.id ? Palette.canvas : Palette.textMuted)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(item.id == charge.id ? Palette.volt : Palette.surfaceRaised, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 2)
            }

            deadlineRow(state: state, deadline: deadline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func deadlineRow(state: CashChargeState, deadline: Date) -> some View {
        let isRunning = state.isDepositable
        let tint: Color = {
            guard case .onTime(let minutes) = state else { return Palette.danger }
            return minutes < 120 ? Palette.amber : Palette.volt
        }()

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isRunning ? "clock.badge.checkmark.fill" : "clock.badge.exclamationmark.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                if case .onTime(let minutes) = state {
                    Text("Te quedan \(CashChargeRules.remainingText(minutes: minutes))")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(tint)
                } else {
                    Text("Plazo vencido")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(tint)
                }
                Text("Fecha límite \(Fmt.dateShort(deadline)) · 23:59:59, cotejada con el registro de la plataforma.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Palette.volt)
            Text("Sin efectivo pendiente")
                .font(.system(.title3, weight: .black))
            Text("No tienes viajes cobrados en efectivo por depositar. Este registro solo se abre cuando la plataforma reporta un cobro en efectivo de tus viajes.")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)

            if canOperate {
                BigButton(title: "Sincronizar con la plataforma", symbol: "arrow.triangle.2.circlepath", tone: .outline) {
                    do {
                        _ = try store.syncCashChargeFromPlatform(amountMxn: demoAmounts.randomElement() ?? 180)
                        isDemoCharge = true
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        resetCapture()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .panel()
    }

    // MARK: - Amount

    private var amountCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "banknote.fill")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                CapsLabel(text: "Monto depositado")
                Spacer()
            }

            TextField("0", text: $amount)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 40, weight: .black))
                .monospacedDigit()
                .padding(.vertical, 8)
                .onChange(of: amount) { _, _ in errorMessage = nil }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .panel()
    }

    /// Published by national direction. The driver reads it at the counter, so every
    /// field can be copied with one tap.
    ///
    /// When nothing has been published, the card is replaced by a refusal rather than by
    /// a placeholder: this screen is read standing at a counter with cash in hand, and a
    /// fictitious CLABE printed here is money sent to an account that does not exist.
    @ViewBuilder
    private var accountCard: some View {
        if let account {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Palette.info)
                        .frame(width: 34, height: 34)
                        .background(Palette.info.opacity(0.12), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cuenta para depósitos en efectivo")
                            .font(.system(.subheadline, weight: .black))
                        Text("Publicada por la administración nacional")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 0)
                }

                copyRow(label: "Banco", value: account.bank, copies: false)
                copyRow(label: "Titular", value: account.holder, copies: false)
                copyRow(label: "CLABE", value: account.readableClabe, copyValue: account.clabe)
                copyRow(label: "Cuenta", value: account.accountNumber, copyValue: account.accountNumber.filter(\.isNumber))
                copyRow(label: "Referencia", value: account.reference, copyValue: account.reference)

                Text(account.instructions)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        } else {
            NoticeBanner(
                symbol: "building.columns",
                title: "Cuenta de depósitos no disponible",
                message: "La cuenta autorizada de la red aún no llega desde el sistema financiero. No deposites efectivo hasta que aparezca aquí.",
                tone: .info
            )
        }
    }

    private func copyRow(label: String, value: String, copyValue: String? = nil, copies: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(Palette.textMuted)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(.system(.footnote, weight: .bold))
                .monospacedDigit()
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if copies {
                Button {
                    UIPasteboard.general.string = copyValue ?? value
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.smooth(duration: 0.2)) { copiedField = label }
                } label: {
                    Image(systemName: copiedField == label ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(copiedField == label ? Palette.volt : Palette.info)
                        .frame(width: 30, height: 30)
                        .background(Palette.surfaceRaised, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copiar \(label)")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Slip

    private func slipCard(_ charge: CashCharge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Comprobante del depósito")

            PhotoSlotView(
                title: evidence == nil ? "Fotografiar comprobante" : "Comprobante adjunto",
                hint: "Ticket completo: importe, fecha y cuenta destino visibles",
                data: evidence
            ) { data in
                evidence = data
                readSlip(data)
            }

            if !isWithinDeadline {
                NoticeBanner(
                    symbol: "xmark.octagon.fill",
                    title: "Registro denegado por plazo vencido",
                    message: "El comprobante de este viaje solo era válido hasta las 23:59:59 del \(Fmt.dateShort(charge.generatedAt)). El monto se cobra de tus ingresos de la semana como «\(CashChargeRules.recoveryConcept)».",
                    tone: .danger
                )
            } else if isReadingSlip {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cotejando importe, fecha y cuenta destino del comprobante…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelFlat(cornerRadius: 16)
            } else if evidence != nil, let reading {
                VStack(spacing: 10) {
                    amountVerification(reading: reading)
                    dateVerification(charge: charge)
                    // The third lock compares the slip against a published account. With
                    // none published there is nothing to compare, so the check is not
                    // drawn as passed or failed — it is not drawn at all, and `canSave`
                    // stays false because `accountMatch` never reaches `.matched`.
                    if let account {
                        accountVerification(reading: reading, account: account)
                    }
                }
            } else {
                Text("Se revisan cuatro cosas del ticket: que el importe impreso sea el que capturaste, que la fecha sea la del viaje, que la cuenta destino sea la de la red y que aún estés dentro del plazo del mismo día.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func amountVerification(reading: DepositSlipReader.Reading) -> some View {
        let state = amountMatch
        let tint: Color = switch state {
        case .matched: Palette.volt
        case .mismatched: Palette.danger
        case .unreadable, .notChecked: Palette.amber
        }

        return VStack(alignment: .leading, spacing: 8) {
            checkHeader(symbol: state.symbol, tint: tint, title: state.label, detail: amountDetail(reading: reading, state: state))

            if let detected = reading.detectedMxn {
                HStack(spacing: 8) {
                    ReadingTile(label: "Capturado", value: Fmt.mxn(declared), tone: .primary)
                    ReadingTile(label: "En el ticket", value: Fmt.mxn(detected), tone: tint)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.35), lineWidth: 1) }
    }

    private func dateVerification(charge: CashCharge) -> some View {
        let check = slipDateCheck
        let tint: Color = check.isValid ? Palette.volt : Palette.danger

        let title: String = switch check {
        case .valid: "Fecha del comprobante verificada"
        case .otherDay: "El comprobante es de otro día"
        case .unreadable: "No se pudo leer la fecha del ticket"
        case .pending: "Fecha pendiente de cotejar"
        }

        let detail: String = switch check {
        case .valid(let printed):
            "Depositado el \(Fmt.dateShort(printed)), el mismo día del viaje."
        case .otherDay(let printed):
            "El ticket dice \(Fmt.dateShort(printed)) y el cobro se generó el \(Fmt.dateShort(charge.generatedAt)). Solo se acepta el comprobante del mismo día."
        case .unreadable:
            "Vuelve a fotografiar el ticket con la fecha visible: sin ella no se puede validar el depósito."
        case .pending:
            "Adjunta el comprobante para cotejar la fecha."
        }

        return checkHeader(symbol: check.isValid ? "calendar.badge.checkmark" : "calendar.badge.exclamationmark", tint: tint, title: title, detail: detail)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.35), lineWidth: 1) }
    }

    /// Third lock: the money has to land in the account of the network. A slip with a
    /// different destination proves a deposit, but not this one.
    private func accountVerification(
        reading: DepositSlipReader.Reading,
        account: CashDepositAccount
    ) -> some View {
        let state = accountMatch
        let tint: Color = switch state {
        case .matched: Palette.volt
        case .mismatched: Palette.danger
        case .unreadable, .notChecked: Palette.amber
        }

        let title: String = switch state {
        case .matched: "Cuenta destino verificada"
        case .mismatched: "El depósito no fue a la cuenta de la red"
        case .unreadable, .notChecked: "No se pudo leer la cuenta destino"
        }

        let detail: String = switch state {
        case .matched:
            "El comprobante muestra la cuenta \(account.bank) registrada por la administración nacional."
        case .mismatched:
            "La cuenta impresa no coincide con la CLABE \(account.readableClabe). Solo se acepta el depósito a la cuenta autorizada."
        case .unreadable, .notChecked:
            "Vuelve a fotografiar el ticket con la CLABE o el número de cuenta destino visibles."
        }

        return VStack(alignment: .leading, spacing: 8) {
            checkHeader(
                symbol: state == .matched ? "building.columns.fill" : "exclamationmark.triangle.fill",
                tint: tint,
                title: title,
                detail: detail
            )

            if let printed = reading.detectedAccounts.first {
                HStack(spacing: 8) {
                    ReadingTile(label: "Registrada", value: last4(account.clabe), hint: account.bank, tone: .primary)
                    ReadingTile(label: "En el ticket", value: last4(printed), hint: "Últimos dígitos", tone: tint)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.35), lineWidth: 1) }
    }

    /// Accounts are compared by their tail: it is the part no store ever masks.
    private func last4(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count >= 4 else { return digits.isEmpty ? "—" : digits }
        return "••\(digits.suffix(4))"
    }

    private func checkHeader(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.footnote, weight: .black))
                    .foregroundStyle(tint)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func amountDetail(reading: DepositSlipReader.Reading, state: DepositMatch) -> String {
        switch state {
        case .matched:
            "El importe del comprobante coincide con el monto capturado."
        case .mismatched:
            "El ticket dice \(Fmt.mxn(reading.detectedMxn ?? 0)) y capturaste \(Fmt.mxn(declared)). Corrige el monto o vuelve a fotografiar el comprobante."
        case .unreadable, .notChecked:
            "No se pudo leer un importe en la foto. Toma el ticket completo, sin sombras y con el importe enfocado."
        }
    }

    // MARK: - Actions

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        // Anything whose day already ended stops being a deposit and becomes a discount
        // on the week, before the driver can try to file it late.
        recovered = store.chargeBackExpiredCashCharges()

        // While the app is in development the screen has to be reachable even when the
        // platform has not reported a cash trip yet: a demo charge is seeded so the whole
        // registration can be walked through. Never for a proved identity — a charge
        // nobody reported would become a real recovery against their week the moment its
        // deadline passed.
        guard canOperate else { return }
        guard store.openCashCharges.isEmpty else { return }
        guard let charge = try? store.syncCashChargeFromPlatform(
            amountMxn: demoAmounts.randomElement() ?? 180
        ) else { return }
        selectedChargeId = charge.id
        isDemoCharge = true
    }

    private func resetCapture() {
        evidence = nil
        reading = nil
        amount = ""
        errorMessage = nil
    }

    private func readSlip(_ data: Data) {
        isReadingSlip = true
        reading = nil
        Task {
            let result = await DepositSlipReader.read(data)
            reading = result
            isReadingSlip = false
            if let detected = result.detectedMxn, declared == 0 {
                // The slip already carries the figure: it saves the driver typing it.
                amount = "\(detected)"
            }
        }
    }

    private func save() {
        guard let charge else { return }
        guard declared > 0 else {
            errorMessage = "Captura el monto que depositaste."
            return
        }
        guard evidence != nil else {
            errorMessage = "Adjunta la foto del comprobante del depósito."
            return
        }
        guard isWithinDeadline else {
            errorMessage = "El plazo del mismo día venció. El monto se cobra de tus ingresos de la semana."
            return
        }
        guard slipDateCheck.isValid else {
            errorMessage = "El comprobante debe ser del mismo día en que se generó el cobro."
            return
        }
        guard amountMatch == .matched else {
            errorMessage = "El monto capturado no coincide con el comprobante. Corrígelo antes de guardar."
            return
        }
        guard accountMatch == .matched else {
            errorMessage = "El comprobante debe mostrar la cuenta autorizada de la red."
            return
        }

        do {
            _ = try store.registerCashDeposit(
                charge: charge,
                declaredMxn: declared,
                detectedMxn: reading?.detectedMxn,
                match: amountMatch,
                accountMatch: accountMatch,
                detectedAccount: reading?.detectedAccounts.first,
                slip: evidence
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

#Preview {
    IncomeView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
