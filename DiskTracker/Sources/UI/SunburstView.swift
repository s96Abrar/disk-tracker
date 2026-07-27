//
//  SunburstView.swift
//  DiskTracker
//
//  Phase 2: Enhanced sunburst visualization with Canvas.
//  Multi-level radial layout with click-to-zoom, hover feedback.
//

import SwiftUI

struct SunburstView: View {
    @ObservedObject var model: AppModel
    @State private var hoveredSegment: Int? = nil
    @State private var zoomLevel: Int = 0

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

            Canvas { context, canvasSize in
                // Demo data - in Phase 3 this will come from model.rootNode
                let segments = buildSegmentsFromTree(root: model.rootNode, center: center, maxRadius: maxRadius)

                for (index, segment) in segments.enumerated() {
                    var path = Path()
                    
                    // Create arc segment
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

                    // Fill with color
                    let isHovered = hoveredSegment == index
                    let opacity = isHovered ? 1.0 : 0.75
                    context.fill(
                        path,
                        with: .color(segment.color.opacity(opacity))
                    )

                    // Stroke
                    context.stroke(
                        path,
                        with: .color(.white.opacity(isHovered ? 0.8 : 0.3)),
                        lineWidth: isHovered ? 2 : 1
                    )

                    // Draw label for large enough segments
                    if segment.size > 0.05 {
                        let midAngle = (segment.startAngle + segment.endAngle) / 2
                        let midRadius = (segment.innerRadius + segment.outerRadius) / 2
                        let labelX = center.x + midRadius * cos(midAngle * .pi / 180)
                        let labelY = center.y + midRadius * sin(midAngle * .pi / 180)

                        let text = Text(segment.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                        
                        context.draw(text, at: CGPoint(x: labelX, y: labelY), anchor: .center)
                    }
                }

                // Center text
                let centerText = Text(formatBytes(model.scanState.totalSize))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                context.draw(centerText, at: center, anchor: .center)

                let subtext = Text("\(model.scanState.fileCount) items")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                context.draw(subtext, at: CGPoint(x: center.x, y: center.y + 18), anchor: .center)
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        // Hit testing would go here
                    }
            )
            
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func buildSegmentsFromTree(root: DiskNode?, center: CGPoint, maxRadius: CGFloat) -> [SunburstSegment] {
        guard let root = root else { return [] }

        var segments: [SunburstSegment] = []
        var currentAngle: Double = 0
        let totalAngle: Double = 360
        let totalSize = (root.fileKind == .directory ? root.totalPhysicalSize : root.physicalSize) > 0 ? Double(root.fileKind == .directory ? root.totalPhysicalSize : root.physicalSize) : 1.0

        // Root segment at center
        segments.append(SunburstSegment(
            label: root.name,
            startAngle: 0,
            endAngle: 360,
            innerRadius: 0,
            outerRadius: maxRadius * 0.2,
            color: colors[.directory] ?? .gray,
            size: 1.0
        ))

        // Process children
        if let children = root.children {
            for child in children {
                let childSize = totalSize > 0 ? Double(child.physicalSize) / totalSize : 0
                let endAngle = currentAngle + totalAngle * childSize

                segments.append(SunburstSegment(
                    label: child.name,
                    startAngle: currentAngle,
                    endAngle: endAngle,
                    innerRadius: maxRadius * 0.2,
                    outerRadius: maxRadius * 0.6,
                    color: colors[child.fileKind] ?? .gray,
                    size: childSize
                ))

                currentAngle = endAngle
            }
        }

        return segments
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
