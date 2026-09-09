//
//  ScanBufferTests.swift
//  DiskTrackerTests
//
//  The scan buffer is a byte-level contract with `traversal-engine/src/wire.rs`.
//  A wrong offset here does not throw — it yields plausible sizes for the wrong
//  fields, which is exactly the failure this format replaced. So these tests
//  assert on concrete offsets, and the last one reads a buffer produced by the
//  real engine rather than by this file.
//

import XCTest
@testable import DiskTracker

final class ScanBufferTests: XCTestCase {

    // MARK: - Builder mirroring wire.rs

    private static let headerSize = 32
    private static let recordSize = 56
    private static let magic: UInt64 = 0x4454_4B53_4341_4E01

    private struct Rec {
        var nodeID: UInt64 = 0
        var parentID: UInt64 = 0
        var logical: UInt64 = 0
        var physical: UInt64 = 0
        var modTime: Int64 = 0
        var nameOffset: UInt32 = 0
        var nameLen: UInt32 = 0
        var childCount: UInt32 = 0
        var depth: UInt16 = 0
        var nodeType: UInt8 = 0
        var systemProtected: UInt8 = 0
    }

    private func makeBuffer(
        records: [Rec],
        stringTable: [UInt8],
        magic: UInt64 = ScanBufferTests.magic,
        version: UInt32 = 1,
        recordSize: UInt32 = UInt32(ScanBufferTests.recordSize)
    ) -> Data {
        var d = Data()
        func append<T: FixedWidthInteger>(_ v: T) {
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        append(magic)
        append(version)
        append(recordSize)
        append(UInt64(records.count))
        append(UInt64(stringTable.count))
        for r in records {
            append(r.nodeID)
            append(r.parentID)
            append(r.logical)
            append(r.physical)
            append(r.modTime)
            append(r.nameOffset)
            append(r.nameLen)
            append(r.childCount)
            append(r.depth)
            append(r.nodeType)
            append(r.systemProtected)
        }
        d.append(contentsOf: stringTable)
        return d
    }

    // MARK: - Field offsets

    func testReadsEveryFieldAtItsDocumentedOffset() throws {
        let table = Array("report.pdf\u{0}".utf8)
        let rec = Rec(
            nodeID: 42, parentID: 7,
            logical: 123_456, physical: 131_072,
            modTime: 1_700_000_000,
            nameOffset: 0, nameLen: 10,
            childCount: 3, depth: 4,
            nodeType: 0, systemProtected: 1
        )
        let buffer = try XCTUnwrap(ScanBuffer(makeBuffer(records: [rec], stringTable: table)))

        XCTAssertEqual(buffer.recordCount, 1)
        XCTAssertEqual(buffer.nodeID(at: 0), 42)
        XCTAssertEqual(buffer.parentID(at: 0), 7)
        XCTAssertEqual(buffer.logicalSize(at: 0), 123_456)
        XCTAssertEqual(buffer.physicalSize(at: 0), 131_072)
        XCTAssertEqual(buffer.modTimeSecs(at: 0), 1_700_000_000)
        XCTAssertEqual(buffer.childCount(at: 0), 3)
        XCTAssertEqual(buffer.depth(at: 0), 4)
        XCTAssertEqual(buffer.nodeType(at: 0), 0)
        XCTAssertTrue(buffer.isSystemProtected(at: 0))
        XCTAssertEqual(buffer.name(at: 0), "report.pdf")
    }

    func testIndexesIntoTheCorrectRecord() throws {
        let table = Array("aa\u{0}bb\u{0}cc\u{0}".utf8)
        var records: [Rec] = []
        for i in 0..<3 {
            var r = Rec()
            r.nodeID = UInt64(i + 1)
            r.logical = UInt64(i + 1) * 1000
            r.nameOffset = UInt32(i) * 3
            r.nameLen = 2
            records.append(r)
        }
        let buffer = try XCTUnwrap(ScanBuffer(makeBuffer(records: records, stringTable: table)))

        XCTAssertEqual(buffer.recordCount, 3)
        XCTAssertEqual(buffer.name(at: 0), "aa")
        XCTAssertEqual(buffer.name(at: 2), "cc")
        XCTAssertEqual(buffer.logicalSize(at: 1), 2000)
        XCTAssertEqual(buffer.nodeID(at: 2), 3)
    }

    /// Dates before 1970 are legal on disk and must not wrap to a huge positive.
    func testModTimeStaysSigned() throws {
        let rec = Rec(modTime: -86_400)
        let buffer = try XCTUnwrap(ScanBuffer(makeBuffer(records: [rec], stringTable: [])))
        XCTAssertEqual(buffer.modTimeSecs(at: 0), -86_400)
    }

    // MARK: - Rejection

    func testRejectsEmptyOutput() {
        // A crashed engine writes nothing; that must not look like a valid scan.
        XCTAssertNil(ScanBuffer(Data()))
    }

    func testRejectsForeignPayload() {
        XCTAssertNil(ScanBuffer(Data("not a scan buffer at all, just text".utf8)))
    }

    func testRejectsVersionMismatch() {
        // A stale bundled engine would otherwise be misread field by field.
        let d = makeBuffer(records: [Rec()], stringTable: [], version: 99)
        XCTAssertNil(ScanBuffer(d))
    }

    func testRejectsRecordSizeMismatch() {
        let d = makeBuffer(records: [Rec()], stringTable: [], recordSize: 64)
        XCTAssertNil(ScanBuffer(d))
    }

    func testRejectsTruncatedPayload() {
        // A pipe closed mid-write must fail up front, not partway through the
        // tree build with half a scan already assembled.
        var d = makeBuffer(records: [Rec(), Rec()], stringTable: Array("ab\u{0}".utf8))
        d.removeLast(20)
        XCTAssertNil(ScanBuffer(d))
    }

    func testRejectsTrailingGarbage() {
        var d = makeBuffer(records: [Rec()], stringTable: [])
        d.append(contentsOf: [0xFF, 0xFF])
        XCTAssertNil(ScanBuffer(d))
    }

    func testSurvivesOutOfRangeNameReference() throws {
        // Never crash on a malformed name reference; an empty name is recoverable.
        let rec = Rec(nameOffset: 9_999, nameLen: 50)
        let buffer = try XCTUnwrap(ScanBuffer(makeBuffer(records: [rec], stringTable: [])))
        XCTAssertEqual(buffer.name(at: 0), "")
    }

    func testDecodesNonASCIINames() throws {
        let name = "Ünïcødé 📁 файл"
        let table = Array(name.utf8)
        let rec = Rec(nameOffset: 0, nameLen: UInt32(table.count))
        let buffer = try XCTUnwrap(ScanBuffer(makeBuffer(records: [rec], stringTable: table)))
        XCTAssertEqual(buffer.name(at: 0), name)
    }

    /// `Data` from a pipe can be a slice with a non-zero `startIndex`. Reading
    /// at absolute offsets rather than relative ones would return garbage.
    func testReadsCorrectlyFromASlicedData() throws {
        let real = makeBuffer(
            records: [Rec(nodeID: 99, logical: 555, nameOffset: 0, nameLen: 2)],
            stringTable: Array("hi\u{0}".utf8)
        )
        var padded = Data([0xAA, 0xBB, 0xCC, 0xDD])
        padded.append(real)
        let sliced = padded.dropFirst(4)

        let buffer = try XCTUnwrap(ScanBuffer(sliced))
        XCTAssertEqual(buffer.nodeID(at: 0), 99)
        XCTAssertEqual(buffer.logicalSize(at: 0), 555)
        XCTAssertEqual(buffer.name(at: 0), "hi")
    }

    // MARK: - Against the real engine

    /// Everything above validates the reader against a buffer this file wrote.
    /// That proves self-consistency, not agreement with Rust. This runs the
    /// actual engine and checks the result against `FileManager`.
    func testReadsBufferProducedByTheRealEngine() throws {
        let engine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DiskTrackerTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // DiskTracker/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("traversal-engine/target/release/disk-tracker-engine")

        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: engine.path),
            "Engine not built — run ./build-disk-tracker --rust"
        )

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanbuffer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = Data(repeating: 0x41, count: 4096)
        try payload.write(to: dir.appendingPathComponent("alpha.txt"))
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try payload.write(to: dir.appendingPathComponent("nested/beta.bin"))

        let pipe = Pipe()
        let task = Process()
        task.executableURL = engine
        task.arguments = ["scan", dir.path]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let buffer = try XCTUnwrap(
            ScanBuffer(data),
            "Engine output did not parse — the Rust and Swift layouts disagree"
        )

        // root + alpha.txt + nested + nested/beta.bin
        XCTAssertEqual(buffer.recordCount, 4)

        let names = (0..<buffer.recordCount).map { buffer.name(at: $0) }
        XCTAssertTrue(names.contains("alpha.txt"), "got \(names)")
        XCTAssertTrue(names.contains("beta.bin"), "got \(names)")

        let alpha = try XCTUnwrap((0..<buffer.recordCount).first { buffer.name(at: $0) == "alpha.txt" })
        XCTAssertEqual(buffer.logicalSize(at: alpha), 4096)
        XCTAssertGreaterThanOrEqual(buffer.physicalSize(at: alpha), 4096)
        XCTAssertEqual(buffer.nodeType(at: alpha), 0, "regular file")

        let nested = try XCTUnwrap((0..<buffer.recordCount).first { buffer.name(at: $0) == "nested" })
        XCTAssertEqual(buffer.nodeType(at: nested), 1, "directory")
        XCTAssertEqual(buffer.parentID(at: nested), buffer.nodeID(at: 0), "child of root")
    }
}

// MARK: - Tree assembly

/// `buildTree` folds what used to be three separate walks over the finished
/// tree — full paths, recursive physical totals, and child ordering — into the
/// single assembly pass. These cover the properties those walks used to
/// guarantee.
final class ScanBufferTreeTests: XCTestCase {

    private struct Entry {
        let nodeID: UInt64
        let parentID: UInt64
        let name: String
        let isDir: Bool
        let physical: UInt64
    }

    /// Encodes entries in the engine's wire format so the tree builder is
    /// exercised through the same path a real scan takes.
    private func buffer(_ entries: [Entry]) throws -> ScanBuffer {
        var table = Data()
        var offsets: [(UInt32, UInt32)] = []
        for e in entries {
            let bytes = Array(e.name.utf8)
            offsets.append((UInt32(table.count), UInt32(bytes.count)))
            table.append(contentsOf: bytes)
            table.append(0)
        }

        var d = Data()
        func append<T: FixedWidthInteger>(_ v: T) {
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        append(UInt64(0x4454_4B53_4341_4E01))
        append(UInt32(1))
        append(UInt32(56))
        append(UInt64(entries.count))
        append(UInt64(table.count))
        for (i, e) in entries.enumerated() {
            append(e.nodeID)
            append(e.parentID)
            append(e.physical)          // logical
            append(e.physical)          // physical
            append(Int64(1_700_000_000))
            append(offsets[i].0)
            append(offsets[i].1)
            append(UInt32(0))
            append(UInt16(0))
            append(UInt8(e.isDir ? 1 : 0))
            append(UInt8(0))
        }
        d.append(table)
        return try XCTUnwrap(ScanBuffer(d))
    }

    /// root/
    ///   docs/            (dir)
    ///     deep/          (dir)
    ///       big.bin      4000
    ///     note.txt       100
    ///   apple.txt        7
    private func sampleTree() throws -> DiskNode {
        let buf = try buffer([
            Entry(nodeID: 1, parentID: 0, name: "root",      isDir: true,  physical: 0),
            Entry(nodeID: 2, parentID: 1, name: "docs",      isDir: true,  physical: 0),
            Entry(nodeID: 3, parentID: 1, name: "apple.txt", isDir: false, physical: 7),
            Entry(nodeID: 4, parentID: 2, name: "deep",      isDir: true,  physical: 0),
            Entry(nodeID: 5, parentID: 2, name: "note.txt",  isDir: false, physical: 100),
            Entry(nodeID: 6, parentID: 4, name: "big.bin",   isDir: false, physical: 4000),
        ])
        return try XCTUnwrap(DirectoryScannerBridge().buildTree(buf))
    }

    func testBuildsFullPathsFromTheRoot() throws {
        let root = try sampleTree()
        XCTAssertEqual(root.path, "root")

        let docs = try XCTUnwrap(root.children?.first { $0.name == "docs" })
        XCTAssertEqual(docs.path, "root/docs")

        let deep = try XCTUnwrap(docs.children?.first { $0.name == "deep" })
        let big = try XCTUnwrap(deep.children?.first)
        XCTAssertEqual(big.path, "root/docs/deep/big.bin")
    }

    /// A grandchild's bytes must reach the root. Attaching children after the
    /// parent had been copied is what previously dropped them from the totals.
    func testTotalsIncludeNestedDescendants() throws {
        let root = try sampleTree()
        XCTAssertEqual(root.totalPhysicalSize, 4107, "7 + 100 + 4000")

        let docs = try XCTUnwrap(root.children?.first { $0.name == "docs" })
        XCTAssertEqual(docs.totalPhysicalSize, 4100)

        let deep = try XCTUnwrap(docs.children?.first { $0.name == "deep" })
        XCTAssertEqual(deep.totalPhysicalSize, 4000)
    }

    func testOrdersDirectoriesBeforeFiles() throws {
        let root = try sampleTree()
        let names = try XCTUnwrap(root.children).map(\.name)
        XCTAssertEqual(names, ["docs", "apple.txt"], "directories sort ahead of files")
    }

    func testClassifiesNodeKinds() throws {
        let root = try sampleTree()
        XCTAssertEqual(root.fileKind, .directory)

        let apple = try XCTUnwrap(root.children?.first { $0.name == "apple.txt" })
        XCTAssertEqual(apple.fileKind, .document, "classified by extension")
        XCTAssertEqual(apple.totalPhysicalSize, 7, "a leaf's total is its own size")
    }

    func testEmptyBufferProducesNoTree() throws {
        let buf = try buffer([])
        XCTAssertNil(DirectoryScannerBridge().buildTree(buf))
    }

    func testHandlesADirectoryWithNoChildren() throws {
        let buf = try buffer([
            Entry(nodeID: 1, parentID: 0, name: "root",  isDir: true, physical: 0),
            Entry(nodeID: 2, parentID: 1, name: "empty", isDir: true, physical: 0),
        ])
        let root = try XCTUnwrap(DirectoryScannerBridge().buildTree(buf))
        let empty = try XCTUnwrap(root.children?.first)
        XCTAssertEqual(empty.totalPhysicalSize, 0)
        XCTAssertEqual(empty.children?.count, 0)
    }
}
