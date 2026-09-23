//
//  DevCachesSheet.swift
//  DiskTracker
//
//  Where developer-tool caches are spending space, with a way to trash them.
//  Trashing goes through the same DeletionController and confirmation as the
//  scan views.
//

import SwiftUI
import AppKit

struct DevCachesSheet: View {
    var model: AppModel
    var onClose: () -> Void

    @State private var deletion = DeletionController()
    /// Held while the sheet is open: measuring and trashing both need it.
    @State private var homeGrant = ScopedAccess.access(path: DevCaches.realHome)
    @State private var items: [DevCaches.Measured]?
    @State private var selected: Set<String> = []

    private var total: UInt64 { (items ?? []).reduce(0) { $0 + $1.node.totalPhysicalSize } }
    private var selection: [DevCaches.Measured] { (items ?? []).filter { selected.contains($0.id) } }
    private var selectionSize: UInt64 { selection.reduce(0) { $0 + $1.node.totalPhysicalSize } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Developer Caches", systemImage: "hammer")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.md)

            Divider()

            content
        }
        .frame(width: 640, height: 520)
        .deletionConfirmation(deletion, model: model)
        .task { if homeGrant != nil { await measure() } }
        // Dialog closed: drop whatever went to Trash. No re-measure — a cancel
        // would re-scan every cache for nothing.
        .onChange(of: deletion.isConfirming) { _, confirming in
            guard !confirming, let current = items else { return }
            items = current.filter { FileManager.default.fileExists(atPath: $0.cache.path) }
            selected.formIntersection(items?.map(\.id) ?? [])
        }
    }

    @ViewBuilder
    private var content: some View {
        if homeGrant == nil {
            EmptyState(
                icon: "lock",
                title: "Home Folder Access Needed",
                message: "The caches live in your home folder, which the app can't see until you allow it once.",
                action: {
                    guard FolderPicker.grantHomeAccess() else { return }
                    homeGrant = ScopedAccess.access(path: DevCaches.realHome)
                    Task { await measure() }
                },
                actionLabel: "Allow Access…",
                actionIcon: "lock.open"
            )
        } else if let items {
            if items.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "No Developer Caches",
                           message: "None of the known cache folders exist.")
            } else {
                summary(items)
                Divider()
                List {
                    ForEach(DevTool.allCases, id: \.self) { tool in
                        let rows = items.filter { $0.cache.tool == tool }
                        if !rows.isEmpty {
                            Section(tool.rawValue) {
                                ForEach(rows) { row($0) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                Divider()
                footer
            }
        } else {
            ProgressView("Measuring caches…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Summary

    /// Total plus one bar split by tool — the at-a-glance answer.
    private func summary(_ items: [DevCaches.Measured]) -> some View {
        let byTool = DevTool.allCases.map { tool in
            (tool, items.filter { $0.cache.tool == tool }.reduce(0) { $0 + $1.node.totalPhysicalSize })
        }.filter { $0.1 > 0 }

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(humanReadableBytes(total))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                Text("in developer caches")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(byTool, id: \.0) { tool, size in
                        Rectangle()
                            .fill(tool.color)
                            .frame(width: max(2, geo.size.width * CGFloat(size) / CGFloat(max(total, 1))))
                            .help("\(tool.rawValue): \(humanReadableBytes(size))")
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            HStack(spacing: Spacing.sm) {
                ForEach(byTool, id: \.0) { tool, size in
                    HStack(spacing: 4) {
                        Circle().fill(tool.color).frame(width: 7, height: 7)
                        Text("\(tool.rawValue) \(humanReadableBytes(size))")
                    }
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(Spacing.md)
    }

    // MARK: - Row

    private func row(_ item: DevCaches.Measured) -> some View {
        let size = item.node.totalPhysicalSize
        let isOn = Binding(
            get: { selected.contains(item.id) },
            set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }
        )
        return HStack(spacing: Spacing.sm) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .disabled(!item.cache.trashable)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.cache.label).font(.system(size: 12, weight: .medium))
                    if let warning = item.cache.warning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(warning)
                    }
                }
                Text("~/" + item.cache.relativePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let command = item.cache.command {
                    HStack(spacing: 4) {
                        Text(item.cache.trashable ? "Or run in Terminal:" : "Clean up in Terminal:")
                        Text(command).font(.system(size: 10, design: .monospaced))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy command")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(humanReadableBytes(size))
                    .font(.system(size: 11, design: .monospaced))
                GeometryReader { geo in
                    Capsule()
                        .fill(item.cache.tool.color)
                        .frame(width: max(2, geo.size.width * CGFloat(size) / CGFloat(max(total, 1))))
                }
                .frame(width: 90, height: 4)
            }

            Button {
                FileOperationsService.shared.showInFinder(url: URL(fileURLWithPath: item.cache.path))
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(selection.isEmpty
                 ? "Everything here is rebuilt by its tool on next use, except Archives."
                 : "\(selection.count) selected · \(humanReadableBytes(selectionSize))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Move to Trash…", role: .destructive) {
                deletion.requestDelete(selection.map(\.node))
            }
            .disabled(selection.isEmpty)
        }
        .padding(Spacing.md)
    }

    // MARK: - Measuring

    private func measure() async {
        items = nil
        let measured = await Task.detached(priority: .userInitiated) { DevCaches.measure() }.value
        guard let measured else {
            homeGrant = nil  // bookmark went stale; ask again
            return
        }
        items = measured
        selected.formIntersection(measured.map(\.id))
    }
}

private extension DevTool {
    var color: Color {
        switch self {
        case .homebrew: return .fileAudio
        case .javascript: return .fileImage
        case .python: return .fileDocument
        case .rust: return .fileApplication
        case .gradle: return .fileArchive
        case .android: return .brandOK
        case .xcode: return .brandAccent
        case .simulator: return .fileVideo
        }
    }
}
