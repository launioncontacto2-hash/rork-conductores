import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Human resources

/// Employee files. They are created automatically with every driver credential, and this
/// screen is where documents, vigencias and bajas are exercised.
struct LabHumanResourcesView: View {
    @Environment(LabStore.self) private var lab

    @State private var documentTarget: EmployeeFile?
    @State private var search: String = ""

    private var files: [EmployeeFile] {
        lab.world.employeeFiles.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        LabScreen(section: .humanResources) {
            LabSectionTitle(
                title: "Expedientes",
                subtitle: "Cada conductor creado abre expediente con sus documentos críticos en pendiente. Un documento vencido saca al conductor de la operación.",
                symbol: "folder.fill.badge.person.crop"
            )

            if lab.world.employeeFiles.isEmpty {
                LabEmptyState(
                    title: "Sin expedientes",
                    message: "Los expedientes nacen al crear un conductor en Usuarios. Crea uno para poder cargar documentos y probar vigencias.",
                    symbol: "folder"
                )
            } else {
                summary
                LabField(label: "Buscar", placeholder: "Nombre del empleado", text: $search)
                ForEach(files) { file in
                    fileCard(file)
                }
            }
        }
        .sheet(item: $documentTarget) { file in
            LabDocumentCapture(subjectId: file.id, subjectName: file.name)
        }
    }

    private var summary: some View {
        let pending = lab.world.employeeFiles.reduce(0) { total, file in
            total + file.documents.filter { $0.status == .pending }.count
        }
        let expired = lab.world.employeeFiles.reduce(0) { total, file in
            total + file.documents.filter { $0.status == .expired }.count
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            LabStat(label: "Expedientes", value: "\(lab.world.employeeFiles.count)", symbol: "folder.fill")
            LabStat(label: "Pendientes", value: "\(pending)", tint: pending > 0 ? LabTone.accent : LabTone.good, symbol: "clock.fill")
            LabStat(label: "Vencidos", value: "\(expired)", tint: expired > 0 ? LabTone.bad : LabTone.good, symbol: "calendar.badge.exclamationmark")
        }
    }

    private func fileCard(_ file: EmployeeFile) -> some View {
        let delivered = file.documents.filter { $0.status == .delivered }.count
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(file.employeeNumber) · \(file.block.shortLabel)")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
                Spacer(minLength: 0)
                LabChip(
                    text: file.status.label,
                    symbol: file.status.symbol,
                    tint: file.status.canOperate ? LabTone.good : LabTone.bad
                )
            }

            HStack(spacing: 8) {
                LabStat(label: "Documentos", value: "\(delivered) / \(file.documents.count)", symbol: "doc.fill")
                LabStat(label: "Movimientos", value: "\(file.events.count)", symbol: "clock.arrow.circlepath")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(file.documents) { document in
                        LabChip(
                            text: document.kind.label,
                            symbol: document.status.symbol,
                            tint: tint(for: document.status)
                        )
                    }
                }
            }
            .scrollClipDisabled()

            Button("Adjuntar documento") { documentTarget = file }
                .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
        }
        .padding(15)
        .labPanel()
    }

    private func tint(for status: DocumentStatus) -> Color {
        switch status {
        case .delivered: LabTone.good
        case .pending: LabTone.muted
        case .rejected, .expired: LabTone.bad
        case .expiringSoon: LabTone.accent
        }
    }
}

// MARK: - Recruitment

/// Leads, funnel and campaigns. Everything a recruitment desk reads comes from here while
/// the environment is in test mode.
struct LabRecruitmentView: View {
    @Environment(LabStore.self) private var lab

    @State private var isProspectPresented: Bool = false
    @State private var isCampaignPresented: Bool = false
    @State private var stageFilter: RecruitStage?

    private var prospects: [Prospect] {
        lab.world.prospects.filter { stageFilter == nil || $0.stage == stageFilter }
    }

    var body: some View {
        LabScreen(section: .recruitment) {
            LabSectionTitle(
                title: "Adquisición de talento",
                subtitle: "Genera leads, muévelos por el embudo y crea las campañas que los producen. El guardia de duplicados se activa con teléfonos repetidos.",
                symbol: "person.crop.circle.badge.plus"
            )

            HStack(spacing: 8) {
                Button("Nuevo candidato") { isProspectPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .solid, isCompact: true))
                    .disabled(lab.world.stations.isEmpty)
                Button("Nueva campaña") { isCampaignPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                    .disabled(lab.world.stations.isEmpty)
            }

            if lab.world.stations.isEmpty {
                LabEmptyState(
                    title: "Falta la estación",
                    message: "Un candidato siempre se postula a una estación concreta.",
                    symbol: "building.2"
                )
            } else {
                funnel
                campaignsCard

                LabOptionRow(
                    label: "Etapa",
                    options: [RecruitStage?.none] + RecruitStage.allCases.map { Optional($0) },
                    selection: $stageFilter,
                    title: { $0?.shortLabel ?? "Todas" },
                    symbol: { $0?.symbol ?? "line.3.horizontal.decrease.circle.fill" }
                )

                if prospects.isEmpty {
                    LabEmptyState(
                        title: lab.world.prospects.isEmpty ? "Sin candidatos" : "Sin resultados",
                        message: lab.world.prospects.isEmpty
                            ? "El embudo está vacío. Crea un candidato o recibe un lead simulado desde Integraciones."
                            : "Ningún candidato está en esa etapa.",
                        symbol: "person.crop.circle.badge.questionmark"
                    )
                } else {
                    ForEach(prospects) { prospect in
                        prospectCard(prospect)
                    }
                }
            }
        }
        .sheet(isPresented: $isProspectPresented) { LabProspectEditor() }
        .sheet(isPresented: $isCampaignPresented) { LabCampaignEditor() }
    }

    private var funnel: some View {
        VStack(alignment: .leading, spacing: 9) {
            LabCaps(text: "Embudo")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(RecruitStage.allCases) { stage in
                    let count = lab.world.prospects.filter { $0.stage == stage }.count
                    LabStat(
                        label: stage.shortLabel,
                        value: "\(count)",
                        tint: count == 0 ? LabTone.muted : .white,
                        symbol: stage.symbol
                    )
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    private var campaignsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Campañas")
            if lab.world.campaigns.isEmpty {
                Text("Sin campañas activas. Una campaña define el presupuesto y la fuente de los leads.")
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(lab.world.campaigns) { campaign in
                    LabRow(
                        title: campaign.name,
                        subtitle: "\(campaign.platform.label) · \(lab.world.station(id: campaign.stationId)?.code ?? "—")",
                        detail: "\(Fmt.mxn(campaign.spentMxn)) de \(Fmt.mxn(campaign.budgetMxn))",
                        symbol: campaign.platform.symbol,
                        tint: campaign.isActive ? LabTone.good : LabTone.muted
                    ) {
                        Button {
                            lab.deleteCampaign(id: campaign.id)
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

    private func prospectCard(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prospect.name)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(prospect.phone) · \(prospect.city)")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
                Spacer(minLength: 0)
                LabChip(text: prospect.stage.shortLabel, symbol: prospect.stage.symbol, tint: LabTone.accent)
            }

            HStack(spacing: 6) {
                LabChip(text: prospect.source.shortLabel, symbol: prospect.source.symbol, tint: LabTone.muted)
                LabChip(text: prospect.requestedBlock.shortLabel, symbol: prospect.requestedBlock.symbol, tint: LabTone.muted)
                Spacer(minLength: 0)
            }

            LabOptionRow(
                label: "Mover a",
                options: RecruitStage.allCases,
                selection: Binding(
                    get: { prospect.stage },
                    set: { lab.advanceProspect(id: prospect.id, to: $0) }
                ),
                title: \.shortLabel,
                symbol: { $0.symbol }
            )

            HStack {
                Spacer(minLength: 0)
                Button("Eliminar") { lab.deleteProspect(id: prospect.id) }
                    .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
            }
        }
        .padding(15)
        .labPanel()
    }
}

private struct LabProspectEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var city: String = "CDMX"
    @State private var age: Int = 30
    @State private var experience: Int = 2
    @State private var stationId: String = ""
    @State private var block: ShiftBlock = .weekdayMorning
    @State private var source: LeadSource = .facebook
    @State private var stage: RecruitStage = .lead

    var body: some View {
        LabSheet(
            title: "Nuevo candidato",
            subtitle: "Si repites un teléfono ya registrado, el sistema debe marcarlo como duplicado en la interfaz de reclutamiento.",
            isConfirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !stationId.isEmpty,
            onConfirm: save
        ) {
            LabField(label: "Nombre", placeholder: "Nombre y apellidos", text: $name, autocapitalization: .words)
            LabField(label: "Teléfono", placeholder: "5512345678", text: $phone, keyboard: .phonePad)
            LabField(label: "Correo", placeholder: "candidato@correo.mx", text: $email, keyboard: .emailAddress, autocapitalization: .never)
            LabField(label: "Ciudad", placeholder: "CDMX", text: $city)
            LabNumberField(label: "Edad", value: $age, range: 18...75)
            LabNumberField(label: "Años de experiencia", value: $experience, range: 0...40)

            LabOptionRow(
                label: "Estación",
                options: lab.world.stations.map(\.id),
                selection: $stationId,
                title: { id in lab.world.station(id: id)?.code ?? "—" }
            )
            LabOptionRow(label: "Bloque solicitado", options: ShiftBlock.allCases, selection: $block, title: \.shortLabel, symbol: { $0.symbol })
            LabOptionRow(label: "Fuente", options: LeadSource.allCases, selection: $source, title: \.shortLabel, symbol: { $0.symbol })
            LabOptionRow(label: "Etapa inicial", options: RecruitStage.allCases, selection: $stage, title: \.shortLabel, symbol: { $0.symbol })
        }
        .onAppear { stationId = lab.world.stations.first?.id ?? "" }
    }

    private func save() {
        let prospect = Prospect(
            id: "labpro-\(UUID().uuidString.prefix(8))",
            name: name.trimmingCharacters(in: .whitespaces),
            phone: phone,
            email: email,
            city: city,
            age: age,
            curp: "",
            stationId: stationId,
            requestedBlock: block,
            experienceYears: experience,
            platforms: [],
            hasLicense: true,
            source: source,
            campaignId: nil,
            createdAt: Date(),
            stage: stage,
            contactedAt: nil,
            screening: nil,
            interview: nil,
            documents: [],
            authorizedAt: nil,
            hiringVerdict: nil,
            hiringNote: nil,
            verdictAt: nil,
            hiredAt: nil,
            lossReason: nil,
            lossNote: nil,
            ownerName: LabRules.adminAccount.name,
            notes: "Candidato creado desde el laboratorio de pruebas.",
            history: []
        )
        lab.addProspect(prospect)
        dismiss()
    }
}

private struct LabCampaignEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var platform: LeadSource = .facebook
    @State private var stationId: String = ""
    @State private var budget: Int = 10_000
    @State private var days: Int = 30

    var body: some View {
        LabSheet(
            title: "Nueva campaña",
            subtitle: "La campaña es lo que convierte presupuesto en leads. Desde Integraciones puedes recibir formularios simulados que caen aquí.",
            isConfirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !stationId.isEmpty,
            onConfirm: save
        ) {
            LabField(label: "Nombre", placeholder: "Campaña conductores CDMX", text: $name)
            LabOptionRow(label: "Plataforma", options: LeadSource.allCases, selection: $platform, title: \.shortLabel, symbol: { $0.symbol })
            LabOptionRow(
                label: "Estación",
                options: lab.world.stations.map(\.id),
                selection: $stationId,
                title: { id in lab.world.station(id: id)?.code ?? "—" }
            )
            LabNumberField(label: "Presupuesto", value: $budget, range: 500...500_000, step: 500, suffix: "MXN")
            LabNumberField(label: "Duración", value: $days, range: 1...180, suffix: "días")
        }
        .onAppear { stationId = lab.world.stations.first?.id ?? "" }
    }

    private func save() {
        let campaign = RecruitCampaign(
            id: "labcmp-\(UUID().uuidString.prefix(8))",
            name: name.trimmingCharacters(in: .whitespaces),
            platform: platform,
            stationId: stationId,
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(TimeInterval(days * 86400)),
            budgetMxn: budget,
            spentMxn: 0,
            isActive: true,
            externalFormId: "form-prueba-\(Int.random(in: 1000...9999))"
        )
        if lab.saveCampaign(campaign) { dismiss() }
    }
}

// MARK: - Operation

/// Incidents and the live state of the operation. Turns themselves are started from the
/// driver interface; this is where the supervisor's inbox is filled.
struct LabOperationView: View {
    @Environment(LabStore.self) private var lab

    @State private var isIncidentPresented: Bool = false

    var body: some View {
        LabScreen(section: .operation) {
            LabSectionTitle(
                title: "Operación",
                subtitle: "Estado del turno en curso e incidencias que llegan al escritorio del supervisor.",
                symbol: "gauge.with.dots.needle.bottom.50percent"
            )

            liveCard

            Button("Registrar incidencia") { isIncidentPresented = true }
                .buttonStyle(LabButtonStyle(kind: .solid))
                .disabled(lab.world.vehicles.isEmpty)

            if lab.world.incidents.isEmpty {
                LabEmptyState(
                    title: "Sin incidencias",
                    message: "No hay reportes abiertos. Registra uno para verlo llegar a supervisión y a taller.",
                    symbol: "exclamationmark.bubble"
                )
            } else {
                ForEach(lab.world.incidents) { incident in
                    LabRow(
                        title: incident.kind.label,
                        subtitle: incident.detail,
                        detail: "\(incident.vehicleNumber) · \(incident.severity.label) · \(incident.status.label)",
                        symbol: incident.kind.symbol,
                        tint: incident.isOpen ? LabTone.bad : LabTone.muted
                    )
                }
            }
        }
        .sheet(isPresented: $isIncidentPresented) { LabIncidentEditor() }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Turno en curso")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                LabStat(
                    label: "Unidades en operación",
                    value: "\(lab.world.vehicles.filter { $0.stage == .operating }.count)",
                    symbol: "steeringwheel"
                )
                LabStat(
                    label: "Disponibles",
                    value: "\(lab.world.vehicles.filter { $0.stage == .available }.count)",
                    tint: LabTone.good,
                    symbol: "checkmark.circle.fill"
                )
                LabStat(
                    label: "En taller",
                    value: "\(lab.world.vehicles.filter { $0.stage == .maintenance }.count)",
                    tint: LabTone.accent,
                    symbol: "wrench.adjustable.fill"
                )
                LabStat(
                    label: "Fuera de servicio",
                    value: "\(lab.world.vehicles.filter { $0.stage == .outOfService }.count)",
                    tint: LabTone.bad,
                    symbol: "exclamationmark.octagon.fill"
                )
            }
        }
        .padding(16)
        .labPanel()
    }
}

private struct LabIncidentEditor: View {
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var vehicleId: String = ""
    @State private var kind: IncidentKind = .damage
    @State private var severity: IncidentSeverity = .medium
    @State private var detail: String = ""

    var body: some View {
        LabSheet(
            title: "Nueva incidencia",
            subtitle: "Una incidencia crítica saca la unidad de la flotilla disponible y abre trabajo en taller.",
            isConfirmEnabled: !vehicleId.isEmpty && !detail.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: save
        ) {
            LabOptionRow(
                label: "Unidad",
                options: lab.world.vehicles.map(\.id),
                selection: $vehicleId,
                title: { id in lab.world.vehicle(id: id)?.internalNumber ?? "—" }
            )
            LabOptionRow(label: "Tipo", options: IncidentKind.allCases, selection: $kind, title: \.label, symbol: { $0.symbol })
            LabOptionRow(label: "Severidad", options: IncidentSeverity.allCases, selection: $severity, title: \.label)
            LabField(label: "Descripción", placeholder: "Qué pasó", text: $detail)
        }
        .onAppear { vehicleId = lab.world.vehicles.first?.id ?? "" }
    }

    private func save() {
        guard let vehicle = lab.world.vehicle(id: vehicleId) else { return }
        let incident = StationIncident(
            id: "labinc-\(UUID().uuidString.prefix(8))",
            stationId: vehicle.stationId,
            driverId: nil,
            driverName: "Registro de laboratorio",
            vehicleNumber: vehicle.internalNumber,
            kind: kind,
            severity: severity,
            createdAt: Date(),
            detail: detail,
            photos: [],
            status: .open,
            reportedBy: LabRules.adminAccount.name
        )
        lab.registerIncident(incident)
        dismiss()
    }
}

// MARK: - Documents

/// Real capture: camera, gallery and files, plus the OCR outcomes the app has to survive.
struct LabDocumentsView: View {
    @Environment(LabStore.self) private var lab

    @State private var isCapturePresented: Bool = false

    var body: some View {
        LabScreen(section: .documents) {
            LabSectionTitle(
                title: "Documentos y evidencias",
                subtitle: "Sube archivos reales desde la cámara, la galería o el explorador y elige qué debe leer el OCR para ver cómo responde la app.",
                symbol: "doc.viewfinder.fill"
            )

            Button("Capturar documento") { isCapturePresented = true }
                .buttonStyle(LabButtonStyle(kind: .solid))

            ocrLegend

            if lab.world.documents.isEmpty {
                LabEmptyState(
                    title: "Sin documentos",
                    message: "No hay ningún archivo cargado en el entorno de pruebas.",
                    symbol: "doc"
                )
            } else {
                ForEach(lab.world.documents) { document in
                    documentCard(document)
                }
            }
        }
        .sheet(isPresented: $isCapturePresented) {
            LabDocumentCapture(subjectId: nil, subjectName: nil)
        }
    }

    private var ocrLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabCaps(text: "Respuestas esperadas del OCR")
            ForEach(LabOcrOutcome.allCases) { outcome in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: outcome.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(outcome == .correct ? LabTone.good : LabTone.accent)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(outcome.label)
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(.white)
                        Text(outcome.appResponse)
                            .font(.caption2)
                            .foregroundStyle(LabTone.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    private func documentCard(_ document: LabDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                thumbnail(document)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.kind.label)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                    Text(document.subjectName.isEmpty ? "Sin expediente" : document.subjectName)
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                    Text("\(document.fileName) · \(document.sizeLabel)")
                        .font(.caption2)
                        .foregroundStyle(LabTone.muted.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    lab.deleteDocument(id: document.id)
                } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(LabTone.bad)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                LabChip(text: document.source.label, symbol: document.source.symbol, tint: LabTone.muted)
                if let ocr = document.ocr {
                    LabChip(
                        text: "\(ocr.outcome.label) · \(ocr.confidence)%",
                        symbol: ocr.outcome.symbol,
                        tint: ocr.outcome == .correct ? LabTone.good : LabTone.bad
                    )
                }
                Spacer(minLength: 0)
            }

            if let ocr = document.ocr {
                Text(ocr.outcome.appResponse)
                    .font(.caption)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !ocr.fields.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(ocr.fields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .font(.caption2)
                                    .foregroundStyle(LabTone.muted)
                                Spacer(minLength: 0)
                                Text(value)
                                    .font(.system(.caption2, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(10)
                    .labFlat(cornerRadius: 12)
                }
            }
        }
        .padding(15)
        .labPanel()
    }

    @ViewBuilder
    private func thumbnail(_ document: LabDocument) -> some View {
        if !document.isPdf, let data = document.data, let image = UIImage(data: data) {
            Color(LabTone.raised)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 12))
        } else {
            Image(systemName: document.isPdf ? "doc.richtext.fill" : "doc.fill")
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(LabTone.accent)
                .frame(width: 52, height: 52)
                .background(LabTone.accent.opacity(0.12), in: .rect(cornerRadius: 12))
        }
    }
}

/// Capture flow shared by HR and the documents module.
struct LabDocumentCapture: View {
    let subjectId: String?
    let subjectName: String?

    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var kind: DocumentKind = .officialId
    @State private var outcome: LabOcrOutcome = .correct
    @State private var pickedData: Data?
    @State private var pickedName: String = ""
    @State private var pickedMime: String = "image/jpeg"
    @State private var source: LabDocumentSource = .camera
    @State private var isCameraPresented: Bool = false
    @State private var isFilePresented: Bool = false
    @State private var photoItem: PhotosPickerItem?
    @State private var chosenSubjectId: String = ""

    private var resolvedSubjectId: String { subjectId ?? chosenSubjectId }

    private var resolvedSubjectName: String {
        if let subjectName { return subjectName }
        return lab.world.employeeFiles.first { $0.id == chosenSubjectId }?.name ?? ""
    }

    var body: some View {
        LabSheet(
            title: "Capturar documento",
            subtitle: "El archivo se guarda tal cual en el entorno de pruebas y se adjunta al expediente elegido.",
            confirmTitle: "Adjuntar",
            isConfirmEnabled: pickedData != nil,
            onConfirm: save
        ) {
            if subjectId == nil {
                if lab.world.employeeFiles.isEmpty {
                    Text("No hay expedientes: el documento se guardará suelto en el laboratorio.")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                } else {
                    LabOptionRow(
                        label: "Expediente",
                        options: lab.world.employeeFiles.map(\.id),
                        selection: $chosenSubjectId,
                        title: { id in lab.world.employeeFiles.first { $0.id == id }?.name ?? "—" }
                    )
                }
            }

            LabOptionRow(label: "Tipo de documento", options: DocumentKind.allCases, selection: $kind, title: \.label)

            VStack(alignment: .leading, spacing: 9) {
                LabCaps(text: "Origen del archivo")
                HStack(spacing: 8) {
                    Button {
                        source = .camera
                        isCameraPresented = true
                    } label: {
                        Label("Cámara", systemImage: "camera.fill")
                    }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Galería", systemImage: "photo.on.rectangle.angled")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(LabTone.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(LabTone.accent.opacity(0.14), in: .capsule)
                            .overlay { Capsule().stroke(LabTone.accent.opacity(0.45), lineWidth: 1) }
                    }

                    Button {
                        source = .file
                        isFilePresented = true
                    } label: {
                        Label("Archivo", systemImage: "folder.fill")
                    }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                }
            }

            preview

            LabOptionRow(
                label: "Resultado del OCR simulado",
                options: LabOcrOutcome.allCases,
                selection: $outcome,
                title: \.label,
                symbol: { $0.symbol }
            )

            VStack(alignment: .leading, spacing: 5) {
                LabCaps(text: "Respuesta esperada de la app")
                Text(outcome.appResponse)
                    .font(.footnote)
                    .foregroundStyle(outcome == .correct ? LabTone.good : LabTone.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .labFlat()
        }
        .onAppear { chosenSubjectId = lab.world.employeeFiles.first?.id ?? "" }
        .fullScreenCover(isPresented: $isCameraPresented) {
            EvidencePicker { data in
                pickedData = data
                pickedName = "captura-\(Int(Date().timeIntervalSince1970)).jpg"
                pickedMime = "image/jpeg"
                source = .camera
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isFilePresented,
            allowedContentTypes: [.pdf, .image, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .task(id: photoItem) {
            guard let photoItem else { return }
            if let data = try? await photoItem.loadTransferable(type: Data.self) {
                pickedData = data
                pickedName = "galeria-\(Int(Date().timeIntervalSince1970)).jpg"
                pickedMime = "image/jpeg"
                source = .gallery
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let pickedData {
            VStack(alignment: .leading, spacing: 8) {
                LabCaps(text: "Archivo seleccionado")
                if pickedMime.hasPrefix("image"), let image = UIImage(data: pickedData) {
                    Color(LabTone.raised)
                        .frame(height: 190)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 16))
                } else {
                    Label(pickedName, systemImage: "doc.richtext.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .labFlat()
                }
                Text("\(pickedName) · \(Double(pickedData.count) / 1024 < 1024 ? String(format: "%.0f KB", Double(pickedData.count) / 1024) : String(format: "%.1f MB", Double(pickedData.count) / 1_048_576))")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
            }
        } else {
            Text("Ningún archivo seleccionado todavía.")
                .font(.caption)
                .foregroundStyle(LabTone.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .labFlat()
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pickedData = data
                pickedName = url.lastPathComponent
                pickedMime = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
                source = .file
            } catch {
                lab.notify("No se pudo leer el archivo seleccionado.", tone: .failure)
            }
        case .failure:
            lab.notify("Selección de archivo cancelada o inválida.", tone: .warning)
        }
    }

    private func save() {
        guard let pickedData else { return }
        let fields: [String: String] = {
            switch outcome {
            case .correct: ["Nombre": resolvedSubjectName.isEmpty ? "Titular de prueba" : resolvedSubjectName, "Vigencia": "2030"]
            case .incorrect: ["Nombre": "NOMBRE ILEGIBLE", "Vigencia": "—"]
            case .unreadable: [:]
            case .incomplete: ["Nombre": resolvedSubjectName.isEmpty ? "Titular de prueba" : resolvedSubjectName]
            case .expired: ["Nombre": resolvedSubjectName.isEmpty ? "Titular de prueba" : resolvedSubjectName, "Vigencia": "2023"]
            }
        }()

        let document = LabDocument(
            id: "labdoc-\(UUID().uuidString.prefix(8))",
            kind: kind,
            subjectId: resolvedSubjectId,
            subjectName: resolvedSubjectName,
            fileName: pickedName,
            mime: pickedMime,
            data: pickedData.count < 900_000 ? pickedData : nil,
            byteCount: pickedData.count,
            source: source,
            capturedAt: Date(),
            ocr: LabOcrResult(
                outcome: outcome,
                fields: fields,
                confidence: outcome.confidence,
                readAt: Date()
            )
        )
        lab.attachDocument(document)
        dismiss()
    }
}
