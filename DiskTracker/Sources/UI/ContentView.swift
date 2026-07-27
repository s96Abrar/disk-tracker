//
//  ContentView.swift
//  DiskTracker
//
//  Phase 3: Enhanced layout with inspector, toolbar, view modes,
//  safety confirmation dialogs, hidden file toggle, and batch operations.
//

import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var scanPath = NSHomeDirectory()
    @State private var showInspector = true

    // Phase 3: Confirmation dialog state
    @State private var showDeleteConfirmation = false
    @State private var nodeToDelete: DiskNode?

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .frame(minWidth: 200, idealWidth: 220)
        } detail: {
            HSplitView {
                // Main content area
                VStack(spacing: 0) {
                    // Enhanced toolbar
                    ToolbarView(
                        scanPath: $scanPath,
                        model: model,
                        showInspector: $showInspector,
                        onDeleteRequested: { node in
                            nodeToDelete = node
                            showDeleteConfirmation = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    // Phase 4: Low-space alert banner
                    if model.freeSpaceMonitor.isAlertShowing,
                       let snap = model.freeSpaceMonitor.snapshot {
                        LowSpaceBanner(level: model.freeSpaceMonitor.alertLevel,
                                       available: snap.availableBytes,
                                       total: snap.totalBytes) {
                            model.freeSpaceMonitor.isAlertShowing = false
                        }
                    }

                    // Phase 4: Smart filter results list (overrides visualization when a filter is active)
                    if model.activeSmartFilter != nil, !model.smartFilterResults.isEmpty {
                        SmartFilterResultsView(
                            model: model,
                            onDeleteRequested: { node in
                                nodeToDelete = node
                                showDeleteConfirmation = true
                            }
                        )
                    } else {
                    // Visualization
                    Group {
                        switch model.currentView {
                        case .sunburst:
                            SunburstView(model: model)
                        case .treemap:
                            TreemapView(model: model)
                        case .list:
                            DirectoryListView(model: model)
                        }
                    }
                    .frame(minWidth: 400, minHeight: 300)
                    }
                }

                // Inspector panel
                if showInspector {
                    InspectorView(
                        model: model,
                        onDeleteRequested: { node in
                            nodeToDelete = node
                            showDeleteConfirmation = true
                        }
                    )
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                }
            }
        }
        .navigationTitle("Disk Tracker")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: showInspector ? "sidebar.right" : "sidebar.right")
                        .symbolVariant(showInspector ? .fill : .none)
                }
                .help("Toggle inspector")

                Button {
                    // Settings
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
        }
        .alert("Move to Trash?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { nodeToDelete = nil }
            Button("Move to Trash", role: .destructive) {
                if let node = nodeToDelete {
                    _ = FileOperationsService.shared.moveToTrash(
                        url: URL(fileURLWithPath: node.path)
                    )
                }
                nodeToDelete = nil
            }
        } message: {
            if let node = nodeToDelete {
                Text("Are you sure you want to move \"\(node.name)\" to the trash?")
            } else {
                Text("Are you sure you want to move this item to the trash?")
            }
        }
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @Binding var scanPath: String
    @ObservedObject var model: AppModel
    @Binding var showInspector: Bool
    var onDeleteRequested: ((DiskNode) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Path selector
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                TextField("Scan Path", text: $scanPath)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 200)

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.title = "Select Folder to Scan"
                    panel.message = "Choose a directory to analyze with Disk Tracker"
                    panel.prompt = "Select"
                    if panel.runModal() == .OK, let url = panel.url {
                        scanPath = url.path
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Scan controls
            if case .scanning(let progress) = model.scanState {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 120)
                        .progressViewStyle(.linear)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)

                    Button {
                        model.cancelScan()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            } else {
                Button {
                    model.startScan(path: scanPath)
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
            }

            Spacer()

            // Phase 3: Hidden file toggle
            Toggle("Hidden Files", isOn: $model.showHiddenFiles)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Show files starting with a dot")

            // Phase 3: Batch mode toggle
            Toggle("Batch", isOn: $model.isBatchMode)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Enable multi-select for batch operations")

            // Phase 4: Smart filters
            Menu {
                Button("None") {
                    model.activeSmartFilter = nil
                    model.smartFilterResults = []
                }
                ForEach(AppModel.SmartFilterKind.allCases) { kind in
                    Button {
                        model.activeSmartFilter = kind
                        model.runSmartFilter()
                    } label: {
                        Label(kind.rawValue, systemImage: kind.icon)
                    }
                }
            } label: {
                Label(model.activeSmartFilter?.rawValue ?? "Smart Filters",
                      systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .disabled(model.rootNode == nil)
            .help("Find large, old, or empty files")

            // View mode picker
            Picker("View", selection: $model.currentView) {
                ForEach(AppModel.ViewMode.allCases) { mode in
                    Label {
                        Text(mode.rawValue)
                    } icon: {
                        Image(systemName: mode.icon)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var model: AppModel
    var onDeleteRequested: ((DiskNode) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Details")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let node = model.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Name and icon
                        HStack(spacing: 12) {
                            Circle()
                                .fill(colorForKind(node.fileKind))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: iconForKind(node.fileKind))
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(node.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Divider()

                        // Size info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Size")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Physical")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatBytes(node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize))
                                        .font(.title3)
                                        .fontWeight(.
                                                    semibold)
                                }

                                Spacer()

                                VStack(alignment: .trailing) {
                                    Text("Logical")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatBytes(node.logicalSize))
                                        .font(.body)
                                }
                            }

                            if node.physicalSize != node.logicalSize {
                                let diff = node.logicalSize > node.physicalSize
                                    ? node.logicalSize - node.physicalSize
                                    : node.physicalSize - node.logicalSize
                                Text("Diff: \(formatBytes(diff))")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Divider()

                        // Folder info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Folder Details")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(node.fileKind == .directory ? "\(childCountString(node))" : "—")
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Modified")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(dateModifiedString(from: node.modTimeSecs))
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                        }

                        Divider()

                        // Actions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Actions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Button {
                                    FileOperationsService.shared.showInFinder(
                                        url: URL(fileURLWithPath: node.path)
                                    )
                                } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    FileOperationsService.shared.previewWithQuickLook(
                                        url: URL(fileURLWithPath: node.path)
                                    )
                                } label: {
                                    Label("Quick Look", systemImage: "eye")
                                }
                                .buttonStyle(.bordered)
                            }

                            // Phase 3: Use service-level protection
                            let isProtected = FileOperationsService.shared.isSystemProtected(
                                url: URL(fileURLWithPath: node.path)
                            )
                            if !isProtected {
                                Button(role: .destructive) {
                                    onDeleteRequested?(node)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else {
                                Label("System protected", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "square.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Select an item")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click on the visualization\nto inspect an item")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }

            Spacer()

            // Phase 4: Live free-space indicator
            Divider()
            FreeSpaceIndicator(monitor: model.freeSpaceMonitor)
                .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func dateModifiedString(from secs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(secs))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func childCountString(_ node: DiskNode) -> String {
        guard node.fileKind == .directory else { return "—" }
        return "\(node.childCount)"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func colorForKind(_ kind: FileKind) -> Color {
        switch kind {
        case .image: return Color(hex: "FF6B6B")
        case .video: return Color(hex: "9B59B6")
        case .audio: return Color(hex: "F39C12")
        case .document: return Color(hex: "3498DB")
        case .archive: return Color(hex: "27AE60")
        case .application: return Color(hex: "E74C3C")
        case .directory: return Color(hex: "2C3E50")
        case .other: return Color(hex: "95A5A6")
        }
    }

    private func iconForKind(_ kind: FileKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc"
        case .archive: return "doc.zipper"
        case .application: return "app"
        case .directory: return "folder"
        case .other: return "doc.questionmark"
        }
    }
}
