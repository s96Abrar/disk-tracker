//
//  FilteredResultsView.swift
//  DiskTracker
//
//  Flat result list shown when a sidebar category or the search field narrows
//  the scan. The hierarchy views stay structural — a category cuts across the
//  tree, so there is no folder to descend.
//

import SwiftUI
import AppKit

struct FilteredResultsView: View {
    var model: AppModel

    var body: some View {
        let matches = model.filteredNodes

        VStack(spacing: 0) {
            header(count: matches.count)
            Divider().opacity(0.3)

            if matches.isEmpty {
                emptyState
            } else {
                List(matches, id: \.id) { node in
                    row(node)
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func header(count: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Label(model.selectedCategory.rawValue, systemImage: model.selectedCategory.icon)
                .font(.system(size: 12, weight: .semibold))

            if !model.searchQuery.isEmpty {
                Text("matching “\(model.searchQuery)”")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(countLabel(count))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func countLabel(_ count: Int) -> String {
        count >= AppModel.maxFilterMatches
            ? "first \(count) by size"
            : "\(count) item\(count == 1 ? "" : "s")"
    }

    private func row(_ node: DiskNode) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: node.fileKind.iconName)
                .font(.system(size: 12))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(node.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: Spacing.sm)

            Text(humanReadableBytes(node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { model.selectNode(node) }
        .nodeActions(node, model: model)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.system(size: 13, weight: .semibold))
            Text(model.searchQuery.isEmpty
                 ? "This scan has no \(model.selectedCategory.rawValue.lowercased())."
                 : "Nothing named “\(model.searchQuery)” in \(model.selectedCategory.rawValue.lowercased()).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
