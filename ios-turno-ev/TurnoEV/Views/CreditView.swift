import SwiftUI

/// Credit panel: sale of the fleet's used units on credit.
/// Shows a promotional banner while the driver has no contract, and the full
/// transparency dashboard once the contract is signed.
struct CreditView: View {
    @Environment(FleetStore.self) private var store

    @State private var isHowItWorksPresented: Bool = false
    @State private var isApprovalPresented: Bool = false
    /// Reason the boundary gave for refusing a write, when it refused one.
    @State private var unavailableReason: String?

    /// Whether the contractual operation can be performed at all from this device.
    /// The programme is presented to everyone; signing is what needs an authority.
    private var canOperate: Bool { store.canSimulateFinancialState }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        if let credit = store.credit, let metrics = store.creditMetrics {
                            ActiveCreditPanel(credit: credit, metrics: metrics)
                            if canOperate { demoFooter(hasCredit: true) }
                        } else {
                            CreditOfferPanel(
                                canRequest: canOperate,
                                onHowItWorks: { isHowItWorksPresented = true },
                                onRequest: requestCredit
                            )
                            if canOperate { demoFooter(hasCredit: false) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Créditos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SessionMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isHowItWorksPresented = true
                    } label: {
                        Image(systemName: "play.rectangle.fill")
                    }
                    .tint(Palette.volt)
                }
            }
            .sheet(isPresented: $isHowItWorksPresented) {
                CreditHowItWorksView()
            }
            .alert("¡Crédito aprobado!", isPresented: $isApprovalPresented) {
                Button("Ver mi crédito") {}
            } message: {
                Text("Firmaste tu contrato del \(CreditProgram.vehicleModel) sin enganche. El descuento semanal empieza en 7 días y la unidad se entrega en el mes \(CreditProgram.deliveryMonth).")
            }
            .alert(
                "Solicitud de crédito aún no disponible",
                isPresented: Binding(
                    get: { unavailableReason != nil },
                    set: { if !$0 { unavailableReason = nil } }
                )
            ) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(unavailableReason ?? "")
            }
        }
    }

    /// Signs the contract, or shows why it could not be signed.
    ///
    /// The approval alert is only ever reached after the store actually wrote the
    /// contract. Announcing an approval the app did not perform is the part of the old
    /// flow that made a local fixture look like a signed loan.
    private func requestCredit() {
        do {
            try store.requestCredit()
            isApprovalPresented = true
        } catch {
            unavailableReason = error.localizedDescription
        }
    }

    private func loadDemoProgress() {
        do {
            try store.loadCreditDemoProgress()
        } catch {
            unavailableReason = error.localizedDescription
        }
    }

    /// Demo helpers so both presentations of the panel can be reviewed.
    private func demoFooter(hasCredit: Bool) -> some View {
        VStack(spacing: 8) {
            CapsLabel(text: "Vista de demostración")
            if hasCredit {
                HStack(spacing: 10) {
                    Button("Contrato semana 14") { loadDemoProgress() }
                    Button("Ver anuncio") { store.cancelCredit() }
                }
            } else {
                Button("Ver crédito en curso (semana 14)") { loadDemoProgress() }
            }
        }
        .font(.system(.caption, weight: .semibold))
        .tint(Palette.info)
        .frame(maxWidth: .infinity)
        .padding(14)
        .panelFlat()
    }
}

// MARK: - Offer (driver without credit)

private struct CreditOfferPanel: View {
    /// Whether the contractual action is available. The programme itself — hero,
    /// benefits, steps, terms — is shown either way: what the fleet offers is
    /// information, and information does not need a backend.
    let canRequest: Bool
    let onHowItWorks: () -> Void
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            hero
            benefits
            steps

            VStack(spacing: 10) {
                if !canRequest {
                    NoticeBanner(
                        symbol: "clock.badge.exclamationmark",
                        title: "Solicitud de crédito aún no disponible",
                        message: "Esta operación requiere conexión con el sistema financiero de la estación.",
                        tone: .info
                    )
                }
                BigButton(
                    title: "Solicitar mi crédito",
                    symbol: "signature",
                    isEnabled: canRequest,
                    action: onRequest
                )
                BigButton(title: "Cómo funciona", symbol: "play.circle.fill", tone: .outline, action: onHowItWorks)
            }

            Text("Descuento vía nómina · \(CreditProgram.termWeeks) pagos semanales · plazo de \(CreditProgram.termMonths) meses · la unidad se entrega en el mes \(CreditProgram.deliveryMonth).")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color(Palette.surfaceRaised)
                .frame(height: 208)
                .overlay {
                    Image(CreditProgram.imageAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    Text("Seminueva certificada")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.volt, in: .capsule)
                        .padding(14)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, Palette.surface.opacity(0.95)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 96)
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(topLeadingRadius: 26, topTrailingRadius: 26))

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Venta de unidades de flotilla")
                Text("Llévate tu \(CreditProgram.vehicleModel) a crédito")
                    .font(.system(.title2, weight: .black))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sin enganche, con aprobación inmediata y equipo de carga incluido. Kilometraje no mayor a \(Fmt.km(CreditProgram.maxHandoverKm)).")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .background(Palette.surface.opacity(0.9), in: .rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26).stroke(Palette.volt.opacity(0.35), lineWidth: 1)
        }
        .voltGlow(22)
    }

    private var benefits: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(CreditProgram.benefits) { benefit in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: benefit.symbol)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Palette.volt)
                    Text(benefit.title)
                        .font(.system(.subheadline, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(benefit.detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
                .padding(14)
                .panelFlat()
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Así funciona en 4 pasos", systemImage: "list.number")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Palette.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CreditProgram.steps) { step in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(step.index)")
                                .font(.system(.subheadline, weight: .black))
                                .foregroundStyle(Palette.canvas)
                                .frame(width: 26, height: 26)
                                .background(Palette.volt, in: .circle)
                            Text(step.title)
                                .font(.system(.subheadline, weight: .bold))
                            Text(step.detail)
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 168, alignment: .topLeading)
                        .padding(14)
                        .panelFlat()
                    }
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }
}

// MARK: - Active contract

private struct ActiveCreditPanel: View {
    let credit: CreditAccount
    let metrics: CreditMetrics

    @State private var areTermsExpanded: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            balanceCard
            nextPaymentCard
            deliveryCard
            behaviourCard
            paymentsCard
            termsCard
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel(text: "Saldo del crédito")
                    Text(Fmt.mxn(metrics.balanceMxn))
                        .font(.system(size: 38, weight: .black))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(credit.vehicleTarget) · contrato \(credit.contractId)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                VStack(spacing: 2) {
                    Text("\(metrics.weeksPaid)")
                        .font(.system(.title3, weight: .black))
                        .monospacedDigit()
                    Text("de \(CreditProgram.termWeeks)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                    CapsLabel(text: "Semanas")
                }
                .padding(12)
                .panelFlat()
            }

            ProgressTrack(
                value: Double(metrics.paidMxn),
                goal: Double(credit.totalMxn),
                tone: Palette.volt
            )

            HStack(spacing: 10) {
                StatTile(label: "Pagado", value: Fmt.mxn(metrics.paidMxn), tone: .volt)
                StatTile(label: "Abono semanal", value: Fmt.mxn(credit.weeklyMxn), hint: "Vía nómina")
                StatTile(label: "Restan", value: "\(metrics.weeksRemaining)", hint: "Semanas por pagar")
            }
        }
        .padding(18)
        .panel()
    }

    private var nextPaymentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Próximo descuento", systemImage: "calendar.badge.clock")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Palette.textMuted)

            if let next = metrics.nextPayment {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(next.concept)
                            .font(.system(.headline, weight: .black))
                        Text(Fmt.dateShort(next.dueDate).capitalized)
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(Fmt.mxn(next.amountMxn))
                            .font(.system(.headline, weight: .black))
                            .monospacedDigit()
                        Text(next.status.label.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .tracking(1)
                            .foregroundStyle(tone(for: next.status))
                    }
                }
            } else {
                Text("No tienes abonos pendientes esta semana.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            }

            Text("El descuento se aplica automáticamente en tu nómina semanal; no necesitas hacer transferencias.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Entrega de la unidad", systemImage: "car.side.fill")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Palette.textMuted)

            HStack(alignment: .center, spacing: 16) {
                RingGauge(
                    value: Double(metrics.monthsElapsed),
                    goal: Double(CreditProgram.deliveryMonth),
                    headline: "\(metrics.monthsElapsed)/\(CreditProgram.deliveryMonth)",
                    caption: "Meses"
                )
                .scaleEffect(0.82)
                .frame(width: 146, height: 146)

                VStack(alignment: .leading, spacing: 8) {
                    if metrics.isUnitDelivered {
                        Text("Unidad lista para entrega")
                            .font(.system(.subheadline, weight: .black))
                            .foregroundStyle(Palette.volt)
                    } else {
                        Text("Faltan \(metrics.monthsToDelivery) meses")
                            .font(.system(.subheadline, weight: .black))
                    }
                    Text("Fecha estimada: \(Fmt.dateShort(metrics.estimatedDeliveryDate).capitalized)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                    Text("Odómetro actual: \(Fmt.km(credit.assignedVehicleOdometerKm))")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                    Text("Sale de flotilla entre \(Fmt.km(CreditProgram.minHandoverKm)) y \(Fmt.km(CreditProgram.maxHandoverKm)).")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            NoticeBanner(
                symbol: "info.circle.fill",
                title: "Mientras construyes tu historial, la unidad sigue operando en la flotilla.",
                message: "Ese modelo es lo que nos permite venderte más barato que un crédito tradicional.",
                tone: .info
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private var behaviourCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Comportamiento crediticio", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text("RIESGO \(metrics.risk.label.uppercased())")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                    .foregroundStyle(riskColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(riskColor.opacity(0.14), in: .capsule)
            }

            HStack(spacing: 10) {
                StatTile(
                    label: "Cumplimiento",
                    value: "\(Int((metrics.complianceRate * 100).rounded()))%",
                    tone: metrics.complianceRate >= 0.95 ? .volt : .amber
                )
                StatTile(label: "Puntuales", value: "\(credit.onTimePayments)", tone: .info)
                StatTile(label: "Atrasados", value: "\(credit.latePayments)", tone: credit.latePayments == 0 ? .neutral : .danger)
            }

            Text(metrics.risk.detail)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private var paymentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Historial de abonos", systemImage: "list.bullet.rectangle.portrait.fill")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Palette.textMuted)

            ForEach(credit.payments) { payment in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payment.concept)
                            .font(.system(.subheadline, weight: .bold))
                        Text(Fmt.dateShort(payment.dueDate).capitalized)
                            .font(.caption2)
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.mxn(payment.amountMxn))
                            .font(.system(.subheadline, weight: .black))
                            .monospacedDigit()
                        Text(payment.status.label.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .tracking(1)
                            .foregroundStyle(tone(for: payment.status))
                    }
                }
                .padding(14)
                .panelFlat(cornerRadius: 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private var termsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                areTermsExpanded.toggle()
            } label: {
                HStack {
                    Label("Condiciones del contrato", systemImage: "doc.text.fill")
                        .font(.system(.subheadline, weight: .bold))
                    Spacer()
                    Image(systemName: areTermsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .buttonStyle(.plain)

            if areTermsExpanded {
                VStack(spacing: 8) {
                    termRow("Firma", Fmt.dateShort(credit.startedAt).capitalized)
                    termRow("Enganche", "Sin enganche")
                    termRow("Monto financiado", Fmt.mxn(credit.totalMxn))
                    termRow("Plazo", "\(CreditProgram.termMonths) meses · \(CreditProgram.termWeeks) semanas")
                    termRow("Forma de pago", "Descuento semanal vía nómina")
                    termRow("Entrega de unidad", "Mes \(CreditProgram.deliveryMonth)")
                    termRow("Último abono", Fmt.dateShort(metrics.contractEndDate).capitalized)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private func termRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
            Spacer()
            Text(value)
                .font(.system(.caption, weight: .bold))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .panelFlat(cornerRadius: 14)
    }

    private var riskColor: Color {
        switch metrics.risk {
        case .low: Palette.volt
        case .medium: Palette.amber
        case .high: Palette.danger
        }
    }

    private func tone(for status: CreditStatus) -> Color {
        switch status {
        case .paid: Palette.volt
        case .due: Palette.amber
        case .late: Palette.danger
        }
    }
}

#Preview {
    CreditView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
