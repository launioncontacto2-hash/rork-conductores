import SwiftUI
import UIKit

/// The candidate list of the recruitment desk, filtered by the stage of the funnel.
struct RecruitProspectsView: View {
    let recruit: RecruitmentStore
    let header: RecruitHeader
    let onOpenProspect: (String) -> Void

    @State private var filter: ProspectFilter = .all
    @State private var search: String = ""
    @State private var stationId: String?

    enum ProspectFilter: String, CaseIterable, Identifiable, Hashable {
        case all
        case contacted
        case prequalified
        case interviewed
        case documents
        case readyToHire
        case approved
        case hired
        case lost

        var id: String { rawValue }

        var stage: RecruitStage? {
            switch self {
            case .all: nil
            case .contacted: .contacted
            case .prequalified: .prequalified
            case .interviewed: .interviewed
            case .documents: .documents
            case .readyToHire: .readyToHire
            case .approved: .approved
            case .hired: .hired
            case .lost: .lost
            }
        }

        var label: String { stage?.shortLabel ?? "Todos" }
        var symbol: String { stage?.symbol ?? "person.3.fill" }

        static func from(_ stage: RecruitStage?) -> ProspectFilter {
            allCases.first { $0.stage == stage } ?? .all
        }
    }

    init(
        recruit: RecruitmentStore,
        header: RecruitHeader,
        initialStage: RecruitStage? = nil,
        onOpenProspect: @escaping (String) -> Void
    ) {
        self.recruit = recruit
        self.header = header
        self.onOpenProspect = onOpenProspect
        _filter = State(initialValue: ProspectFilter.from(initialStage))
    }

    private var rows: [Prospect] {
        recruit.prospects(stage: filter.stage, stationId: stationId, search: search)
    }

    var body: some View {
        ZStack {
            RecruitmentBackground()
            ScrollView {
                VStack(spacing: 14) {
                    header

                    FilterScroller(
                        items: ProspectFilter.allCases,
                        title: { $0.label },
                        symbol: { $0.symbol },
                        count: { count(for: $0) },
                        selection: $filter,
                        accent: RecTone.accent
                    )
                    .padding(.horizontal, -18)

                    if recruit.stations.count > 1 { stationPicker }

                    if rows.isEmpty {
                        RecEmptyState(
                            symbol: "person.crop.circle.badge.questionmark",
                            title: "Sin candidatos en esta etapa",
                            message: "Cambia el filtro o registra un nuevo lead para llenar el embudo."
                        )
                    } else {
                        ForEach(rows) { prospect in
                            ProspectRow(prospect: prospect, showStation: stationId == nil) {
                                onOpenProspect(prospect.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .searchable(text: $search, prompt: "Nombre, teléfono o correo")
    }

    private var stationPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                stationChip(title: "Todas", id: nil)
                ForEach(recruit.stations) { station in
                    stationChip(title: station.code, id: station.id)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func stationChip(title: String, id: String?) -> some View {
        let isSelected = stationId == id
        return Button {
            stationId = id
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(title)
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(isSelected ? Palette.canvas : Palette.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? RecTone.accent : Palette.surface.opacity(0.85), in: .capsule)
                .overlay { Capsule().stroke(isSelected ? .clear : Palette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func count(for filter: ProspectFilter) -> Int {
        guard let stage = filter.stage else { return recruit.prospects.count }
        return recruit.prospects.filter { $0.stage == stage }.count
    }
}

// MARK: - Detail

/// Full record of one candidate: screening, interview, initial documents, the alta and an
/// immutable history. Nothing financial lives here — by design, not by omission.
struct ProspectDetailView: View {
    let recruit: RecruitmentStore
    let prospectId: String

    @Environment(\.dismiss) private var dismiss
    @State private var isScreening: Bool = false
    @State private var isInterviewing: Bool = false
    @State private var isScheduling: Bool = false
    @State private var isHiring: Bool = false
    @State private var isDiscarding: Bool = false
    @State private var filing: DossierDocument?
    @State private var dossierVersion: Int = 0

    private var prospect: Prospect? { recruit.prospect(id: prospectId) }

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                if let prospect {
                    ScrollView {
                        VStack(spacing: 14) {
                            headline(prospect)
                            quickActions(prospect)
                            contactCard(prospect)
                            screeningCard(prospect)
                            interviewCard(prospect)
                            documentsCard(prospect)
                            guardedDocumentsCard(prospect)
                            hiringCard(prospect)
                            agendaCard(prospect)
                            historyCard(prospect)
                            permissionNote
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    RecEmptyState(
                        symbol: "person.crop.circle.badge.questionmark",
                        title: "Candidato no encontrado",
                        message: "El expediente ya no está en la base activa."
                    )
                    .padding(18)
                }
            }
            .navigationTitle(prospect?.shortName ?? "Candidato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isScreening) {
            if let prospect {
                ScreeningFormView(recruit: recruit, prospect: prospect)
            }
        }
        .sheet(isPresented: $isInterviewing) {
            if let prospect {
                RecruitInterviewView(recruit: recruit, prospect: prospect)
            }
        }
        .sheet(isPresented: $isScheduling) {
            if let prospect {
                AppointmentFormView(recruit: recruit, prospect: prospect)
            }
        }
        .sheet(isPresented: $isHiring) {
            if let prospect {
                HireFormView(recruit: recruit, prospect: prospect)
            }
        }
        .sheet(isPresented: $isDiscarding) {
            if let prospect {
                LossFormView(recruit: recruit, prospect: prospect)
            }
        }
        .sheet(item: $filing) { kind in
            if let prospect {
                DossierFilingSheet(
                    kind: kind,
                    subjectId: DossierBook.driverSubjectId(email: prospect.email, fallback: prospect.id),
                    subjectLabel: prospect.name,
                    deskName: recruit.account.name,
                    // Action time: the instant the desk opens the filing form.
                    now: recruit.now,
                    onSaved: { dossierVersion += 1 }
                )
            }
        }
    }

    /// The two papers recruitment guards for the person. They travel with the driver:
    /// on the road he shows them from his own app, without asking anybody.
    private func guardedDocumentsCard(_ prospect: Prospect) -> some View {
        let subjectId = DossierBook.driverSubjectId(email: prospect.email, fallback: prospect.id)
        let pending = DossierDocument.driverFile.filter {
            DossierBook.document(kind: $0, subjectId: subjectId) == nil
        }.count

        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Documentos que resguarda reclutamiento",
                subtitle: pending == 0 ? "Copias digitales completas" : "\(pending) por digitalizar",
                accent: RecTone.accent
            )

            ForEach(DossierDocument.driverFile) { kind in
                DossierDeskRow(
                    kind: kind,
                    document: DossierBook.document(kind: kind, subjectId: subjectId),
                    accent: RecTone.accent
                ) {
                    filing = kind
                }
            }

            Text("Estas copias se muestran al conductor durante su turno. Los documentos de la unidad —póliza, tarjeta de circulación y factura— los carga el supervisor en el archivo del auto.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(dossierVersion)
        .padding(15)
        .panel()
    }

    // MARK: - Headline

    private func headline(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(prospect.initials)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(prospect.stage.tone)
                    .frame(width: 66, height: 66)
                    .background(Palette.surfaceRaised, in: .circle)
                    .overlay { Circle().stroke(prospect.stage.tone.opacity(0.55), lineWidth: 2) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(prospect.name)
                        .font(.system(.headline, weight: .black))
                        .multilineTextAlignment(.leading)
                    Text("\(StaffDirectory.station(id: prospect.stationId)?.displayName ?? "—") · \(prospect.requestedBlock.label)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                    HStack(spacing: 6) {
                        StatePill(text: prospect.stage.label, symbol: prospect.stage.symbol, tone: prospect.stage.tone, compact: true)
                        StatePill(text: prospect.source.shortLabel, symbol: prospect.source.symbol, tone: Palette.textMuted, compact: true)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                // Days in process and the expediente percentage are both answers to a
                // date. Each carries its own leaf; the two figures between them are store
                // facts and never hear from the clock.
                TimeScope(.day) { now in
                    DemandFigure(value: "\(prospect.daysInProcess(now: now))", caption: "Días en proceso")
                }
                DemandFigure(value: "\(prospect.experienceYears)", caption: "Años manejando", tone: RecTone.cool)
                DemandFigure(
                    value: prospect.interviewScorePct.map { "\($0)" } ?? "—",
                    caption: "Entrevista",
                    tone: prospect.interviewScorePct != nil ? RecTone.good : Palette.textMuted
                )
                TimeScope(.day) { now in
                    let pct = prospect.documentPct(now: now)
                    DemandFigure(
                        value: "\(pct) %",
                        caption: "Expediente",
                        tone: pct == 100 ? RecTone.good : RecTone.warn
                    )
                }
            }

            if prospect.stage == .lost, let reason = prospect.lossReason {
                NoticeBanner(
                    symbol: reason.symbol,
                    title: "Fuera del proceso · \(reason.label)",
                    message: prospect.lossNote,
                    tone: .danger
                )
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Quick actions

    private func quickActions(_ prospect: Prospect) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                if let url = URL(string: "tel://\(RecruitRules.normalizePhone(prospect.phone))") {
                    Link(destination: url) {
                        actionChip(title: "Llamar", symbol: "phone.fill", tone: RecTone.accent, filled: true)
                    }
                }
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    recruit.markContacted(prospect.id)
                } label: {
                    actionChip(
                        title: prospect.contactedAt == nil ? "Contactado" : "Nuevo contacto",
                        symbol: "checkmark.circle.fill",
                        tone: RecTone.cool,
                        filled: false
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 9) {
                Button { isScreening = true } label: {
                    actionChip(title: "Precalificar", symbol: "checklist", tone: RecTone.cool, filled: false)
                }
                .buttonStyle(.plain)

                Button { isScheduling = true } label: {
                    actionChip(title: "Programar cita", symbol: "calendar.badge.plus", tone: RecTone.cool, filled: false)
                }
                .buttonStyle(.plain)
            }

            if prospect.stage == .lost {
                Button {
                    recruit.reopen(prospect.id)
                } label: {
                    actionChip(title: "Reingresar al proceso", symbol: "arrow.uturn.right", tone: RecTone.accent, filled: true)
                }
                .buttonStyle(.plain)
            } else {
                Button { isDiscarding = true } label: {
                    actionChip(title: "Descartar candidato", symbol: "xmark.circle.fill", tone: RecTone.bad, filled: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionChip(title: String, symbol: String, tone: Color, filled: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(.footnote, weight: .bold))
        }
        .foregroundStyle(filled ? Palette.canvas : tone)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(filled ? tone : tone.opacity(0.12), in: .capsule)
        .overlay { Capsule().stroke(filled ? .clear : tone.opacity(0.4), lineWidth: 1) }
    }

    // MARK: - Cards

    private func contactCard(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SupSectionHeader(title: "Datos del candidato", accent: RecTone.accent)
            MetricLine(label: "Teléfono", value: prospect.phone)
            MetricLine(label: "Correo", value: prospect.email.isEmpty ? "—" : prospect.email)
            MetricLine(label: "Ciudad", value: prospect.city)
            MetricLine(label: "Edad", value: "\(prospect.age) años")
            MetricLine(label: "Plataformas", value: prospect.platforms.isEmpty ? "Ninguna" : prospect.platformsLabel)
            MetricLine(
                label: "Licencia",
                value: prospect.hasLicense ? "Vigente" : "Sin licencia",
                tone: prospect.hasLicense ? RecTone.good : RecTone.bad
            )
            // `firstContactMinutes` is frozen at the moment of contact — a store fact.
            // Only the "registrado hace X" caption keeps counting, so the line is the leaf.
            TimeScope(.minute) { now in
                MetricLine(
                    label: "Primer contacto",
                    value: prospect.firstContactMinutes.map { Fmt.durationText($0) } ?? "Pendiente",
                    detail: prospect.contactedAt.map { "Registrado \(Fmt.relative($0, from: now))" },
                    tone: prospect.contactedAt == nil ? RecTone.warn : RecTone.cool
                )
            }
        }
        .padding(15)
        .panel()
    }

    private func screeningCard(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Precalificación",
                subtitle: "Filtro rápido antes de invertir una entrevista",
                actionTitle: prospect.screening == nil ? "Iniciar" : "Editar",
                accent: RecTone.accent,
                action: { isScreening = true }
            )

            if let screening = prospect.screening {
                HStack(spacing: 10) {
                    StatePill(
                        text: screening.outcome.label,
                        symbol: screening.outcome.symbol,
                        tone: screening.outcome.tone
                    )
                    Text("\(screening.passed) de \(ScreeningCheck.allCases.count) criterios")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                }
                if !screening.blockingFailures.isEmpty {
                    Text("No cumple: \(screening.blockingFailures.map(\.label).joined(separator: ", ")).")
                        .font(.system(size: 11))
                        .foregroundStyle(RecTone.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !screening.notes.isEmpty {
                    Text(screening.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Sin precalificar. Diez criterios: edad, licencia, experiencia, disponibilidad del bloque, ciudad, inicio inmediato, documentación básica y cumplimiento de horario.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .panel()
    }

    private func interviewCard(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Primera entrevista",
                subtitle: "Diez criterios de 1 a 5 · la decisión sigue siendo humana",
                actionTitle: prospect.interview?.interviewedAt == nil ? "Realizar" : "Editar",
                accent: RecTone.accent,
                action: { isInterviewing = true }
            )

            if let interview = prospect.interview, interview.interviewedAt != nil {
                HStack(spacing: 10) {
                    Text("\(interview.scorePct)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle((interview.decision ?? interview.suggestion).tone)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("de 100 puntos")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                        StatePill(
                            text: (interview.decision ?? interview.suggestion).label,
                            symbol: (interview.decision ?? interview.suggestion).symbol,
                            tone: (interview.decision ?? interview.suggestion).tone,
                            compact: true
                        )
                    }
                    Spacer(minLength: 0)
                    Text("Entrevistó \(Fmt.firstName(interview.interviewerName))")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                if !interview.notes.isEmpty {
                    Text(interview.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Sin entrevistar. La puntuación es una sugerencia calculada; el reclutador firma la recomendación final.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .panel()
    }

    private func documentsCard(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Heading and bar read the same percentage and move together, so they share
            // one leaf. The checklist below them is toggled by hand, never by the clock.
            TimeScope(.day) { now in
                let pct = prospect.documentPct(now: now)
                VStack(alignment: .leading, spacing: 10) {
                    SupSectionHeader(
                        title: "Expediente inicial",
                        subtitle: "\(pct) % completo",
                        accent: RecTone.accent
                    )
                    ProgressTrack(
                        value: Double(pct),
                        goal: 100,
                        tone: pct == 100 ? RecTone.good : RecTone.warn
                    )
                    .frame(height: 8)
                }
            }

            ForEach(DocumentKind.recruitmentChecklist) { kind in
                let document = prospect.documents.first { $0.kind == kind }
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    recruit.toggleDocument(prospect.id, kind: kind)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: document?.status == .delivered ? "checkmark.circle.fill" : "circle")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(document?.status == .delivered ? RecTone.good : Palette.textMuted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.label)
                                .font(.system(.footnote, weight: .bold))
                            Text(document?.uploadedAt.map { "Cargado \(Fmt.dateShort($0))" } ?? "Pendiente de solicitar")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }

            Text("Contrato, CLABE y seguridad social no se piden aquí: nacen con la nómina de la estación, ya con el alta firmada.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .panel()
    }

    /// The end of the process: recruitment signs the alta itself. Nobody re-interviews,
    /// nobody approves after this and nobody in the station can block it.
    private func hiringCard(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Alta del conductor",
                subtitle: "La firma es tuya: no pasa por supervisión",
                accent: RecTone.accent
            )

            if let hiredAt = prospect.hiredAt {
                HStack(spacing: 10) {
                    StatePill(text: "Contratado", symbol: "steeringwheel", tone: RecTone.good)
                    RelativeTime(date: hiredAt)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                }
                if let note = prospect.hiringNote, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NoticeBanner(
                    symbol: "folder.fill.badge.person.crop",
                    title: "Expediente laboral entregado",
                    message: "La estación ya lo tiene en su plantilla. Contrato, CLABE y nómina se administran allá.",
                    tone: .volt
                )
            } else if let verdict = prospect.hiringVerdict, verdict == .rejected {
                StatePill(text: verdict.label, symbol: verdict.symbol, tone: verdict.tone)
                if let note = prospect.hiringNote, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // Readiness to hire is decided by document expiry, so it turns on a date:
                // the button appears — and the list of what is missing shrinks — at
                // logical midnight. Only this branch is inside the scope; the heading, the
                // hired state and the rejected state above it stay out.
                TimeScope(.day) { now in
                    if prospect.isReadyToHire(now: now) {
                        BigButton(title: "Firmar alta y contratar", symbol: "signature", tone: .volt) {
                            isHiring = true
                        }
                        Text("Genera el expediente laboral en \(StaffDirectory.station(id: prospect.stationId)?.code ?? "la estación") y libera el turno solicitado.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    } else {
                        let missing = prospect.missingDocuments(now: now)
                        Text(prospect.passedEvaluation()
                            ? "Falta cerrar el expediente inicial: \(missing.map(\.label).joined(separator: ", "))."
                            : "Para firmar el alta necesitas precalificación apta, la entrevista firmada y el expediente inicial completo.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(15)
        .panel()
    }

    private func agendaCard(_ prospect: Prospect) -> some View {
        let appointments = recruit.appointments(prospectId: prospect.id)
        return Group {
            if !appointments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SupSectionHeader(title: "Citas", accent: RecTone.accent)
                    ForEach(appointments) { appointment in
                        AppointmentRow(appointment: appointment)
                    }
                }
                .padding(15)
                .panel()
            }
        }
    }

    private func historyCard(_ prospect: Prospect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Historial",
                subtitle: "Nunca se elimina, ni al rechazar",
                accent: RecTone.accent
            )
            ForEach(prospect.history) { event in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: event.kind.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RecTone.accent)
                        .frame(width: 26, height: 26)
                        .background(RecTone.accent.opacity(0.12), in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.detail)
                            .font(.system(size: 11, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(event.kind.label) · \(event.author) · \(Fmt.dateShort(event.date)) \(Fmt.clock(event.date))")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(15)
        .panel()
    }

    private var permissionNote: some View {
        Text("Reclutamiento lleva el proceso de principio a fin, pero no consulta créditos, liquidaciones ni nómina, y no registra CLABE: el dinero del conductor vive en la estación.")
            .font(.system(size: 10))
            .foregroundStyle(Palette.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }
}

// MARK: - Screening form

struct ScreeningFormView: View {
    let recruit: RecruitmentStore
    let prospect: Prospect

    @Environment(\.dismiss) private var dismiss
    @State private var screening: Screening
    @State private var decision: ScreeningOutcome?

    init(recruit: RecruitmentStore, prospect: Prospect) {
        self.recruit = recruit
        self.prospect = prospect
        let existing = prospect.screening ?? Screening(reviewer: recruit.account.name)
        _screening = State(initialValue: existing)
        _decision = State(initialValue: existing.decision)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        summary

                        ForEach(ScreeningCheck.allCases) { check in
                            checkRow(check)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: "Comentarios")
                            TextField("Observaciones de la llamada", text: $screening.notes, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.footnote)
                                .padding(12)
                                .panelFlat()
                        }

                        decisionPicker

                        BigButton(title: "Guardar precalificación", symbol: "checkmark.seal.fill", tone: .volt) {
                            var updated = screening
                            updated.decision = decision ?? screening.suggestion
                            recruit.saveScreening(prospect.id, screening: updated)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Precalificación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prospect.name)
                .font(.system(.subheadline, weight: .black))
            Text("\(prospect.requestedBlock.label) · \(prospect.city) · \(prospect.age) años")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
            HStack(spacing: 8) {
                StatePill(
                    text: "Sugerencia: \(screening.suggestion.label)",
                    symbol: screening.suggestion.symbol,
                    tone: screening.suggestion.tone,
                    compact: true
                )
                Text("\(screening.answered)/\(ScreeningCheck.allCases.count) respondidos")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel()
    }

    private func checkRow(_ check: ScreeningCheck) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.label)
                        .font(.system(.footnote, weight: .bold))
                    Text(check.hint)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 4)
                if check.isBlocking {
                    Text("BLOQUEANTE")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(RecTone.bad)
                }
            }
            HStack(spacing: 8) {
                answerButton(check, value: true, title: "Sí", tone: RecTone.good)
                answerButton(check, value: false, title: "No", tone: RecTone.bad)
            }
        }
        .padding(12)
        .panelFlat()
    }

    private func answerButton(_ check: ScreeningCheck, value: Bool, title: String, tone: Color) -> some View {
        let isSelected = screening.answers[check.rawValue] == value
        return Button {
            screening.answers[check.rawValue] = value
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(title)
                .font(.system(.footnote, weight: .black))
                .foregroundStyle(isSelected ? Palette.canvas : tone)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(isSelected ? tone : tone.opacity(0.1), in: .rect(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(isSelected ? .clear : tone.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var decisionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Resultado")
            HStack(spacing: 8) {
                ForEach(ScreeningOutcome.allCases) { outcome in
                    Button {
                        decision = outcome
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: outcome.symbol)
                                .font(.system(size: 14, weight: .bold))
                            Text(outcome.label)
                                .font(.system(size: 11, weight: .black))
                        }
                        .foregroundStyle(decision == outcome ? Palette.canvas : outcome.tone)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(decision == outcome ? outcome.tone : outcome.tone.opacity(0.1), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(decision == outcome ? .clear : outcome.tone.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("La sugerencia se calcula sola; el resultado lo firma el reclutador.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(14)
        .panel()
    }
}

// MARK: - Interview

struct RecruitInterviewView: View {
    let recruit: RecruitmentStore
    let prospect: Prospect

    @Environment(\.dismiss) private var dismiss
    @State private var sheet: InterviewSheet
    @State private var decision: InterviewSuggestion?

    init(recruit: RecruitmentStore, prospect: Prospect) {
        self.recruit = recruit
        self.prospect = prospect
        let existing = prospect.interview ?? InterviewSheet(interviewerName: recruit.account.name)
        _sheet = State(initialValue: existing)
        _decision = State(initialValue: existing.decision)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        scoreHeadline

                        ForEach(InterviewCriterion.allCases) { criterion in
                            ScoreStepper(criterion: criterion, value: sheet.score(criterion)) { value in
                                sheet.scores[criterion.rawValue] = value
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: "Notas de la entrevista")
                            TextField("Expectativas, historial laboral, observaciones", text: $sheet.notes, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.footnote)
                                .padding(12)
                                .panelFlat()
                        }

                        decisionPicker

                        BigButton(
                            title: "Guardar entrevista",
                            symbol: "checkmark.seal.fill",
                            tone: .volt,
                            isEnabled: sheet.answered > 0
                        ) {
                            var updated = sheet
                            updated.decision = decision ?? sheet.suggestion
                            recruit.saveInterview(prospect.id, sheet: updated)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Primera entrevista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var scoreHeadline: some View {
        HStack(spacing: 14) {
            RecRing(
                ratio: Double(sheet.scorePct) / 100,
                headline: "\(sheet.scorePct)",
                caption: "Puntos",
                tone: sheet.suggestion.tone,
                size: 82
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(prospect.name)
                    .font(.system(.subheadline, weight: .black))
                Text("\(sheet.answered) de \(InterviewCriterion.allCases.count) criterios calificados")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                StatePill(
                    text: "Sugerencia: \(sheet.suggestion.label)",
                    symbol: sheet.suggestion.symbol,
                    tone: sheet.suggestion.tone,
                    compact: true
                )
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .panel()
    }

    private var decisionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Recomendación del reclutador")
            HStack(spacing: 8) {
                ForEach([InterviewSuggestion.recommended, .secondReview, .notRecommended], id: \.rawValue) { option in
                    Button {
                        decision = option
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 13, weight: .bold))
                            Text(option.label)
                                .font(.system(size: 10, weight: .black))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(decision == option ? Palette.canvas : option.tone)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(decision == option ? option.tone : option.tone.opacity(0.1), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(decision == option ? .clear : option.tone.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("La recomendación automática es informativa. La decisión queda bajo control humano.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(14)
        .panel()
    }
}

// MARK: - Alta

/// Where recruitment closes its own process: the contract. Four conditions have to be
/// true at once, and all four are visible before the button can be pressed.
struct HireFormView: View {
    let recruit: RecruitmentStore
    let prospect: Prospect

    @Environment(\.dismiss) private var dismiss
    @State private var employeeNumber: String = ""
    @State private var comments: String = ""
    @State private var isRejecting: Bool = false

    private var station: Station? { StaffDirectory.station(id: prospect.stationId) }

    /// The day the alta is being judged against — the one temporal input of this sheet.
    ///
    /// This replaces a re-export of `RecruitmentStore.now`, and the replacement matters
    /// more here than anywhere else in the app: `now` does not only word a caption here, it
    /// decides `canSign`, and therefore whether the signing button is enabled. Under the
    /// old form the button was kept honest by an accident — `recruit.now` reached
    /// `FleetStore.now`, which registered a global dependency as a side effect. The day that
    /// side effect is removed, an authorisation control would have silently frozen.
    ///
    /// Now the dependency is real and named. `ClockAnchor` writes this on the day boundary,
    /// and the sheet reads the prospect through it, so both the conditions and the button
    /// move for exactly two reasons: the calendar day changed, or the candidate's file did.
    ///
    /// Every rule that decides an alta is a date question — `missingDocuments` and
    /// `isReadyToHire` both resolve document expiry, and `daysInProcess` counts days. There
    /// is no intraday condition, so one `.day` anchor governs the whole sheet.
    @State private var dayAnchor: Date = AppClock.now()

    /// Open seats of the block the candidate asked for, read from the fleet itself.
    private var blockVacancy: BlockCoverage? {
        recruit.demands
            .first { $0.station.id == prospect.stationId }?
            .blocks.first { $0.block == prospect.requestedBlock }
    }

    private var conditions: [(label: String, detail: String, isMet: Bool)] {
        let missing = prospect.missingDocuments(now: dayAnchor)
        let vacancy = blockVacancy?.deficit ?? 0
        return [
            (
                "Precalificación apta",
                prospect.screening?.outcome.label ?? "Sin precalificar",
                prospect.screening?.outcome == .fit
            ),
            (
                "Entrevista firmada",
                prospect.interview?.interviewedAt == nil
                    ? "Pendiente"
                    : "\(prospect.interview?.scorePct ?? 0) / 100 · \((prospect.interview?.decision ?? prospect.interview?.suggestion)?.label ?? "—")",
                prospect.passedEvaluation()
            ),
            (
                "Expediente inicial completo",
                missing.isEmpty ? "6 de 6 documentos" : "Faltan \(missing.count)",
                missing.isEmpty
            ),
            (
                "Vacante abierta en \(prospect.requestedBlock.label)",
                vacancy > 0 ? "\(vacancy) plazas sin cubrir" : "El bloque ya está cubierto",
                vacancy > 0
            ),
        ]
    }

    /// Authorisation, not presentation.
    ///
    /// Deliberately reads the same anchor as `conditions`: the four rows the recruiter is
    /// shown and the button they enable must never disagree about what day it is.
    private var canSign: Bool {
        prospect.isReadyToHire(now: dayAnchor) && !employeeNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCard
                        conditionsCard
                        numberCard

                        NoticeBanner(
                            symbol: "signature",
                            title: "Contratas tú, no la estación",
                            message: "Al firmar se crea el expediente laboral en \(station?.code ?? "la estación") y el conductor queda listo para su primer turno. Supervisión solo lo verá en su plantilla.",
                            tone: .volt
                        )

                        BigButton(
                            title: "Firmar alta de \(prospect.shortName)",
                            symbol: "signature",
                            tone: .volt,
                            isEnabled: canSign
                        ) {
                            guard recruit.hire(prospect.id, employeeNumber: employeeNumber, notes: comments) else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                return
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }

                        BigButton(title: "No contratar", symbol: "xmark.octagon.fill", tone: .outline) {
                            isRejecting = true
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Alta del conductor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .background {
            ClockAnchor(.day, date: $dayAnchor)
        }
        .task { employeeNumber = recruit.suggestedEmployeeNumber(for: prospect) }
        .alert("No contratar", isPresented: $isRejecting) {
            Button("Cancelar", role: .cancel) {}
            Button("Confirmar", role: .destructive) {
                recruit.rejectAtHire(
                    prospect.id,
                    note: comments.isEmpty ? "Descartado en la decisión final de contratación." : comments
                )
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                dismiss()
            }
        } message: {
            Text("El candidato sale del proceso con motivo «rechazado en la alta». Su historial se conserva completo.")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Vas a contratar")
            MetricLine(label: "Nombre", value: prospect.name)
            MetricLine(label: "Estación", value: station?.displayName ?? "—", tone: RecTone.cool)
            MetricLine(label: "Turno", value: prospect.requestedBlock.label, tone: RecTone.cool)
            MetricLine(label: "Experiencia", value: "\(prospect.experienceYears) años · \(prospect.platformsLabel)")
            MetricLine(label: "Días en proceso", value: "\(prospect.daysInProcess(now: dayAnchor))")
        }
        .padding(15)
        .panel()
    }

    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Condiciones del alta",
                subtitle: "Las cuatro se verifican solas",
                accent: RecTone.accent
            )
            ForEach(conditions, id: \.label) { condition in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: condition.isMet ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(condition.isMet ? RecTone.good : RecTone.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(condition.label)
                            .font(.system(.footnote, weight: .bold))
                        Text(condition.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("La vacante se lee de la flotilla instalada: unidades activas × 4 turnos. Puedes firmar aunque el bloque esté cubierto, pero quedará asentado.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .panel()
    }

    private var numberCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Número de empleado")
            TextField("Número", text: $employeeNumber)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(12)
                .panelFlat()

            CapsLabel(text: "Nota del alta")
            TextField("Qué conviene que sepa la estación", text: $comments, axis: .vertical)
                .lineLimit(2...5)
                .font(.footnote)
                .padding(12)
                .panelFlat()
        }
        .padding(15)
        .panel()
    }
}

// MARK: - Loss

/// Leaving the funnel always demands a reason: it is the only way to tell whether the
/// problem is the campaign, the offer or the process.
struct LossFormView: View {
    let recruit: RecruitmentStore
    let prospect: Prospect

    @Environment(\.dismiss) private var dismiss
    @State private var reason: LossReason?
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        Text("¿Por qué sale del proceso \(prospect.shortName)?")
                            .font(.system(.subheadline, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                            ForEach(LossReason.allCases) { option in
                                Button {
                                    reason = option
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Image(systemName: option.symbol)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(option.label)
                                            .font(.system(size: 11, weight: .bold))
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                                    .padding(11)
                                    .foregroundStyle(reason == option ? Palette.canvas : .primary)
                                    .background(reason == option ? RecTone.bad : Palette.surfaceRaised.opacity(0.75), in: .rect(cornerRadius: 14))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(reason == option ? .clear : Palette.hairline, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        TextField("Detalle (opcional)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.footnote)
                            .padding(12)
                            .panelFlat()

                        BigButton(
                            title: "Registrar salida",
                            symbol: "xmark.circle.fill",
                            tone: .danger,
                            isEnabled: reason != nil
                        ) {
                            guard let reason else { return }
                            recruit.markLost(prospect.id, reason: reason, note: note)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            dismiss()
                        }

                        Text("El expediente y su historial se conservan. Si la persona regresa, puede reingresar al proceso sin perder lo registrado.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Motivo de pérdida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
