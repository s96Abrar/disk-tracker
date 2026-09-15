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

    /// Index of the tile under the cursor. Also tells the context menu which
    /// node was right-clicked — a Canvas has no per-tile view to attach one to.
    @State private var hoveredIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let layout = calculateSquarifiedLayout(in: geometry.size)

            Canvas { context, _ in
                for (index, item) in layout.enumerated() {
                    let rect = item.frame
                    let path = Path(roundedRect: rect, cornerRadius: 4)

                    let isHovered = hoveredIndex == index
                    context.fill(path, with: .color(item.color.opacity(isHovered ? 1.0 : 0.85)))
                    context.stroke(
                        path,
                        with: .color(.white.opacity(isHovered ? 0.9 : 0.4)),
                        lineWidth: isHovered ? 2 : 1
                    )

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
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    // Only write on a real change: every mouse-move pixel would
                    // otherwise invalidate the body and redraw every tile.
                    let hit = layout.firstIndex { $0.frame.contains(location) }
                    if hit != hoveredIndex { hoveredIndex = hit }
                case .ended:
                    if hoveredIndex != nil { hoveredIndex = nil }
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { event in
                    guard let hit = layout.first(where: { $0.frame.contains(event.location) }),
                          let node = hit.node else { return }
                    model.selectNode(node)
                }
            )
            .nodeActions(model: model) {
                hoveredIndex.flatMap { layout.indices.contains($0) ? layout[$0].node : nil }
            }
            .onChange(of: model.rootNode) { _, _ in
                hoveredIndex = nil
            }
        }
    }

    /// A tile smaller than this on either side is a sliver: unreadable,
    /// unclickable, and indistinguishable from its own border.
    private static let minTileSide: CGFloat = 5

    /// Test seam: the layout is the behaviour worth asserting on, and driving
    /// it through a rendered Canvas would prove far less.
    func layoutForTesting(in size: CGSize) -> [TreemapRect] {
        calculateSquarifiedLayout(in: size)
    }

    private func calculateSquarifiedLayout(in size: CGSize) -> [TreemapRect] {
        guard size.width > 0, size.height > 0 else { return [] }

        let items = visibleItems(in: size)
        
        var rects: [TreemapRect] = []
        var remaining = items
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
                rects.append(TreemapRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, label: item.label, color: item.color, node: item.node))
            }

            if isHorizontal {
                bounds = CGRect(x: bounds.minX, y: bounds.minY + rowThickness, width: bounds.width, height: bounds.height - rowThickness)
            } else {
                bounds = CGRect(x: bounds.minX + rowThickness, y: bounds.minY, width: bounds.width - rowThickness, height: bounds.height)
            }
        }
        return rects
    }

    /// Items worth laying out, largest first.
    ///
    /// A folder with 200k immediate children would otherwise produce 200k
    /// tiles, almost all of them below a pixel — the whole cost of a frame
    /// spent on marks nobody can see. Culling here rather than at draw time
    /// also keeps the layout loop short.
    ///
    /// The area a tile receives is its share of the canvas, so the cut can be
    /// made from the weights alone, before any rectangle exists. Squarified
    /// layout keeps tiles roughly square, so a tile below `minTileSide`
    /// squared is below `minTileSide` on at least one side.
    private func visibleItems(in size: CGSize) -> [TreemapItem] {
        let all = buildTreemapItems(from: model.rootNode, colors: colors)
            .sorted { $0.value > $1.value }

        let total = all.reduce(0.0) { $0 + $1.value }
        guard total > 0 else { return [] }

        let canvasArea = Double(size.width * size.height)
        let minArea = Double(Self.minTileSide * Self.minTileSide)

        // Sorted largest-first, so the first tile too small ends the list.
        if let cut = all.firstIndex(where: { ($0.value / total) * canvasArea < minArea }) {
            return Array(all[..<cut])
        }
        return all
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
            return [TreemapItem(label: root.name, value: weight(root), color: colors[root.fileKind] ?? .gray, node: root)]
        }

        return children
            .filter { weight($0) > 0 }
            .map { TreemapItem(label: $0.name, value: weight($0), color: colors[$0.fileKind] ?? .gray, node: $0) }
    }
}

struct TreemapItem {
    let label: String
    let value: Double
    let color: Color
    /// The node this tile stands for, so a click has something to act on.
    /// Layout used to carry only a label, which made every tile inert.
    var node: DiskNode?
}

struct TreemapRect {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let label: String
    let color: Color
    var node: DiskNode?

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

