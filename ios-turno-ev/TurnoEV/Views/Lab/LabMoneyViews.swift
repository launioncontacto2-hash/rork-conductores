import SwiftUI

// MARK: - Credits

/// Used-unit contracts. The laboratory can put a contract in any state so the driver panel,
/// the manager desk and the settlement deduction can all be exercised.
struct LabCreditsView: View {
    @Environment(LabStore.self) private var lab

    @State private var isCreating: Bool = false
    @State private var editing: LabCredit?
    @State private var paymentTarget: LabCredit?
    @State private var paymentAmount: Int = 0

    var body: some View {
        LabScreen(section: .credits) {
            LabSectionTitle(
                title: "Créditos",
                subtitle: "Contratos de unidad usada: monto, plazo, abono semanal y comportamiento de pago.",
                symbol: "creditcard.fill"
            )

            Button("Nuevo crédito") { isCreating = true }
                .buttonStyle(LabButtonStyle(kind: .solid))
                .disabled(lab.world.driverUsers.isEmpty)

            if lab.world.driverUsers.isEmpty {
                LabEmptyState(
                    title: "Falta el conductor",
                    message: "Un crédito siempre pertenece a un conductor. Crea uno en Usuarios.",
                    symbol: "steeringwheel"
                )
            } else if lab.world.credits.isEmpty {
                LabEmptyState(
                    title: "Sin créditos",
                    message: "Ningún conductor tiene contrato. Crea uno para ver el panel de crédito con datos.",
                    symbol: "creditcard"
                )
            } else {
                summary
                ForEach(lab.world.credits) { credit in
                    creditCard(credit)
                }
            }
        }
        .sheet(isPresented: $isCreating) { LabCreditEditor(credit: nil) }
        .sheet(item: $editing) { credit in LabCreditEditor(credit: credit) }
        .alert("Registrar abono", isPresented: Binding(get: { paymentTarget != nil }, set: { if !$0 { paymentTarget = nil } })) {
            Button("Aplicar") {
                if let id = paymentTarget?.id { lab.registerCreditPayment(id: id, amountMxn: paymentAmount) }
                paymentTarget = nil
            }
            Button("Cancelar", role: .cancel) { paymentTarget = nil }
        } message: {
            Text("Se aplicará el abono semanal de \(Fmt.mxn(paymentAmount)) al contrato de \(paymentTarget?.driverName ?? "").")
        }
    }

    private var summary: some View {
        let outstanding = lab.world.credits.reduce(0) { $0 + $1.balanceMxn }
        let late = lab.world.credits.filter { $0.state == .late }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            LabStat(label: "Contratos", value: "\(lab.world.credits.count)", symbol: "doc.text.fill")
            LabStat(label: "Saldo", value: Fmt.mxn(outstanding), symbol: "banknote.fill")
            LabStat(label: "Atrasados", value: "\(late)", tint: late > 0 ? LabTone.bad : LabTone.good, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func creditCard(_ credit: LabCredit) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.driverName)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                    Text(credit.vehicleLabel)
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
                Spacer(minLength: 0)
                LabChip(
                    text: credit.state.label,
                    tint: credit.state == .late || credit.state == .suspended ? LabTone.bad : LabTone.good
                )
            }

            HStack(spacing: 8) {
                LabStat(label: "Monto", value: Fmt.mxn(credit.principalMxn), symbol: "tag.fill")
                LabStat(label: "Saldo", value: Fmt.mxn(credit.balanceMxn), tint: LabTone.accent, symbol: "banknote.fill")
                LabStat(label: "Semanas", value: "\(credit.weeksPaid)/\(credit.weeks)", symbol: "calendar")
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LabTone.raised)
                    Capsule()
                        .fill(LabTone.accent)
                        .frame(width: proxy.size.width * credit.progress)
                }
            }
            .frame(height: 7)

            LabOptionRow(
                label: "Estado",
                options: LabCreditState.allCases,
                selection: Binding(
                    get: { credit.state },
                    set: { lab.setCreditState(id: credit.id, state: $0) }
                ),
                title: \.label
            )

            HStack(spacing: 8) {
                Button("Abonar") {
                    paymentAmount = credit.weeklyMxn
                    paymentTarget = credit
                }
                .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("Editar") { editing = credit }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Spacer(minLength: 0)
                Button {
                    lab.deleteCredit(id: credit.id)
                } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(LabTone.bad)
                }
                .buttonStyle(.plain)
            }

            if !credit.movements.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    LabCaps(text: "Movimientos")
                    ForEach(credit.movements.prefix(3)) { movement in
                        HStack {
                            Text(movement.concept)
                                .font(.caption2)
                                .foregroundStyle(LabTone.muted)
                            Spacer(minLength: 0)
                            Text(Fmt.mxn(movement.amountMxn))
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(10)
                .labFlat(cornerRadius: 12)
            }
        }
        .padding(15)
        .labPanel()
    }
}

private struct LabCreditEditor: View {
    let credit: LabCredit?
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var driverId: String = ""
    @State private var vehicleId: String = ""
    @State private var principal: Int = 180_000
    @State private var weekly: Int = 1_200
    @State private var weeks: Int = 150
    @State private var weeksPaid: Int = 0
    @State private var state: LabCreditState = .active

    private var drivers: [LabUser] { lab.world.driverUsers }

    var body: some View {
        LabSheet(
            title: credit == nil ? "Nuevo crédito" : "Editar crédito",
            subtitle: "Sin enganche y con descuento semanal. El plazo se calcula solo con el monto y el abono.",
            isConfirmEnabled: !driverId.isEmpty && principal > 0 && weekly > 0,
            onConfirm: save
        ) {
            LabOptionRow(
                label: "Conductor",
                options: drivers.map(\.id),
                selection: $driverId,
                title: { id in drivers.first { $0.id == id }?.name ?? "—" }
            )

            if !lab.world.vehicles.isEmpty {
                LabOptionRow(
                    label: "Unidad objetivo",
                    options: lab.world.vehicles.map(\.id),
                    selection: $vehicleId,
                    title: { id in lab.world.vehicle(id: id)?.internalNumber ?? "—" }
                )
            }

            LabNumberField(label: "Monto total", value: $principal, range: 1000...1_000_000, step: 5000, suffix: "MXN")
            LabNumberField(label: "Abono semanal", value: $weekly, range: 100...20_000, step: 100, suffix: "MXN")
            LabNumberField(label: "Semanas pagadas", value: $weeksPaid, range: 0...400)
            LabOptionRow(label: "Estado", options: LabCreditState.allCases, selection: $state, title: \.label)

            VStack(alignment: .leading, spacing: 5) {
                LabCaps(text: "Plazo calculado")
                Text("\(weeks) semanas · \(Fmt.mxn(max(0, principal - weekly * weeksPaid))) de saldo tras \(weeksPaid) abono(s).")
                    .font(.footnote)
                    .foregroundStyle(LabTone.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()
        }
        .onAppear(perform: load)
        .onChange(of: principal) { _, _ in recalc() }
        .onChange(of: weekly) { _, _ in recalc() }
    }

    private func recalc() {
        weeks = weekly > 0 ? Int((Double(principal) / Double(weekly)).rounded(.up)) : 0
    }

    private func load() {
        guard let credit else {
            driverId = drivers.first?.id ?? ""
            vehicleId = lab.world.vehicles.first?.id ?? ""
            recalc()
            return
        }
        driverId = lab.world.users.first { $0.driverId == credit.driverId }?.id ?? ""
        vehicleId = credit.vehicleId ?? ""
        principal = credit.principalMxn
        weekly = credit.weeklyMxn
        weeks = credit.weeks
        weeksPaid = credit.weeksPaid
        state = credit.state
    }

    private func save() {
        guard let user = drivers.first(where: { $0.id == driverId }) else { return }
        let vehicle = lab.world.vehicle(id: vehicleId)
        let value = LabCredit(
            id: credit?.id ?? "labcrd-\(UUID().uuidString.prefix(8))",
            driverId: user.driverId ?? user.id,
            driverName: user.name,
            vehicleId: vehicle?.id,
            vehicleLabel: vehicle.map { "\($0.fullModel) · \($0.internalNumber)" } ?? "Unidad por asignar",
            principalMxn: principal,
            weeklyMxn: weekly,
            weeks: weeks,
            weeksPaid: weeksPaid,
            paidMxn: weekly * weeksPaid,
            startedAt: credit?.startedAt ?? Date(),
            endsAt: Date().addingTimeInterval(TimeInterval(weeks * 7 * 86400)),
            state: state,
            movements: credit?.movements ?? [],
            createdAt: credit?.createdAt ?? Date()
        )
        if lab.saveCredit(value) { dismiss() }
    }
}

// MARK: - Bonuses

struct LabBonusesView: View {
    @Environment(LabStore.self) private var lab
    @State private var isCreating: Bool = false

    var body: some View {
        LabScreen(section: .bonuses) {
            LabSectionTitle(
                title: "Reglas de bonos",
                subtitle: "Monto, condición, periodicidad y a qué rol aplica. Un bono sin regla no se puede ganar ni perder.",
                symbol: "rosette"
            )

            Button("Nuevo bono") { isCreating = true }
                .buttonStyle(LabButtonStyle(kind: .solid))

            if lab.world.bonuses.isEmpty {
                LabEmptyState(
                    title: "Sin bonos",
                    message: "No hay ninguna regla configurada. Crea la primera para que la pantalla de bonos tenga contenido.",
                    symbol: "rosette"
                )
            } else {
                ForEach(lab.world.bonuses) { bonus in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bonus.name)
                                    .font(.system(.subheadline, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(bonus.condition)
                                    .font(.caption)
                                    .foregroundStyle(LabTone.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Text(Fmt.mxn(bonus.amountMxn))
                                .font(.system(.headline, weight: .black))
                                .foregroundStyle(LabTone.accent)
                        }
                        HStack(spacing: 6) {
                            LabChip(text: bonus.period.label, symbol: "calendar", tint: LabTone.muted)
                            LabChip(text: bonus.role.shortLabel, symbol: bonus.role.symbol, tint: LabTone.muted)
                            LabChip(
                                text: bonus.isActive ? "Activo" : "Inactivo",
                                tint: bonus.isActive ? LabTone.good : LabTone.muted
                            )
                            Spacer(minLength: 0)
                            Button {
                                lab.deleteBonus(id: bonus.id)
                            } label: {
                                Image(systemName: "trash").font(.caption2).foregroundStyle(LabTone.bad)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(15)
                    .labPanel()
                }
            }
        }
        .sheet(isPresented: $isCreating) { LabBonusEditor() }
    }
}

private struct LabBonusEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var condition: String = ""
    @State private var amount: Int = 1_000
    @State private var period: LabBonusPeriod = .monthly
    @State private var role: StaffRole = .driver
    @State private var stationId: String = ""

    var body: some View {
        LabSheet(
            title: "Nuevo bono",
            isConfirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0,
            onConfirm: save
        ) {
            LabField(label: "Nombre", placeholder: "Bono de puntualidad", text: $name)
            LabField(label: "Condición", placeholder: "Cero minutos de atraso en la semana", text: $condition)
            LabNumberField(label: "Monto", value: $amount, range: 100...100_000, step: 100, suffix: "MXN")
            LabOptionRow(label: "Periodicidad", options: LabBonusPeriod.allCases, selection: $period, title: \.label)
            LabOptionRow(label: "Rol", options: StaffRole.operationalRoles, selection: $role, title: \.shortLabel, symbol: { $0.symbol })
            if !lab.world.stations.isEmpty {
                LabOptionRow(
                    label: "Estación (opcional)",
                    options: [""] + lab.world.stations.map(\.id),
                    selection: $stationId,
                    title: { id in id.isEmpty ? "Toda la red" : (lab.world.station(id: id)?.code ?? "—") }
                )
            }
        }
    }

    private func save() {
        let bonus = LabBonus(
            id: "labbon-\(UUID().uuidString.prefix(8))",
            name: name.trimmingCharacters(in: .whitespaces),
            detail: condition,
            amountMxn: amount,
            condition: condition.isEmpty ? "Sin condición definida" : condition,
            period: period,
            stationId: stationId.isEmpty ? nil : stationId,
            role: role,
            startsAt: Date(),
            endsAt: Date().addingTimeInterval(365 * 86400),
            isActive: true,
            createdAt: Date()
        )
        if lab.saveBonus(bonus) { dismiss() }
    }
}

// MARK: - Goals

struct LabGoalsView: View {
    @Environment(LabStore.self) private var lab
    @State private var isCreating: Bool = false

    var body: some View {
        LabScreen(section: .goals) {
            LabSectionTitle(
                title: "Metas",
                subtitle: "La meta por hora multiplicada por las horas del turno es lo que el conductor ve como objetivo diario.",
                symbol: "target"
            )

            Button("Nueva meta") { isCreating = true }
                .buttonStyle(LabButtonStyle(kind: .solid))

            if lab.world.goals.isEmpty {
                LabEmptyState(
                    title: "Sin metas",
                    message: "Sin metas configuradas la pantalla de objetivos del conductor arranca en cero.",
                    symbol: "target"
                )
            } else {
                ForEach(lab.world.goals) { goal in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.name)
                                    .font(.system(.subheadline, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(goal.scope.label) · \(goal.targetLabel)")
                                    .font(.caption)
                                    .foregroundStyle(LabTone.muted)
                            }
                            Spacer(minLength: 0)
                            LabChip(text: goal.group.label, symbol: "calendar", tint: LabTone.muted)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            LabStat(label: "Por hora", value: Fmt.mxn(goal.hourlyMxn), symbol: "clock.fill")
                            LabStat(label: "Diaria", value: Fmt.mxn(goal.dailyMxn), tint: LabTone.accent, symbol: "sun.max.fill")
                            LabStat(label: "Semanal", value: Fmt.mxn(goal.weeklyMxn), symbol: "calendar")
                            LabStat(label: "Viajes/día", value: "\(goal.tripsPerDay)", symbol: "car.fill")
                        }
                        HStack {
                            Spacer(minLength: 0)
                            Button("Eliminar") { lab.deleteGoal(id: goal.id) }
                                .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
                        }
                    }
                    .padding(15)
                    .labPanel()
                }
            }
        }
        .sheet(isPresented: $isCreating) { LabGoalEditor() }
    }
}

private struct LabGoalEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var scope: LabGoalScope = .national
    @State private var targetId: String = ""
    @State private var group: ShiftGroup = .weekday
    @State private var hourly: Int = 180
    @State private var hours: Int = 8
    @State private var trips: Int = 14

    var body: some View {
        LabSheet(
            title: "Nueva meta",
            isConfirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && hourly > 0,
            onConfirm: save
        ) {
            LabField(label: "Nombre", placeholder: "Meta base entre semana", text: $name)
            LabOptionRow(label: "Alcance", options: LabGoalScope.allCases, selection: $scope, title: \.label, symbol: { $0.symbol })
            if scope == .station, !lab.world.stations.isEmpty {
                LabOptionRow(
                    label: "Estación",
                    options: lab.world.stations.map(\.id),
                    selection: $targetId,
                    title: { id in lab.world.station(id: id)?.code ?? "—" }
                )
            }
            if scope == .driver, !lab.world.driverUsers.isEmpty {
                LabOptionRow(
                    label: "Conductor",
                    options: lab.world.driverUsers.map(\.id),
                    selection: $targetId,
                    title: { id in lab.world.user(id: id)?.name ?? "—" }
                )
            }
            LabOptionRow(label: "Grupo", options: ShiftGroup.allCases, selection: $group, title: \.label)
            LabNumberField(label: "Meta por hora", value: $hourly, range: 10...5_000, step: 10, suffix: "MXN")
            LabNumberField(label: "Horas por día", value: $hours, range: 1...14, suffix: "h")
            LabNumberField(label: "Viajes por día", value: $trips, range: 0...60)

            VStack(alignment: .leading, spacing: 5) {
                LabCaps(text: "Resultado")
                Text("\(Fmt.mxn(hourly * hours)) al día · \(Fmt.mxn(hourly * hours * 6)) a la semana.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()
        }
    }

    private func save() {
        let label: String = {
            switch scope {
            case .national: "Toda la red"
            case .station: lab.world.station(id: targetId)?.displayName ?? "—"
            case .driver: lab.world.user(id: targetId)?.name ?? "—"
            case .block: "Por bloque"
            }
        }()
        let goal = LabGoal(
            id: "labgoa-\(UUID().uuidString.prefix(8))",
            name: name.trimmingCharacters(in: .whitespaces),
            scope: scope,
            targetId: targetId.isEmpty ? nil : targetId,
            targetLabel: label,
            group: group,
            hourlyMxn: hourly,
            hoursPerDay: hours,
            tripsPerDay: trips,
            createdAt: Date()
        )
        if lab.saveGoal(goal) { dismiss() }
    }
}

// MARK: - Maintenance

struct LabMaintenanceView: View {
    @Environment(LabStore.self) private var lab
    @State private var isOrderPresented: Bool = false

    var body: some View {
        LabScreen(section: .maintenance) {
            LabSectionTitle(
                title: "Taller",
                subtitle: "Activos de la estación y órdenes de servicio. Cada unidad creada genera su activo automáticamente.",
                symbol: "wrench.and.screwdriver.fill"
            )

            Button("Nueva orden") { isOrderPresented = true }
                .buttonStyle(LabButtonStyle(kind: .solid))
                .disabled(lab.world.assets.isEmpty)

            assetsCard

            if lab.world.orders.isEmpty {
                LabEmptyState(
                    title: "Sin órdenes",
                    message: "El taller no tiene trabajo. Crea una orden para verla en la interfaz de mantenimiento.",
                    symbol: "wrench.and.screwdriver"
                )
            } else {
                ForEach(lab.world.orders) { order in
                    orderCard(order)
                }
            }
        }
        .sheet(isPresented: $isOrderPresented) { LabOrderEditor() }
    }

    private var assetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabCaps(text: "Activos")
                Spacer(minLength: 0)
                Text("\(lab.world.assets.count)")
                    .font(.system(.caption, weight: .black))
                    .foregroundStyle(LabTone.accent)
            }
            if lab.world.assets.isEmpty {
                Text("Sin activos registrados. Se crean solos al dar de alta unidades.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(lab.world.assets.prefix(6)) { asset in
                    LabRow(
                        title: asset.name,
                        subtitle: "\(asset.category.label) · \(asset.code)",
                        symbol: asset.category.symbol,
                        tint: asset.state == .operational ? LabTone.good : LabTone.bad
                    )
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    private func orderCard(_ order: WorkOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.folio)
                        .font(.system(.subheadline, weight: .black))
                        .foregroundStyle(.white)
                    Text("\(order.assetName) · \(order.assetCode)")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
                Spacer(minLength: 0)
                LabChip(text: order.priority.label, tint: order.priority == .critical ? LabTone.bad : LabTone.accent)
            }
            Text(order.problem)
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            LabOptionRow(
                label: "Estado",
                options: WorkOrderStatus.allCases,
                selection: Binding(
                    get: { order.status },
                    set: { lab.setOrderStatus(id: order.id, status: $0) }
                ),
                title: \.label,
                symbol: { $0.symbol }
            )

            HStack {
                Spacer(minLength: 0)
                Button("Eliminar") { lab.deleteOrder(id: order.id) }
                    .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
            }
        }
        .padding(15)
        .labPanel()
    }
}

private struct LabOrderEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var assetId: String = ""
    @State private var problem: String = ""
    @State private var priority: WorkOrderPriority = .medium
    @State private var isPreventive: Bool = false
    @State private var estimatedMinutes: Int = 120

    var body: some View {
        LabSheet(
            title: "Nueva orden",
            subtitle: "El SLA de la orden depende de su prioridad; vencerlo pesa en el índice de mantenimiento.",
            isConfirmEnabled: !assetId.isEmpty && !problem.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: save
        ) {
            LabOptionRow(
                label: "Activo",
                options: lab.world.assets.map(\.id),
                selection: $assetId,
                title: { id in lab.world.assets.first { $0.id == id }?.name ?? "—" }
            )
            LabField(label: "Problema", placeholder: "Qué hay que reparar", text: $problem)
            LabOptionRow(label: "Prioridad", options: WorkOrderPriority.allCases, selection: $priority, title: \.label)
            LabNumberField(label: "Minutos estimados", value: $estimatedMinutes, range: 15...1440, step: 15, suffix: "min")
            LabToggleRow(title: "Servicio preventivo", subtitle: "Cuenta en el índice de preventivos cumplidos", isOn: $isPreventive)
        }
        .onAppear { assetId = lab.world.assets.first?.id ?? "" }
    }

    private func save() {
        guard let asset = lab.world.assets.first(where: { $0.id == assetId }) else { return }
        let technician = lab.world.users(at: asset.stationId, role: .maintenance).first
        let order = WorkOrder(
            id: "labord-\(UUID().uuidString.prefix(8))",
            folio: "OT-\(String(format: "%04d", lab.world.orders.count + 1))",
            stationId: asset.stationId,
            assetId: asset.id,
            assetName: asset.name,
            assetCode: asset.code,
            category: asset.category,
            problem: problem,
            priority: priority,
            isPreventive: isPreventive,
            assignedAt: Date(),
            assignedByName: LabRules.adminAccount.name,
            technicianId: technician?.id ?? "sin-tecnico",
            technicianName: technician?.name ?? "Sin técnico asignado",
            acceptedAt: nil,
            finishedAt: nil,
            closedAt: nil,
            estimatedMinutes: estimatedMinutes,
            status: .pending,
            workDone: "",
            pendingWork: "",
            observations: "",
            materials: [],
            evidence: [],
            evidenceAssets: [],
            returnReason: nil,
            vehicleId: asset.vehicleId
        )
        if lab.saveOrder(order) { dismiss() }
    }
}

// MARK: - Finance

struct LabFinanceView: View {
    @Environment(LabStore.self) private var lab
    @State private var isBankPresented: Bool = false
    @State private var isSettlementPresented: Bool = false

    var body: some View {
        LabScreen(section: .finance) {
            LabSectionTitle(
                title: "Finanzas",
                subtitle: "Datos bancarios y liquidaciones semanales. Una CLABE solo puede existir una vez en toda la red.",
                symbol: "banknote.fill"
            )

            HStack(spacing: 8) {
                Button("Cuenta bancaria") { isBankPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .solid, isCompact: true))
                    .disabled(lab.world.driverUsers.isEmpty)
                Button("Liquidación") { isSettlementPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                    .disabled(lab.world.driverUsers.isEmpty)
            }

            if lab.world.driverUsers.isEmpty {
                LabEmptyState(
                    title: "Falta el conductor",
                    message: "El dinero siempre pertenece a alguien. Crea un conductor primero.",
                    symbol: "steeringwheel"
                )
            } else {
                banksCard
                settlementsCard
                transfersCard
            }
        }
        .sheet(isPresented: $isBankPresented) { LabBankEditor() }
        .sheet(isPresented: $isSettlementPresented) { LabSettlementEditor() }
    }

    private var banksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Cuentas bancarias")
            if lab.world.bankAccounts.isEmpty {
                Text("Ningún conductor tiene cuenta registrada.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(lab.world.bankAccounts) { account in
                    LabRow(
                        title: account.driverName,
                        subtitle: "\(account.bank) · \(account.maskedClabe)",
                        detail: account.status.label,
                        symbol: "building.columns.fill",
                        tint: account.status == .verified ? LabTone.good : LabTone.accent
                    ) {
                        Button {
                            lab.deleteBankAccount(id: account.id)
                        } label: {
                            Image(systemName: "trash").font(.caption2).foregroundStyle(LabTone.bad)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    private var settlementsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Liquidaciones")
            if lab.world.settlements.isEmpty {
                Text("Sin liquidaciones generadas.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(lab.world.settlements) { settlement in
                    LabRow(
                        title: settlement.rangeLabel,
                        subtitle: lab.world.users.first { $0.driverId == settlement.driverId }?.name ?? settlement.driverId,
                        detail: "Neto \(Fmt.mxn(settlement.netMxn)) · \(settlement.status.label)",
                        symbol: settlement.status.symbol,
                        tint: settlement.status == .transferred ? LabTone.good : LabTone.accent
                    ) {
                        Button {
                            lab.deleteSettlement(id: settlement.id)
                        } label: {
                            Image(systemName: "trash").font(.caption2).foregroundStyle(LabTone.bad)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    private var transfersCard: some View {
        Group {
            if !lab.world.transfers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LabCaps(text: "Dispersiones simuladas")
                    ForEach(lab.world.transfers.prefix(6)) { transfer in
                        LabRow(
                            title: transfer.driverName,
                            subtitle: transfer.outcome.appResponse,
                            detail: "\(Fmt.mxn(transfer.amountMxn)) · ref \(transfer.reference)",
                            symbol: transfer.outcome.symbol,
                            tint: LabTone.tone(for: transfer.outcome.result)
                        )
                    }
                }
                .padding(16)
                .labPanel()
            }
        }
    }
}

private struct LabBankEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var driverId: String = ""
    @State private var bank: String = "BBVA México"
    @State private var clabe: String = ""
    @State private var accountNumber: String = ""
    @State private var hasProof: Bool = true

    var body: some View {
        LabSheet(
            title: "Cuenta bancaria",
            subtitle: "Escribe una CLABE ya usada para comprobar que el sistema bloquea duplicados.",
            isConfirmEnabled: !driverId.isEmpty && clabe.filter(\.isNumber).count == 18,
            onConfirm: save
        ) {
            LabOptionRow(
                label: "Conductor",
                options: lab.world.driverUsers.map(\.id),
                selection: $driverId,
                title: { id in lab.world.user(id: id)?.name ?? "—" }
            )
            LabField(label: "Banco", placeholder: "BBVA México", text: $bank)
            LabField(label: "CLABE (18 dígitos)", placeholder: "646180000000000000", text: $clabe, keyboard: .numberPad)
            LabField(label: "Número de cuenta", placeholder: "Opcional", text: $accountNumber, keyboard: .numberPad)
            LabToggleRow(title: "Comprobante adjunto", isOn: $hasProof)

            Button("Generar CLABE de prueba") {
                clabe = LabRules.generateClabe(seed: Int(Date().timeIntervalSince1970) % 99_999)
            }
            .buttonStyle(LabButtonStyle(kind: .soft))
        }
        .onAppear { driverId = lab.world.driverUsers.first?.id ?? "" }
    }

    private func save() {
        guard let user = lab.world.user(id: driverId) else { return }
        let account = LabBankAccount(
            id: "labbnk-\(UUID().uuidString.prefix(8))",
            driverId: user.driverId ?? user.id,
            driverName: user.name,
            bank: bank,
            clabe: clabe.filter(\.isNumber),
            accountNumber: accountNumber,
            holder: user.name,
            hasProof: hasProof,
            status: hasProof ? .verified : .pending,
            registeredAt: Date()
        )
        if lab.saveBankAccount(account) { dismiss() }
    }
}

private struct LabSettlementEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var driverId: String = ""
    @State private var gross: Int = 8_000
    @State private var bonus: Int = 1_000
    @State private var creditDeduction: Int = 1_200
    @State private var status: SettlementStatus = .available

    private var net: Int { gross + bonus - creditDeduction - SettlementRules.serviceDeductionMxn }

    var body: some View {
        LabSheet(
            title: "Nueva liquidación",
            subtitle: "Bruto, bonos y descuentos de la semana. El neto es lo que se dispersa al banco.",
            isConfirmEnabled: !driverId.isEmpty,
            onConfirm: save
        ) {
            LabOptionRow(
                label: "Conductor",
                options: lab.world.driverUsers.map(\.id),
                selection: $driverId,
                title: { id in lab.world.user(id: id)?.name ?? "—" }
            )
            LabNumberField(label: "Ingreso bruto", value: $gross, range: 0...200_000, step: 500, suffix: "MXN")
            LabNumberField(label: "Bonos", value: $bonus, range: 0...50_000, step: 100, suffix: "MXN")
            LabNumberField(label: "Descuento de crédito", value: $creditDeduction, range: 0...50_000, step: 100, suffix: "MXN")
            LabOptionRow(label: "Estado", options: SettlementStatus.allCases, selection: $status, title: \.label, symbol: { $0.symbol })

            VStack(alignment: .leading, spacing: 5) {
                LabCaps(text: "Neto a transferir")
                Text(Fmt.mxn(net))
                    .font(.system(.title2, weight: .black))
                    .foregroundStyle(net >= 0 ? LabTone.good : LabTone.bad)
                Text("Incluye la deducción fija de servicio de \(Fmt.mxn(SettlementRules.serviceDeductionMxn)).")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()
        }
        .onAppear { driverId = lab.world.driverUsers.first?.id ?? "" }
    }

    private func save() {
        guard let user = lab.world.user(id: driverId) else { return }
        let weekStart = ShiftRules.weekStart(for: Date())
        let settlement = WeeklySettlement(
            id: "labset-\(UUID().uuidString.prefix(8))",
            driverId: user.driverId ?? user.id,
            weekStart: weekStart,
            weekEnd: weekStart.addingTimeInterval(6 * 86400),
            lines: [
                SettlementLine(id: "l1", concept: "Ingresos de la semana", detail: "Plataformas y efectivo", amountMxn: gross, kind: .income),
                SettlementLine(id: "l2", concept: "Bonos", detail: "Bonos ganados", amountMxn: bonus, kind: .bonus),
                SettlementLine(id: "l3", concept: "Abono de crédito", detail: "Descuento semanal", amountMxn: -creditDeduction, kind: .credit),
                SettlementLine(id: "l4", concept: "Servicio", detail: "Deducción fija", amountMxn: -SettlementRules.serviceDeductionMxn, kind: .deduction),
            ],
            status: status,
            requestedAt: nil,
            transferredAt: nil,
            closedAt: nil,
            adjustments: [],
            reviewNote: nil,
            reviewOpenedAt: nil
        )
        if lab.saveSettlement(settlement) { dismiss() }
    }
}
