//
//  LoginItemManager.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Thin wrapper around SMAppService.mainApp for the Settings toggle.
//

import Foundation
import ServiceManagement

@MainActor
enum LoginItemManager {
    enum LoginItemError: LocalizedError {
        case notBundledApp

        var errorDescription: String? {
            switch self {
            case .notBundledApp:
                return "Launch on Login only works from a bundled .app build."
            }
        }
    }

    static var isSupportedBuild: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusMessage: String {
        guard isSupportedBuild else {
            return "Available in the bundled .app build."
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            return "DrPaste will start automatically when you log in."
        case .notRegistered:
            return "DrPaste will not start automatically."
        case .requiresApproval:
            return "macOS needs approval in System Settings -> Login Items."
        case .notFound:
            return "Login item registration is not available for this build."
        @unknown default:
            return "Login item status is unknown."
        }
    }

    static func refresh() -> (enabled: Bool, message: String) {
        (isEnabled, statusMessage)
    }

    static func setEnabled(_ enabled: Bool) throws -> (enabled: Bool, message: String) {
        guard isSupportedBuild else {
            throw LoginItemError.notBundledApp
        }

        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }

        return refresh()
    }
}
