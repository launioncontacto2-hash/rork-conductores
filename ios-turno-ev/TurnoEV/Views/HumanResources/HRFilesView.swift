import SwiftUI

/// Biblioteca digital de expedientes. Nothing is ever deleted here: a replaced document
/// keeps its previous versions and every movement stays in the timeline.
struct HRFilesView: View {
    let office: StationOfficeStore

    @State private var search: String = ""
    @State private var block: BlockFilter = .all
    @State private var onlyIssues: Bool = false
    @State private var selected: String?

    enum BlockFilter: String, CaseIterable, Identifiable, Hashable {
        case all
        case weekdayMorning
        case weekdayEvening
        case weekendMorning
        case weekendEvening

        var id: String { rawValue }

        var block: ShiftBlock? {
            switch self {
            case .all: nil
            case .weekdayMorning: .weekdayMorning
            case .weekdayEvening: .weekdayEvening
            case .weekendMorning: .weekendMorning
            case .weekendEvening: .weekendEvening
            }
        }

        var label: String { block?.shortLabel ?? "Todos" }
        var symbol: String { block?.symbol ?? "folder.fill" }
    }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 12) {
                    FilterScroller(
                        items: BlockFilter.allCases,
                        title: { $0.label },
                        symbol: { $0.symbol },
                        count: { office.files(block: $0.block).count },
                        selection: $block
                    )
                    .padding(.horizontal, -18)

                    Toggle(isOn: $onlyIssues) {
                        Text("Solo expedientes con pendientes")
                            .font(.system(.footnote, weight: .semibold))
                    }
                    .tint(Palette.volt)
                    .padding(12)
                    .panelFlat()

                    summary

                    if files.isEmpty {
                        SupEmptyState(
                            symbol: "folder.badge.questionmark",
                            title: "Sin expedientes",
                            message: "Ningún expediente coincide con la búsqueda."
                        )
                    } else {
                        ForEach(files) { file in
                            EmployeeFileRow(file: file) { selected = file.id }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .searchable(text: $search, prompt: "Nombre, número, CURP o RFC")
        .navigationTitle("Expedientes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.canvas, for: .navigationBar)
        .sheet(item: Binding(get: { selected.map(FileRoute.init) }, set: { selected = $0?.id })) { route in
            EmployeeFileView(office: office, fileId: route.id)
        }
    }

    private struct FileRoute: Identifiable, Hashable {
        let id: String
    }

    private var files: [EmployeeFile] {
        office.searchFiles(search, block: block.block, onlyIssues: onlyIssues)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatTile(label: "Expedientes", value: "\(office.activeFiles.count)", hint: "Activos", tone: .neutral)
            StatTile(
                label: "Incompletos",
                value: "\(office.incompleteFiles.count)",
                hint: "Falta documentación",
                tone: office.incompleteFiles.isEmpty ? .volt : .amber
            )
            StatTile(
                label: "Vencidos",
                value: "\(office.expiredDocumentFiles.count)",
                hint: "Bloquean turno",
                tone: office.expiredDocumentFiles.isEmpty ? .volt : .danger
            )
        }
    }
}

/// One file in the search list.
///
/// The completion percentage is the only thing the clock decides here, and it decides both
/// the number and its colour — so the row is the unit and it owns the scope. A list of two
/// hundred employees invalidates two hundred rows at most, and never the `ScrollView`, the
/// search field, the block filter or the summary tiles above them.
private struct EmployeeFileRow: View {
    let file: EmployeeFile
    let onOpen: () -> Void

    var body: some View {
        TimeScope(.minute) { now in
            let pct = file.completionPct(now: now)
            PersonRow(
                title: file.shortName,
                subtitle: "\(file.employeeNumber) · \(file.block.shortLabel) · \(file.status.label)",
                initials: file.initials,
                tone: file.status.tone,
                trailing: "\(pct)%",
                trailingTone: pct == 100 ? Palette.volt : Palette.amber,
                isLive: file.isLiveSession,
                action: onOpen
            )
        }
    }
}

// MARK: - Employee file

/// One driver's digital file: identity, documents by category, banking and history.
struct EmployeeFileView: View {
    let office: StationOfficeStore
    let fileId: String

    @Environment(\.dismiss) private var dismiss
    @State private var showsBankForm: Bool = false
    @State private var showsBlockChange: Bool = false
    @State private var newBlock: ShiftBlock = .weekdayMorning
    @State private var blockReason: String = ""

    private var file: EmployeeFile? { office.file(id: fileId) }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()
                ScrollView {
                    if let file {
                        VStack(spacing: 14) {
                            headline(file)
                            completion(file)
                            documents(file)
                            banking(file)
                            history(file)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 34)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Expediente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
            .sheet(isPresented: $showsBankForm) {
                if let file {
                    BankRegistrationView(office: office, file: file)
                }
            }
            .alert("Cambio de turno", isPresented: $showsBlockChange) {
                TextField("Motivo", text: $blockReason)
                Button("Aplicar") {
                    office.changeBlock(newBlock, for: fileId, reason: blockReason.isEmpty ? "Sin motivo capturado" : blockReason)
                    blockReason = ""
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("El movimiento queda asentado en el expediente y en la bitácora de auditoría.")
            }
        }
    }

    private func headline(_ file: EmployeeFile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Color(Palette.surfaceRaised)
                    .frame(width: 62, height: 62)
                    .overlay {
                        if let asset = file.photoAsset {
                            Image(asset)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        } else {
                            Text(file.initials)
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(file.status.tone)
                        }
                    }
                    .clipShape(.circle)
                    .overlay { Circle().stroke(file.status.tone.opacity(0.55), lineWidth: 2) }

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(.headline, weight: .black))
                    Text("\(file.employeeNumber) · \(office.station.code)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                    StatePill(text: file.status.label, symbol: file.status.symbol, tone: file.status.tone, compact: true)
                }
                Spacer(minLength: 0)
            }

            DetailRow(label: "Turno", value: "\(file.block.label) · \(file.block.scheduleLabel)")
            DetailRow(label: "Ingreso", value: Fmt.dateLong(file.hiredAt))
            DetailRow(label: "Alta firmada por", value: file.supervisorName)
            DetailRow(label: "Teléfono", value: file.phone)
            DetailRow(label: "CURP", value: file.curp)
            DetailRow(label: "RFC", value: file.rfc)

            Button {
                newBlock = file.block
                showsBlockChange = true
            } label: {
                Label("Cambiar turno", systemImage: "arrow.left.arrow.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.volt)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .panel()
    }

    /// Percentage, progress bar, missing list and the blocking banner all move together
    /// when a document crosses its expiry date, so the card is the smallest honest unit and
    /// the scope stops there. The `ScrollView`, the identity card above and the documents,
    /// banking and history panels below are never re-evaluated by the clock.
    private func completion(_ file: EmployeeFile) -> some View {
        TimeScope(.minute) { now in
            let pct = file.completionPct(now: now)
            let missing = file.missingDocuments(now: now)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Expediente \(pct) % completo")
                        .font(.system(.headline, weight: .black))
                        .foregroundStyle(pct == 100 ? Palette.volt : Palette.amber)
                    Spacer(minLength: 0)
                }
                ProgressTrack(value: Double(pct), goal: 100, tone: pct == 100 ? Palette.volt : Palette.amber)
                if missing.isEmpty {
                    Text("Sin documentos faltantes.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                } else {
                    Text("Faltan: \(missing.map(\.label).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                if file.hasCriticalExpired(now: now) {
                    NoticeBanner(
                        symbol: "calendar.badge.exclamationmark",
                        title: "Documentación crítica vencida",
                        message: "No puede tomar turno hasta actualizar licencia o identificación oficial.",
                        tone: .danger
                    )
                }
            }
            .padding(16)
            .panel()
        }
    }

    private func documents(_ file: EmployeeFile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Documentos", subtitle: "Organizados por categoría, con versiones anteriores")
            ForEach(DocumentCategory.allCases) { category in
                let documents = file.documents.filter { $0.kind.category == category }
                if !documents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(category.label, systemImage: category.symbol)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Palette.textMuted)
                        ForEach(documents) { document in
                            // The row keeps its own clock; the closure is action time — the
                            // instant the desk toggles the document, not a cadence.
                            DocumentRow(document: document) {
                                let status = document.resolvedStatus(now: office.now)
                                office.setDocument(
                                    document.kind,
                                    status: status == .delivered ? .pending : .delivered,
                                    expiresAt: document.kind.expires
                                        ? office.now.addingTimeInterval(365 * 86_400)
                                        : nil,
                                    for: file.id
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func banking(_ file: EmployeeFile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Información financiera",
                subtitle: "La cuenta bancaria la registra la supervisión de la estación",
                actionTitle: file.bank == nil ? "Registrar" : "Sustituir"
            ) {
                showsBankForm = true
            }

            if let bank = file.bank {
                DetailRow(label: "Banco", value: bank.bank)
                DetailRow(label: "CLABE", value: bank.maskedClabe)
                DetailRow(label: "Titular", value: bank.holder)
                DetailRow(label: "RFC", value: bank.rfc)
                DetailRow(label: "Registro", value: "\(Fmt.dateShort(bank.registeredAt)) · \(bank.registeredBy)")
                DetailRow(label: "Estado", value: bank.status.label, tone: bank.status.tone)
                Text("El conductor puede consultar sus datos, nunca modificarlos: cualquier cambio pasa por solicitud, validación de supervisión y aprobación de gerencia.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            } else {
                SupEmptyState(
                    symbol: "building.columns",
                    title: "Sin cuenta registrada",
                    message: "Registra banco, CLABE y comprobante para poder dispersar su liquidación semanal."
                )
            }

            let requests = office.bankRequests(driverId: file.id)
            if !requests.isEmpty {
                ForEach(requests) { request in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(request.status.tone)
                        Text("\(request.bank) · \(request.maskedClabe)")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 4)
                        Text(request.status.label)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(request.status.tone)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat(cornerRadius: 12)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func history(_ file: EmployeeFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Historial", subtitle: "Movimientos laborales del expediente")
            ForEach(file.events) { event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: event.kind.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.volt)
                        .frame(width: 26, height: 26)
                        .background(Palette.surfaceRaised, in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.kind.label)
                            .font(.system(.footnote, weight: .bold))
                        Text(event.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                        Text("\(Fmt.dateShort(event.date)) · \(event.author)")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 0)
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

// MARK: - Bank registration

/// Initial bank registration by the supervisor, with the national CLABE check.
struct BankRegistrationView: View {
    let office: StationOfficeStore
    let file: EmployeeFile

    @Environment(\.dismiss) private var dismiss

    @State private var bank: String = ""
    @State private var clabe: String = ""
    @State private var accountNumber: String = ""
    @State private var holder: String = ""
    @State private var rfc: String = ""
    @State private var hasProof: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    TextField("Banco", text: $bank)
                    TextField("CLABE (18 dígitos)", text: $clabe).keyboardType(.numberPad)
                    TextField("Número de cuenta", text: $accountNumber).keyboardType(.numberPad)
                    TextField("Nombre del titular", text: $holder)
                    TextField("RFC", text: $rfc).textInputAutocapitalization(.characters)
                    Toggle("Comprobante bancario adjunto", isOn: $hasProof)
                }
                Section {
                    Text("Una CLABE solo puede estar asociada a un conductor dentro de toda la red nacional. Si ya existe, el registro se bloquea y el intento queda en auditoría.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SupervisionBackground())
            .navigationTitle("Alta bancaria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Registrar") { register() }
                        .disabled(bank.isEmpty || clabe.count < 18)
                        .tint(Palette.volt)
                }
            }
            .alert("No se pudo registrar", isPresented: .constant(errorMessage != nil)) {
                Button("Entendido") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                holder = file.name
                rfc = file.rfc
            }
        }
    }

    private func register() {
        let result = office.registerBank(
            fileId: file.id,
            bank: bank,
            clabe: clabe,
            accountNumber: accountNumber,
            holder: holder,
            rfc: rfc,
            hasProof: hasProof
        )
        if let message = result.message {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}

// MARK: - Bank requests

/// Solicitudes bancarias: driver asks, supervisor validates, manager approves, station applies.
struct HRBankRequestsView: View {
    let office: StationOfficeStore

    @State private var note: String = ""
    @State private var resolving: String?

    var body: some View {
        OfficeScreen(title: "Solicitudes bancarias") {
            if office.bankRequests.isEmpty {
                SupEmptyState(
                    symbol: "building.columns",
                    title: "Sin solicitudes",
                    message: "Cuando un conductor pida cambiar su cuenta, aparecerá aquí con sus validaciones."
                )
            } else {
                ForEach(office.bankRequests.sorted { $0.createdAt > $1.createdAt }) { request in
                    card(for: request)
                }
            }
        }
        .alert("Resolución", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } })) {
            TextField("Nota para el conductor", text: $note)
            Button("Aprobar") {
                if let id = resolving {
                    office.resolveBankRequest(id: id, approved: true, note: note.isEmpty ? "Documentación conforme." : note)
                }
                note = ""
            }
            Button("Rechazar", role: .destructive) {
                if let id = resolving {
                    office.resolveBankRequest(id: id, approved: false, note: note.isEmpty ? "Documentación insuficiente." : note)
                }
                note = ""
            }
            Button("Cancelar", role: .cancel) { note = "" }
        }
    }

    private func card(for request: BankChangeRequest) -> some View {
        let validations = office.validations(for: request)
        let blocked = validations.contains { $0.isBlocking && !$0.passed }
        let needsManual = validations.contains { !$0.isBlocking && !$0.passed }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.driverName)
                        .font(.system(.subheadline, weight: .black))
                    Text("\(request.bank) · \(request.maskedClabe)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 4)
                StatePill(text: request.status.label, symbol: "arrow.triangle.branch", tone: request.status.tone, compact: true)
            }

            Text(request.reason)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)

            VStack(spacing: 7) {
                ForEach(validations) { validation in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: validation.passed ? "checkmark.circle.fill" : (validation.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(validation.passed ? Palette.volt : (validation.isBlocking ? Palette.danger : Palette.amber))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(validation.title)
                                .font(.system(size: 11, weight: .bold))
                            Text(validation.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(11)
            .panelFlat(cornerRadius: 14)

            if blocked {
                NoticeBanner(
                    symbol: "lock.fill",
                    title: "Solicitud bloqueada",
                    message: "Una validación obligatoria no se cumple. No se puede aplicar el cambio.",
                    tone: .danger
                )
            } else if needsManual {
                NoticeBanner(
                    symbol: "person.fill.questionmark",
                    title: "Requiere revisión manual",
                    message: "El domicilio no coincide exactamente. No se rechaza de forma automática.",
                    tone: .amber
                )
            }

            HStack(spacing: 10) {
                if request.status == .requested {
                    BigButton(title: "Validar y enviar a gerencia", symbol: "checkmark.shield.fill", isEnabled: !blocked) {
                        office.validateBankRequest(id: request.id)
                    }
                } else if request.status == .review {
                    BigButton(title: "Resolver", symbol: "signature", isEnabled: !blocked) {
                        resolving = request.id
                    }
                } else if request.status == .approved {
                    BigButton(title: "Aplicar al expediente", symbol: "arrow.down.doc.fill") {
                        office.applyBankRequest(id: request.id)
                    }
                }
            }

            if let resolution = request.resolutionNote {
                DetailRow(label: "Resolución", value: resolution)
            }
            Text("Flujo: conductor → solicitud → supervisor → validación → gerente → aprobación → cambio. La cuenta anterior se conserva en el historial.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }
}

// MARK: - Audit

/// Bitácora inmutable: supervisors read it, nobody edits it.
struct AuditTrailView: View {
    let office: StationOfficeStore

    var body: some View {
        OfficeScreen(title: "Auditoría") {
            NoticeBanner(
                symbol: "lock.doc.fill",
                title: "Registro inmutable",
                message: "Ninguna acción de esta bitácora puede modificarse o eliminarse desde supervisión.",
                tone: .info
            )

            if office.audit.isEmpty {
                SupEmptyState(
                    symbol: "doc.text.magnifyingglass",
                    title: "Sin movimientos",
                    message: "Aquí quedará registrada cada alta, baja, cambio bancario, aprobación u orden de mantenimiento."
                )
            } else {
                ForEach(office.audit) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.action.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.volt)
                            Text(entry.action.label)
                                .font(.system(.footnote, weight: .black))
                            Spacer(minLength: 4)
                            Text(Fmt.clock(entry.createdAt))
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textMuted)
                        }
                        Text(entry.subject)
                            .font(.system(size: 11, weight: .semibold))
                        if let previous = entry.previousValue {
                            DetailRow(label: "Valor anterior", value: previous)
                        }
                        if let newValue = entry.newValue {
                            DetailRow(label: "Valor nuevo", value: newValue)
                        }
                        if let reason = entry.reason {
                            DetailRow(label: "Motivo", value: reason)
                        }
                        if let authorizer = entry.authorizerName {
                            DetailRow(label: "Autorizó", value: authorizer)
                        }
                        Text("\(entry.actorName) · \(entry.actorRole.shortLabel) · \(Fmt.dateShort(entry.createdAt))")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat()
                }
            }
        }
    }
}
