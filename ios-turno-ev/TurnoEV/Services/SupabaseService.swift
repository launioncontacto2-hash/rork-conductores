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
    static let urlVariable = "EXPO_PUBLIC_SUPABASE_URL"
    static let keyVariable = "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"

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

    nonisolated struct MembershipRow: Decodable, Sendable {
        let id: UUID
        let profile_id: UUID
        let station_id: UUID
        let role: String
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

    struct Result: Sendable {
        let authUserId: UUID
        let profile: ProfileRow
        let membership: MembershipRow
        let station: StationRow
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
        // Supabase conserva la sesión y las consultas siguientes llevan
        // el JWT del usuario autenticado.
        let session = try await client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )

        let authUserId = session.user.id

        // 2. Perfil visible bajo RLS.
        let profiles: [ProfileRow] = try await client
            .from("profiles")
            .select("id,auth_user_id,employee_number,display_name,status")
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

        // 3. Membresía visible bajo RLS.
        let memberships: [MembershipRow] = try await client
            .from("staff_memberships")
            .select("id,profile_id,station_id,role,starts_at,ends_at")
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

        guard membership.role == "driver" else {
            throw ProbeError.wrongRole(membership.role)
        }

        // 4. Estación visible bajo RLS.
        let stations: [StationRow] = try await client
            .from("stations")
            .select("id,environment_id,code,name,status")
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

        guard membership.role == "driver" else {
            throw ProbeError.wrongRole(membership.role)
        }

        // For a driver these are required operational assignments.
        guard let shiftGroup = membership.shift_group,
              !shiftGroup.isEmpty else {
            throw ProbeError.missingShiftGroup
        }

        guard let shiftSlot = membership.shift_slot,
              !shiftSlot.isEmpty else {
            throw ProbeError.missingShiftSlot
        }

        // Validate against the Swift domain now, before these strings are
        // allowed to reach FleetStore.
        guard ShiftGroup(rawValue: shiftGroup) != nil else {
            throw ProbeError.invalidShiftGroup(shiftGroup)
        }

        guard ShiftSlot(rawValue: shiftSlot) != nil else {
            throw ProbeError.invalidShiftSlot(shiftSlot)
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