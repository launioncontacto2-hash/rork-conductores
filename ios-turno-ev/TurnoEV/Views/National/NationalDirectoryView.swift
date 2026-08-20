import SwiftUI

/// Credential directory of the whole network. Direction is the only role that can create
/// gerentes, supervisores y mantenimiento — un conductor siempre nace en su estación.
struct NationalDirectoryView: View {
    let national: NationalStore
    let header: NationalHeader

    @State private var search: String = ""
    @State private var roleFilter: StaffRole?
    @State private var isCreating: Bool = false
    @State private var selected: NetworkCredential?

    private var filters: [StaffRole?] { [nil, .manager, .supervisor, .maintenance] }

    var body: some View {
        ZStack {
            NationalBackground()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    coverageCard
                    createButton
                    filterBar
                    searchField
                    list
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isCreating) {
            CredentialFormView(national: national)
        }
        .sheet(item: $selected) { credential in
            CredentialDetailView(national: national, credential: credential)
        }
    }

    // MARK: - Coverage

    /// Three questions only direction can answer, all of them per station: ¿tiene
    /// gerente? ¿tiene supervisor en cada bloque? ¿tiene mesa de reclutamiento propia?
    private var coverageCard: some View {
        let stationCount = StaffDirectory.stations.count
        let withoutManager = national.stationsWithoutManager
        let withoutRecruiter = national.stationsWithoutRecruiter
        let gaps = national.supervisionGaps
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Cobertura de mando",
                subtitle: "Cada estación necesita su gerente, su supervisión por bloque y su reclutamiento"
            )

            HStack(spacing: 10) {
                NatFigure(
                    value: "\(stationCount - withoutManager.count)/\(stationCount)",
                    caption: "Estaciones con gerente",
                    detail: withoutManager.isEmpty
                        ? "Cada estación tiene responsable"
                        : withoutManager.map(\.code).joined(separator: ", "),
                    tone: withoutManager.isEmpty ? NatTone.good : NatTone.bad
                )
                NatFigure(
                    value: "\(stationCount * 2 - gaps.count)/\(stationCount * 2)",
                    caption: "Bloques con supervisor",
                    detail: gaps.isEmpty ? "Matutino y vespertino cubiertos" : "\(gaps.count) bloques sin cubrir",
                    tone: gaps.isEmpty ? NatTone.good : NatTone.warn
                )
            }

            NatFigure(
                value: "\(stationCount - withoutRecruiter.count)/\(stationCount)",
                caption: "Estaciones con reclutamiento",
                detail: withoutRecruiter.isEmpty
                    ? "Cada estación trabaja sus propias vacantes"
                    : "Sin mesa propia: \(withoutRecruiter.map(\.code).joined(separator: ", "))",
                tone: withoutRecruiter.isEmpty ? NatTone.good : NatTone.warn
            )

            ForEach(withoutManager.prefix(3)) { station in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NatTone.bad)
                    Text("\(station.name) · sin gerente asignado")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                }
            }

            ForEach(Array(gaps.prefix(3).enumerated()), id: \.offset) { _, gap in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NatTone.warn)
                    Text("\(gap.station.name) · bloque \(gap.slot.label.lowercased()) sin supervisor")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var createButton: some View {
        BigButton(title: "Generar credencial", symbol: "person.badge.key.fill") {
            isCreating = true
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(filters.enumerated()), id: \.offset) { _, role in
                    let isSelected = role == roleFilter
                    Button {
                        roleFilter = role
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: role?.symbol ?? "person.3.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(role?.shortLabel ?? "Todas")
                                .font(.system(.footnote, weight: .bold))
                            Text("\(national.staff(role: role).count)")
                                .font(.system(size: 10, weight: .black))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    (isSelected ? Palette.canvas.opacity(0.25) : Palette.surfaceRaised),
                                    in: .capsule
                                )
                        }
                        .foregroundStyle(isSelected ? Palette.canvas : Palette.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(isSelected ? NatTone.accent : Palette.surface.opacity(0.85), in: .capsule)
                        .overlay {
                            Capsule().stroke(isSelected ? .clear : Palette.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Palette.textMuted)
            TextField("Nombre, número de empleado o estación", text: $search)
                .font(.system(.footnote, weight: .semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .panelFlat()
    }

    // MARK: - List

    private var list: some View {
        let people = national.staff(search: search, role: roleFilter)
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Credenciales",
                subtitle: "\(people.count) cuentas con acceso a la red"
            )
            if people.isEmpty {
                Text("Ninguna credencial coincide con la búsqueda.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .panelFlat()
            } else {
                ForEach(people) { credential in
                    CredentialRow(
                        credential: credential,
                        isGenerated: national.isGenerated(credential)
                    ) {
                        selected = credential
                    }
                }
            }
        }
    }
}

// MARK: - Creation

/// Credential form. The role decides which scope is required, and the app blocks a
/// duplicate email, a repeated employee number or a shift that is already covered.
struct CredentialFormView: View {
    let national: NationalStore

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var employeeNumber: String = ""
    @State private var email: String = ""
    @State private var role: StaffRole = .supervisor
    @State private var regionId: String = StaffDirectory.regions.first?.id ?? ""
    @State private var stationId: String = StaffDirectory.stations.first?.id ?? ""
    @State private var slot: ShiftSlot = .morning
    @State private var error: String?
    @State private var created: NetworkCredential?

    private var allowedRoles: [StaffRole] { national.account.role.canRegister }

    private var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !employeeNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        if let created {
                            successCard(created)
                        } else {
                            hierarchyNote
                            roleSection
                            identitySection
                            scopeSection
                            if let error {
                                NoticeBanner(
                                    symbol: "exclamationmark.octagon.fill",
                                    title: "No se generó la credencial",
                                    message: error,
                                    tone: .danger
                                )
                            }
                            BigButton(
                                title: "Generar credencial",
                                symbol: "key.fill",
                                isEnabled: isComplete,
                                action: submit
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Nueva credencial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(created == nil ? "Cancelar" : "Listo") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hierarchyNote: some View {
        NoticeBanner(
            symbol: "arrow.triangle.branch",
            title: "Jerarquía de altas",
            message: "Dirección genera gerentes, supervisores, mantenimiento y reclutamiento, siempre para una estación. Los conductores los registra el reclutamiento de esa estación, que lleva el proceso completo hasta firmar el alta.",
            tone: .info
        )
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Rol")
            HStack(spacing: 8) {
                ForEach(allowedRoles, id: \.rawValue) { option in
                    let isSelected = option == role
                    Button {
                        role = option
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.symbol)
                                .font(.system(.footnote, weight: .bold))
                            Text(option.shortLabel)
                                .font(.system(size: 11, weight: .black))
                        }
                        .foregroundStyle(isSelected ? Palette.canvas : Palette.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(isSelected ? NatTone.accent : Palette.surfaceRaised.opacity(0.8), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? .clear : Palette.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(role.registrationNote)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Identidad")
            field(title: "Nombre completo", text: $name, placeholder: "Nombre y apellidos")
            field(title: "Número de empleado", text: $employeeNumber, placeholder: "EV-SUP-000")
            field(title: "Correo institucional", text: $email, placeholder: "nombre@turnoev.mx", isEmail: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func field(
        title: String,
        text: Binding<String>,
        placeholder: String,
        isEmail: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.textMuted)
            TextField(placeholder, text: text)
                .font(.system(.subheadline, weight: .semibold))
                .textInputAutocapitalization(isEmail ? .never : .words)
                .autocorrectionDisabled()
                .keyboardType(isEmail ? .emailAddress : .default)
                .padding(12)
                .panelFlat(cornerRadius: 14)
        }
    }

    /// Every credential direction generates is station staff, so the scope is always a
    /// station. Only supervision and workshop also need a block.
    @ViewBuilder
    private var scopeSection: some View {
        let needsSlot = role == .supervisor || role == .maintenance
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Alcance")
            Picker("Estación", selection: $stationId) {
                ForEach(StaffDirectory.stations) { station in
                    Text(station.displayName).tag(station.id)
                }
            }
            .pickerStyle(.menu)
            .tint(NatTone.accent)

            if needsSlot {
                Picker("Bloque", selection: $slot) {
                    ForEach(ShiftSlot.allCases, id: \.rawValue) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(scopeNote)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var scopeNote: String {
        switch role {
        case .manager:
            "Un gerente dirige una sola estación y responde por ella completa. Cada estación tiene el suyo."
        case .recruiter:
            "Reclutamiento es un departamento de la estación: solo trabaja las vacantes de esa sede."
        default:
            "La credencial queda ligada a esa estación: el personal no puede laborar en otra sede de la red."
        }
    }

    private func successCard(_ credential: NetworkCredential) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(NatTone.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Credencial generada")
                        .font(.system(.headline, weight: .black))
                    Text("\(credential.name) · \(credential.role.label)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                credentialLine(title: "Número de empleado", value: credential.employeeNumber)
                credentialLine(title: "Correo de acceso", value: credential.email)
                credentialLine(title: "Contraseña temporal", value: credential.temporaryPassword, tone: NatTone.accent)
                credentialLine(title: "Alcance", value: credential.scopeLabel)
            }

            Text("Entrega estos datos en persona. La contraseña temporal se cambia en el primer acceso y el dispositivo queda ligado con Face ID.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func credentialLine(title: String, value: String, tone: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.footnote, weight: .black))
                .foregroundStyle(tone)
        }
        .padding(11)
        .panelFlat(cornerRadius: 14)
    }

    private func submit() {
        let outcome = national.createCredential(
            name: name,
            employeeNumber: employeeNumber,
            email: email,
            role: role,
            stationId: role == .manager ? nil : stationId,
            regionId: role == .manager ? regionId : nil,
            slot: role == .manager ? nil : slot
        )
        switch outcome {
        case .created(let credential):
            created = credential
            error = nil
        default:
            error = outcome.message
        }
    }
}

// MARK: - Detail

/// One credential: its scope, its origin and the only decision direction can take here.
struct CredentialDetailView: View {
    let national: NationalStore
    let credential: NetworkCredential

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming: Bool = false

    private var current: NetworkCredential {
        national.networkStaff.first { $0.id == credential.id } ?? credential
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        identity
                        scope
                        capabilities
                        actions
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(current.role.shortLabel)
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

    private var identity: some View {
        VStack(spacing: 12) {
            Image(systemName: current.role.symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(current.role.directoryTone)
                .frame(width: 66, height: 66)
                .background(Palette.surfaceRaised, in: .circle)
                .overlay { Circle().stroke(current.role.directoryTone.opacity(0.5), lineWidth: 2) }

            VStack(spacing: 3) {
                Text(current.name)
                    .font(.system(.title3, weight: .black))
                    .multilineTextAlignment(.center)
                Text("\(current.role.label) · \(current.employeeNumber)")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            if current.status == .suspended {
                StatePill(text: "Credencial suspendida", symbol: "pause.circle.fill", tone: NatTone.bad)
            } else {
                StatePill(text: "Credencial activa", symbol: "checkmark.seal.fill", tone: NatTone.good)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .panel()
    }

    private var scope: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Alcance y origen")
            DetailRow(label: "Ámbito", value: current.scopeLabel)
            DetailRow(label: "Correo", value: current.email)
            if let slot = current.slot, current.role != .manager {
                DetailRow(label: "Bloque", value: slot.label)
            }
            DetailRow(label: "Generada por", value: current.createdBy)
            DetailRow(label: "Alta", value: Fmt.dateShort(current.createdAt))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Lo que puede hacer")
            ForEach(current.role.capabilities, id: \.self) { line in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NatTone.accent)
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if current.status == .active {
                BigButton(title: "Suspender credencial", symbol: "pause.circle.fill", tone: .danger) {
                    isConfirming = true
                }
            } else {
                BigButton(title: "Reactivar credencial", symbol: "play.circle.fill") {
                    national.setStatus(.active, for: current.id)
                }
            }
            Text("Suspender bloquea el acceso de inmediato en todos los dispositivos. El expediente y el historial de la persona se conservan.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .confirmationDialog(
            "¿Suspender la credencial de \(current.name)?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Suspender", role: .destructive) {
                national.setStatus(.suspended, for: current.id)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("No podrá iniciar sesión hasta que dirección la reactive.")
        }
    }
}
