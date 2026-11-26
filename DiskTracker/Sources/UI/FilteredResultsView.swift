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

    /// Every empty result gets a way out: widen the category first, since a
    /// search that fails in one category may hit in the others.
    @ViewBuilder
    private var emptyState: some View {
        let category = model.selectedCategory
        let query = model.searchQuery
        if query.isEmpty {
            EmptyState(icon: "magnifyingglass", title: "No matches",
                       message: "This scan has no \(category.rawValue.lowercased()).",
                       action: { model.selectedCategory = .directories },
                       actionLabel: "Show Everything", actionIcon: "folder")
        } else if category != .directories {
            EmptyState(icon: "magnifyingglass", title: "No matches",
                       message: "Nothing named “\(query)” in \(category.rawValue.lowercased()).",
                       action: { model.selectedCategory = .directories },
                       actionLabel: "Search All Categories", actionIcon: "magnifyingglass")
        } else {
            EmptyState(icon: "magnifyingglass", title: "No matches",
                       message: "Nothing named “\(query)” in this scan. Check the spelling or try part of the name.",
                       action: { model.searchQuery = "" },
                       actionLabel: "Clear Search", actionIcon: "xmark.circle")
        }
    }
}
