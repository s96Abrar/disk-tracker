//
//  ScanResultsView.swift
//  DiskTracker
//
//  Scan Results screen. Reached when a scan completes (live or restored
//  from history). Mirrors the sunburst mock top-to-bottom:
//   - Sidebar (CategoriesSidebar)
//   - Top toolbar: search + Smart Filters + Re-scan + Choose Folder
//   - Breadcrumb for the folder both panes are showing
//   - Resizable split: list (or filtered results) on the left, Sunburst or
//     Treemap on the right, picked with `model.currentView`
//   - Status bar (shared)
//
//  Re-scan runs `model.startScan(path: model.currentScanPath)`.
//  Choose Folder opens NSOpenPanel; on selection, switches scan path and
//  starts a new scan (allowed once the current one finishes — gated by
//  `canStartNewScan`).
//

import SwiftUI
import AppKit

struct ScanResultsView: View {
    /// `@Bindable` rather than plain: the search field binds to
    /// `model.searchQuery`.
    @Bindable var model: AppModel

    /// Back to Dashboard.
    var onBack: () -> Void

    /// Smart filter results are shown in a sheet over the visualization.
    @State private var showingSmartFilters = false

    /// Owns the delete confirmation for everything on this screen. Put in the
    /// environment so a context menu inside a List row can reach it without
    /// every view in between carrying a closure.
    @State private var deletion = DeletionController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CategoriesSidebar(model: model, onBack: onBack)

                VStack(spacing: 0) {
                    toolbar
                    Divider().opacity(0.3)
                    visualization
                }
            }

            LowSpaceBanner(monitor: model.freeSpaceMonitor)

            if model.isBatchMode {
                BatchActionBar(model: model)
            }

            StatusBar(model: model)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(deletion)
        .deletionConfirmation(deletion, model: model)
        // Spacebar previews the inspected node, as it does in Finder.
        .quickLookPreview { model.selectedNode }
        // A preview of a file that no longer exists is a stale window.
        .onChange(of: model.rootNode) { _, _ in QuickLookPreview.shared.close() }
        .sheet(isPresented: $showingSmartFilters) {
            smartFilterSheet
                // A sheet is a separate presentation context, so it needs the
                // controller and the dialog attached again.
                .environment(deletion)
                .deletionConfirmation(deletion, model: model)
        }
    }

    private var smartFilterSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.activeSmartFilter?.rawValue ?? "Smart Filters")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.isDuplicateScanRunning {
                    ProgressView().controlSize(.small)
                }
                Button("Done") {
                    showingSmartFilters = false
                    model.activeSmartFilter = nil
                    model.smartFilterResults = []
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.md)

            Divider()

            SmartFilterResultsView(model: model)
        }
        .frame(width: 720, height: 480)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search…", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 160)
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(nsColor: .controlBackgroundColor))
            )

            // Smart Filters — the services behind these (large/old/empty,
            // duplicates, app bundles) were fully built but unreachable after
            // the migration dropped ContentView.
            Menu {
                ForEach(AppModel.SmartFilterKind.allCases) { kind in
                    Button {
                        model.activeSmartFilter = kind
                        model.runSmartFilter()
                        showingSmartFilters = true
                    } label: {
                        Label(kind.rawValue, systemImage: kind.icon)
                    }
                }
            } label: {
                Text("Smart Filters")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.rootNode == nil)
            .help("Find large, old, empty, duplicate or bundled items")

            // Batch mode — turns row taps into multi-selection for the
            // BatchActionBar. Off by default so a tap still means "inspect".
            Button {
                model.isBatchMode.toggle()
                if !model.isBatchMode { model.clearBatchSelection() }
            } label: {
                Label("Select", systemImage: model.isBatchMode
                      ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .tint(model.isBatchMode ? Color.brandAccent : nil)
            .disabled(model.rootNode == nil)
            .help(model.isBatchMode ? "Leave selection mode" : "Select multiple items to delete")

            // Re-scan — disabled while a scan is running.
            Button {
                rescanCurrent()
            } label: {
                Label("Re-scan", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandAccent)
            .disabled(!model.canStartNewScan)

            // Choose Folder — also gated by canStartNewScan.
            Button {
                chooseFolderAndScan()
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .disabled(!model.canStartNewScan)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }

    // MARK: - Visualization area

    @ViewBuilder
    private var visualization: some View {
        if case .scanning = model.scanState {
            scanningState
        } else if model.rootNode == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                breadcrumb
                Divider().opacity(0.3)
                HSplitView {
                    // A category or search narrows the left pane to a flat
                    // list; the chart stays a structural view of the tree.
                    Group {
                        if model.isFiltering {
                            FilteredResultsView(model: model)
                        } else {
                            DirectoryListView(model: model)
                        }
                    }
                    .frame(minWidth: 360, idealWidth: 480)

                    chartPane
                        .frame(minWidth: 360)
                }
            }
        }
    }

    // ponytail: divider position resets each launch; wrap NSSplitView with an
    // autosaveName if users ask for it to stick.
    private var chartPane: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("Chart", selection: $model.currentView) {
                    ForEach(AppModel.ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(Spacing.sm)

            switch model.currentView {
            case .sunburst: SunburstView(model: model)
            case .treemap:  TreemapView(model: model)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Where both panes are. Always shown, so zooming doesn't shift the
    /// layout; the chart's own gestures and a list double-click move it.
    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button {
                model.focusPath = []
            } label: {
                Label(model.rootNode?.name ?? "", systemImage: "house")
                    .font(.system(size: 11, weight: model.focusPath.isEmpty ? .semibold : .medium))
            }
            .buttonStyle(.plain)

            ForEach(Array(model.focusPath.enumerated()), id: \.element.id) { index, node in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Button {
                    // Truncating to this node is what makes the crumb a jump
                    // rather than a single step back.
                    model.focusPath = Array(model.focusPath.prefix(index + 1))
                } label: {
                    Text(node.name)
                        .font(.system(size: 11,
                                      weight: index == model.focusPath.count - 1 ? .semibold : .regular))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: Spacing.sm)

            Button {
                model.focusPath.removeLast()
            } label: {
                Label("Up", systemImage: "arrow.up.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(model.focusPath.isEmpty)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Go up one level (⌘↑)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    /// Shown while the engine is walking. The count comes from the engine's
    /// progress stream; there is no percentage because the total is unknown
    /// until the walk completes.
    private var scanningState: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning \(model.currentScanPath)")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(model.filesScanned) items found")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Cancel Scan") { model.cancelScan() }
                .buttonStyle(.bordered)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyState(icon: "magnifyingglass.circle", title: "No scan loaded",
                   message: "Choose a folder to start a scan.",
                   action: chooseFolderAndScan,
                   actionLabel: "Choose Folder…",
                   actionIcon: "folder.badge.plus")
    }

    // MARK: - Actions

    private func rescanCurrent() {
        guard model.canStartNewScan else { return }
        model.startScan(path: model.currentScanPath)
    }

    private func chooseFolderAndScan() {
        guard let url = FolderPicker.chooseScanFolder(), model.canStartNewScan else { return }
        model.startScan(path: url.path)
    }
}
