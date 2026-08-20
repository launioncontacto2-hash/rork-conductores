import SwiftUI

nonisolated enum VehicleFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case available
    case operating
    case maintenance
    case outOfService

    var id: String { rawValue }

    var state: FleetVehicleState? {
        switch self {
        case .all: nil
        case .available: .available
        case .operating: .operating
        case .maintenance: .maintenance
        case .outOfService: .outOfService
        }
    }

    var label: String { state?.label ?? "Todas" }
    var symbol: String { state?.symbol ?? "square.grid.2x2.fill" }

    static func from(_ state: FleetVehicleState?) -> VehicleFilter {
        allCases.first { $0.state == state } ?? .all
    }
}

/// Vehículos: the station fleet board, one card per unit.
struct SupervisorVehiclesView: View {
    let supervision: SupervisionStore
    let header: SupervisorHeader
    @Binding var filter: VehicleFilter
    let onOpenVehicle: (String) -> Void

    @State private var search: String = ""

    private var rows: [StationVehicle] { supervision.vehicles(matching: filter.state, search: search) }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                        TextField("Número interno, placas o conductor", text: $search)
                            .font(.subheadline)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if !search.isEmpty {
                            Button {
                                search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Palette.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .panelFlat()

                    FilterScroller(
                        items: VehicleFilter.allCases,
                        title: { $0.label },
                        symbol: { $0.symbol },
                        count: { supervision.vehicles(matching: $0.state).count },
                        selection: $filter
                    )
                    .padding(.horizontal, -18)

                    HStack {
                        Text("\(rows.count) unidades")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                        Spacer()
                        Text("Capacidad \(supervision.station.vehicleCapacity) por turno")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                    }

                    if rows.isEmpty {
                        SupEmptyState(
                            symbol: filter.symbol,
                            title: "Sin unidades en este estado",
                            message: "Cambia el filtro para revisar el resto de la flotilla."
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(rows) { vehicle in
                                VehicleCard(vehicle: vehicle) { onOpenVehicle(vehicle.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct VehicleCard: View {
    let vehicle: StationVehicle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Color.black
                        .frame(width: 66, height: 52)
                        .overlay {
                            Image(vehicle.photoAsset)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .opacity(0.85)
                                .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12).stroke(vehicle.state.tone.opacity(0.5), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(vehicle.internalNumber)
                            .font(.system(.subheadline, weight: .black))
                        Text("\(vehicle.model) · \(vehicle.plates)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                        StatePill(text: vehicle.state.label, symbol: vehicle.state.symbol, tone: vehicle.state.tone)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        BatteryPill(level: vehicle.batteryPct)
                        Text("Bahía \(vehicle.bay)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                    }
                }

                HStack(spacing: 8) {
                    InfoChip(symbol: "gauge.with.dots.needle.bottom.50percent", text: Fmt.km(vehicle.odometerKm), tone: Palette.textMuted)
                    InfoChip(
                        symbol: "wrench.and.screwdriver.fill",
                        text: vehicle.maintenance.label,
                        tone: vehicle.maintenance.tone
                    )
                    if let name = vehicle.assignedDriverName {
                        InfoChip(symbol: "person.fill", text: Fmt.firstName(name), tone: SupTone.accent)
                    } else if vehicle.state == .available {
                        InfoChip(symbol: "person.badge.plus", text: "Libre", tone: SupTone.good)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .padding(14)
            .panel(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

/// Unit file with the actions that block or release a vehicle.
struct SupervisorVehicleDetailView: View {
    let supervision: SupervisionStore
    let vehicleId: String
    let onReportIncident: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workshopNote: String = ""
    @State private var filing: DossierDocument?
    @State private var dossierVersion: Int = 0

    private var vehicle: StationVehicle? { supervision.vehicle(id: vehicleId) }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                if let vehicle {
                    ScrollView {
                        VStack(spacing: 14) {
                            hero(vehicle)
                            readings(vehicle)
                            documentsCard(vehicle)
                            maintenanceCard(vehicle)
                            actions(vehicle)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    SupEmptyState(
                        symbol: "car.fill.badge.xmark",
                        title: "Unidad no disponible",
                        message: "El vehículo ya no pertenece a esta estación."
                    )
                    .padding(20)
                }
            }
            .navigationTitle("Unidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $filing) { kind in
                if let vehicle {
                    DossierFilingSheet(
                        kind: kind,
                        subjectId: vehicle.id,
                        subjectLabel: "\(vehicle.internalNumber) · \(vehicle.model)",
                        deskName: supervision.account.name,
                        now: supervision.now,
                        onSaved: { dossierVersion += 1 }
                    )
                }
            }
        }
        .presentationContentInteraction(.scrolls)
    }

    /// The papers of the unit live here: supervision is the only desk that files them,
    /// and the driver reads them from the road when somebody asks for them.
    private func documentsCard(_ vehicle: StationVehicle) -> some View {
        let filed = DossierDocument.vehicleFile.map { kind in
            (kind, DossierBook.document(kind: kind, subjectId: vehicle.id))
        }
        let pending = filed.filter { $0.1 == nil }.count

        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Documentos de la unidad",
                subtitle: pending == 0 ? "Expediente completo" : "\(pending) por cargar"
            )

            ForEach(DossierDocument.vehicleFile) { kind in
                DossierDeskRow(
                    kind: kind,
                    document: filed.first { $0.0 == kind }?.1,
                    now: supervision.now,
                    accent: SupTone.accent
                ) {
                    filing = kind
                }
            }

            Text("El conductor los consulta desde su reporte de incidencia. La factura se muestra siempre con marca de agua «Copia sin valor fiscal».")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(dossierVersion)
        .padding(16)
        .panel()
    }

    private func hero(_ vehicle: StationVehicle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.black
                .frame(height: 168)
                .overlay {
                    Image(vehicle.photoAsset)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 20))
                .overlay(alignment: .topLeading) {
                    StatePill(text: vehicle.state.label, symbol: vehicle.state.symbol, tone: vehicle.state.tone)
                        .padding(12)
                }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicle.internalNumber)
                        .font(.system(.title3, weight: .black))
                    Text("\(vehicle.model) · \(vehicle.plates)")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer()
                BatteryPill(level: vehicle.batteryPct)
            }
        }
        .padding(14)
        .panel()
    }

    private func readings(_ vehicle: StationVehicle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Lecturas de la unidad")
            HStack(spacing: 10) {
                StatTile(label: "Kilometraje", value: Fmt.km(vehicle.odometerKm), hint: "Registro de estación", tone: .neutral)
                StatTile(
                    label: "Batería",
                    value: "\(vehicle.batteryPct)%",
                    hint: "Mínimo \(SupervisionRules.minBatteryPct)% para salir",
                    tone: vehicle.batteryPct > SupervisionRules.minBatteryPct ? .volt : .danger
                )
            }
            DetailRow(label: "Bahía", value: "\(vehicle.bay)")
            DetailRow(label: "Conductor asignado", value: vehicle.assignedDriverName ?? "Sin asignar")
            DetailRow(label: "QR leído hoy", value: vehicle.qrScanned ? "Sí" : "No")
        }
        .padding(16)
        .panel()
    }

    private func maintenanceCard(_ vehicle: StationVehicle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Mantenimiento")
            HStack {
                StatePill(text: vehicle.maintenance.label, symbol: "wrench.and.screwdriver.fill", tone: vehicle.maintenance.tone)
                Spacer()
            }
            DetailRow(label: "Próximo servicio", value: Fmt.km(vehicle.nextServiceKm))
            DetailRow(
                label: "Faltan",
                value: vehicle.kmToService > 0 ? Fmt.km(vehicle.kmToService) : "Vencido por \(Fmt.km(-vehicle.kmToService))"
            )
            DetailRow(label: "Último servicio", value: Fmt.dateShort(vehicle.lastServiceAt))
            ProgressTrack(
                value: Double(10_000 - max(0, vehicle.kmToService)),
                goal: 10_000,
                tone: vehicle.maintenance.tone
            )
        }
        .padding(16)
        .panel()
    }

    private func actions(_ vehicle: StationVehicle) -> some View {
        VStack(spacing: 10) {
            TextField("Nota para el encargado de mantenimiento", text: $workshopNote, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(14)
                .panelFlat()

            BigButton(title: "Enviar a mantenimiento", symbol: "wrench.and.screwdriver.fill", tone: .outline) {
                supervision.sendToWorkshop(id: vehicle.id, note: workshopNote)
                workshopNote = ""
                dismiss()
            }

            if vehicle.state == .outOfService {
                BigButton(title: "Liberar unidad a disponible", symbol: "bolt.car.fill") {
                    supervision.setVehicleState(id: vehicle.id, state: .available)
                    dismiss()
                }
            } else {
                BigButton(title: "Marcar fuera de servicio", symbol: "xmark.octagon.fill", tone: .danger) {
                    supervision.setVehicleState(id: vehicle.id, state: .outOfService)
                    dismiss()
                }
            }

            Button {
                dismiss()
                onReportIncident(vehicle.internalNumber)
            } label: {
                Label("Levantar incidencia de esta unidad", systemImage: "exclamationmark.bubble.fill")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(SupTone.accent)
            }
            .buttonStyle(.plain)
        }
    }
}
