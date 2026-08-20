import SwiftUI

/// Capacidad de personal: the arithmetic that decides whether the station can operate.
/// Required drivers are never typed — they are the active fleet times four blocks.
struct HRCapacityView: View {
    let office: StationOfficeStore

    var body: some View {
        OfficeScreen(title: "Capacidad de personal") {
            headline
            blocks
            unavailable
            incoming
        }
    }

    private var plan: CapacityPlan { office.capacityPlan }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HeadlineFigure(
                    value: "\(plan.activeVehicles)",
                    caption: "Vehículos activos",
                    tone: .primary,
                    detail: "de \(HRRules.maxVehiclesPerStation) de capacidad instalada"
                )
                HeadlineFigure(
                    value: "\(plan.requiredDrivers)",
                    caption: "Conductores requeridos",
                    tone: Palette.info,
                    detail: "\(plan.activeVehicles) × \(HRRules.driversPerVehicle) bloques"
                )
            }

            ProgressTrack(
                value: Double(plan.availableDrivers),
                goal: Double(max(1, plan.requiredDrivers)),
                tone: plan.deficit == 0 ? Palette.volt : Palette.amber,
                marker: Double(plan.hiredDrivers)
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(label: "Contratados", value: "\(plan.hiredDrivers)", hint: "Plantilla firmada", tone: .neutral)
                StatTile(
                    label: "Disponibles reales",
                    value: "\(plan.availableDrivers)",
                    hint: "Pueden tomar turno hoy",
                    tone: .volt
                )
                StatTile(
                    label: "En contratación",
                    value: "\(plan.onboardingDrivers)",
                    hint: "Candidatos en proceso",
                    tone: .info
                )
                StatTile(
                    label: "Déficit operativo",
                    value: "\(plan.deficit)",
                    hint: "Requeridos menos disponibles",
                    tone: plan.deficit > 0 ? .danger : .volt
                )
            }

            Text("Contratado no es lo mismo que disponible: bajas, suspensiones, incapacidades, vacaciones y documentación crítica vencida salen de la cuenta.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    private var blocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Cobertura por turno",
                subtitle: "Cada bloque se cubre por separado, no con la plantilla total"
            )
            ForEach(plan.blocks) { coverage in
                CoverageRow(coverage: coverage)
            }
        }
        .padding(16)
        .panel()
    }

    private var unavailable: some View {
        let people = office.unavailableFiles
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "No disponibles hoy",
                subtitle: "\(people.count) de \(plan.hiredDrivers) contratados"
            )
            if people.isEmpty {
                SupEmptyState(
                    symbol: "checkmark.seal.fill",
                    title: "Plantilla completa",
                    message: "Todos los conductores contratados pueden tomar turno."
                )
            } else {
                ForEach(people) { file in
                    HStack(spacing: 10) {
                        Image(systemName: file.status.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(file.hasCriticalExpired(now: office.now) ? Palette.danger : file.status.tone)
                            .frame(width: 28, height: 28)
                            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.shortName)
                                .font(.system(.footnote, weight: .bold))
                            Text("\(file.block.shortLabel) · \(file.unavailableReason(now: office.now) ?? "—")")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat(cornerRadius: 14)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private var incoming: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Unidades por incorporar",
                subtitle: "Cada unidad nueva pide 4 conductores más"
            )

            HStack(spacing: 10) {
                StatTile(label: "Flotilla futura", value: "\(plan.futureVehicles)", hint: "+\(plan.incomingVehicles) por llegar", tone: .info)
                StatTile(label: "Requeridos futuros", value: "\(plan.futureRequired)", hint: "Con la flotilla completa", tone: .neutral)
                StatTile(
                    label: "Necesidad futura",
                    value: "\(plan.futureDeficit)",
                    hint: "Descontando proceso actual",
                    tone: plan.futureDeficit > 0 ? .danger : .volt
                )
            }

            ForEach(office.incorporations) { incorporation in
                IncorporationRow(incorporation: incorporation, now: office.now)
            }
        }
        .padding(16)
        .panel()
    }
}

/// One purchase batch on its way to the station.
struct IncorporationRow: View {
    let incorporation: VehicleIncorporation
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: incorporation.stage.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(incorporation.stage.tone)
                Text("\(incorporation.units) × \(incorporation.model)")
                    .font(.system(.footnote, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatePill(text: incorporation.stage.label, symbol: incorporation.stage.symbol, tone: incorporation.stage.tone, compact: true)
            }

            HStack(spacing: 14) {
                Label("Llega \(Fmt.dateShort(incorporation.arrivalAt))", systemImage: "shippingbox.fill")
                Label("Opera \(Fmt.dateShort(incorporation.operationStartAt))", systemImage: "bolt.car.fill")
            }
            .font(.system(size: 10))
            .foregroundStyle(Palette.textMuted)

            HStack(spacing: 6) {
                Text("\(incorporation.requiredDrivers) conductores")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Palette.canvas)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.volt, in: .capsule)
                Text("en \(incorporation.daysToOperation(now: now)) días")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
            }

            if !incorporation.note.isEmpty {
                Text(incorporation.note)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat()
    }
}

// Planeación de reclutamiento vive ahora en la mesa de reclutamiento de la estación:
// es ella quien decide cuándo empezar a buscar para cada llegada de unidades.
