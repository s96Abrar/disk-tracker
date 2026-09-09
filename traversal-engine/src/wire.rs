//! `wire.rs` — Binary scan-result format written to stdout.
//!
//! The app used to receive scan results as JSON. For a million files that is
//! roughly 250MB of text to serialize, pipe and re-parse, against a 300MB
//! memory budget for the whole scan — the format cost more than the walk.
//!
//! This is the same data as a flat buffer:
//!
//! ```text
//! [ Header (32 bytes) ][ WireRecord x N ][ string table bytes ]
//! ```
//!
//! Names live in the string table, addressed by `name_offset` / `name_len`.
//!
//! ## Why not `FileRecord` directly
//!
//! `FileRecord` is `#[repr(C)]`, so its layout includes compiler-inserted
//! padding between fields. That is fine within Rust, but it makes the Swift
//! side depend on padding rules rather than on a written-down contract.
//! `WireRecord` is explicitly packed in a fixed order with no implicit gaps, so
//! both sides agree by construction. `Reader.swift` mirrors these offsets.

use crate::file_record::FileRecord;

/// "DTKSCAN\x01". Lets the reader reject a stray or truncated stream instead of
/// interpreting shell noise as records.
pub const WIRE_MAGIC: u64 = 0x4454_4B53_4341_4E01;

/// Bumped whenever the record layout changes. The reader refuses a mismatch
/// rather than silently misreading a stale bundled engine.
pub const WIRE_VERSION: u32 = 1;

/// Bytes per record on the wire. Verified against the writer by a test.
pub const WIRE_RECORD_SIZE: u32 = 56;

/// Bytes in the header preceding the records.
pub const WIRE_HEADER_SIZE: usize = 32;

/// Serialize a scan result into the wire format.
///
/// Field order — every offset is fixed and mirrored in Swift:
///
/// | Offset | Size | Field |
/// |--------|------|-------|
/// | 0  | 8 | `node_id` |
/// | 8  | 8 | `parent_id` |
/// | 16 | 8 | `logical_size` |
/// | 24 | 8 | `physical_size` |
/// | 32 | 8 | `mod_time_secs` (i64) |
/// | 40 | 4 | `name_offset` |
/// | 44 | 4 | `name_len` |
/// | 48 | 4 | `child_count` |
/// | 52 | 2 | `depth` |
/// | 54 | 1 | `node_type` |
/// | 55 | 1 | `is_system_protected` |
///
/// All integers are little-endian, which every Mac this runs on is.
pub fn encode(records: &[FileRecord], string_table: &[u8]) -> Vec<u8> {
    let record_bytes = records.len() * WIRE_RECORD_SIZE as usize;
    let mut out = Vec::with_capacity(WIRE_HEADER_SIZE + record_bytes + string_table.len());

    out.extend_from_slice(&WIRE_MAGIC.to_le_bytes());
    out.extend_from_slice(&WIRE_VERSION.to_le_bytes());
    out.extend_from_slice(&WIRE_RECORD_SIZE.to_le_bytes());
    out.extend_from_slice(&(records.len() as u64).to_le_bytes());
    out.extend_from_slice(&(string_table.len() as u64).to_le_bytes());
    debug_assert_eq!(out.len(), WIRE_HEADER_SIZE);

    for r in records {
        out.extend_from_slice(&r.node_id.to_le_bytes());
        out.extend_from_slice(&r.parent_id.to_le_bytes());
        out.extend_from_slice(&r.logical_size.to_le_bytes());
        out.extend_from_slice(&r.physical_size.to_le_bytes());
        out.extend_from_slice(&r.mod_time_secs.to_le_bytes());
        out.extend_from_slice(&r.name_offset.to_le_bytes());
        out.extend_from_slice(&r.name_len.to_le_bytes());
        out.extend_from_slice(&r.child_count.to_le_bytes());
        out.extend_from_slice(&r.depth.to_le_bytes());
        out.push(r.node_type);
        out.push(u8::from(r.is_system_protected));
    }

    out.extend_from_slice(string_table);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> FileRecord {
        FileRecord {
            node_id: 7,
            parent_id: 3,
            name_offset: 11,
            name_len: 5,
            logical_size: 1234,
            physical_size: 4096,
            node_type: 1,
            is_system_protected: true,
            mod_time_secs: -42, // pre-epoch: must survive as a signed value
            depth: 2,
            child_count: 9,
            first_child_id: 0,
            padding: [0; 6],
        }
    }

    #[test]
    fn header_and_record_sizes_are_exact() {
        let buf = encode(&[sample()], b"hello\0");
        assert_eq!(
            buf.len(),
            WIRE_HEADER_SIZE + WIRE_RECORD_SIZE as usize + 6,
            "size drift here silently shifts every field the reader sees"
        );
    }

    #[test]
    fn fields_land_at_their_documented_offsets() {
        let buf = encode(&[sample()], b"");
        let r = &buf[WIRE_HEADER_SIZE..];
        let u64_at = |o: usize| u64::from_le_bytes(r[o..o + 8].try_into().unwrap());
        let u32_at = |o: usize| u32::from_le_bytes(r[o..o + 4].try_into().unwrap());

        assert_eq!(u64_at(0), 7, "node_id");
        assert_eq!(u64_at(8), 3, "parent_id");
        assert_eq!(u64_at(16), 1234, "logical_size");
        assert_eq!(u64_at(24), 4096, "physical_size");
        assert_eq!(
            i64::from_le_bytes(r[32..40].try_into().unwrap()),
            -42,
            "mod_time_secs must stay signed"
        );
        assert_eq!(u32_at(40), 11, "name_offset");
        assert_eq!(u32_at(44), 5, "name_len");
        assert_eq!(u32_at(48), 9, "child_count");
        assert_eq!(
            u16::from_le_bytes(r[52..54].try_into().unwrap()),
            2,
            "depth"
        );
        assert_eq!(r[54], 1, "node_type");
        assert_eq!(r[55], 1, "is_system_protected");
    }

    #[test]
    fn header_is_self_describing() {
        let buf = encode(&[sample(), sample()], b"ab\0");
        assert_eq!(
            u64::from_le_bytes(buf[0..8].try_into().unwrap()),
            WIRE_MAGIC
        );
        assert_eq!(
            u32::from_le_bytes(buf[8..12].try_into().unwrap()),
            WIRE_VERSION
        );
        assert_eq!(
            u32::from_le_bytes(buf[12..16].try_into().unwrap()),
            WIRE_RECORD_SIZE
        );
        assert_eq!(u64::from_le_bytes(buf[16..24].try_into().unwrap()), 2);
        assert_eq!(u64::from_le_bytes(buf[24..32].try_into().unwrap()), 3);
    }

    #[test]
    fn string_table_follows_the_records() {
        let buf = encode(&[sample()], b"name\0");
        let start = WIRE_HEADER_SIZE + WIRE_RECORD_SIZE as usize;
        assert_eq!(&buf[start..], b"name\0");
    }
}
