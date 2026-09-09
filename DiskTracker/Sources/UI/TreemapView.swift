//
//  TreemapView.swift
//  DiskTracker
//
//  Phase 2: Squarified treemap visualization with Canvas.
//

import SwiftUI

struct TreemapView: View {
    var model: AppModel

    // Color palette for file types (mirrors SunburstView)
    private let colors: [FileKind: Color] = [
        .image: Color(hex: "FF6B6B"),
        .video: Color(hex: "9B59B6"),
        .audio: Color(hex: "F39C12"),
        .document: Color(hex: "3498DB"),
        .archive: Color(hex: "27AE60"),
        .application: Color(hex: "E74C3C"),
        .directory: Color(hex: "2C3E50"),
        .other: Color(hex: "95A5A6"),
    ]

    var body: some View {
        GeometryReader { geometry in
            let layout = calculateSquarifiedLayout(in: geometry.size)

            Canvas { context, _ in
                for item in layout {
                    let rect = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
                    let path = Path(roundedRect: rect, cornerRadius: 4)
                    
                    context.fill(path, with: .color(item.color.opacity(0.85)))
                    context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1)

                    // Draw the label *inside* the rect: clipped so it can never
                    // bleed into a neighbouring tile, and laid out in the tile's
                    // width so long names truncate instead of overflowing.
                    if item.width > 40 && item.height > 20 {
                        let inset = rect.insetBy(dx: 4, dy: 2)
                        guard let label = context.fittedLine(
                            item.label,
                            maxWidth: inset.width,
                            font: .system(size: 10, weight: .medium),
                            color: .white
                        ), label.size.height <= inset.height else { continue }

                        context.drawLayer { layer in
                            layer.clip(to: Path(inset))
                            layer.draw(label.text, at: CGPoint(x: inset.midX, y: inset.midY), anchor: .center)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func calculateSquarifiedLayout(in size: CGSize) -> [TreemapRect] {
        let items = buildTreemapItems(from: model.rootNode, colors: colors)

        guard size.width > 0, size.height > 0 else { return [] }
        
        var rects: [TreemapRect] = []
        var remaining = items.sorted { $0.value > $1.value }
        var bounds = CGRect(origin: .zero, size: size)

        while !remaining.isEmpty {
            let total = remaining.reduce(0) { $0 + $1.value }
            let isHorizontal = bounds.width >= bounds.height
            var row: [TreemapItem] = []
            var rowSum: Double = 0

            for item in remaining {
                row.append(item)
                rowSum += item.value
                let rowFraction = rowSum / total
                let rowThickness = isHorizontal ? bounds.height * rowFraction : bounds.width * rowFraction
                
                if row.count > 1 && rowThickness < 20 {
                    row.removeLast()
                    break
                }
            }

            remaining.removeFirst(row.count)
            let rowFraction = row.reduce(0) { $0 + $1.value } / total
            let rowThickness = isHorizontal ? bounds.height * rowFraction : bounds.width * rowFraction
            var offset: CGFloat = 0

            for item in row {
                let itemFraction = item.value / row.reduce(0) { $0 + $1.value }
                let itemSize = isHorizontal ? bounds.width * itemFraction : bounds.height * itemFraction
                
                let rect: CGRect
                if isHorizontal {
                    rect = CGRect(x: bounds.minX + offset, y: bounds.minY, width: itemSize, height: rowThickness)
                    offset += itemSize
                } else {
                    rect = CGRect(x: bounds.minX, y: bounds.minY + offset, width: rowThickness, height: itemSize)
                    offset += itemSize
                }
                rects.append(TreemapRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, label: item.label, color: item.color))
            }

            if isHorizontal {
                bounds = CGRect(x: bounds.minX, y: bounds.minY + rowThickness, width: bounds.width, height: bounds.height - rowThickness)
            } else {
                bounds = CGRect(x: bounds.minX + rowThickness, y: bounds.minY, width: bounds.width - rowThickness, height: bounds.height)
            }
        }
        return rects
    }

    /// Directories carry their weight in `totalPhysicalSize`; their own
    /// `physicalSize` is just the directory entry.
    private func weight(_ node: DiskNode) -> Double {
        Double(node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize)
    }

    private func buildTreemapItems(from root: DiskNode?, colors: [FileKind: Color]) -> [TreemapItem] {
        guard let root = root else { return [] }

        // The tiles are the root's *children* — the root itself is the canvas.
        // Including it as a sibling of its own children double-counted the tree
        // and left a stray zero-area tile.
        guard let children = root.children, !children.isEmpty else {
            return [TreemapItem(label: root.name, value: weight(root), color: colors[root.fileKind] ?? .gray)]
        }

        return children
            .filter { weight($0) > 0 }
            .map { TreemapItem(label: $0.name, value: weight($0), color: colors[$0.fileKind] ?? .gray) }
    }
}

struct TreemapItem {
    let label: String
    let value: Double
    let color: Color
}

struct TreemapRect {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let label: String
    let color: Color
}

