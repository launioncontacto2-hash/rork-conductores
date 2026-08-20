import SwiftUI
import UIKit

/// Mantenimiento seen from supervision: assign work, follow it and validate the report
/// the technician sends back. The same orders open inside the maintenance interface.
struct SupervisorWorkshopView: View {
    let office: StationOfficeStore
    let header: SupervisorHeader

    @State private var filter: OrderFilter = .open
    @State private var route: Route?

    private enum Route: Identifiable, Hashable {
        case detail(String)
        case newOrder

        var id: String {
            switch self {
            case .detail(let id): "detail-\(id)"
            case .newOrder: "new"
            }
        }
    }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    summary
                    validationQueue
                    board
                    assets
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $route) { route in
            switch route {
            case .detail(let id):
                WorkOrderDetailView(office: office, orderId: id, isTechnician: false)
            case .newOrder:
                AssignOrderView(office: office)
            }
        }
    }

    private var metrics: WorkshopMetrics { office.workshopMetrics }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Taller de la estación",
                subtitle: "Vehículos, cargadores, energía, instalaciones y equipo",
                actionTitle: "Asignar orden"
            ) {
                route = .newOrder
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(label: "Abiertas", value: "\(metrics.openTotal)", hint: "Pendientes y en proceso", tone: metrics.openTotal > 0 ? .amber : .volt)
                StatTile(label: "Por validar", value: "\(metrics.awaitingValidation)", hint: "Reportes enviados", tone: metrics.awaitingValidation > 0 ? .amber : .volt)
                StatTile(label: "Disponibilidad", value: "\(Int(metrics.fleetAvailabilityRatio * 100))%", hint: "\(metrics.fleetAvailable) de \(metrics.fleetTotal) unidades", tone: metrics.fleetAvailabilityRatio >= 0.9 ? .volt : .danger)
                StatTile(label: "Resolución", value: Fmt.durationText(metrics.averageResolutionMinutes), hint: "Promedio", tone: .info)
            }
        }
        .padding(16)
        .panel()
    }

    private var validationQueue: some View {
        let orders = office.ordersAwaitingValidation
        return Group {
            if !orders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SupSectionHeader(
                        title: "Por validar",
                        subtitle: "El técnico terminó y espera tu firma"
                    )
                    ForEach(orders) { order in
                        WorkOrderRow(order: order, now: office.now) {
                            route = .detail(order.id)
                        }
                    }
                }
                .padding(16)
                .panel()
            }
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            FilterScroller(
                items: OrderFilter.allCases,
                title: { $0.label },
                symbol: { $0.symbol },
                count: { count(for: $0) },
                selection: $filter
            )
            .padding(.horizontal, -16)

            if visible.isEmpty {
                SupEmptyState(
                    symbol: "wrench.and.screwdriver",
                    title: "Sin órdenes",
                    message: "No hay órdenes de trabajo en este estado."
                )
            } else {
                ForEach(visible) { order in
                    WorkOrderRow(order: order, now: office.now) {
                        route = .detail(order.id)
                    }
                }
            }
        }
        .padding(16)
        .panel()
    }

    private var assets: some View {
        let down = office.assets.filter { $0.state != .operational }
        return Group {
            if !down.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SupSectionHeader(
                        title: "Activos con falla",
                        subtitle: "\(down.count) equipos fuera o degradados"
                    )
                    ForEach(down) { asset in
                        HStack(spacing: 10) {
                            Image(systemName: asset.category.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(asset.state.tone)
                                .frame(width: 28, height: 28)
                                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(asset.name)
                                    .font(.system(.footnote, weight: .bold))
                                Text("\(asset.code) · \(asset.category.label)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.textMuted)
                            }
                            Spacer(minLength: 4)
                            Text(asset.state.label)
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(asset.state.tone)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelFlat(cornerRadius: 14)
                    }
                }
                .padding(16)
                .panel()
            }
        }
    }

    private func count(for filter: OrderFilter) -> Int {
        switch filter {
        case .open: office.openOrders.count
        case .all: office.orders.count
        default: office.orders.filter { $0.status == filter.status }.count
        }
    }

    private var visible: [WorkOrder] {
        switch filter {
        case .open: office.openOrders
        case .all: office.orders(status: nil)
        default: office.orders(status: filter.status)
        }
    }
}

// MARK: - Filter

enum OrderFilter: String, CaseIterable, Identifiable, Hashable {
    case open
    case pending
    case inProgress
    case finished
    case closed
    case all

    var id: String { rawValue }

    var status: WorkOrderStatus? {
        switch self {
        case .pending: .pending
        case .inProgress: .inProgress
        case .finished: .finished
        case .closed: .closed
        case .open, .all: nil
        }
    }

    var label: String {
        switch self {
        case .open: "Abiertas"
        case .pending: "Pendientes"
        case .inProgress: "En proceso"
        case .finished: "Por validar"
        case .closed: "Cerradas"
        case .all: "Todas"
        }
    }

    var symbol: String {
        switch self {
        case .open: "tray.full.fill"
        case .pending: "tray.fill"
        case .inProgress: "wrench.and.screwdriver.fill"
        case .finished: "paperplane.fill"
        case .closed: "checkmark.seal.fill"
        case .all: "square.grid.2x2.fill"
        }
    }
}

// MARK: - Row

struct WorkOrderRow: View {
    let order: WorkOrder
    let now: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: order.category.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(order.priority.tone)
                    Text(order.folio)
                        .font(.system(size: 11, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textMuted)
                    Text(order.assetCode)
                        .font(.system(.footnote, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    StatePill(text: order.status.label, symbol: order.status.symbol, tone: order.status.tone, compact: true)
                }

                Text(order.problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 10) {
                    Label(order.priority.label, systemImage: "flag.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(order.priority.tone)
                    if order.isPreventive {
                        Label("Preventivo", systemImage: "calendar.badge.checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.info)
                    }
                    Spacer(minLength: 0)
                    if order.isOverdue(now: now) {
                        Label("Fuera de tiempo", systemImage: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Palette.danger)
                    } else {
                        Text(Fmt.relative(order.assignedAt, from: now))
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

/// One work order. The technician executes and reports; the supervisor validates.
struct WorkOrderDetailView: View {
    let office: StationOfficeStore
    let orderId: String
    let isTechnician: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var workDone: String = ""
    @State private var pendingWork: String = ""
    @State private var observations: String = ""
    @State private var materialName: String = ""
    @State private var materialQuantity: Int = 1
    @State private var showsCamera: Bool = false
    @State private var returnNote: String = ""
    @State private var isReturning: Bool = false
    @State private var reportError: String?

    private var order: WorkOrder? { office.order(id: orderId) }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()
                ScrollView {
                    if let order {
                        VStack(spacing: 14) {
                            headline(order)
                            timeline(order)
                            if isTechnician { technicianTools(order) } else { report(order) }
                            materials(order)
                            evidence(order)
                            actions(order)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 34)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(order?.folio ?? "Orden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
            .sheet(isPresented: $showsCamera) {
                EvidencePicker { data in
                    office.addEvidence(data, to: orderId)
                }
                .ignoresSafeArea()
            }
            .alert("Devolver la orden", isPresented: $isReturning) {
                TextField("¿Qué falta?", text: $returnNote)
                Button("Devolver", role: .destructive) {
                    office.validateOrder(id: orderId, approved: false, note: returnNote.isEmpty ? "Información insuficiente." : returnNote)
                    returnNote = ""
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Reporte incompleto", isPresented: .constant(reportError != nil)) {
                Button("Entendido") { reportError = nil }
            } message: {
                Text(reportError ?? "")
            }
            .task {
                if let order {
                    workDone = order.workDone
                    pendingWork = order.pendingWork
                    observations = order.observations
                }
            }
        }
    }

    private func headline(_ order: WorkOrder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: order.category.symbol)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Palette.volt)
                    .frame(width: 40, height: 40)
                    .background(Palette.volt.opacity(0.12), in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.assetName)
                        .font(.system(.subheadline, weight: .black))
                    Text("\(order.assetCode) · \(order.category.label)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
                StatePill(text: order.priority.label, symbol: "flag.fill", tone: order.priority.tone, compact: true)
            }

            Text(order.problem)
                .font(.footnote)

            DetailRow(label: "Estado", value: order.status.label, tone: order.status.tone)
            DetailRow(label: "Asignada", value: "\(Fmt.dateShort(order.assignedAt)) \(Fmt.clock(order.assignedAt)) · \(order.assignedByName)")
            DetailRow(label: "Responsable", value: order.technicianName)
            DetailRow(label: "Tiempo estimado", value: Fmt.durationText(order.estimatedMinutes))
            if let actual = order.actualMinutes {
                DetailRow(
                    label: "Tiempo real",
                    value: Fmt.durationText(actual),
                    tone: actual <= order.estimatedMinutes ? Palette.volt : Palette.amber
                )
            }
            DetailRow(
                label: "Compromiso",
                value: "\(Fmt.dateShort(order.dueAt)) \(Fmt.clock(order.dueAt))",
                tone: order.isOverdue(now: office.now) ? Palette.danger : .primary
            )

            if let reason = order.returnReason {
                NoticeBanner(symbol: "arrow.uturn.left.circle.fill", title: "Orden devuelta", message: reason, tone: .danger)
            }
        }
        .padding(16)
        .panel()
    }

    private func timeline(_ order: WorkOrder) -> some View {
        let steps: [(String, Bool)] = [
            ("Asignada", true),
            ("Aceptada", order.acceptedAt != nil),
            ("Ejecutada", order.finishedAt != nil),
            ("Validada", order.closedAt != nil),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                VStack(spacing: 5) {
                    Circle()
                        .fill(step.1 ? Palette.volt : Palette.surfaceRaised)
                        .frame(width: 10, height: 10)
                    Text(step.0)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(step.1 ? Palette.volt : Palette.textMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(13)
        .panel()
    }

    private func technicianTools(_ order: WorkOrder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Reporte de trabajo", subtitle: "Se envía a supervisión para validación")

            VStack(alignment: .leading, spacing: 6) {
                CapsLabel(text: "Trabajo realizado")
                TextEditor(text: $workDone)
                    .frame(minHeight: 84)
                    .scrollContentBackground(.hidden)
                    .padding(9)
                    .panelFlat()
            }
            VStack(alignment: .leading, spacing: 6) {
                CapsLabel(text: "Trabajo pendiente")
                TextEditor(text: $pendingWork)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(9)
                    .panelFlat()
            }
            VStack(alignment: .leading, spacing: 6) {
                CapsLabel(text: "Observaciones")
                TextEditor(text: $observations)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(9)
                    .panelFlat()
            }
        }
        .padding(16)
        .panel()
    }

    private func report(_ order: WorkOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Reporte del técnico", subtitle: "Lo que llegó del taller")
            if order.workDone.isEmpty {
                SupEmptyState(
                    symbol: "doc.text.magnifyingglass",
                    title: "Sin reporte todavía",
                    message: "El técnico aún no envía el trabajo realizado."
                )
            } else {
                DetailRow(label: "Trabajo realizado", value: order.workDone)
                if !order.pendingWork.isEmpty {
                    DetailRow(label: "Pendiente", value: order.pendingWork, tone: Palette.amber)
                }
                if !order.observations.isEmpty {
                    DetailRow(label: "Observaciones", value: order.observations)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func materials(_ order: WorkOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Materiales y refacciones")
            if order.materials.isEmpty {
                Text("Sin material registrado.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(order.materials) { material in
                    DetailRow(label: material.name, value: "\(material.quantity)")
                }
            }
            if isTechnician, order.status.isOpen {
                HStack(spacing: 8) {
                    TextField("Refacción", text: $materialName)
                        .padding(10)
                        .panelFlat(cornerRadius: 12)
                    Stepper("\(materialQuantity)", value: $materialQuantity, in: 1...20)
                        .labelsHidden()
                    Button {
                        guard !materialName.isEmpty else { return }
                        office.addMaterial(name: materialName, quantity: materialQuantity, to: orderId)
                        materialName = ""
                        materialQuantity = 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.volt)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func evidence(_ order: WorkOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Evidencias",
                subtitle: "Fotografías del trabajo",
                actionTitle: isTechnician && order.status.isOpen ? "Capturar" : nil
            ) {
                showsCamera = true
            }

            if !order.hasEvidence {
                SupEmptyState(
                    symbol: "camera.badge.ellipsis",
                    title: "Sin evidencias",
                    message: "No se puede enviar el reporte sin al menos una fotografía del trabajo."
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(order.evidence.enumerated()), id: \.offset) { index, data in
                        EvidenceThumb(caption: "Captura \(index + 1)", data: data)
                    }
                    ForEach(order.evidenceAssets, id: \.self) { asset in
                        EvidenceThumb(caption: "Archivo", asset: asset)
                    }
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func actions(_ order: WorkOrder) -> some View {
        VStack(spacing: 10) {
            if isTechnician {
                switch order.status {
                case .pending:
                    BigButton(title: "Aceptar orden", symbol: "hand.raised.fill") {
                        office.acceptOrder(id: orderId)
                    }
                case .inProgress, .waiting, .returned:
                    BigButton(title: "Enviar reporte a supervisión", symbol: "paperplane.fill") {
                        submit(order)
                    }
                    BigButton(
                        title: order.status == .waiting ? "Reanudar trabajo" : "Poner en espera",
                        symbol: order.status == .waiting ? "play.fill" : "pause.fill",
                        tone: .outline
                    ) {
                        office.setOrderStatus(order.status == .waiting ? .inProgress : .waiting, id: orderId)
                    }
                default:
                    EmptyView()
                }
            } else {
                if order.status == .finished {
                    BigButton(title: "Aprobar y cerrar orden", symbol: "checkmark.seal.fill") {
                        office.validateOrder(id: orderId, approved: true, note: "")
                        dismiss()
                    }
                    BigButton(title: "Devolver al técnico", symbol: "arrow.uturn.left", tone: .outline) {
                        isReturning = true
                    }
                } else if order.status.isOpen {
                    BigButton(title: "Cancelar orden", symbol: "xmark.circle.fill", tone: .outline) {
                        office.setOrderStatus(.cancelled, id: orderId)
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit(_ order: WorkOrder) {
        let sent = office.submitReport(
            id: orderId,
            workDone: workDone,
            pendingWork: pendingWork,
            observations: observations
        )
        if sent {
            dismiss()
        } else {
            reportError = "Captura el trabajo realizado y adjunta al menos una evidencia fotográfica."
        }
    }
}

// MARK: - Assign

/// New work order. Any asset of the station can be assigned, not only vehicles.
struct AssignOrderView: View {
    let office: StationOfficeStore

    @Environment(\.dismiss) private var dismiss
    @State private var category: AssetCategory = .vehicles
    @State private var assetId: String = ""
    @State private var problem: String = ""
    @State private var priority: WorkOrderPriority = .medium
    @State private var estimatedMinutes: Int = 60
    @State private var isPreventive: Bool = false

    private var assets: [StationAsset] { office.assets(category: category) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activo") {
                    Picker("Categoría", selection: $category) {
                        ForEach(AssetCategory.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                    Picker("Activo", selection: $assetId) {
                        Text("Selecciona").tag("")
                        ForEach(assets) { asset in
                            Text("\(asset.code) · \(asset.name)").tag(asset.id)
                        }
                    }
                }

                Section("Trabajo") {
                    TextField("Problema o servicio", text: $problem, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Prioridad", selection: $priority) {
                        ForEach(WorkOrderPriority.allCases) { option in
                            Text("\(option.label) · \(option.slaHours) h").tag(option)
                        }
                    }
                    Stepper("Tiempo estimado: \(Fmt.durationText(estimatedMinutes))", value: $estimatedMinutes, in: 15...480, step: 15)
                    Toggle("Mantenimiento preventivo", isOn: $isPreventive)
                }

                Section {
                    Text("La orden llega al personal de mantenimiento de tu estación. Al terminar, te devuelve el reporte con evidencias para que lo valides.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SupervisionBackground())
            .navigationTitle("Nueva orden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Asignar") {
                        office.assignOrder(
                            assetId: assetId,
                            problem: problem,
                            priority: priority,
                            estimatedMinutes: estimatedMinutes,
                            isPreventive: isPreventive
                        )
                        dismiss()
                    }
                    .disabled(assetId.isEmpty || problem.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(Palette.volt)
                }
            }
            .task {
                assetId = assets.first?.id ?? ""
            }
            .onChange(of: category) { _, _ in
                assetId = assets.first?.id ?? ""
            }
        }
    }
}
