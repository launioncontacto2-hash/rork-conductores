import Foundation
import Supabase

// MARK: - Credentials

/// Reads the Supabase credentials out of the public configuration injected at build time.
///
/// `Config.swift` is regenerated at build time from the variables registered in Rork: the
/// literals are empty in source control and carry the real values only in a built app.
///
/// Nothing here is hardcoded and nothing is defaulted. A missing or malformed credential is
/// reported as such — naming the exact defect — and the app stays local. A bad value is never
/// silently repaired into a guess, because a connection that works by accident is worse than
/// one that fails out loud.
@MainActor
enum SupabaseConfig {
    // `nonisolated`: these are immutable names, not state. `Problem.message`
    // builds its text outside the main actor, so keeping them actor-isolated
    // would be an error under the Swift 6 language mode.
    nonisolated static let urlVariable = "EXPO_PUBLIC_SUPABASE_URL"
    nonisolated static let keyVariable = "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"

    /// The concrete ways a pasted credential goes wrong. Each one is reported by name so the
    /// laboratory can say *what* is wrong, not merely *that* something is wrong.
    enum Defect: Error, Equatable {
        case surroundingQuotes
        case surroundingBrackets
        case internalWhitespace
        /// The whole `NAME=value` pair was pasted instead of just the value.
        case variableNamePasted
        case wrongScheme(String)
        case missingScheme
        case extraPath(String)
        case looksTruncated
        case notAURL

        var explanation: String {
            switch self {
            case .surroundingQuotes:
                return "llega envuelta en comillas"
            case .surroundingBrackets:
                return "llega envuelta en corchetes o signos < >"
            case .internalWhitespace:
                return "contiene espacios o saltos de línea intermedios"
            case .variableNamePasted:
                return "incluye el nombre de la variable y un signo = delante del valor"
            case .wrongScheme(let scheme):
                return "usa el esquema \(scheme):// en lugar de https://"
            case .missingScheme:
                return "no empieza por https://"
            case .extraPath(let path):
                return "trae texto extra después del dominio (\(path))"
            case .looksTruncated:
                return "parece truncada: es demasiado corta"
            case .notAURL:
                return "no tiene forma de URL"
            }
        }
    }

    /// Why the connection cannot be built, in the words the laboratory shows.
    enum Problem: Error, Equatable {
        case missingURL
        case missingKey
        /// The received URL is echoed back: it is public information, and seeing it is the
        /// fastest way to spot a truncated or mistyped value.
        case badURL(received: String, defect: Defect)
        /// The key is never echoed — only the defect is named.
        case badKey(defect: Defect)
        case privilegedKey

        var message: String {
            switch self {
            case .missingURL:
                return "Falta la variable \(urlVariable)."
            case .missingKey:
                return "Falta la variable \(keyVariable)."
            case .badURL(let received, let defect):
                return "\(urlVariable) \(defect.explanation). Valor recibido: \(received) — debe ser exactamente https://<ref>.supabase.co"
            case .badKey(let defect):
                return "\(keyVariable) \(defect.explanation). Vuelve a pegar la publishable key sin comillas ni espacios."
            case .privilegedKey:
                return "La clave configurada es una credencial privilegiada (service_role o secret). No puede vivir dentro de la aplicación cliente: sustitúyela por la publishable key."
            }
        }
    }

    struct Credentials: Equatable {
        let url: URL
        let publishableKey: String

        /// Safe to show on screen: enough to recognise the key, never the whole secret.
        var maskedKey: String {
            guard publishableKey.count > 16 else { return "…\(publishableKey.suffix(4))" }
            return "\(publishableKey.prefix(12))…\(publishableKey.suffix(4))"
        }

        var projectRef: String {
            url.host?.split(separator: ".").first.map(String.init) ?? "—"
        }
    }

    /// The raw URL exactly as the build injected it. Public information, shown verbatim in the
    /// diagnostic so a truncated or altered value is immediately obvious.
    static var rawURL: String { Config.EXPO_PUBLIC_SUPABASE_URL }

    // MARK: Key normalisation

    /// Characters that can never legitimately appear inside a Supabase API key.
    ///
    /// Both key generations use a restricted alphabet: `sb_publishable_…` keys are
    /// `[A-Za-z0-9_]`, and legacy `anon` JWTs are base64url segments joined by dots
    /// (`[A-Za-z0-9_.-]`). A backslash is impossible in either. When one shows up it was added
    /// in transit — almost always Markdown escaping (`sb\_publishable\_…`), which happens when
    /// the key is copied out of a chat message, a README or a formatted document instead of
    /// straight from the Supabase dashboard.
    ///
    /// Same story for zero-width characters, which rich-text editors love to smuggle in.
    ///
    /// These are transport artefacts, not user choices, so they are removed — but never in
    /// silence: `keyAudit` reports every repair on screen.
    static func normalizeKey(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value.removeAll { character in
            if character == "\\" { return true }
            return character.unicodeScalars.allSatisfy { $0.properties.isDefaultIgnorableCodePoint }
        }
        return value
    }

    /// A safe, character-level portrait of the injected key.
    ///
    /// Everything here is designed to be shown on screen: the length, the fixed public prefix,
    /// the last four characters, and which suspicious characters are present. The key itself is
    /// never reconstructible from this.
    struct KeyAudit: Equatable {
        let isEmpty: Bool
        /// Length exactly as injected, before any repair.
        let rawLength: Int
        /// Length after removing transport artefacts.
        let normalizedLength: Int
        /// First characters, with invisible ones made visible.
        let visiblePrefix: String
        let lastFour: String
        let hasBackslash: Bool
        let hasSpace: Bool
        let hasNewline: Bool
        let hasQuotes: Bool
        let hasInvisible: Bool
        let recognisedFormat: KeyFormat

        var wasRepaired: Bool { rawLength != normalizedLength }

        /// Human-readable list of what is wrong with the characters themselves.
        var findings: [String] {
            var found: [String] = []
            if hasBackslash { found.append("barra invertida \\") }
            if hasSpace { found.append("espacios") }
            if hasNewline { found.append("saltos de línea") }
            if hasQuotes { found.append("comillas") }
            if hasInvisible { found.append("caracteres invisibles") }
            return found
        }
    }

    static var keyAudit: KeyAudit { audit(Config.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY) }

    static func audit(_ raw: String) -> KeyAudit {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeKey(raw)
        let quotes: Set<Character> = ["\"", "'", "`"]

        return KeyAudit(
            isEmpty: trimmed.isEmpty,
            rawLength: trimmed.count,
            normalizedLength: normalized.count,
            // 15 characters is exactly the fixed, public `sb_publishable_` marker — enough to
            // prove the prefix survived the trip, short of any random material.
            visiblePrefix: sanitizedForDisplay(String(trimmed.prefix(15))),
            lastFour: String(trimmed.suffix(4)),
            hasBackslash: trimmed.contains("\\"),
            hasSpace: trimmed.contains(" "),
            hasNewline: trimmed.contains(where: { $0.isNewline }),
            hasQuotes: trimmed.contains(where: { quotes.contains($0) }),
            hasInvisible: trimmed.contains { character in
                character.unicodeScalars.allSatisfy { $0.properties.isDefaultIgnorableCodePoint }
            },
            recognisedFormat: format(of: normalized)
        )
    }

    /// Renders invisible characters as visible marks so the diagnostic cannot lie by omission.
    private static func sanitizedForDisplay(_ text: String) -> String {
        var output = ""
        for character in text {
            if character == " " {
                output += "␠"
            } else if character.isNewline {
                output += "⏎"
            } else if character == "\t" {
                output += "⇥"
            } else if character.unicodeScalars.allSatisfy({ $0.properties.isDefaultIgnorableCodePoint }) {
                output += "⟨invisible⟩"
            } else {
                output.append(character)
            }
        }
        return output
    }

    static func resolve() -> Result<Credentials, Problem> {
        // Outer whitespace is an artefact of value injection, not a user mistake: it is
        // trimmed. Everything else is reported rather than repaired.
        let rawURL = Config.EXPO_PUBLIC_SUPABASE_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Transport artefacts (Markdown escapes, zero-width characters) are stripped here.
        // Quotes, brackets and inner spaces are deliberately *not* removed: those are genuine
        // paste mistakes and are reported below instead of being papered over.
        let rawKey = normalizeKey(Config.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY)

        guard !rawURL.isEmpty else { return .failure(.missingURL) }
        guard !rawKey.isEmpty else { return .failure(.missingKey) }

        if let defect = pasteDefect(in: rawURL, variableName: urlVariable) {
            return .failure(.badURL(received: rawURL, defect: defect))
        }
        if let defect = pasteDefect(in: rawKey, variableName: keyVariable) {
            return .failure(.badKey(defect: defect))
        }
        if rawKey.count < 20 {
            return .failure(.badKey(defect: .looksTruncated))
        }

        let url: URL
        switch validatedURL(rawURL) {
        case .success(let value): url = value
        case .failure(let defect): return .failure(.badURL(received: rawURL, defect: defect))
        }

        // Hard stop: a privileged key inside the app would hand every device full write
        // access to the whole database, bypassing Row Level Security entirely.
        guard !isPrivileged(rawKey) else { return .failure(.privilegedKey) }

        return .success(Credentials(url: url, publishableKey: rawKey))
    }

    /// Defects shared by both variables: the classic copy-paste accidents.
    private static func pasteDefect(in value: String, variableName: String) -> Defect? {
        let quotes: Set<Character> = ["\"", "'", "`"]
        if let first = value.first, let last = value.last, quotes.contains(first) || quotes.contains(last) {
            return .surroundingQuotes
        }
        if value.hasPrefix("<") || value.hasSuffix(">") || value.hasPrefix("[") || value.hasSuffix("]") {
            return .surroundingBrackets
        }
        if value.contains(where: { $0.isWhitespace }) {
            return .internalWhitespace
        }
        // Catches both `EXPO_PUBLIC_…=value` and a leftover `NEXT_PUBLIC_…=value`.
        if value.contains("=") && (value.uppercased().contains(variableName) || value.uppercased().contains("PUBLIC_SUPABASE")) {
            return .variableNamePasted
        }
        return nil
    }

    /// Accepts only a bare `https://host` origin — the shape the Supabase SDK expects.
    private static func validatedURL(_ value: String) -> Result<URL, Defect> {
        guard let components = URLComponents(string: value), let host = components.host, !host.isEmpty else {
            return .failure(value.contains("://") ? .notAURL : .missingScheme)
        }

        guard let scheme = components.scheme, !scheme.isEmpty else { return .failure(.missingScheme) }
        guard scheme == "https" else { return .failure(.wrongScheme(scheme)) }

        // A lone trailing slash is harmless and dropped; anything else is extra text.
        let path = components.path
        if !path.isEmpty && path != "/" {
            return .failure(.extraPath(path))
        }
        if let query = components.query, !query.isEmpty {
            return .failure(.extraPath("?\(query)"))
        }

        guard let origin = URL(string: "https://\(host)") else { return .failure(.notAURL) }
        return .success(origin)
    }

    /// Recognises the two shapes a privileged credential can take: the modern
    /// `sb_secret_…` key, and a legacy JWT whose payload carries `role: service_role`.
    static func isPrivileged(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return true }
        return jwtRole(of: key) == "service_role"
    }

    /// Which generation of API key this is. It decides how the key may be transmitted.
    enum KeyFormat: Equatable {
        /// `sb_publishable_…` — an opaque string, **not** a JWT.
        case publishable
        /// The legacy `anon` key, a genuine HS256 JWT.
        case legacyJWT
        case unknown

        var label: String {
            switch self {
            case .publishable: return "publishable (sb_publishable_…)"
            case .legacyJWT: return "anon heredada (JWT)"
            case .unknown: return "formato no reconocido"
            }
        }
    }

    static func format(of key: String) -> KeyFormat {
        if key.hasPrefix("sb_publishable_") { return .publishable }
        if key.split(separator: ".").count == 3 { return .legacyJWT }
        return .unknown
    }

    /// The headers Supabase expects for a keyed, unauthenticated request.
    ///
    /// This is the whole subtlety of the new key system. The API key always travels in
    /// `apikey`. `Authorization: Bearer …` is reserved for a **user session JWT**, and the new
    /// publishable keys are not JWTs — sending one as a bearer token makes the gateway try to
    /// parse it as a JWT, fail, and answer 401 even though the key is perfectly valid for the
    /// project. A legacy `anon` key *is* a JWT, which is why the same code used to work.
    ///
    /// So: `apikey` always; `Authorization` only for the legacy JWT shape.
    static func requestHeaders(for credentials: Credentials) -> [String: String] {
        var headers = ["apikey": credentials.publishableKey]
        if format(of: credentials.publishableKey) == .legacyJWT {
            headers["Authorization"] = "Bearer \(credentials.publishableKey)"
        }
        return headers
    }

    private static func jwtRole(of key: String) -> String? {
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["role"] as? String
    }
}

// MARK: - Client

/// Single Supabase client of the application.
///
/// It is optional on purpose. The app has to keep working exactly as it does today while the
/// credentials are not registered yet, so nothing here force-unwraps and nothing crashes on
/// launch: without configuration `client` is simply `nil` and every caller stays local.
@MainActor
enum SupabaseBridge {
    private static var cached: SupabaseClient?
    private static var cachedFor: SupabaseConfig.Credentials?

    /// The live client, or nil while the project is not configured.
    static var client: SupabaseClient? {
        guard case .success(let credentials) = SupabaseConfig.resolve() else {
            cached = nil
            cachedFor = nil
            return nil
        }

        // Rebuild only when the credentials actually changed.
        if let cached, cachedFor == credentials { return cached }

        let created = SupabaseClient(
            supabaseURL: credentials.url,
            supabaseKey: credentials.publishableKey
        )
        cached = created
        cachedFor = credentials
        return created
    }

    static var isConfigured: Bool {
        if case .success = SupabaseConfig.resolve() { return true }
        return false
    }
}

// MARK: - Connection check

/// Minimal proof that this device can talk to the Supabase project.
///
/// It asks the Auth service health endpoint (`/auth/v1/health`) — the endpoint Supabase
/// publishes for exactly this purpose. It is a better probe than the Data API root: it does
/// not depend on any table, schema or PostgREST exposure setting, it reads and writes nothing
/// operational, and it answers with the service identity so the check can prove *which*
/// service replied instead of merely that something did.
///
/// What it proves is the three things worth proving at this stage: the URL resolves, the
/// network reaches it, and the gateway accepts the key.
@MainActor
enum SupabaseHealth {
    /// Path of the official health endpoint, kept in one place so the diagnostic and the
    /// request can never drift apart.
    static let healthPath = "auth/v1/health"

    /// Identity of the service that answered, when it reports one.
    ///
    /// `nonisolated` because it is pure data decoded off the main actor.
    nonisolated struct ServiceInfo: Codable, Equatable {
        let name: String?
        let version: String?
        let description: String?

        /// Short label for the screen, e.g. "GoTrue v2.180.0". Nil when nothing usable came back.
        var label: String? {
            switch (name, version) {
            case let (name?, version?): return "\(name) \(version)"
            case let (name?, nil): return name
            case let (nil, version?): return version
            default: return nil
            }
        }
    }

    /// What a refusal actually tells us. A 401 has several possible causes and they are not
    /// interchangeable, so the check reports only what the response supports — never a guess.
    enum Rejection: Equatable {
        /// The gateway tried to read the key as a JWT. Evidence of a header/format mismatch,
        /// not of an invalid key.
        case notAJWT
        /// The project explicitly said the key is not one of its keys.
        case invalidAPIKey
        /// The legacy `anon`/`service_role` keys have been disabled for this project.
        case legacyKeysDisabled
        /// Refused, but the response does not say why. We do not invent a reason.
        case undetermined(String?)

        var summary: String {
            switch self {
            case .notAJWT:
                return "La puerta de enlace intentó leer la clave como JWT."
            case .invalidAPIKey:
                return "El proyecto declara que esta clave no le pertenece o fue revocada."
            case .legacyKeysDisabled:
                return "Las claves heredadas (anon/service_role) están deshabilitadas en este proyecto."
            case .undetermined(let body):
                if let body, !body.isEmpty {
                    return "El proyecto rechazó la petición sin indicar una causa reconocible: \(body)"
                }
                return "El proyecto rechazó la petición sin indicar una causa."
            }
        }

        /// What to do about it. Deliberately avoids blaming the key unless there is evidence.
        var advice: String {
            switch self {
            case .notAJWT:
                return "Es un problema de cabeceras, no de la clave: la clave publishable debe viajar sólo en apikey."
            case .invalidAPIKey:
                return "Verifica en Supabase → Settings → API Keys que la clave siga activa y sea la de este proyecto."
            case .legacyKeysDisabled:
                return "Usa la clave publishable (sb_publishable_…) en lugar de la anon heredada."
            case .undetermined:
                return "No hay evidencia suficiente para atribuirlo a la clave. Revisa el estado del proyecto en Supabase."
            }
        }
    }

    enum Outcome: Equatable {
        case idle
        case checking
        case notConfigured(SupabaseConfig.Problem)
        /// Reached and the key was accepted. Latency in milliseconds, plus the service
        /// identity when the endpoint reports one.
        case connected(milliseconds: Int, projectRef: String, service: ServiceInfo?)
        /// Reached, but the project refused the request.
        case rejected(status: Int, rejection: Rejection)
        case unreachable(reason: String)

        var isConclusive: Bool {
            switch self {
            case .idle, .checking: return false
            default: return true
            }
        }
    }

    static func check() async -> Outcome {
        switch SupabaseConfig.resolve() {
        case .failure(let problem):
            return .notConfigured(problem)

        case .success(let credentials):
            // The SDK client is built here too, so a configuration that cannot produce a
            // client is caught by the check rather than at the first real query.
            guard SupabaseBridge.client != nil else {
                return .unreachable(reason: "No se pudo construir el cliente de Supabase.")
            }

            var request = URLRequest(url: credentials.url.appendingPathComponent(healthPath))
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            // The API key travels in `apikey` and nowhere else. No `Authorization` header is
            // set here: that one carries a signed-in user's JWT, and a publishable key is not
            // a JWT — sending it as a bearer token is what made the gateway answer 401.
            request.setValue(credentials.publishableKey, forHTTPHeaderField: "apikey")

            let started = ContinuousClock.now
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let elapsed = ContinuousClock.now - started
                let milliseconds = Int(elapsed / .milliseconds(1))

                guard let http = response as? HTTPURLResponse else {
                    return .unreachable(reason: "Respuesta no reconocida del servidor.")
                }

                switch http.statusCode {
                case 200:
                    return .connected(
                        milliseconds: milliseconds,
                        projectRef: credentials.projectRef,
                        service: try? JSONDecoder().decode(ServiceInfo.self, from: data)
                    )

                case 401, 403:
                    return .rejected(status: http.statusCode, rejection: classify(body: data))

                default:
                    return .unreachable(reason: "El proyecto respondió con estado \(http.statusCode).")
                }
            } catch {
                // Sanitised: the key never reaches the log.
                print("[Supabase] Falló la comprobación de conexión: \(error.localizedDescription)")
                return .unreachable(reason: error.localizedDescription)
            }
        }
    }

    /// Reads the refusal from the response body instead of inferring it from the status code.
    private static func classify(body: Data) -> Rejection {
        guard let text = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .undetermined(nil)
        }

        let lowered = text.lowercased()

        if lowered.contains("invalid jwt")
            || lowered.contains("bad_jwt")
            || lowered.contains("invalid_jwt_format")
            || lowered.contains("invalid token") {
            return .notAJWT
        }
        if lowered.contains("legacy") && lowered.contains("disabled") {
            return .legacyKeysDisabled
        }
        if lowered.contains("invalid api key") || lowered.contains("invalid_api_key") {
            return .invalidAPIKey
        }

        // Keep the excerpt short: it is a diagnostic, not a log dump.
        return .undetermined(String(text.prefix(160)))
    }
}

// MARK: - Auth + RLS end-to-end probe

@MainActor
enum SupabaseAuthProbe {

    nonisolated struct ProfileRow: Decodable, Sendable {
        let id: UUID
        let auth_user_id: UUID?
        let employee_number: String
        let display_name: String
        let status: String
    }

    /// Active operational membership returned by RLS.
    ///
    /// The shift assignment belongs to the membership, not to the profile:
    /// the profile identifies the person; the membership says where, as what
    /// and in which operational block that person currently works.
    nonisolated struct MembershipRow: Decodable, Sendable {
        let id: UUID
        let profile_id: UUID
        let station_id: UUID
        let role: String
        let shift_group: String?
        let shift_slot: String?
        let starts_at: Date
        let ends_at: Date?
    }

    nonisolated struct StationRow: Decodable, Sendable {
        let id: UUID
        let environment_id: UUID
        let code: String
        let name: String
        let status: String
    }

    /// Complete identity proved against Auth + RLS.
    ///
    /// Nothing here is inferred from MockData. If this result exists, every
    /// operational field came from the authenticated Supabase world.
    struct Result: Sendable {
        let authUserId: UUID
        let profile: ProfileRow
        let membership: MembershipRow
        let station: StationRow

        var employeeNumber: String {
            profile.employee_number
        }

        var displayName: String {
            profile.display_name
        }

        var role: String {
            membership.role
        }

        var stationCode: String {
            station.code
        }

        var shiftGroup: String? {
            membership.shift_group
        }

        var shiftSlot: String? {
            membership.shift_slot
        }
    }

    enum ProbeError: LocalizedError {
        case notConfigured
        case noProfile
        case multipleProfiles(Int)
        case noMembership
        case multipleMemberships(Int)
        case noStation
        case multipleStations(Int)
        case wrongAuthUser(expected: UUID, received: UUID?)
        case wrongRole(String)
        case inactiveProfile(String)
        case inactiveStation(String)
        case missingShiftGroup
        case missingShiftSlot
        case invalidShiftGroup(String)
        case invalidShiftSlot(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Supabase no está configurado."

            case .noProfile:
                return "El usuario inició sesión, pero RLS no devolvió ningún perfil."

            case .multipleProfiles(let count):
                return "RLS devolvió \(count) perfiles; debía devolver exactamente uno."

            case .noMembership:
                return "El perfil no tiene una membresía visible."

            case .multipleMemberships(let count):
                return "RLS devolvió \(count) membresías; para esta prueba debía devolver exactamente una."

            case .noStation:
                return "La membresía no permite leer ninguna estación."

            case .multipleStations(let count):
                return "RLS devolvió \(count) estaciones; para esta prueba debía devolver exactamente una."

            case .wrongAuthUser(let expected, let received):
                return "El perfil no corresponde al usuario Auth. Esperado \(expected), recibido \(received?.uuidString ?? "nil")."

            case .wrongRole(let role):
                return "La membresía devolvió un rol inesperado: \(role)."

            case .inactiveProfile(let status):
                return "El perfil no está activo: \(status)."

            case .inactiveStation(let status):
                return "La estación no está activa: \(status)."

            case .missingShiftGroup:
                return "La membresía del conductor no tiene shift_group."

            case .missingShiftSlot:
                return "La membresía del conductor no tiene shift_slot."

            case .invalidShiftGroup(let value):
                return "La membresía devolvió un shift_group no reconocido: \(value)."

            case .invalidShiftSlot(let value):
                return "La membresía devolvió un shift_slot no reconocido: \(value)."
            }
        }
    }

    static func run(
        email: String,
        password: String
    ) async throws -> Result {

        guard let client = SupabaseBridge.client else {
            throw ProbeError.notConfigured
        }

        // 1. Auth REAL.
        //
        // From this point on the Supabase SDK carries the authenticated
        // user's JWT. The following reads therefore exercise the actual
        // RLS policies rather than the public API key alone.
        let session = try await client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )

        let authUserId = session.user.id

        // 2. Profile visible under RLS.
        let profiles: [ProfileRow] = try await client
            .from("profiles")
            .select(
                """
                id,
                auth_user_id,
                employee_number,
                display_name,
                status
                """
            )
            .execute()
            .value

        guard !profiles.isEmpty else {
            throw ProbeError.noProfile
        }

        guard profiles.count == 1 else {
            throw ProbeError.multipleProfiles(profiles.count)
        }

        let profile = profiles[0]

        guard profile.auth_user_id == authUserId else {
            throw ProbeError.wrongAuthUser(
                expected: authUserId,
                received: profile.auth_user_id
            )
        }

        guard profile.status == "active" else {
            throw ProbeError.inactiveProfile(profile.status)
        }

        // 3. Active membership visible under RLS.
        //
        // shift_group and shift_slot are intentionally read from this row.
        // They are operational assignments and must not come from MockData.
        let memberships: [MembershipRow] = try await client
            .from("staff_memberships")
            .select(
                """
                id,
                profile_id,
                station_id,
                role,
                shift_group,
                shift_slot,
                starts_at,
                ends_at
                """
            )
            // A supervisor can legitimately read every active membership at the
            // station. Authentication must resolve only the signed-in profile's
            // membership, not treat those supervised drivers as duplicate identities.
            .eq("profile_id", value: profile.id.uuidString)
            .is("ends_at", value: nil)
            .execute()
            .value

        guard !memberships.isEmpty else {
            throw ProbeError.noMembership
        }

        guard memberships.count == 1 else {
            throw ProbeError.multipleMemberships(memberships.count)
        }

        let membership = memberships[0]

        guard membership.profile_id == profile.id else {
            throw ProbeError.noMembership
        }

        guard membership.role == "driver"
                || membership.role == "supervisor"
                || membership.role == "maintenance"
                || membership.role == "recruitment" else {
            throw ProbeError.wrongRole(membership.role)
        }

        // Only a driver needs an assigned operational block. A supervisor's
        // station scope comes from the membership itself and may legitimately
        // carry no shift group or slot.
        if membership.role == "driver" {
            guard let shiftGroup = membership.shift_group,
                  !shiftGroup.isEmpty else {
                throw ProbeError.missingShiftGroup
            }

            guard let shiftSlot = membership.shift_slot,
                  !shiftSlot.isEmpty else {
                throw ProbeError.missingShiftSlot
            }

            guard ShiftGroup(rawValue: shiftGroup) != nil else {
                throw ProbeError.invalidShiftGroup(shiftGroup)
            }

            guard ShiftSlot(rawValue: shiftSlot) != nil else {
                throw ProbeError.invalidShiftSlot(shiftSlot)
            }
        }

        // 4. Station visible under RLS.
        let stations: [StationRow] = try await client
            .from("stations")
            .select(
                """
                id,
                environment_id,
                code,
                name,
                status
                """
            )
            .execute()
            .value

        guard !stations.isEmpty else {
            throw ProbeError.noStation
        }

        guard stations.count == 1 else {
            throw ProbeError.multipleStations(stations.count)
        }

        let station = stations[0]

        guard station.id == membership.station_id else {
            throw ProbeError.noStation
        }

        guard station.status == "active" else {
            throw ProbeError.inactiveStation(station.status)
        }

        return Result(
            authUserId: authUserId,
            profile: profile,
            membership: membership,
            station: station
        )
    }
}

// MARK: - 15C vehicle assignment

/// The iOS contract for the already deployed 15C tables and RPC. All reads run with the
/// signed-in user's JWT, so RLS remains the authority for station scope. The only write is
/// `assign_vehicle`; the client never inserts or updates an assignment or vehicle directly.
@MainActor
enum SupabaseAssignmentService {
    nonisolated struct DriverRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let profile_id: UUID
        let employee_number: String
        let status: String
    }

    nonisolated struct VehicleRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let internal_number: String
        let plate: String?
        let qr_code: String
        let model: String
        let odometer_km: Int
        let battery_pct: Int?
        let status: String
    }

    nonisolated struct AssignmentRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let driver_profile_id: UUID
        let vehicle_id: UUID
        let kind: String
        let titular_vehicle_id: UUID?
        let note: String?
        let assigned_by: UUID
        let assigned_at: Date
        let ended_at: Date?
    }

    nonisolated struct Snapshot: Sendable {
        let drivers: [DriverRow]
        let vehicles: [VehicleRow]
        let assignments: [AssignmentRow]
    }

    nonisolated struct DriverAssignment: Sendable {
        let assignment: AssignmentRow
        let vehicle: VehicleRow
    }

    nonisolated struct AssignParameters: Encodable, Sendable {
        let p_driver_profile_id: UUID
        let p_vehicle_id: UUID
        let p_idempotency_key: String
        let p_kind: String
        let p_titular_vehicle_id: UUID?
        let p_note: String?
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidStation
        case invalidIdentifier
        case driverProfileNotVisible
        case missingTitular
        case assignmentVehicleNotVisible

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase no está configurado."
            case .invalidStation: "La sesión no contiene una estación válida."
            case .invalidIdentifier: "El conductor o el vehículo no tienen un identificador válido."
            case .driverProfileNotVisible: "RLS no devolvió el perfil operativo del conductor."
            case .missingTitular: "Para asignar una sustituta, el conductor debe tener una unidad titular vigente."
            case .assignmentVehicleNotVisible: "La asignación existe, pero RLS no permitió leer su vehículo."
            }
        }
    }

    static func loadSupervisorSnapshot(stationId: String) async throws -> Snapshot {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidStation }

        async let driversRequest: [DriverRow] = client
            .from("driver_profiles")
            .select("id,station_id,profile_id,employee_number,status")
            .eq("station_id", value: stationId)
            .execute()
            .value

        async let vehiclesRequest: [VehicleRow] = client
            .from("vehicles")
            .select("id,station_id,internal_number,plate,qr_code,model,odometer_km,battery_pct,status")
            .eq("station_id", value: stationId)
            .execute()
            .value

        async let assignmentsRequest: [AssignmentRow] = client
            .from("assignments")
            .select("id,station_id,driver_profile_id,vehicle_id,kind,titular_vehicle_id,note,assigned_by,assigned_at,ended_at")
            .eq("station_id", value: stationId)
            .execute()
            .value

        let (drivers, vehicles, assignments) = try await (
            driversRequest,
            vehiclesRequest,
            assignmentsRequest
        )

        return Snapshot(
            drivers: drivers.filter { $0.status == "active" }.sorted { $0.employee_number < $1.employee_number },
            vehicles: vehicles.sorted { $0.internal_number < $1.internal_number },
            assignments: assignments.filter { $0.ended_at == nil }
        )
    }

    @discardableResult
    static func assign(
        driverId: String,
        vehicleId: String,
        kind: AssignedUnitKind,
        titularVehicleId: String?,
        note: String
    ) async throws -> AssignmentRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard let driverUUID = UUID(uuidString: driverId),
              let vehicleUUID = UUID(uuidString: vehicleId) else {
            throw ServiceError.invalidIdentifier
        }

        let titularUUID = titularVehicleId.flatMap(UUID.init(uuidString:))
        if kind == .substitute, titularUUID == nil { throw ServiceError.missingTitular }

        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let parameters = AssignParameters(
            p_driver_profile_id: driverUUID,
            p_vehicle_id: vehicleUUID,
            p_idempotency_key: "ios-\(UUID().uuidString.lowercased())",
            p_kind: kind.rawValue,
            p_titular_vehicle_id: kind == .substitute ? titularUUID : nil,
            p_note: cleanedNote.isEmpty ? nil : cleanedNote
        )

        return try await client
            .rpc("assign_vehicle", params: parameters)
            .execute()
            .value
    }

    static func loadDriverAssignment(profileId: String) async throws -> DriverAssignment? {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: profileId) != nil else { throw ServiceError.invalidIdentifier }

        // `SessionPrincipal.profileId` identifies public.profiles. Assignments do not point
        // at that identity row directly: their foreign key is public.driver_profiles.id.
        // Resolve the authenticated driver's operational profile under RLS before reading
        // the assignment. Using profiles.id in the assignment filter returns an honest but
        // misleading empty result, which is why the UI previously said "sin unidad".
        let driverProfiles: [DriverRow] = try await client
            .from("driver_profiles")
            .select("id,station_id,profile_id,employee_number,status")
            .eq("profile_id", value: profileId)
            .execute()
            .value

        guard let driverProfile = driverProfiles.first(where: { $0.status == "active" }) else {
            throw ServiceError.driverProfileNotVisible
        }

        let assignments: [AssignmentRow] = try await client
            .from("assignments")
            .select("id,station_id,driver_profile_id,vehicle_id,kind,titular_vehicle_id,note,assigned_by,assigned_at,ended_at")
            .eq("driver_profile_id", value: driverProfile.id.uuidString)
            .execute()
            .value

        guard let assignment = assignments
            .filter({ $0.ended_at == nil })
            .max(by: { $0.assigned_at < $1.assigned_at }) else {
            return nil
        }

        let vehicles: [VehicleRow] = try await client
            .from("vehicles")
            .select("id,station_id,internal_number,plate,qr_code,model,odometer_km,battery_pct,status")
            .eq("id", value: assignment.vehicle_id.uuidString)
            .execute()
            .value

        guard let vehicle = vehicles.first else { throw ServiceError.assignmentVehicleNotVisible }
        return DriverAssignment(assignment: assignment, vehicle: vehicle)
    }
}

// MARK: - 16A exclusive driver device

/// Claims and verifies the one iPhone allowed to perform driver operations.
///
/// The identifier belongs to the installation, not to the person. It contains no
/// credential and survives app restarts so the server can distinguish two physical
/// phones that authenticate with the same Supabase user.
@MainActor
enum SupabaseDriverDeviceService {
    private static let installIdKey = "turnoev.backend.install-id"

    nonisolated struct ClaimParameters: Encodable, Sendable {
        let p_install_id: String
        let p_app_version: String?
    }

    nonisolated struct HeartbeatParameters: Encodable, Sendable {
        let p_install_id: String
    }

    nonisolated struct DeviceRow: Decodable, Sendable {
        let id: UUID
        let install_id: String
        let profile_id: UUID
        let platform: String
        let last_seen_at: Date
        let deleted_at: Date?
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case sessionReplaced

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Supabase no está configurado."
            case .sessionReplaced:
                return "Esta cuenta se abrió en otro teléfono. Vuelve a iniciar sesión para tomar el control."
            }
        }
    }

    static var installId: String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: installIdKey),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }

        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: installIdKey)
        return generated
    }

    private static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func claim() async throws {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        let parameters = ClaimParameters(
            p_install_id: installId,
            p_app_version: appVersion
        )

        do {
            let _: DeviceRow = try await client
                .rpc("claim_driver_device", params: parameters)
                .execute()
                .value
        } catch {
            throw translate(error)
        }
    }

    static func heartbeat() async throws {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        let parameters = HeartbeatParameters(p_install_id: installId)

        do {
            let _: DeviceRow = try await client
                .rpc("heartbeat_driver_device", params: parameters)
                .execute()
                .value
        } catch {
            throw translate(error)
        }
    }

    static func isSessionReplacement(_ error: Error) -> Bool {
        if case ServiceError.sessionReplaced = error { return true }
        return error.localizedDescription.contains("driver_session_replaced")
    }

    private static func translate(_ error: Error) -> Error {
        if error.localizedDescription.contains("driver_session_replaced") {
            return ServiceError.sessionReplaced
        }
        return error
    }
}

// MARK: - 15D/16A shift lifecycle

/// Authenticated iOS contract for the 15D shift tables and RPCs. Reads remain subject
/// to RLS; starts and finishes always cross the transactional server functions.
@MainActor
enum SupabaseShiftService {
    nonisolated struct ShiftRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let driver_profile_id: UUID
        let vehicle_id: UUID
        let assignment_id: UUID
        let folio: String
        let status: String
        let shift_group: String
        let shift_slot: String
        let scheduled_start_at: Date
        let scheduled_end_at: Date
        let started_at: Date
        let finished_at: Date?
        let late_minutes: Int
        let start_odometer_km: Int
        let start_battery_pct: Int
        let end_odometer_km: Int?
        let end_battery_pct: Int?
        let revision: Int64
    }

    nonisolated struct StartParameters: Encodable, Sendable {
        let p_assignment_id: UUID
        let p_odometer_km: Int64
        let p_battery_pct: Int
        let p_idempotency_key: String
        let p_install_id: String
    }

    nonisolated struct FinishParameters: Encodable, Sendable {
        let p_shift_id: UUID
        let p_expected_revision: Int64
        let p_odometer_km: Int64
        let p_battery_pct: Int
        let p_idempotency_key: String
        let p_install_id: String
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidIdentifier

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase no está configurado."
            case .invalidIdentifier: "El turno o la asignación no tienen un identificador válido."
            }
        }
    }

    private static let columns = """
        id,station_id,driver_profile_id,vehicle_id,assignment_id,folio,status,
        shift_group,shift_slot,scheduled_start_at,scheduled_end_at,started_at,
        finished_at,late_minutes,start_odometer_km,start_battery_pct,
        end_odometer_km,end_battery_pct,revision
        """

    static func loadOpenShift(assignmentId: String) async throws -> ShiftRow? {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: assignmentId) != nil else { throw ServiceError.invalidIdentifier }

        let rows: [ShiftRow] = try await client
            .from("shifts")
            .select(columns)
            .eq("assignment_id", value: assignmentId)
            .eq("status", value: "open")
            .execute()
            .value

        return rows.max { $0.started_at < $1.started_at }
    }

    static func loadSupervisorOpenShifts(stationId: String) async throws -> [ShiftRow] {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidIdentifier }

        let rows: [ShiftRow] = try await client
            .from("shifts")
            .select(columns)
            .eq("station_id", value: stationId)
            .eq("status", value: "open")
            .execute()
            .value

        return rows.sorted { $0.started_at > $1.started_at }
    }

    static func start(
        assignmentId: String,
        odometerKm: Int,
        batteryPct: Int,
        idempotencyKey: String
    ) async throws -> ShiftRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard let assignmentUUID = UUID(uuidString: assignmentId) else {
            throw ServiceError.invalidIdentifier
        }

        let parameters = StartParameters(
            p_assignment_id: assignmentUUID,
            p_odometer_km: Int64(odometerKm),
            p_battery_pct: batteryPct,
            p_idempotency_key: idempotencyKey,
            p_install_id: SupabaseDriverDeviceService.installId
        )

        return try await client
            .rpc("start_shift_v2", params: parameters)
            .execute()
            .value
    }

    static func finish(
        shiftId: String,
        expectedRevision: Int64,
        odometerKm: Int,
        batteryPct: Int,
        idempotencyKey: String
    ) async throws -> ShiftRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard let shiftUUID = UUID(uuidString: shiftId) else {
            throw ServiceError.invalidIdentifier
        }

        let parameters = FinishParameters(
            p_shift_id: shiftUUID,
            p_expected_revision: expectedRevision,
            p_odometer_km: Int64(odometerKm),
            p_battery_pct: batteryPct,
            p_idempotency_key: idempotencyKey,
            p_install_id: SupabaseDriverDeviceService.installId
        )

        return try await client
            .rpc("finish_shift_v2", params: parameters)
            .execute()
            .value
    }
}

// MARK: - 15E incident lifecycle

/// Authenticated contract for incident reports. The server derives identity, vehicle,
/// station, severity and timestamp from the signed-in driver's open shift; the phone only
/// sends the human observation and an idempotency key.
@MainActor
enum SupabaseIncidentService {
    nonisolated struct IncidentRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let shift_id: UUID
        let vehicle_id: UUID
        let reported_by: UUID
        let folio: String
        let kind: String
        let severity: String
        let description: String
        let status: String
        let resolution_note: String?
        let revision: Int64
        let reported_at: Date
        let closed_at: Date?
    }

    nonisolated struct ReportParameters: Encodable, Sendable {
        let p_shift_id: UUID
        let p_kind: String
        let p_description: String
        let p_idempotency_key: String
        let p_install_id: String
    }

    nonisolated struct UpdateParameters: Encodable, Sendable {
        let p_incident_id: UUID
        let p_expected_revision: Int64
        let p_status: String
        let p_note: String?
        let p_idempotency_key: String
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidIdentifier

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase no está configurado."
            case .invalidIdentifier: "El turno no tiene un identificador válido."
            }
        }
    }

    private static let columns = """
        id,station_id,shift_id,vehicle_id,reported_by,folio,kind,severity,
        description,status,resolution_note,revision,reported_at,closed_at
        """

    static func loadDriverIncidents(profileId: String) async throws -> [IncidentRow] {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: profileId) != nil else { throw ServiceError.invalidIdentifier }

        let rows: [IncidentRow] = try await client
            .from("incidents")
            .select(columns)
            .eq("reported_by", value: profileId)
            .order("reported_at", ascending: false)
            .execute()
            .value

        return rows
    }

    static func loadStationIncidents(stationId: String) async throws -> [IncidentRow] {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidIdentifier }

        return try await client
            .from("incidents")
            .select(columns)
            .eq("station_id", value: stationId)
            .order("reported_at", ascending: false)
            .execute()
            .value
    }

    static func report(
        shiftId: String,
        kind: IncidentKind,
        description: String,
        idempotencyKey: String
    ) async throws -> IncidentRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard let shiftUUID = UUID(uuidString: shiftId) else {
            throw ServiceError.invalidIdentifier
        }

        let parameters = ReportParameters(
            p_shift_id: shiftUUID,
            p_kind: kind.rawValue,
            p_description: description,
            p_idempotency_key: idempotencyKey,
            p_install_id: SupabaseDriverDeviceService.installId
        )

        return try await client
            .rpc("report_incident", params: parameters)
            .execute()
            .value
    }

    static func update(
        incident: IncidentRow,
        status: String,
        note: String?,
        idempotencyKey: String
    ) async throws -> IncidentRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client
            .rpc(
                "update_incident",
                params: UpdateParameters(
                    p_incident_id: incident.id,
                    p_expected_revision: incident.revision,
                    p_status: status,
                    p_note: note,
                    p_idempotency_key: idempotencyKey
                )
            )
            .execute()
            .value
    }
}

// MARK: - 15E workshop lifecycle

/// Station-scoped workshop contract. RLS selects the maintenance technician's station;
/// every mutation remains an authenticated, revision-checked and idempotent RPC.
@MainActor
enum SupabaseWorkshopService {
    nonisolated struct WorkOrderRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let vehicle_id: UUID
        let incident_id: UUID
        let folio: String
        let problem: String
        let priority: String
        let status: String
        let estimated_minutes: Int
        let work_done: String
        let revision: Int64
        let opened_at: Date
        let closed_at: Date?
    }

    nonisolated struct OpenParameters: Encodable, Sendable {
        let p_incident_id: UUID
        let p_priority: String
        let p_estimated_minutes: Int
        let p_idempotency_key: String
    }

    nonisolated struct CloseParameters: Encodable, Sendable {
        let p_work_order_id: UUID
        let p_expected_revision: Int64
        let p_work_done: String
        let p_idempotency_key: String
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidIdentifier

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase no está configurado."
            case .invalidIdentifier: "La estación no tiene un identificador válido."
            }
        }
    }

    private static let columns = """
        id,station_id,vehicle_id,incident_id,folio,problem,priority,status,
        estimated_minutes,work_done,revision,opened_at,closed_at
        """

    static func loadStationOrders(stationId: String) async throws -> [WorkOrderRow] {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidIdentifier }

        return try await client
            .from("work_orders")
            .select(columns)
            .eq("station_id", value: stationId)
            .order("opened_at", ascending: false)
            .execute()
            .value
    }

    static func loadStationVehicles(
        stationId: String
    ) async throws -> [SupabaseAssignmentService.VehicleRow] {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidIdentifier }

        return try await client
            .from("vehicles")
            .select("id,station_id,internal_number,plate,qr_code,model,odometer_km,battery_pct,status")
            .eq("station_id", value: stationId)
            .order("internal_number", ascending: true)
            .execute()
            .value
    }

    static func open(
        incidentId: UUID,
        priority: String,
        estimatedMinutes: Int,
        idempotencyKey: String
    ) async throws -> WorkOrderRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client
            .rpc(
                "open_work_order",
                params: OpenParameters(
                    p_incident_id: incidentId,
                    p_priority: priority,
                    p_estimated_minutes: estimatedMinutes,
                    p_idempotency_key: idempotencyKey
                )
            )
            .execute()
            .value
    }

    static func close(
        order: WorkOrderRow,
        workDone: String,
        idempotencyKey: String
    ) async throws -> WorkOrderRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client
            .rpc(
                "close_work_order",
                params: CloseParameters(
                    p_work_order_id: order.id,
                    p_expected_revision: order.revision,
                    p_work_done: workDone,
                    p_idempotency_key: idempotencyKey
                )
            )
            .execute()
            .value
    }
}

// MARK: - 15F coverage lifecycle

/// Authoritative absence and guard contract. The phone reads only rows admitted by RLS;
/// identity, station, eligibility and the winner of a race are all decided in PostgreSQL.
@MainActor
enum SupabaseCoverageService {
    nonisolated struct AbsenceRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let driver_profile_id: UUID
        let vacancy_id: UUID?
        let folio: String
        let operating_date: String
        let shift_group: String
        let shift_slot: String
        let kind: String
        let reason: String
        let comments: String
        let status: String
        let decision_note: String?
        let revision: Int64
        let requested_at: Date
        let decided_at: Date?
    }

    nonisolated struct VacancyRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let absence_id: UUID?
        let titular_driver_profile_id: UUID?
        let folio: String
        let operating_date: String
        let shift_group: String
        let shift_slot: String
        let origin: String
        let bonus_mode: String
        let bonus_mxn: Int
        let reason: String
        let status: String
        let is_critical: Bool
        let revision: Int64
        let opened_at: Date
        let claimed_at: Date?
        let approved_at: Date?
    }

    nonisolated struct ClaimRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let vacancy_id: UUID
        let driver_profile_id: UUID
        let status: String
        let operating_date: String
        let shift_slot: String
        let note: String?
        let claimed_at: Date
        let decided_at: Date?
    }

    nonisolated struct DriverSnapshot: Sendable {
        let absences: [AbsenceRow]
        let vacancies: [VacancyRow]
        let claims: [ClaimRow]
    }

    nonisolated struct StationSnapshot: Sendable {
        let absences: [AbsenceRow]
        let vacancies: [VacancyRow]
        let claims: [ClaimRow]
    }

    nonisolated struct RequestParameters: Encodable, Sendable {
        let p_operating_date: String
        let p_shift_slot: String
        let p_kind: String
        let p_reason: String
        let p_comments: String
        let p_idempotency_key: String
        let p_install_id: String
    }

    nonisolated struct ClaimParameters: Encodable, Sendable {
        let p_vacancy_id: UUID
        let p_idempotency_key: String
        let p_install_id: String
    }

    nonisolated struct ApproveParameters: Encodable, Sendable {
        let p_vacancy_id: UUID
        let p_expected_revision: Int64
        let p_note: String?
        let p_idempotency_key: String
    }

    nonisolated struct ResolveParameters: Encodable, Sendable {
        let p_absence_id: UUID
        let p_expected_revision: Int64
        let p_decision: String
        let p_note: String
        let p_idempotency_key: String
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidIdentifier

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase no está configurado."
            case .invalidIdentifier: "La vacante no tiene un identificador válido."
            }
        }
    }

    private static let absenceColumns = """
        id,station_id,driver_profile_id,vacancy_id,folio,operating_date,
        shift_group,shift_slot,kind,reason,comments,status,decision_note,
        revision,requested_at,decided_at
        """
    private static let vacancyColumns = """
        id,station_id,absence_id,titular_driver_profile_id,folio,operating_date,
        shift_group,shift_slot,origin,bonus_mode,bonus_mxn,reason,status,
        is_critical,revision,opened_at,claimed_at,approved_at
        """
    private static let claimColumns = """
        id,station_id,vacancy_id,driver_profile_id,status,operating_date,
        shift_slot,note,claimed_at,decided_at
        """

    static func loadDriverSnapshot(stationId: String) async throws -> DriverSnapshot {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidIdentifier }

        async let absenceRequest: [AbsenceRow] = client
            .from("absences")
            .select(absenceColumns)
            .order("requested_at", ascending: false)
            .execute()
            .value
        async let vacancyRequest: [VacancyRow] = client
            .from("coverage_vacancies")
            .select(vacancyColumns)
            .eq("station_id", value: stationId)
            .order("opened_at", ascending: false)
            .execute()
            .value
        async let claimRequest: [ClaimRow] = client
            .from("coverage_claims")
            .select(claimColumns)
            .order("claimed_at", ascending: false)
            .execute()
            .value

        let (absences, vacancies, claims) = try await (
            absenceRequest, vacancyRequest, claimRequest
        )
        return DriverSnapshot(absences: absences, vacancies: vacancies, claims: claims)
    }

    static func loadStationSnapshot(stationId: String) async throws -> StationSnapshot {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidIdentifier }

        async let absenceRequest: [AbsenceRow] = client
            .from("absences")
            .select(absenceColumns)
            .eq("station_id", value: stationId)
            .order("requested_at", ascending: false)
            .execute()
            .value
        async let vacancyRequest: [VacancyRow] = client
            .from("coverage_vacancies")
            .select(vacancyColumns)
            .eq("station_id", value: stationId)
            .order("opened_at", ascending: false)
            .execute()
            .value
        async let claimRequest: [ClaimRow] = client
            .from("coverage_claims")
            .select(claimColumns)
            .eq("station_id", value: stationId)
            .order("claimed_at", ascending: false)
            .execute()
            .value

        let (absences, vacancies, claims) = try await (
            absenceRequest, vacancyRequest, claimRequest
        )
        return StationSnapshot(absences: absences, vacancies: vacancies, claims: claims)
    }

    static func requestAbsence(
        operatingDate: String,
        shiftSlot: ShiftSlot,
        kind: AbsenceKind,
        reason: String,
        comments: String,
        idempotencyKey: String
    ) async throws -> AbsenceRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client
            .rpc(
                "request_absence",
                params: RequestParameters(
                    p_operating_date: operatingDate,
                    p_shift_slot: shiftSlot.rawValue,
                    p_kind: kind.rawValue,
                    p_reason: reason,
                    p_comments: comments,
                    p_idempotency_key: idempotencyKey,
                    p_install_id: SupabaseDriverDeviceService.installId
                )
            )
            .execute()
            .value
    }

    static func claim(
        vacancyId: UUID,
        idempotencyKey: String
    ) async throws -> ClaimRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client
            .rpc(
                "claim_guard",
                params: ClaimParameters(
                    p_vacancy_id: vacancyId,
                    p_idempotency_key: idempotencyKey,
                    p_install_id: SupabaseDriverDeviceService.installId
                )
            )
            .execute()
            .value
    }

    static func approve(
        vacancy: VacancyRow,
        note: String?,
        idempotencyKey: String
    ) async throws -> VacancyRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client
            .rpc(
                "approve_guard",
                params: ApproveParameters(
                    p_vacancy_id: vacancy.id,
                    p_expected_revision: vacancy.revision,
                    p_note: note,
                    p_idempotency_key: idempotencyKey
                )
            )
            .execute()
            .value
    }

    static func resolve(
        absence: AbsenceRow,
        decision: String,
        note: String,
        idempotencyKey: String
    ) async throws -> AbsenceRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client
            .rpc(
                "resolve_absence",
                params: ResolveParameters(
                    p_absence_id: absence.id,
                    p_expected_revision: absence.revision,
                    p_decision: decision,
                    p_note: note,
                    p_idempotency_key: idempotencyKey
                )
            )
            .execute()
            .value
    }

    nonisolated static func userMessage(for error: Error) -> String {
        let message = error.localizedDescription
        let lowered = message.lowercased()
        if lowered.contains("vacancy_already_claimed") {
            return "Otro conductor tomó esta guardia primero. Actualiza para ver que ya fue asignada."
        }
        if lowered.contains("driver_has_regular_shift_conflict") {
            return "Esta guardia coincide con tu turno regular."
        }
        if lowered.contains("driver_has_shift_conflict")
            || lowered.contains("driver_has_guard_conflict") {
            return "Ya tienes un turno o guardia en ese horario."
        }
        if lowered.contains("titular_cannot_claim_own_vacancy") {
            return "No puedes tomar la guardia creada por tu propia ausencia."
        }
        if lowered.contains("absence_shift_group_not_owned")
            || lowered.contains("absence_shift_slot_not_owned") {
            return "La fecha y el turno deben corresponder a tu bloque asignado."
        }
        if lowered.contains("revision_conflict") {
            return "La información cambió en otro dispositivo. Actualiza antes de continuar."
        }
        return message
    }
}

// MARK: - 15H recruitment dossier + hiring

/// Authoritative recruitment contract. The app can read only the station rows exposed by
/// RLS, uploads immutable objects to the private bucket and mutates the lifecycle solely
/// through the audited RPC/Edge Function pair.
@MainActor
enum SupabaseHiringService {
    nonisolated struct CandidateRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let station_id: UUID
        let full_name: String
        let phone: String
        let email: String
        let city: String
        let age: Int
        let curp: String
        let requested_shift_group: String
        let requested_shift_slot: String
        let stage: String
        let screening_status: String?
        let interview_score: Int?
        let interview_decision: String?
        let notes: String?
        let revision: Int64
        let created_at: Date
        let updated_at: Date
        let hired_at: Date?
    }

    nonisolated struct DocumentRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let candidate_id: UUID
        let kind: String
        let status: String
        let object_path: String
        let original_filename: String
        let content_type: String
        let byte_size: Int64
        let issued_at: String?
        let expires_at: String?
        let uploaded_at: Date
    }

    nonisolated struct HiringRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let candidate_id: UUID
        let employee_number: String
        let shift_group: String
        let shift_slot: String
        let status: String
        let revision: Int64
        let failure_code: String?
        let signed_at: Date
        let completed_at: Date?
    }

    nonisolated struct Snapshot: Sendable {
        let candidates: [CandidateRow]
        let documents: [DocumentRow]
        let hirings: [HiringRow]
    }

    nonisolated struct UploadParameters: Encodable, Sendable {
        let p_candidate_id: UUID
        let p_kind: String
        let p_object_path: String
        let p_original_filename: String
        let p_issued_at: String?
        let p_expires_at: String?
        let p_checksum_sha256: String?
        let p_idempotency_key: String
    }

    nonisolated struct CompleteParameters: Encodable, Sendable {
        let candidate_id: UUID
        let employee_number: String
        let temporary_password: String
        let idempotency_key: String
    }

    nonisolated struct CompleteResponse: Decodable, Sendable {
        let hiring: HiringRow
        let created: Bool
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidStation
        case invalidScope
        case unsupportedFile
        case fileTooLarge

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase no está configurado."
            case .invalidStation: "La sesión de reclutamiento no contiene una estación válida."
            case .invalidScope: "El expediente no corresponde a esta sesión."
            case .unsupportedFile: "Usa PDF, JPEG, PNG o HEIC."
            case .fileTooLarge: "El archivo supera el límite de 10 MB."
            }
        }
    }

    private static let candidateColumns = """
        id,station_id,full_name,phone,email,city,age,curp,
        requested_shift_group,requested_shift_slot,stage,screening_status,
        interview_score,interview_decision,notes,revision,created_at,updated_at,hired_at
        """
    private static let documentColumns = """
        id,candidate_id,kind,status,object_path,original_filename,content_type,
        byte_size,issued_at,expires_at,uploaded_at
        """
    private static let hiringColumns = """
        id,candidate_id,employee_number,shift_group,shift_slot,status,revision,
        failure_code,signed_at,completed_at
        """

    static func loadSnapshot(stationId: String) async throws -> Snapshot {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard UUID(uuidString: stationId) != nil else { throw ServiceError.invalidStation }

        async let candidateRequest: [CandidateRow] = client
            .from("candidates")
            .select(candidateColumns)
            .eq("station_id", value: stationId)
            .order("created_at", ascending: false)
            .execute()
            .value
        async let documentRequest: [DocumentRow] = client
            .from("candidate_documents")
            .select(documentColumns)
            .eq("station_id", value: stationId)
            .order("uploaded_at", ascending: false)
            .execute()
            .value
        async let hiringRequest: [HiringRow] = client
            .from("hirings")
            .select(hiringColumns)
            .eq("station_id", value: stationId)
            .order("signed_at", ascending: false)
            .execute()
            .value

        let (candidates, documents, hirings) = try await (
            candidateRequest, documentRequest, hiringRequest
        )
        return Snapshot(candidates: candidates, documents: documents, hirings: hirings)
    }

    static func uploadDocument(
        data: Data,
        filename: String,
        contentType: String,
        candidate: CandidateRow,
        principal: SessionPrincipal,
        kind: String,
        issuedAt: String? = nil,
        expiresAt: String? = nil
    ) async throws -> DocumentRow {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }
        guard data.count <= 10 * 1_024 * 1_024 else { throw ServiceError.fileTooLarge }
        guard ["application/pdf", "image/jpeg", "image/png", "image/heic"].contains(contentType)
        else { throw ServiceError.unsupportedFile }
        guard let environmentId = principal.environmentId,
              let stationId = principal.stationId,
              candidate.station_id.uuidString.caseInsensitiveCompare(stationId) == .orderedSame
        else { throw ServiceError.invalidScope }

        let operationId = UUID().uuidString.lowercased()
        let extensionName = (filename as NSString).pathExtension.lowercased()
        let storedName = extensionName.isEmpty ? operationId : "\(operationId).\(extensionName)"
        let path = "\(environmentId)/\(stationId)/\(candidate.id.uuidString.lowercased())/\(storedName)"

        try await client.storage
            .from("candidate-documents")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: contentType, upsert: false)
            )

        return try await client
            .rpc(
                "upload_document",
                params: UploadParameters(
                    p_candidate_id: candidate.id,
                    p_kind: kind,
                    p_object_path: path,
                    p_original_filename: filename,
                    p_issued_at: issuedAt,
                    p_expires_at: expiresAt,
                    p_checksum_sha256: nil,
                    p_idempotency_key: "ios-document-\(operationId)"
                )
            )
            .execute()
            .value
    }

    static func completeHiring(
        candidateId: UUID,
        employeeNumber: String,
        temporaryPassword: String
    ) async throws -> CompleteResponse {
        guard let client = SupabaseBridge.client else { throw ServiceError.notConfigured }

        return try await client.functions.invoke(
            "complete-hiring",
            options: FunctionInvokeOptions(
                body: CompleteParameters(
                    candidate_id: candidateId,
                    employee_number: employeeNumber,
                    temporary_password: temporaryPassword,
                    idempotency_key: "ios-hiring-\(UUID().uuidString.lowercased())"
                )
            )
        )
    }

    nonisolated static func userMessage(for error: Error) -> String {
        let message = error.localizedDescription
        let lowered = message.lowercased()
        if lowered.contains("candidate_not_ready") || lowered.contains("candidate_documents_incomplete") {
            return "El expediente todavía no contiene los seis documentos vigentes."
        }
        if lowered.contains("employee_number_already_exists") {
            return "Ese número de empleado ya pertenece a otra persona."
        }
        if lowered.contains("auth_identity_creation_failed") {
            return "No se pudo crear la identidad de acceso. Verifica que el correo no esté registrado."
        }
        if lowered.contains("test_environment_required") {
            return "El alta automática está habilitada únicamente en TEST."
        }
        if lowered.contains("session") || lowered.contains("jwt") {
            return "La sesión venció. Inicia sesión nuevamente."
        }
        return message
    }
}
