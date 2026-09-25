//
//  DashboardLayoutTests.swift
//  DiskTrackerTests
//

import AppKit
import SwiftUI
import XCTest
@testable import DiskTracker

@MainActor
final class DashboardLayoutTests: XCTestCase {

    /// x, in points, of the sidebar's 1pt trailing separator: the first
    /// column, on a row below the nav list, that differs from the window
    /// background. Rendered through AppKit, so the ScrollView lays out for real.
    private func separatorX(
        of root: some View = DashboardView(model: AppModel()), windowWidth width: CGFloat
    ) throws -> CGFloat {
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        let scale = CGFloat(rep.pixelsWide) / width
        let row = Int(800 * scale)
        func rgb(_ x: Int) -> [CGFloat] {
            let c = rep.colorAt(x: x, y: row)?.usingColorSpace(.sRGB)
            return [c?.redComponent ?? 0, c?.greenComponent ?? 0, c?.blueComponent ?? 0]
        }
        let background = rgb(1)
        for x in 2..<rep.pixelsWide
        where zip(rgb(x), background).map({ abs($0 - $1) }).max()! > 0.02 {
            return CGFloat(x) / scale
        }
        throw XCTSkip("no separator found on row")
    }

    /// Full screen used to centre the whole sidebar + content row, which is
    /// only ~1020pt wide, leaving the sidebar stranded mid-window.
    func testSidebarStaysAtTheLeadingEdgeInAWideWindow() throws {
        XCTAssertEqual(try separatorX(windowWidth: 1100), 260, accuracy: 2)
        XCTAssertEqual(try separatorX(windowWidth: 2000), 260, accuracy: 2)
    }

    func testScanResultsSidebarStaysAtTheLeadingEdgeInAWideWindow() throws {
        let model = AppModel()
        let results = ScanResultsView(model: model, onBack: {})
        XCTAssertEqual(try separatorX(of: results, windowWidth: 1100), 240, accuracy: 2)
        XCTAssertEqual(try separatorX(of: results, windowWidth: 2000), 240, accuracy: 2)
    }
}
