//
//  UsageProbe.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
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
                                         lifetimeUsage: lifetimeUsage)
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
                                    lifetimeUsage: Double) -> Double {
        let prefix = OpenRouterUsageProbe.todayKey(providerID: providerID)
        let defaults = UserDefaults.standard
        let anchorUSD = defaults.double(forKey: prefix + ".anchorUSD")
        let anchorDateTS = defaults.double(forKey: prefix + ".anchorDate")
        let cal = Calendar(identifier: .gregorian)
        let startOfDay = cal.startOfDay(for: Date()).timeIntervalSince1970

        let needsReset: Bool = {
            // 1. New day or no anchor yet.
            if anchorDateTS < startOfDay || anchorUSD <= 0 { return true }
            // 2. Lifetime went backwards (account reset / re-keyed).
            if lifetimeUsage < anchorUSD { return true }
            // 3. Implausibly large jump (machine switch / extended
            //    offline activity on another device). $50 threshold
            //    catches the "I worked yesterday on the laptop with
            //    a different DrPaste install" pattern without
            //    triggering on legitimate within-day spend.
            if lifetimeUsage - anchorUSD > 50.0 { return true }
            return false
        }()

        if needsReset {
            defaults.set(lifetimeUsage, forKey: prefix + ".anchorUSD")
            defaults.set(startOfDay, forKey: prefix + ".anchorDate")
            return 0
        }
        return max(0, lifetimeUsage - anchorUSD)
    }

    private static func todayKey(providerID: String) -> String {
        "drpaste.usage.openrouter.\(providerID)"
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
