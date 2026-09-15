//
//  NodeActions.swift
//  DiskTracker
//
//  The delete / reveal / preview flow, shared by every view that shows a
//  scanned node: the directory list, filtered results, smart-filter results,
//  and both canvases.
//
//  It lives in one place because the confirmation rules are the dangerous part.
//  A per-view copy is a per-view chance to forget the system-path check or the
//  folder warning.
//

import SwiftUI
import AppKit

/// Owns the in-flight deletion and its confirmation.
///
/// Held by `ScanResultsView` and read from the environment, so a context menu
/// deep inside a `List` row can start a deletion without every intermediate
/// view passing a closure down.
@Observable
final class DeletionController {

    /// Nodes awaiting confirmation. Non-empty means the dialog is up.
    private(set) var pending: [DiskNode] = []

    /// Outcome of the last deletion, shown as an alert. Cleared on dismissal.
    var failure: DeletionFailure?

    struct DeletionFailure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var isConfirming: Bool {
        get { !pending.isEmpty }
        set { if !newValue { pending = [] } }
    }

    /// Total bytes the pending deletion would reclaim.
    var pendingSize: UInt64 {
        pending.reduce(0) { total, node in
            total + (node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize)
        }
    }

    /// True when anything pending is a folder — deleting one takes everything
    /// inside it, which the dialog says out loud.
    var pendingIncludesFolder: Bool {
        pending.contains { $0.fileKind == .directory }
    }

    /// True when anything pending sits under a protected system path.
    var pendingIncludesProtected: Bool {
        pending.contains {
            FileOperationsService.shared.isSystemProtected(url: URL(fileURLWithPath: $0.path))
        }
    }

    // MARK: - Intent

    /// Asks to delete one node. Always confirms: Trash is recoverable, but a
    /// mis-click on a folder is not obviously recoverable to the person who
    /// made it.
    func requestDelete(_ node: DiskNode) {
        pending = [node]
    }

    /// Asks to delete a batch.
    func requestDelete(_ nodes: [DiskNode]) {
        guard !nodes.isEmpty else { return }
        pending = nodes
    }

    func cancel() {
        pending = []
    }

    // MARK: - Execution

    /// Moves the confirmed nodes to Trash and updates the tree.
    ///
    /// Partial success is normal — one file in a batch can be locked or already
    /// gone — so this removes whatever actually went to Trash and reports the
    /// rest rather than treating the batch as all-or-nothing.
    func confirmDelete(model: AppModel) {
        let nodes = pending
        pending = []
        guard !nodes.isEmpty else { return }

        let urls = nodes.map { URL(fileURLWithPath: $0.path) }
        let results = FileOperationsService.shared.moveMultipleToTrash(urls: urls)

        var deleted: [String] = []
        var failures: [(String, String)] = []
        for (url, result) in results {
            switch result {
            case .success:
                deleted.append(url.path)
            case .failure(let error):
                failures.append((url.lastPathComponent, Self.describe(error)))
            }
        }

        if !deleted.isEmpty {
            model.removeFromTree(paths: deleted)
        }

        guard !failures.isEmpty else { return }
        failure = DeletionFailure(
            title: failures.count == 1
                ? "Couldn't move \(failures[0].0) to Trash"
                : "Couldn't move \(failures.count) items to Trash",
            message: Self.summarize(failures, deletedCount: deleted.count)
        )
    }

    private static func describe(_ error: FileOperationError) -> String {
        switch error {
        case .invalidURL:
            return "the path isn't a file"
        case .systemPathProtected:
            return "it's a protected system location"
        case .deletionFailed(let underlying):
            return underlying.localizedDescription
        }
    }

    private static func summarize(_ failures: [(String, String)], deletedCount: Int) -> String {
        // Listing every name in a large failed batch produces an unreadable
        // alert, so cap it and count the rest.
        let shown = failures.prefix(5)
            .map { "• \($0.0) — \($0.1)" }
            .joined(separator: "\n")
        let more = failures.count > 5 ? "\n• and \(failures.count - 5) more" : ""
        let progress = deletedCount > 0
            ? "\n\n\(deletedCount) other item\(deletedCount == 1 ? "" : "s") moved to Trash."
            : ""
        return shown + more + progress
    }
}

// MARK: - Context menu

extension View {
    /// Adds the standard right-click menu for a scanned node.
    func nodeActions(_ node: DiskNode, model: AppModel) -> some View {
        nodeActions(model: model) { node }
    }

    /// Menu for a node resolved at the moment the menu opens.
    ///
    /// The canvases have no per-node view to hang a menu on — they know which
    /// node is under the cursor only from hover state. A context menu builds
    /// its content on presentation, so resolving there targets whatever the
    /// user actually right-clicked, and the canvas keeps a stable identity
    /// instead of being rebuilt on every hover change.
    func nodeActions(model: AppModel, resolve: @escaping () -> DiskNode?) -> some View {
        modifier(NodeActionsModifier(resolve: resolve, model: model))
    }
}

private struct NodeActionsModifier: ViewModifier {
    let resolve: () -> DiskNode?
    var model: AppModel
    @Environment(DeletionController.self) private var deletion

    func body(content: Content) -> some View {
        content.contextMenu {
            if let node = resolve() {
                menu(for: node)
            } else {
                Button("No item here") {}.disabled(true)
            }
        }
    }

    @ViewBuilder
    private func menu(for node: DiskNode) -> some View {
        Group {
            Button {
                QuickLookPreview.shared.toggle(url: URL(fileURLWithPath: node.path))
            } label: {
                Label("Quick Look", systemImage: "eye")
            }

            // Distinct from Quick Look: this hands the file to its default
            // application rather than previewing it in place.
            Button {
                FileOperationsService.shared.openInDefaultApp(
                    url: URL(fileURLWithPath: node.path))
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }

            Button {
                FileOperationsService.shared.showInFinder(
                    url: URL(fileURLWithPath: node.path))
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            Button {
                model.selectNode(node)
            } label: {
                Label("Select", systemImage: "cursorarrow.rays")
            }

            Divider()

            Button(role: .destructive) {
                deletion.requestDelete(node)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            // The scan root has no parent in the tree to delete from, and
            // removing it would leave the window showing a scan of nothing.
            .disabled(node.path == model.rootNode?.path)
        }
    }
}

// MARK: - Confirmation

extension View {
    /// Attaches the confirmation dialog and failure alert. Applied once, by the
    /// screen that owns the `DeletionController`.
    func deletionConfirmation(_ deletion: DeletionController, model: AppModel) -> some View {
        modifier(DeletionConfirmationModifier(deletion: deletion, model: model))
    }
}

private struct DeletionConfirmationModifier: ViewModifier {
    @Bindable var deletion: DeletionController
    var model: AppModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                title,
                isPresented: $deletion.isConfirming,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    deletion.confirmDelete(model: model)
                }
                Button("Cancel", role: .cancel) {
                    deletion.cancel()
                }
            } message: {
                Text(explanation)
            }
            .alert(item: $deletion.failure) { failure in
                Alert(
                    title: Text(failure.title),
                    message: Text(failure.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }

    private var title: String {
        let items = deletion.pending
        if items.count == 1 {
            return "Move “\(items[0].name)” to Trash?"
        }
        return "Move \(items.count) items to Trash?"
    }

    /// Says what will actually happen. The size is the reclaim figure, which is
    /// the number the user came here for.
    private var explanation: String {
        var parts: [String] = []

        if deletion.pendingIncludesProtected {
            parts.append(
                "Some of these are in protected system locations and will be "
                + "skipped — removing them could stop macOS from working.")
        }
        if deletion.pendingIncludesFolder {
            parts.append("Folders are moved with everything inside them.")
        }

        let size = humanReadableBytes(deletion.pendingSize)
        parts.append("This frees about \(size). You can restore from Trash until it's emptied.")
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Batch bar

/// Actions for the current multi-selection. Shown above the status bar while
/// batch mode is on, so the count and reclaimable size stay visible while the
/// user keeps selecting.
struct BatchActionBar: View {
    var model: AppModel
    @Environment(DeletionController.self) private var deletion

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandAccent)

            Text("\(model.selectedNodes.count) selected")
                .font(.system(size: 12, weight: .semibold))

            Text(humanReadableBytes(model.selectedTotalSize))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear") { model.clearBatchSelection() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.selectedNodes.isEmpty)

            Button {
                deletion.requestDelete(model.selectedDiskNodes)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .disabled(model.selectedNodes.isEmpty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1),
            alignment: .top
        )
    }
}
