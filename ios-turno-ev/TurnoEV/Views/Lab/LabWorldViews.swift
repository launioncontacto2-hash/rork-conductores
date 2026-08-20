import SwiftUI

// MARK: - Stations

/// Creation and life cycle of the physical network. Nothing else can exist before a
/// station does: units, staff and expedients all hang from here.
struct LabStationsView: View {
    @Environment(LabStore.self) private var lab

    @State private var editing: LabStation?
    @State private var isCreating: Bool = false
    @State private var isRegionPresented: Bool = false
    @State private var newRegionName: String = ""
    @State private var pendingDeletion: LabStation?

    var body: some View {
        LabScreen(section: .stations) {
            LabSectionTitle(
                title: "Red física",
                subtitle: "Cada estación define su cupo de unidades y, con eso, cuántos conductores exige la operación.",
                symbol: "building.2.fill"
            )

            regionsCard

            HStack(spacing: 8) {
                Button("Nueva estación") { isCreating = true }
                    .buttonStyle(LabButtonStyle(kind: .solid, isCompact: true))
                    .disabled(lab.world.regions.isEmpty)
                Button("Nueva región") { isRegionPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
            }

            if lab.world.stations.isEmpty {
                LabEmptyState(
                    title: "Sin estaciones",
                    message: lab.world.regions.isEmpty
                        ? "Crea primero una región y después la primera estación de la red."
                        : "Crea la primera estación para que el resto del sistema tenga dónde existir.",
                    symbol: "building.2"
                )
            } else {
                ForEach(lab.world.stations) { station in
                    stationCard(station)
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            LabStationEditor(station: nil)
        }
        .sheet(item: $editing) { station in
            LabStationEditor(station: station)
        }
        .alert("Nueva región", isPresented: $isRegionPresented) {
            TextField("Nombre de la región", text: $newRegionName)
            Button("Crear") {
                lab.addRegion(name: newRegionName)
                newRegionName = ""
            }
            Button("Cancelar", role: .cancel) { newRegionName = "" }
        }
        .confirmationDialog(
            "¿Eliminar \(pendingDeletion?.name ?? "")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar en cascada", role: .destructive) {
                if let id = pendingDeletion?.id { lab.deleteStation(id: id) }
                pendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Se borran también sus unidades, usuarios, expedientes, candidatos, activos y órdenes.")
        }
    }

    private var regionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Regiones")
            if lab.world.regions.isEmpty {
                Text("Todavía no hay regiones. Una región solo agrupa estaciones para los reportes de dirección nacional: no manda sobre ellas.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(lab.world.regions) { region in
                    HStack {
                        LabChip(text: region.name, symbol: "map.fill")
                        Spacer(minLength: 0)
                        Text("\(lab.world.stations.filter { $0.regionId == region.id }.count) estaciones")
                            .font(.caption2)
                            .foregroundStyle(LabTone.muted)
                        Button {
                            lab.deleteRegion(id: region.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption2)
                                .foregroundStyle(LabTone.bad)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .labFlat(cornerRadius: 13)
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    private func stationCard(_ station: LabStation) -> some View {
        let installed = lab.world.installedCount(at: station.id)
        let incoming = lab.world.vehicles(at: station.id).filter { $0.stage.isIncoming }.count
        let drivers = lab.world.users(at: station.id, role: .driver).count
        let required = installed * lab.world.shiftConfig.driversPerVehicle

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.system(.headline, weight: .black))
                        .foregroundStyle(.white)
                    Text("\(station.code) · \(station.city), \(station.state)")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
                Spacer(minLength: 0)
                LabChip(
                    text: station.lifecycle.label,
                    symbol: station.lifecycle.symbol,
                    tint: station.lifecycle.isOperational ? LabTone.good : LabTone.muted
                )
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                LabStat(label: "Unidades", value: "\(installed) / \(station.maxVehicles)", symbol: "car.2.fill")
                LabStat(label: "Por llegar", value: "\(incoming)", tint: incoming > 0 ? LabTone.cool : LabTone.muted, symbol: "truck.box.fill")
                LabStat(
                    label: "Conductores",
                    value: "\(drivers) / \(required)",
                    tint: drivers < required ? LabTone.bad : LabTone.good,
                    symbol: "steeringwheel"
                )
                LabStat(
                    label: "Supervisión",
                    value: "\(lab.world.users(at: station.id, role: .supervisor).count) / \(station.supervisorsRequired)",
                    symbol: "person.2.badge.gearshape.fill"
                )
            }

            LabOptionRow(
                label: "Ciclo de vida",
                options: StationLifecycle.allCases,
                selection: Binding(
                    get: { station.lifecycle },
                    set: { lab.setStationLifecycle(id: station.id, lifecycle: $0) }
                ),
                title: \.label,
                symbol: { $0.symbol }
            )

            HStack(spacing: 8) {
                Button("Editar") { editing = station }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Spacer(minLength: 0)
                Button("Eliminar") { pendingDeletion = station }
                    .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
            }
        }
        .padding(16)
        .labPanel()
    }
}

private struct LabStationEditor: View {
    let station: LabStation?
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var name: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var address: String = ""
    @State private var regionId: String = ""
    @State private var maxVehicles: Int = 20
    @State private var plannedVehicles: Int = 20
    @State private var supervisors: Int = 2
    @State private var maintenance: Int = 1
    @State private var lifecycle: StationLifecycle = .active
    @State private var openedAt: Date = Date()

    private var isValid: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !regionId.isEmpty
    }

    var body: some View {
        LabSheet(
            title: station == nil ? "Nueva estación" : "Editar estación",
            subtitle: "El cupo de unidades es lo que gobierna toda la aritmética de personal: unidades × \(lab.world.shiftConfig.driversPerVehicle) conductores.",
            isConfirmEnabled: isValid,
            onConfirm: save
        ) {
            LabField(label: "Código", placeholder: "NTE-01", text: $code, autocapitalization: .characters)
            LabField(label: "Nombre", placeholder: "Estación Norte", text: $name)
            LabField(label: "Ciudad", placeholder: "CDMX", text: $city)
            LabField(label: "Estado", placeholder: "Ciudad de México", text: $state)
            LabField(label: "Dirección", placeholder: "Av. Insurgentes 100", text: $address)

            LabOptionRow(
                label: "Región",
                options: lab.world.regions.map(\.id),
                selection: $regionId,
                title: { id in lab.world.regions.first { $0.id == id }?.name ?? "—" }
            )

            LabNumberField(label: "Cupo máximo de unidades", value: $maxVehicles, range: 1...HRRules.maxVehiclesPerStation, step: 1, suffix: "unidades")
            LabNumberField(label: "Unidades planeadas", value: $plannedVehicles, range: 0...200, step: 1, suffix: "unidades")
            LabNumberField(label: "Supervisores requeridos", value: $supervisors, range: 0...10)
            LabNumberField(label: "Mantenimiento requerido", value: $maintenance, range: 0...10)

            LabOptionRow(
                label: "Ciclo de vida",
                options: StationLifecycle.allCases,
                selection: $lifecycle,
                title: \.label,
                symbol: { $0.symbol }
            )

            DatePicker("Fecha de apertura", selection: $openedAt, displayedComponents: .date)
                .datePickerStyle(.compact)
                .foregroundStyle(.white)
                .tint(LabTone.accent)
                .padding(12)
                .labFlat()

            VStack(alignment: .leading, spacing: 6) {
                LabCaps(text: "Plantilla que exigirá")
                Text("\(maxVehicles) unidades × \(lab.world.shiftConfig.driversPerVehicle) = \(maxVehicles * lab.world.shiftConfig.driversPerVehicle) conductores al llenar el cupo.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let station else {
            regionId = lab.world.regions.first?.id ?? ""
            return
        }
        code = station.code
        name = station.name
        city = station.city
        state = station.state
        address = station.address
        regionId = station.regionId
        maxVehicles = station.maxVehicles
        plannedVehicles = station.plannedVehicles
        supervisors = station.supervisorsRequired
        maintenance = station.maintenanceRequired
        lifecycle = station.lifecycle
        openedAt = station.openedAt
    }

    private func save() {
        let value = LabStation(
            id: station?.id ?? "labest-\(UUID().uuidString.prefix(8))",
            code: code.trimmingCharacters(in: .whitespaces).uppercased(),
            name: name.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces),
            state: state.trimmingCharacters(in: .whitespaces),
            address: address,
            regionId: regionId,
            openedAt: openedAt,
            maxVehicles: maxVehicles,
            plannedVehicles: plannedVehicles,
            lifecycle: lifecycle,
            driversPerVehicle: lab.world.shiftConfig.driversPerVehicle,
            supervisorsRequired: supervisors,
            maintenanceRequired: maintenance,
            managerId: station?.managerId,
            activeBlocks: station?.activeBlocks ?? ShiftBlock.allCases,
            createdAt: station?.createdAt ?? Date()
        )
        if lab.saveStation(value) { dismiss() }
    }
}

// MARK: - Users

/// Credentials of every role. Creating one here is exactly the same as an alta made by
/// direction or by a supervisor, only the origin is the laboratory.
struct LabUsersView: View {
    @Environment(LabStore.self) private var lab

    @State private var editing: LabUser?
    @State private var isCreating: Bool = false
    @State private var roleFilter: StaffRole?
    @State private var search: String = ""
    @State private var previewTarget: LabUser?

    private var filtered: [LabUser] {
        lab.world.users.filter { user in
            (roleFilter == nil || user.role == roleFilter)
                && (search.isEmpty
                    || user.name.localizedStandardContains(search)
                    || user.employeeNumber.localizedStandardContains(search)
                    || user.email.localizedStandardContains(search))
        }
    }

    var body: some View {
        LabScreen(section: .users) {
            LabSectionTitle(
                title: "Credenciales de la red",
                subtitle: "El rol de la credencial es lo único que abre una interfaz. Aquí puedes generar cualquiera de los seis roles operativos.",
                symbol: "person.badge.key.fill"
            )

            Button("Nuevo usuario") { isCreating = true }
                .buttonStyle(LabButtonStyle(kind: .solid))
                .disabled(lab.world.stations.isEmpty && lab.world.regions.isEmpty)

            if lab.world.stations.isEmpty {
                LabEmptyState(
                    title: "Falta la estación",
                    message: "Conductores, supervisores y mantenimiento necesitan una estación asignada. Crea una antes de generar credenciales operativas.",
                    symbol: "building.2"
                )
            }

            roleSummary

            LabField(label: "Buscar", placeholder: "Nombre, número o correo", text: $search, autocapitalization: .never)

            LabOptionRow(
                label: "Filtro por rol",
                options: [StaffRole?.none] + StaffRole.operationalRoles.map { Optional($0) },
                selection: $roleFilter,
                title: { $0?.shortLabel ?? "Todos" },
                symbol: { $0?.symbol ?? "person.3.fill" }
            )

            if filtered.isEmpty {
                LabEmptyState(
                    title: lab.world.users.isEmpty ? "Sin usuarios" : "Sin resultados",
                    message: lab.world.users.isEmpty
                        ? "No existe ninguna credencial. Crea la primera para poder abrir una interfaz distinta a esta."
                        : "Ningún usuario coincide con el filtro.",
                    symbol: "person.slash"
                )
            } else {
                ForEach(filtered) { user in
                    userCard(user)
                }
            }
        }
        .sheet(isPresented: $isCreating) { LabUserEditor(user: nil) }
        .sheet(item: $editing) { user in LabUserEditor(user: user) }
        .sheet(item: $previewTarget) { user in LabPreviewSheet(user: user) }
    }

    private var roleSummary: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(StaffRole.operationalRoles, id: \.self) { role in
                LabStat(
                    label: role.shortLabel,
                    value: "\(lab.credentials(for: role).count)",
                    tint: lab.credentials(for: role).isEmpty ? LabTone.muted : .white,
                    symbol: role.symbol
                )
            }
        }
    }

    private func userCard(_ user: LabUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Text(user.initials)
                    .font(.system(.caption, weight: .black))
                    .foregroundStyle(LabTone.accent)
                    .frame(width: 38, height: 38)
                    .background(LabTone.accent.opacity(0.12), in: .circle)
                    .overlay { Circle().stroke(LabTone.accent.opacity(0.4), lineWidth: 1) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(user.role.label) · \(user.employeeNumber)")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                    Text(user.email)
                        .font(.caption2)
                        .foregroundStyle(LabTone.muted.opacity(0.8))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    LabChip(
                        text: user.status.label,
                        tint: user.status == .active ? LabTone.good : LabTone.bad
                    )
                    if user.testRole != nil {
                        LabChip(text: "Vista previa", symbol: "eye.fill", tint: LabTone.cool)
                    }
                }
            }

            HStack(spacing: 6) {
                if let stationId = user.stationId, let station = lab.world.station(id: stationId) {
                    LabChip(text: station.code, symbol: "building.2.fill", tint: LabTone.muted)
                }
                if let block = user.block {
                    LabChip(text: block.shortLabel, symbol: block.symbol, tint: LabTone.muted)
                }
                LabChip(text: user.employment.label, symbol: user.employment.symbol, tint: user.employment.canOperate ? LabTone.good : LabTone.bad)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Editar") { editing = user }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("Ver como") { previewTarget = user }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Spacer(minLength: 0)
                Menu {
                    Button(user.status == .active ? "Suspender" : "Reactivar") {
                        lab.setUserStatus(id: user.id, status: user.status == .active ? .suspended : .active)
                    }
                    ForEach(EmploymentStatus.allCases) { status in
                        Button("Situación: \(status.label)") { lab.setEmployment(id: user.id, employment: status) }
                    }
                    Divider()
                    Button("Eliminar", role: .destructive) { lab.deleteUser(id: user.id) }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LabTone.muted)
                }
            }
        }
        .padding(15)
        .labPanel()
    }
}

private struct LabUserEditor: View {
    let user: LabUser?
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var employeeNumber: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var password: String = "Prueba14"
    @State private var role: StaffRole = .driver
    @State private var stationId: String = ""
    @State private var regionId: String = ""
    @State private var block: ShiftBlock = .weekdayMorning
    @State private var employment: EmploymentStatus = .active

    /// Every operational role belongs to a station — the manager and the recruitment
    /// desk included, because a station runs itself.
    private var needsStation: Bool { role.isStationBound }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
            && password.count >= 6
            && (!needsStation || !stationId.isEmpty)
    }

    var body: some View {
        LabSheet(
            title: user == nil ? "Nuevo usuario" : "Editar usuario",
            subtitle: "La credencial se valida como cualquier otra: correo o número de empleado más contraseña.",
            isConfirmEnabled: isValid,
            onConfirm: save
        ) {
            LabOptionRow(
                label: "Rol",
                options: StaffRole.operationalRoles,
                selection: $role,
                title: \.shortLabel,
                symbol: { $0.symbol }
            )

            Text(role.registrationNote)
                .font(.caption)
                .foregroundStyle(LabTone.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            LabField(label: "Nombre completo", placeholder: "Nombre y apellidos", text: $name, autocapitalization: .words)
            LabField(label: "Número de empleado", placeholder: "PRB-0001", text: $employeeNumber, autocapitalization: .characters)
            LabField(label: "Correo", placeholder: "usuario@turnoev.mx", text: $email, keyboard: .emailAddress, autocapitalization: .never)
            LabField(label: "Teléfono", placeholder: "5512345678", text: $phone, keyboard: .phonePad)
            LabField(label: "Contraseña", placeholder: "Mínimo 6 caracteres", text: $password, autocapitalization: .never)

            if needsStation {
                LabOptionRow(
                    label: "Estación",
                    options: lab.world.stations.map(\.id),
                    selection: $stationId,
                    title: { id in lab.world.station(id: id)?.code ?? "—" }
                )

                if role == .manager || role == .recruiter {
                    Text(role == .manager
                        ? "Un gerente dirige una sola estación. Si esa estación ya tiene gerente, el guardado se bloquea."
                        : "Reclutamiento es un departamento de la estación: solo trabaja sus vacantes.")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if role == .driver || role == .supervisor {
                LabOptionRow(
                    label: "Bloque de turno",
                    options: ShiftBlock.allCases,
                    selection: $block,
                    title: \.shortLabel,
                    symbol: { $0.symbol }
                )
            }

            if role == .driver {
                LabOptionRow(
                    label: "Situación laboral",
                    options: EmploymentStatus.allCases,
                    selection: $employment,
                    title: \.label,
                    symbol: { $0.symbol }
                )

                capacityHint
            }
        }
        .onAppear(perform: load)
    }

    private var capacityHint: some View {
        Group {
            if let station = lab.world.station(id: stationId) {
                let installed = lab.world.installedCount(at: station.id)
                let ceiling = installed * lab.world.shiftConfig.driversPerVehicle
                let current = lab.world.users(at: station.id, role: .driver).count
                VStack(alignment: .leading, spacing: 4) {
                    LabCaps(text: "Cupo de la estación")
                    Text("\(current) de \(ceiling) conductores para \(installed) unidades instaladas.")
                        .font(.footnote)
                        .foregroundStyle(current >= ceiling && ceiling > 0 ? LabTone.bad : LabTone.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .labFlat()
            }
        }
    }

    private func load() {
        guard let user else {
            stationId = lab.world.stations.first?.id ?? ""
            regionId = lab.world.regions.first?.id ?? ""
            employeeNumber = "PRB-\(String(format: "%04d", lab.world.users.count + 1))"
            email = "prueba\(lab.world.users.count + 1)@turnoev.mx"
            return
        }
        name = user.name
        employeeNumber = user.employeeNumber
        email = user.email
        phone = user.phone
        password = user.password
        role = user.role
        stationId = user.stationId ?? ""
        regionId = user.regionId ?? ""
        block = user.block ?? .weekdayMorning
        employment = user.employment
    }

    private func save() {
        let value = LabUser(
            id: user?.id ?? "labusr-\(UUID().uuidString.prefix(8))",
            name: name.trimmingCharacters(in: .whitespaces),
            employeeNumber: employeeNumber.trimmingCharacters(in: .whitespaces).uppercased(),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            phone: phone,
            password: password,
            role: role,
            stationId: stationId.isEmpty ? nil : stationId,
            // The region is metadata now: it always follows the station.
            regionId: lab.world.station(id: stationId)?.regionId,
            block: (role == .driver || role == .supervisor) ? block : nil,
            photoData: user?.photoData,
            status: user?.status ?? .active,
            employment: role == .driver ? employment : .active,
            hiredAt: user?.hiredAt ?? Date(),
            driverId: user?.driverId,
            createdAt: user?.createdAt ?? Date(),
            testRole: user?.testRole
        )
        if lab.saveUser(value) { dismiss() }
    }
}

// MARK: - Vehicles

/// Fleet of the network. Every installed unit multiplies the plantilla the stations need,
/// so this screen is the origin of most of the arithmetic in the app.
struct LabVehiclesView: View {
    @Environment(LabStore.self) private var lab

    @State private var editing: LabVehicle?
    @State private var isCreating: Bool = false
    @State private var stageFilter: LabVehicleStage?
    @State private var readingsTarget: LabVehicle?
    @State private var qrTarget: LabVehicle?

    private var filtered: [LabVehicle] {
        lab.world.vehicles.filter { stageFilter == nil || $0.stage == stageFilter }
    }

    var body: some View {
        LabScreen(section: .vehicles) {
            LabSectionTitle(
                title: "Flotilla",
                subtitle: "Alta, ciclo de compra, QR, odómetro y batería. Cada unidad instalada exige \(lab.world.shiftConfig.driversPerVehicle) conductores.",
                symbol: "car.2.fill"
            )

            Button("Nueva unidad") { isCreating = true }
                .buttonStyle(LabButtonStyle(kind: .solid))
                .disabled(lab.world.stations.isEmpty)

            if lab.world.stations.isEmpty {
                LabEmptyState(
                    title: "Falta la estación",
                    message: "Una unidad siempre pertenece a una estación. Crea la estación primero.",
                    symbol: "building.2"
                )
            } else if lab.world.vehicles.isEmpty {
                LabEmptyState(
                    title: "Sin unidades",
                    message: "La flotilla está en cero. Da de alta la primera unidad para que aparezca en supervisión, taller y en el panel del conductor.",
                    symbol: "car"
                )
            } else {
                fleetSummary

                LabOptionRow(
                    label: "Etapa",
                    options: [LabVehicleStage?.none] + LabVehicleStage.allCases.map { Optional($0) },
                    selection: $stageFilter,
                    title: { $0?.label ?? "Todas" },
                    symbol: { $0?.symbol ?? "square.grid.2x2.fill" }
                )

                ForEach(filtered) { vehicle in
                    vehicleCard(vehicle)
                }
            }
        }
        .sheet(isPresented: $isCreating) { LabVehicleEditor(vehicle: nil) }
        .sheet(item: $editing) { vehicle in LabVehicleEditor(vehicle: vehicle) }
        .sheet(item: $readingsTarget) { vehicle in LabReadingsSheet(vehicle: vehicle) }
        .sheet(item: $qrTarget) { vehicle in LabQrSheet(vehicle: vehicle) }
    }

    private var fleetSummary: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            LabStat(label: "Instaladas", value: "\(lab.world.installedVehicles.count)", symbol: "checkmark.circle.fill")
            LabStat(label: "Por llegar", value: "\(lab.world.incomingVehicles.count)", tint: LabTone.cool, symbol: "truck.box.fill")
            LabStat(
                label: "Exigen",
                value: "\(lab.world.requiredDrivers)",
                tint: LabTone.accent,
                symbol: "steeringwheel"
            )
        }
    }

    private func vehicleCard(_ vehicle: LabVehicle) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicle.internalNumber)
                        .font(.system(.headline, weight: .black))
                        .foregroundStyle(.white)
                    Text("\(vehicle.fullModel) · \(vehicle.plates)")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                    Text("VIN \(vehicle.vin)")
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(LabTone.muted.opacity(0.75))
                }
                Spacer(minLength: 0)
                LabChip(text: vehicle.stage.label, symbol: vehicle.stage.symbol, tint: tint(for: vehicle.stage))
            }

            HStack(spacing: 8) {
                LabStat(label: "Odómetro", value: "\(vehicle.odometerKm)", symbol: "gauge.with.needle.fill")
                LabStat(
                    label: "Batería",
                    value: "\(vehicle.batteryPct)%",
                    tint: vehicle.batteryPct < lab.world.shiftConfig.minimumBatteryPct ? LabTone.bad : LabTone.good,
                    symbol: "bolt.fill"
                )
                LabStat(
                    label: "Discrepancia",
                    value: vehicle.odometerGapKm > 0 ? "\(vehicle.odometerGapKm) km" : "—",
                    tint: vehicle.odometerGapKm > 0 ? LabTone.bad : LabTone.muted,
                    symbol: "arrow.triangle.branch"
                )
            }

            LabOptionRow(
                label: "Etapa del ciclo",
                options: LabVehicleStage.allCases,
                selection: Binding(
                    get: { vehicle.stage },
                    set: { lab.setVehicleStage(id: vehicle.id, stage: $0) }
                ),
                title: \.label,
                symbol: { $0.symbol }
            )

            HStack(spacing: 8) {
                Button("Lecturas") { readingsTarget = vehicle }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("QR") { qrTarget = vehicle }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("Editar") { editing = vehicle }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Spacer(minLength: 0)
                Button {
                    lab.deleteVehicle(id: vehicle.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(LabTone.bad)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .labPanel()
    }

    private func tint(for stage: LabVehicleStage) -> Color {
        switch stage {
        case .available, .operating: LabTone.good
        case .maintenance: LabTone.accent
        case .outOfService: LabTone.bad
        default: LabTone.cool
        }
    }
}

private struct LabVehicleEditor: View {
    let vehicle: LabVehicle?
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var internalNumber: String = ""
    @State private var brand: String = "BYD"
    @State private var model: String = "Dolphin Mini"
    @State private var year: Int = 2025
    @State private var vin: String = ""
    @State private var plates: String = ""
    @State private var odometerKm: Int = 0
    @State private var batteryPct: Int = 100
    @State private var rangeKm: Int = 300
    @State private var stationId: String = ""
    @State private var stage: LabVehicleStage = .available
    @State private var operationStartAt: Date = Date()

    private var isValid: Bool {
        !internalNumber.trimmingCharacters(in: .whitespaces).isEmpty && !stationId.isEmpty
    }

    var body: some View {
        LabSheet(
            title: vehicle == nil ? "Nueva unidad" : "Editar unidad",
            subtitle: "Las unidades en compra, traslado o preparación cuentan como flotilla futura y generan vacantes proyectadas.",
            isConfirmEnabled: isValid,
            onConfirm: save
        ) {
            LabField(label: "Número interno", placeholder: "TEV-014", text: $internalNumber, autocapitalization: .characters)
            LabField(label: "Marca", placeholder: "BYD", text: $brand, autocapitalization: .words)
            LabField(label: "Modelo", placeholder: "Dolphin Mini", text: $model, autocapitalization: .words)
            LabNumberField(label: "Año", value: $year, range: 2015...2030)
            LabField(label: "VIN", placeholder: "17 caracteres", text: $vin, autocapitalization: .characters)
            LabField(label: "Placas", placeholder: "NXP-482-C", text: $plates, autocapitalization: .characters)

            LabOptionRow(
                label: "Estación",
                options: lab.world.stations.map(\.id),
                selection: $stationId,
                title: { id in lab.world.station(id: id)?.code ?? "—" }
            )

            LabOptionRow(
                label: "Etapa",
                options: LabVehicleStage.allCases,
                selection: $stage,
                title: \.label,
                symbol: { $0.symbol }
            )

            LabNumberField(label: "Odómetro", value: $odometerKm, range: 0...500_000, step: 100, suffix: "km")
            LabNumberField(label: "Batería", value: $batteryPct, range: 0...100, step: 5, suffix: "%")
            LabNumberField(label: "Autonomía", value: $rangeKm, range: 50...800, step: 10, suffix: "km")

            if stage.isIncoming {
                DatePicker("Inicio de operación", selection: $operationStartAt, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .foregroundStyle(.white)
                    .tint(LabTone.accent)
                    .padding(12)
                    .labFlat()
            }

            Button("Generar VIN y placas de prueba") {
                let seed = Int(Date().timeIntervalSince1970) % 99_999
                vin = LabRules.generateVin(seed: seed)
                plates = LabRules.generatePlates(seed: seed)
            }
            .buttonStyle(LabButtonStyle(kind: .soft))
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let vehicle else {
            stationId = lab.world.stations.first?.id ?? ""
            let seed = lab.world.vehicles.count + 1
            internalNumber = "PRB-\(String(format: "%03d", seed))"
            vin = LabRules.generateVin(seed: seed)
            plates = LabRules.generatePlates(seed: seed)
            return
        }
        internalNumber = vehicle.internalNumber
        brand = vehicle.brand
        model = vehicle.model
        year = vehicle.year
        vin = vehicle.vin
        plates = vehicle.plates
        odometerKm = vehicle.odometerKm
        batteryPct = vehicle.batteryPct
        rangeKm = vehicle.rangeKm
        stationId = vehicle.stationId
        stage = vehicle.stage
        operationStartAt = vehicle.operationStartAt
    }

    private func save() {
        let code = internalNumber.trimmingCharacters(in: .whitespaces).uppercased()
        let value = LabVehicle(
            id: vehicle?.id ?? "labveh-\(UUID().uuidString.prefix(8))",
            internalNumber: code,
            brand: brand,
            model: model,
            year: year,
            vin: vin.uppercased(),
            plates: plates.uppercased(),
            odometerKm: odometerKm,
            batteryPct: batteryPct,
            rangeKm: rangeKm,
            stationId: stationId,
            stage: stage,
            incorporatedAt: vehicle?.incorporatedAt ?? Date(),
            operationStartAt: operationStartAt,
            qrCode: code,
            occupiedBy: vehicle?.occupiedBy,
            photoOdometerKm: vehicle?.photoOdometerKm,
            telemetryOdometerKm: vehicle?.telemetryOdometerKm,
            lastTelemetryAt: vehicle?.lastTelemetryAt,
            createdAt: vehicle?.createdAt ?? Date()
        )
        if lab.saveVehicle(value) { dismiss() }
    }
}

/// Lets the administrator feed the three odometer sources separately so the discrepancy
/// rule can actually be exercised.
private struct LabReadingsSheet: View {
    let vehicle: LabVehicle
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var manual: Int = 0
    @State private var photo: Int = 0
    @State private var battery: Int = 0

    var body: some View {
        LabSheet(
            title: "Lecturas de \(vehicle.internalNumber)",
            subtitle: "Tres fuentes distintas: captura manual, evidencia fotográfica y telemetría. Si no coinciden, el sistema debe levantar la discrepancia.",
            confirmTitle: "Aplicar",
            onConfirm: {
                lab.updateVehicleReadings(id: vehicle.id, odometerKm: manual, batteryPct: battery, photoOdometerKm: photo)
                dismiss()
            }
        ) {
            LabNumberField(label: "Odómetro capturado", value: $manual, range: 0...500_000, step: 50, suffix: "km")
            LabNumberField(label: "Odómetro de la foto", value: $photo, range: 0...500_000, step: 50, suffix: "km")
            LabNumberField(label: "Batería", value: $battery, range: 0...100, step: 5, suffix: "%")

            VStack(alignment: .leading, spacing: 6) {
                LabCaps(text: "Telemetría recibida")
                Text(
                    vehicle.telemetryOdometerKm.map { "\($0) km · \(vehicle.lastTelemetryAt.map { Fmt.relative($0, from: Date()) } ?? "sin fecha")" }
                        ?? "Sin lectura de telemetría todavía. Envíala desde Integraciones simuladas."
                )
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()

            let gap = max(manual, photo) - min(manual, photo)
            if gap > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Discrepancia de \(gap) km", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(LabTone.bad)
                    Text("Al aplicar, el sistema levantará una alerta de kilometraje para el supervisor de la estación.")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(LabTone.bad.opacity(0.1), in: .rect(cornerRadius: 16))
            }
        }
        .onAppear {
            manual = vehicle.odometerKm
            photo = vehicle.photoOdometerKm ?? vehicle.odometerKm
            battery = vehicle.batteryPct
        }
    }
}

/// The QR the driver scans at the start of a shift. Rendered from the unit code so it can
/// be photographed off the screen with another device during a test.
private struct LabQrSheet: View {
    let vehicle: LabVehicle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                LabQrCode(text: vehicle.qrCode)
                    .frame(width: 220, height: 220)
                    .padding(18)
                    .background(.white, in: .rect(cornerRadius: 22))

                VStack(spacing: 5) {
                    Text(vehicle.qrCode)
                        .font(.system(.title3, weight: .black))
                        .monospaced()
                        .foregroundStyle(.white)
                    Text("\(vehicle.fullModel) · \(vehicle.plates)")
                        .font(.footnote)
                        .foregroundStyle(LabTone.muted)
                }

                Text("Escanea este código desde la interfaz del conductor para asignar la unidad. Si lo escaneas en otra estación, la asignación debe rechazarse.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)

                Spacer(minLength: 0)
            }
            .padding(.top, 26)
            .frame(maxWidth: .infinity)
            .background(LabBackground())
            .navigationTitle("Código de la unidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }.foregroundStyle(LabTone.accent)
                }
            }
            .toolbarBackground(LabTone.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(LabTone.canvas)
        .preferredColorScheme(.dark)
    }
}
