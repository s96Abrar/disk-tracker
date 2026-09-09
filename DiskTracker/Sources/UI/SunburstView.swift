//
//  SunburstView.swift
//  DiskTracker
//
//  Multi-ring radial layout drawn with Canvas. Click a wedge to drill into it,
//  click the centre to go back up. Labels are measured before they are drawn,
//  so they never overlap their neighbours.
//

import SwiftUI

struct SunburstView: View {
    var model: AppModel

    /// Index into the currently rendered segment list.
    @State private var hoveredIndex: Int? = nil

    /// Node the rings are currently centred on. nil = the scan root.
    @State private var focusNode: DiskNode? = nil

    // Color palette for file types
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
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = size / 2 - 40
            // Computed in body so it can never go stale behind the tree it
            // draws. Hover only re-renders when the hovered wedge changes.
            let segments = SunburstLayout.build(root: currentRoot, maxRadius: maxRadius, colors: colors)

            ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for (index, segment) in segments.enumerated() {
                    let path = wedgePath(segment, center: center)
                    let isHovered = hoveredIndex == index

                    context.fill(path, with: .color(segment.color.opacity(isHovered ? 1.0 : 0.75)))
                    context.stroke(
                        path,
                        with: .color(.white.opacity(isHovered ? 0.8 : 0.3)),
                        lineWidth: isHovered ? 2 : 1
                    )

                    if segment.innerRadius > 0 {
                        drawLabel(segment, in: context, center: center)
                    }
                }

                drawCentre(in: context, at: center, radius: centreRadius(maxRadius))
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    // Only write when it actually changes — otherwise every
                    // mouse-move pixel invalidates the body.
                    let hit = segments.firstIndex { $0.contains(location, center: center) }
                    if hit != hoveredIndex { hoveredIndex = hit }
                case .ended:
                    if hoveredIndex != nil { hoveredIndex = nil }
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        handleTap(at: event.location, center: center, maxRadius: maxRadius, segments: segments)
                    }
            )
            .onChange(of: model.rootNode) { _, _ in
                // A new scan invalidates whatever we were zoomed into.
                focusNode = nil
                hoveredIndex = nil
            }

            if let index = hoveredIndex, segments.indices.contains(index),
               let node = segments[index].node, let root = currentRoot {
                let anchor = tooltipOrigin(for: segments[index], center: center, canvas: geometry.size)
                SunburstTooltip(node: node, share: SunburstLayout.fraction(of: node, in: root), rootName: root.name)
                    .frame(width: Self.tooltipWidth, alignment: .leading)
                    .offset(x: anchor.x, y: anchor.y)
                    // The card sits over the chart; letting it take hits would
                    // cancel the very hover that is showing it.
                    .allowsHitTesting(false)
            }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Tooltip

    static let tooltipWidth: CGFloat = 240
    /// Clamping only needs an upper bound; the card lays out shorter than this
    /// when it has no date or item count to show.
    private static let tooltipMaxHeight: CGFloat = 130

    /// Anchors the card just outside the hovered wedge, then keeps it fully
    /// inside the canvas. Derived from the wedge, not the pointer, so moving
    /// within one wedge doesn't re-render the chart.
    private func tooltipOrigin(for segment: SunburstSegment, center: CGPoint, canvas: CGSize) -> CGPoint {
        let midAngle = (segment.startAngle + segment.endAngle) / 2 * .pi / 180
        let x = center.x + (segment.outerRadius + 16) * cos(midAngle) - Self.tooltipWidth / 2
        let y = center.y + (segment.outerRadius + 16) * sin(midAngle) - Self.tooltipMaxHeight / 2

        return CGPoint(
            x: min(max(8, x), max(8, canvas.width - Self.tooltipWidth - 8)),
            y: min(max(8, y), max(8, canvas.height - Self.tooltipMaxHeight - 8))
        )
    }

    // MARK: - Interaction

    private var currentRoot: DiskNode? { focusNode ?? model.rootNode }

    private func handleTap(at location: CGPoint, center: CGPoint, maxRadius: CGFloat, segments: [SunburstSegment]) {
        let distance = hypot(location.x - center.x, location.y - center.y)

        // Centre disc = "go up one level".
        if distance <= centreRadius(maxRadius) {
            guard let root = model.rootNode, let focus = focusNode else { return }
            let up = parent(of: focus, in: root)
            // Normalise "back at the scan root" to nil, so the view knows it is
            // no longer zoomed and drops the "go up" hint.
            focusNode = (up?.path == root.path) ? nil : up
            return
        }

        guard let hit = segments.first(where: { $0.contains(location, center: center) }),
              let node = hit.node else { return }

        model.selectNode(node)
        // Only directories with contents are worth zooming into.
        if node.fileKind == .directory, node.children?.isEmpty == false {
            focusNode = node
        }
    }

    /// Find the parent of `node` by walking from `root`. Returns nil when
    /// `node` is the root, which lands the view back at the scan root.
    private func parent(of node: DiskNode, in root: DiskNode) -> DiskNode? {
        guard let children = root.children else { return nil }
        if children.contains(where: { $0.path == node.path }) { return root }
        for child in children {
            if let found = parent(of: node, in: child) { return found }
        }
        return nil
    }

    // MARK: - Layout

    private func centreRadius(_ maxRadius: CGFloat) -> CGFloat {
        SunburstLayout.centreRadius(maxRadius)
    }

    private func weight(_ node: DiskNode) -> UInt64 {
        SunburstLayout.weight(node)
    }

    private func wedgePath(_ segment: SunburstSegment, center: CGPoint) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: segment.outerRadius,
            startAngle: .degrees(segment.startAngle),
            endAngle: .degrees(segment.endAngle),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: segment.innerRadius,
            startAngle: .degrees(segment.endAngle),
            endAngle: .degrees(segment.startAngle),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    // MARK: - Labels

    /// Draws the wedge label along the radius, but only when it actually fits:
    /// the text is laid out inside the wedge's radial extent (so it truncates
    /// instead of spilling), and it is skipped entirely unless the wedge is
    /// tangentially thicker than a line of text — which is exactly the
    /// condition under which neighbouring labels would collide.
    private func drawLabel(_ segment: SunburstSegment, in context: GraphicsContext, center: CGPoint) {
        let sweep = segment.endAngle - segment.startAngle
        let midAngle = (segment.startAngle + segment.endAngle) / 2
        let midRadius = (segment.innerRadius + segment.outerRadius) / 2

        let radialSpace = segment.outerRadius - segment.innerRadius - 8
        guard radialSpace > 24 else { return }

        guard let label = context.fittedLine(
            segment.label,
            maxWidth: radialSpace,
            font: .system(size: 9, weight: .medium),
            color: .white
        ) else { return }

        // The wedge's tangential thickness is what separates this label from
        // its neighbours; if a line of text is thicker than that, they collide.
        let tangentialSpace = midRadius * CGFloat(sweep) * .pi / 180
        guard tangentialSpace >= label.size.height + 2 else { return }

        let x = center.x + midRadius * cos(midAngle * .pi / 180)
        let y = center.y + midRadius * sin(midAngle * .pi / 180)
        // Keep text upright on the left half of the circle.
        let flipped = midAngle > 90 && midAngle < 270
        let rotation = flipped ? midAngle + 180 : midAngle

        context.drawLayer { layer in
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .degrees(rotation))
            layer.draw(label.text, at: .zero, anchor: .center)
        }
    }

    private func drawCentre(in context: GraphicsContext, at center: CGPoint, radius: CGFloat) {
        let root = currentRoot
        let zoomed = focusNode != nil
        // Stack the lines around the centre so the block stays vertically
        // centred whether or not the "go up" hint is present.
        let titleY = center.y - (zoomed ? 14 : 8)

        let title = Text(humanReadableBytes(root.map(weight) ?? 0))
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.primary)
        context.draw(title, at: CGPoint(x: center.x, y: titleY), anchor: .center)

        // Chord width, not the diameter: the disc is a circle, so a full-width
        // line would poke out of it. Truncated so a long folder name can't.
        if let name = root?.name, !name.isEmpty,
           let fitted = context.fittedLine(
                name,
                maxWidth: radius * 1.4,
                font: .system(size: 11),
                color: .secondary
           ) {
            context.draw(fitted.text, at: CGPoint(x: center.x, y: titleY + 20), anchor: .center)
        }

        if zoomed {
            let hint = Text("click centre to go up")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            context.draw(hint, at: CGPoint(x: center.x, y: titleY + 38), anchor: .center)
        }
    }
}

/// Hover card: what the wedge is, how big, and how much of the current view it
/// accounts for. The wedge label is truncated to fit its ring, so the full name
/// here is the point of the thing.
private struct SunburstTooltip: View {
    let node: DiskNode
    let share: Double
    let rootName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: node.fileKind.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandAccent)
                Text(node.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.3)

            row("Size", humanReadableBytes(SunburstLayout.weight(node)))
            row("Share", "\(percentText) of \(rootName)")
            row("Type", node.fileKind.displayName)

            if node.fileKind == .directory {
                row("Items", "\(node.childCount)")
            }
            if node.modTimeSecs > 0 {
                row("Modified", Date(timeIntervalSince1970: TimeInterval(node.modTimeSecs))
                    .formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(radius: 8, y: 2)
    }

    /// Sub-0.1% slivers read better as "<0.1%" than as "0.0%".
    private var percentText: String {
        let percent = share * 100
        if percent > 0 && percent < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", percent)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Ring geometry for the sunburst. Pure layout, no view state, so it can be
/// tested directly — a silently empty chart is otherwise invisible until
/// someone runs a scan and looks at it.
enum SunburstLayout {

    /// Rings drawn outside the centre disc.
    static let ringCount = 3

    /// Wedges thinner than this are invisible at any realistic window size and
    /// only cost layout + hit-test work.
    static let minSweepDegrees: Double = 0.75

    static func centreRadius(_ maxRadius: CGFloat) -> CGFloat {
        maxRadius / CGFloat(ringCount + 1)
    }

    /// Directories carry their weight in `totalPhysicalSize`; their own
    /// `physicalSize` is just the directory entry and is effectively zero,
    /// which used to collapse every folder wedge to nothing.
    static func weight(_ node: DiskNode) -> UInt64 {
        node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize
    }

    /// `node`'s share of `root`, 0...1. Zero-sized roots (an empty folder, or a
    /// scan that found nothing) would otherwise divide by zero into NaN and
    /// render as "nan%".
    static func fraction(of node: DiskNode, in root: DiskNode) -> Double {
        let total = Double(weight(root))
        guard total > 0 else { return 0 }
        return Double(weight(node)) / total
    }

    static func build(root: DiskNode?, maxRadius: CGFloat, colors: [FileKind: Color]) -> [SunburstSegment] {
        guard let root, maxRadius > 0 else { return [] }

        let ringWidth = centreRadius(maxRadius)
        var segments: [SunburstSegment] = [
            SunburstSegment(
                label: root.name,
                startAngle: 0,
                endAngle: 360,
                innerRadius: 0,
                outerRadius: ringWidth,
                color: colors[.directory] ?? .gray,
                size: 1.0,
                node: root
            )
        ]

        func addRing(_ node: DiskNode, ring: Int, startAngle: Double, sweep: Double) {
            guard ring <= ringCount,
                  let children = node.children,
                  !children.isEmpty else { return }

            let total = children.reduce(0.0) { $0 + Double(weight($1)) }
            guard total > 0 else { return }

            let inner = ringWidth * CGFloat(ring)
            let outer = inner + ringWidth
            var angle = startAngle

            for child in children.sorted(by: { weight($0) > weight($1) }) {
                let fraction = Double(weight(child)) / total
                let childSweep = sweep * fraction
                // Sorted largest-first, so once one is too thin the rest are too.
                if childSweep < minSweepDegrees { break }

                segments.append(SunburstSegment(
                    label: child.name,
                    startAngle: angle,
                    endAngle: angle + childSweep,
                    innerRadius: inner,
                    outerRadius: outer,
                    color: colors[child.fileKind] ?? .gray,
                    size: fraction,
                    node: child
                ))
                addRing(child, ring: ring + 1, startAngle: angle, sweep: childSweep)
                angle += childSweep
            }
        }

        addRing(root, ring: 1, startAngle: 0, sweep: 360)
        return segments
    }
}

struct SunburstSegment: Identifiable {
    let id = UUID()
    let label: String
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let color: Color
    let size: Double
    /// The node this wedge stands for, for selection and drill-down.
    var node: DiskNode? = nil

    /// Polar hit test in the canvas' coordinate space.
    func contains(_ point: CGPoint, center: CGPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius, innerRadius > 0 else { return false }

        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        return angle >= startAngle && angle < endAngle
    }
}

// Extension to expose scan state properties
extension ScanState {
    var totalSize: UInt64 {
        if case .completed(let total, _) = self { return total }
        return 0
    }

    var fileCount: Int {
        if case .completed(_, let count) = self { return count }
        return 0
    }
}
