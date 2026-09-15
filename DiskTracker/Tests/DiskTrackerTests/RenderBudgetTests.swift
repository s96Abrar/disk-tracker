//
//  RenderBudgetTests.swift
//  DiskTrackerTests
//
//  Frame budget for the two canvases.
//
//  These do NOT measure frames per second, and the timings are not shipping
//  numbers: the test target is built with -Onone, where this kind of tight
//  numeric loop runs an order of magnitude slower than Release. Actual fps
//  needs an Instruments pass against a Release build — see 2_BUILD_PLAN.md §3.
//
//  What they do catch is the class of bug that makes 60fps impossible at any
//  optimisation level: layout whose cost scales with the size of the scan
//  rather than with the marks on screen. A Canvas re-runs layout on every
//  redraw, so an O(n^2) pass over a large directory is unrecoverable however
//  fast the GPU is. That was not hypothetical — these tests were written
//  against a treemap layout taking 5.1 seconds per frame for 50k children.
//
//  So the assertions are about scaling and bounded output, which hold in any
//  configuration. The absolute ceilings are loose regression guards sized for
//  Debug, not statements about shipping performance.
//

import XCTest
@testable import DiskTracker

final class RenderBudgetTests: XCTestCase {

    /// Loose Debug-mode ceiling. 60fps leaves 16.67ms per frame for everything,
    /// and Release runs this roughly an order of magnitude faster, so a Debug
    /// pass under 150ms is comfortably inside the real budget. Tight enough to
    /// catch a return to quadratic layout, loose enough not to fail on a busy
    /// machine.
    private static let debugCeilingSeconds = 0.150

    // MARK: - Fixtures

    /// A tree shaped like a real scan: one dominant folder, a long tail of
    /// small files, and enough breadth to make culling matter.
    private func wideTree(childCount: Int) -> DiskNode {
        var children: [DiskNode] = []
        children.reserveCapacity(childCount)
        for i in 0..<childCount {
            // Sizes spanning orders of magnitude, so the cull lands mid-list
            // rather than keeping or dropping everything.
            let size = UInt64(10_000_000 / (i + 1))
            children.append(DiskNode(
                recordIndex: i, name: "file\(i).dat", path: "/root/file\(i).dat",
                logicalSize: size, physicalSize: size,
                fileKind: i % 3 == 0 ? .directory : .document,
                isSystemProtected: false, modTimeSecs: 0, depth: 1,
                childCount: 0, children: [], totalPhysicalSize: size))
        }
        return DiskNode(
            recordIndex: 0, name: "root", path: "/root",
            logicalSize: 0, physicalSize: 0, fileKind: .directory,
            isSystemProtected: false, modTimeSecs: 0, depth: 0,
            childCount: UInt32(childCount), children: children,
            totalPhysicalSize: children.reduce(0) { $0 + $1.physicalSize })
    }

    private func time(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    // MARK: - Treemap

    func testTreemapLayoutStaysInsideTheFrameBudget() {
        let root = wideTree(childCount: 50_000)
        let size = CGSize(width: 1400, height: 900)

        // Warm once: the first call pays for lazy allocation, not layout.
        _ = TreemapView.layout(of: root, in: size)

        let elapsed = time { _ = TreemapView.layout(of: root, in: size) }
        print("treemap layout, 50k children: \(String(format: "%.2f", elapsed * 1000))ms")

        XCTAssertLessThan(
            elapsed, Self.debugCeilingSeconds,
            "treemap layout took \(String(format: "%.0f", elapsed * 1000))ms in Debug; "
            + "the ceiling is \(String(format: "%.0f", Self.debugCeilingSeconds * 1000))ms. "
            + "This is a complexity guard, not an fps measurement.")
    }

    /// The cull is what makes the budget reachable: without it, layout is
    /// proportional to the child count rather than to the tiles on screen.
    func testTreemapLayoutBarelyGrowsWithHiddenChildren() {
        let root10k = wideTree(childCount: 10_000)
        let root100k = wideTree(childCount: 100_000)
        let size = CGSize(width: 1400, height: 900)

        _ = TreemapView.layout(of: root10k, in: size)
        _ = TreemapView.layout(of: root100k, in: size)

        let small = time { _ = TreemapView.layout(of: root10k, in: size) }
        let large = time { _ = TreemapView.layout(of: root100k, in: size) }
        print("treemap layout: 10k \(String(format: "%.2f", small * 1000))ms, "
              + "100k \(String(format: "%.2f", large * 1000))ms")

        // The assertion that matters, and the one that is configuration
        // independent: 10x the children must not cost 10x the time. The cull
        // bounds the tiles laid out, so the extra work is the linear scan that
        // finds them.
        XCTAssertLessThan(
            large, small * 6,
            "10x the children cost \(String(format: "%.1f", large / small))x the time — "
            + "layout is scaling with the scan instead of with the visible tiles")
    }

    func testTreemapProducesAWorkableNumberOfTiles() {
        let tiles = TreemapView.layout(of: wideTree(childCount: 100_000),
                                       in: CGSize(width: 1400, height: 900))

        print("treemap tiles from 100k children: \(tiles.count)")
        XCTAssertLessThan(tiles.count, 20_000, "far more tiles than the canvas has pixels for")
        XCTAssertGreaterThan(tiles.count, 0)
    }

    // MARK: - Sunburst

    func testSunburstLayoutStaysInsideTheFrameBudget() {
        let root = wideTree(childCount: 50_000)

        _ = SunburstLayout.build(root: root, maxRadius: 400, colors: [:])
        let elapsed = time { _ = SunburstLayout.build(root: root, maxRadius: 400, colors: [:]) }
        print("sunburst layout, 50k children: \(String(format: "%.2f", elapsed * 1000))ms")

        XCTAssertLessThan(
            elapsed, Self.debugCeilingSeconds,
            "sunburst layout took \(String(format: "%.0f", elapsed * 1000))ms in Debug; "
            + "the ceiling is \(String(format: "%.0f", Self.debugCeilingSeconds * 1000))ms. "
            + "This is a complexity guard, not an fps measurement.")
    }

    func testSunburstProducesAWorkableNumberOfWedges() {
        let root = wideTree(childCount: 100_000)
        let segments = SunburstLayout.build(root: root, maxRadius: 400, colors: [:])

        print("sunburst wedges from 100k children: \(segments.count)")
        // A full circle at radius 400 is ~2500pt of arc; at 5pt minimum that is
        // ~500 wedges per ring, over at most 3 rings plus the centre disc.
        XCTAssertLessThan(segments.count, 5_000)
        XCTAssertGreaterThan(segments.count, 0)
    }

    // MARK: - Hit testing

    /// Hover runs on every mouse-move, so it shares the frame budget with
    /// layout and has to be cheap on its own.
    func testHitTestingIsCheapEnoughForHover() {
        let root = wideTree(childCount: 50_000)
        let segments = SunburstLayout.build(root: root, maxRadius: 400, colors: [:])
        let center = CGPoint(x: 500, y: 500)

        let elapsed = time {
            for i in 0..<100 {
                let point = CGPoint(x: 500 + Double(i % 200), y: 500 + Double(i % 150))
                _ = segments.firstIndex { $0.contains(point, center: center) }
            }
        }
        let perHit = elapsed / 100
        print("sunburst hit test: \(String(format: "%.3f", perHit * 1000))ms per probe")

        XCTAssertLessThan(
            perHit, 0.016_67,
            "a single hover probe costs more than a whole frame")
    }
}
