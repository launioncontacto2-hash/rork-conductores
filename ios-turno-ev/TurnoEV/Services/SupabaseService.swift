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

    static func resolve() -> Result<Credentials, Problem> {
        // Outer whitespace is an artefact of value injection, not a user mistake: it is
        // trimmed. Everything else is reported rather than repaired.
        let rawURL = Config.EXPO_PUBLIC_SUPABASE_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = Config.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY.trimmingCharacters(in: .whitespacesAndNewlines)

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
/// It asks the REST root (`/rest/v1/`) rather than any table, so it works before a single
/// table exists and it never reads or writes operational data. What it proves is exactly the
/// three things worth proving at this stage: the URL resolves, the network reaches it, and
/// the publishable key is accepted.
@MainActor
enum SupabaseHealth {
    enum Outcome: Equatable {
        case idle
        case checking
        case notConfigured(SupabaseConfig.Problem)
        /// Reached and the key was accepted. Latency in milliseconds.
        case connected(milliseconds: Int, projectRef: String)
        /// Reached, but the project refused the key.
        case rejected(status: Int)
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

            var request = URLRequest(url: credentials.url.appendingPathComponent("rest/v1/"))
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            request.setValue(credentials.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(credentials.publishableKey)", forHTTPHeaderField: "Authorization")

            let started = ContinuousClock.now
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let elapsed = ContinuousClock.now - started
                let milliseconds = Int(elapsed / .milliseconds(1))

                guard let http = response as? HTTPURLResponse else {
                    return .unreachable(reason: "Respuesta no reconocida del servidor.")
                }

                switch http.statusCode {
                case 200..<300:
                    return .connected(milliseconds: milliseconds, projectRef: credentials.projectRef)
                case 401, 403:
                    return .rejected(status: http.statusCode)
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
}
