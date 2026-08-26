import SwiftUI

/// Alertas: the automatic board plus the incident log of the station.
struct SupervisorAlertsView: View {
    let supervision: SupervisionStore
    let header: SupervisorHeader
    @Binding var showsIncidents: Bool
    let onOpenTicket: (String) -> Void
    let onOpenDriver: (String) -> Void
    let onNewIncident: () -> Void

    private enum Segment: String, CaseIterable, Identifiable {
        case alerts
        case incidents

        var id: String { rawValue }
        var label: String {
            switch self {
            case .alerts: "Alertas automáticas"
            case .incidents: "Incidencias"
            }
        }
    }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header

                    Picker("Vista", selection: segmentBinding) {
                        ForEach(Segment.allCases) { segment in
                            Text(segment.label).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)

                    if showsIncidents {
                        incidentsSection
                    } else {
                        alertsSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var segmentBinding: Binding<Segment> {
        Binding(
            get: { showsIncidents ? .incidents : .alerts },
            set: { showsIncidents = $0 == .incidents }
        )
    }

    // MARK: - Alerts

    /// Membership: an alert joins this board when a driver crosses the grace boundary, with
    /// no event behind it. The scope wraps the alert block alone — the segmented picker, the
    /// incident section and the `ScrollView` stay outside it.
    private var alertsSection: some View {
        TimeScope(.minute) { now in
            let alerts = supervision.alerts(now: now)
            let critical = supervision.criticalAlerts(now: now)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatTile(
                        label: "Activas",
                        value: "\(alerts.count)",
                        hint: "Generadas por reglas",
                        tone: alerts.isEmpty ? .volt : .amber
                    )
                    StatTile(
                        label: "Gravedad alta",
                        value: "\(critical.count)",
                        hint: "Requieren acción inmediata",
                        tone: critical.isEmpty ? .volt : .danger
                    )
                }

                if !supervision.resolvedAlertIds.isEmpty {
                    Button {
                        supervision.restoreAlerts()
                    } label: {
                        Label("Restaurar \(supervision.resolvedAlertIds.count) alertas atendidas", systemImage: "arrow.uturn.backward")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(SupTone.accent)
                    }
                    .buttonStyle(.plain)
                }

                if alerts.isEmpty {
                    SupEmptyState(
                        symbol: "shield.checkered",
                        title: "Sin alertas activas",
                        message: "Retrasos, unidades sin escanear, baterías bajas, mantenimientos vencidos y diferencias de kilometraje aparecerán aquí al instante."
                    )
                } else {
                    ForEach(alerts) { alert in
                        AlertRow(
                            alert: alert,
                            onResolve: { supervision.resolveAlert(id: alert.id) },
                            action: {
                                if let ticketId = alert.ticketId {
                                    onOpenTicket(ticketId)
                                } else if let driverId = alert.driverId {
                                    onOpenDriver(driverId)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Incidents

    private var incidentsSection: some View {
        let incidents = supervision.allIncidents
        return VStack(alignment: .leading, spacing: 12) {
            BigButton(title: "Reportar incidencia", symbol: "exclamationmark.bubble.fill") {
                onNewIncident()
            }

            HStack(spacing: 10) {
                StatTile(
                    label: "Abiertas",
                    value: "\(incidents.filter { $0.status == .open }.count)",
                    hint: "Sin resolver",
                    tone: .danger
                )
                StatTile(
                    label: "En revisión",
                    value: "\(incidents.filter { $0.status == .review }.count)",
                    hint: "Con taller o seguros",
                    tone: .amber
                )
                StatTile(
                    label: "Cerradas",
                    value: "\(incidents.filter { $0.status == .closed }.count)",
                    hint: "Del periodo",
                    tone: .volt
                )
            }

            if incidents.isEmpty {
                SupEmptyState(
                    symbol: "checkmark.shield.fill",
                    title: "Sin incidencias",
                    message: "Registra accidentes, daños o fallas mecánicas con fotografías y nivel de gravedad."
                )
            } else {
                ForEach(incidents) { incident in
                    IncidentRow(
                        incident: incident,
                        onStatus: incident.id.hasPrefix("live-")
                            ? nil
                            : { status in supervision.setIncidentStatus(id: incident.id, status: status) }
                    )
                }
            }
        }
    }
}

/// Incident card with severity, evidence count and status control.
///
/// Like `AlertRow`, it keeps its own clock: only the age caption moves, and it moves
/// inside `RelativeTime`.
struct IncidentRow: View {
    let incident: StationIncident
    let onStatus: ((IncidentStatus) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: incident.kind.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(incident.severity.tone)
                    .frame(width: 32, height: 32)
                    .background(incident.severity.tone.opacity(0.14), in: .rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(incident.kind.label) · \(incident.vehicleNumber)")
                        .font(.system(.subheadline, weight: .black))
                    Text("\(incident.driverName) · reportó \(incident.reportedBy)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                StatePill(text: incident.severity.label, symbol: "waveform.path.ecg", tone: incident.severity.tone, compact: true)
            }

            Text(incident.detail)
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)

            if !incident.photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(incident.photos.enumerated()), id: \.offset) { item in
                            EvidenceThumb(caption: "Evidencia \(item.offset + 1)", data: item.element)
                                .frame(width: 120)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 8) {
                StatePill(
                    text: incident.status.label,
                    symbol: incident.status == .closed ? "checkmark.seal.fill" : "clock.fill",
                    tone: incident.status == .closed ? SupTone.good : SupTone.warn,
                    compact: true
                )
                RelativeTime(date: incident.createdAt)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: 0)
                if let onStatus, incident.status != .closed {
                    Menu {
                        if incident.status == .open {
                            Button("Enviar a revisión") { onStatus(.review) }
                        }
                        Button("Cerrar incidencia") { onStatus(.closed) }
                    } label: {
                        Text("Actualizar")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(SupTone.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panelFlat()
    }
}

// MARK: - Report form

/// Accident, damage and mechanical failure report with photos and severity.
struct SupervisorIncidentFormView: View {
    let supervision: SupervisionStore
    var presetDriverId: String?
    var presetVehicleNumber: String?

    @Environment(\.dismiss) private var dismiss

    @State private var kind: IncidentKind = .damage
    @State private var severity: IncidentSeverity = .medium
    @State private var driverId: String?
    @State private var vehicleNumber: String = ""
    @State private var detail: String = ""
    @State private var photos: [Data] = []
    /// Body angles, captured only here: the driver no longer photographs the unit at every start.
    @State private var bodyPhotos: [String: Data] = [:]

    /// Instant the roster menu is read against, taken once when the form opens.
    ///
    /// Deliberately not a cadence. This picker lists the whole roster, and no driver joins
    /// or leaves that list because time passed — only each row's *state* is temporal, and
    /// this menu shows no state. Subscribing a form to the minute so a name can stay still
    /// would be paying invalidation for nothing.
    @State private var rosterAt: Date = AppClock.now()

    private var canSubmit: Bool {
        !vehicleNumber.isEmpty && detail.trimmingCharacters(in: .whitespacesAndNewlines).count > 8
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        kindPicker
                        severityPicker
                        involvedCard
                        detailCard
                        photosCard
                        bodyCard

                        BigButton(title: "Registrar incidencia", symbol: "paperplane.fill", isEnabled: canSubmit) {
                            supervision.report(
                                kind: kind,
                                severity: severity,
                                driverId: driverId,
                                vehicleNumber: vehicleNumber,
                                detail: detail,
                                photos: photos + InspectionSlot.bodySlots.compactMap { bodyPhotos[$0.rawValue] }
                            )
                            dismiss()
                        }

                        Text("Las incidencias de gravedad alta o crítica retiran la unidad de operación de inmediato y notifican al conductor.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Nueva incidencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear {
                driverId = presetDriverId
                if let presetVehicleNumber {
                    vehicleNumber = presetVehicleNumber
                } else if let driver = supervision.driver(id: presetDriverId, now: rosterAt), let unit = driver.vehicleNumber {
                    vehicleNumber = unit
                }
            }
        }
        .presentationContentInteraction(.scrolls)
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Tipo de reporte")
            HStack(spacing: 8) {
                ForEach(IncidentKind.allCases, id: \.self) { option in
                    Button {
                        kind = option
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.symbol)
                                .font(.system(.footnote, weight: .bold))
                            Text(option.label)
                                .font(.system(size: 10, weight: .black))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(kind == option ? Palette.canvas : Palette.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(kind == option ? SupTone.accent : Palette.surfaceRaised.opacity(0.7), in: .rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(kind == option ? .clear : Palette.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var severityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Gravedad")
            HStack(spacing: 8) {
                ForEach(IncidentSeverity.allCases) { option in
                    Button {
                        severity = option
                    } label: {
                        Text(option.label)
                            .font(.system(.caption, weight: .black))
                            .foregroundStyle(severity == option ? Palette.canvas : option.tone)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(severity == option ? option.tone : option.tone.opacity(0.12), in: .rect(cornerRadius: 13))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13)
                                    .stroke(option.tone.opacity(severity == option ? 0 : 0.45), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(severity.hint)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
    }

    private var involvedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Involucrados")

            Menu {
                Button("Sin conductor (unidad en estación)") { driverId = nil }
                ForEach(supervision.allDrivers(now: rosterAt).prefix(60)) { driver in
                    Button("\(driver.shortName) · \(driver.vehicleNumber ?? "sin unidad")") {
                        driverId = driver.id
                        if let unit = driver.vehicleNumber { vehicleNumber = unit }
                    }
                }
            } label: {
                menuRow(
                    label: "Conductor",
                    value: supervision.driver(id: driverId, now: rosterAt)?.shortName ?? "Sin conductor",
                    symbol: "person.fill"
                )
            }

            Menu {
                ForEach(supervision.vehicles.prefix(100)) { vehicle in
                    Button("\(vehicle.internalNumber) · \(vehicle.state.label)") {
                        vehicleNumber = vehicle.internalNumber
                    }
                }
            } label: {
                menuRow(
                    label: "Unidad",
                    value: vehicleNumber.isEmpty ? "Selecciona" : vehicleNumber,
                    symbol: "car.side.fill"
                )
            }
        }
        .padding(16)
        .panel()
    }

    private func menuRow(label: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(SupTone.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                Text(value)
                    .font(.system(.subheadline, weight: .bold))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 14)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Descripción de los hechos")
            TextField("Qué pasó, dónde y cómo quedó la unidad", text: $detail, axis: .vertical)
                .font(.subheadline)
                .lineLimit(4...8)
                .padding(14)
                .panelFlat()
        }
    }

    /// The four body angles that used to be part of the driver's start of shift.
    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CapsLabel(text: "Carrocería de la unidad")
                Spacer()
                Text("\(bodyPhotos.count)/\(InspectionSlot.bodySlots.count)")
                    .font(.system(size: 10, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(bodyPhotos.count == InspectionSlot.bodySlots.count ? SupTone.good : Palette.textMuted)
            }

            Text("Opcional. Levanta los ángulos que documenten el daño; el conductor ya no los captura al iniciar turno.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(InspectionSlot.bodySlots, id: \.self) { slot in
                    PhotoSlotView(
                        title: slot.title,
                        hint: slot.hint,
                        data: bodyPhotos[slot.rawValue]
                    ) { data in
                        bodyPhotos[slot.rawValue] = data
                    }
                }
            }
        }
    }

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Fotografías (hasta 3)")
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    PhotoSlotView(
                        title: "Foto \(index + 1)",
                        hint: index == 0 ? "Daño principal" : nil,
                        data: photos.indices.contains(index) ? photos[index] : nil
                    ) { data in
                        if photos.indices.contains(index) {
                            photos[index] = data
                        } else {
                            photos.append(data)
                        }
                    }
                }
            }
        }
    }
}
