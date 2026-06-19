//
//  UsageProbe.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Per-provider live usage probes — hit each provider's billing API
//  for "today's" cost / request count / token count and surface it
//  in the Settings → AI provider row so the user sees actual spend
//  next to the brand they're paying. Each provider has its own
//  endpoint shape and auth model:
//
//   • OpenAI   /v1/organization/costs — nominally wants an
//     Organization-scope `sk-admin-…` key, but we send the regular
//     inference key here too. If the user's key lacks that scope
//     the call 401s and the row reads "Unauthorized — check key";
//     users who have a billing-scope key can put it in the API
//     Key field directly. One key per provider, no extra UI.
//   • OpenRouter  /api/v1/credits — uses the same key as inference;
//     returns lifetime credit usage. Lifetime is the best we can do
//     (no per-day bucket API); we cache the previous read locally
//     and report the delta as "today's usage".
//   • Anthropic / Gemini / others — no public usage API today.
//     `probe(for:)` returns nil and the Settings row hides the
//     usage line for those rows.
//
//  Everything here is async + throwing; the caller catches errors
//  silently and shows a "—" line so a transient network blip
//  doesn't paint the row red. Real failures (bad key, wrong endpoint)
//  surface as a small inline error string in the snapshot.
//

import Foundation
import CryptoKit   // #A56 — SHA256 anchor fingerprint
import IOKit       // #A56 — IOPlatformUUID for machine-switch detection

// MARK: - Snapshot

/// A single point-in-time usage reading for one provider.
struct UsageSnapshot: Equatable {
    /// Total cost spent today, in USD.
    var costUSD: Double
    /// Total HTTP request count today.
    var requestCount: Int
    /// Total token count today (input + output combined; we don't
    /// split them in the row because the user cares about the
    /// magnitude, not the breakdown).
    var tokenCount: Int
    /// Wall-clock moment this reading was taken. The Settings row
    /// shows "updated 3s ago" so the user knows when the number
    /// last refreshed.
    var fetchedAt: Date
    /// Non-nil for failed reads — surfaces "API key missing" /
    /// "rate-limited" / etc. in place of the numbers.
    var error: String?

    static let empty = UsageSnapshot(costUSD: 0, requestCount: 0,
                                     tokenCount: 0, fetchedAt: .distantPast,
                                     error: nil)
}

// MARK: - Probe protocol

/// One probe per provider kind. `fetchToday` is async + throwing;
/// the registry catches and wraps errors into a snapshot with
/// `error` populated so the caller doesn't have to.
protocol UsageProbe {
    /// Hit the provider's usage endpoint and return today's
    /// cost / requests / tokens.
    ///
    /// - parameter provider: registry entry — the probe uses `id`
    ///   to look up API keys (regular and admin) from
    ///   `APIKeyStorage`, and `baseURL` when the provider allows
    ///   self-hosted endpoints.
    func fetchToday(provider: ConfiguredProvider) async throws -> UsageSnapshot
}

// MARK: - Registry

/// Maps `ProviderKind` to its probe implementation. Returns nil for
/// kinds that have no public usage API; the Settings row checks
/// this and hides the usage line accordingly.
enum UsageProbeRegistry {
    static func probe(for kind: ProviderKind) -> UsageProbe? {
        switch kind {
        case .openai:     return OpenAIUsageProbe()
        case .openrouter: return OpenRouterUsageProbe()
        case .anthropic, .gemini, .grok, .mistral, .deepseek,
             .together, .cloudflareWorkers, .groq, .cerebras,
             .ollama, .lmstudio, .llamaCpp, .custom:
            return nil
        }
    }
}

// MARK: - OpenAI

/// Hits `GET /v1/organization/costs?start_time=<midnight-local>&bucket_width=1d`
/// with the provider's regular inference key. **`start_time` is the
/// Unix-epoch seconds for the user's local-time midnight, not UTC
/// midnight** — the OpenAI endpoint accepts any Unix timestamp and
/// returns aggregated costs since that point, so anchoring the bucket
/// at the user's local calendar day is the more intuitive default
/// ("today" matches the user's wall clock, not their region offset
/// from UTC). Earlier the comment claimed UTC; the code never matched
/// that claim, and the user-facing label "Today: $0.042" reads as
/// local-day anyway. The endpoint nominally wants an
/// Organization-scope key (`sk-admin-…`); a regular `sk-…` key returns
/// 401 and the row surfaces "Unauthorized — check key" so the user
/// knows the inference key doesn't have billing scope. We deliberately don't ask for a
/// second key in the UI — one key per provider is enough; users
/// who have a billing-scope key can put THAT in the API Key field
/// and inference still works fine against it.
///
/// OpenAI's usage API doesn't return token counts on the costs
/// endpoint; for tokens we'd hit `/v1/organization/usage/completions`
/// + `/v1/organization/usage/embeddings` separately. We currently
/// surface only cost + request count from costs to keep the call
/// budget at one round-trip per refresh — extending to tokens is
/// a follow-up if users ask.
struct OpenAIUsageProbe: UsageProbe {
    func fetchToday(provider: ConfiguredProvider) async throws -> UsageSnapshot {
        guard let apiKey = APIKeyStorage.load(for: provider.id),
              !apiKey.isEmpty else {
            throw UsageProbeError.missingKey
        }
        // Midnight at the user's LOCAL calendar day; OpenAI's costs
        // API takes Unix seconds and returns USD aggregated since that
        // point. Anchoring on local midnight makes "Today" in the UI
        // mean what the user expects ("since I woke up today"), not
        // what UTC says.
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let startTime = Int(startOfDay.timeIntervalSince1970)
        var comps = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
        comps.queryItems = [
            URLQueryItem(name: "start_time", value: String(startTime)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "line_item")
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response) = try await AIHTTP.session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UsageProbeError.transport("no http response")
        }
        // 401 = key invalid, 403 = key valid but lacks Organization
        // scope (the costs endpoint nominally needs `sk-admin-…`).
        // Either way the user can't fix it from inside DrPaste
        // without supplying a different key — we surface this as
        // `.notSupportedForKey` and the row hides the usage line
        // silently instead of painting a permanent orange error.
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageProbeError.notSupportedForKey
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UsageProbeError.http(http.statusCode, body.prefix(200).description)
        }
        // Response shape (abbreviated):
        // { "data": [ { "results": [ { "amount": { "value": 0.123,
        //   "currency": "usd" }, "line_item": "..." }, ... ] } ] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bucketArr = root["data"] as? [[String: Any]] else {
            throw UsageProbeError.parse("unexpected costs payload")
        }
        var totalUSD: Double = 0
        var lineItems: Int = 0
        for bucket in bucketArr {
            guard let results = bucket["results"] as? [[String: Any]] else { continue }
            for r in results {
                lineItems += 1
                if let amount = r["amount"] as? [String: Any],
                   let value = amount["value"] as? Double {
                    totalUSD += value
                }
            }
        }
        return UsageSnapshot(costUSD: totalUSD,
                             requestCount: lineItems,
                             tokenCount: 0,
                             fetchedAt: Date(),
                             error: nil)
    }
}

// MARK: - OpenRouter

/// Hits `GET /api/v1/credits` and `GET /api/v1/key` for the
/// user's account.  `/credits` returns lifetime `usage` and
/// remaining balance; `/key` returns rate-limit metadata. We pair
/// the lifetime usage reading with the last-known snapshot stored
/// locally and report the delta as "today's usage" — OpenRouter
/// doesn't expose per-bucket history, so this is the best we can
/// do without server-side accounting.
struct OpenRouterUsageProbe: UsageProbe {
    func fetchToday(provider: ConfiguredProvider) async throws -> UsageSnapshot {
        guard let apiKey = APIKeyStorage.load(for: provider.id), !apiKey.isEmpty else {
            throw UsageProbeError.missingKey
        }
        let url = URL(string: "https://openrouter.ai/api/v1/credits")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response) = try await AIHTTP.session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UsageProbeError.transport("no http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageProbeError.notSupportedForKey
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UsageProbeError.http(http.statusCode, body.prefix(200).description)
        }
        // Response shape:
        // { "data": { "total_credits": 5.0, "total_usage": 1.234 } }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let lifetimeUsage = (payload["total_usage"] as? NSNumber)?.doubleValue
        else {
            throw UsageProbeError.parse("unexpected credits payload")
        }
        // Compute today's delta from a locally-persisted anchor.
        // OpenRouter exposes only the LIFETIME total_usage value
        // on /credits — to surface "today's spend" we cache the
        // reading at first-fetch-of-the-day as an anchor and
        // report `current − anchor` on subsequent reads.
        let todayUSD = computeTodayDelta(providerID: provider.id,
                                         lifetimeUsage: lifetimeUsage,
                                         apiKey: apiKey)
        return UsageSnapshot(costUSD: todayUSD,
                             requestCount: 0,
                             tokenCount: 0,
                             fetchedAt: Date(),
                             error: nil)
    }

    /// Anchor-management for the OpenRouter "today" delta. Three
    /// resets, in priority order:
    ///
    ///   1. **New day** — `anchorDate < startOfDay(now)`. Expected
    ///      daily rollover. Reset anchor to current lifetime, today =
    ///      0 (we lose pre-launch in-day usage but recover from now).
    ///
    ///   2. **Backwards jump** — `lifetimeUsage < anchorUSD`. The
    ///      lifetime counter can only grow under normal operation;
    ///      a smaller reading means OpenRouter reset the account
    ///      (extremely rare), the user re-keyed to a different
    ///      account (common — pasting a coworker's key into the same
    ///      provider slot), or our anchor was corrupted. Reset.
    ///
    ///   3. **Implausible jump** — current is huge compared to the
    ///      anchor (`current − anchor > $50` in a single tick). The
    ///      user almost certainly switched machines: an anchor from
    ///      machine A doesn't capture what they spent on machine B,
    ///      so the delta is fake. Reset to current and surface a
    ///      fresh "today = 0" until the local machine has its own
    ///      history. $50 chosen empirically — heavy real usage in
    ///      one session rarely exceeds a few dollars, while a
    ///      machine-switch easily looks like tens-to-hundreds of
    ///      dollars of "growth" since the stale anchor.
    private func computeTodayDelta(providerID: String,
                                    lifetimeUsage: Double,
                                    apiKey: String) -> Double {
        let defaults = UserDefaults.standard
        let cal = Calendar(identifier: .gregorian)
        let startOfDay = cal.startOfDay(for: Date())
        let now = Date()
        let storedAnchor = OpenRouterAnchor.load(providerID: providerID,
                                                 defaults: defaults)
        // Re-key detection now goes through the SHA-256 fingerprint of
        // the API key (#A56) instead of relying solely on "lifetime
        // went backwards" — a re-key to a different account that
        // happens to have higher lifetime usage was undetectable
        // under the legacy logic.
        let currentFingerprint = OpenRouterAnchor.fingerprint(forKey: apiKey)
        // Machine-switch detection (#A56). The machineUUID is the
        // hardware UUID of the boot drive — same across reboots,
        // different across machines. A mismatch means an exported /
        // synced anchor moved to a new host; reset cleanly.
        let currentMachineUUID = OpenRouterAnchor.currentMachineUUID()

        let needsReset: Bool = {
            guard let anchor = storedAnchor else { return true }
            // 1. Stored from a previous day → daily rollover.
            if anchor.date < startOfDay { return true }
            // 2. Lifetime went backwards.
            if lifetimeUsage < anchor.credits { return true }
            // 3. API key changed → user re-keyed; old anchor belongs
            //    to a different OpenRouter account.
            if anchor.keyFingerprint != currentFingerprint { return true }
            // 4. Machine UUID changed → anchor moved to a different
            //    host (config import / iCloud sync). Local "today"
            //    counter starts fresh.
            if anchor.machineUUID != currentMachineUUID { return true }
            // 5. Implausibly large jump (extended offline activity on
            //    a parallel install hitting the same key).
            if lifetimeUsage - anchor.credits > 50.0 { return true }
            return false
        }()

        if needsReset {
            let fresh = OpenRouterAnchor(providerID: providerID,
                                         date: startOfDay,
                                         credits: lifetimeUsage,
                                         machineUUID: currentMachineUUID,
                                         keyFingerprint: currentFingerprint,
                                         updatedAt: now)
            fresh.save(defaults: defaults)
            return 0
        }
        return max(0, lifetimeUsage - (storedAnchor?.credits ?? 0))
    }
}

// MARK: - OpenRouter anchor (#A56)

/// Codable per-provider anchor for the OpenRouter "today" delta
/// computation. Replaces the legacy split-double pair
/// (`anchorUSD` + `anchorDate`) with one JSON blob that also carries
/// the machine UUID + key fingerprint, so re-key and machine-switch
/// detection can happen explicitly instead of relying on
/// "lifetime went backwards" heuristics.
///
/// Storage: one key per providerID,
/// `drpaste.usage.openrouter.<providerID>.anchor.v2`, JSON-encoded.
/// Legacy double keys are migrated on first load and then deleted.
struct OpenRouterAnchor: Codable {
    let providerID: String
    let date: Date          // start-of-day when the anchor was set
    let credits: Double     // lifetime usage at anchor time, USD
    let machineUUID: String // hardware UUID of the boot drive
    let keyFingerprint: String // SHA-256 of the API key (hex, short)
    let updatedAt: Date     // last save — useful for diagnostics

    static func key(providerID: String) -> String {
        "drpaste.usage.openrouter.\(providerID).anchor.v2"
    }

    /// Legacy keys used by the pre-#A56 split-double storage. Read
    /// once during migration, then deleted so we don't pay the
    /// migration cost on every load.
    private static func legacyKeyUSD(providerID: String) -> String {
        "drpaste.usage.openrouter.\(providerID).anchorUSD"
    }
    private static func legacyKeyDate(providerID: String) -> String {
        "drpaste.usage.openrouter.\(providerID).anchorDate"
    }

    static func load(providerID: String,
                     defaults: UserDefaults = .standard) -> OpenRouterAnchor? {
        // 1. Try the v2 (Codable) layout.
        if let data = defaults.data(forKey: key(providerID: providerID)),
           let decoded = try? JSONDecoder().decode(OpenRouterAnchor.self, from: data) {
            return decoded
        }
        // 2. Fall back to legacy doubles. Build a partial anchor and
        //    let the caller decide whether to reset — this is mostly
        //    useful for the "lifetime backwards" check to keep
        //    behaving sensibly during the upgrade window.
        let legacyUSD = defaults.double(forKey: legacyKeyUSD(providerID: providerID))
        let legacyDateTS = defaults.double(forKey: legacyKeyDate(providerID: providerID))
        guard legacyUSD > 0 || legacyDateTS > 0 else { return nil }
        // Migrate inline: build a v2 record from the legacy fields +
        // current machine UUID + a placeholder fingerprint that will
        // mismatch any real key, forcing a clean reset on the next
        // delta compute. Saves the v2 record, removes the legacy
        // keys — one-time cost per provider.
        let migrated = OpenRouterAnchor(
            providerID: providerID,
            date: Date(timeIntervalSince1970: legacyDateTS),
            credits: legacyUSD,
            machineUUID: currentMachineUUID(),
            keyFingerprint: "",
            updatedAt: Date()
        )
        migrated.save(defaults: defaults)
        defaults.removeObject(forKey: legacyKeyUSD(providerID: providerID))
        defaults.removeObject(forKey: legacyKeyDate(providerID: providerID))
        return migrated
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(providerID: providerID))
    }

    /// Hardware UUID of the host's boot drive — reasonably stable
    /// across reboots, deterministic per-machine. Used to detect
    /// "the user moved DrPaste config to a different Mac" so we
    /// reset the local-today counter to 0 rather than reporting a
    /// fake delta from the imported anchor.
    ///
    /// Reads `IOPlatformUUID` from `IOPlatformExpertDevice` via the
    /// canonical IOKit recipe. Cached after the first call —
    /// hardware UUID can't change without a reboot.
    private static var cachedMachineUUID: String?
    static func currentMachineUUID() -> String {
        if let cached = cachedMachineUUID { return cached }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else {
            cachedMachineUUID = "unknown"
            return "unknown"
        }
        defer { IOObjectRelease(service) }
        let cfString = IORegistryEntryCreateCFProperty(
            service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String
        let resolved = cfString ?? "unknown"
        cachedMachineUUID = resolved
        return resolved
    }

    /// Stable short fingerprint of an API key — SHA-256 first 12 hex
    /// chars. Long enough to make collisions astronomically unlikely
    /// for the small number of keys a single user holds, short
    /// enough that the persisted JSON stays compact.
    static func fingerprint(forKey key: String) -> String {
        guard !key.isEmpty else { return "" }
        let data = Data(key.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum UsageProbeError: LocalizedError {
    case missingKey
    /// 401/403 from a usage endpoint. The user's API key works for
    /// inference but lacks the org/billing scope this endpoint
    /// requires. We can't fix this from inside DrPaste (we
    /// deliberately don't ask for a second admin key) — the row
    /// hides the usage line silently rather than painting a
    /// permanent error.
    case notSupportedForKey
    case transport(String)
    case http(Int, String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:        return "API key missing"
        case .notSupportedForKey: return "Usage not available for this key"
        case .transport(let s):  return "Network: \(s)"
        case .http(let code, _): return "HTTP \(code)"
        case .parse(let s):      return "Parse: \(s)"
        }
    }
}
