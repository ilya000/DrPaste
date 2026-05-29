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

    /// TEMPORARY (0.14.0, will be restored in #A1).
    ///
    /// Keychain access is currently disabled for ALL builds. The previous
    /// user-controllable "Skip macOS Keychain" toggle exposed inconsistent
    /// behaviour across rebuild cycles (each rebuild changes the binary
    /// hash, so Keychain ACL prompts for the login password on every
    /// launch, even when the user had a key successfully saved on the
    /// previous build). Until #A1 ships a signed `.app` with a stable code
    /// signature, every API key lives in the plain-JSON fallback file at
    /// `~/Library/Application Support/DrPaste/provider-keys-fallback.json`
    /// with `0o600` (user-only) permissions — the same protection level
    /// as `~/.aws/credentials` or `~/.kube/config`.
    ///
    /// #A1 will: (1) re-enable the Keychain code paths in `save`, `load`,
    /// and `remove`, (2) flip this getter back to reading
    /// `UserDefaults.standard.bool(forKey: fallbackOnlyDefaultsKey)`, and
    /// (3) ship a one-time migration that moves any JSON-file keys into
    /// the now-stable Keychain.
    static var fallbackOnly: Bool {
        true
        // UserDefaults.standard.bool(forKey: fallbackOnlyDefaultsKey)
    }

    static func setFallbackOnly(_ enabled: Bool) {
        // TEMPORARY (#A1): no-op while Keychain is disabled. The getter
        // ignores the persisted flag, so writing it would just leave a
        // stale value behind for the migration to clean up later.
        _ = enabled
        // UserDefaults.standard.set(enabled, forKey: fallbackOnlyDefaultsKey)
    }

    /// Saves an API key.
    ///
    /// TEMPORARY (#A1): all keys are routed to the plain-JSON fallback
    /// file. The Keychain code path below is intentionally commented out
    /// — it will be restored when #A1 lands a signed `.app`. Until then
    /// every save / load / remove stays out of Keychain so unsigned dev
    /// builds don't trigger the login-password ACL prompt on each
    /// rebuild.
    @discardableResult
    static func save(_ key: String, for providerID: String, syncToICloud: Bool = false) -> Bool {
        guard !key.isEmpty else { return false }
        _ = syncToICloud  // unused while Keychain path is disabled — see #A1
        return saveFallback(key, for: providerID)

        /* ORIGINAL KEYCHAIN CODE — restore in #A1 after signed `.app` ships.
           Currently commented out so unsigned builds do not invoke
           SecItemAdd, which prompts for the login password on every binary
           hash change.

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
            removeFallback(providerID: providerID)
            return true
        }
        NSLog("DrPaste: Keychain save failed (status \(status)), using fallback file storage.")
        return saveFallback(key, for: providerID)
        */
    }

    /// Reads an API key.
    ///
    /// TEMPORARY (#A1): always reads from the JSON fallback. The Keychain
    /// lookup is intentionally suppressed — see `save` for context.
    static func load(for providerID: String) -> String? {
        return loadFallback(providerID: providerID)

        /* ORIGINAL KEYCHAIN CODE — restore in #A1.

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
        */
    }

    /// Removes a stored key from the JSON fallback file.
    ///
    /// TEMPORARY (#A1): Keychain delete path commented out. When #A1
    /// re-enables Keychain, the delete needs to fan out across both the
    /// synced and non-synced Keychain variants AND the fallback file, so
    /// a key migrated between storage backends doesn't leave a stale
    /// twin behind.
    @discardableResult
    static func remove(for providerID: String) -> Bool {
        removeFallback(providerID: providerID)
        return true

        /* ORIGINAL KEYCHAIN CODE — restore in #A1.

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
        */
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
