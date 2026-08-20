import SwiftUI

/// Vacancies of this station, block by block, plus the units already bought that will
/// demand more drivers. This is the origin of everything: unidades × 4 = plantilla.
struct RecruitVacanciesView: View {
    let recruit: RecruitmentStore
    let header: RecruitHeader

    @State private var expanded: Set<String> = []

    private var now: Date { recruit.now }

    var body: some View {
        ZStack {
            RecruitmentBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    ruleCard
                    networkBlocks
                    stationsSection
                    incomingSection
                    plannerCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Rule

    private var ruleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Regla de plantilla")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(recruit.totalActiveVehicles)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(RecTone.accent)
                Text("unidades")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                Text("×4")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textMuted)
                Text("=")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Palette.textMuted)
                Text("\(recruit.totalRequired)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(RecTone.accent)
                Text("conductores")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)

            Text("Matutino y vespertino, entre semana y fin de semana. Ninguna vacante de esta pantalla se escribe a mano: todas salen de la flotilla instalada en tu estación y de sus expedientes activos.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: - Blocks

    private var networkBlocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Cobertura por turno",
                subtitle: "Los cuatro bloques de tu estación",
                accent: RecTone.accent
            )
            ForEach(recruit.networkBlocks) { coverage in
                CoverageRow(coverage: coverage)
            }
        }
    }

    // MARK: - Stations

    private var stationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Detalle de la estación",
                subtitle: "Toca la tarjeta para abrir sus cuatro bloques",
                accent: RecTone.accent
            )

            ForEach(recruit.demands.sorted { $0.vacancies > $1.vacancies }) { demand in
                VStack(spacing: 10) {
                    StationDemandCard(demand: demand, now: now) {
                        if expanded.contains(demand.id) {
                            expanded.remove(demand.id)
                        } else {
                            expanded.insert(demand.id)
                        }
                    }

                    if expanded.contains(demand.id) {
                        VStack(spacing: 9) {
                            ForEach(demand.blocks) { coverage in
                                CoverageRow(coverage: coverage)
                            }
                            if let worst = demand.worstBlock, worst.deficit > 0 {
                                Text("El bloque más descubierto es \(worst.block.label.lowercased()): faltan \(worst.deficit) conductores.")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(worst.level.tone)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.smooth(duration: 0.3), value: expanded)
            }
        }
    }

    // MARK: - Incoming units

    private var incomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Unidades por incorporarse",
                subtitle: "Cada unidad nueva exige cuatro conductores nuevos",
                accent: RecTone.accent
            )

            if recruit.upcomingIncorporations.isEmpty {
                RecEmptyState(
                    symbol: "bolt.car.fill",
                    title: "Sin incorporaciones programadas",
                    message: "Ninguna estación tiene unidades en compra, traslado o preparación."
                )
            } else {
                ForEach(recruit.upcomingIncorporations) { incorporation in
                    incorporationCard(incorporation)
                }
            }
        }
    }

    private func incorporationCard(_ incorporation: VehicleIncorporation) -> some View {
        let station = StaffDirectory.station(id: incorporation.stationId)
        let days = max(0, incorporation.daysToOperation(now: now))
        let projected = recruit.projectedHires(days: days)
        let gap = max(0, incorporation.requiredDrivers - projected)
        let level = RecruitRules.coverageRisk(
            daysAvailable: days,
            averageHiringDays: recruit.averageHiringDays,
            deficit: gap
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: incorporation.stage.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(incorporation.stage.tone)
                    .frame(width: 32, height: 32)
                    .background(incorporation.stage.tone.opacity(0.14), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(incorporation.units) × \(incorporation.model)")
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text("\(station?.displayName ?? "—") · \(incorporation.stage.label)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 4)
                LevelPill(level: level, compact: true)
            }

            HStack(spacing: 8) {
                DemandFigure(value: "\(days)", caption: "Días para operar", tone: days < recruit.averageHiringDays ? RecTone.bad : RecTone.cool)
                DemandFigure(value: "\(incorporation.requiredDrivers)", caption: "Conductores", tone: RecTone.warn)
                DemandFigure(value: "\(projected)", caption: "Proyección", tone: RecTone.cool)
                DemandFigure(value: "\(gap)", caption: "Déficit", tone: gap > 0 ? RecTone.bad : RecTone.good)
            }

            Text(riskSentence(days: days, gap: gap, needed: incorporation.requiredDrivers))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(level.tone)
                .fixedSize(horizontal: false, vertical: true)

            Text("Fecha prevista de operación: \(Fmt.dateLong(incorporation.operationStartAt)). \(incorporation.note)")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 22)
    }

    private func riskSentence(days: Int, gap: Int, needed: Int) -> String {
        guard gap > 0 else {
            return "El ritmo actual de contratación cubre estas \(needed) plazas antes de la fecha de operación."
        }
        if days < recruit.averageHiringDays {
            return "Riesgo de cobertura: quedan \(days) días y contratar toma \(recruit.averageHiringDays). Déficit proyectado de \(gap) conductores; la capacidad actual de reclutamiento no alcanza."
        }
        return "Faltan \(gap) conductores respecto a la proyección. Hay que abrir más leads esta semana para llegar a tiempo."
    }

    // MARK: - Planner

    private var plannerCard: some View {
        let needed = recruit.projectedVacancies
        let leads = recruit.leadsNeeded(for: needed)
        let budget = recruit.recommendedBudget(for: needed)

        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "De vacantes a leads",
                subtitle: "La conversión histórica traduce plazas en candidatos",
                accent: RecTone.accent
            )

            VStack(spacing: 8) {
                MetricLine(label: "Contrataciones requeridas", value: "\(needed)", detail: "Vacantes de hoy más las que traen las unidades compradas", tone: RecTone.warn)
                MetricLine(label: "Conversión lead → contratación", value: "\(Int((recruit.conversion * 100).rounded())) %", detail: "Calculada sobre la base real", tone: RecTone.cool)
                MetricLine(label: "Leads necesarios", value: "\(leads)", detail: "Incluye \(recruit.marginPct) % de margen de seguridad", tone: RecTone.accent)
                MetricLine(
                    label: "Presupuesto estimado",
                    value: budget > 0 ? Fmt.mxn(budget) : "—",
                    detail: recruit.costPerLead > 0
                        ? "A un costo promedio de \(Fmt.mxn(recruit.costPerLead)) por lead"
                        : "Sin histórico de costo por lead todavía",
                    tone: RecTone.good
                )
            }

            Text("Solo es una recomendación. Esta versión no activa, aumenta ni modifica campañas publicitarias de forma automática.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .panel()
    }
}
