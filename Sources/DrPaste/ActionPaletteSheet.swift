//
//  ActionPaletteSheet.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Palette sheet: the Browse button in the Settings Actions list opens this
//  window. Shows every available action for the current content type, grouped
//  by category. Disabled actions have their toggle off so the user can enable
//  any of them with a single click. Search field at the top for quick lookup.
//

import SwiftUI

struct ActionPaletteSheet: View {
    let kind: SemanticKind
    @ObservedObject var registry: ActionRegistry
    let onClose: () -> Void

    @State private var search: String = ""

    private struct Category: Identifiable {
        let id: String
        let title: String
        let prefix: String
    }

    private let categories: [Category] = [
        Category(id: "core", title: "Core", prefix: "builtin.identity"),
        Category(id: "text", title: "Text transformations", prefix: "builtin.uppercase"),
        Category(id: "url", title: "URL", prefix: "builtin.url_"),
        Category(id: "json", title: "JSON", prefix: "builtin.json_"),
        Category(id: "table", title: "Table / CSV", prefix: "builtin.table_"),
        Category(id: "md", title: "Markdown", prefix: "builtin.md_"),
        Category(id: "code", title: "Code", prefix: "builtin.code_"),
        Category(id: "rich", title: "Rich text", prefix: "builtin.rich_"),
        Category(id: "image", title: "Image", prefix: "builtin.image_"),
        Category(id: "files", title: "Files", prefix: "builtin.files_"),
        Category(id: "ai", title: "AI", prefix: "ai.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search actions…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredCategories, id: \.id) { cat in
                        let actions = applicableActionsForCategory(cat)
                        if !actions.isEmpty {
                            categorySectionHeader(cat.title, count: actions.count)
                            ForEach(actions, id: \.id) { action in
                                paletteRow(action)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
            }

            Divider()

            HStack {
                Text("Click toggle to enable. Changes apply immediately.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 540, height: 560)
    }

    private func categorySectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 12).padding(.bottom, 4)
    }

    private func paletteRow(_ action: ClipboardAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: enabledBinding(action.id))
                .labelsHidden()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(action))
                    .font(.system(size: 13, weight: .medium))
                Text(description(for: action.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(registry.isEnabled(action.id)
                      ? Color.accentColor.opacity(0.08)
                      : Color.primary.opacity(0.03))
        )
    }

    private func displayName(_ action: ClipboardAction) -> String {
        registry.displayTitle(forActionID: action.id, defaultTitle: action.title)
    }

    private func description(for actionID: String) -> String {
        BuiltinActionMetadata.descriptions[actionID] ?? ""
    }

    private func enabledBinding(_ actionID: String) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled(actionID) },
            set: { registry.setEnabled($0, for: actionID) }
        )
    }

    private var filteredCategories: [Category] {
        if search.isEmpty { return categories }
        return categories.filter { cat in !applicableActionsForCategory(cat).isEmpty }
    }

    /// All applicable actions for this content type within a single category.
    private func applicableActionsForCategory(_ cat: Category) -> [ClipboardAction] {
        let item = SettingsSamples.sample(for: kind)
        let ctx = ContextDetector.detect(item)
        let all = registry.actions.filter { action in
            // Exclude user.* (custom AI / transformations) — they live in the main list.
            guard !action.id.hasPrefix("user.") else { return false }
            // Category match
            switch cat.id {
            case "core":
                return action.id == "builtin.identity" || action.id == "builtin.paste_as_text"
            case "ai":
                return action.id.hasPrefix("ai.")
            default:
                return action.id.hasPrefix(cat.prefix) && action.id != "builtin.identity"
                    && action.id != "builtin.paste_as_text"
            }
        }
        let applicable = all.filter { $0.isApplicable(item: item, context: ctx) }
        if search.isEmpty { return applicable }
        let s = search.lowercased()
        return applicable.filter { action in
            displayName(action).lowercased().contains(s)
                || description(for: action.id).lowercased().contains(s)
                || action.id.lowercased().contains(s)
        }
    }
}
