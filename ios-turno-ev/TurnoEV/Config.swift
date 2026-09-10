// Config.swift - Public runtime configuration injected at iOS build time.
// Values stay empty in source control and are supplied through build settings.

import Foundation

enum Config {
    static let EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY = bundleValue(
        named: "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY"
    )
    static let EXPO_PUBLIC_SUPABASE_URL = bundleValue(
        named: "EXPO_PUBLIC_SUPABASE_URL"
    )

    static let allValues: [String: String] = [
        "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
        "EXPO_PUBLIC_SUPABASE_URL": EXPO_PUBLIC_SUPABASE_URL,
    ]

    private static func bundleValue(named name: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: name) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
