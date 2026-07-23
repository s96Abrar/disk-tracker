//
//  SidebarView.swift
//  DiskTracker
//
//  Phase 2: Enhanced sidebar with volume selection and scan history.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @State private var volumes: [DiskVolume] = []

    var body: some View {
        List {
            // Quick scan section
            Section("Quick Scan") {
                ForEach(["/", "/Users", "/Applications"], id: \.self) { path in
                    Button {
                        model.startScan(path: path)
                    } label: {
                        HStack {
                            Image(systemName: pathIcon(for: path))
                            Text(path)
                            Spacer()
                            if case .scanning = model.scanState {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }

            // Volumes section
            Section("Volumes") {
                ForEach(volumes) { volume in
                    VolumeRow(volume: volume, model: model)
                }
            }

            // Scan history (wired via ScanHistoryService)
            Section("History") {
                if let last = model.scanHistory.mostRecentScan {
                    HStack {
                        Image(systemName: "clock")
                        VStack(alignment: .leading) {
                            Text(last.scanDate, style: .relative)
                            Text("Last scan")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Image(systemName: "list.bullet")
                        VStack(alignment: .leading) {
                            Text("\(model.scanHistory.entries.count) scans")
                                .font(.caption)
                            Text("\(formatBytes(model.scanHistory.totalBytesScanned)) total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No scan history")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            // Status section
            Section("Status") {
                switch model.scanState {
                case .idle:
                    Label("Ready to scan", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                case .scanning(let progress):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scanning…")
                            .font(.caption)
                        ProgressView(value: progress)
                            .frame(height: 4)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case .completed(let total, let count):
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Scan complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        HStack {
                            Text(formatBytes(total))
                                .font(.caption)
                            Text("·")
                            Text("\(count) items")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                case .failed(let error):
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // File type breakdown from real tree stats (was hardcoded dummy data)
            if case .completed = model.scanState {
                Section("Breakdown") {
                    FileTypeRow(kind: .directory, size: model.treeStats.fileTypeSizes[.directory] ?? 0, color: Color(hex: "2C3E50"))
                    FileTypeRow(kind: .image, size: model.treeStats.fileTypeSizes[.image] ?? 0, color: Color(hex: "FF6B6B"))
                    FileTypeRow(kind: .video, size: model.treeStats.fileTypeSizes[.video] ?? 0, color: Color(hex: "9B59B6"))
                    FileTypeRow(kind: .document, size: model.treeStats.fileTypeSizes[.document] ?? 0, color: Color(hex: "3498DB"))
                    FileTypeRow(kind: .application, size: model.treeStats.fileTypeSizes[.application] ?? 0, color: Color(hex: "E74C3C"))
                    FileTypeRow(kind: .archive, size: model.treeStats.fileTypeSizes[.archive] ?? 0, color: Color(hex: "27AE60"))
                    FileTypeRow(kind: .other, size: model.treeStats.fileTypeSizes[.other] ?? 0, color: Color(hex: "95A5A6"))
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 220)
        .task {
            volumes = DiskVolumeService.mountedVolumes()
        }
    }

    private func pathIcon(for path: String) -> String {
        switch path {
        case "/": return "internaldrive"
        case "/Users": return "house"
        case "/Applications": return "app"
        default: return "folder"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct VolumeRow: View {
    let volume: DiskVolume
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.isRemovable ? "externaldrive" : "internaldrive")
                .foregroundStyle(volume.isReadOnly ? .orange : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(formatBytes(volume.availableCapacity)) free")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Usage indicator
            CircularProgressView(fraction: volume.usageFraction)
                .frame(width: 28, height: 28)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            model.startScan(path: volume.url.path)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct CircularProgressView: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(
                    fraction > 0.9 ? Color.red : fraction > 0.7 ? Color.orange : Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(fraction * 100))")
                .font(.system(size: 8, weight: .medium, design: .rounded))
        }
    }
}

struct FileTypeRow: View {
    let kind: FileKind
    let size: UInt64
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(kindName)

            Spacer()

            Text(formatBytes(size))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var kindName: String {
        switch kind {
        case .directory: return "Directories"
        case .image: return "Images"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .document: return "Documents"
        case .archive: return "Archives"
        case .application: return "Applications"
        case .other: return "Other"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
