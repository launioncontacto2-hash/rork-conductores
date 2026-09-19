// Config.swift - Auto-generated at build time
// Virtual read-only view of public environment variables available to Swift code.
//
// Values remain empty in source control and are supplied through the generated
// Info.plist at build time.

import Foundation

enum Config {
    static let EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY = bundleValue(named: "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY")
    static let EXPO_PUBLIC_SUPABASE_URL = bundleValue(named: "EXPO_PUBLIC_SUPABASE_URL")

    private static func bundleValue(named name: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: name) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static let allValues: [String: String] = [
        "EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY": EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
        "EXPO_PUBLIC_SUPABASE_URL": EXPO_PUBLIC_SUPABASE_URL,
    ]
}
