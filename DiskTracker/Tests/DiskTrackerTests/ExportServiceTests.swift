//
//  ExportServiceTests.swift
//  DiskTrackerTests
//
//  Phase 5 TDD: JSON + CSV export of DiskNode trees.
//

import XCTest
@testable import DiskTracker

final class ExportServiceTests: XCTestCase {

    // MARK: - Test helpers

    private func leaf(path: String, size: UInt64 = 100, modTime: Int64 = 1_700_000_000) -> DiskNode {
        DiskNode(recordIndex: 0,
                 name: (path as NSString).lastPathComponent,
                 path: path,
                 logicalSize: size,
                 physicalSize: size,
                 fileKind: .other,
                 isSystemProtected: false,
                 modTimeSecs: modTime,
                 depth: 1,
                 children: nil)
    }

    private func dir(path: String, children: [DiskNode]) -> DiskNode {
        DiskNode(recordIndex: 0,
                 name: (path as NSString).lastPathComponent,
                 path: path,
                 logicalSize: 0,
                 physicalSize: 0,
                 fileKind: .directory,
                 isSystemProtected: false,
                 modTimeSecs: 1,
                 depth: 0,
                 children: children)
    }

    /// Fixed epoch seconds for deterministic formatting.
    private let fixedEpoch: TimeInterval = 1_700_000_000  // ~2023-11-14

    private func fixedFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    // MARK: - CSV

    func testCSVHasHeader() {
        let root = leaf(path: "/file.txt")
        let csv = ExportService.exportCSV(root: root, formatter: fixedFormatter())
        XCTAssertTrue(csv.hasPrefix("Path,Name,PhysicalSize,LogicalSize,Kind,ModDate"))
    }

    func testCSVOneRowPerFile() {
        let root = dir(path: "/root", children: [
            leaf(path: "/root/a.txt"),
            leaf(path: "/root/b.txt"),
        ])
        let csv = ExportService.exportCSV(root: root, formatter: fixedFormatter())
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 1 + 2)  // header + 2 rows
    }

    func testCSVSkipsDirectories() {
        let root = dir(path: "/root", children: [
            leaf(path: "/root/a.txt"),
        ])
        let csv = ExportService.exportCSV(root: root, formatter: fixedFormatter())
        XCTAssertFalse(csv.contains(",root,"))
    }

    func testCSVRowFormat() {
        let root = leaf(path: "/file.txt", size: 4_096, modTime: Int64(fixedEpoch))
        let csv = ExportService.exportCSV(root: root, formatter: fixedFormatter())
        let row = csv.split(separator: "\n").last.map(String.init) ?? ""
        XCTAssertEqual(row, "/file.txt,file.txt,4096,4096,Other,2023-11-14 22:13:20")
    }

    func testCSVEscapesQuotes() {
        let node = DiskNode(recordIndex: 0, name: #"a"b"#, path: "/x",
                            logicalSize: 1, physicalSize: 1, fileKind: .other,
                            isSystemProtected: false, modTimeSecs: Int64(fixedEpoch),
                            depth: 1, children: nil)
        let csv = ExportService.exportCSV(root: node, formatter: fixedFormatter())
        XCTAssertTrue(csv.contains(#""a""b""#))
    }

    func testCSVEscapesCommas() {
        let node = DiskNode(recordIndex: 0, name: "a,b", path: "/x",
                            logicalSize: 1, physicalSize: 1, fileKind: .other,
                            isSystemProtected: false, modTimeSecs: Int64(fixedEpoch),
                            depth: 1, children: nil)
        let csv = ExportService.exportCSV(root: node, formatter: fixedFormatter())
        XCTAssertTrue(csv.contains("\"a,b\""))
    }

    func testCSVEmptyTreeHasHeaderOnly() {
        let root = dir(path: "/", children: [])
        let csv = ExportService.exportCSV(root: root, formatter: fixedFormatter())
        XCTAssertEqual(csv.split(separator: "\n").count, 1)
    }

    func testFileKindLabel() {
        XCTAssertEqual(ExportService.fileKindLabel(.image), "Image")
        XCTAssertEqual(ExportService.fileKindLabel(.video), "Video")
        XCTAssertEqual(ExportService.fileKindLabel(.audio), "Audio")
        XCTAssertEqual(ExportService.fileKindLabel(.document), "Document")
        XCTAssertEqual(ExportService.fileKindLabel(.archive), "Archive")
        XCTAssertEqual(ExportService.fileKindLabel(.application), "Application")
        XCTAssertEqual(ExportService.fileKindLabel(.directory), "Directory")
        XCTAssertEqual(ExportService.fileKindLabel(.other), "Other")
    }

    func testCSVEscapeNoop() {
        XCTAssertEqual(ExportService.csvEscape("plain"), "plain")
        XCTAssertEqual(ExportService.csvEscape("with,comma"), #""with,comma""#)
    }

    // MARK: - JSON

    func testJSONEncodesNameAndSize() {
        let root = leaf(path: "/file.txt", size: 4_096)
        let json = ExportService.exportJSON(root: root, formatter: fixedFormatter())
        XCTAssertTrue(json.contains("\"name\" : \"file.txt\""))
        XCTAssertTrue(json.contains("\"physicalSize\" : 4096"))
    }

    func testJSONIncludesChildrenForDir() {
        let root = dir(path: "/d", children: [leaf(path: "/d/a.txt")])
        let json = ExportService.exportJSON(root: root, formatter: fixedFormatter())
        XCTAssertTrue(json.contains("\"children\""))
    }

    func testJSONIsValidJSON() {
        let root = dir(path: "/", children: [
            leaf(path: "/a.txt", size: 10),
            leaf(path: "/b.txt", size: 20),
        ])
        let json = ExportService.exportJSON(root: root, formatter: fixedFormatter())
        let data = json.data(using: .utf8) ?? Data()
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }
}
