import Foundation
import Supabase

// MARK: - Credentials

/// Reads the Supabase credentials out of the public configuration injected at build time.
///
/// Two deliberate decisions here:
///
/// 1. The values are read through `Config.allValues` instead of `Config.EXPO_PUBLIC_SUPABASE_URL`.
///    `Config.swift` is regenerated at build time from the variables registered in Rork, so a
///    direct reference would not compile until those variables exist. The dictionary lookup
///    compiles today and starts returning real values the moment they are registered.
/// 2. Nothing is hardcoded and nothing is defaulted. A missing credential is reported as
///    missing; it is never replaced by a guess.
@MainActor
enum SupabaseConfig {
    static let urlVariable = "EXPO_PUBLIC_SUPABASE_URL"
    static let keyVariable = "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"

    /// Why the connection cannot be built, in the words the laboratory shows.
    enum Problem: Error, Equatable {
        case missingURL
        case missingKey
        case malformedURL
        case privilegedKey

        var message: String {
            switch self {
            case .missingURL:
                return "Falta la variable \(urlVariable)."
            case .missingKey:
                return "Falta la variable \(keyVariable)."
            case .malformedURL:
                return "\(urlVariable) no es una URL válida. Debe verse como https://<ref>.supabase.co"
            case .privilegedKey:
                return "La clave configurada es una credencial privilegiada (service_role o secret). No puede vivir dentro de la aplicación cliente: sustitúyela por la publishable key."
            }
        }
    }

    struct Credentials: Equatable {
        let url: URL
        let publishableKey: String

        /// Safe to show on screen: enough to recognise the project, never the whole key.
        var maskedKey: String {
            let visible = publishableKey.prefix(12)
            return "\(visible)…\(publishableKey.suffix(4))"
        }

        var projectRef: String {
            url.host?.split(separator: ".").first.map(String.init) ?? "—"
        }
    }

    static func resolve() -> Result<Credentials, Problem> {
        let rawURL = value(for: urlVariable)
        let rawKey = value(for: keyVariable)

        guard let rawURL, !rawURL.isEmpty else { return .failure(.missingURL) }
        guard let rawKey, !rawKey.isEmpty else { return .failure(.missingKey) }

        guard let url = URL(string: rawURL), let scheme = url.scheme, scheme == "https", url.host != nil else {
            return .failure(.malformedURL)
        }

        // Hard stop: a privileged key inside the app would hand every device full write
        // access to the whole database, bypassing Row Level Security entirely.
        guard !isPrivileged(rawKey) else { return .failure(.privilegedKey) }

        return .success(Credentials(url: url, publishableKey: rawKey))
    }

    private static func value(for name: String) -> String? {
        Config.allValues[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
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
                // Sanitised: the URL and the key never reach the log.
                print("[Supabase] Falló la comprobación de conexión: \(error.localizedDescription)")
                return .unreachable(reason: error.localizedDescription)
            }
        }
    }
}
