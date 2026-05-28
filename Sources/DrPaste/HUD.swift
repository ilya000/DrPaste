//
//  HUD.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  HUD overlay — единая imp для gesture и summon mode (отличаются только
//  styleMask панели + Limited Mode banner). Поддержка ApplyOutcome.failed
//  через inline notice (Backlog #2), source label под header (Backlog #1),
//  AttributedString rich text preview (Правка #3), accent через NSColor,
//  font scaling, dynamic visibleRowCount + chevrons, scroll actions с
//  автоцентрированием.
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - State

@MainActor
final class HudState: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var itemIndex: Int = 0
    @Published var actionIndex: Int = 0
    @Published var actions: [ClipboardAction] = []

    /// Последний результат action.apply — драйвит preview и UI failure notice.
    @Published var outcome: ApplyOutcome? = nil
    @Published var isPreviewLoading: Bool = false
    @Published var mode: HudMode = .gesture
    @Published var engineLabel: String = ""

    /// Content meta для focused item — лениво вычисляется через ContentMetaCache (Правка #15).
    @Published var contentMeta: String? = nil

    /// Optional provider — позволяет HUD получить custom title для action
    /// (правка #6 lite — пользователь может переименовать built-in).
    /// Закладывается через AppDelegate.showPanel при создании view.
    var actionTitleProvider: ((String, String) -> String)? = nil

    private static let fontScaleKey = "drpaste.hud.fontScale"
    @Published var fontScale: CGFloat = {
        let v = UserDefaults.standard.double(forKey: HudState.fontScaleKey)
        return v == 0 ? 1.0 : CGFloat(v)
    }() {
        didSet { UserDefaults.standard.set(Double(fontScale), forKey: Self.fontScaleKey) }
    }

    func adjustFontScale(_ change: FontChange) {
        switch change {
        case .bigger:  fontScale = min(1.6, fontScale + 0.1)
        case .smaller: fontScale = max(0.7, fontScale - 0.1)
        case .reset:   fontScale = 1.0
        }
    }

    var currentItem: ClipboardItem? {
        guard itemIndex >= 0, itemIndex < items.count else { return nil }
        return items[itemIndex]
    }
    var currentAction: ClipboardAction? {
        guard actionIndex >= 0, actionIndex < actions.count else { return nil }
        return actions[actionIndex]
    }
}

// MARK: - Panel

final class HudPanel: NSPanel {
    private let allowsKey: Bool
    private static let cornerRadius: CGFloat = 18

    init(contentRect: NSRect, allowsKey: Bool) {
        self.allowsKey = allowsKey
        let style: NSWindow.StyleMask = allowsKey
            ? [.borderless, .titled, .fullSizeContentView]
            : [.borderless, .nonactivatingPanel]
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = !allowsKey
    }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    // Правка #12: defensive corner radius — re-apply при каждом layout,
    // recursively на subview'ы (vibrant material имеет собственный layer).
    // cornerCurve = .continuous даёт Apple-style squircle.
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        applyRoundedCorners()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        applyRoundedCorners()
    }

    private func applyRoundedCorners() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.cornerRadius = Self.cornerRadius
        cv.layer?.cornerCurve = .continuous
        cv.layer?.masksToBounds = true
        applyRoundedCornersRecursive(cv)
    }

    private func applyRoundedCornersRecursive(_ view: NSView) {
        for sub in view.subviews {
            if sub.wantsLayer || sub.layer != nil {
                sub.layer?.cornerRadius = Self.cornerRadius
                sub.layer?.cornerCurve = .continuous
                sub.layer?.masksToBounds = true
            }
            applyRoundedCornersRecursive(sub)
        }
    }
}

// MARK: - acceptsFirstMouse host

final class HudHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - HUD view

struct HudView: View {
    @ObservedObject var state: HudState
    let onPick: (Int, Int) -> Void               // (itemIdx, actionIdx) — обновить preview
    let onCommit: () -> Void                      // release / Enter / dbl-click
    let onOpenAccessibility: () -> Void
    let onRecoveryAction: (RecoveryAction) -> Void
    let onClose: () -> Void                       // Правка #15: close button mouse-route

    @State private var hoveredItemID: UUID? = nil
    @State private var hoveredActionID: String? = nil

    private var accent: Color { Color(nsColor: .controlAccentColor) }
    private func sz(_ base: CGFloat) -> CGFloat { base * state.fontScale }

    var body: some View {
        ZStack {
            VisualEffect(material: .hudWindow, blending: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

            VStack(spacing: 8) {
                compactHeader
                Divider().opacity(0.3)
                content
                Divider().opacity(0.3)
                actionsBar
                footer
                if state.mode == .summon { limitedModeBanner }
            }
            .padding(14)
        }
        .frame(width: 720, height: state.mode == .summon ? 440 : 400)
    }

    // MARK: header (Правка #15 — компактная одна строка + close button)

    private var compactHeader: some View {
        HStack(spacing: 6) {
            AppBrand.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: sz(16), height: sz(16))
            Text(AppBrand.name)
                .font(.system(size: sz(13), weight: .semibold))
            Text("·").foregroundStyle(.secondary)
            Text("\(state.itemIndex + 1)/\(max(state.items.count, 1))")
                .font(.system(size: sz(11), design: .monospaced))
                .foregroundStyle(.secondary)
            if let src = compactSourceLabel {
                Text("·").foregroundStyle(.secondary)
                Text(src)
                    .font(.system(size: sz(11)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let timestampLabel = compactTimestampLabel {
                Text("·").foregroundStyle(.secondary)
                Text(timestampLabel)
                    .font(.system(size: sz(11)))
                    .foregroundStyle(.tertiary)
                    .help(absoluteTimestampLabel ?? "")
            }
            Spacer()
            if !state.engineLabel.isEmpty {
                Text(state.engineLabel)
                    .font(.system(size: sz(9), design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: sz(14)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close DrPaste")
        }
    }

    /// Краткая форма source: app + window title (truncate до 25 char)
    private var compactSourceLabel: String? {
        guard let item = state.currentItem else { return nil }
        guard let app = item.sourceAppName ?? item.sourceBundleID?
                .components(separatedBy: ".").last?.capitalized else { return nil }
        if let title = item.sourceWindowTitle, !title.isEmpty {
            let trimmed = title.prefix(25)
            let suffix = title.count > 25 ? "…" : ""
            return "\(app) \"\(trimmed)\(suffix)\""
        }
        return app
    }

    /// Relative timestamp ("just now", "5m ago", "2h ago") для recent items,
    /// absolute date/time для старых (>1 day). Tooltip всегда показывает полную дату.
    private var compactTimestampLabel: String? {
        guard let item = state.currentItem else { return nil }
        let interval = Date().timeIntervalSince(item.createdAt)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 86400 * 7 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
        // Старше недели — точная дата
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: item.createdAt)
    }

    /// Полный timestamp для tooltip на hover (всегда абсолютный).
    private var absoluteTimestampLabel: String? {
        guard let item = state.currentItem else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return "Copied \(formatter.string(from: item.createdAt))"
    }

    /// Content meta row (Правка #15 — небольшая строка с metadata о focused item).
    /// Расположена непосредственно над preview pane, в правой колонке content area.
    private var contentMetaRow: some View {
        HStack(spacing: 0) {
            if let meta = state.contentMeta {
                Text(meta)
                    .font(.system(size: sz(10)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if state.currentItem != nil {
                Text("…")
                    .font(.system(size: sz(10)))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(height: sz(14))
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        if state.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: sz(28)))
                    .foregroundStyle(.secondary)
                Text("History is empty")
                    .font(.system(size: sz(13)))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 12) {
                historyColumn.frame(width: 260, alignment: .leading)
                Divider().opacity(0.2)
                VStack(alignment: .leading, spacing: 4) {
                    contentMetaRow                  // meta теперь NAD preview pane
                    previewPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: history

    private var visibleRowCount: Int {
        let base = 11
        let v = Int(round(Double(base) / state.fontScale))
        return max(5, min(v, state.items.count))
    }

    private var visibleWindow: (start: Int, end: Int) {
        let n = state.items.count
        let count = visibleRowCount
        var start = state.itemIndex - count / 2
        start = max(0, min(start, n - count))
        let end = min(start + count, n)
        return (start, end)
    }
    private var hasItemsAbove: Bool { visibleWindow.start > 0 }
    private var hasItemsBelow: Bool { visibleWindow.end < state.items.count }

    private var historyColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasItemsAbove {
                HStack { Spacer(); Image(systemName: "chevron.compact.up")
                    .foregroundStyle(.secondary).opacity(0.7); Spacer() }
                    .frame(height: 10)
            } else {
                Color.clear.frame(height: 10)
            }

            let win = visibleWindow
            ForEach(win.start..<win.end, id: \.self) { idx in
                itemRow(state.items[idx], absoluteIdx: idx)
            }

            if hasItemsBelow {
                HStack { Spacer(); Image(systemName: "chevron.compact.down")
                    .foregroundStyle(.secondary).opacity(0.7); Spacer() }
                    .frame(height: 10)
            } else {
                Color.clear.frame(height: 10)
            }
            Spacer(minLength: 0)
        }
    }

    private func itemRow(_ item: ClipboardItem, absoluteIdx: Int) -> some View {
        let isActive = absoluteIdx == state.itemIndex
        let isHover = hoveredItemID == item.id
        return HStack(spacing: 6) {
            Image(systemName: item.semantic.sfSymbol).frame(width: sz(14))
            Text(snippet(item))
                .lineLimit(1)
                .font(.system(size: sz(12)))
                .foregroundStyle(isActive ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                      ? accent.opacity(0.22)
                      : (isHover ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in hoveredItemID = hovering ? item.id : nil }
        .onTapGesture(count: 2) {
            onPick(absoluteIdx, state.actionIndex)
            onCommit()
        }
        .onTapGesture(count: 1) {
            onPick(absoluteIdx, state.actionIndex)
        }
    }

    private func snippet(_ item: ClipboardItem) -> String {
        switch item.semantic {
        case .image, .pdf:
            return item.previewText ?? item.semantic.displayName
        case .files:
            return item.previewText ?? "Files"
        default:
            return (item.previewText ?? "").prefix(80)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    // MARK: preview

    @ViewBuilder
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Failure notice сверху если outcome.failed (Backlog #2)
            if case .failed(_, let reason, let recovery) = state.outcome {
                failureNotice(reason: reason, recovery: recovery)
            }
            if case .sideEffect(let desc, _) = state.outcome {
                sideEffectNotice(description: desc)
            }
            if case .alternativeCommit(_, let style) = state.outcome {
                alternativeCommitNotice(style: style)
            }

            if state.isPreviewLoading {
                VStack {
                    ProgressView().controlSize(.small)
                    Text("processing…")
                        .font(.system(size: sz(11)))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                previewContent
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        // Все случаи показывают item content. Failed/side-effect/alternativeCommit
        // показывают original — пользователь видит что было бы вставлено.
        let item: ClipboardItem? = {
            switch state.outcome {
            case .preview(let i):                return i
            case .alternativeCommit(let i, _):   return i
            case .failed(let i, _, _):           return i
            case .sideEffect:                    return state.currentItem
            case .none:                           return state.currentItem
            }
        }()
        if let item = item { renderItem(item) }
    }

    @ViewBuilder
    private func renderItem(_ item: ClipboardItem) -> some View {
        switch item.semantic {
        case .text, .url, .email, .json, .code, .markdown, .table:
            ScrollView {
                Text(item.previewText ?? "")
                    .font(.system(size: sz(12), design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
                    .padding(.horizontal, 6)        // защита от corner-radius clipping
                    .padding(.vertical, 2)
            }
        case .richText:
            ScrollView {
                richTextView(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        case .image, .pdf:
            ImagePreview(item: item)
                .padding(.horizontal, 6)
        case .files:
            VStack(alignment: .leading, spacing: 2) {
                if let urls = filesList(item) {
                    ForEach(urls, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: sz(11), design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 6)
        case .unknown:
            VStack(alignment: .leading) {
                Text("Unknown content type")
                    .foregroundStyle(.secondary)
                Text(item.previewText ?? "")
                    .font(.system(size: sz(11), design: .monospaced))
            }
            .padding(.horizontal, 6)
        }
    }

    private func filesList(_ item: ClipboardItem) -> [String]? {
        // Парсим из representations или previewText
        if item.semantic == .files, let s = item.previewText {
            return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    @ViewBuilder
    private func richTextView(_ item: ClipboardItem) -> some View {
        if let attr = makeAttributedString(from: item) {
            Text(attr).font(.system(size: sz(12)))
        } else {
            Text(item.previewText ?? "").font(.system(size: sz(12)))
        }
    }

    private func makeAttributedString(from item: ClipboardItem) -> AttributedString? {
        // Try RTF
        if let rel = item.representations["public.rtf"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let ns = try? NSAttributedString(data: data,
                                            options: [.documentType: NSAttributedString.DocumentType.rtf],
                                            documentAttributes: nil) {
            return try? AttributedString(ns, including: \.swiftUI)
        }
        // Try HTML
        if let rel = item.representations["public.html"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let ns = try? NSAttributedString(data: data,
                                            options: [.documentType: NSAttributedString.DocumentType.html,
                                                      .characterEncoding: String.Encoding.utf8.rawValue],
                                            documentAttributes: nil) {
            return try? AttributedString(ns, including: \.swiftUI)
        }
        return nil
    }

    // MARK: failure / side-effect / alternativeCommit notices

    private func failureNotice(reason: String, recovery: RecoveryAction?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: sz(11)))
            Text(reason)
                .font(.system(size: sz(11)))
                .foregroundStyle(.primary)
            Spacer()
            if let rec = recovery {
                Button(recoveryLabel(rec)) { onRecoveryAction(rec) }
                    .controlSize(.small)
                    .font(.system(size: sz(10)))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
    }

    private func recoveryLabel(_ rec: RecoveryAction) -> String {
        switch rec {
        case .openProvidersConfig:      return "Open AI Settings"
        case .openAccessibilitySettings: return "Open Accessibility"
        case .custom(let label, _):     return label
        }
    }

    private func sideEffectNotice(description: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(accent).font(.system(size: sz(11)))
            Text(description).font(.system(size: sz(11)))
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.10)))
    }

    private func alternativeCommitNotice(style: CommitStyle) -> some View {
        let label: String = {
            switch style {
            case .standardPaste: return ""
            case .typeSlowly(let d, _): return "Will type slowly (\(Int(d * 1000)) ms / char)"
            case .typeFast: return "Will type fast (50 ms / char)"
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: "keyboard").foregroundStyle(accent).font(.system(size: sz(11)))
            Text(label).font(.system(size: sz(11)))
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.10)))
    }

    // MARK: actions bar (scroll + autocenter + fade)

    private var actionsBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.actions.indices, id: \.self) { idx in
                        actionChip(idx).id(idx)
                    }
                }
                .padding(.horizontal, 4)
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .leading, endPoint: .trailing)
            )
            .onChange(of: state.actionIndex) { newIdx in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
        .frame(height: sz(30))
    }

    private func actionChip(_ idx: Int) -> some View {
        let a = state.actions[idx]
        let isActive = idx == state.actionIndex
        let isHover = hoveredActionID == a.id
        let title = state.actionTitleProvider?(a.id, a.title) ?? a.title
        return HStack(spacing: 4) {
            if let badge = providerBadge(for: a) {
                ProviderBadgeView(text: badge.label, color: badge.color,
                                  fontSize: sz(9), iconName: badge.icon)
            }
            Text(title)
                .font(.system(size: sz(11), weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : .secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Capsule().fill(
                isActive
                ? accent.opacity(0.28)
                : (isHover ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06))
            )
        )
        .contentShape(Capsule())
        .onHover { hovering in hoveredActionID = hovering ? a.id : nil }
        .onTapGesture(count: 2) {
            onPick(state.itemIndex, idx)
            onCommit()
        }
        .onTapGesture(count: 1) {
            onPick(state.itemIndex, idx)
        }
    }

    /// Provider badge для AI actions (#9). Возвращает label, color и SF Symbol.
    private func providerBadge(for action: ClipboardAction)
        -> (label: String, color: Color, icon: String)?
    {
        guard let ai = action as? AIAction else { return nil }
        // Resolve provider kind через registry
        let resolvedKind: ProviderKind? = {
            if let id = ai.providerID,
               let cp = AIProviderRegistry.shared.config.providers.first(where: { $0.id == id }) {
                return cp.kind
            }
            if let defaultID = AIProviderRegistry.shared.config.defaultProviderID,
               let cp = AIProviderRegistry.shared.config.providers.first(where: { $0.id == defaultID }) {
                return cp.kind
            }
            return nil
        }()
        guard let kind = resolvedKind else { return ("AI", Color.gray, "sparkle") }
        return (kind.badgeLabel, badgeColor(for: kind), kind.iconName)
    }

    private func badgeColor(for kind: ProviderKind) -> Color {
        switch kind {
        case .anthropic: return .orange
        case .openai:    return .green
        case .gemini:    return .blue
        case .grok:      return .primary
        case .mistral:   return .purple
        case .deepseek:  return .indigo
        case .ollama, .lmstudio, .llamaCpp, .custom: return .gray
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 12) {
            keyHint("↑↓", "history")
            keyHint("←→", "actions")
            keyHint("⌫", "delete")             // Правка #14
            if state.mode == .gesture {
                keyHint("release", "paste")
            } else {
                keyHint("⏎", "paste")
            }
            keyHint("esc", "cancel")
            Spacer()
            keyHint("⌘+/-", "zoom")
        }
        .font(.system(size: sz(10), design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            Text(label)
        }
    }

    // MARK: Limited Mode banner

    private var limitedModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited Mode")
                    .font(.system(size: sz(11), weight: .semibold))
                Text("Press Enter to paste. Enable Accessibility for release-to-paste gesture mode.")
                    .font(.system(size: sz(10)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings…") { onOpenAccessibility() }
                .controlSize(.small)
                .font(.system(size: sz(10)))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - VisualEffect

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .active
        v.isEmphasized = false
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material; nsView.blendingMode = blending
    }
}

// MARK: - Image preview

/// Provider badge (#9, #10) — маленький SF Symbol icon слева от title в action chip.
/// Использует branded color provider'а. Параметр text оставлен для совместимости (показывается
/// в Settings tooltip).
struct ProviderBadgeView: View {
    let text: String
    let color: Color
    let fontSize: CGFloat
    var iconName: String = "sparkle"

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: fontSize + 1, weight: .medium))
            .foregroundStyle(color)
            .frame(width: fontSize + 4, height: fontSize + 4)
            .background(Circle().fill(color.opacity(0.18)))
            .help(text)
    }
}

/// Image preview pane (Правка #13) — thumbnail + constraints + dimensions label.
/// Никогда не рендерит full-size NSImage — только cached thumbnail (max 600 pt).
struct ImagePreview: View {
    let item: ClipboardItem

    /// #8 fix: загружаем через Data (а не NSImage(contentsOf:)) чтобы обходить
    /// NSImage URL-cache. Это критично для transformed items (grayscale/invert/etc) —
    /// новый файл может иметь тот же URL-like ключ, NSImage возвращает stale.
    private var loadedImage: NSImage? {
        guard let rel = item.previewImageRel,
              let data = try? Data(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel))
        else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let img = loadedImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 480, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .id(item.id)   // force re-render when item changes
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
