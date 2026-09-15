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

    /// Rows thinner than this are not worth breaking out; the squarified
    /// algorithm keeps packing into the current row until it reaches this.
    private static let minRowThickness: CGFloat = 20

    /// Test seam: the layout is the behaviour worth asserting on, and driving
    /// it through a rendered Canvas would prove far less.
    func layoutForTesting(in size: CGSize) -> [TreemapRect] {
        calculateSquarifiedLayout(in: size)
    }

    private func calculateSquarifiedLayout(in size: CGSize) -> [TreemapRect] {
        guard size.width > 0, size.height > 0 else { return [] }

        let items = visibleItems(in: size)
        guard !items.isEmpty else { return [] }

        var rects: [TreemapRect] = []
        rects.reserveCapacity(items.count)
        var bounds = CGRect(origin: .zero, size: size)

        // A cursor rather than `remaining.removeFirst(n)`: dropping from the
        // front of an array shifts every remaining element, once per row.
        var cursor = items.startIndex

        // Running total of everything not yet placed, carried across rows.
        // Re-summing the tail on each row was the same O(n) walk repeated.
        var remainingValue = items.reduce(0.0) { $0 + $1.value }

        while cursor < items.endIndex, remainingValue > 0 {
            let isHorizontal = bounds.width >= bounds.height
            let crossLength = isHorizontal ? bounds.height : bounds.width

            // Grow the row until it is thick enough to be worth drawing.
            var rowEnd = cursor
            var rowSum = 0.0
            while rowEnd < items.endIndex {
                let candidateSum = rowSum + items[rowEnd].value
                let thickness = crossLength * (candidateSum / remainingValue)
                // One item always goes in, however thin — otherwise a single
                // dominant tile leaves an empty row and the loop never advances.
                if rowEnd > cursor, thickness >= Self.minRowThickness, rowSum > 0 {
                    break
                }
                rowSum = candidateSum
                rowEnd = items.index(after: rowEnd)
                if thickness >= Self.minRowThickness { break }
            }
            guard rowEnd > cursor, rowSum > 0 else { break }

            let rowThickness = crossLength * (rowSum / remainingValue)
            let alongLength = isHorizontal ? bounds.width : bounds.height
            var offset: CGFloat = 0

            for i in cursor..<rowEnd {
                let item = items[i]
                // `rowSum` is hoisted: computing it per item made laying out a
                // row quadratic in its own length.
                let itemSize = alongLength * (item.value / rowSum)
                let rect = isHorizontal
                    ? CGRect(x: bounds.minX + offset, y: bounds.minY,
                             width: itemSize, height: rowThickness)
                    : CGRect(x: bounds.minX, y: bounds.minY + offset,
                             width: rowThickness, height: itemSize)
                offset += itemSize

                rects.append(TreemapRect(
                    x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                    label: item.label, color: item.color, node: item.node))
            }

            bounds = isHorizontal
                ? CGRect(x: bounds.minX, y: bounds.minY + rowThickness,
                         width: bounds.width, height: bounds.height - rowThickness)
                : CGRect(x: bounds.minX + rowThickness, y: bounds.minY,
                         width: bounds.width - rowThickness, height: bounds.height)

            remainingValue -= rowSum
            cursor = rowEnd

            // Out of room: anything left would be drawn at zero size anyway.
            if bounds.width <= 0 || bounds.height <= 0 { break }
        }
        return rects
    }

    /// Items worth laying out, largest first.
    ///
    /// A folder with 200k immediate children would otherwise produce 200k
    /// tiles, almost all of them below a pixel — the whole cost of a frame
    /// spent on marks nobody can see.
    ///
    /// The area a tile receives is its share of the canvas, so the cut can be
    /// made from the weights alone. That matters for more than layout time:
    /// `DiskNode` is a large value type holding two strings and an array, so
    /// filtering or mapping the node list copies every element and pays ARC
    /// traffic on each. Working out the threshold first, then building a
    /// `TreemapItem` only for survivors, keeps the copies proportional to what
    /// is drawn rather than to what was scanned.
    private func visibleItems(in size: CGSize) -> [TreemapItem] {
        guard let root = model.rootNode else { return [] }

        // The tiles are the root's *children* — the root itself is the canvas.
        guard let children = root.children, !children.isEmpty else {
            let value = weight(root)
            guard value > 0 else { return [] }
            return [TreemapItem(label: root.name, value: value,
                                color: colors[root.fileKind] ?? .gray, node: root)]
        }

        // Pass 1: total. Reads fields in place — passing each node to
        // `weight(_:)` copies a struct holding two strings and an array.
        var total = 0.0
        for i in children.indices { total += weight(children, i) }
        guard total > 0 else { return [] }

        // A tile's area is its share of the canvas, so the smallest weight that
        // can fill `minTileSide` squared follows directly.
        let canvasArea = Double(size.width * size.height)
        guard canvasArea > 0 else { return [] }
        let minValue = Double(Self.minTileSide * Self.minTileSide) * total / canvasArea

        // Pass 2: indices of the survivors. Indices are cheap to sort; nodes
        // are not.
        var keep: [Int] = []
        for i in children.indices where weight(children, i) >= minValue {
            keep.append(i)
        }
        guard !keep.isEmpty else { return [] }
        keep.sort { weight(children, $0) > weight(children, $1) }

        // Pass 3: build items only for what will be drawn.
        return keep.map { i in
            let child = children[i]
            return TreemapItem(label: child.name, value: weight(children, i),
                               color: colors[child.fileKind] ?? .gray, node: child)
        }
    }

    /// Directories carry their weight in `totalPhysicalSize`; their own
    /// `physicalSize` is just the directory entry.
    private func weight(_ node: DiskNode) -> Double {
        Double(node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize)
    }

    /// Weight of `children[index]` without copying the element — see the note
    /// in `visibleItems`.
    @inline(__always)
    private func weight(_ children: [DiskNode], _ index: Int) -> Double {
        Double(children[index].fileKind == .directory
               ? children[index].totalPhysicalSize
               : children[index].physicalSize)
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

