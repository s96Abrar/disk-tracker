//
//  DirectoryListView.swift
//  DiskTracker
//
//  Phase 2: Enhanced directory list with OutlineGroup and size columns.
//

import SwiftUI

struct DirectoryListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // Phase 3: Will use model.rootNode with OutlineGroup
        // For now, show demo data
        List {
            Section {
                ForEach(demoItems) { item in
                    DirectoryRowView(item: item, model: model)
                }
            } header: {
                HStack {
                    Text("Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Size")
                        .frame(width: 100, alignment: .trailing)
                    Text("Items")
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var demoItems: [DemoItem] {
        [
            DemoItem(name: "Home", path: "/Users/abrar", size: 42_000_000_000, itemCount: 128_000, kind: .directory, depth: 0),
            DemoItem(name: "Applications", path: "/Applications", size: 15_000_000_000, itemCount: 450, kind: .application, depth: 0),
            DemoItem(name: "Library", path: "/Library", size: 8_000_000_000, itemCount: 25_000, kind: .directory, depth: 0),
            DemoItem(name: "System", path: "/System", size: 12_000_000_000, itemCount: 15_000, kind: .directory, depth: 0),
        ]
    }
}

struct DemoItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: UInt64
    let itemCount: Int
    let kind: FileKind
    let depth: Int
}

struct DirectoryRowView: View {
    let item: DemoItem
    @ObservedObject var model: AppModel
    @State private var isExpanded = false

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

    var body: some View {
        HStack(spacing: 8) {
            // Indent based on depth
            if item.depth > 0 {
                Spacer()
                    .frame(width: CGFloat(item.depth * 16))
            }

            // Expand/collapse for directories
            if item.kind == .directory {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
                    .frame(width: 16)
            }

            // Icon
            Circle()
                .fill(colorForKind(item.kind))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: iconForKind(item.kind))
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                )

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Size
            Text(formatBytes(item.size))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            // Item count
            Text("\(item.itemCount)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // Select this item
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
