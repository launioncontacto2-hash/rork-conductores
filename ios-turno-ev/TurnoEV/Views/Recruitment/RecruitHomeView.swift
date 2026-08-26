import SwiftUI

/// The only question this screen answers: ¿tenemos suficientes candidatos para cubrir lo
/// que la flotilla va a necesitar? Everything above the fold is demand; everything below
/// is what recruitment has done about it.
struct RecruitHomeView: View {
    let recruit: RecruitmentStore
    let header: RecruitHeader
    let onOpenLeads: () -> Void
    let onOpenProspects: (RecruitStage?) -> Void
    let onOpenAppointments: () -> Void
    let onOpenVacancies: () -> Void
    let onOpenAnalytics: (RecruitAnalyticsTab) -> Void
    let onOpenAlerts: () -> Void

    /// Instants the counters of this dashboard are measured against.
    ///
    /// Two, because the board mixes semantics: the exception panel and the overdue-lead
    /// counter turn on a minute — a lead crosses its contact window at an arbitrary hour —
    /// while documents, altas and the agenda turn on a date. Written by invisible leaves,
    /// so the `ScrollView` is never invalidated by the clock.
    @State private var minuteAnchor: Date = AppClock.now()
    @State private var dayAnchor: Date = AppClock.now()

    var body: some View {
        ZStack {
            RecruitmentBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    demandCard
                    paceCard
                    exceptionBoard
                    funnelStrip
                    stationStrip
                    modules
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            ClockAnchor(.minute, date: $minuteAnchor)
            ClockAnchor(.day, date: $dayAnchor)
        }
    }

    // MARK: - Demand

    /// Units × 4 turnos. Every vacancy in this app is born from this multiplication.
    private var demandCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    CapsLabel(text: "Necesidad de personal")
                    Text("\(recruit.totalActiveVehicles) unidades × 4 turnos")
                        .font(.system(.subheadline, weight: .black))
                    Text("Cada unidad necesita cuatro conductores: matutino y vespertino, entre semana y fin de semana.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                RecRing(
                    ratio: recruit.coverageRatio,
                    headline: "\(recruit.coveragePct)%",
                    caption: "Cobertura",
                    tone: recruit.coveragePct >= 100 ? RecTone.good : (recruit.coveragePct >= 90 ? RecTone.warn : RecTone.bad)
                )
            }

            HStack(spacing: 8) {
                DemandFigure(value: "\(recruit.totalRequired)", caption: "Requeridos")
                DemandFigure(value: "\(recruit.totalAvailable)", caption: "Disponibles", tone: RecTone.cool)
                DemandFigure(
                    value: "\(recruit.totalVacancies)",
                    caption: "Vacantes hoy",
                    tone: recruit.totalVacancies > 0 ? RecTone.bad : RecTone.good
                )
                DemandFigure(
                    value: "\(recruit.projectedVacancies)",
                    caption: "Proyectadas",
                    tone: recruit.projectedVacancies > recruit.totalVacancies ? RecTone.warn : Palette.textMuted
                )
            }

            if recruit.totalIncomingVehicles > 0 {
                Text("\(recruit.totalIncomingVehicles) unidades ya compradas entrarán a operar: \(recruit.totalIncomingVehicles * HRRules.driversPerVehicle) conductores adicionales que hoy todavía no existen.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RecTone.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onOpenVacancies) {
                HStack {
                    Text("Ver vacantes por turno")
                        .font(.system(.footnote, weight: .bold))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundStyle(Palette.canvas)
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(RecTone.accent, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .panel()
    }

    // MARK: - Pace

    /// Does the current pace get there in time? Leads needed vs leads in hand.
    private var paceCard: some View {
        let needed = recruit.totalVacancies + (recruit.projectedVacancies - recruit.totalVacancies)
        let leadTarget = recruit.leadsNeeded(for: needed, now: dayAnchor)
        let inProcess = recruit.prospects.filter { $0.stage.isOpen }.count
        let isEnough = inProcess >= leadTarget

        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "¿Alcanza el ritmo?",
                subtitle: "Un lead no es una contratación: manda la conversión histórica",
                accent: RecTone.accent
            )

            HStack(spacing: 10) {
                HeadlineFigure(
                    value: "\(leadTarget)",
                    caption: "Leads necesarios",
                    tone: isEnough ? RecTone.good : RecTone.warn,
                    detail: "para \(needed) contrataciones"
                )
                HeadlineFigure(
                    value: "\(inProcess)",
                    caption: "En proceso hoy",
                    tone: isEnough ? RecTone.good : RecTone.bad,
                    detail: isEnough ? "cobertura suficiente" : "faltan \(leadTarget - inProcess)"
                )
            }

            VStack(spacing: 8) {
                MetricLine(
                    label: "Conversión lead → contratación",
                    value: "\(Int((recruit.conversion(now: dayAnchor) * 100).rounded())) %",
                    detail: "Histórico real de la base, no un supuesto",
                    tone: RecTone.cool
                )
                MetricLine(
                    label: "Tiempo medio de contratación",
                    value: "\(recruit.averageHiringDays) días",
                    detail: "Del alta del lead al contrato firmado",
                    tone: RecTone.cool
                )
                MetricLine(
                    label: "Margen de seguridad",
                    value: "\(recruit.marginPct) %",
                    detail: "Candidatos extra sobre la necesidad estadística",
                    tone: Palette.textMuted
                )
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Exceptions

    private var exceptionBoard: some View {
        // The set of alerts changes with time — `overdueLeads` is one of its terms — so
        // the heading, the empty state and the cards all read the same minute anchor.
        let alerts = recruit.alerts(now: minuteAnchor)
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Requieren atención",
                subtitle: "Umbrales de cobertura, contacto y agenda",
                actionTitle: alerts.isEmpty ? nil : "Ver todas",
                accent: RecTone.accent,
                action: alerts.isEmpty ? nil : onOpenAlerts
            )

            if alerts.isEmpty {
                NoticeBanner(
                    symbol: "checkmark.seal.fill",
                    title: "Sin alertas abiertas",
                    message: "La cobertura, el contacto y la agenda están dentro de los umbrales.",
                    tone: .volt
                )
            } else {
                ForEach(alerts.prefix(3)) { alert in
                    RecruitAlertCard(
                        alert: alert,
                        onOpen: { open(alert.destination) },
                        onReview: { recruit.reviewAlert(id: alert.id) }
                    )
                }
            }
        }
    }

    // MARK: - Funnel strip

    private var funnelStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Reclutamiento",
                subtitle: "Lo que hay hoy en cada etapa",
                actionTitle: "Pipeline",
                accent: RecTone.accent,
                action: { onOpenAnalytics(.pipeline) }
            )

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                MetricCard(
                    label: "Leads nuevos",
                    value: "\(recruit.count(stage: .lead))",
                    symbol: "sparkles",
                    detail: "\(recruit.overdueLeads(now: minuteAnchor).count) sin contactar a tiempo",
                    tone: recruit.overdueLeads(now: minuteAnchor).isEmpty ? RecTone.accent : RecTone.bad,
                    isAlarming: !recruit.overdueLeads(now: minuteAnchor).isEmpty,
                    action: onOpenLeads
                )
                MetricCard(
                    label: "Contactados",
                    value: "\(recruit.count(stage: .contacted))",
                    symbol: "phone.fill",
                    detail: "esperan precalificación",
                    tone: RecTone.cool,
                    action: { onOpenProspects(.contacted) }
                )
                MetricCard(
                    label: "Precalificados",
                    value: "\(recruit.count(stage: .prequalified))",
                    symbol: "checklist",
                    detail: "listos para entrevista",
                    tone: RecTone.cool,
                    action: { onOpenProspects(.prequalified) }
                )
                MetricCard(
                    label: "Citas programadas",
                    value: "\(recruit.upcomingAppointments(now: dayAnchor).count)",
                    symbol: "calendar.badge.clock",
                    detail: "\(recruit.todayAppointments(now: dayAnchor).count) hoy",
                    tone: RecTone.warn,
                    action: onOpenAppointments
                )
                MetricCard(
                    label: "Documentación pendiente",
                    value: "\(recruit.awaitingDocuments(now: dayAnchor).count)",
                    symbol: "doc.text.fill",
                    detail: "expedientes iniciales incompletos",
                    tone: RecTone.warn,
                    action: { onOpenProspects(.documents) }
                )
                MetricCard(
                    label: "Listos para contratar",
                    value: "\(recruit.readyToHire(now: dayAnchor).count)",
                    symbol: "signature",
                    detail: "expediente completo, falta tu firma",
                    tone: RecTone.warn,
                    action: { onOpenProspects(.readyToHire) }
                )
                MetricCard(
                    label: "Altas autorizadas",
                    value: "\(recruit.count(stage: .approved))",
                    symbol: "checkmark.seal.fill",
                    detail: "firmadas por ti esta semana",
                    tone: RecTone.good,
                    action: { onOpenProspects(.approved) }
                )
                MetricCard(
                    label: "Contratados",
                    value: "\(recruit.count(stage: .hired))",
                    symbol: "steeringwheel",
                    detail: "en \(recruit.averageHiringDays) días promedio",
                    tone: RecTone.good,
                    action: { onOpenProspects(.hired) }
                )
            }
        }
    }

    // MARK: - Stations

    private var stationStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Estaciones",
                subtitle: "Dónde está la vacante y desde cuándo",
                accent: RecTone.accent
            )
            ForEach(recruit.demands.sorted { $0.vacancies > $1.vacancies }) { demand in
                StationDemandCard(demand: demand, action: onOpenVacancies)
            }
        }
    }

    // MARK: - Modules

    private var modules: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Análisis", subtitle: "De dónde vienen y por qué se pierden", accent: RecTone.accent)

            Button { onOpenAnalytics(.pipeline) } label: {
                moduleRow(
                    title: "Pipeline y motivos de pérdida",
                    subtitle: "Conversión etapa por etapa · \(recruit.prospects.filter { $0.stage == .lost }.count) salidas registradas",
                    symbol: "chart.bar.doc.horizontal.fill"
                )
            }
            .buttonStyle(.plain)

            Button { onOpenAnalytics(.campaigns) } label: {
                moduleRow(
                    title: "Campañas y presupuesto",
                    subtitle: "Costo por lead y por contratación · \(recruit.campaigns.filter(\.isActive).count) activas",
                    symbol: "megaphone.fill"
                )
            }
            .buttonStyle(.plain)

            Button { onOpenAnalytics(.metrics) } label: {
                moduleRow(
                    title: "Métricas del reclutador",
                    subtitle: "Resultados reales, no número de llamadas",
                    symbol: "chart.line.uptrend.xyaxis"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func moduleRow(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(RecTone.accent)
                .frame(width: 34, height: 34)
                .background(RecTone.accent.opacity(0.12), in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat()
    }

    // MARK: - Routing

    private func open(_ destination: RecruitDestination) {
        switch destination {
        case .leads: onOpenLeads()
        case .prospects: onOpenProspects(nil)
        case .appointments: onOpenAppointments()
        case .vacancies: onOpenVacancies()
        case .campaigns: onOpenAnalytics(.campaigns)
        case .pipeline: onOpenAnalytics(.pipeline)
        }
    }
}
