import SwiftUI

/// Expansion. Direction opens stations, and the app never lets it forget the consequence:
/// every unit purchased is four drivers that somebody has to contratar antes de la
/// apertura. A station that opens without plantilla no abre, arranca fallando.
struct NationalExpansionView: View {
    let national: NationalStore

    @State private var isCreating: Bool = false
    @State private var selected: StationProject?

    private var metrics: NetworkMetrics { national.metrics }

    var body: some View {
        NationalScreen(title: "Expansión") {
            growthCard
            recruitmentCard
            BigButton(title: "Proyectar nueva estación", symbol: "plus.viewfinder") {
                isCreating = true
            }
            projectList
        }
        .sheet(isPresented: $isCreating) {
            ProjectFormView(national: national)
        }
        .sheet(item: $selected) { project in
            ProjectDetailView(national: national, projectId: project.id)
        }
    }

    // MARK: - Growth

    private var growthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SupSectionHeader(
                title: "Crecimiento comprometido",
                subtitle: "Lo que la red ya autorizó y todavía no opera"
            )

            HStack(spacing: 10) {
                NatFigure(
                    value: "\(metrics.fleetSize)",
                    caption: "Unidades hoy",
                    detail: "\(metrics.stations) estaciones operando",
                    tone: NatTone.cool
                )
                NatFigure(
                    value: "+\(metrics.incomingVehicles)",
                    caption: "En apertura",
                    detail: "Red proyectada: \(metrics.projectedFleet) unidades",
                    tone: NatTone.accent
                )
            }

            ProgressTrack(
                value: Double(metrics.fleetSize),
                goal: Double(max(1, metrics.projectedFleet)),
                tone: NatTone.accent
            )
            .frame(height: 8)

            HStack(spacing: 10) {
                NatFigure(
                    value: Fmt.mxn(national.committedInvestmentMxn),
                    caption: "Inversión comprometida",
                    detail: "Unidades de las estaciones por abrir",
                    tone: NatTone.accent
                )
                NatFigure(
                    value: "\(HRRules.requiredDrivers(activeVehicles: metrics.incomingVehicles))",
                    caption: "Plazas que se abren",
                    detail: "\(metrics.incomingVehicles) unidades × \(HRRules.driversPerVehicle) turnos",
                    tone: NatTone.warn
                )
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Recruitment

    /// National recruitment need: current deficit plus everything the openings will demand.
    private var recruitmentCard: some View {
        let need = NationalRules.nationalRecruitmentNeed(
            projects: national.projects,
            deficit: metrics.driverDeficit
        )
        let pending = national.projects.filter { $0.stage != .operating }.reduce(0) { $0 + $1.driverDeficit }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HeadlineFigure(
                    value: "\(need)",
                    caption: "candidatos a iniciar",
                    tone: need > 0 ? NatTone.warn : NatTone.good,
                    detail: "Con la conversión histórica de la red y \(HRRules.safetyMarginPct)% de margen"
                )
                Spacer(minLength: 0)
            }

            Text("Se necesitan \(metrics.driverDeficit + pending) contrataciones firmes: \(metrics.driverDeficit) para cubrir la flotilla instalada y \(pending) para las estaciones en apertura. Contratar toma \(NationalRules.averageHiringDays) días en promedio.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.leading)

            if pending > 0 {
                NoticeBanner(
                    symbol: "clock.badge.exclamationmark.fill",
                    title: "Una unidad sin conductor no factura",
                    message: "El reclutamiento se inicia antes de que lleguen las unidades, no cuando ya están estacionadas.",
                    tone: .amber
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: - Projects

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Estaciones en proceso",
                subtitle: "Ordenadas por fecha de apertura"
            )
            if national.projects.isEmpty {
                Text("No hay proyectos de apertura registrados.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .panelFlat()
            } else {
                ForEach(national.projectsByLaunch) { project in
                    ProjectCard(project: project, now: national.now) {
                        selected = project
                    }
                }
            }
        }
    }
}

// MARK: - Form

/// New station projection. The required plantilla is computed live while direction moves
/// the fleet size, so the decision is never taken blind.
struct ProjectFormView: View {
    let national: NationalStore

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var code: String = ""
    @State private var city: String = ""
    @State private var regionId: String = StaffDirectory.regions.first?.id ?? ""
    @State private var targetVehicles: Int = 16
    @State private var launchDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 90)
    @State private var note: String = ""

    private var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !city.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var requiredDrivers: Int {
        HRRules.requiredDrivers(activeVehicles: targetVehicles)
    }

    private var daysAvailable: Int {
        ShiftRules.calendar.dateComponents([.day], from: national.now, to: launchDate).day ?? 0
    }

    private var risk: OpsAlertLevel {
        HRRules.hiringRisk(
            daysAvailable: max(0, daysAvailable),
            averageHiringDays: NationalRules.averageHiringDays,
            deficit: requiredDrivers
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        consequenceCard
                        identitySection
                        fleetSection
                        calendarSection
                        BigButton(
                            title: "Registrar proyecto",
                            symbol: "checkmark.seal.fill",
                            isEnabled: isComplete
                        ) {
                            national.addProject(
                                name: name,
                                code: code,
                                city: city,
                                regionId: regionId,
                                targetVehicles: targetVehicles,
                                launchDate: launchDate,
                                note: note
                            )
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Nueva estación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// What the decision really costs, updated as the fleet size moves.
    private var consequenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Lo que implica abrir esta estación")
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(requiredDrivers)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(risk.demandsAction ? risk.tone : NatTone.accent)
                    CapsLabel(text: "conductores de plantilla")
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.mxn(targetVehicles * CreditProgram.priceMxn))
                        .font(.system(.subheadline, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(NatTone.cool)
                    Text("inversión en unidades")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
            }

            if daysAvailable < NationalRules.averageHiringDays {
                NoticeBanner(
                    symbol: "exclamationmark.octagon.fill",
                    title: "La fecha no da tiempo de contratar",
                    message: "Faltan \(max(0, daysAvailable)) días y contratar toma \(NationalRules.averageHiringDays) en promedio. La estación abriría sin conductores.",
                    tone: .danger
                )
            } else {
                Text("Quedan \(daysAvailable) días para la apertura; el reclutamiento debe iniciar a más tardar en \(max(0, daysAvailable - NationalRules.averageHiringDays)) días.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Identidad")
            labelledField(title: "Nombre de la estación", text: $name, placeholder: "Estación Centro")
            labelledField(title: "Código", text: $code, placeholder: "QRO-01")
            labelledField(title: "Ciudad", text: $city, placeholder: "Querétaro")
            Picker("Región", selection: $regionId) {
                ForEach(StaffDirectory.regions) { region in
                    Text(region.name).tag(region.id)
                }
            }
            .pickerStyle(.menu)
            .tint(NatTone.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func labelledField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.textMuted)
            TextField(placeholder, text: text)
                .font(.system(.subheadline, weight: .semibold))
                .autocorrectionDisabled()
                .padding(12)
                .panelFlat(cornerRadius: 14)
        }
    }

    private var fleetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CapsLabel(text: "Unidades de arranque")
                Spacer(minLength: 8)
                Text("\(targetVehicles)")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(NatTone.accent)
            }
            Stepper(value: $targetVehicles, in: 1...HRRules.maxVehiclesPerStation) {
                Text("\(targetVehicles) de un máximo de \(HRRules.maxVehiclesPerStation) por estación")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            .tint(NatTone.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Apertura")
            DatePicker("Fecha de apertura", selection: $launchDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(NatTone.accent)
            labelledField(title: "Nota", text: $note, placeholder: "Predio, acometida eléctrica, permisos…")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

// MARK: - Detail

/// One project with its stage timeline and its hiring, which is the real gate to open.
struct ProjectDetailView: View {
    let national: NationalStore
    let projectId: String

    @Environment(\.dismiss) private var dismiss
    @State private var isRemoving: Bool = false

    private var project: StationProject? { national.project(id: projectId) }

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                if let project {
                    ScrollView {
                        VStack(spacing: 14) {
                            headline(project)
                            timeline(project)
                            hiring(project)
                            noteCard(project)
                            actions(project)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    Text("Proyecto no disponible")
                        .font(.footnote)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .navigationTitle(project?.code ?? "Proyecto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func headline(_ project: StationProject) -> some View {
        let risk = project.risk(now: national.now, averageHiringDays: NationalRules.averageHiringDays)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(.title3, weight: .black))
                Text("\(project.city) · región \(StaffDirectory.region(id: project.regionId)?.name ?? "—")")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            HStack(spacing: 10) {
                NatFigure(
                    value: "\(project.daysToLaunch(now: national.now))",
                    caption: "Días para abrir",
                    detail: Fmt.dateShort(project.launchDate),
                    tone: risk.demandsAction ? risk.tone : NatTone.accent
                )
                NatFigure(
                    value: "\(project.targetVehicles)",
                    caption: "Unidades",
                    detail: Fmt.mxn(project.investmentMxn),
                    tone: NatTone.cool
                )
            }

            if risk.demandsAction {
                NoticeBanner(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Apertura en riesgo por plantilla",
                    message: "Faltan \(project.driverDeficit) conductores y contratar toma \(NationalRules.averageHiringDays) días. Inicia reclutamiento o mueve la fecha.",
                    tone: risk == .critical ? .danger : .amber
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func timeline(_ project: StationProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Etapas", subtitle: "Dirección es quien las avanza")
            ForEach(ProjectStage.allCases) { stage in
                let isDone = stage.order < project.stage.order
                let isCurrent = stage == project.stage
                HStack(spacing: 12) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : stage.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isDone ? NatTone.good : (isCurrent ? NatTone.accent : Palette.textMuted))
                        .frame(width: 30, height: 30)
                        .background(
                            (isCurrent ? NatTone.accent : Color.white).opacity(isCurrent ? 0.14 : 0.05),
                            in: .rect(cornerRadius: 10)
                        )
                    Text(stage.label)
                        .font(.system(.footnote, weight: isCurrent ? .black : .semibold))
                        .foregroundStyle(isCurrent ? .primary : Palette.textMuted)
                    Spacer(minLength: 0)
                    if isCurrent {
                        StatePill(text: "Actual", symbol: "location.fill", tone: NatTone.accent, compact: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func hiring(_ project: StationProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Contratación",
                subtitle: "\(project.targetVehicles) unidades × \(HRRules.driversPerVehicle) turnos = \(project.requiredDrivers) plazas"
            )

            ProgressTrack(
                value: Double(project.hiredDrivers),
                goal: Double(max(1, project.requiredDrivers)),
                tone: project.driverDeficit == 0 ? NatTone.good : NatTone.warn
            )
            .frame(height: 10)

            HStack(spacing: 10) {
                NatFigure(
                    value: "\(project.hiredDrivers)",
                    caption: "Contratados",
                    detail: "\(project.driverDeficit) por cubrir",
                    tone: project.driverDeficit == 0 ? NatTone.good : NatTone.warn
                )
                NatFigure(
                    value: "\(project.candidatesStarted)",
                    caption: "Candidatos iniciados",
                    detail: "Recomendado: \(HRRules.recommendedCandidates(needed: project.requiredDrivers, conversionRate: 0.42))",
                    tone: NatTone.cool
                )
            }

            HStack(spacing: 10) {
                Button("Registrar 10 contratados") {
                    national.updateHiring(
                        projectId: project.id,
                        hired: project.hiredDrivers + 10,
                        candidates: project.candidatesStarted
                    )
                }
                .font(.system(.caption, weight: .black))
                .foregroundStyle(NatTone.accent)

                Spacer(minLength: 0)

                Button("Iniciar 25 candidatos") {
                    national.updateHiring(
                        projectId: project.id,
                        hired: project.hiredDrivers,
                        candidates: project.candidatesStarted + 25
                    )
                }
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func noteCard(_ project: StationProject) -> some View {
        Group {
            if !project.note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CapsLabel(text: "Nota de dirección")
                    Text(project.note)
                        .font(.footnote)
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelFlat()
            }
        }
    }

    private func actions(_ project: StationProject) -> some View {
        VStack(spacing: 10) {
            if let next = project.stage.next {
                BigButton(title: "Avanzar a \(next.label.lowercased())", symbol: next.symbol) {
                    national.advance(projectId: project.id)
                }
            } else {
                NoticeBanner(
                    symbol: "bolt.fill",
                    title: "Estación operando",
                    message: "El proyecto se convirtió en una estación de la red.",
                    tone: .volt
                )
            }

            Button("Cancelar proyecto") { isRemoving = true }
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(NatTone.bad)
        }
        .confirmationDialog(
            "¿Cancelar \(project.name)?",
            isPresented: $isRemoving,
            titleVisibility: .visible
        ) {
            Button("Cancelar proyecto", role: .destructive) {
                national.removeProject(id: project.id)
                dismiss()
            }
            Button("Conservar", role: .cancel) {}
        } message: {
            Text("Se elimina de la planeación de la red. La inversión comprometida deja de contarse.")
        }
    }
}
