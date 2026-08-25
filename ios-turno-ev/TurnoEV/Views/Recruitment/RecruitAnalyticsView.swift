import SwiftUI

nonisolated enum RecruitAnalyticsTab: String, CaseIterable, Identifiable, Sendable {
    case pipeline
    case campaigns
    case metrics

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pipeline: "Pipeline"
        case .campaigns: "Campañas"
        case .metrics: "Métricas"
        }
    }
}

/// Everything that explains the funnel: where candidates fall out, which channel really
/// produces drivers and what the recruitment desk is delivering.
struct RecruitAnalyticsView: View {
    let recruit: RecruitmentStore
    let header: RecruitHeader
    @Binding var tab: RecruitAnalyticsTab

    private var now: Date { recruit.now }

    var body: some View {
        ZStack {
            RecruitmentBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header

                    Picker("Sección", selection: $tab) {
                        ForEach(RecruitAnalyticsTab.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .pipeline: pipelineSection
                    case .campaigns: campaignsSection
                    case .metrics: metricsSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Pipeline

    private var pipelineSection: some View {
        let funnel = recruit.funnel
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SupSectionHeader(
                    title: "Embudo completo",
                    subtitle: "Cuántos llegaron a cada etapa, incluidos los que ya salieron",
                    accent: RecTone.accent
                )
                FunnelBoard(funnel: funnel, highlight: .hired)
            }
            .padding(16)
            .panel()

            VStack(alignment: .leading, spacing: 10) {
                SupSectionHeader(
                    title: "Conversión",
                    subtitle: "Un lead no equivale a una contratación",
                    accent: RecTone.accent
                )
                ConversionRow(title: "Lead → Contactado", ratio: funnel.leadToContact)
                ConversionRow(title: "Contactado → Entrevista", ratio: funnel.contactToInterview)
                ConversionRow(title: "Entrevista → Aprobado", ratio: funnel.interviewToApproved)
                ConversionRow(title: "Aprobado → Contratado", ratio: funnel.approvedToHire)
                ConversionRow(
                    title: "Lead → Contratado",
                    ratio: funnel.leadToHire,
                    detail: "Es la tasa que se usa para calcular cuántos leads hay que generar."
                )
            }
            .padding(16)
            .panel()

            lossSection
        }
    }

    private var lossSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Motivos de pérdida",
                subtitle: "Dónde se rompe el proceso realmente",
                accent: RecTone.accent
            )

            if recruit.lossReasons.isEmpty {
                RecEmptyState(
                    symbol: "checkmark.seal.fill",
                    title: "Sin salidas registradas",
                    message: "Nadie ha abandonado el proceso en esta base."
                )
            } else {
                let maxValue = recruit.lossReasons.first?.count ?? 1
                VStack(spacing: 9) {
                    ForEach(recruit.lossReasons, id: \.reason.id) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.reason.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(entry.reason.isActionable ? RecTone.warn : Palette.textMuted)
                                .frame(width: 20)
                            Text(entry.reason.label)
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 132, alignment: .leading)
                                .lineLimit(2)
                            GeometryReader { proxy in
                                let ratio = Double(entry.count) / Double(max(1, maxValue))
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.surfaceRaised)
                                    Capsule()
                                        .fill(entry.reason.isActionable ? RecTone.warn.opacity(0.7) : Palette.textMuted.opacity(0.5))
                                        .frame(width: max(12, proxy.size.width * ratio))
                                        .animation(.smooth(duration: 0.6), value: ratio)
                                }
                            }
                            .frame(height: 14)
                            Text("\(entry.count)")
                                .font(.system(size: 11, weight: .black))
                                .monospacedDigit()
                                .frame(width: 26, alignment: .trailing)
                        }
                    }
                }
                .padding(14)
                .panel()

                Text("Los motivos en ámbar dependen de nosotros: oferta, horarios, distancia y velocidad de respuesta. Los grises dependen del candidato.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Campaigns

    private var campaignsSection: some View {
        VStack(spacing: 14) {
            budgetCard

            VStack(alignment: .leading, spacing: 10) {
                SupSectionHeader(
                    title: "Campañas",
                    subtitle: "Inversión, leads y contrataciones reales",
                    accent: RecTone.accent
                )
                ForEach(recruit.campaignPerformance) { performance in
                    CampaignCard(performance: performance)
                }
            }

            sourceSection
            integrationSection
        }
    }

    private var budgetCard: some View {
        let needed = recruit.projectedVacancies
        let leads = recruit.leadsNeeded(for: needed)
        let budget = recruit.recommendedBudget(for: needed)

        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Presupuesto recomendado",
                subtitle: "Calculado, no activado",
                accent: RecTone.accent
            )
            HStack(spacing: 10) {
                HeadlineFigure(
                    value: budget > 0 ? Fmt.mxn(budget) : "—",
                    caption: "Inversión sugerida",
                    tone: RecTone.accent,
                    detail: "\(leads) leads objetivo"
                )
                HeadlineFigure(
                    value: recruit.costPerLead > 0 ? Fmt.mxn(recruit.costPerLead) : "—",
                    caption: "Costo por lead",
                    tone: RecTone.cool,
                    detail: recruit.costPerHire > 0 ? "\(Fmt.mxn(recruit.costPerHire)) por contratación" : "sin histórico"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Margen de seguridad")
                HStack(spacing: 10) {
                    Button {
                        recruit.setMargin(recruit.marginPct - 5)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(.footnote, weight: .black))
                            .frame(width: 38, height: 38)
                            .background(Palette.surfaceRaised, in: .circle)
                    }
                    .buttonStyle(.plain)

                    Text("\(recruit.marginPct) %")
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)

                    Button {
                        recruit.setMargin(recruit.marginPct + 5)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(.footnote, weight: .black))
                            .frame(width: 38, height: 38)
                            .background(Palette.surfaceRaised, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                Text("Candidatos extra que se inician por encima de la necesidad estadística, para absorber inasistencias y bajas de último momento.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .panelFlat()
        }
        .padding(16)
        .panel()
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Por fuente",
                subtitle: "Qué canal produce conductores, no solo registros",
                accent: RecTone.accent
            )
            ForEach(recruit.sourcePerformance) { performance in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: performance.source.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(performance.source.isPaid ? RecTone.accent : Palette.textMuted)
                            .frame(width: 30, height: 30)
                            .background(
                                (performance.source.isPaid ? RecTone.accent : Palette.textMuted).opacity(0.12),
                                in: .rect(cornerRadius: 10)
                            )
                        Text(performance.source.label)
                            .font(.system(.subheadline, weight: .bold))
                        Spacer(minLength: 4)
                        Text("\(Int((performance.conversion * 100).rounded())) %")
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(performance.conversion >= recruit.conversion ? RecTone.good : RecTone.warn)
                    }
                    HStack(spacing: 8) {
                        DemandFigure(value: "\(performance.leads)", caption: "Leads")
                        DemandFigure(value: "\(performance.hires)", caption: "Contratados", tone: RecTone.good)
                        DemandFigure(
                            value: performance.costPerHire > 0 ? Fmt.mxn(performance.costPerHire) : "Sin costo",
                            caption: "Por contratación"
                        )
                    }
                }
                .padding(13)
                .panel(cornerRadius: 20)
            }
        }
    }

    private var integrationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Integraciones previstas",
                subtitle: "Arquitectura lista, conexiones aún no activas",
                accent: RecTone.accent
            )
            VStack(spacing: 8) {
                ForEach(IntegrationChannel.allCases) { channel in
                    HStack(spacing: 10) {
                        Image(systemName: channel.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                            .frame(width: 28, height: 28)
                            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(channel.label)
                                .font(.system(.footnote, weight: .bold))
                            Text(channel.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Text("PENDIENTE")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.7)
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat(cornerRadius: 14)
                }
            }
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        let metrics = recruit.recruiterMetrics
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SupSectionHeader(
                    title: "Resultados del reclutador",
                    subtitle: "Se mide lo que produce conductores, no el número de llamadas",
                    accent: RecTone.accent
                )
                HStack(spacing: 10) {
                    HeadlineFigure(
                        value: "\(metrics.hires)",
                        caption: "Contrataciones",
                        tone: RecTone.good,
                        detail: "de \(metrics.assignedLeads) leads asignados"
                    )
                    HeadlineFigure(
                        value: "\(metrics.averageHiringDays)",
                        caption: "Días por contratación",
                        tone: RecTone.cool,
                        detail: "del lead al contrato"
                    )
                }
            }
            .padding(16)
            .panel()

            VStack(spacing: 8) {
                MetricLine(
                    label: "Leads asignados",
                    value: "\(metrics.assignedLeads)",
                    detail: "Todo lo que entró a la bandeja"
                )
                MetricLine(
                    label: "Porcentaje contactado",
                    value: "\(Int((metrics.contactRate * 100).rounded())) %",
                    detail: "\(metrics.contacted) leads con contacto registrado",
                    tone: metrics.contactRate >= 0.8 ? RecTone.good : RecTone.warn
                )
                MetricLine(
                    label: "Tiempo promedio de primer contacto",
                    value: Fmt.durationText(metrics.averageFirstContactMinutes),
                    detail: "Compromiso: \(RecruitRules.contactSlaMinutes / 60) horas",
                    tone: metrics.averageFirstContactMinutes <= RecruitRules.contactSlaMinutes ? RecTone.good : RecTone.bad
                )
                MetricLine(
                    label: "Entrevistas realizadas",
                    value: "\(metrics.interviewsDone)",
                    detail: "\(metrics.interviewsScheduled) programadas por delante"
                )
                MetricLine(
                    label: "Asistencia a entrevistas",
                    value: "\(Int((metrics.attendanceRate * 100).rounded())) %",
                    detail: "\(metrics.noShowAppointments) inasistencias registradas",
                    tone: metrics.attendanceRate >= 0.7 ? RecTone.good : RecTone.warn
                )
                MetricLine(
                    label: "Listos para contratar",
                    value: "\(metrics.readyToHire)",
                    detail: "Expediente completo esperando tu firma",
                    tone: RecTone.cool
                )
                MetricLine(
                    label: "Altas firmadas",
                    value: "\(metrics.approved)",
                    detail: "Contrataciones autorizadas por esta mesa",
                    tone: RecTone.good
                )
                MetricLine(
                    label: "Conversión general",
                    value: "\(Int((metrics.conversion * 100).rounded())) %",
                    detail: "Lead → contratación",
                    tone: RecTone.accent
                )
            }

            Text("La productividad no se mide por llamadas hechas: se mide por conductores que llegaron a operar un turno.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
    }
}
