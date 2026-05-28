//
//  APIKeyStorage.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Keychain-based API key storage (Правка #4).
//  kSecAttrSynchronizable: false по умолчанию — sync через iCloud Keychain
//  включается в Правке #11 когда подпишемся и реализуем iCloud sync.
//

import Foundation
import Security

enum APIKeyStorage {
    private static let service = "com.ilya000.DrPaste.provider"
    private static var fallbackURL: URL {
        AppStorage.dataDir.appendingPathComponent("provider-keys-fallback.json")
    }

    /// Сохранить API key. Сначала пытается Keychain (best practice),
    /// fallback на plain JSON file если Keychain недоступен (unsigned build, sandbox issues).
    /// JSON файл — не идеально но позволяет dev-сборкам работать.
    @discardableResult
    static func save(_ key: String, for providerID: String, syncToICloud: Bool = false) -> Bool {
        guard !key.isEmpty else { return false }
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
            // Если Keychain принял — удалим fallback запись если она была
            removeFallback(providerID: providerID)
            return true
        }
        // Fallback на plain JSON
        NSLog("DrPaste: Keychain save failed (status \(status)), using fallback file storage.")
        return saveFallback(key, for: providerID)
    }

    /// Прочитать API key из Keychain, fallback на JSON file.
    static func load(for providerID: String) -> String? {
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

    /// Удалить ключ из Keychain (обе варианта sync) + fallback file.
    @discardableResult
    static func remove(for providerID: String) -> Bool {
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

    // MARK: - JSON fallback (для unsigned builds где Keychain недоступен)

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
