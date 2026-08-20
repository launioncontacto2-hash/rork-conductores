import SwiftUI
import UIKit

/// Inbox of leads. Everything that arrives from a campaign, a referral or the front desk
/// lands here first. The clock is the metric: a lead that waits stops answering.
struct RecruitLeadsView: View {
    let recruit: RecruitmentStore
    let header: RecruitHeader
    let onOpenProspect: (String) -> Void

    @State private var isCreating: Bool = false
    @State private var simulated: Prospect?
    @State private var showsSimulator: Bool = false

    private var now: Date { recruit.now }

    var body: some View {
        ZStack {
            RecruitmentBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    intakeCard
                    if !recruit.overdueLeads.isEmpty { overdueSection }
                    freshSection
                    integrationNote
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isCreating) {
            ProspectFormView(recruit: recruit)
        }
        .sheet(item: $simulated) { prospect in
            NewLeadNoticeView(prospect: prospect) {
                simulated = nil
                onOpenProspect(prospect.id)
            }
        }
        .alert("Candidato duplicado", isPresented: $showsSimulator) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("La persona simulada ya existe en la base con el mismo teléfono o correo. No se creó un segundo expediente.")
        }
    }

    // MARK: - Intake

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    CapsLabel(text: "Bandeja de leads")
                    Text("\(recruit.count(stage: .lead)) por atender")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(recruit.overdueLeads.isEmpty ? RecTone.accent : RecTone.bad)
                    Text("Tiempo de respuesta comprometido: \(RecruitRules.contactSlaMinutes / 60) horas desde que entra el formulario.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    isCreating = true
                } label: {
                    Label("Registrar lead", systemImage: "person.badge.plus")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Palette.canvas)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RecTone.accent, in: .capsule)
                }
                .buttonStyle(.plain)

                Button {
                    simulateIncomingLead()
                } label: {
                    Label("Simular Meta", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(RecTone.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RecTone.accent.opacity(0.12), in: .capsule)
                        .overlay { Capsule().stroke(RecTone.accent.opacity(0.4), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Sections

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Fuera de tiempo",
                subtitle: "Llevan más de \(RecruitRules.contactSlaMinutes / 60) horas esperando",
                accent: RecTone.bad
            )
            ForEach(recruit.overdueLeads) { prospect in
                ProspectRow(prospect: prospect, now: now) { onOpenProspect(prospect.id) }
            }
        }
    }

    private var freshSection: some View {
        let fresh = recruit.newLeads.filter { !$0.isOverdueContact(now: now) }
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Recientes",
                subtitle: "Ordenados por hora de llegada",
                accent: RecTone.accent
            )
            if fresh.isEmpty {
                RecEmptyState(
                    symbol: "tray",
                    title: "Bandeja limpia",
                    message: "Cada lead que entró ya tuvo un primer contacto registrado."
                )
            } else {
                ForEach(fresh) { prospect in
                    ProspectRow(prospect: prospect, now: now) { onOpenProspect(prospect.id) }
                }
            }
        }
    }

    private var integrationNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Origen de los leads",
                subtitle: "Hoy simulado, mañana automático",
                accent: RecTone.accent
            )
            VStack(alignment: .leading, spacing: 8) {
                ForEach([IntegrationChannel.metaLeadAds, .whatsapp, .email], id: \.id) { channel in
                    HStack(spacing: 10) {
                        Image(systemName: channel.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                            .frame(width: 26, height: 26)
                            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(channel.label)
                                .font(.system(.footnote, weight: .bold))
                            Text(channel.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Text("PENDIENTE")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                Text("Flujo previsto: Facebook o Instagram → formulario → webhook → base central → reclutamiento → notificación. Ninguna API está conectada todavía.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .panel()
        }
    }

    // MARK: - Simulation

    /// Fires the same entry point the webhook will use when Meta Lead Ads is connected.
    private func simulateIncomingLead() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard let station = recruit.stations.randomElement() else { return }
        let campaign = recruit.campaigns.first { $0.stationId == station.id && $0.platform == .facebook }
        let stamp = Int(now.timeIntervalSince1970) % 10_000
        let payload = LeadAdPayload(
            leadgenId: "\(stamp)",
            formId: campaign?.externalFormId ?? "form_demo",
            campaignId: campaign?.id,
            platform: .facebook,
            fullName: "Carlos Hernández Loera",
            phone: "55 41\(String(format: "%02d", stamp % 100)) 88\(String(format: "%02d", stamp % 90))",
            email: "carlos.hernandez\(stamp)@correo.mx",
            city: station.city,
            stationCode: station.code,
            requestedBlock: .weekdayMorning,
            experienceYears: 3,
            platforms: ["Uber", "DiDi"],
            age: 31,
            hasLicense: true,
            createdAt: now
        )
        if let prospect = recruit.ingest(payload) {
            simulated = prospect
        } else {
            showsSimulator = true
        }
    }
}

// MARK: - New lead notice

/// What the recruiter sees the moment a form is submitted.
struct NewLeadNoticeView: View {
    let prospect: Prospect
    let onOpen: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var station: Station? { StaffDirectory.station(id: prospect.stationId) }

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                VStack(spacing: 18) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(RecTone.accent)
                        .frame(width: 88, height: 88)
                        .background(RecTone.accent.opacity(0.12), in: .circle)
                        .overlay { Circle().stroke(RecTone.accent.opacity(0.5), lineWidth: 2) }

                    VStack(spacing: 6) {
                        Text("NUEVO CANDIDATO")
                            .font(.system(size: 11, weight: .black))
                            .tracking(1.6)
                            .foregroundStyle(RecTone.accent)
                        Text(prospect.name)
                            .font(.system(.title3, weight: .black))
                            .multilineTextAlignment(.center)
                        Text("solicitó información para trabajar en \(station?.displayName ?? "la red").")
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 8) {
                        MetricLine(label: "Turno solicitado", value: prospect.requestedBlock.shortLabel, tone: RecTone.cool)
                        MetricLine(label: "Origen", value: prospect.source.label, tone: RecTone.cool)
                        MetricLine(label: "Teléfono", value: prospect.phone)
                        MetricLine(label: "Recibido", value: Fmt.clock(prospect.createdAt), detail: Fmt.dateLong(prospect.createdAt))
                    }

                    BigButton(title: "Ver candidato", symbol: "arrow.right", tone: .volt) {
                        onOpen()
                        dismiss()
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
            }
            .navigationTitle("Nuevo lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Después") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Manual registration

/// Manual lead capture with the duplicate guard in front: phone, email and CURP are
/// checked against the whole base before a second file can exist.
struct ProspectFormView: View {
    let recruit: RecruitmentStore

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var curp: String = ""
    @State private var city: String = ""
    @State private var age: Int = 28
    @State private var stationId: String = ""
    @State private var block: ShiftBlock = .weekdayMorning
    @State private var experienceYears: Int = 2
    @State private var hasLicense: Bool = true
    @State private var platforms: Set<String> = []
    @State private var source: LeadSource = .referral
    @State private var notes: String = ""
    @State private var duplicate: Prospect?

    private let platformOptions = ["Uber", "DiDi", "inDrive", "Cabify"]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && RecruitRules.normalizePhone(phone).count >= 10
            && !stationId.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Persona") {
                    TextField("Nombre completo", text: $name)
                    TextField("Teléfono", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Correo", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("CURP (opcional)", text: $curp)
                        .textInputAutocapitalization(.characters)
                    TextField("Ciudad", text: $city)
                    Stepper("Edad: \(age)", value: $age, in: 18...70)
                }

                if let duplicate {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Posible candidato duplicado", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(.footnote, weight: .bold))
                                .foregroundStyle(RecTone.warn)
                            Text("\(duplicate.name) ya existe en la base · \(duplicate.stage.label) · alta \(Fmt.dateShort(duplicate.createdAt)).")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                            Text("No se creará un segundo expediente. Revisa el existente y continúa ahí.")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                }

                Section("Vacante de interés") {
                    Picker("Estación", selection: $stationId) {
                        ForEach(recruit.stations) { station in
                            Text(station.displayName).tag(station.id)
                        }
                    }
                    Picker("Turno solicitado", selection: $block) {
                        ForEach(ShiftBlock.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                Section("Experiencia") {
                    Stepper("Años conduciendo: \(experienceYears)", value: $experienceYears, in: 0...30)
                    Toggle("Licencia vigente", isOn: $hasLicense)
                    ForEach(platformOptions, id: \.self) { option in
                        Button {
                            if platforms.contains(option) { platforms.remove(option) } else { platforms.insert(option) }
                        } label: {
                            HStack {
                                Text(option)
                                Spacer()
                                if platforms.contains(option) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(RecTone.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Origen") {
                    Picker("Fuente", selection: $source) {
                        ForEach(LeadSource.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    TextField("Comentarios", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("Reclutamiento firma el alta, pero no registra CLABE ni nómina: eso se administra en la estación con el expediente ya creado.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RecruitmentBackground())
            .navigationTitle("Nuevo lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") { save() }
                        .disabled(!canSave || duplicate != nil)
                        .font(.system(.body, weight: .bold))
                }
            }
            .onAppear {
                if stationId.isEmpty { stationId = recruit.stations.first?.id ?? "" }
                if city.isEmpty { city = StaffDirectory.station(id: stationId)?.city ?? "" }
            }
            .onChange(of: phone) { _, _ in checkDuplicate() }
            .onChange(of: email) { _, _ in checkDuplicate() }
            .onChange(of: curp) { _, _ in checkDuplicate() }
        }
        .preferredColorScheme(.dark)
    }

    private func checkDuplicate() {
        duplicate = recruit.duplicate(phone: phone, email: email, curp: curp)
    }

    private func save() {
        let created = recruit.createProspect(
            name: name.trimmingCharacters(in: .whitespaces),
            phone: phone,
            email: email,
            curp: curp,
            city: city,
            age: age,
            stationId: stationId,
            block: block,
            experienceYears: experienceYears,
            platforms: Array(platforms).sorted(),
            hasLicense: hasLicense,
            source: source,
            campaignId: nil,
            notes: notes
        )
        if created != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            checkDuplicate()
        }
    }
}
