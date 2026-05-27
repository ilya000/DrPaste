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

    /// Сохранить API key в Keychain.
    /// - Parameter syncToICloud: если true — kSecAttrSynchronizable: true,
    ///   ключ синхронизируется через iCloud Keychain (Правка #11).
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
        return status == errSecSuccess
    }

    /// Прочитать API key. Возвращает nil если нет (или нет permissions).
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
        return nil
    }

    /// Удалить ключ из Keychain (обе варианта sync).
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
        return anyRemoved
    }
}
