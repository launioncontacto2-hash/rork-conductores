import SwiftUI

/// Regions and their stations. Direction compares, it does not operate: from here it can
/// only read the station and see who answers for it.
struct NationalRegionsView: View {
    let national: NationalStore
    let header: NationalHeader
    let onOpenRegion: (String) -> Void
    let onOpenStation: (String) -> Void

    private enum Sorting: String, CaseIterable, Identifiable {
        case performance
        case risk
        case fleet

        var id: String { rawValue }

        var label: String {
            switch self {
            case .performance: "Desempeño"
            case .risk: "Riesgo"
            case .fleet: "Flotilla"
            }
        }

        var symbol: String {
            switch self {
            case .performance: "chart.line.uptrend.xyaxis"
            case .risk: "exclamationmark.triangle.fill"
            case .fleet: "car.2.fill"
            }
        }
    }

    @State private var sorting: Sorting = .performance

    /// Instant the ranking is measured against. `.minute`, inherited from `rollups`: a
    /// region's health counts the requests that have gone stale on it.
    @State private var minuteAnchor: Date = AppClock.now()

    private var regions: [RegionRollup] {
        switch sorting {
        case .performance: national.rollupsByPerformance(now: minuteAnchor)
        case .risk: national.rollupsByRisk(now: minuteAnchor)
        case .fleet: national.rollups(now: minuteAnchor).sorted { $0.fleetSize > $1.fleetSize }
        }
    }

    var body: some View {
        ZStack {
            NationalBackground()
            ScrollView {
                VStack(spacing: 14) {
                    header

                    HStack(spacing: 8) {
                        ForEach(Sorting.allCases) { option in
                            let isSelected = option == sorting
                            Button {
                                sorting = option
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: option.symbol)
                                        .font(.system(size: 11, weight: .bold))
                                    Text(option.label)
                                        .font(.system(.footnote, weight: .bold))
                                }
                                .foregroundStyle(isSelected ? Palette.canvas : Palette.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(isSelected ? NatTone.accent : Palette.surface.opacity(0.85), in: .capsule)
                                .overlay {
                                    Capsule().stroke(isSelected ? .clear : Palette.hairline, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                        VStack(spacing: 10) {
                            RegionCard(rank: index + 1, region: region) { onOpenRegion(region.id) }

                            ForEach(region.stations) { station in
                                StationLine(station: station) { onOpenStation(station.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            ClockAnchor(.minute, date: $minuteAnchor)
        }
    }
}

/// Compact station line under its region.
struct StationLine: View {
    let station: StationScorecard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(station.health.tone)
                    .frame(width: 30, height: 30)
                    .background(station.health.tone.opacity(0.13), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(station.name)
                            .font(.system(.footnote, weight: .bold))
                            .lineLimit(1)
                        if station.isLive {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(NatTone.good)
                        }
                    }
                    Text("\(station.code) · \(station.fleetSize) unidades · \(station.payrollSize) de plantilla")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(Int(station.goalRatio * 100))%")
                    .font(.system(size: 12, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(station.goalRatio >= RegionalRules.goalFloor ? NatTone.good : NatTone.bad)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(11)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Region detail

/// Everything direction can read about a region without stepping into its operation.
struct NationalRegionDetailView: View {
    let national: NationalStore
    let regionId: String
    let onOpenStation: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Instant this file is measured against. `.minute`, inherited from `rollup`.
    @State private var minuteAnchor: Date = AppClock.now()

    private var region: RegionRollup? { national.rollup(id: regionId, now: minuteAnchor) }

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                if let region {
                    ScrollView {
                        VStack(spacing: 14) {
                            summary(region)
                            managerCard(region)
                            meters(region)
                            stations(region)
                            attention(region)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    Text("Región no disponible")
                        .font(.footnote)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .navigationTitle(region?.name ?? "Región")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .background {
            ClockAnchor(.minute, date: $minuteAnchor)
        }
        .preferredColorScheme(.dark)
    }

    private func summary(_ region: RegionRollup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    CapsLabel(text: "Facturación del turno")
                    Text(Fmt.mxn(region.earningsMxn))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(region.goalRatio >= NationalRules.regionGoalFloor ? NatTone.good : NatTone.bad)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("Meta del turno \(Fmt.mxn(region.goalMxn)) · \(region.tripsToday) viajes")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                HealthBadge(health: region.health)
            }
            ProgressTrack(value: region.goalRatio, goal: 1, tone: NatTone.accent)
                .frame(height: 8)
        }
        .padding(16)
        .panel()
    }

    /// A region has no manager of its own: each of its stations runs itself. What
    /// direction needs to see is whether any station is operating without one.
    private func managerCard(_ region: RegionRollup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Gerencias de la región")
            HStack(spacing: 12) {
                Image(systemName: region.isFullyManaged ? "chart.bar.xaxis" : "person.crop.circle.badge.questionmark")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(region.isFullyManaged ? NatTone.accent : NatTone.bad)
                    .frame(width: 38, height: 38)
                    .background((region.isFullyManaged ? NatTone.accent : NatTone.bad).opacity(0.13), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.managementLabel)
                        .font(.system(.subheadline, weight: .bold))
                    Text(region.isFullyManaged
                        ? "Cada estación autoriza sus propias altas, bonos, créditos y bajas"
                        : "Sin gerente: \(region.stationsWithoutManager.joined(separator: ", ")) no puede autorizar nada")
                        .font(.caption2)
                        .foregroundStyle(region.isFullyManaged ? Palette.textMuted : NatTone.bad)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
                InfoChip(symbol: "checkmark.seal.fill", text: "\(region.pendingApprovals) por firmar", tone: Palette.textMuted)
                if region.agingApprovals > 0 {
                    InfoChip(symbol: "hourglass", text: "\(region.agingApprovals) detenidas", tone: NatTone.bad)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func meters(_ region: RegionRollup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Indicadores", subtitle: "Comparables con el resto del país")
            MeterRow(
                label: "Meta del turno",
                value: "\(Int(region.goalRatio * 100))%",
                ratio: region.goalRatio,
                tone: NatTone.accent,
                marker: 1
            )
            MeterRow(
                label: "Plantilla contra flotilla",
                value: "\(region.payrollSize)/\(region.requiredDrivers)",
                ratio: region.staffingRatio,
                tone: region.driverDeficit == 0 ? NatTone.good : NatTone.warn,
                marker: 1
            )
            MeterRow(
                label: "Asistencia del bloque",
                value: "\(Int(region.attendanceRatio * 100))%",
                ratio: region.attendanceRatio,
                tone: region.attendanceRatio >= 0.94 ? NatTone.good : NatTone.warn,
                marker: 1
            )
            MeterRow(
                label: "Unidades en calle",
                value: "\(region.operatingVehicles)/\(region.fleetSize)",
                ratio: region.utilizationRatio,
                tone: NatTone.cool,
                marker: 1
            )
        }
        .padding(16)
        .panel()
    }

    private func stations(_ region: RegionRollup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Estaciones", subtitle: "\(region.stationCount) en la región")
            ForEach(region.stations) { station in
                StationLine(station: station) { onOpenStation(station.id) }
            }
        }
    }

    private func attention(_ region: RegionRollup) -> some View {
        Group {
            if !region.stationsNeedingAttention.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SupSectionHeader(title: "Requieren seguimiento", subtitle: "Dirección informa, gerencia interviene")
                    ForEach(region.stationsNeedingAttention) { station in
                        NoticeBanner(
                            symbol: station.health.symbol,
                            title: "\(station.name) · \(station.health.label)",
                            message: "\(Int(station.goalRatio * 100))% de meta · \(station.absentDrivers) ausencias · \(station.inMaintenance + station.outOfService) unidades detenidas.",
                            tone: station.health == .critical ? .danger : .amber
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Station detail

/// Read-only station file for direction: the numbers and who holds each shift.
struct NationalStationDetailView: View {
    let national: NationalStore
    let stationId: String

    @Environment(\.dismiss) private var dismiss

    private var station: StationScorecard? { national.station(id: stationId) }

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                if let station {
                    ScrollView {
                        VStack(spacing: 14) {
                            headline(station)
                            grid(station)
                            staff(station)
                            portfolio(station)
                            note
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    Text("Estación no disponible")
                        .font(.footnote)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .navigationTitle(station?.name ?? "Estación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func headline(_ station: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    CapsLabel(text: "\(station.code) · \(station.city)")
                    Text(Fmt.mxn(station.earningsMxn))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(station.goalRatio >= RegionalRules.goalFloor ? NatTone.good : NatTone.bad)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("\(Int(station.goalRatio * 100))% de \(Fmt.mxn(station.goalMxn)) · \(station.vehicleCapacity) × \(Fmt.mxn(station.driverGoalMxn)) · turno \(station.slot.label.lowercased())")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                HealthBadge(health: station.health)
            }
            SparkBars(values: station.weekEarnings, tone: NatTone.accent)
                .frame(height: 26)
        }
        .padding(16)
        .panel()
    }

    private func grid(_ station: StationScorecard) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NatFigure(
                value: "\(station.fleetSize)",
                caption: "Unidades",
                detail: "\(station.inMaintenance) en taller · \(station.outOfService) fuera",
                tone: NatTone.cool
            )
            NatFigure(
                value: "\(station.payrollSize)",
                caption: "Plantilla",
                detail: "requiere \(HRRules.requiredDrivers(activeVehicles: station.fleetSize))",
                tone: station.payrollSize >= HRRules.requiredDrivers(activeVehicles: station.fleetSize) ? NatTone.good : NatTone.warn
            )
            NatFigure(
                value: "\(station.presentDrivers)/\(station.rosterSize)",
                caption: "Asistencia del bloque",
                detail: "\(station.lateDrivers) con atraso",
                tone: station.attendanceRatio >= 0.94 ? NatTone.good : NatTone.warn
            )
            NatFigure(
                value: "\(Int(station.punctualityPct))%",
                caption: "Puntualidad",
                detail: "Calificación \(Fmt.rating(station.ratingAvg))",
                tone: station.punctualityPct >= 90 ? NatTone.good : NatTone.warn
            )
        }
    }

    private func staff(_ station: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Supervisión", subtitle: "Quien responde por cada bloque")
            ForEach(national.supervisors(stationId: station.id)) { supervisor in
                SupervisorRow(card: supervisor)
            }
        }
    }

    private func portfolio(_ station: StationScorecard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Programas", subtitle: "Crédito y bonos de la estación")
            HStack(spacing: 10) {
                NatFigure(
                    value: "\(station.creditPortfolio)",
                    caption: "Créditos",
                    detail: "\(station.creditBehind) con atraso · \(station.creditDelivered) entregados",
                    tone: station.creditBehind > 0 ? NatTone.warn : NatTone.good
                )
                NatFigure(
                    value: "\(station.bonusAtRisk)",
                    caption: "Bonos en riesgo",
                    detail: "\(station.bonusEligible) elegibles este mes",
                    tone: station.bonusAtRisk > 0 ? NatTone.warn : NatTone.good
                )
            }
        }
    }

    private var note: some View {
        NoticeBanner(
            symbol: "eye.fill",
            title: "Lectura de dirección",
            message: "Dirección no interviene en la operación de una estación: lo que aquí se detecta baja al gerente de esa estación, que es quien autoriza y corrige.",
            tone: .info
        )
    }
}
