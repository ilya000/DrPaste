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

            VStack(spacing: 10) {
                header
                if let src = currentSourceLabel { sourceLabel(src) }
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

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            AppBrand.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: sz(22), height: sz(22))
            Text(AppBrand.name)
                .font(.system(size: sz(14), weight: .semibold))
            Spacer()
            Text("\(state.itemIndex + 1)/\(max(state.items.count, 1))")
                .font(.system(size: sz(11), design: .monospaced))
                .foregroundStyle(.secondary)
            if !state.engineLabel.isEmpty {
                Text(state.engineLabel)
                    .font(.system(size: sz(10), design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentSourceLabel: String? {
        guard let item = state.currentItem else { return nil }
        if let app = item.sourceAppName {
            if let title = item.sourceWindowTitle, !title.isEmpty {
                return "Copied from \(app) — \(title)"
            }
            return "Copied from \(app)"
        }
        if let bundle = item.sourceBundleID {
            return "Copied from \(bundle)"
        }
        return nil
    }

    private func sourceLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: sz(9)))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: sz(10)))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
                previewPane.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            }
        case .richText:
            ScrollView {
                richTextView(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image, .pdf:
            ImagePreview(item: item)
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
        case .unknown:
            VStack(alignment: .leading) {
                Text("Unknown content type")
                    .foregroundStyle(.secondary)
                Text(item.previewText ?? "")
                    .font(.system(size: sz(11), design: .monospaced))
            }
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
        return Text(a.title)
            .font(.system(size: sz(11), weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.primary : .secondary)
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

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 14) {
            keyHint("↑↓", "history")
            keyHint("←→", "actions")
            if state.mode == .gesture {
                keyHint("release", "paste")
            } else {
                keyHint("enter", "paste")
                keyHint("dbl-click", "paste")
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

struct ImagePreview: NSViewRepresentable {
    let item: ClipboardItem
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        return v
    }
    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let rel = item.previewImageRel {
            let url = AppStorage.imagesDir.appendingPathComponent(rel)
            nsView.image = NSImage(contentsOf: url)
        }
    }
}
