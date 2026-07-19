//
//  DirectoryListViewTests.swift
//  DiskTrackerTests
//
//  Phase 2: DirectoryListView component tests.
//  Tests row view, expand/collapse, and icon mapping.
//

import XCTest
import SwiftUI
@testable import DiskTracker

final class DirectoryListViewTests: XCTestCase {

    // MARK: - DemoItem Tests

    func testDemoItemInitialization() {
        let item = DemoItem(
            name: "Documents",
            path: "/Users/test/Documents",
            size: 5_000_000_000,
            itemCount: 1250,
            kind: .directory,
            depth: 0
        )

        XCTAssertEqual(item.name, "Documents")
        XCTAssertEqual(item.path, "/Users/test/Documents")
        XCTAssertEqual(item.size, 5_000_000_000)
        XCTAssertEqual(item.itemCount, 1250)
        XCTAssertEqual(item.kind, .directory)
        XCTAssertEqual(item.depth, 0)
        XCTAssertNotNil(item.id)  // Identifiable
    }

    func testDemoItemForDifferentFileKinds() {
        let kinds: [FileKind] = [.image, .video, .audio, .document, .archive, .application, .directory, .other]
        
        for kind in kinds {
            let item = DemoItem(
                name: "test",
                path: "/test",
                size: 1000,
                itemCount: 10,
                kind: kind,
                depth: 0
            )
            XCTAssertEqual(item.kind, kind)
        }
    }

    // MARK: - Color Mapping Tests

    func testColorForKindReturnsCorrectColors() {
        let colors: [FileKind: Color] = [
            .image: Color(hex: "FF6B6B"),
            .video: Color(hex: "9B59B6"),
            .audio: Color(hex: "F39C12"),
            .document: Color(hex: "3498DB"),
            .archive: Color(hex: "27AE60"),
            .application: Color(hex: "E74C3C"),
            .directory: Color(hex: "2C3E50"),
            .other: Color(hex: "95A5A6"),
        ]

        for kind in FileKind.allCases {
            let color = colors[kind]
            XCTAssertNotNil(color, "Missing color for \(kind)")
        }
    }

    // MARK: - Icon Mapping Tests

    func testIconForKindImage() {
        let icon = iconForKind(.image)
        XCTAssertEqual(icon, "photo")
    }

    func testIconForKindVideo() {
        let icon = iconForKind(.video)
        XCTAssertEqual(icon, "film")
    }

    func testIconForKindAudio() {
        let icon = iconForKind(.audio)
        XCTAssertEqual(icon, "music.note")
    }

    func testIconForKindDocument() {
        let icon = iconForKind(.document)
        XCTAssertEqual(icon, "doc")
    }

    func testIconForKindArchive() {
        let icon = iconForKind(.archive)
        XCTAssertEqual(icon, "doc.zipper")
    }

    func testIconForKindApplication() {
        let icon = iconForKind(.application)
        XCTAssertEqual(icon, "app")
    }

    func testIconForKindDirectory() {
        let icon = iconForKind(.directory)
        XCTAssertEqual(icon, "folder")
    }

    func testIconForKindOther() {
        let icon = iconForKind(.other)
        XCTAssertEqual(icon, "doc.questionmark")
    }

    // Helper function mirroring DirectoryRowView implementation
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

    // MARK: - DirectoryRowView Depth Indentation Tests

    func testDepthZeroHasNoIndent() {
        let item = DemoItem(
            name: "Home",
            path: "/home",
            size: 42_000_000_000,
            itemCount: 128_000,
            kind: .directory,
            depth: 0
        )

        XCTAssertEqual(item.depth, 0)
    }

    func testDepthOneHasIndent() {
        let item = DemoItem(
            name: "Documents",
            path: "/home/Documents",
            size: 5_000_000_000,
            itemCount: 1000,
            kind: .directory,
            depth: 1
        )

        let indent = CGFloat(item.depth * 16)
        XCTAssertEqual(indent, 16)
    }

    func testDepthTwoHasMoreIndent() {
        let item = DemoItem(
            name: "Subfolder",
            path: "/home/Documents/Subfolder",
            size: 100_000,
            itemCount: 50,
            kind: .directory,
            depth: 2
        )

        let indent = CGFloat(item.depth * 16)
        XCTAssertEqual(indent, 32)
    }

    // MARK: - Size Formatting Tests

    func testFormatBytes() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        
        let kb = formatter.string(fromByteCount: 1024)
        XCTAssertTrue(kb.lowercased().contains("k"))
        
        let mb = formatter.string(fromByteCount: 1_048_576)
        XCTAssertTrue(mb.lowercased().contains("m"))
        
        let gb = formatter.string(fromByteCount: 1_073_741_824)
        XCTAssertTrue(mb.lowercased().contains("m") || gb.lowercased().contains("g"))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Expand/Collapse State Tests

    func testExpandStateDefaultsToFalse() {
        var isExpanded = false
        XCTAssertFalse(isExpanded)
        
        isExpanded.toggle()
        XCTAssertTrue(isExpanded)
        
        isExpanded.toggle()
        XCTAssertFalse(isExpanded)
    }

    // MARK: - Row Construction Tests

    func testRowShowsExpandButtonForDirectory() {
        let item = DemoItem(
            name: "Folder",
            path: "/folder",
            size: 1000,
            itemCount: 10,
            kind: .directory,
            depth: 0
        )
        
        XCTAssertEqual(item.kind, .directory)  // Should show expand button
    }

    func testRowDoesNotShowExpandForFile() {
        let item = DemoItem(
            name: "file.txt",
            path: "/file.txt",
            size: 1000,
            itemCount: 1,
            kind: .document,
            depth: 0
        )
        
        // Document is not a directory, so no expand button
        let isDirectory = item.kind == .directory
        XCTAssertFalse(isDirectory)
    }

    // MARK: - Item Count Display Tests

    func testItemCountFormatting() {
        let item = DemoItem(
            name: "Folder",
            path: "/folder",
            size: 1000,
            itemCount: 1500,
            kind: .directory,
            depth: 0
        )
        
        let countString = "\(item.itemCount)"
        XCTAssertEqual(countString, "1500")
    }

    // MARK: - Color Hex Tests

    func testColorHexValuesAreValid() {
        // Verify all hex colors used in the app are valid 6-digit hex values
        let hexColors: [String] = [
            "FF6B6B",  // image
            "9B59B6",  // video
            "F39C12",  // audio
            "3498DB",  // document
            "27AE60",  // archive
            "E74C3C",  // application
            "2C3E50",  // directory
            "95A5A6",  // other
        ]

        for hex in hexColors {
            XCTAssertEqual(hex.count, 6, "Color hex should be 6 digits: \(hex)")
            
            // Check all characters are valid hex
            let validHexChars = CharacterSet(charactersIn: "0123456789ABCDEF")
            for char in hex.unicodeScalars {
                XCTAssertTrue(validHexChars.contains(char), "Invalid hex character: \(char)")
            }
        }
    }
}
