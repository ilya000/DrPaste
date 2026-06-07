//
//  AIImageActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  AI image-to-image transformations. Same shape as AIAction (text):
//  prompt + provider + applicability, materialised from a
//  CustomAIDescriptor with kind == .image, so users can edit the
//  prompt, switch provider, rename, disable, or clone any seeded
//  style into their own ("Stained glass", "Oil painting", …) via
//  Settings → Actions → AI without touching the source code.
//
//  Image generation routes through OpenAI's /v1/images/edits endpoint
//  (model: gpt-image-1) when the resolved provider's kind == .openai.
//  Other provider kinds fail with a clear "switch to OpenAI for image
//  actions" message in the HUD preview pane. Future expansion (BACKLOG
//  #0.32.0): per-kind routing — Gemini 2.5 Flash Image, Replicate's
//  Flux/SDXL via OpenRouter multimodal. The action shape itself is
//  provider-agnostic; only `AIImageHTTP.runEdit` needs to grow when
//  we wire additional providers.
//

import Foundation
import AppKit

// MARK: - AIImageAction

/// Image-in → image-out AI action. Materialised from a
/// `CustomAIDescriptor` with `kind == .image` by
/// `ActionRegistry.rebuildCustomAI`. Constructor mirrors `AIAction`'s
/// shape (id, title, promptTemplate, providerID) so the Settings
/// editor's existing AI form covers both the text and image cases
/// without per-kind branching in the UI layer.
///
/// `isLocal == false` puts this on the same code path as text
/// AIActions in `main.swift / refreshPreview`: the HUD shows the
/// in-flight panel (provider · model · elapsed) and `aiStreamingTask`
/// drives cancellation. The image API doesn't stream incremental
/// tokens (single HTTP POST with a single base64 PNG in response),
/// so `applyStreaming` falls back to `apply` — the only "stream"
/// the user sees is the elapsed counter ticking up.
struct AIImageAction: ClipboardAction {
    let id: String
    let title: String
    let isLocal: Bool = false
    let promptTemplate: String
    /// nil means "follow the user's default AI provider", same convention
    /// as AIAction. The descriptor stores empty-string for this case;
    /// ActionRegistry maps "" → nil at materialisation time.
    let providerID: String?

    init(id: String, title: String, promptTemplate: String, providerID: String? = nil) {
        self.id = id
        self.title = title
        self.promptTemplate = promptTemplate
        self.providerID = providerID
    }

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Same applicability gate as the local image filters — pure
        // image clips plus rich-text clips that carry an embedded
        // image. The latter case will use the embedded image as the
        // edit base.
        context.contains(.image) || RichTextImageExtractor.hasEmbeddedImage(item)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Resolve provider on the main actor — mirrors the
        // AIAction.resolveProvider pattern exactly.
        let resolved: ResolvedProvider? = await MainActor.run { resolveProvider() }
        guard let resolved = resolved else {
            return .failed(
                original: item,
                reason: "AI image styles need an image-capable provider " +
                        "(OpenAI, Google Gemini, or OpenRouter with an " +
                        "image-capable model). Open Settings → AI Providers, " +
                        "add a key for one of them, and either pick it as " +
                        "default OR set this action's provider directly.",
                recovery: .openProvidersConfig
            )
        }
        // Pull the source PNG (file I/O — off the main actor).
        let sourcePNG: Data? = await Task.detached(priority: .userInitiated) {
            return AIImageHTTP.sourcePNG(for: item)
        }.value
        guard let sourcePNG = sourcePNG else {
            return .failed(
                original: item,
                reason: "Couldn't read the source image.",
                recovery: nil
            )
        }
        // Preflight (#A55): cap source size at 4 MB and auto-resize
        // when above. Most image-edit endpoints reject larger uploads,
        // so a direct-trigger AI image hotkey on a large screenshot
        // would previously fail with no recovery. Now: if > 4 MB,
        // downscale longer side to 2048 px and re-encode PNG. If still
        // too large, fall through to the explicit failure (extremely
        // dense content over 2048 px is rare). Off-main because PNG
        // encode is CPU-bound and the source can be 10+ MB.
        let preflightLimit = 4 * 1024 * 1024
        var uploadPNG = sourcePNG
        var wasResized = false
        if sourcePNG.count > preflightLimit {
            let resized = await Task.detached(priority: .userInitiated) {
                return AIImageHTTP.downscaleToFit(sourcePNG: sourcePNG,
                                                  maxLongSide: 2048)
            }.value
            if let resized = resized, resized.count < sourcePNG.count {
                uploadPNG = resized
                wasResized = true
            }
        }
        guard uploadPNG.count <= preflightLimit else {
            return .failed(
                original: item,
                reason: "Image is \(uploadPNG.count / 1024 / 1024) MB even after auto-resize. " +
                        "Try ‘Compress JPEG’ or a sharper resize first.",
                recovery: nil
            )
        }
        if wasResized {
            NSLog("DrPaste: AI image preflight resized %d MB → %d KB (longer side 2048)",
                  sourcePNG.count / 1024 / 1024, uploadPNG.count / 1024)
        }
        let sourcePNGFinal = uploadPNG
        do {
            let resultPNG = try await AIImageHTTP.runEdit(
                sourcePNG: sourcePNGFinal,
                prompt: promptTemplate,
                resolved: resolved
            )
            let saved = await MainActor.run {
                AIImageHTTP.persist(pngData: resultPNG, sourceItem: item)
            }
            guard let saved = saved else {
                return .failed(
                    original: item,
                    reason: "Couldn't save the AI image to history.",
                    recovery: nil
                )
            }
            return .preview(saved)
        } catch let AIProviderError.http(status, body) {
            // Surface the provider's actual error body — image-edit
            // failures are usually descriptive
            // ("content_policy_violation", "invalid image format",
            // "model not found", etc.) and the user needs to see
            // them to fix.
            let trimmed = body.prefix(200)
            return .failed(
                original: item,
                reason: "\(resolved.providerLabel) image edit failed (HTTP \(status)): \(trimmed)",
                recovery: .openProvidersConfig
            )
        } catch AIProviderError.networkUnreachable {
            return .failed(
                original: item,
                reason: "Network unreachable. Check that \(resolved.providerLabel) is reachable.",
                recovery: nil
            )
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            // User navigated away. Caller's previewToken guard drops
            // this result anyway. Stay on the .preview path so the
            // return type doesn't flag a half-completed call.
            return .preview(item)
        } catch is CancellationError {
            return .preview(item)
        } catch {
            return .failed(
                original: item,
                reason: "\(resolved.providerLabel) image edit error: \(error.localizedDescription)",
                recovery: nil
            )
        }
    }

    // MARK: - Helpers

    /// Resolved provider details — API key, kind (drives the HTTP
    /// dispatch in `AIImageHTTP.runEdit`), human-readable label, and
    /// the model string the user picked. Three kinds supported today:
    /// .openai, .gemini, .openrouter (see ProviderKind.supportsImageEdit
    /// for the rationale).
    struct ResolvedProvider {
        let kind: ProviderKind
        let apiKey: String
        let providerLabel: String
        let model: String
        let baseURL: String?
    }

    /// Pick the provider this action should use. Priority:
    /// 1. `providerID` is set → use that provider explicitly.
    /// 2. `providerID == nil` → use the registry's defaultProvider.
    /// The resolved provider must support image edits — see
    /// `ProviderKind.supportsImageEdit`. If the default doesn't,
    /// we look for any enabled image-capable provider as a soft
    /// fallback so a Claude-default user with OpenAI ALSO configured
    /// still gets working image actions.
    @MainActor
    func resolveProvider() -> ResolvedProvider? {
        let registry = AIProviderRegistry.shared
        let cfg = registry.config
        // Explicit per-action providerID wins outright.
        if let id = providerID, !id.isEmpty,
           let cp = cfg.providers.first(where: { $0.id == id }),
           cp.enabled, cp.kind.supportsImageEdit,
           let apiKey = APIKeyStorage.load(for: cp.id), !apiKey.isEmpty {
            return ResolvedProvider(kind: cp.kind, apiKey: apiKey,
                                    providerLabel: cp.displayName,
                                    model: cp.model, baseURL: cp.baseURL)
        }
        // Try default provider next.
        if let defaultID = cfg.defaultProviderID, !defaultID.isEmpty,
           let cp = cfg.providers.first(where: { $0.id == defaultID }),
           cp.enabled, cp.kind.supportsImageEdit,
           let apiKey = APIKeyStorage.load(for: cp.id), !apiKey.isEmpty {
            return ResolvedProvider(kind: cp.kind, apiKey: apiKey,
                                    providerLabel: cp.displayName,
                                    model: cp.model, baseURL: cp.baseURL)
        }
        // Soft fallback — cheapest enabled image-capable provider
        // with a key. Beats failing when the user has e.g. Claude as
        // default chat but ALSO has OpenAI configured for occasional
        // image work. We walk providers in cost-rank order (Gemini →
        // OpenRouter → OpenAI → Custom) instead of registry order so
        // a Plus/Free user with multiple keys gets the cheap path
        // by default, and so this matches the UI auto-select
        // exactly (the picker chip in Edit Action surfaces the
        // same provider as runtime).
        let ranked = cfg.providers
            .filter { $0.enabled && $0.kind.supportsImageEdit }
            .sorted { $0.kind.imageEditCostRank < $1.kind.imageEditCostRank }
        for cp in ranked {
            if let apiKey = APIKeyStorage.load(for: cp.id), !apiKey.isEmpty {
                return ResolvedProvider(kind: cp.kind, apiKey: apiKey,
                                        providerLabel: cp.displayName,
                                        model: cp.model, baseURL: cp.baseURL)
            }
        }
        return nil
    }
}

// MARK: - AITextToImageAction (text → image)

/// Text-in / image-out AI action. Takes clipboard text content
/// (any kind — plain text, markdown, JSON, etc.) and treats the
/// concatenation of the user's prompt template + the clipboard
/// text as the description for a fresh image generation. The
/// source image isn't required (unlike `AIImageAction`); the
/// model invents the picture from prose.
///
/// Three backends dispatched by `AIImageHTTP.runGenerate`:
/// OpenAI `/v1/images/generations`, Gemini `:generateContent`
/// with text-only input, OpenRouter chat completions with a
/// text-only multimodal request. Same `supportsImageEdit` flag
/// governs which providers can run this — image-generation
/// providers are a superset of image-edit providers in practice,
/// but for simplicity we treat them as the same capability tier.
struct AITextToImageAction: ClipboardAction {
    let id: String
    let title: String
    let isLocal: Bool = false
    let promptTemplate: String
    let providerID: String?

    init(id: String, title: String, promptTemplate: String, providerID: String? = nil) {
        self.id = id
        self.title = title
        self.promptTemplate = promptTemplate
        self.providerID = providerID
    }

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Any text-bearing clip works as input — plain text, rich
        // text (stripped to `previewText`), URL, JSON, etc. The
        // prompt blends with this text to describe what to draw.
        switch item.semantic {
        case .text, .richText, .url, .email,
             .json, .code, .markdown, .table:
            return true
        case .image, .pdf, .files, .unknown:
            return false
        }
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let resolved: AIImageAction.ResolvedProvider? = await MainActor.run {
            // Re-use AIImageAction.resolveProvider via a transient
            // peer — same provider-resolution rules (per-action
            // override → default → any image-capable fallback).
            let peer = AIImageAction(id: id, title: title,
                                      promptTemplate: promptTemplate,
                                      providerID: providerID)
            return peer.resolveProvider()
        }
        guard let resolved = resolved else {
            return .failed(
                original: item,
                reason: "AI image generation needs an image-capable provider " +
                        "(OpenAI, Google Gemini, OpenRouter, or a custom OpenAI-" +
                        "compatible endpoint). Open Settings → AI Providers, add " +
                        "a key, and either pick it as default OR set this action's " +
                        "provider directly.",
                recovery: .openProvidersConfig
            )
        }
        // Blend the user's prompt template with the clipboard text.
        // Pattern: "<prompt>\n\n<clipboard text>". The model treats
        // the whole thing as the image description. If the user
        // wrote a self-contained prompt with no `{input}` slot,
        // the clipboard text still adds context at the end —
        // usually a reasonable fallback.
        let clipboardText = item.previewText ?? ""
        let fullPrompt: String
        if promptTemplate.contains("{input}") {
            fullPrompt = promptTemplate.replacingOccurrences(of: "{input}", with: clipboardText)
        } else if clipboardText.isEmpty {
            fullPrompt = promptTemplate
        } else {
            fullPrompt = promptTemplate + "\n\n" + clipboardText
        }
        do {
            let resultPNG = try await AIImageHTTP.runGenerate(
                prompt: fullPrompt,
                resolved: resolved
            )
            let saved = await MainActor.run {
                AIImageHTTP.persist(pngData: resultPNG, sourceItem: item)
            }
            guard let saved = saved else {
                return .failed(original: item,
                              reason: "Couldn't save the generated image to history.",
                              recovery: nil)
            }
            return .preview(saved)
        } catch let AIProviderError.http(status, body) {
            let trimmed = body.prefix(200)
            return .failed(original: item,
                          reason: "\(resolved.providerLabel) image generation failed (HTTP \(status)): \(trimmed)",
                          recovery: .openProvidersConfig)
        } catch AIProviderError.networkUnreachable {
            return .failed(original: item,
                          reason: "Network unreachable. Check that \(resolved.providerLabel) is reachable.",
                          recovery: nil)
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return .preview(item)
        } catch is CancellationError {
            return .preview(item)
        } catch {
            return .failed(original: item,
                          reason: "\(resolved.providerLabel) image generation error: \(error.localizedDescription)",
                          recovery: nil)
        }
    }
}

// MARK: - HTTP plumbing

/// Static helpers that perform the actual OpenAI `images/edits` POST
/// plus on-disk persistence of the result. Pulled out of `AIImageAction`
/// so the action stays read-only / value-typed and the HTTP code can
/// be unit-tested in isolation if needed.
enum AIImageHTTP {

    /// Preflight downscale (#A55) — used by AIImageAction when the
    /// source PNG exceeds the provider's image-edit cap. Re-encodes
    /// PNG at a new pixel size with the longer side capped at
    /// `maxLongSide`. Returns nil if the source can't be decoded;
    /// callers fall back to the original failure path in that case.
    /// Pure function; safe to call off-main.
    static func downscaleToFit(sourcePNG: Data, maxLongSide: Int) -> Data? {
        guard let image = NSImage(data: sourcePNG),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let srcW = cg.width
        let srcH = cg.height
        let longer = max(srcW, srcH)
        guard longer > maxLongSide else { return sourcePNG }
        let scale = Double(maxLongSide) / Double(longer)
        let dstW = max(1, Int(Double(srcW) * scale))
        let dstH = max(1, Int(Double(srcH) * scale))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: dstW, height: dstH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let resized = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: resized)
        return rep.representation(using: .png, properties: [:])
    }

    /// Load the source PNG bytes for `item`, in priority order:
    /// 1. Raw full-resolution representations the watcher captured (public.png
    ///    / .tiff / .jpeg / .heic — re-encoded to PNG if needed).
    /// 2. First embedded image from a rich-text attachment (original bytes).
    /// 3. The preview thumbnail — LAST resort only.
    ///
    /// Codex regression — this used to read `previewImageRel` FIRST. But that's
    /// a downscaled ≤600 pt thumbnail (PreviewSynthesizer.imageRelative), not
    /// "highest quality" as the old comment claimed, so AI edits (watercolor /
    /// sketch / cartoon) ran on a 600 px thumbnail of a 5K screenshot and
    /// produced low-resolution output. Same lesson as #A48 for local image
    /// actions: operate on the ORIGINAL bytes.
    static func sourcePNG(for item: ClipboardItem) -> Data? {
        for type in ["public.png", "public.tiff", "public.jpeg", "public.heic"] {
            if let rel = item.representations[type],
               let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)) {
                return reEncodeToPNG(data)
            }
        }
        if item.semantic == .richText,
           let img = RichTextImageExtractor.firstImage(in: item),
           let tiff = img.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            return png
        }
        if let rel = item.previewImageRel,
           let data = try? Data(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel)) {
            return reEncodeToPNG(data)
        }
        return nil
    }

    /// Decode + re-encode to PNG. OpenAI accepts PNG for image edits;
    /// other formats trip the endpoint's "invalid image" check even
    /// when the bytes are valid JPEG / HEIC. Re-encoding is cheap
    /// (handful of ms) and removes a class of mysterious 400s.
    private static func reEncodeToPNG(_ data: Data) -> Data? {
        // PNG fast-path — if the bytes are already PNG (header
        // `89 50 4E 47`), pass them through. Saves a round-trip when
        // the source is already in the target format.
        if data.count > 8,
           data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 {
            return data
        }
        if let img = NSImage(data: data),
           let tiff = img.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }

    /// Issue an image-edit request against the resolved provider and
    /// return the PNG bytes. Dispatches on provider kind — each
    /// backend has its own URL shape, auth header, body format, and
    /// response parser. Throws `AIProviderError` on HTTP / network /
    /// decode failures so the action's catch arms can map them to
    /// friendly `ApplyOutcome.failed` reasons.
    ///
    /// All backends share the same timeout budget (90 s) and the
    /// same error taxonomy so the caller's catch arms are uniform.
    static func runEdit(sourcePNG: Data,
                        prompt: String,
                        resolved: AIImageAction.ResolvedProvider) async throws -> Data {
        switch resolved.kind {
        case .openai:
            return try await runOpenAIEdit(
                sourcePNG: sourcePNG, prompt: prompt,
                apiKey: resolved.apiKey,
                baseURL: "https://api.openai.com/v1"
            )
        case .gemini:
            return try await runGeminiEdit(
                sourcePNG: sourcePNG, prompt: prompt,
                apiKey: resolved.apiKey,
                model: resolved.model.isEmpty
                    ? "gemini-2.5-flash-image-preview"
                    : resolved.model
            )
        case .openrouter:
            return try await runOpenRouterEdit(
                sourcePNG: sourcePNG, prompt: prompt,
                apiKey: resolved.apiKey,
                model: resolved.model.isEmpty
                    ? "google/gemini-2.5-flash-image-preview"
                    : resolved.model
            )
        case .custom:
            // Custom = OpenAI-compatible endpoint at a user-supplied
            // baseURL. We optimistically dispatch the OpenAI-shape
            // /images/edits call. If the user's endpoint speaks it
            // (e.g. a Replicate proxy, an enterprise self-host),
            // works. If not (text-only LLM proxy, unsupported
            // route), the HTTP failure bubbles up to the action's
            // catch arm with the actual error body — user sees
            // "Custom image edit failed (HTTP 404): ..." and knows
            // to switch providers.
            let base = (resolved.baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !base.isEmpty else {
                throw AIProviderError.decode(
                    "Custom provider has no baseURL configured — set one in Settings → AI."
                )
            }
            return try await runOpenAIEdit(
                sourcePNG: sourcePNG, prompt: prompt,
                apiKey: resolved.apiKey,
                baseURL: base
            )
        default:
            // Should never reach — resolveProvider only returns kinds
            // with supportsImageEdit. Defensive guard if a future
            // provider gets the flag without an HTTP backend.
            throw AIProviderError.decode(
                "Provider kind \(resolved.kind.rawValue) doesn't have an image-edit HTTP backend wired."
            )
        }
    }

    /// Text-to-image generation — no source image, just a prompt.
    /// Dispatched on resolved provider kind, same as `runEdit`.
    /// Used by `AITextToImageAction` (e.g. "AI: Whiteboard sketch").
    static func runGenerate(prompt: String,
                            resolved: AIImageAction.ResolvedProvider) async throws -> Data {
        switch resolved.kind {
        case .openai:
            return try await runOpenAIGenerate(
                prompt: prompt, apiKey: resolved.apiKey,
                baseURL: "https://api.openai.com/v1"
            )
        case .gemini:
            return try await runGeminiGenerate(
                prompt: prompt, apiKey: resolved.apiKey,
                model: resolved.model.isEmpty
                    ? "gemini-2.5-flash-image-preview"
                    : resolved.model
            )
        case .openrouter:
            return try await runOpenRouterGenerate(
                prompt: prompt, apiKey: resolved.apiKey,
                model: resolved.model.isEmpty
                    ? "google/gemini-2.5-flash-image-preview"
                    : resolved.model
            )
        case .custom:
            let base = (resolved.baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !base.isEmpty else {
                throw AIProviderError.decode(
                    "Custom provider has no baseURL configured — set one in Settings → AI."
                )
            }
            return try await runOpenAIGenerate(
                prompt: prompt, apiKey: resolved.apiKey, baseURL: base
            )
        default:
            throw AIProviderError.decode(
                "Provider kind \(resolved.kind.rawValue) doesn't have an image-generate HTTP backend wired."
            )
        }
    }

    /// Pull a `Quality: low|medium|high|auto` directive line out of
    /// the user's prompt template. Returns the cleaned prompt (with
    /// the directive stripped) and the extracted value if present.
    ///
    /// Why this lives in the prompt rather than as a hidden code
    /// constant: the user gets to decide how cheap-vs-pretty each
    /// action is. The seed prompts ship with `Quality: low` (4×
    /// cheaper per gpt-image-1 call) but anyone who wants gallery-
    /// grade output edits the prompt and removes the directive (or
    /// changes it to `Quality: high`) — no setting to hunt for, no
    /// hidden state, the contract is right there in the template
    /// the user is already editing.
    ///
    /// Matches any line of the form `Quality: <value>` (case-
    /// insensitive, surrounding whitespace tolerated). One directive
    /// per prompt; if the user writes several, the LAST one wins
    /// (regex global match keeps semantics predictable — the line
    /// closest to the end is the one we honour). Removed lines
    /// don't leak into the model call, so the prompt the model
    /// sees reads naturally.
    static func extractQualityDirective(from prompt: String) -> (cleaned: String, quality: String?) {
        let pattern = #"(?im)^\s*quality\s*:\s*(low|medium|high|auto)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (prompt, nil)
        }
        let ns = prompt as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: prompt, range: range)
        guard let last = matches.last else { return (prompt, nil) }
        let value = ns.substring(with: last.range(at: 1)).lowercased()
        // Strip ALL Quality: lines (not just the last) so the model
        // doesn't see directive noise. Walk matches in reverse so
        // earlier ranges stay valid after each removal.
        var cleaned = ns
        for m in matches.reversed() {
            cleaned = cleaned.replacingCharacters(in: m.range, with: "") as NSString
        }
        // Collapse any blank lines the removal left behind.
        let collapsed = (cleaned as String)
            .replacingOccurrences(of: #"\n{3,}"#,
                                  with: "\n\n",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (collapsed, value)
    }

    /// OpenAI-shape text-to-image — POST to `<baseURL>/images/generations`.
    /// Body: JSON `{ model, prompt, n, size, [quality] }`. Response
    /// same as edits: `{ data: [ { b64_json } ] }`. Single function
    /// reused for both `.openai` (api.openai.com) and `.custom`
    /// (user-supplied baseURL).
    private static func runOpenAIGenerate(prompt: String,
                                           apiKey: String,
                                           baseURL: String) async throws -> Data {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/images/generations") else {
            throw AIProviderError.decode("Invalid base URL: \(baseURL)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90

        // Pull `Quality: <tier>` directive out of the prompt
        // template so the user controls cost via the same field
        // they edit the prompt in. nil = omit the parameter (let
        // OpenAI default = medium).
        let (cleanedPrompt, qualityFromPrompt) = Self.extractQualityDirective(from: prompt)

        struct GenReq: Encodable {
            let model: String
            let prompt: String
            let n: Int
            let size: String
            /// Per-request tier. gpt-image-1 prices per 1024×1024:
            /// `low` ~$0.011, `medium` ~$0.042, `high` ~$0.167,
            /// `auto` lets OpenAI pick. Sourced from the prompt
            /// `Quality:` line; nil means we omit the field and
            /// take OpenAI's default. gpt-image-1 doesn't accept
            /// 512×512 (DALL-E only); 1024×1024 is the smallest
            /// valid size.
            let quality: String?
        }
        let body = GenReq(model: "gpt-image-1", prompt: cleanedPrompt,
                          n: 1, size: "1024x1024", quality: qualityFromPrompt)
        // JSONEncoder skips nil optionals by default, so a missing
        // Quality: directive cleanly omits the field on the wire.
        req.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await execute(req, providerName: "OpenAI")

        struct Resp: Decodable {
            struct Item: Decodable {
                let b64_json: String?
                let url: String?
            }
            let data: [Item]
        }
        let decoded: Resp
        do {
            decoded = try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw AIProviderError.decode(
                "Couldn't parse OpenAI images/generations response: \(error.localizedDescription)"
            )
        }
        guard let first = decoded.data.first else {
            throw AIProviderError.decode("OpenAI returned no images in response")
        }
        if let b64 = first.b64_json, let bytes = Data(base64Encoded: b64) {
            return bytes
        }
        if let urlStr = first.url, let imgURL = URL(string: urlStr) {
            let (imgData, imgResp) = try await URLSession.shared.data(from: imgURL)
            guard let http = imgResp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AIProviderError.decode("Couldn't fetch generated image from URL")
            }
            return imgData
        }
        throw AIProviderError.decode("OpenAI image had neither b64_json nor url")
    }

    /// Gemini text-to-image — same `:generateContent` endpoint as the
    /// edit path but with a text-only `parts` array (no inlineData
    /// for source image). The model still returns the image as an
    /// inlineData part inside the response candidates.
    private static func runGeminiGenerate(prompt: String,
                                           apiKey: String,
                                           model: String) async throws -> Data {
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlStr) else {
            throw AIProviderError.decode("Invalid Gemini endpoint URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 90

        struct GeminiPart: Encodable {
            let text: String
        }
        struct GeminiContent: Encodable {
            let parts: [GeminiPart]
        }
        struct GeminiReq: Encodable {
            let contents: [GeminiContent]
        }
        let body = GeminiReq(contents: [GeminiContent(parts: [GeminiPart(text: prompt)])])
        req.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await execute(req, providerName: "Gemini")

        // Re-use the same response shape as runGeminiEdit — look
        // for the first inlineData part with mime image/*.
        struct GeminiResp: Decodable {
            struct Candidate: Decodable {
                let content: Content
                struct Content: Decodable {
                    let parts: [Part]
                    struct Part: Decodable {
                        let text: String?
                        let inlineData: InlineData?
                        struct InlineData: Decodable {
                            let mimeType: String
                            let data: String
                        }
                    }
                }
            }
            let candidates: [Candidate]?
        }
        let decoded: GeminiResp
        do {
            decoded = try JSONDecoder().decode(GeminiResp.self, from: data)
        } catch {
            throw AIProviderError.decode(
                "Couldn't parse Gemini generateContent response: \(error.localizedDescription)"
            )
        }
        for cand in decoded.candidates ?? [] {
            for part in cand.content.parts {
                if let inline = part.inlineData,
                   inline.mimeType.hasPrefix("image/"),
                   let bytes = Data(base64Encoded: inline.data) {
                    return bytes
                }
            }
        }
        throw AIProviderError.decode(
            "Gemini returned no image part. Make sure the configured model supports image output (e.g. gemini-2.5-flash-image-preview)."
        )
    }

    /// OpenRouter text-to-image via chat completions — text-only
    /// content array (no source image_url part). Same response-parsing
    /// helpers as the edit path scan for an inline image URL.
    private static func runOpenRouterGenerate(prompt: String,
                                               apiKey: String,
                                               model: String) async throws -> Data {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("https://github.com/ilya000/DrPaste", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("DrPaste", forHTTPHeaderField: "X-Title")
        req.timeoutInterval = 90

        let body: [String: Any] = [
            "model": model,
            "modalities": ["image", "text"],
            "messages": [[
                "role": "user",
                "content": [["type": "text", "text": prompt]]
            ]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await execute(req, providerName: "OpenRouter")

        // Same parsing as runOpenRouterEdit — try the documented
        // `images` array first, fall back to recursive scan for
        // data:image URLs anywhere in the response.
        struct ORResp: Decodable {
            struct Choice: Decodable {
                let message: Message
                struct Message: Decodable {
                    let images: [ImageEntry]?
                    struct ImageEntry: Decodable {
                        let type: String?
                        let image_url: ImageURL?
                        struct ImageURL: Decodable {
                            let url: String?
                        }
                    }
                }
            }
            let choices: [Choice]?
        }
        if let decoded = try? JSONDecoder().decode(ORResp.self, from: data),
           let firstChoice = decoded.choices?.first,
           let images = firstChoice.message.images {
            for entry in images {
                if let urlStr = entry.image_url?.url,
                   let bytes = decodeDataURL(urlStr) {
                    return bytes
                }
            }
        }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let bytes = scanForImageDataURL(in: json) {
            return bytes
        }
        let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
        let snippet = bodyStr.prefix(300)
        throw AIProviderError.decode(
            "OpenRouter returned no image. The configured model may not support image generation. Response: \(snippet)"
        )
    }

    // MARK: - OpenAI gpt-image-1

    /// OpenAI-shape image edit — multipart POST to
    /// `<baseURL>/images/edits` with model `gpt-image-1`. Response:
    /// `{ data: [ { b64_json } ] }`. Same wire format used for both
    /// real OpenAI (baseURL = `https://api.openai.com/v1`) and any
    /// OpenAI-compatible custom endpoint the user has configured
    /// under the `.custom` provider kind.
    private static func runOpenAIEdit(sourcePNG: Data,
                                       prompt: String,
                                       apiKey: String,
                                       baseURL: String) async throws -> Data {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/images/edits") else {
            throw AIProviderError.decode("Invalid base URL: \(baseURL)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let boundary = "----DrPasteImageEdit-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // 90 s timeout — gpt-image-1 typically responds in 8–25 s for a
        // small image; slow regions / large source images push above
        // 30 s. 90 s is the longest tolerable wait before the user
        // assumes the thing is stuck and bails out via the MiniHUD X
        // button.
        req.timeoutInterval = 90

        var body = Data()
        let nl = "\r\n"
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\(nl)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(nl)\(nl)".data(using: .utf8)!)
            body.append("\(value)\(nl)".data(using: .utf8)!)
        }
        // Same `Quality: <tier>` extraction as the generate path —
        // user controls the cost/fidelity tradeoff via a directive
        // line in the prompt template instead of a hidden code
        // constant.
        let (cleanedPrompt, qualityFromPrompt) = Self.extractQualityDirective(from: prompt)
        appendField("model", "gpt-image-1")
        appendField("prompt", cleanedPrompt)
        appendField("n", "1")
        // gpt-image-1 minimum size; 512×512 is DALL-E-only.
        appendField("size", "1024x1024")
        // Quality from the prompt directive if present; otherwise
        // omit the field and take OpenAI's default (medium).
        if let q = qualityFromPrompt {
            appendField("quality", q)
        }

        // Image file part
        body.append("--\(boundary)\(nl)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"source.png\"\(nl)".data(using: .utf8)!)
        body.append("Content-Type: image/png\(nl)\(nl)".data(using: .utf8)!)
        body.append(sourcePNG)
        body.append(nl.data(using: .utf8)!)
        body.append("--\(boundary)--\(nl)".data(using: .utf8)!)

        req.httpBody = body
        let (data, _) = try await execute(req, providerName: "OpenAI")

        struct Resp: Decodable {
            struct Item: Decodable {
                let b64_json: String?
                let url: String?
            }
            let data: [Item]
        }
        let decoded: Resp
        do {
            decoded = try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw AIProviderError.decode(
                "Couldn't parse OpenAI images/edits response: \(error.localizedDescription)"
            )
        }
        guard let first = decoded.data.first else {
            throw AIProviderError.decode("OpenAI returned no images in response")
        }
        if let b64 = first.b64_json, let bytes = Data(base64Encoded: b64) {
            return bytes
        }
        if let urlStr = first.url, let imgURL = URL(string: urlStr) {
            let (imgData, imgResp) = try await URLSession.shared.data(from: imgURL)
            guard let http = imgResp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AIProviderError.decode("Couldn't fetch generated image from URL")
            }
            return imgData
        }
        throw AIProviderError.decode("OpenAI image had neither b64_json nor url")
    }

    // MARK: - Google Gemini 2.5 Flash Image

    /// Gemini native image edit — POST to
    /// `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
    /// with header `x-goog-api-key`. Body uses the standard
    /// multimodal `contents.parts` array: one text part (the prompt)
    /// + one `inlineData` part (base64-encoded source PNG, mimeType
    /// `image/png`). The response contains a similar `candidates →
    /// content → parts` structure; we scan parts for the first
    /// `inlineData` whose mime starts with "image/" and return its
    /// base64-decoded bytes.
    private static func runGeminiEdit(sourcePNG: Data,
                                       prompt: String,
                                       apiKey: String,
                                       model: String) async throws -> Data {
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlStr) else {
            throw AIProviderError.decode("Invalid Gemini endpoint URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 90

        struct GeminiPart: Encodable {
            let text: String?
            let inlineData: InlineData?
            struct InlineData: Encodable {
                let mimeType: String
                let data: String
            }
        }
        struct GeminiContent: Encodable {
            let parts: [GeminiPart]
        }
        struct GeminiReq: Encodable {
            let contents: [GeminiContent]
        }
        let textPart = GeminiPart(text: prompt, inlineData: nil)
        let imgPart = GeminiPart(
            text: nil,
            inlineData: GeminiPart.InlineData(
                mimeType: "image/png",
                data: sourcePNG.base64EncodedString()
            )
        )
        let body = GeminiReq(contents: [GeminiContent(parts: [textPart, imgPart])])
        req.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await execute(req, providerName: "Gemini")

        struct GeminiResp: Decodable {
            struct Candidate: Decodable {
                let content: Content
                struct Content: Decodable {
                    let parts: [Part]
                    struct Part: Decodable {
                        let text: String?
                        let inlineData: InlineData?
                        struct InlineData: Decodable {
                            let mimeType: String
                            let data: String
                        }
                    }
                }
            }
            let candidates: [Candidate]?
        }
        let decoded: GeminiResp
        do {
            decoded = try JSONDecoder().decode(GeminiResp.self, from: data)
        } catch {
            throw AIProviderError.decode(
                "Couldn't parse Gemini generateContent response: \(error.localizedDescription)"
            )
        }
        for cand in decoded.candidates ?? [] {
            for part in cand.content.parts {
                if let inline = part.inlineData,
                   inline.mimeType.hasPrefix("image/"),
                   let bytes = Data(base64Encoded: inline.data) {
                    return bytes
                }
            }
        }
        throw AIProviderError.decode(
            "Gemini returned no image part. Make sure the configured model supports image output (e.g. gemini-2.5-flash-image-preview)."
        )
    }

    // MARK: - OpenRouter (multimodal chat completions)

    /// OpenRouter image edit via its OpenAI-compatible
    /// `/v1/chat/completions` endpoint. Sends a chat-style request
    /// where the user message is a list of multimodal content parts:
    /// one `text` part (the prompt) and one `image_url` part (data
    /// URL encoding the source PNG as base64). The response is
    /// returned in OpenAI chat shape but the assistant message
    /// content may include an `image_url` part with the generated
    /// image — works against image-capable models routed via
    /// OpenRouter (Gemini Flash Image, Flux models, etc.). Whether
    /// a given model returns an image depends on the model the
    /// user configured — text-only chat models obviously won't.
    private static func runOpenRouterEdit(sourcePNG: Data,
                                           prompt: String,
                                           apiKey: String,
                                           model: String) async throws -> Data {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // OpenRouter recommends an HTTP-Referer for analytics; harmless
        // when omitted but courteous to set.
        req.setValue("https://github.com/ilya000/DrPaste", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("DrPaste", forHTTPHeaderField: "X-Title")
        req.timeoutInterval = 90

        let dataURL = "data:image/png;base64," + sourcePNG.base64EncodedString()
        // The body is hand-rolled as a [String: Any] dictionary
        // serialised via JSONSerialization — it has a heterogeneous
        // `content` array (mixed text and image_url parts) which is
        // awkward to express through Codable.
        let body: [String: Any] = [
            "model": model,
            "modalities": ["image", "text"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url",
                     "image_url": ["url": dataURL]]
                ]
            ]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await execute(req, providerName: "OpenRouter")

        // OpenRouter chat-completion response. The assistant message
        // content can be either a plain string (legacy) or an array
        // of typed parts (multimodal). Parse the multimodal form and
        // look for an `image_url` part containing a data: URL.
        struct ORResp: Decodable {
            struct Choice: Decodable {
                let message: Message
                struct Message: Decodable {
                    // `content` is either String or [Part]; we
                    // capture both via RawValue and inspect manually.
                    let images: [ImageEntry]?
                    struct ImageEntry: Decodable {
                        let type: String?
                        let image_url: ImageURL?
                        struct ImageURL: Decodable {
                            let url: String?
                        }
                    }
                }
            }
            let choices: [Choice]?
        }
        // Try OpenRouter's documented `images` array first (post-2024
        // multimodal spec). Fall back to scanning message content for
        // a data: URL.
        if let decoded = try? JSONDecoder().decode(ORResp.self, from: data),
           let firstChoice = decoded.choices?.first,
           let images = firstChoice.message.images {
            for entry in images {
                if let urlStr = entry.image_url?.url,
                   let bytes = decodeDataURL(urlStr) {
                    return bytes
                }
            }
        }
        // Fallback raw-JSON scan: walk JSONSerialization output
        // looking for any "url" string that's a data:image/* base64.
        if let json = try? JSONSerialization.jsonObject(with: data),
           let bytes = scanForImageDataURL(in: json) {
            return bytes
        }
        // Last-resort: include the response body in the error so the
        // user can see exactly what OpenRouter returned (a text reply
        // from a text-only model, an error message, etc.).
        let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
        let snippet = bodyStr.prefix(300)
        throw AIProviderError.decode(
            "OpenRouter returned no image. The configured model may not support image output. Response: \(snippet)"
        )
    }

    // MARK: - Shared helpers

    /// Run a prepared URLRequest and translate URLSession's typed
    /// errors into our domain `AIProviderError` taxonomy. Returns
    /// raw response data + HTTP response object; caller parses the
    /// body per-backend.
    private static func execute(_ req: URLRequest,
                                providerName: String) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let urlErr as URLError where urlErr.code == .notConnectedToInternet
            || urlErr.code == .networkConnectionLost
            || urlErr.code == .dnsLookupFailed {
            throw AIProviderError.networkUnreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.decode("\(providerName): no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AIProviderError.http(status: http.statusCode, body: body)
        }
        return (data, http)
    }

    /// Decode a `data:image/png;base64,...` URL string into raw bytes.
    /// Returns nil for non-data URLs or malformed base64.
    private static func decodeDataURL(_ urlStr: String) -> Data? {
        guard urlStr.hasPrefix("data:"),
              let commaIdx = urlStr.firstIndex(of: ",") else { return nil }
        let base64 = String(urlStr[urlStr.index(after: commaIdx)...])
        return Data(base64Encoded: base64)
    }

    /// Recursive scan for any "url" string anywhere in a JSON tree
    /// that looks like a data:image/* base64 URL. Defensive helper
    /// for OpenRouter responses where the image part can land in a
    /// few different shapes depending on the underlying provider.
    private static func scanForImageDataURL(in node: Any) -> Data? {
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if key == "url", let s = value as? String, s.hasPrefix("data:image/"),
                   let bytes = decodeDataURL(s) {
                    return bytes
                }
                if let bytes = scanForImageDataURL(in: value) { return bytes }
            }
        } else if let arr = node as? [Any] {
            for item in arr {
                if let bytes = scanForImageDataURL(in: item) { return bytes }
            }
        }
        return nil
    }

    /// Persist the generated PNG into the clipboard store and return a
    /// fresh ClipboardItem suitable for `.preview`. Mirrors the
    /// region-capture path (`ClipboardStore.addCapturedImage`) so the
    /// AI-edited image lands in history at index 0 just like any
    /// user-captured screen region.
    @MainActor
    static func persist(pngData: Data, sourceItem: ClipboardItem) -> ClipboardItem? {
        let (width, height): (Int, Int) = {
            if let img = NSImage(data: pngData) {
                let s = img.size
                if let rep = img.representations.first {
                    return (rep.pixelsWide, rep.pixelsHigh)
                }
                return (Int(s.width), Int(s.height))
            }
            return (1024, 1024)
        }()
        let store = (NSApp.delegate as? AppDelegate)?.clipboardStoreForAIImage
        return store?.addCapturedImage(
            pngData: pngData,
            width: width,
            height: height,
            sourceApp: nil
        )
    }
}

// MARK: - AppDelegate hook

/// AppDelegate owns the ClipboardStore but doesn't expose it
/// publicly. This tiny passthrough lets `AIImageHTTP.persist` reach
/// the store without us threading the dependency through every
/// action-construction site (custom AI descriptors are materialised
/// by ActionRegistry via the value-type `AIImageAction(...)` initializer;
/// we don't want to pass `store` to every init just to make this one
/// path work).
extension AppDelegate {
    /// Read-only access to the clipboard store for the AI image
    /// generation path. Only caller is `AIImageHTTP.persist`, which
    /// runs after the app has finished launching (an AI image edit
    /// can't fire before AppDelegate.applicationDidFinishLaunching
    /// populates `store`).
    @MainActor
    var clipboardStoreForAIImage: ClipboardStore { store }
}
