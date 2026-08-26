import SwiftUI

/// Expediente: the full file of the manager's own station — identity, the people who
/// hold each shift and the recruitment desk that fills its vacancies.
struct ManagerStationsView: View {
    let regional: RegionalStore
    let header: ManagerHeader
    let onOpenStation: (String) -> Void

    /// Instant the counters of this screen are measured against. `.minute`, because
    /// `metrics` counts requests that go stale twenty-four hours after an arbitrary hour.
    @State private var minuteAnchor: Date = AppClock.now()

    private var station: Station { regional.station }

    var body: some View {
        ZStack {
            ManagementBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    summary

                    SupSectionHeader(
                        title: "Expediente de \(station.code)",
                        subtitle: "Meta, asistencia, flotilla y calidad en un solo índice",
                        accent: MgTone.accent
                    )

                    if let card = regional.card {
                        StationRankCard(rank: 1, card: card) { onOpenStation(card.id) }
                    } else {
                        SupEmptyState(
                            symbol: "building.2",
                            title: "Estación sin datos",
                            message: "Tu estación aún no tiene operación registrada en este bloque.",
                            accent: MgTone.accent
                        )
                    }

                    capacity
                    recruitmentDesk
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            ClockAnchor(.minute, date: $minuteAnchor)
        }
    }

    private var summary: some View {
        let metrics = regional.metrics(now: minuteAnchor)
        return HStack(spacing: 10) {
            StatTile(
                label: "Unidades",
                value: "\(metrics.fleetSize)",
                hint: "\(metrics.operatingVehicles) en ruta",
                tone: .neutral
            )
            StatTile(
                label: "Detenidas",
                value: "\(metrics.idleVehicles)",
                hint: "Taller y fuera de servicio",
                tone: metrics.idleVehicles > 14 ? .danger : .neutral
            )
            StatTile(
                label: "Plantilla",
                value: "\(metrics.payrollSize)",
                hint: "de \(station.requiredDrivers) requeridos",
                tone: metrics.payrollSize < station.requiredDrivers ? .amber : .volt
            )
        }
    }

    /// The arithmetic the whole network runs on, stated plainly for the one person who
    /// answers for it: installed units × 4 blocks = drivers this station must hold.
    private var capacity: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Capacidad instalada")
            DetailRow(label: "Unidades en la estación", value: "\(station.vehicleCapacity)")
            DetailRow(label: "Turnos por unidad", value: "4 bloques")
            DetailRow(label: "Conductores requeridos", value: "\(station.requiredDrivers)")
            DetailRow(
                label: "Meta por turno entre semana",
                value: Fmt.mxn(ShiftRules.stationShiftGoalMxn(capacity: station.vehicleCapacity, group: .weekday))
            )
            DetailRow(
                label: "Meta por turno fin de semana",
                value: Fmt.mxn(ShiftRules.stationShiftGoalMxn(capacity: station.vehicleCapacity, group: .weekend))
            )
            DetailRow(
                label: "Faltantes",
                value: "\(max(0, station.requiredDrivers - regional.metrics(now: minuteAnchor).payrollSize))"
            )
            Text("Cada unidad instalada sostiene cuatro turnos. Si la plantilla baja de ese número, la estación deja unidades paradas aunque estén en buen estado.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    /// Recruitment belongs to the station, so the manager sees exactly whose desk fills
    /// their vacancies instead of escalating to a shared service.
    @ViewBuilder
    private var recruitmentDesk: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Reclutamiento de la estación")
            if let contact = regional.staffDirectory.first(where: { $0.desk == .recruitment }) {
                StationContactRow(contact: contact)
                Text("Cubre y firma las altas de \(station.code). El directorio completo de la plantilla está en Personal.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            } else {
                Text("Esta estación aún no tiene mesa de reclutamiento asignada. Dirección nacional debe crearla para que las vacantes se cubran.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(16)
        .panel()
    }
}

// MARK: - Detail

/// Station file the manager opens from the ranking. Read-only: the manager compares and
/// decides, the supervisor is the one who operates.
struct ManagerStationDetailView: View {
    let regional: RegionalStore
    let stationId: String
    let onOpenRequest: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var card: StationScorecard? { regional.station(id: stationId) }

    var body: some View {
        NavigationStack {
            ZStack {
                ManagementBackground()

                if let card {
                    ScrollView {
                        VStack(spacing: 14) {
                            identity(card)
                            money(card)
                            people(card)
                            fleet(card)
                            programs(card)
                            requests(card)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    SupEmptyState(
                        symbol: "building.2",
                        title: "Estación no disponible",
                        message: "Este expediente no pertenece a tu estación.",
                        accent: MgTone.accent
                    )
                    .padding(18)
                }
            }
            .navigationTitle(card?.code ?? "Estación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func identity(_ card: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .font(.title3)
                    .foregroundStyle(MgTone.accent)
                    .frame(width: 48, height: 48)
                    .background(MgTone.accent.opacity(0.14), in: .rect(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name)
                        .font(.system(.headline, weight: .black))
                    Text("\(card.code) · \(card.city)")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
                HealthBadge(health: card.health)
            }

            if card.isLive {
                NoticeBanner(
                    symbol: "antenna.radiowaves.left.and.right",
                    title: "Operación en vivo",
                    message: "Los movimientos que el conductor y el supervisor registran en esta estación se reflejan aquí al instante.",
                    tone: .volt
                )
            }

            Divider().overlay(Palette.hairline)

            DetailRow(label: "Turno observado", value: "\(card.slot.label) · \(card.slot.rangeLabel)")
            DetailRow(label: "Capacidad", value: "\(card.fleetSize) unidades · 4 turnos")
            DetailRow(label: "Plantilla", value: "\(card.payrollSize) conductores")
            DetailRow(label: "Calificación de plataforma", value: Fmt.rating(card.ratingAvg))
            DetailRow(label: "Índice de salud", value: "\(Int(card.healthScore * 100)) / 100")
        }
        .padding(16)
        .panel()
    }

    private func money(_ card: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Facturación")
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.mxn(card.earningsMxn))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(card.goalRatio >= RegionalRules.goalFloor ? MgTone.good : MgTone.bad)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("Meta fija del turno \(Fmt.mxn(card.goalMxn))")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                SparkBars(values: card.weekEarnings, tone: MgTone.accent)
                    .frame(width: 96)
            }
            ProgressTrack(value: card.goalRatio, goal: 1, tone: MgTone.accent)
                .frame(height: 8)

            DetailRow(
                label: "Cómo se calcula",
                value: "\(card.vehicleCapacity) × \(Fmt.mxn(card.driverGoalMxn))"
            )
            DetailRow(label: "Meta del día (2 turnos)", value: Fmt.mxn(card.dayGoalMxn))
            DetailRow(label: "Meta de la semana", value: Fmt.mxn(card.weekGoalMxn))

            HStack(spacing: 10) {
                StatTile(label: "Falta hoy", value: Fmt.mxn(card.goalGapMxn), hint: "Para cerrar el turno", tone: card.goalGapMxn == 0 ? .volt : .amber)
                StatTile(label: "Semana", value: Fmt.mxn(card.weekEarningsMxn), hint: "\(Int(card.weekGoalRatio * 100))% de meta", tone: .neutral)
                StatTile(label: "Viajes", value: "\(card.tripsToday)", hint: "Del turno en curso", tone: .info)
            }

            Text("La meta no depende de cuántos conductores se presentaron: son las \(card.vehicleCapacity) unidades autorizadas por \(Fmt.mxn(card.driverGoalMxn)) de meta diaria \(card.goalGroup == .weekend ? "de fin de semana" : "entre semana").")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    private func people(_ card: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Conductores del turno")
            MeterRow(
                label: "Asistencia",
                value: "\(card.presentDrivers)/\(card.rosterSize)",
                ratio: card.attendanceRatio,
                tone: card.attendanceRatio >= 0.94 ? MgTone.good : MgTone.accent
            )
            MeterRow(
                label: "Puntualidad de la semana",
                value: "\(Int(card.punctualityPct))%",
                ratio: card.punctualityPct / 100,
                tone: card.punctualityPct >= 90 ? MgTone.good : MgTone.accent
            )
            MeterRow(
                label: "Cuidado de unidad",
                value: "\(Int(card.carePct))%",
                ratio: card.carePct / 100,
                tone: card.carePct >= 90 ? MgTone.good : MgTone.accent
            )

            HStack(spacing: 10) {
                StatTile(label: "Retrasados", value: "\(card.lateDrivers)", tone: card.lateDrivers > 8 ? .danger : .amber)
                StatTile(label: "Ausentes", value: "\(card.absentDrivers)", tone: card.absentDrivers > 5 ? .danger : .neutral)
                StatTile(label: "En fila", value: "\(card.pendingHandovers)", hint: "Entregas por firmar", tone: .info)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Supervisión de la estación")
                ForEach(regional.supervisors(stationId: card.id)) { supervisor in
                    SupervisorRow(card: supervisor)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func fleet(_ card: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Flotilla")
            MeterRow(
                label: "Unidades disponibles para turno",
                value: "\(Int(card.availabilityRatio * 100))%",
                ratio: card.availabilityRatio,
                tone: card.availabilityRatio >= RegionalRules.availabilityFloor ? MgTone.good : MgTone.bad
            )
            HStack(spacing: 10) {
                StatTile(label: "En ruta", value: "\(card.operatingVehicles)", tone: .volt)
                StatTile(label: "Libres", value: "\(card.availableVehicles)", tone: .info)
            }
            HStack(spacing: 10) {
                StatTile(label: "En taller", value: "\(card.inMaintenance)", tone: card.inMaintenance >= RegionalRules.maintenanceBacklogCeiling ? .danger : .amber)
                StatTile(label: "Fuera de servicio", value: "\(card.outOfService)", tone: card.outOfService > 3 ? .danger : .neutral)
            }

            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(text: "Mantenimiento asignado")
                ForEach(regional.maintenance(stationId: card.id), id: \.id) { technician in
                    StaffLineRow(
                        name: technician.name,
                        detail: "Taller \(card.code) · turno \(technician.slot.label.lowercased())",
                        symbol: "wrench.and.screwdriver.fill",
                        tone: Palette.ember
                    )
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func programs(_ card: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Programas")
            HStack(spacing: 10) {
                StatTile(label: "Créditos activos", value: "\(card.creditCurrent)", tone: .info)
                StatTile(label: "Con atraso", value: "\(card.creditBehind)", tone: card.creditBehind > 3 ? .danger : .neutral)
                StatTile(label: "Entregadas", value: "\(card.creditDelivered)", hint: "Mes 24 cumplido", tone: .volt)
            }
            HStack(spacing: 10) {
                StatTile(label: "Bonos vigentes", value: "\(card.bonusEligible)", hint: "Van por el corte del mes", tone: .volt)
                StatTile(label: "Bonos en riesgo", value: "\(card.bonusAtRisk)", hint: "Una semana fallida los cancela", tone: .amber)
            }
            Text("Los bonos se evalúan cada semana y se pagan al cierre del mes: basta una semana incumplida para perder el periodo completo.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    @ViewBuilder
    private func requests(_ card: StationScorecard) -> some View {
        let pending = regional.pendingRequests.filter { $0.stationId == card.id }
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Pendientes de esta estación",
                subtitle: "Altas, bonos, créditos y bajas por firmar",
                accent: MgTone.accent
            )
            if pending.isEmpty {
                SupEmptyState(
                    symbol: "checkmark.seal.fill",
                    title: "Nada pendiente",
                    message: "No hay solicitudes de esta estación esperando tu autorización.",
                    accent: MgTone.accent
                )
            } else {
                ForEach(pending) { request in
                    RequestRow(request: request) { onOpenRequest(request.id) }
                }
            }
        }
    }
}
