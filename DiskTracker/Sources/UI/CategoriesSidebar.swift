//
//  CategoriesSidebar.swift
//  DiskTracker
//
//  Categories sidebar shown on Scan Results. Mirrors the sunburst mock:
//  title "Disk Tracker", category rows (Directories / Images / Videos /
//  Documents / Applications / Archives / Other) with item counts derived
//  from the current tree's `treeStats`.
//

import SwiftUI

struct CategoriesSidebar: View {
    var model: AppModel

    /// Back navigation (parallels `StatusBar`'s Back button but lives here
    /// in the sidebar so the user can always find it).
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            title
            navBack
            categoryList
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(width: 240)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Disk Tracker")
                .font(.system(size: 18, weight: .semibold))
            Rectangle()
                .fill(Color.brandAccent)
                .frame(width: 32, height: 3)
                .clipShape(Capsule())
        }
        .padding(.bottom, Spacing.sm)
    }

    private var navBack: some View {
        Button(action: onBack) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
                Text("Dashboard")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ScanCategory.allCases) { category in
                categoryRow(category)
            }
        }
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private func categoryRow(_ category: ScanCategory) -> some View {
        let isSelected = model.selectedCategory == category
        let count = model.itemCount(for: category)

        Button {
            model.selectedCategory = category
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.brandAccent : .secondary)
                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.brandAccent.opacity(0.18)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
