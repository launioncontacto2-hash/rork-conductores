import SwiftUI

// MARK: - System

/// Global rules of the environment: shift arithmetic, clock and the role preview.
struct LabSystemView: View {
    @Environment(LabStore.self) private var lab

    @State private var config: LabShiftConfig = .standard
    @State private var previewTarget: LabUser?

    var body: some View {
        LabScreen(section: .system) {
            LabSectionTitle(
                title: "Configuración del sistema",
                subtitle: "Las reglas que gobiernan toda la aritmética: cuántos conductores exige una unidad, cuánto dura un turno y con qué batería se puede salir.",
                symbol: "gearshape.2.fill"
            )

            shiftRules
            blocksCard
            clockCard
            previewCard
        }
        .sheet(item: $previewTarget) { user in LabPreviewSheet(user: user) }
        .onAppear { config = lab.world.shiftConfig }
    }

    private var shiftRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabCaps(text: "Reglas de turno")

            LabNumberField(label: "Conductores por unidad", value: $config.driversPerVehicle, range: 1...8)
            LabNumberField(label: "Horas por turno", value: $config.shiftHours, range: 4...12, suffix: "h")
            LabNumberField(label: "Hora de comida", value: $config.mealHours, range: 0...3, suffix: "h")
            LabNumberField(label: "Tolerancia de entrada", value: $config.graceMinutes, range: 0...60, step: 5, suffix: "min")
            LabNumberField(label: "Batería mínima para salir", value: $config.minimumBatteryPct, range: 0...100, step: 5, suffix: "%")
            LabNumberField(label: "Fotos de inspección", value: $config.inspectionPhotos, range: 0...12)

            VStack(alignment: .leading, spacing: 5) {
                LabCaps(text: "Efecto inmediato")
                Text("\(lab.world.installedVehicles.count) unidades × \(config.driversPerVehicle) = \(lab.world.installedVehicles.count * config.driversPerVehicle) conductores requeridos en toda la red.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()

            Button("Aplicar reglas") { lab.updateShiftConfig(config) }
                .buttonStyle(LabButtonStyle(kind: .solid))
        }
        .padding(16)
        .labPanel()
    }

    private var blocksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Bloques de turno")
            ForEach(Array(config.blocks.enumerated()), id: \.element.id) { index, block in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.block.label)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(block.scheduleLabel)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(LabTone.muted)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $config.blocks[index].isActive)
                        .labelsHidden()
                        .tint(LabTone.accent)
                }
                .padding(12)
                .labFlat()
            }
        }
        .padding(16)
        .labPanel()
    }

    private var clockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabCaps(text: "Reloj del entorno")
            HStack {
                Text(Fmt.clockSeconds(lab.now))
                    .font(.system(.title, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(LabTone.accent)
                Spacer(minLength: 0)
                Text(Fmt.dateShort(lab.now))
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
            }

            Text("Mover el reloj también mueve el mundo: los créditos abonan sus semanas y los documentos que ya pasaron su vigencia se marcan vencidos.")
                .font(.caption)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("+1 día") { lab.advanceTime(days: 1) }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("+1 semana") { lab.advanceTime(days: 7) }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("+1 mes") { lab.advanceTime(days: 30) }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Spacer(minLength: 0)
                Button("Real") { lab.setClockOffset(minutes: 0) }
                    .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
            }
        }
        .padding(16)
        .labPanel()
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Ver como…")
            Text("Revisa cualquier interfaz con las credenciales que creaste. La sesión se abre con ese rol y el laboratorio queda disponible para volver.")
                .font(.caption)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            if lab.world.users.isEmpty {
                Text("Sin credenciales todavía: crea un usuario para poder abrir otra interfaz.")
                    .font(.caption)
                    .foregroundStyle(LabTone.accent)
            } else {
                ForEach(StaffRole.operationalRoles, id: \.self) { role in
                    let users = lab.credentials(for: role)
                    if let user = users.first {
                        Button {
                            previewTarget = user
                        } label: {
                            LabRow(
                                title: role.label,
                                subtitle: user.name,
                                detail: "\(users.count) credencial(es) disponibles",
                                symbol: role.symbol
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(LabTone.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .labPanel()
    }
}

/// Opens another interface with a test credential, without changing anybody's real role.
struct LabPreviewSheet: View {
    let user: LabUser
    @Environment(LabStore.self) private var lab
    @Environment(FleetStore.self) private var fleet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LabSheet(
            title: "Ver como \(user.role.shortLabel)",
            subtitle: "Se abrirá la interfaz de \(user.role.label) con la credencial de \(user.name). Todo lo que veas ahí son datos de prueba.",
            confirmTitle: "Abrir interfaz",
            onConfirm: open
        ) {
            VStack(alignment: .leading, spacing: 9) {
                LabRow(title: user.name, subtitle: user.email, detail: user.employeeNumber, symbol: user.role.symbol)
                if let stationId = user.stationId, let station = lab.world.station(id: stationId) {
                    LabRow(title: station.displayName, subtitle: "Estación asignada", symbol: "building.2.fill", tint: LabTone.muted)
                }
                LabRow(
                    title: "Contraseña de prueba",
                    subtitle: user.password,
                    symbol: "key.fill",
                    tint: LabTone.muted
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Cómo volver", systemImage: "arrow.uturn.left")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(LabTone.accent)
                Text("Cierra sesión desde el menú de cuenta y entra otra vez con \(LabRules.adminEmail). El laboratorio conserva todo lo que construiste.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()
        }
    }

    private func open() {
        guard lab.isTest else {
            lab.notify("Activa el modo prueba antes de abrir una interfaz de prueba.", tone: .warning)
            dismiss()
            return
        }
        lab.record(
            action: "Abrir interfaz en vista previa",
            section: .system,
            detail: "\(user.role.label) · \(user.name)",
            result: .success
        )
        fleet.signIn(account: user.account, method: .credentials)
        dismiss()
    }
}

// MARK: - Alerts

struct LabAlertsView: View {
    @Environment(LabStore.self) private var lab

    @State private var isCreating: Bool = false
    @State private var isFaultPresented: Bool = false

    var body: some View {
        LabScreen(section: .alerts) {
            LabSectionTitle(
                title: "Alertas y fallos",
                subtitle: "Genera alertas por nivel y destinatario, o inyecta un fallo controlado y observa qué hace el sistema.",
                symbol: "bell.badge.fill"
            )

            HStack(spacing: 8) {
                Button("Generar alerta") { isCreating = true }
                    .buttonStyle(LabButtonStyle(kind: .solid, isCompact: true))
                Button("Inyectar fallo") { isFaultPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
            }

            if !lab.activeFaults.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LabCaps(text: "Fallos activos")
                    ForEach(lab.activeFaults) { fault in
                        LabRow(
                            title: fault.kind.label,
                            subtitle: fault.detail,
                            detail: fault.targetLabel,
                            symbol: fault.kind.symbol,
                            tint: LabTone.tone(for: fault.kind.level)
                        ) {
                            Button("Resolver") { lab.resolveFault(id: fault.id) }
                                .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                        }
                    }
                }
                .padding(16)
                .labPanel()
            }

            if lab.world.alerts.isEmpty {
                LabEmptyState(
                    title: "Sin alertas",
                    message: "No hay ninguna alerta en el sistema de pruebas.",
                    symbol: "bell.slash"
                )
            } else {
                HStack {
                    LabCaps(text: "Alertas (\(lab.world.alerts.count))")
                    Spacer(minLength: 0)
                    Button("Limpiar") { lab.clearAlerts() }
                        .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                }
                ForEach(lab.world.alerts) { alert in
                    Button {
                        lab.markAlertRead(id: alert.id)
                    } label: {
                        LabRow(
                            title: alert.title,
                            subtitle: alert.detail,
                            detail: "\(alert.level.label) · \(alert.audience.shortLabel) · \(alert.origin)",
                            symbol: alert.level.symbol,
                            tint: LabTone.tone(for: alert.level)
                        ) {
                            if !alert.isRead {
                                Circle()
                                    .fill(LabTone.accent)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $isCreating) { LabAlertEditor() }
        .sheet(isPresented: $isFaultPresented) { LabFaultInjector() }
    }
}

private struct LabAlertEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var level: OpsAlertLevel = .important
    @State private var audience: StaffRole = .supervisor
    @State private var stationId: String = ""
    @State private var title: String = ""
    @State private var detail: String = ""

    var body: some View {
        LabSheet(
            title: "Generar alerta",
            subtitle: "El nivel decide el color y la urgencia; el destinatario decide en qué escritorio aparece.",
            isConfirmEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: {
                lab.createManualAlert(
                    level: level,
                    audience: audience,
                    stationId: stationId.isEmpty ? nil : stationId,
                    title: title,
                    detail: detail
                )
                dismiss()
            }
        ) {
            LabOptionRow(label: "Nivel", options: OpsAlertLevel.allCases, selection: $level, title: \.label, symbol: { $0.symbol })
            LabOptionRow(label: "Destinatario", options: StaffRole.operationalRoles, selection: $audience, title: \.shortLabel, symbol: { $0.symbol })
            if !lab.world.stations.isEmpty {
                LabOptionRow(
                    label: "Estación",
                    options: [""] + lab.world.stations.map(\.id),
                    selection: $stationId,
                    title: { id in id.isEmpty ? "Toda la red" : (lab.world.station(id: id)?.code ?? "—") }
                )
            }
            LabField(label: "Título", placeholder: "Unidad sin conductor asignado", text: $title)
            LabField(label: "Detalle", placeholder: "Qué debe hacer quien la reciba", text: $detail)
        }
    }
}

/// Sixteen controlled failures, each with the consequence the system must produce.
private struct LabFaultInjector: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var kind: LabFaultKind = .vehicleBreakdown
    @State private var targetId: String = ""

    private var options: [(id: String, label: String)] {
        switch kind.target {
        case .vehicle:
            lab.world.vehicles.map { ($0.id, "\($0.internalNumber) · \($0.fullModel)") }
        case .driver:
            lab.world.driverUsers.map { ($0.driverId ?? $0.id, $0.name) }
        case .order:
            lab.world.orders.map { ($0.id, "\($0.folio) · \($0.assetName)") }
        case .candidate:
            lab.world.prospects.map { ($0.id, $0.name) }
        case .station:
            lab.world.stations.map { ($0.id, $0.displayName) }
        }
    }

    var body: some View {
        LabSheet(
            title: "Inyectar fallo",
            subtitle: "El fallo se aplica de verdad sobre el mundo de pruebas y levanta la alerta que corresponde.",
            confirmTitle: "Inyectar",
            isConfirmEnabled: !options.isEmpty,
            onConfirm: {
                let label = options.first { $0.id == targetId }?.label ?? kind.target.label
                lab.injectFault(kind: kind, targetId: targetId, targetLabel: label)
                dismiss()
            }
        ) {
            LabOptionRow(label: "Tipo de fallo", options: LabFaultKind.allCases, selection: $kind, title: \.label, symbol: { $0.symbol })

            if options.isEmpty {
                Text("No hay ningún \(kind.target.label.lowercased()) en el entorno de pruebas para aplicar este fallo. Crea uno primero.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.bad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .labFlat()
            } else {
                LabOptionRow(
                    label: kind.target.label,
                    options: options.map(\.id),
                    selection: $targetId,
                    title: { id in options.first { $0.id == id }?.label ?? "—" }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                LabCaps(text: "Respuesta esperada del sistema")
                Text(kind.expectedResponse)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    LabChip(text: kind.level.label, symbol: kind.level.symbol, tint: LabTone.tone(for: kind.level))
                    LabChip(text: "Va a \(kind.audience.shortLabel)", symbol: kind.audience.symbol, tint: LabTone.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LabTone.bad.opacity(0.09), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(LabTone.bad.opacity(0.35), lineWidth: 1)
            }
        }
        .onAppear { targetId = options.first?.id ?? "" }
        .onChange(of: kind) { _, _ in targetId = options.first?.id ?? "" }
    }
}

// MARK: - Integrations

/// Simulated external systems: the ride platform, the vehicle telemetry, the lead forms
/// and the bank. None of them touches a real service.
struct LabIntegrationsView: View {
    @Environment(LabStore.self) private var lab

    @State private var isUberPresented: Bool = false
    @State private var isTelemetryPresented: Bool = false
    @State private var isMetaPresented: Bool = false
    @State private var isBankingPresented: Bool = false

    var body: some View {
        LabScreen(section: .integrations) {
            LabSectionTitle(
                title: "Integraciones simuladas",
                subtitle: "Todo lo que en producción vendría de fuera, aquí lo escribes tú. Nada sale del dispositivo.",
                symbol: "antenna.radiowaves.left.and.right"
            )

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                integrationTile(
                    title: "Uber / DiDi",
                    caption: "Viajes, ingresos y horas en línea",
                    symbol: "car.circle.fill",
                    count: lab.world.uberFeeds.count
                ) { isUberPresented = true }

                integrationTile(
                    title: "Telemetría BYD",
                    caption: "Batería, odómetro y ubicación",
                    symbol: "bolt.car.fill",
                    count: lab.world.telemetry.count
                ) { isTelemetryPresented = true }

                integrationTile(
                    title: "Meta Lead Ads",
                    caption: "Formularios de campaña",
                    symbol: "megaphone.fill",
                    count: lab.world.prospects.filter { $0.campaignId != nil }.count
                ) { isMetaPresented = true }

                integrationTile(
                    title: "Banca",
                    caption: "Dispersión de liquidaciones",
                    symbol: "building.columns.fill",
                    count: lab.world.transfers.count
                ) { isBankingPresented = true }
            }

            if !lab.world.uberFeeds.isEmpty {
                feedCard(
                    title: "Últimos datos de plataforma",
                    rows: lab.world.uberFeeds.prefix(4).map { feed in
                        (feed.id, feed.driverName, "\(feed.trips) viajes · \(feed.km) km · \(Fmt.durationText(feed.onlineMinutes))", Fmt.mxn(feed.totalMxn))
                    }
                )
            }

            if !lab.world.telemetry.isEmpty {
                feedCard(
                    title: "Últimas lecturas de telemetría",
                    rows: lab.world.telemetry.prefix(4).map { reading in
                        (reading.id, reading.vehicleLabel, "\(reading.batteryPct)% · \(reading.chargeState.label) · \(reading.coordinateLabel)", Fmt.km(reading.odometerKm))
                    }
                )
            }
        }
        .sheet(isPresented: $isUberPresented) { LabUberSimulator() }
        .sheet(isPresented: $isTelemetryPresented) { LabTelemetrySimulator() }
        .sheet(isPresented: $isMetaPresented) { LabMetaSimulator() }
        .sheet(isPresented: $isBankingPresented) { LabBankingSimulator() }
    }

    private func integrationTile(
        title: String,
        caption: String,
        symbol: String,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(LabTone.accent)
                        .frame(width: 32, height: 32)
                        .background(LabTone.accent.opacity(0.13), in: .rect(cornerRadius: 11))
                    Spacer(minLength: 0)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(.caption2, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(LabTone.canvas)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(LabTone.accent, in: .capsule)
                    }
                }
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(.white)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 122, alignment: .top)
            .padding(13)
            .labPanel(cornerRadius: 19)
        }
        .buttonStyle(.plain)
    }

    private func feedCard(title: String, rows: [(String, String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: title)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.1)
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(.white)
                        Text(row.2)
                            .font(.caption2)
                            .foregroundStyle(LabTone.muted)
                    }
                    Spacer(minLength: 0)
                    Text(row.3)
                        .font(.system(.caption, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(LabTone.accent)
                }
                .padding(11)
                .labFlat(cornerRadius: 13)
            }
        }
        .padding(16)
        .labPanel()
    }
}

private struct LabUberSimulator: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var driverId: String = ""
    @State private var trips: Int = 14
    @State private var earnings: Int = 1_800
    @State private var tips: Int = 120
    @State private var onlineMinutes: Int = 480
    @State private var km: Int = 160

    var body: some View {
        LabSheet(
            title: "Datos de plataforma",
            subtitle: "Simula la respuesta de la API de viajes para un conductor y un día concretos.",
            confirmTitle: "Recibir",
            isConfirmEnabled: !driverId.isEmpty,
            onConfirm: save
        ) {
            if lab.world.driverUsers.isEmpty {
                Text("No hay conductores en el entorno de pruebas.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.bad)
            } else {
                LabOptionRow(
                    label: "Conductor",
                    options: lab.world.driverUsers.map(\.id),
                    selection: $driverId,
                    title: { id in lab.world.user(id: id)?.name ?? "—" }
                )
                LabNumberField(label: "Viajes", value: $trips, range: 0...100)
                LabNumberField(label: "Ingresos", value: $earnings, range: 0...50_000, step: 50, suffix: "MXN")
                LabNumberField(label: "Propinas", value: $tips, range: 0...5_000, step: 10, suffix: "MXN")
                LabNumberField(label: "Minutos en línea", value: $onlineMinutes, range: 0...900, step: 15, suffix: "min")
                LabNumberField(label: "Kilómetros", value: $km, range: 0...800, step: 10, suffix: "km")
            }
        }
        .onAppear { driverId = lab.world.driverUsers.first?.id ?? "" }
    }

    private func save() {
        guard let user = lab.world.user(id: driverId) else { return }
        let feed = LabUberFeed(
            id: "labubr-\(UUID().uuidString.prefix(8))",
            driverId: user.driverId ?? user.id,
            driverName: user.name,
            vehicleId: nil,
            vehicleLabel: "—",
            date: lab.now,
            trips: trips,
            earningsMxn: earnings,
            tipsMxn: tips,
            onlineMinutes: onlineMinutes,
            km: km,
            receivedAt: Date()
        )
        lab.receiveUberFeed(feed)
        dismiss()
    }
}

private struct LabTelemetrySimulator: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var vehicleId: String = ""
    @State private var battery: Int = 85
    @State private var odometer: Int = 0
    @State private var range: Int = 280
    @State private var charge: LabChargeState = .idle
    @State private var latitude: Double = 19.4326
    @State private var longitude: Double = -99.1332

    var body: some View {
        LabSheet(
            title: "Telemetría del vehículo",
            subtitle: "Batería, odómetro, autonomía y posición. Si el odómetro no coincide con la captura manual, se levanta discrepancia.",
            confirmTitle: "Recibir",
            isConfirmEnabled: !vehicleId.isEmpty,
            onConfirm: save
        ) {
            if lab.world.vehicles.isEmpty {
                Text("No hay unidades en el entorno de pruebas.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.bad)
            } else {
                LabOptionRow(
                    label: "Unidad",
                    options: lab.world.vehicles.map(\.id),
                    selection: $vehicleId,
                    title: { id in lab.world.vehicle(id: id)?.internalNumber ?? "—" }
                )
                LabNumberField(label: "Batería", value: $battery, range: 0...100, step: 5, suffix: "%")
                LabNumberField(label: "Odómetro", value: $odometer, range: 0...500_000, step: 50, suffix: "km")
                LabNumberField(label: "Autonomía", value: $range, range: 0...800, step: 10, suffix: "km")
                LabOptionRow(label: "Estado de carga", options: LabChargeState.allCases, selection: $charge, title: \.label)

                VStack(alignment: .leading, spacing: 6) {
                    LabCaps(text: "Ubicación simulada")
                    Text(String(format: "%.4f, %.4f", latitude, longitude))
                        .font(.system(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Button("CDMX") { latitude = 19.4326; longitude = -99.1332 }
                            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                        Button("Guadalajara") { latitude = 20.6597; longitude = -103.3496 }
                            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                        Button("Monterrey") { latitude = 25.6866; longitude = -100.3161 }
                            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .labFlat()

                if battery < lab.world.shiftConfig.minimumBatteryPct {
                    Text("Con \(battery)% la unidad queda por debajo del mínimo de \(lab.world.shiftConfig.minimumBatteryPct)% y no debería poder iniciar turno.")
                        .font(.caption)
                        .foregroundStyle(LabTone.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(LabTone.bad.opacity(0.1), in: .rect(cornerRadius: 14))
                }
            }
        }
        .onAppear {
            vehicleId = lab.world.vehicles.first?.id ?? ""
            odometer = lab.world.vehicles.first?.odometerKm ?? 0
        }
    }

    private func save() {
        guard let vehicle = lab.world.vehicle(id: vehicleId) else { return }
        let reading = LabTelemetryReading(
            id: "labtel-\(UUID().uuidString.prefix(8))",
            vehicleId: vehicle.id,
            vehicleLabel: "\(vehicle.internalNumber) · \(vehicle.fullModel)",
            batteryPct: battery,
            odometerKm: odometer,
            rangeKm: range,
            latitude: latitude,
            longitude: longitude,
            chargeState: charge,
            stage: vehicle.stage,
            receivedAt: Date()
        )
        lab.receiveTelemetry(reading)
        dismiss()
    }
}

private struct LabMetaSimulator: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var campaignId: String = ""
    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var city: String = "CDMX"

    var body: some View {
        LabSheet(
            title: "Formulario de campaña",
            subtitle: "Simula el envío de un formulario de Meta. El lead entra al embudo con la fuente de la campaña.",
            confirmTitle: "Recibir lead",
            isConfirmEnabled: !campaignId.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: save
        ) {
            if lab.world.campaigns.isEmpty {
                Text("No hay campañas creadas. Crea una en Reclutamiento para poder recibir leads.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.bad)
            } else {
                LabOptionRow(
                    label: "Campaña",
                    options: lab.world.campaigns.map(\.id),
                    selection: $campaignId,
                    title: { id in lab.world.campaigns.first { $0.id == id }?.name ?? "—" }
                )
                LabField(label: "Nombre", placeholder: "Nombre del interesado", text: $name, autocapitalization: .words)
                LabField(label: "Teléfono", placeholder: "5512345678", text: $phone, keyboard: .phonePad)
                LabField(label: "Ciudad", placeholder: "CDMX", text: $city)
            }
        }
        .onAppear { campaignId = lab.world.campaigns.first?.id ?? "" }
    }

    private func save() {
        guard let campaign = lab.world.campaigns.first(where: { $0.id == campaignId }) else { return }
        lab.receiveMetaLead(campaign: campaign, name: name, phone: phone, city: city)
        dismiss()
    }
}

private struct LabBankingSimulator: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var driverId: String = ""
    @State private var amount: Int = 5_000
    @State private var outcome: LabTransferOutcome = .success

    var body: some View {
        LabSheet(
            title: "Dispersión bancaria",
            subtitle: "Elige qué contesta el banco y observa cómo reacciona la liquidación.",
            confirmTitle: "Ejecutar",
            isConfirmEnabled: !driverId.isEmpty,
            onConfirm: save
        ) {
            if lab.world.driverUsers.isEmpty {
                Text("No hay conductores para dispersar.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.bad)
            } else {
                LabOptionRow(
                    label: "Conductor",
                    options: lab.world.driverUsers.map(\.id),
                    selection: $driverId,
                    title: { id in lab.world.user(id: id)?.name ?? "—" }
                )
                LabNumberField(label: "Monto", value: $amount, range: 1...200_000, step: 100, suffix: "MXN")
                LabOptionRow(
                    label: "Respuesta del banco",
                    options: LabTransferOutcome.allCases,
                    selection: $outcome,
                    title: \.label,
                    symbol: { $0.symbol }
                )

                VStack(alignment: .leading, spacing: 5) {
                    LabCaps(text: "Qué debe pasar")
                    Text(outcome.appResponse)
                        .font(.footnote)
                        .foregroundStyle(outcome.isSuccess ? LabTone.good : LabTone.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .labFlat()
            }
        }
        .onAppear { driverId = lab.world.driverUsers.first?.id ?? "" }
    }

    private func save() {
        guard let user = lab.world.user(id: driverId) else { return }
        let account = lab.world.bankAccounts.first { $0.driverId == (user.driverId ?? user.id) }
        let transfer = LabTransfer(
            id: "labtrf-\(UUID().uuidString.prefix(8))",
            driverId: user.driverId ?? user.id,
            driverName: user.name,
            amountMxn: amount,
            bank: account?.bank ?? "Sin cuenta registrada",
            clabe: account?.clabe ?? "",
            outcome: outcome,
            reference: "REF-\(Int.random(in: 100_000...999_999))",
            createdAt: Date()
        )
        lab.runTransfer(transfer)
        dismiss()
    }
}

// MARK: - Scenarios

/// Loads whole networks in one action, plus the capacity calculator that turns fleet into
/// hiring targets.
struct LabScenariosView: View {
    @Environment(LabStore.self) private var lab

    @State private var pending: LabScenario?
    @State private var vehicles: Int = 20
    @State private var drivers: Int = 60
    @State private var incoming: Int = 10
    @State private var days: Int = 20
    @State private var conversion: Int = 30
    @State private var hiringDays: Int = 12

    private var result: LabCapacityResult {
        LabRules.capacity(
            LabCapacityInput(
                vehicles: vehicles,
                drivers: drivers,
                incomingVehicles: incoming,
                daysToArrival: days,
                conversionRate: Double(conversion) / 100,
                averageHiringDays: hiringDays
            )
        )
    }

    var body: some View {
        LabScreen(section: .scenarios) {
            LabSectionTitle(
                title: "Escenarios",
                subtitle: "Carga una red completa de golpe para probar la operación sin capturar nada a mano.",
                symbol: "square.stack.3d.up.fill"
            )

            ForEach(lab.scenarios) { scenario in
                scenarioCard(scenario)
            }

            calculator
        }
        .confirmationDialog(
            "¿Cargar «\(pending?.name ?? "")»?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Cargar escenario") {
                if let scenario = pending { lab.load(scenario: scenario) }
                pending = nil
            }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: {
            Text("Se añadirá al entorno de pruebas actual y activará el modo prueba. No se borra nada de lo que ya creaste.")
        }
    }

    private func scenarioCard(_ scenario: LabScenario) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.name)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                    Text(scenario.detail)
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                LabChip(
                    text: "\(scenario.coveragePct)%",
                    symbol: "person.3.fill",
                    tint: scenario.deficit > 0 ? LabTone.bad : LabTone.good
                )
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                LabStat(label: "Unidades", value: "\(scenario.vehicles)", symbol: "car.2.fill")
                LabStat(label: "Conductores", value: "\(scenario.drivers)", symbol: "steeringwheel")
                LabStat(label: "Candidatos", value: "\(scenario.candidates)", symbol: "person.crop.circle.badge.plus")
            }

            Button("Cargar") { pending = scenario }
                .buttonStyle(LabButtonStyle(kind: .solid, isCompact: true))
        }
        .padding(15)
        .labPanel()
    }

    private var calculator: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabSectionTitle(
                title: "Simulador de capacidad",
                subtitle: "La aritmética que gobierna la red: cada unidad exige conductores y cada unidad que llega abre vacantes con fecha.",
                symbol: "function"
            )

            LabNumberField(label: "Unidades instaladas", value: $vehicles, range: 0...500)
            LabNumberField(label: "Conductores disponibles", value: $drivers, range: 0...2000, step: 5)
            LabNumberField(label: "Unidades por llegar", value: $incoming, range: 0...500)
            LabNumberField(label: "Días para su llegada", value: $days, range: 0...365)
            LabNumberField(label: "Conversión del embudo", value: $conversion, range: 1...100, step: 5, suffix: "%")
            LabNumberField(label: "Días promedio de contratación", value: $hiringDays, range: 1...90)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                LabStat(label: "Requeridos hoy", value: "\(result.requiredDrivers)", symbol: "person.3.fill")
                LabStat(
                    label: "Déficit actual",
                    value: "\(result.deficit)",
                    tint: result.deficit > 0 ? LabTone.bad : LabTone.good,
                    symbol: "person.badge.minus"
                )
                LabStat(label: "Requeridos a futuro", value: "\(result.futureRequired)", symbol: "calendar.badge.plus")
                LabStat(
                    label: "Vacantes proyectadas",
                    value: "\(result.futureVacancies)",
                    tint: result.futureVacancies > 0 ? LabTone.accent : LabTone.good,
                    symbol: "flag.fill"
                )
                LabStat(label: "Leads necesarios", value: "\(result.leadsNeeded)", tint: LabTone.cool, symbol: "megaphone.fill")
                LabStat(
                    label: result.isLate ? "Tarde por" : "Arrancar en",
                    value: "\(abs(result.startInDays)) d",
                    tint: result.isLate ? LabTone.bad : LabTone.good,
                    symbol: "clock.fill"
                )
            }

            HStack(spacing: 9) {
                Image(systemName: result.level.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(LabTone.tone(for: result.level))
                Text(verdict)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LabTone.tone(for: result.level).opacity(0.1), in: .rect(cornerRadius: 16))
        }
        .padding(16)
        .labPanel()
    }

    private var verdict: String {
        if result.futureVacancies == 0 {
            return "La plantilla cubre la flotilla actual y la que viene."
        }
        if result.isLate {
            return "El reclutamiento ya va tarde: contratar toma \(hiringDays) días y las unidades llegan en \(days). Hay que abrir campañas hoy."
        }
        return "Hay que iniciar \(result.leadsNeeded) leads en los próximos \(result.startInDays) días para llegar con plantilla completa."
    }
}

// MARK: - Audit

struct LabAuditView: View {
    @Environment(LabStore.self) private var lab

    @State private var sectionFilter: LabSection?
    @State private var resultFilter: LabResult?
    @State private var isExportPresented: Bool = false

    private var entries: [LabAuditEntry] {
        lab.auditEntries(section: sectionFilter, result: resultFilter)
    }

    var body: some View {
        LabScreen(section: .audit) {
            LabSectionTitle(
                title: "Historial de pruebas",
                subtitle: "Todo lo que se ejecuta en el laboratorio queda registrado con su resultado y la respuesta del sistema.",
                symbol: "list.bullet.rectangle.portrait.fill"
            )

            summary

            LabOptionRow(
                label: "Módulo",
                options: [LabSection?.none] + LabSection.allCases.map { Optional($0) },
                selection: $sectionFilter,
                title: { $0?.label ?? "Todos" },
                symbol: { $0?.symbol ?? "square.grid.2x2.fill" }
            )

            LabOptionRow(
                label: "Resultado",
                options: [LabResult?.none] + LabResult.allCases.map { Optional($0) },
                selection: $resultFilter,
                title: { $0?.label ?? "Todos" },
                symbol: { $0?.symbol ?? "circle.grid.2x2.fill" }
            )

            HStack(spacing: 8) {
                Button("Exportar") { isExportPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                    .disabled(lab.auditEntries.isEmpty)
                Spacer(minLength: 0)
                Button("Limpiar historial") { lab.clearAudit() }
                    .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
                    .disabled(lab.auditEntries.isEmpty)
            }

            if entries.isEmpty {
                LabEmptyState(
                    title: "Sin registros",
                    message: "Todavía no se ha ejecutado nada con este filtro.",
                    symbol: "list.bullet.rectangle"
                )
            } else {
                ForEach(entries) { entry in
                    entryCard(entry)
                }
            }
        }
        .sheet(isPresented: $isExportPresented) {
            LabExportSheet(text: lab.exportAudit())
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(LabResult.allCases) { result in
                LabStat(
                    label: result.label,
                    value: "\(lab.auditEntries.filter { $0.result == result }.count)",
                    tint: LabTone.tone(for: result),
                    symbol: result.symbol
                )
            }
        }
    }

    private func entryCard(_ entry: LabAuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.action)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                LabResultBadge(result: entry.result)
            }

            if let error = entry.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(LabTone.tone(for: entry.result))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LabTone.tone(for: entry.result).opacity(0.1), in: .rect(cornerRadius: 11))
            }

            HStack(spacing: 6) {
                LabChip(text: entry.section.label, symbol: entry.section.symbol, tint: LabTone.muted)
                LabChip(text: entry.origin, symbol: "testtube.2", tint: LabTone.muted)
                Spacer(minLength: 0)
                Text("\(Fmt.dateShort(entry.createdAt)) · \(Fmt.clock(entry.createdAt))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(LabTone.muted)
            }
        }
        .padding(14)
        .labPanel()
    }
}

private struct LabExportSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(LabBackground())
            .navigationTitle("Exportar historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(LabTone.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(LabTone.accent)
                }
            }
            .toolbarBackground(LabTone.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(LabTone.canvas)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reset

struct LabResetView: View {
    @Environment(LabStore.self) private var lab

    @State private var pending: LabStore.ResetTarget?
    @State private var confirmation: String = ""

    var body: some View {
        LabScreen(section: .reset) {
            LabSectionTitle(
                title: "Reiniciar el entorno",
                subtitle: "Borra lo que necesites del mundo de pruebas. La red demostrativa de producción nunca se toca.",
                symbol: "trash.fill"
            )

            VStack(alignment: .leading, spacing: 8) {
                Label("Esto solo afecta al entorno de pruebas", systemImage: "shield.lefthalf.filled")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(LabTone.good)
                Text("Los datos sembrados de producción viven en otro lado y no se pueden borrar desde aquí. Tu credencial de administrador tampoco se elimina nunca.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastReset = lab.world.lastResetAt {
                    Text("Último reinicio: \(Fmt.dateShort(lastReset)) · \(Fmt.clock(lastReset))")
                        .font(.caption2)
                        .foregroundStyle(LabTone.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .labPanel()

            ForEach(LabStore.ResetTarget.allCases) { target in
                Button {
                    confirmation = ""
                    pending = target
                } label: {
                    LabRow(
                        title: target.label,
                        subtitle: target.detail,
                        symbol: target.symbol,
                        tint: target == .everything ? LabTone.bad : LabTone.accent
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(LabTone.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .alert(
            "¿Reiniciar \(pending?.label.lowercased() ?? "")?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            if pending == .everything {
                TextField("Escribe BORRAR", text: $confirmation)
            }
            Button("Reiniciar", role: .destructive) {
                if let target = pending, target != .everything || confirmation.uppercased() == "BORRAR" {
                    lab.reset(target)
                }
                pending = nil
                confirmation = ""
            }
            Button("Cancelar", role: .cancel) { pending = nil; confirmation = "" }
        } message: {
            Text(
                pending == .everything
                    ? "Se eliminan todos los registros de prueba. Escribe BORRAR para confirmar."
                    : (pending?.detail ?? "")
            )
        }
    }
}
