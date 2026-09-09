//
//  DirectoryListView.swift
//  DiskTracker
//

import SwiftUI

struct DirectoryListView: View {
    var model: AppModel

    var body: some View {
        if let root = model.rootNode {
            List {
                Section {
                    let displayNodes = model.sortedNodes(root.children ?? [])
                    ForEach(displayNodes, id: \.id) { child in
                        DirectoryRowView(node: child, model: model)
                    }
                } header: {
                    HStack(spacing: 4) {
                        SortHeaderButton(title: "Name", sortKey: .name, model: model)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SortHeaderButton(title: "Size", sortKey: .size, model: model)
                            .frame(width: 100, alignment: .trailing)
                        SortHeaderButton(title: "Items", sortKey: .items, model: model)
                            .frame(width: 60, alignment: .trailing)
                        SortHeaderButton(title: "Date Modified", sortKey: .dateModified, model: model)
                            .frame(width: 110, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No scan data")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Scan a folder to see directory contents")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct SortHeaderButton: View {
    let title: String
    let sortKey: AppModel.SortKey
    var model: AppModel

    var body: some View {
        Button {
            model.toggleSort(for: sortKey)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if model.sortKey == sortKey {
                    Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct DirectoryRowView: View {
    let node: DiskNode
    var model: AppModel
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 8) {
            if node.depth > 0 {
                Spacer()
                    .frame(width: CGFloat(node.depth * 16))
            }
            if node.fileKind == .directory && !(node.children?.isEmpty ?? true) {
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
            Circle()
                .fill(colorForKind(node.fileKind))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: iconForKind(node.fileKind))
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body)
                    .lineLimit(1)
                Text(node.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(humanReadableBytes(node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(node.fileKind == .directory ? "\(childCount(of: node))" : "—")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
            Text(dateModifiedString(from: node.modTimeSecs))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectNode(node)
        }
        if isExpanded, let children = node.children {
            ForEach(children) { child in
                DirectoryRowView(node: child, model: model)
            }
        }
    }

    private func dateModifiedString(from secs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(secs))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func childCount(of node: DiskNode) -> Int {
        guard let children = node.children, !children.isEmpty else { return 0 }
        return children.count + children.reduce(0) { $0 + childCount(of: $1) }
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
