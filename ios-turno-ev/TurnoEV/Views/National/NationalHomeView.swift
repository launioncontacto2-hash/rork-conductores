import SwiftUI

/// The country in one screen. Direction opens with three questions: ¿cuánto factura hoy
/// la red?, ¿alcanza la plantilla para la flotilla instalada? y ¿qué se detuvo?
struct NationalHomeView: View {
    let national: NationalStore
    let header: NationalHeader
    let onOpenRegion: (String) -> Void
    let onOpenRegions: () -> Void
    let onOpenDirectory: () -> Void
    let onOpenExpansion: () -> Void
    let onOpenPolicy: () -> Void

    private var metrics: NetworkMetrics { national.metrics }

    var body: some View {
        ZStack {
            NationalBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    billingCard
                    staffingCard
                    exceptionBoard
                    weekCard
                    regionStrip
                    networkGrid
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Billing

    private var billingCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    CapsLabel(text: "Facturación de la red hoy")
                    Text(Fmt.mxn(metrics.earningsMxn))
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(metrics.goalRatio >= NationalRules.regionGoalFloor ? NatTone.good : NatTone.bad)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("Meta del turno \(Fmt.mxn(metrics.goalMxn)) · \(metrics.tripsToday) viajes")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                MgRing(
                    ratio: metrics.goalRatio,
                    headline: "\(Int(metrics.goalRatio * 100))%",
                    caption: "de meta",
                    tone: metrics.goalRatio >= 1 ? NatTone.good : NatTone.accent,
                    size: 108
                )
            }

            HStack(spacing: 10) {
                NatFigure(
                    value: Fmt.mxn(metrics.earningsPerVehicleMxn),
                    caption: "Por unidad",
                    detail: "Promedio nacional del día",
                    tone: NatTone.accent
                )
                NatFigure(
                    value: "\(Int(metrics.utilizationRatio * 100))%",
                    caption: "Flotilla en calle",
                    detail: "\(metrics.operatingVehicles) de \(metrics.fleetSize) unidades",
                    tone: metrics.utilizationRatio >= 0.7 ? NatTone.good : NatTone.warn
                )
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Staffing

    /// The arithmetic of the whole company: unidades × 4 turnos = plantilla necesaria.
    private var staffingCard: some View {
        let covered = metrics.driverDeficit == 0
        return Button(action: onOpenDirectory) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: covered ? "checkmark.seal.fill" : "person.badge.minus")
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(covered ? NatTone.good : NatTone.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            covered
                                ? "La plantilla nacional cubre la flotilla instalada"
                                : "Faltan \(metrics.driverDeficit) conductores en la red"
                        )
                        .font(.system(.subheadline, weight: .black))
                        .multilineTextAlignment(.leading)
                        Text("\(metrics.fleetSize) unidades × \(HRRules.driversPerVehicle) turnos = \(metrics.requiredDrivers) de plantilla · hay \(metrics.payrollSize)")
                            .font(.caption2)
                            .foregroundStyle(Palette.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }

                ProgressTrack(
                    value: Double(metrics.payrollSize),
                    goal: Double(max(1, metrics.requiredDrivers)),
                    tone: covered ? NatTone.good : NatTone.warn
                )
                .frame(height: 8)

                if metrics.incomingVehicles > 0 {
                    Text("Además, \(metrics.incomingVehicles) unidades autorizadas en apertura sumarán \(HRRules.requiredDrivers(activeVehicles: metrics.incomingVehicles)) plazas más.")
                        .font(.system(size: 10))
                        .foregroundStyle(NatTone.cool)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exceptions

    private var exceptionBoard: some View {
        let alerts = Array(national.criticalAlerts.prefix(4))
        return Group {
            if alerts.isEmpty {
                NoticeBanner(
                    symbol: "checkmark.seal.fill",
                    title: "Ninguna región requiere a dirección hoy",
                    message: "Metas, plantilla, autorizaciones y aperturas dentro de umbral.",
                    tone: .volt
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SupSectionHeader(
                        title: "Requieren a dirección",
                        subtitle: "Excepciones de toda la red, ordenadas por gravedad"
                    )
                    ForEach(alerts) { alert in
                        NationalAlertCard(
                            alert: alert,
                            onOpen: { open(alert.kind.destination) },
                            onReview: { national.reviewAlert(id: alert.id) }
                        )
                    }
                }
            }
        }
    }

    private func open(_ destination: NationalDestination) {
        switch destination {
        case .regions: onOpenRegions()
        case .directory: onOpenDirectory()
        case .expansion: onOpenExpansion()
        case .policy: onOpenPolicy()
        }
    }

    // MARK: - Week

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Semana de la red",
                subtitle: "Lunes a domingo contra la meta de cada día"
            )
            WeekBarsChart(points: national.weekSeries, tone: NatTone.accent)
            HStack(spacing: 10) {
                NatFigure(
                    value: Fmt.mxn(metrics.weekEarningsMxn),
                    caption: "Acumulado",
                    detail: "\(Int(metrics.weekGoalRatio * 100))% de \(Fmt.mxn(metrics.weekGoalMxn))",
                    tone: NatTone.accent
                )
                NatFigure(
                    value: "\(metrics.criticalIncidents)",
                    caption: "Incidentes críticos",
                    detail: "\(metrics.openIncidents) incidentes abiertos en total",
                    tone: metrics.criticalIncidents > 0 ? NatTone.bad : NatTone.good
                )
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Regions

    private var regionStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Regiones",
                subtitle: "Ordenadas por desempeño del día",
                actionTitle: "Ver todas",
                accent: NatTone.accent,
                action: onOpenRegions
            )
            ForEach(Array(national.rollupsByPerformance.enumerated()), id: \.element.id) { index, region in
                RegionCard(rank: index + 1, region: region) { onOpenRegion(region.id) }
            }
        }
    }

    // MARK: - Network grid

    private var networkGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Red", subtitle: "Estructura, cartera y crecimiento")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NatFigure(
                    value: "\(metrics.stations)",
                    caption: "Estaciones",
                    detail: "en \(metrics.regions) regiones",
                    tone: NatTone.accent
                )
                NatFigure(
                    value: "\(metrics.fleetSize)",
                    caption: "Unidades",
                    detail: "\(metrics.idleVehicles) detenidas hoy",
                    tone: NatTone.cool
                )
                NatFigure(
                    value: "\(metrics.creditPortfolio)",
                    caption: "Cartera de crédito",
                    detail: "\(metrics.creditBehind) con atraso",
                    tone: metrics.creditBehind > 0 ? NatTone.warn : NatTone.good
                )
                NatFigure(
                    value: "\(metrics.pendingApprovals)",
                    caption: "Por autorizar",
                    detail: "\(metrics.agingApprovals) detenidas más de 24 h",
                    tone: metrics.agingApprovals > 0 ? NatTone.bad : Palette.textMuted
                )
            }

            ModuleLink(
                title: "Expansión",
                subtitle: "\(national.projects.filter { $0.stage != .operating }.count) estaciones en apertura · \(Fmt.mxn(national.committedInvestmentMxn)) comprometidos",
                symbol: "map.fill"
            ) {
                NationalExpansionView(national: national)
            }

            ModuleLink(
                title: "Reglas de la red",
                subtitle: "Versión \(national.policy.version) · metas, tolerancias, bonos y crédito",
                symbol: "text.book.closed.fill"
            ) {
                NationalPolicyView(national: national)
            }
        }
    }
}
