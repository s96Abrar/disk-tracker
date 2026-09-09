//
//  ScanBuffer.swift
//  DiskTracker
//
//  Reader for the flat scan buffer the Rust engine writes to stdout.
//  Mirrors `traversal-engine/src/wire.rs` — the offsets below and the table in
//  that file's doc comment are one contract, and both sides have tests
//  asserting the same numbers.
//
//      [ Header (32 bytes) ][ Record x N (56 bytes each) ][ string table ]
//
//  This replaced a JSON document. For a million files that was ~250MB of text
//  to parse against a 300MB budget for the entire scan.
//

import Foundation

/// Random-access view over a scan buffer.
///
/// Fields are read on demand rather than materialised into an array of structs:
/// the tree builder touches each record once, so a parallel array of parsed
/// values would double peak memory for no gain.
struct ScanBuffer {
    private let data: Data
    /// Byte offset where the string table begins.
    private let stringTableOffset: Int
    let recordCount: Int

    // Must match `wire.rs`.
    private static let magic: UInt64 = 0x4454_4B53_4341_4E01 // "DTKSCAN\u{01}"
    private static let version: UInt32 = 1
    private static let recordSize = 56
    private static let headerSize = 32

    /// Parses the header and validates it against this build's expectations.
    /// Returns nil when the payload is truncated, not a scan buffer at all
    /// (a crashed engine writing nothing, or a shell error on stdout), or was
    /// produced by an engine whose layout no longer matches.
    init?(_ data: Data) {
        guard data.count >= Self.headerSize else { return nil }

        let magic: UInt64 = data.load(at: 0)
        guard magic == Self.magic else { return nil }

        let version: UInt32 = data.load(at: 8)
        let recordSize: UInt32 = data.load(at: 12)
        // A stale bundled engine would otherwise be misread field by field.
        guard version == Self.version, recordSize == UInt32(Self.recordSize) else { return nil }

        let count: UInt64 = data.load(at: 16)
        let stringTableLength: UInt64 = data.load(at: 24)

        // Reject a truncated payload up front rather than discovering it
        // partway through building the tree.
        let expected = UInt64(Self.headerSize)
            + count * UInt64(Self.recordSize)
            + stringTableLength
        guard expected == UInt64(data.count) else { return nil }

        self.data = data
        self.recordCount = Int(count)
        self.stringTableOffset = Self.headerSize + Int(count) * Self.recordSize
    }

    private func fieldOffset(_ index: Int, _ field: Int) -> Int {
        Self.headerSize + index * Self.recordSize + field
    }

    func nodeID(at i: Int) -> UInt64 { data.load(at: fieldOffset(i, 0)) }
    func parentID(at i: Int) -> UInt64 { data.load(at: fieldOffset(i, 8)) }
    func logicalSize(at i: Int) -> UInt64 { data.load(at: fieldOffset(i, 16)) }
    func physicalSize(at i: Int) -> UInt64 { data.load(at: fieldOffset(i, 24)) }
    func modTimeSecs(at i: Int) -> Int64 { data.load(at: fieldOffset(i, 32)) }
    func childCount(at i: Int) -> UInt32 { data.load(at: fieldOffset(i, 48)) }
    func depth(at i: Int) -> UInt16 { data.load(at: fieldOffset(i, 52)) }
    func nodeType(at i: Int) -> UInt8 { data[data.startIndex + fieldOffset(i, 54)] }
    func isSystemProtected(at i: Int) -> Bool { data[data.startIndex + fieldOffset(i, 55)] != 0 }

    /// The entry's name, decoded from the string table.
    ///
    /// Filenames on macOS are bytes, not guaranteed UTF-8, so an undecodable
    /// name is repaired rather than dropped — losing the entry would silently
    /// remove its bytes from every total above it.
    func name(at i: Int) -> String {
        let offset: UInt32 = data.load(at: fieldOffset(i, 40))
        let length: UInt32 = data.load(at: fieldOffset(i, 44))

        let start = stringTableOffset + Int(offset)
        let end = start + Int(length)
        guard start >= stringTableOffset, end <= data.count, start <= end else { return "" }

        let base = data.startIndex
        return String(decoding: data[(base + start)..<(base + end)], as: UTF8.self)
    }
}

private extension Data {
    /// Reads a fixed-width integer at a byte offset from the start of the
    /// buffer. `Data` slices carry non-zero start indices, so the offset is
    /// applied relative to `startIndex` rather than to zero.
    ///
    /// The buffer comes off a pipe with no alignment guarantee, hence
    /// `loadUnaligned`.
    func load<T: FixedWidthInteger>(at offset: Int) -> T {
        withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
    }
}
