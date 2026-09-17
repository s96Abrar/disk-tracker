//
//  QuickLookPreview.swift
//  DiskTracker
//
//  Spacebar preview, the way Finder does it.
//
//  `QLPreviewPanel` is a shared AppKit singleton that pulls its content from
//  whichever object currently answers the responder chain. SwiftUI has no
//  equivalent, so this bridges: a controller holds the URL, and a hidden
//  NSView inserted into the hierarchy accepts the panel and feeds it.
//

import SwiftUI
import AppKit
import QuickLookUI

/// Holds whatever the preview panel should be showing.
///
/// A singleton because `QLPreviewPanel` is: there is one panel per app, and it
/// asks the responder chain for its data source rather than being handed one.
@MainActor
final class QuickLookPreview: NSObject {
    static let shared = QuickLookPreview()

    private var url: URL?

    private override init() { super.init() }

    /// Shows `url` in the panel, or closes the panel if it is already showing
    /// that file — the spacebar toggles, as it does in Finder.
    func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible, self.url == url {
            panel.orderOut(nil)
            return
        }

        self.url = url
        if panel.isVisible {
            // Already open on a different file: refresh in place rather than
            // closing and reopening, which flickers.
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// The file the panel is currently showing, or nil when nothing is queued.
    var currentURL: URL? { url }
}

// MARK: - Panel data source

// `@preconcurrency`: QLPreviewPanel calls its data source on the main thread,
// but the SDK protocol carries no actor annotation, so Swift 6 cannot see that
// and rejects the conformance from a @MainActor type.
extension QuickLookPreview: @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}

// MARK: - Responder bridge

/// Invisible view that claims the preview panel for this window.
///
/// `QLPreviewPanel` will not open unless something in the responder chain
/// returns true from `acceptsPreviewPanelControl`. No SwiftUI view does, so
/// one is inserted.
private struct QuickLookResponder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PanelHostView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PanelHostView: NSView {
        override var acceptsFirstResponder: Bool { true }

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

        // AppKit drives the preview panel from the main thread, but the
        // QuickLookUI additions to NSResponder carry no actor annotation, so
        // Swift sees these overrides as nonisolated and rejects touching the
        // panel's main-actor properties. `assumeIsolated` states what AppKit
        // already guarantees; it traps rather than corrupts if that ever fails.
        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated {
                panel.dataSource = QuickLookPreview.shared
                panel.delegate = QuickLookPreview.shared
            }
        }

        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated {
                panel.dataSource = nil
                panel.delegate = nil
            }
        }
    }
}

// MARK: - View integration

extension View {
    /// Enables Quick Look for this screen: installs the responder bridge and
    /// binds the spacebar to preview `node()`.
    ///
    /// The binding is a hidden zero-size button rather than `onKeyPress`, which
    /// requires focus that a Canvas or a List row does not reliably hold.
    /// A keyboard shortcut works wherever the window is focused, which is what
    /// makes spacebar feel like Finder.
    func quickLookPreview(for node: @escaping () -> DiskNode?) -> some View {
        self
            .background(QuickLookResponder().frame(width: 0, height: 0))
            .background(
                Button {
                    guard let node = node() else { return }
                    QuickLookPreview.shared.toggle(url: URL(fileURLWithPath: node.path))
                } label: { Color.clear.frame(width: 0, height: 0) }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel("Quick Look")
                .opacity(0)
            )
    }
}
