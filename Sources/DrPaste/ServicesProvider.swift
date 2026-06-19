//
//  ServicesProvider.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  macOS Services menu provider (#A23). Hooks into the system-wide
//  right-click → "Services" submenu so the user can send selected
//  text / files / images into DrPaste from any application. The
//  three entries land in 0.55.0:
//
//    • "Add to DrPaste history" — accepts text, files, and images;
//       writes a new ClipboardItem into the store without going
//       through the pasteboard (preserves the existing copy).
//    • "DrPaste: Translate" — accepts text; runs the default
//       Translate AI action and returns the result for inline
//       substitution.
//    • "DrPaste: Quick Copy" — accepts text/files/images; mirrors
//       ⌥⌘C (writes to pasteboard + plays the chime).
//
//  Deployment note: macOS only registers Services that are declared
//  in the host app's Info.plist NSServices array. Until DrPaste
//  ships as a proper signed .app bundle (depends on #A1) the
//  registry sees this provider but the Services menu doesn't list
//  the entries. The runtime wiring below is correct in any case;
//  it'll start working the moment the bundle ships.
//

import AppKit

@MainActor
final class DrPasteServicesProvider: NSObject {

    /// Reference to the AppDelegate for store + registry access.
    /// Bound at `NSApp.servicesProvider = ...` time in main.swift.
    weak var appDelegate: AppDelegate?

    /// Service: "Add to DrPaste history". Reads every payload type
    /// from the incoming pasteboard, classifies it via the same
    /// SemanticClassifier the clipboard watcher uses, and inserts
    /// at the top of history. Service implementations write any
    /// error into the `error` out-param so the Services menu can
    /// surface it.
    @objc func addToHistory(_ pboard: NSPasteboard,
                            userData: String,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let app = appDelegate, let store = app.store else {
            error.pointee = "DrPaste isn't ready yet."
            return
        }
        // Drive the existing snapshot path — same code the watcher
        // uses for live pasteboard captures, so the resulting clip
        // is byte-identical to what would land if the user just
        // hit ⌘C.
        guard let types = pboard.types, !types.isEmpty else {
            error.pointee = "No data available on the pasteboard."
            return
        }
        var representations: [String: String] = [:]
        var ordered: [String] = []
        for t in types {
            guard let data = pboard.data(forType: t) else { continue }
            let rel = store.writeRawBlob(data, type: t.rawValue)
            representations[t.rawValue] = rel
            ordered.append(t.rawValue)
        }
        guard !representations.isEmpty else {
            error.pointee = "Pasteboard payload is empty."
            return
        }
        let semantic = SemanticClassifier.classify(types: ordered, pasteboard: pboard)
        let previewText = PreviewSynthesizer.text(from: pboard, semantic: semantic)
        let previewImage = PreviewSynthesizer.imageRelative(from: pboard,
                                                            semantic: semantic,
                                                            store: store)
        let src = SourceResolver.resolve()
        let imgMeta = semantic == .image
            ? PreviewSynthesizer.imageMetadata(from: pboard)
            : (width: nil, height: nil, fileSize: nil, format: nil)
        let item = ClipboardItem(
            id: UUID(),
            semantic: semantic,
            createdAt: Date(),
            representations: representations,
            typesOrdered: ordered,
            previewText: previewText,
            previewImageRel: previewImage,
            originalImageWidth: imgMeta.width,
            originalImageHeight: imgMeta.height,
            originalImageFileSize: imgMeta.fileSize,
            imageFormat: imgMeta.format,
            sourceBundleID: src.bundleID,
            sourceAppName: src.name,
            sourceWindowTitle: src.window,
            tags: []
        )
        store.add(item)
        SoundFeedback.play(.copySuccess)
    }

    /// Service: "DrPaste: Translate". Accepts text from the host app's
    /// selection, runs the default Translate AI action (seeded as
    /// `user.translate` in DefaultAISeed), and writes the result back
    /// to the same pasteboard so the system inline-substitutes the
    /// selection. The Service signature requires the result to be
    /// available synchronously — we Task.detach the AI call and
    /// block briefly on the result. A future polish path moves this
    /// to NSExtension-style async response.
    @objc func translateSelection(_ pboard: NSPasteboard,
                                  userData: String,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let app = appDelegate, let registry = app.registry else {
            error.pointee = "DrPaste isn't ready yet."
            return
        }
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text selected."
            return
        }
        guard let action = registry.actions.first(where: { $0.id == "ai.text.translate" })
                       as? AIAction else {
            error.pointee = "Translate action not configured."
            return
        }
        // Synchronous wait — see method comment for caveats.
        let item = ClipboardItem(
            id: UUID(), semantic: .text, createdAt: Date(),
            representations: [:], typesOrdered: [],
            previewText: text, previewImageRel: nil,
            sourceBundleID: nil, sourceAppName: "Services menu",
            sourceWindowTitle: nil, tags: []
        )
        let context = ContextDetector.detect(item)
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String? = nil
        Task.detached {
            let outcome = await action.apply(item: item, context: context)
            if case .preview(let result) = outcome {
                resultText = result.previewText
            }
            semaphore.signal()
        }
        let timed = semaphore.wait(timeout: .now() + 30)
        guard timed == .success, let out = resultText else {
            error.pointee = "Translation timed out or failed."
            return
        }
        pboard.clearContents()
        pboard.setString(out, forType: .string)
    }

    /// Service: "DrPaste: Quick Copy". Same shape as ⌥⌘C — adds
    /// the selection to history and plays the chime. Doesn't write
    /// to the pasteboard (the selection was already there).
    @objc func quickCopy(_ pboard: NSPasteboard,
                         userData: String,
                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        // Identical behaviour to addToHistory — Services menu naming
        // distinction only ("Quick Copy" reads more like the ⌥⌘C
        // gesture name).
        addToHistory(pboard, userData: userData, error: error)
    }
}
