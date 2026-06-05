//
//  AIHTTP.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Shared URLSession for non-streaming AI calls (provider test,
//  usage probe, image download, image generate). Streaming AI paths
//  (AIProvider.stream) keep their own session with longer resource
//  timeouts to support multi-minute SSE flows.
//
//  Why this exists:
//
//  `URLSession.shared` has the system-default 60 s request timeout
//  and no explicit resource timeout. That's fine for casual web
//  fetches but produces visible UX problems for AI calls:
//
//   - Provider connection-test hangs for 60 s before reporting
//     failure when the user typed a wrong URL.
//   - Usage probe blocks Settings → AI rendering for 60 s on
//     network drop.
//   - Image generation download stalls indefinitely if the
//     upstream provider's CDN goes dark mid-transfer.
//
//  This session caps request at 20 s and resource at 60 s — enough
//  for any non-streaming AI call but bounded so failures surface
//  quickly. Custom User-Agent identifies DrPaste in provider logs.
//

import Foundation

enum AIHTTP {

    /// Shared session for non-streaming AI HTTP. Use this instead of
    /// `URLSession.shared` for connection-test, usage probes, image
    /// generation, image download, and any other one-shot AI fetch.
    /// Streaming paths in `AIProvider.swift` keep their own session.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "DrPaste/\(AppBrand.version) (macOS)"
        ]
        return URLSession(configuration: config)
    }()
}
