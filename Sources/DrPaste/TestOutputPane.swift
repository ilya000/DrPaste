//
//  TestOutputPane.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  HUD-style Output pane for the Edit Action sheet's Test panel.
//  Renders an `ApplyOutcome` exactly the way `BigHUD.previewPane`
//  renders the live focused action: spinner with provider · model ·
//  elapsed counter while an AI call is in flight, failure notice
//  with an orange warning icon when the action fails, side-effect
//  description for actions like "Reveal in Finder", text content
//  rendered in monospaced font, rich-text content rendered through
//  the same NSTextView wrapper BigHUD uses, image content rendered
//  through `ImagePreview`. Designed as a pure View — no shared
//  state machine — so it can also be lifted into the Playground
//  or any future "preview anywhere" surface without dragging
//  AppDelegate dependencies along.
//

import SwiftUI
import AppKit

struct TestOutputPane: View {
    let outcome: ApplyOutcome?
    let isRunning: Bool
    let inflight: AIInflight?
    let elapsed: TimeInterval
    /// Optional action title for the loading panel. Shown
    /// prominently above the spinner so the user always knows
    /// WHAT is currently running — important for local actions
    /// where there's no AI provider chrome to fall back on
    /// (without this, a slow CIFilter image transform showed only
    /// "processing…" with no indication of which action). Defaults
    /// to nil for callers that don't track action title.
    var actionTitle: String? = nil
    /// Optional run handler — when provided, the empty-state play
    /// glyph becomes a clickable button that triggers the test
    /// directly. Without it the placeholder is text-only ("click
    /// Run test in the toolbar") so a non-functional play icon
    /// doesn't tempt the user.
    var onRun: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Subtle background so the pane visually reads as a
            // distinct surface even when empty.
            Color.primary.opacity(0.03)

            if isRunning {
                loadingPanel
            } else if let outcome = outcome {
                outcomeContent(outcome)
            } else {
                placeholder
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var placeholder: some View {
        // When the caller provides `onRun`, the play glyph is a
        // real button — natural affordance for "click to run". When
        // it doesn't (legacy embeds), we render an inert label so
        // the play icon doesn't promise interaction it can't deliver.
        if let onRun = onRun {
            Button(action: onRun) {
                VStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                    Text("Run test")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Run the action against the Sample input and show the result here")
        } else {
            VStack(spacing: 6) {
                Text("Click “Run test” to preview the result")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Loading

    /// Mirrors BigHUD's `aiLoadingPanel`. Three pieces:
    ///   1. Action title (always when known) — top line, prominent
    ///   2. Provider · Model — when an AI inflight descriptor is set
    ///   3. Elapsed time capsule — always when running, so even
    ///      local-only actions get a "0.3s" reference instead of
    ///      a context-free spinner.
    private var loadingPanel: some View {
        VStack(spacing: 8) {
            if let title = actionTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if let inflight = inflight {
                    Text("\(inflight.providerLabel) · \(inflight.modelName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                } else {
                    Text("processing…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            // Elapsed counter — shown for every running test so the
            // user can tell whether the action is moving or stuck.
            // Capsule background matches BigHUD's "thinking…" pill.
            Text(String(format: inflight != nil ? "thinking… %.1fs" : "%.1fs",
                        elapsed))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Outcome dispatch

    @ViewBuilder
    private func outcomeContent(_ outcome: ApplyOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Failure / side-effect / alternative-commit notices first,
            // matching BigHUD's layout. Failures still render the
            // original item below so the user sees what would have
            // been pasted instead.
            switch outcome {
            case .failed(_, let reason, _):
                failureNotice(reason)
            case .sideEffect(let desc, _):
                sideEffectNotice(desc)
            case .alternativeCommit(_, let style):
                alternativeNotice(style)
            case .preview:
                EmptyView()
            }
            // Content body — text / image / rich text / etc.
            //
            // Type Slowly's outcome animates character-by-character at
            // the SAME delay the production run will use, so the
            // playground preview is bit-for-bit honest about what the
            // user will see at the receiving end. No 2× / "speed it up"
            // visualisation — matches the real keystroke cadence so
            // users can dial the delay parameter against real perceived
            // speed. Static fallback covers re-render cases (the view
            // identity changes when the outcome is re-emitted).
            if case .alternativeCommit(let item, .typeSlowly(let delay, let jitter)) = outcome {
                TypeSlowlyPreview(text: item.previewText ?? "",
                                  baseDelay: delay,
                                  jitter: jitter)
            } else if let item = itemFromOutcome(outcome) {
                renderItem(item)
            }
        }
        .padding(8)
    }

    private func itemFromOutcome(_ outcome: ApplyOutcome) -> ClipboardItem? {
        switch outcome {
        case .preview(let i):                return i
        case .alternativeCommit(let i, _):   return i
        case .failed(let i, _, _):           return i
        case .sideEffect:                    return nil
        }
    }

    // MARK: - Item rendering (mirrors BigHUD.renderItem)

    @ViewBuilder
    private func renderItem(_ item: ClipboardItem) -> some View {
        switch item.semantic {
        case .text, .url, .email, .json, .code, .markdown, .table, .unknown:
            ScrollView {
                Text(item.previewText ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case .richText:
            if let attr = RichTextLoader.attributedString(from: item) {
                RichTextPreviewView(attributedString: attr, fontScale: 1.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    Text(item.previewText ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        case .image, .pdf:
            ImagePreview(item: item)
        case .files:
            // Same list shape as BigHUD's `.files` rendering — one
            // filename per line, monospaced. Image is the only
            // common other case the test panel can produce; .files
            // happens only when the action returns file URLs.
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filesList(item), id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func filesList(_ item: ClipboardItem) -> [String] {
        guard let s = item.previewText else { return [] }
        return s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Notices

    private func failureNotice(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.08)))
    }

    private func sideEffectNotice(_ description: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 11))
            Text(description)
                .font(.system(size: 11))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.08)))
    }

    private func alternativeNotice(_ style: CommitStyle) -> some View {
        let label: String = {
            switch style {
            case .standardPaste:        return "Standard paste"
            case .typeSlowly:           return "Type slowly"
            case .typeFast:             return "Type fast"
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .foregroundStyle(.purple)
                .font(.system(size: 11))
            Text("Alternative commit: \(label)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.purple.opacity(0.08)))
    }
}

// MARK: - Type Slowly preview

/// Renders the Type Slowly output by animating the string character-by-
/// character at the same delay the production run uses (`TypeSimulator.
/// typeSlowly(_:baseDelay:jitter:)`). Lets users dial the delay
/// parameter against the actual perceived speed before triggering the
/// action against a real input field.
///
/// Implementation note: keeps state inside the view so the playground's
/// outcome re-emission (which can churn this view's identity) restarts
/// from index 0 each time. The animation runs on a single Task that
/// honours view-lifecycle cancellation via `.task`.
private struct TypeSlowlyPreview: View {
    let text: String
    let baseDelay: TimeInterval
    let jitter: Double

    @State private var visibleCount: Int = 0
    @State private var finished: Bool = false

    var body: some View {
        let prefix = text.prefix(visibleCount)
        let suffix = text.dropFirst(visibleCount)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: finished ? "checkmark.circle.fill" : "keyboard.fill")
                    .foregroundStyle(finished ? .green : .purple)
                    .font(.system(size: 11))
                Text(finished
                     ? "Preview complete · \(text.count) characters"
                     : "Typing live at \(Int(baseDelay * 1000)) ms / char · \(visibleCount)/\(text.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView {
                // `foregroundStyle(_:)` on a `Text` value (as opposed to a
                // View modifier on a container) is macOS 14+. Deployment
                // target is macOS 13, so use the older
                // `foregroundColor(_:)` API — it's deprecated for
                // SwiftUI in general but still the supported call on a
                // composed Text for back-deployment.
                (Text(String(prefix))
                    .foregroundColor(.primary)
                 + Text(String(suffix))
                    .foregroundColor(Color.secondary.opacity(0.35)))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .task(id: text + "|\(baseDelay)|\(jitter)") {
            visibleCount = 0
            finished = false
            let chars = Array(text)
            for i in 0..<chars.count {
                if Task.isCancelled { return }
                let factor = 1.0 + Double.random(in: -jitter...jitter)
                let delay = baseDelay * factor
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                visibleCount = i + 1
            }
            finished = true
        }
    }
}
