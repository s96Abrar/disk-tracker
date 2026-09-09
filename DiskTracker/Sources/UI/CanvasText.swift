//
//  CanvasText.swift
//  DiskTracker
//
//  Single-line text fitting for Canvas drawing, shared by the sunburst and the
//  treemap.
//
//  Canvas resolves a `Text`, not a `View`, so `.lineLimit(1)` and
//  `.truncationMode(.middle)` are unavailable: an unconstrained `ResolvedText`
//  wraps to as many lines as the proposed width allows. A wrapped four-line
//  file name is taller than the wedge or tile that holds it, so labels either
//  spilled across their neighbours or were dropped entirely. Fitting the string
//  to one line up front is what keeps them readable.
//

import SwiftUI

enum CanvasText {

    /// Middle-truncate `text` to `count` characters, ellipsis included.
    /// Middle rather than tail because file names differ at the end far more
    /// often than at the start ("…S01E03.mp4" vs "Genius.S03E…").
    static func middleTruncated(_ text: String, to count: Int) -> String {
        guard count > 1 else { return "…" }
        guard text.count > count else { return text }
        let head = (count - 1) / 2
        let tail = count - 1 - head
        return "\(text.prefix(head))…\(text.suffix(tail))"
    }
}

extension GraphicsContext {

    /// Resolve `label` as a single line no wider than `maxWidth`,
    /// middle-truncating as needed. Returns nil when not even a truncated stub
    /// fits, which is the caller's cue to skip the label.
    func fittedLine(
        _ label: String,
        maxWidth: CGFloat,
        font: Font,
        color: Color
    ) -> (text: ResolvedText, size: CGSize)? {
        guard maxWidth > 8, !label.isEmpty else { return nil }
        // Large but finite: an infinite proposal makes measurement undefined.
        let unbounded = CGSize(width: 10_000, height: 10_000)

        var candidate = label
        // Converges in one or two passes; the cap is just a stop against a
        // pathological font where the estimate never settles.
        for _ in 0..<4 {
            let resolved = resolve(Text(candidate).font(font).foregroundColor(color))
            let size = resolved.measure(in: unbounded)
            if size.width <= maxWidth { return (resolved, size) }

            // Scale the character budget by how far over we are.
            let budget = Int(Double(candidate.count) * Double(maxWidth / size.width)) - 1
            guard budget >= 5, budget < candidate.count else { return nil }
            candidate = CanvasText.middleTruncated(label, to: budget)
        }
        return nil
    }
}
