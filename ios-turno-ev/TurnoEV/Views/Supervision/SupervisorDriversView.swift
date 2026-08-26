import SwiftUI

/// Conductores: the roster of the supervised shift with big interactive cards.
struct SupervisorDriversView: View {
    let supervision: SupervisionStore
    let header: SupervisorHeader
    @Binding var filter: DriverFilter
    let onOpenDriver: (String) -> Void
    let onOpenTicket: (String) -> Void

    @State private var search: String = ""
    @State private var assigning: AssignmentTarget?

    private func rows(now: Date) -> [StationDriver] {
        supervision.drivers(matching: filter, search: search, now: now)
    }

    /// Person receiving a unit: a driver of the roster or an alta just sent by recruitment.
    struct AssignmentTarget: Identifiable, Hashable {
        let id: String
        let name: String
        let subtitle: String
    }

    /// Altas recruitment turned over that still have no unit tied to them.
    private var pendingHires: [HirePacket] {
        RecruitmentHandoff.hires(stationId: supervision.station.id)
            .filter { supervision.assignment(driverId: $0.id) == nil }
    }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header

                    searchField

                    // Membership: `.late` and `.absent` are states the clock decides, so a
                    // driver enters and leaves these filters with no event behind it. The
                    // counters and the list share one scope because they must never disagree
                    // about how many people are in the filter they label.
                    TimeScope(.minute) { now in
                        FilterScroller(
                            items: DriverFilter.allCases,
                            title: { $0.label },
                            symbol: { $0.symbol },
                            count: { supervision.drivers(matching: $0, now: now).count },
                            selection: $filter
                        )
                        .padding(.horizontal, -18)

                        rosterSection(rows: rows(now: now))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $assigning) { target in
            assignmentSheet(target: target)
        }
    }

    @ViewBuilder
    private func rosterSection(rows: [StationDriver]) -> some View {
        HStack {
            Text("\(rows.count) conductores")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Palette.textMuted)
            Spacer()
        }

        if !pendingHires.isEmpty {
            handoffSection
        }

        if rows.isEmpty {
            SupEmptyState(
                symbol: filter.symbol,
                title: "Sin conductores en este filtro",
                message: "Cambia el filtro o limpia la búsqueda para ver el resto de la plantilla."
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(rows) { driver in
                    DriverCard(
                        driver: driver,
                        ticket: supervision.ticket(forDriver: driver.id),
                        assignment: supervision.assignment(driverId: driver.id),
                        onOpen: { onOpenDriver(driver.id) },
                        onOpenTicket: onOpenTicket,
                        onAssignUnit: {
                            assigning = AssignmentTarget(
                                id: driver.id,
                                name: driver.name,
                                subtitle: "\(driver.employeeNumber) · turno \(driver.slot.label.lowercased())"
                            )
                        }
                    )
                }
            }
        }
    }

    private func assignmentSheet(target: AssignmentTarget) -> some View {
        SupervisorAssignUnitView(
            supervision: supervision,
            driverId: target.id,
            driverName: target.name,
            subtitle: target.subtitle
        )
    }

    /// Altas that recruitment already signed: the station receives the person and this
    /// supervisor decides which unit they drive.
    private var handoffSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CapsLabel(text: "Entregados por reclutamiento")
                Spacer()
                Text("\(pendingHires.count) sin unidad")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SupTone.warn)
            }

            ForEach(pendingHires) { packet in
                Button {
                    assigning = AssignmentTarget(
                        id: packet.id,
                        name: packet.name,
                        subtitle: "Alta de \(packet.recruiterName) · bloque \(packet.block.label.lowercased())"
                    )
                } label: {
                    HStack(spacing: 12) {
                        Text(packet.initials)
                            .font(.system(.caption, weight: .black))
                            .foregroundStyle(SupTone.accent)
                            .frame(width: 38, height: 38)
                            .background(SupTone.accent.opacity(0.14), in: .circle)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(packet.name)
                                .font(.system(.subheadline, weight: .black))
                                .lineLimit(1)
                            Text("Recibido de \(packet.recruiterName)")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }

                        Spacer(minLength: 0)

                        Text("Asignar unidad")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(SupTone.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(12)
                    .background(Palette.surfaceRaised.opacity(0.55), in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(Palette.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Palette.textMuted)
            TextField("Nombre, número de empleado o unidad", text: $search)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
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
    }
}

/// Large driver card: photo, name, unit, entry, shift state, money and credit.
struct DriverCard: View {
    let driver: StationDriver
    let ticket: HandoverTicket?
    var assignment: VehicleAssignment?
    let onOpen: () -> Void
    let onOpenTicket: (String) -> Void
    var onAssignUnit: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        DriverAvatar(driver: driver, size: 58)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(driver.name)
                                .font(.system(.subheadline, weight: .black))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("\(driver.employeeNumber) · \(assignment?.vehicleNumber ?? driver.vehicleNumber ?? "sin unidad")")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                            StatePill(text: driver.state.label, symbol: driver.state.symbol, tone: driver.state.tone)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(Fmt.mxn(driver.earningsMxn))
                                .font(.system(.subheadline, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(driver.earningsMxn > 0 ? SupTone.good : Palette.textMuted)
                            Text("\(driver.trips) viajes")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.textMuted)
                        }
                    }

                    HStack(spacing: 8) {
                        InfoChip(
                            symbol: "clock.fill",
                            text: driver.checkInAt.map { Fmt.clock($0) } ?? "sin entrada",
                            tone: driver.lateMinutes > 0 ? SupTone.warn : Palette.textMuted
                        )
                        if driver.lateMinutes > 0 {
                            InfoChip(symbol: "hourglass", text: "+\(Fmt.lateText(driver.lateMinutes))", tone: SupTone.warn)
                        }
                        if let assignment {
                            InfoChip(
                                symbol: assignment.kind.symbol,
                                text: assignment.kind.shortLabel,
                                tone: assignment.isSubstitute ? SupTone.warn : SupTone.good
                            )
                        }
                        InfoChip(
                            symbol: driver.creditState.symbol,
                            text: driver.creditState.shortLabel,
                            tone: driver.creditState.tone
                        )
                        if driver.openIncidents > 0 {
                            InfoChip(
                                symbol: "exclamationmark.triangle.fill",
                                text: "\(driver.openIncidents)",
                                tone: SupTone.bad
                            )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .buttonStyle(.plain)

            if assignment == nil, let onAssignUnit {
                Button(action: onAssignUnit) {
                    HStack(spacing: 8) {
                        Image(systemName: "car.badge.gearshape")
                        Text("Sin unidad · asignar ahora")
                            .font(.system(.footnote, weight: .black))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(SupTone.warn)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(SupTone.warn.opacity(0.12), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14).stroke(SupTone.warn.opacity(0.45), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            if let ticket {
                Button {
                    onOpenTicket(ticket.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: ticket.kind.symbol)
                        Text("\(ticket.kind.label) por firmar")
                            .font(.system(.footnote, weight: .black))
                        Spacer(minLength: 0)
                        Text("\(ticket.completedChecks)/\(ticket.requiredChecks.count)")
                            .font(.system(.caption, weight: .black))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(SupTone.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(SupTone.accent.opacity(0.12), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14).stroke(SupTone.accent.opacity(0.45), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .panel(cornerRadius: 22)
        .overlay(alignment: .topTrailing) {
            if driver.isLiveSession {
                Text("SESIÓN ACTIVA")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(Palette.canvas)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SupTone.good, in: .capsule)
                    .offset(x: -12, y: -7)
            }
        }
    }
}

struct InfoChip: View {
    let symbol: String
    let text: String
    let tone: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Palette.surfaceRaised.opacity(0.8), in: .capsule)
    }
}

// MARK: - Detail

/// Driver file the supervisor opens from the roster.
struct SupervisorDriverDetailView: View {
    let supervision: SupervisionStore
    let driverId: String
    let onOpenTicket: (String) -> Void
    let onReportIncident: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAssigning: Bool = false

    /// This sheet shows the driver's live state — demorado, ausente, en operación — and that
    /// state is decided by the clock, so the file has to be read against a moving instant
    /// rather than the one it happened to open on. `ClockAnchor` rather than `TimeScope`
    /// because `driver` feeds the whole body, including the navigation title.
    @State private var minuteAnchor: Date = AppClock.now()

    private var driver: StationDriver? { supervision.driver(id: driverId, now: minuteAnchor) }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()
                ClockAnchor(.minute, date: $minuteAnchor)

                if let driver {
                    ScrollView {
                        VStack(spacing: 14) {
                            identityCard(driver)
                            assignmentCard(driver)
                            shiftCard(driver)
                            if let ticket = supervision.ticket(forDriver: driver.id) {
                                Button {
                                    dismiss()
                                    onOpenTicket(ticket.id)
                                } label: {
                                    HandoverRow(ticket: ticket) {
                                        dismiss()
                                        onOpenTicket(ticket.id)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            incidentsCard(driver)
                            actions(driver)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    SupEmptyState(
                        symbol: "person.fill.questionmark",
                        title: "Conductor no disponible",
                        message: "El registro ya no forma parte del turno supervisado."
                    )
                    .padding(20)
                }
            }
            .navigationTitle("Expediente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $isAssigning) {
            if let driver {
                SupervisorAssignUnitView(
                    supervision: supervision,
                    driverId: driver.id,
                    driverName: driver.name,
                    subtitle: "\(driver.employeeNumber) · turno \(driver.slot.label.lowercased())"
                )
            }
        }
    }

    /// The unit tied to this driver. Only supervision writes it, and the driver app
    /// cotejas the QR of the shift against it.
    private func assignmentCard(_ driver: StationDriver) -> some View {
        let assignment = supervision.assignment(driverId: driver.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CapsLabel(text: "Unidad de planta")
                Spacer()
                if let assignment {
                    StatePill(
                        text: assignment.kind.label,
                        symbol: assignment.kind.symbol,
                        tone: assignment.isSubstitute ? SupTone.warn : SupTone.good,
                        compact: true
                    )
                } else {
                    StatePill(text: "Sin asignar", symbol: "car.badge.gearshape", tone: SupTone.bad, compact: true)
                }
            }

            if let assignment {
                DetailRow(label: "Unidad", value: assignment.vehicleNumber)
                if assignment.isSubstitute, let titular = assignment.titularVehicleNumber {
                    DetailRow(label: "Sustituye a", value: titular)
                }
                DetailRow(label: "Asignada por", value: assignment.assignedBy)
                DetailRow(label: "Desde", value: Fmt.dateShort(assignment.assignedAt))
                if !assignment.note.isEmpty {
                    Text(assignment.note)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                }
            } else {
                Text("Reclutamiento ya entregó a esta persona a la estación. Asigna la unidad con la que va a trabajar para que pueda iniciar turno.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            }

            BigButton(
                title: assignment == nil ? "Asignar unidad" : "Cambiar o retirar unidad",
                symbol: "car.badge.gearshape",
                tone: assignment == nil ? .volt : .outline
            ) {
                isAssigning = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func identityCard(_ driver: StationDriver) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                DriverAvatar(driver: driver, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(driver.name)
                        .font(.system(.headline, weight: .black))
                    Text("\(driver.employeeNumber) · \(driver.slot.label)")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                    StatePill(text: driver.state.label, symbol: driver.state.symbol, tone: driver.state.tone)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Palette.hairline)

            DetailRow(
                label: "Unidad asignada",
                value: supervision.assignment(driverId: driver.id)?.vehicleNumber ?? driver.vehicleNumber ?? "Sin asignar"
            )
            DetailRow(label: "Teléfono", value: driver.phone)
            DetailRow(label: "Calificación de plataforma", value: Fmt.rating(driver.platformRating))
            DetailRow(label: "Crédito", value: driver.creditState.label)
        }
        .padding(16)
        .panel()
    }

    private func shiftCard(_ driver: StationDriver) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Turno de hoy")
            HStack(spacing: 10) {
                StatTile(
                    label: "Entrada",
                    value: driver.checkInAt.map { Fmt.clock($0) } ?? "—",
                    hint: "Programado \(Fmt.clock(driver.scheduledStartAt))",
                    tone: driver.lateMinutes > 0 ? .amber : .volt
                )
                StatTile(
                    label: "Atraso",
                    value: Fmt.lateText(driver.lateMinutes),
                    hint: "Tolerancia 10 min",
                    tone: driver.lateMinutes > 0 ? .danger : .neutral
                )
            }
            HStack(spacing: 10) {
                StatTile(
                    label: "Facturado",
                    value: Fmt.mxn(driver.earningsMxn),
                    hint: "Meta \(Fmt.mxn(ShiftRules.goals(for: driver.group).dailyMxn))",
                    tone: .volt
                )
                StatTile(label: "Viajes", value: "\(driver.trips)", hint: "Meta 14 del día", tone: .info)
            }
        }
        .padding(16)
        .panel()
    }

    private func incidentsCard(_ driver: StationDriver) -> some View {
        let incidents = supervision.allIncidents.filter { $0.driverId == driver.id }
        return VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Incidencias del conductor")
            if incidents.isEmpty {
                Text("Sin incidencias registradas en su historial de estación.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(incidents) { incident in
                    IncidentRow(incident: incident, onStatus: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func actions(_ driver: StationDriver) -> some View {
        VStack(spacing: 10) {
            BigButton(title: "Levantar incidencia", symbol: "exclamationmark.bubble.fill", tone: .outline) {
                dismiss()
                onReportIncident(driver.id)
            }
            Text("Los reportes de limpieza, daños y puntualidad afectan los bonos del conductor y quedan en la base compartida.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
    }
}
