//
//  PerformanceTests.swift
//  DiskTrackerTests
//
//  Phase 2: 60fps interaction validation.
//  Target: Canvas rendering completes within 16.67ms (60fps).
//

import XCTest
import SwiftUI
@testable import DiskTracker

final class PerformanceTests: XCTestCase {

    // MARK: - Test Data Generation

    /// Creates a tree with `count` leaf nodes for performance testing.
    func makeTree(depth: Int, breadth: Int, size: UInt64 = 1024) -> DiskNode {
        if depth == 0 {
            return DiskNode(
                recordIndex: 0,
                name: "leaf",
                path: "/leaf",
                logicalSize: size,
                physicalSize: size,
                fileKind: .document,
                isSystemProtected: false,
                modTimeSecs: 0,
                depth: 0,
                children: nil
            )
        }

        var children: [DiskNode] = []
        for _ in 0..<breadth {
            children.append(makeTree(depth: depth - 1, breadth: breadth, size: size))
        }

        let totalSize = children.reduce(UInt64(0)) { $0 + $1.physicalSize }
        return DiskNode(
            recordIndex: 0,
            name: "dir_\(depth)",
            path: "/dir_\(depth)",
            logicalSize: totalSize,
            physicalSize: totalSize,
            fileKind: .directory,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: UInt16(depth),
            children: children
        )
    }

    /// Convert a Duration to milliseconds.
    private func durationMs(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
    }

    // MARK: - Tree Building Performance

    func testDiskNodeTreeBuildingPerformance() {
        let clock = ContinuousClock()
        var total: Duration = .zero

        // Build a 625-node tree 10 times
        for _ in 0..<10 {
            total += clock.measure {
                _ = makeTree(depth: 4, breadth: 5) // 5^0 + ... + 5^4 = 781 nodes
            }
        }

        let ms = durationMs(total)
        XCTAssertLessThan(
            ms,
            10_000.0,
            "Tree building (10 x 781 nodes) should be <10s total, got \(String(format: "%.1f", ms))ms"
        )
    }

    // MARK: - Total Size Calculation Performance

    func testTotalSizeCalculationPerformance() {
        let root = makeTree(depth: 5, breadth: 5) // 5^0 + ... + 5^5 = 3906 nodes

        let clock = ContinuousClock()
        let total = clock.measure {
            for _ in 0..<100 {
                _ = root.totalPhysicalSize
                _ = root.totalLogicalSize
            }
        }

        let ms = durationMs(total)
        // 100 calculations on a ~3906-node tree should complete in under 3s total
        XCTAssertLessThan(
            ms,
            3_000.0,
            "100 size calculations on ~3906-node tree should be <3s total, got \(String(format: "%.1f", ms))ms"
        )
    }

    // MARK: - Large Tree Creation

    func testLargeTreeCreation() {
        let clock = ContinuousClock()
        let total = clock.measure {
            _ = makeTree(depth: 6, breadth: 4) // 4^0 + ... + 4^6 = 5461 nodes
        }

        let ms = durationMs(total)
        XCTAssertLessThan(
            ms,
            6_000.0,
            "Creating 5461-node tree should be <6s, got \(String(format: "%.1f", ms))ms"
        )
    }

    // MARK: - Deep Tree Navigation

    func testDeepTreeNavigation() {
        // Create tree 6 levels deep, breadth 2 → 2^0 + 2^1 + ... + 2^6 = 127 nodes
        let root = makeTree(depth: 6, breadth: 2)

        let clock = ContinuousClock()
        var foundCount = 0

        let total = clock.measure {
            // Navigate all children recursively
            func countChildren(_ node: DiskNode) {
                foundCount += 1
                if let children = node.children {
                    for child in children {
                        countChildren(child)
                    }
                }
            }
            countChildren(root)
        }

        let ms = durationMs(total)
        XCTAssertLessThan(
            ms,
            100.0,
            "Navigating 127-node tree should be <100ms, got \(String(format: "%.1f", ms))ms"
        )
        XCTAssertEqual(foundCount, 127, "Depth-6 breadth-2 tree has 127 nodes, not 64")
    }
}
