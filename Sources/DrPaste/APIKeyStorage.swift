//
//  APIKeyStorage.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Keychain-backed API key storage with a plain-JSON fallback for unsigned
//  builds. kSecAttrSynchronizable defaults to false; iCloud Keychain sync is
//  reserved for when the app ships signed.
//

import Foundation
import Security

enum APIKeyStorage {
    private static let service = "com.ilya000.DrPaste.provider"
    private static var fallbackURL: URL {
        AppStorage.dataDir.appendingPathComponent("provider-keys-fallback.json")
    }

    /// UserDefaults key for the "skip Keychain" preference. When true, all
    /// save / load / remove operations route through the plain-JSON fallback
    /// file and Keychain is never touched. Default false (Keychain first).
    static let fallbackOnlyDefaultsKey = "drpaste.api_keys.use_fallback_only"

    /// True when the user has chosen to bypass Keychain entirely. Reads the
    /// flag on every access so toggling in Settings takes effect immediately.
    ///
    /// Rationale: unsigned builds suffer a Keychain login-password prompt on
    /// every binary hash change (i.e. every rebuild) because Keychain's ACL
    /// is tied to the calling app's code signature. With this flag set, keys
    /// live at `~/Library/Application Support/DrPaste/provider-keys-fallback.json`
    /// with 0o600 (user-only) file permissions — same protection level as
    /// `~/.aws/credentials` or `~/.kube/config`. Acceptable for local-personal
    /// use; switch back to Keychain once the app ships signed and notarized.
    static var fallbackOnly: Bool {
        UserDefaults.standard.bool(forKey: fallbackOnlyDefaultsKey)
    }

    static func setFallbackOnly(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: fallbackOnlyDefaultsKey)
    }

    /// Saves an API key. Tries Keychain first (best practice). Falls back to a
    /// plain JSON file when Keychain is unavailable (unsigned builds, sandbox
    /// issues). The JSON file is not ideal but lets development builds work.
    @discardableResult
    static func save(_ key: String, for providerID: String, syncToICloud: Bool = false) -> Bool {
        guard !key.isEmpty else { return false }
        // Skip Keychain entirely when the user opted out of it (e.g. unsigned
        // build to avoid the per-launch password prompt).
        if fallbackOnly {
            return saveFallback(key, for: providerID)
        }
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecAttrSynchronizable as String: syncToICloud ? kCFBooleanTrue! : kCFBooleanFalse!
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = syncToICloud
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess {
            // Keychain accepted the key — drop any stale fallback entry.
            removeFallback(providerID: providerID)
            return true
        }
        // Fall back to plain JSON.
        NSLog("DrPaste: Keychain save failed (status \(status)), using fallback file storage.")
        return saveFallback(key, for: providerID)
    }

    /// Reads an API key from Keychain, falling back to the JSON file.
    /// When the user has opted out of Keychain (`fallbackOnly == true`), only
    /// the JSON file is consulted so no Keychain ACL prompt can fire.
    static func load(for providerID: String) -> String? {
        if fallbackOnly {
            return loadFallback(providerID: providerID)
        }
        for sync in [false, true] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: providerID,
                kSecAttrSynchronizable as String: sync ? kCFBooleanTrue! : kCFBooleanFalse!,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data,
               let key = String(data: data, encoding: .utf8) {
                return key
            }
        }
        return loadFallback(providerID: providerID)
    }

    /// Removes the key from Keychain (both sync variants) and from the fallback file.
    /// In fallback-only mode the Keychain delete is skipped — Keychain access
    /// from an unsigned binary triggers the same password prompt we are
    /// trying to avoid.
    @discardableResult
    static func remove(for providerID: String) -> Bool {
        if fallbackOnly {
            removeFallback(providerID: providerID)
            return true
        }
        var anyRemoved = false
        for sync in [false, true] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: providerID,
                kSecAttrSynchronizable as String: sync ? kCFBooleanTrue! : kCFBooleanFalse!
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess { anyRemoved = true }
        }
        removeFallback(providerID: providerID)
        return anyRemoved
    }

    // MARK: - JSON fallback (used by unsigned builds where Keychain is unavailable)

    private static func readFallbackMap() -> [String: String] {
        guard let data = try? Data(contentsOf: fallbackURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private static func writeFallbackMap(_ map: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(map) else { return false }
        do {
            try data.write(to: fallbackURL, options: .atomic)
            // Restrict file permissions to user-only (read/write).
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                    ofItemAtPath: fallbackURL.path)
            return true
        } catch {
            NSLog("DrPaste: fallback key storage write failed: \(error)")
            return false
        }
    }

    private static func saveFallback(_ key: String, for providerID: String) -> Bool {
        var map = readFallbackMap()
        map[providerID] = key
        return writeFallbackMap(map)
    }

    private static func loadFallback(providerID: String) -> String? {
        readFallbackMap()[providerID]
    }

    private static func removeFallback(providerID: String) {
        var map = readFallbackMap()
        if map.removeValue(forKey: providerID) != nil {
            _ = writeFallbackMap(map)
        }
    }
}
