//
//  SmartFeaturesViews.swift
//  DiskTracker
//
//  Phase 4: Smart filter results list, low-space banner, live free-space indicator.
//  Backed by SmartFilterService + FreeSpaceMonitor.
//

import SwiftUI

private struct SortHeaderButton: View {
    let title: String
    let sortKey: AppModel.SortKey
    @ObservedObject var model: AppModel
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


// MARK: - Smart Filter Results

/// Lists SmartFilterService results and routes delete requests back to ContentView.
struct SmartFilterResultsView: View {
    @ObservedObject var model: AppModel
    var onDeleteRequested: ((DiskNode) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.smartFilterResults.isEmpty {
                emptyState
            } else {
                resultList
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack {
            Label(model.activeSmartFilter?.rawValue ?? "Smart Filter",
                  systemImage: model.activeSmartFilter?.icon ?? "wand.and.stars")
                .font(.headline)
            SortHeaderButton(title: "Name", sortKey: .name, model: model)
            SortHeaderButton(title: "Size", sortKey: .size, model: model)
            SortHeaderButton(title: "Items", sortKey: .items, model: model)
            SortHeaderButton(title: "Date Modified", sortKey: .dateModified, model: model)
            Spacer()
            Text("\(model.smartFilterResults.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                model.activeSmartFilter = nil
                model.smartFilterResults = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear filter")
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var resultList: some View {
        let sortedResults = model.sortedNodes(model.smartFilterResults.map { $0.node })
        // Note: smart filter results are SmartFilterResult, not DiskNode; sort the underlying nodes
        List(model.smartFilterResults.sorted(by: { a, b in
            switch model.sortKey {
            case .name: return model.sortAscending ? a.node.name.localizedCompare(b.node.name) == .orderedAscending : a.node.name.localizedCompare(b.node.name) == .orderedDescending
            case .size: return model.sortAscending ? a.node.physicalSize < b.node.physicalSize : a.node.physicalSize > b.node.physicalSize
            case .items: return model.sortAscending ? a.node.childCount < b.node.childCount : a.node.childCount > b.node.childCount
            case .dateModified: return model.sortAscending ? a.node.modTimeSecs < b.node.modTimeSecs : a.node.modTimeSecs > b.node.modTimeSecs
            }
        })) { result in
            SmartFilterResultRow(
                result: result,
                isSelected: model.selectedNode?.id == result.node.id,
                onDelete: { onDeleteRequested?(result.node) },
                onSelect: { model.selectNode(result.node) },
                onShowInFinder: { FileOperationsService.shared.showInFinder(url: URL(fileURLWithPath: result.node.path)) }
            )
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This filter found nothing in the scanned tree.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SmartFilterResultRow: View {
    let result: SmartFilterResult
    let isSelected: Bool
    let onDelete: () -> Void
    let onSelect: () -> Void
    let onShowInFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.forFileKind(result.node.fileKind))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: iconForKind(result.node.fileKind))
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.node.name)
                    .font(.body)
                    .lineLimit(1)
                Text(result.node.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(reasonText)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Date Modified column
            Text(dateString(from: result.node.modTimeSecs))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 110, alignment: .trailing)

            if result.matchReason != .emptyFolder && result.node.fileKind != .directory {
                Text(humanReadableBytes(result.node.physicalSize))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }

            Button(action: onShowInFinder) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .tint(.red)
            .help("Move to Trash")
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var reasonText: String {
        switch result.matchReason {
        case .largeFile:   return result.matchReason.rawValue
        case .oldFile:     return "\(result.matchReason.rawValue) · \(ageText)"
        case .emptyFolder: return result.matchReason.rawValue
        case .duplicate:   return result.matchReason.rawValue
        }
    }

    private var ageText: String {
        let secs = max(0, Int64(Date().timeIntervalSince1970) - result.node.modTimeSecs)
        guard secs > 0 else { return "—" }
        let days = secs / 86_400
        if days >= 365 { return "\(days / 365)y ago" }
        if days >= 30 { return "\(days / 30)mo ago" }
        if days > 0  { return "\(days)d ago" }
        let hours = secs / 3_600
        return "\(hours)h ago"
    }


    private func dateString(from secs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(secs))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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

// MARK: - Low Space Banner

/// Alert banner shown when free space drops below the configured threshold.
struct LowSpaceBanner: View {
    let level: FreeSpaceAlertLevel
    let available: UInt64
    let total: UInt64
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(level.description) — \(pct)% free remaining")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(humanReadableBytes(available)) available of \(humanReadableBytes(total))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(barColor)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var pct: Int {
        guard total > 0 else { return 0 }
        return Int(Double(available) / Double(total) * 100)
    }

    private var barColor: Color {
        switch level {
        case .none:     return Color(hex: level.colorHex)
        case .warning:  return Color(hex: "F39C12")
        case .critical: return Color(hex: "E67E22")
        case .emergency:return Color(hex: "E74C3C")
        }
    }
}

// MARK: - Free Space Indicator

/// Live compact readout of the monitored volume's free space.
struct FreeSpaceIndicator: View {
    @ObservedObject var monitor: FreeSpaceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Free Space")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let snap = monitor.snapshot {
                HStack(alignment: .firstTextBaseline) {
                    Text(humanReadableBytes(snap.availableBytes))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("of \(humanReadableBytes(snap.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Gauge(value: snap.usedFraction) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                } minimumValueLabel: {
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } maximumValueLabel: {
                    Text("100%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .gaugeStyle(.accessoryLinear)
                .tint(gaugeTint(snap.alertLevel(thresholdPercent: monitor.thresholdPercent)))

                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(statusColor(snap.alertLevel(thresholdPercent: monitor.thresholdPercent)))
                        .font(.caption2)
                    Text(snap.alertLevel(thresholdPercent: monitor.thresholdPercent).description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let secs = monitor.estimatedSecondsUntilFull {
                        Text("≈ \(formatDuration(secs)) until full")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Not monitoring")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func statusColor(_ level: FreeSpaceAlertLevel) -> Color {
        switch level {
        case .none:     return Color(hex: "27AE60")
        case .warning:  return Color(hex: "F39C12")
        case .critical: return Color(hex: "E67E22")
        case .emergency:return Color(hex: "E74C3C")
        }
    }

    private func gaugeTint(_ level: FreeSpaceAlertLevel) -> Color {
        // ponytail: gauge shows used fraction, so tint shifts as space gets tight.
        switch level {
        case .none:     return Color(hex: "27AE60")
        case .warning:  return Color(hex: "F39C12")
        case .critical: return Color(hex: "E67E22")
        case .emergency:return Color(hex: "E74C3C")
        }
    }

    private func formatDuration(_ secs: TimeInterval) -> String {
        if secs > 86_400 * 30 {
            return "\(Int(secs / 86_400 / 30))mo"
        }
        if secs > 86_400 {
            return "\(Int(secs / 86_400))d"
        }
        if secs > 3_600 {
            return "\(Int(secs / 3_600))h"
        }
        return "\(Int(secs / 60))m"
    }
}
