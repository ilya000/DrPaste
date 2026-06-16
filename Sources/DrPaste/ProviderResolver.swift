//
//  ProviderResolver.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Unified AI provider resolution (#A44, 0.57.0).
//
//  Background: pre-0.57 the "which provider would actually execute
//  THIS action right now" question lived in scattered helpers across
//  the runtime and three UI surfaces:
//
//    - `AIImageAction.resolveProvider()` — runtime soft fallback for
//      image-edit calls, walks `providerID` → `defaultProviderID` →
//      `cheapestEnabledImageProvider`.
//    - `AIProviderRegistry.cheapestEnabledImageProvider()` — cached
//      cost-rank read for the UI badges and picker.
//    - `BigHUD.swift` action-chip provider icon — recomputes "real"
//      executor for image actions.
//    - `MiniHUD.swift` inflight label — same logic, different code.
//    - `SettingsWindow.swift` per-action row + Edit Action picker —
//      yet another copy.
//
//  Each surface carried its own "and check if the resolved provider
//  is different from the user's nominal pick, and if so render an
//  arrow indicator" recipe. The shipped fix for #219 anchored the
//  runtime + UI to the same cheapest-image-provider helper, but the
//  call shapes still differ enough that a future refactor could
//  drift them apart again.
//
//  This file lifts the recipe into one pure function returning a
//  strongly-typed struct:
//
//      ProviderResolver.resolve(
//          action: AIActionLike,
//          operationKind: .text | .imageEdit | .textToImage,
//          config: ProvidersConfig
//      ) -> ResolvedAIProvider?
//
//  Every UI consumer reads the same struct, so:
//
//    - the `providerLabel` + `providerKind` flow into the badge,
//    - `isRerouted` + `rerouteReason` drive the "fallback to: X"
//      notice text,
//    - `capabilityUsed` matches the runtime executor (image-capable
//      providers stay distinct from text-only ones),
//    - `recoveryHint` powers the "Connect an image-capable provider
//      in Settings → AI" surface in `ActionEditor`.
//
//  Migration scope for the 0.57 ship: file added, with the existing
//  `AIImageAction.ResolvedProvider` nested struct kept as the
//  runtime-internal HTTP-dispatch payload (it carries `apiKey` +
//  `baseURL` that the UI must NOT see). Future refactors fold the
//  image runtime into a thin wrapper around `ProviderResolver`
//  + an `APIKeyStorage.load` for the secret half. The four UI
//  consumers migrate one at a time.
//

import Foundation

// MARK: - Public types

/// What an action wants to do — drives the eligibility filter inside
/// the resolver. Mirrors the three AI action kinds shipped today.
enum AIOperationKind: String, Equatable {
    case text         // text-in / text-out (AIAction)
    case imageEdit    // image-in / image-out (AIImageAction)
    case textToImage  // text-in / image-out (AITextToImageAction)
}

/// "What the UI should label this action with right now." Returned
/// by the resolver. NEVER carries the API key — that stays in
/// `APIKeyStorage` and the runtime-only nested struct in
/// `AIImageAction.swift`.
struct ResolvedAIProvider: Equatable {

    /// The configured provider's stable identifier.
    let providerID: String
    /// User-visible name for badges / chips ("OpenAI", "Anthropic",
    /// "OpenRouter — gpt-5").
    let providerLabel: String
    /// Provider family — drives the icon lookup.
    let providerKind: ProviderKind
    /// User-visible model identifier ("claude-sonnet-4.5",
    /// "gpt-image-1", "models/gemini-2.5-flash-image").
    let modelLabel: String
    /// Which operation the resolver was asked about — encoded so the
    /// caller can sanity-check it survived the recursion.
    let capabilityUsed: AIOperationKind
    /// True when the resolved provider differs from the action's
    /// nominal pick (per-action `providerID`, or registry default if
    /// the action follows default). Tells the UI to render the
    /// "auto-fallback to: …" notice.
    let isRerouted: Bool
    /// Human-readable explanation for the reroute. Nil when
    /// `isRerouted` is false. Examples:
    ///   - "Anthropic doesn't support image edits"
    ///   - "Default provider has no API key"
    let rerouteReason: String?
    /// Optional suggestion the UI can surface for the user to fix
    /// the underlying issue. Nil when no recovery makes sense.
    let recoveryHint: String?
}

// MARK: - Resolver

enum ProviderResolver {

    /// Resolve which provider would actually execute the given
    /// action right now. Pure function — depends only on the
    /// supplied `ProvidersConfig` and a callback that checks whether
    /// a given provider has a stored API key. Returns nil when no
    /// provider can serve the requested capability.
    ///
    /// - Parameters:
    ///   - nominalProviderID: the action's `providerID` field. When
    ///     empty / nil the resolver follows the registry default.
    ///   - operationKind: `.text`, `.imageEdit`, or `.textToImage`.
    ///   - config: the live `ProvidersConfig` snapshot.
    ///   - hasKey: closure returning true when `APIKeyStorage` has a
    ///     non-empty key for the given provider ID. Injected so the
    ///     resolver stays pure and testable (tests pass a fake
    ///     dictionary; runtime passes `APIKeyStorage.load`).
    static func resolve(
        nominalProviderID: String?,
        operationKind: AIOperationKind,
        config: ProvidersConfig,
        hasKey: (String) -> Bool
    ) -> ResolvedAIProvider? {

        // 1. Try the explicit per-action provider.
        if let id = nominalProviderID, !id.isEmpty,
           let cp = config.providers.first(where: { $0.id == id }),
           cp.enabled,
           Self.capabilityMatches(cp.kind, operationKind),
           hasKey(cp.id) {
            return Self.makeResolved(from: cp,
                                     operationKind: operationKind,
                                     isRerouted: false,
                                     rerouteReason: nil,
                                     recoveryHint: nil)
        }

        // Capture why the nominal pick was rejected so we can label
        // the reroute meaningfully if a fallback fires below.
        var nominalRejection: String? = nil
        if let id = nominalProviderID, !id.isEmpty {
            if let cp = config.providers.first(where: { $0.id == id }) {
                if !cp.enabled {
                    nominalRejection = "\(cp.displayName) is disabled"
                } else if !Self.capabilityMatches(cp.kind, operationKind) {
                    nominalRejection = Self.capabilityMismatchReason(cp.displayName, operationKind)
                } else if !hasKey(cp.id) {
                    nominalRejection = "\(cp.displayName) has no API key"
                }
            } else {
                nominalRejection = "Configured provider \(id) is missing"
            }
        }

        // 2. Try the registry default — but only when the nominal was
        //    empty/follow-default OR when the nominal failed.
        if let defaultID = config.defaultProviderID, !defaultID.isEmpty,
           let cp = config.providers.first(where: { $0.id == defaultID }),
           cp.enabled,
           Self.capabilityMatches(cp.kind, operationKind),
           hasKey(cp.id) {
            let nominalFollowedDefault = (nominalProviderID ?? "").isEmpty
            let isRerouted = !nominalFollowedDefault
            return Self.makeResolved(from: cp,
                                     operationKind: operationKind,
                                     isRerouted: isRerouted,
                                     rerouteReason: isRerouted ? nominalRejection : nil,
                                     recoveryHint: nil)
        }

        // 3. Cost-ranked soft fallback for image-edit operations.
        //    Same chain `AIImageAction.resolveProvider` uses.
        if operationKind == .imageEdit || operationKind == .textToImage {
            let ranked = config.providers
                .filter { $0.enabled && $0.kind.supportsImageEdit }
                .sorted { $0.kind.imageEditCostRank < $1.kind.imageEditCostRank }
            for cp in ranked where hasKey(cp.id) {
                let reason = nominalRejection ?? "Falling back to the cheapest image-capable provider"
                return Self.makeResolved(from: cp,
                                         operationKind: operationKind,
                                         isRerouted: true,
                                         rerouteReason: reason,
                                         recoveryHint: nil)
            }
            // Nothing image-capable with a key.
            return nil
        }

        // 4. Text-only fallback — first enabled provider with a key.
        if operationKind == .text {
            for cp in config.providers where cp.enabled && hasKey(cp.id) {
                return Self.makeResolved(from: cp,
                                         operationKind: operationKind,
                                         isRerouted: true,
                                         rerouteReason: nominalRejection ?? "Default provider has no API key",
                                         recoveryHint: "Connect a provider in Settings → AI")
            }
        }

        return nil
    }

    // MARK: Helpers

    /// True when the provider kind can execute the requested
    /// operation. Mirrors the eligibility used at the runtime sites.
    static func capabilityMatches(_ kind: ProviderKind,
                                  _ op: AIOperationKind) -> Bool {
        switch op {
        case .text:                      return true              // every kind talks text
        case .imageEdit, .textToImage:   return kind.supportsImageEdit
        }
    }

    private static func capabilityMismatchReason(_ providerName: String,
                                                 _ op: AIOperationKind) -> String {
        switch op {
        case .text:         return "\(providerName) can't execute this action"
        case .imageEdit:    return "\(providerName) doesn't support image edits"
        case .textToImage:  return "\(providerName) doesn't support text → image"
        }
    }

    private static func makeResolved(from cp: ConfiguredProvider,
                                     operationKind: AIOperationKind,
                                     isRerouted: Bool,
                                     rerouteReason: String?,
                                     recoveryHint: String?) -> ResolvedAIProvider {
        ResolvedAIProvider(
            providerID: cp.id,
            providerLabel: cp.displayName,
            providerKind: cp.kind,
            modelLabel: cp.model,
            capabilityUsed: operationKind,
            isRerouted: isRerouted,
            rerouteReason: rerouteReason,
            recoveryHint: recoveryHint
        )
    }
}

// MARK: - Runtime credential adapter

extension ProviderResolver {
    /// Readiness predicate used by UI/runtime wrappers when calling the pure
    /// resolver. Text AI can use local providers and custom no-auth endpoints;
    /// image edit/generation currently requires an API key for every supported
    /// provider kind, matching `AIImageAction.resolveProvider`.
    static func runtimeHasCredential(
        providerID: String,
        operationKind: AIOperationKind,
        config: ProvidersConfig
    ) -> Bool {
        guard let cp = config.providers.first(where: { $0.id == providerID }) else {
            return false
        }
        if operationKind == .text {
            if cp.kind.isLocal { return true }
            if cp.kind == .custom, cp.baseURL?.isEmpty == false { return true }
        }
        return APIKeyStorage.load(for: providerID)?.isEmpty == false
    }
}
