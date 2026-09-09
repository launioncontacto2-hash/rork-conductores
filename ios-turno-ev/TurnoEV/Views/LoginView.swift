import LocalAuthentication
import SwiftUI

/// Access to the network. Credentials are validated against the staff directory and the
/// resolved role is what opens an interface — a driver credential can never open the
/// supervisor, manager, maintenance or national workspace.
///
/// Face ID is the default door: on launch the scan starts by itself and opens the
/// credential linked to this device. The link is created the first time someone enters
/// with identifier + password, so the sensor unlocks a session but never escalates a
/// role — a driver's face can only open the driver interface.
struct LoginView: View {
    @Environment(FleetStore.self) private var store

    private enum Mode {
        case biometric
        case credentials
    }

    private enum CredentialMode: String, CaseIterable {
        case email
        case employee

        var label: String {
            switch self {
            case .email: "Correo"
            case .employee: "N° empleado"
            }
        }
    }

    private static let maxAttempts = 3

    @State private var mode: Mode = .credentials
    @State private var attempts: Int = 0
    @State private var isScanning: Bool = false
    @State private var lastFailed: Bool = false

    /// The automatic scan runs once per appearance of the login screen.
    @State private var didAutoStart: Bool = false

    /// Set when the device has no biometric hardware enrolled (simulator included).
    @State private var isBiometryUnavailable: Bool = false

    @State private var credentialMode: CredentialMode = .email
    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?

    // MARK: - 15B.5 Supabase Auth / RLS probe

    /// Temporary diagnostic result for the first real Supabase Auth test.
    @State private var supabaseProbeMessage: String?

    /// Prevents duplicate Auth requests if the button is tapped repeatedly.
    @State private var isSupabaseProbeRunning: Bool = false

    @State private var isRecoveryPresented: Bool = false
    @State private var isDirectoryPresented: Bool = false

    /// Account already authenticated, shown during the role handoff before the interface opens.
    @State private var handoffAccount: StaffAccount?

    private var enrolled: StaffAccount? {
        store.enrolledAccount
    }

    /// Kept for the dormant demonstration view while only current operational roles remain
    /// eligible for future previews. The production access screen does not expose it.
    private var roleShortcuts: [StaffAccount] {
        [.driver, .supervisor, .maintenance].compactMap { role in
            StaffDirectory.accounts.first { $0.role == role }
        }
    }

    var body: some View {
        ZStack {
            StationBackground()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)

                switch mode {
                case .biometric:
                    biometricSection

                case .credentials:
                    credentialsSection
                }

                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)

            if let handoffAccount {
                RoleHandoffOverlay(account: handoffAccount)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: handoffAccount?.id)
        .animation(.smooth(duration: 0.3), value: mode)
        .onAppear {
            startAutomaticAccess()
        }
        .sheet(isPresented: $isRecoveryPresented) {
            recoverySheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title2)
                .foregroundStyle(Palette.volt)
                .frame(width: 48, height: 48)
                .background(
                    Palette.volt.opacity(0.15),
                    in: .rect(cornerRadius: 16)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(DORIBrand.name)
                    .font(.system(.title3, weight: .black))

                CapsLabel(text: DORIBrand.accessTagline)
            }

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Text(DORIBrand.productName)
                .font(.system(.footnote, weight: .semibold))

            Text("La sesión no inicia ni modifica un turno por sí sola.")
            .font(.caption2)
            .foregroundStyle(Palette.textMuted)
        }
    }

    // MARK: - Face ID (device-linked credential)

    private var biometricSection: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 38)
                    .stroke(
                        lastFailed
                            ? Palette.danger.opacity(0.6)
                            : (enrolled?.role.accent ?? Palette.volt).opacity(0.45),
                        lineWidth: 2
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(isScanning ? 1.05 : 1)
                    .animation(
                        .easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true),
                        value: isScanning
                    )

                Image(systemName: "faceid")
                    .font(.system(size: 78, weight: .light))
                    .foregroundStyle(
                        lastFailed
                            ? Palette.danger
                            : (enrolled?.role.accent ?? Palette.volt)
                    )
                    .shadow(
                        color: (
                            lastFailed
                                ? Palette.danger
                                : (enrolled?.role.accent ?? Palette.volt)
                        ).opacity(0.5),
                        radius: 22
                    )
            }

            Text(isScanning ? "Verificando rostro…" : "Acceso con Face ID")
                .font(.system(.title2, weight: .black))
                .padding(.top, 26)

            if let enrolled {
                VStack(spacing: 8) {
                    Text(enrolled.name)
                        .font(.system(.subheadline, weight: .bold))

                    RoleBadge(
                        role: enrolled.role,
                        compact: true
                    )

                    Text(
                        StaffDirectory.scopeDescription(for: enrolled)
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
                }
                .padding(.top, 12)
            }

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(
                    lastFailed
                        ? Palette.danger
                        : Palette.textMuted
                )
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                BigButton(
                    title: isScanning
                        ? "Escaneando…"
                        : "Iniciar sesión",
                    symbol: "person.crop.circle.badge.checkmark",
                    isEnabled: !isScanning
                ) {
                    beginSession()
                }

                Text(
                    "Entrar a tu perfil no inicia tu turno. " +
                    "El turno se inicia aparte, desde la pantalla Turno " +
                    "y dentro de tu ventana."
                )
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                BigButton(
                    title: isScanning
                        ? "Escaneando"
                        : "Reintentar Face ID",
                    symbol: "faceid",
                    tone: .outline,
                    isEnabled: !isScanning && enrolled != nil
                ) {
                    authenticate()
                }

                Button("Entrar con otra credencial") {
                    mode = .credentials
                    attempts = 0
                    lastFailed = false
                    errorMessage = nil
                    supabaseProbeMessage = nil
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
                .frame(maxWidth: .infinity, minHeight: 46)
                .disabled(isScanning)
            }
            .padding(.top, 22)
        }
    }

    /// Quick role picker: entering here also links the credential to the device, so the
    /// next launch opens that same interface with the automatic scan.
    private var roleSwitcher: some View {
        VStack(spacing: 8) {
            CapsLabel(text: "Entrar por rol")

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(roleShortcuts) { account in
                        Button {
                            grantAccess(
                                to: account,
                                method: .credentials
                            )
                        } label: {
                            HStack(spacing: 6) {
                                Image(
                                    systemName: account.role.symbol
                                )
                                .font(
                                    .system(
                                        size: 11,
                                        weight: .bold
                                    )
                                )

                                Text(account.role.shortLabel)
                                    .font(
                                        .system(
                                            size: 12,
                                            weight: .bold
                                        )
                                    )
                            }
                            .foregroundStyle(account.role.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                account.role.accent.opacity(0.12),
                                in: .capsule
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        account.role.accent.opacity(0.45),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isScanning)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 2)
        }
        .padding(.top, 4)
    }

    private var statusMessage: String {
        if let errorMessage {
            return errorMessage
        }

        if enrolled == nil {
            return "Este dispositivo aún no tiene credencial vinculada. " +
                "Ingresa tus datos la primera vez y después entrarás " +
                "con Face ID en automático."
        }

        if lastFailed {
            return "Intento \(attempts) de \(Self.maxAttempts). " +
                "Después de 3 intentos pedimos tus credenciales."
        }

        if store.awaitsCredentialChoice {
            return "Sesión cerrada. Entra de nuevo con Face ID o elige " +
                "el rol con el que quieres trabajar."
        }

        if isBiometryUnavailable {
            return "Sin sensor biométrico en este entorno. " +
                "Se usa el acceso vinculado de demostración."
        }

        return "El escaneo inicia solo y abre la interfaz del rol " +
            "vinculado a este dispositivo."
    }

    /// Face ID fires on its own so nobody has to tap to enter; without a linked
    /// credential we go straight to the identification form. After an explicit sign out
    /// the scan waits, so another role can be chosen instead of reopening the same one.
    private func startAutomaticAccess() {
        guard !didAutoStart else {
            return
        }

        didAutoStart = true
        // The historical biometric shortcut was linked to a local demonstration
        // credential. DORI stays on the real Supabase door until a backend session can be
        // restored through Keychain without storing or fabricating a password.
        mode = .credentials
    }

    /// Opens a session, by the shortest route available on this device.
    private func beginSession() {
        guard enrolled != nil else {
            mode = .credentials
            return
        }

        authenticate()
    }

    private func authenticate() {
        guard let enrolled else {
            mode = .credentials
            return
        }

        let context = LAContext()
        context.localizedFallbackTitle = ""

        var authError: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &authError
        ) else {
            isBiometryUnavailable = true
            isScanning = true

            Task { @MainActor in
                try? await Task.sleep(
                    for: .milliseconds(900)
                )

                isScanning = false

                grantAccess(
                    to: enrolled,
                    method: .biometric
                )
            }

            return
        }

        isScanning = true
        errorMessage = nil

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason:
                "Confirma tu identidad para abrir tu panel"
        ) { success, _ in
            Task { @MainActor in
                isScanning = false

                if success {
                    lastFailed = false

                    grantAccess(
                        to: enrolled,
                        method: .biometric
                    )
                } else {
                    registerFailure(
                        message:
                            "Face ID no confirmó tu identidad"
                    )
                }
            }
        }
    }

    private func registerFailure(message: String) {
        isScanning = false
        attempts += 1
        lastFailed = true
        errorMessage = message

        if attempts >= Self.maxAttempts {
            mode = .credentials
            errorMessage = nil
        }
    }

    // MARK: - Credentials

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Identifícate")
                    .font(.system(.title2, weight: .black))

                Text(
                    "Detectamos tu rol y estación con tus credenciales, " +
                    "y abrimos solo tu interfaz. Iniciar sesión no inicia tu turno."
                )
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
            }

            TextField(
                credentialMode == .email
                    ? "correo institucional"
                    : "EV-1042",
                text: $identifier
            )
            .textContentType(
                credentialMode == .email
                    ? .emailAddress
                    : .username
            )
            .keyboardType(
                credentialMode == .email
                    ? .emailAddress
                    : .default
            )
            .textInputAutocapitalization(
                credentialMode == .email
                    ? .never
                    : .characters
            )
            .autocorrectionDisabled()
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .panelFlat()

            SecureField(
                "Contraseña",
                text: $password
            )
            .textContentType(.password)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .panelFlat()

            if let errorMessage {
                HStack(
                    alignment: .top,
                    spacing: 8
                ) {
                    Image(
                        systemName:
                            "exclamationmark.triangle.fill"
                    )

                    Text(errorMessage)
                }
                .font(.footnote)
                .foregroundStyle(Palette.danger)
            }

            if let supabaseProbeMessage {
                HStack(
                    alignment: .top,
                    spacing: 8
                ) {
                    Image(
                        systemName:
                            "checkmark.seal.fill"
                    )

                    Text(supabaseProbeMessage)
                }
                .font(.footnote)
                .foregroundStyle(Palette.volt)
            }

            BigButton(
                title: isSupabaseProbeRunning
                    ? "Verificando…"
                    : "Iniciar sesión",
                symbol: isSupabaseProbeRunning
                    ? "hourglass"
                    : "checkmark.shield.fill",
                isEnabled: !isSupabaseProbeRunning
            ) {
                submitCredentials()
            }

            HStack {
                Button {
                    isRecoveryPresented = true
                } label: {
                    Label(
                        "Recuperar contraseña",
                        systemImage: "key.fill"
                    )
                    .font(
                        .system(
                            .subheadline,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(Palette.volt)
                }

                Spacer()

            }
        }
    }

    // MARK: - Credentials submit

    private func submitCredentials() {
        let cleanedIdentifier = identifier
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        // Every visible DORI access uses Supabase Auth. Demonstration identities remain
        // in source for historical previews, but can no longer enter the operational app.
        guard credentialMode == .email,
              cleanedIdentifier.contains("@") else {
            errorMessage = "Ingresa tu correo institucional."
            supabaseProbeMessage = nil
            return
        }

            guard !isSupabaseProbeRunning else {
                return
            }

            guard !password.isEmpty else {
                errorMessage =
                    "Escribe tu contraseña."
                supabaseProbeMessage = nil
                return
            }

            errorMessage = nil
            supabaseProbeMessage = nil
            isSupabaseProbeRunning = true

            Task { @MainActor in
                defer {
                    isSupabaseProbeRunning = false
                }

                do {
                    let resolution =
                        try await SupabaseSessionResolver.run(
                            email: cleanedIdentifier,
                            password: password
                        )

                    // The password is discarded from the view after
                    // Supabase has authenticated it.
                    password = ""

                    let principal: SessionPrincipal
                    switch resolution {
                    case .staff(let result):
                        guard let role = StaffRole(backendValue: result.membership.role) else {
                            supabaseProbeMessage = nil
                            errorMessage = "No pudimos abrir esta cuenta."
                            return
                        }

                        principal = SessionPrincipal(
                            authUserId: result.authUserId.uuidString,
                            profileId: result.profile.id.uuidString,
                            name: result.profile.display_name,
                            employeeNumber: result.profile.employee_number,
                            email: cleanedIdentifier,
                            role: role,
                            environmentId: result.station.environment_id.uuidString,
                            stationId: result.station.id.uuidString,
                            stationCode: result.station.code,
                            stationName: result.station.name,
                            shiftGroup: result.shiftGroup.flatMap(ShiftGroup.init(rawValue:)),
                            shiftSlot: result.shiftSlot.flatMap(ShiftSlot.init(rawValue:))
                        )

                        print(
                            "[Sesión] Personal verificado · " +
                            "\(result.profile.employee_number) · \(result.membership.role)"
                        )

                    case .acquisition(let result):
                        principal = SessionPrincipal(
                            authUserId: result.authUserID.uuidString,
                            profileId: result.profile.id.uuidString,
                            name: result.profile.display_name,
                            employeeNumber: result.profile.employee_number,
                            email: cleanedIdentifier,
                            role: result.membership.role.sessionRole,
                            environmentId: result.membership.environmentID.uuidString,
                            stationId: nil,
                            stationCode: nil,
                            stationName: nil,
                            shiftGroup: nil,
                            shiftSlot: nil
                        )

                        print(
                            "[Adquisiciones] Membresía verificada · " +
                            "\(result.profile.employee_number) · \(result.membership.role.rawValue)"
                        )
                    }

                    supabaseProbeMessage = """
                    Acceso verificado
                    \(principal.name)
                    \(principal.role.label)
                    """

                    let role = principal.role

                    do {
                        // Supabase Auth accepts simultaneous sessions by design. Drivers
                        // are stricter: the latest successful login claims this iPhone as
                        // the only device allowed to start or finish a shift. Supervisors
                        // deliberately keep their multi-device console access.
                        if role == .driver {
                            try await SupabaseDriverDeviceService.claim()
                        }

                        try store.signIn(
                            principal: principal,
                            method: .credentials
                        )

                        // A TEST backend identity follows the shared logical clock without
                        // entering the local simulation. Its assignments and shifts remain
                        // authoritative Supabase records.
                        if store.isBackendTestSession {
                            SharedClockSync.shared.update(isTest: true)
                            await SharedClockSync.shared.refresh()
                            store.syncSimulationClock()
                        }

                        // A driver enters with the complete operation currently active in
                        // Supabase. The same refresh also runs whenever the app returns to
                        // the foreground, which is the two-iPhone handoff path.
                        if role == .driver {
                            try await store.refreshBackendOperationalState()
                        }
                    } catch {
                        // Opening a backend session and adopting its operational data is
                        // one handoff. If the second half fails, do not leave a partially
                        // opened driver session behind the access screen.
                        if store.currentPrincipal?.profileId == principal.profileId {
                            store.signOut()
                        }
                        supabaseProbeMessage = nil
                        errorMessage = "No pudimos abrir tu sesión. Intenta de nuevo."

                        print(
                            "[15B.7] sesión no abierta · " +
                            error.localizedDescription
                        )

                        return
                    }

                    print(
                        "[15B.7] sesión Supabase abierta · " +
                        "\(principal.employeeNumber) · " +
                        "\(role.label)"
                    )

                } catch {
                    password = ""
                    supabaseProbeMessage = nil
                    errorMessage = "No pudimos iniciar sesión. Revisa tus datos e intenta de nuevo."

                    print(
                        "[Sesión] Auth/RLS no resolvió la cuenta · " +
                        error.localizedDescription
                    )
                }
            }

        return
    }

    /// Shows the identified role for a beat, then opens that role's interface only.
    private func grantAccess(
        to account: StaffAccount,
        method: SignInMethod
    ) {
        handoffAccount = account

        Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(1_150)
            )

            completeHandoff(
                to: account,
                method: method,
                reason: "beat"
            )
        }

        Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(3)
            )

            completeHandoff(
                to: account,
                method: method,
                reason: "watchdog"
            )
        }
    }

    /// Single exit of the handoff.
    private func completeHandoff(
        to account: StaffAccount,
        method: SignInMethod,
        reason: String
    ) {
        guard handoffAccount != nil else {
            return
        }

        if store.session == nil {
            store.signIn(
                account: account,
                method: method
            )
        }

        handoffAccount = nil

        let opened = store.session != nil

        if !opened {
            mode = .credentials

            errorMessage =
                "No se pudo abrir la sesión de " +
                "\(account.role.label). Intenta de nuevo."
        }

        print(
            "[login] handoff \(reason) · " +
            "rol=\(account.role.label) · " +
            "sesión=\(opened)"
        )
    }

    // MARK: - Recovery

    private var recoverySheet: some View {
        NavigationStack {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                Text(
                    "DORI no crea contraseñas ni simula solicitudes desde el teléfono. " +
                    "Pide al responsable autorizado que restablezca tu cuenta en Supabase Auth " +
                    "y confirme que conservas una membresía vigente en tu estación."
                )
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)

                Spacer()
            }
            .padding(20)
            .navigationTitle(
                "Recuperar contraseña"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("Cerrar") {
                        isRecoveryPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Demo directory

    private var directorySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    Text(
                        "Toca una cuenta para entrar con ella y vincularla " +
                        "a este dispositivo: los siguientes accesos abren " +
                        "ese rol con Face ID en automático."
                    )
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)

                    ForEach(
                        StaffDirectory.accounts
                    ) { account in
                        Button {
                            credentialMode = .email
                            identifier = account.email
                            mode = .credentials
                            errorMessage = nil
                            supabaseProbeMessage = nil
                            isDirectoryPresented = false

                            grantAccess(
                                to: account,
                                method: .credentials
                            )

                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 8
                            ) {
                                HStack {
                                    RoleBadge(
                                        role: account.role,
                                        compact: true
                                    )

                                    Spacer()

                                    Text(
                                        account.employeeNumber
                                    )
                                    .font(
                                        .system(
                                            .caption,
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundStyle(
                                        Palette.textMuted
                                    )
                                }

                                Text(account.name)
                                    .font(
                                        .system(
                                            .subheadline,
                                            weight: .bold
                                        )
                                    )

                                Text(
                                    StaffDirectory
                                        .scopeDescription(
                                            for: account
                                        )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    Palette.textMuted
                                )

                                Text(account.email)
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    Palette.textMuted
                                )
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(14)
                            .panelFlat()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle(
                "Cuentas de demostración"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("Cerrar") {
                        isDirectoryPresented = false
                    }
                }
            }
        }
    }
}

/// Brief confirmation of the identified role before its interface is built.
private struct RoleHandoffOverlay: View {
    let account: StaffAccount

    @State private var appeared: Bool = false

    var body: some View {
        ZStack {
            Palette.canvas
                .opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(
                    systemName: account.role.symbol
                )
                .font(
                    .system(
                        size: 46,
                        weight: .light
                    )
                )
                .foregroundStyle(
                    account.role.accent
                )
                .frame(
                    width: 104,
                    height: 104
                )
                .background(
                    account.role.accent.opacity(0.12),
                    in: .circle
                )
                .overlay {
                    Circle()
                        .stroke(
                            account.role.accent.opacity(0.5),
                            lineWidth: 2
                        )
                        .scaleEffect(
                            appeared ? 1.12 : 0.9
                        )
                        .opacity(
                            appeared ? 0 : 1
                        )
                        .animation(
                            .easeOut(duration: 1.1)
                                .repeatForever(
                                    autoreverses: false
                                ),
                            value: appeared
                        )
                }

                VStack(spacing: 6) {
                    CapsLabel(
                        text: "Rol identificado"
                    )

                    Text(account.role.label)
                        .font(
                            .system(
                                .title2,
                                weight: .black
                            )
                        )
                        .foregroundStyle(
                            account.role.accent
                        )

                    Text(account.name)
                        .font(
                            .system(
                                .subheadline,
                                weight: .semibold
                            )
                        )

                    Text(
                        StaffDirectory
                            .scopeDescription(
                                for: account
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        Palette.textMuted
                    )
                }

                Text(
                    "Abriendo " +
                    "\(account.role.workspaceTitle.lowercased())…"
                )
                .font(.footnote)
                .foregroundStyle(
                    Palette.textMuted
                )
                .padding(.top, 4)
            }
            .padding(30)
            .scaleEffect(
                appeared ? 1 : 0.94
            )
            .opacity(
                appeared ? 1 : 0
            )
            .animation(
                .spring(
                    response: 0.45,
                    dampingFraction: 0.8
                ),
                value: appeared
            )
        }
        .onAppear {
            appeared = true
        }
    }
}

#Preview {
    LoginView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
