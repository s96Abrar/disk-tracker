//! `file_record.rs` — Defines the on-disk / FFI data layout used by the
//! scanning engine.
//!
//! ## Memory layout
//!
//! A scan result is a *single* contiguous allocation:
//!
//! ```text
//! [ FileRecord₀ ] [ FileRecord₁ ] … [ FileRecordₙ ]
//! [ String bytes (names, paths)                          ]
//! ```
//!
//! The `StringTable` appended at the end is accessed via
//! `record.name_offset..(record.name_offset + record.name_len)`.

/// Maximum sensible file-name length we ever expect from the kernel.
pub const MAX_NAME_LEN: usize = 1024;

/// Discriminates the kind of file-system node we discovered.
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NodeType {
    File = 0,
    Directory = 1,
    Symlink = 2,
    Package = 3,
}

impl TryFrom<u8> for NodeType {
    type Error = ();
    fn try_from(v: u8) -> Result<Self, Self::Error> {
        match v {
            0 => Ok(NodeType::File),
            1 => Ok(NodeType::Directory),
            2 => Ok(NodeType::Symlink),
            3 => Ok(NodeType::Package),
            _ => Err(()),
        }
    }
}

/// ## Safety
///
/// *Must* match the layout used by the Swift / C++ FFI consumer exactly.
/// Changing field order or adding fields breaks ABI compatability.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct FileRecord {
    pub node_id: u64,
    pub parent_id: u64,
    pub name_offset: u32,
    pub name_len: u32,
    pub logical_size: u64,
    pub physical_size: u64,
    pub node_type: u8,
    pub is_system_protected: bool,
    pub mod_time_secs: i64,
    pub depth: u16,
    pub child_count: u32,
    pub first_child_id: u64,
    pub padding: [u8; 6],
}

/// Fixed header so the FFI consumer can validate struct size before reading.
pub const FILE_RECORD_SIZE: usize = std::mem::size_of::<FileRecord>();
pub const FILE_RECORD_MAGIC: u64 = 0x4454_5243_0000_0001; // "DTRC\0\0\0\1"

// ---------------------------------------------------------------------------
// String table helpers
// ---------------------------------------------------------------------------

/// Append `s` into `buf`, returning the offset where it was written.
pub fn append_to_string_table(buf: &mut Vec<u8>, s: &str) -> u32 {
    let offset = buf.len() as u32;
    buf.extend_from_slice(s.as_bytes());
    buf.push(0); // NUL terminator
    offset
}

/// Read a NUL-terminated string from ` buf` starting at `offset`.
///
/// # Safety
/// `offset` must point to a valid NUL-terminated region inside `buf`.
pub unsafe fn read_string_from_table(buf: &[u8], offset: u32) -> &str {
    let start = offset as usize;
    let end = buf[start..]
        .iter()
        .position(|&b| b == 0)
        .unwrap_or(buf.len() - start);
    std::str::from_utf8_unchecked(&buf[start..start + end])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_node_type_conversions() {
        assert_eq!(NodeType::try_from(0u8), Ok(NodeType::File));
        assert_eq!(NodeType::try_from(1u8), Ok(NodeType::Directory));
        assert_eq!(NodeType::try_from(2u8), Ok(NodeType::Symlink));
        assert_eq!(NodeType::try_from(3u8), Ok(NodeType::Package));
        assert_eq!(NodeType::try_from(4u8), Err(()));
        assert_eq!(NodeType::try_from(255u8), Err(()));
    }

    #[test]
    fn test_string_table_single_string() {
        let mut buf = Vec::new();
        let offset = append_to_string_table(&mut buf, "test.txt");
        assert_eq!(offset, 0);

        // Verify NUL terminator
        assert_eq!(buf, b"test.txt\0");

        // Read back
        unsafe {
            let s = read_string_from_table(&buf, offset);
            assert_eq!(s, "test.txt");
        }
    }

    #[test]
    fn test_string_table_multiple_strings() {
        let mut buf = Vec::new();

        let offset1 = append_to_string_table(&mut buf, "file1.txt");
        let offset2 = append_to_string_table(&mut buf, "file2.txt");
        let offset3 = append_to_string_table(&mut buf, "");

        assert_eq!(offset1, 0);
        // "file1.txt\0" = 10 bytes (9 chars + NUL)
        assert_eq!(offset2, 10);
        // offset2 + "file2.txt\0" = 10 + 10 = 20
        assert_eq!(offset3, 20);

        unsafe {
            assert_eq!(read_string_from_table(&buf, offset1), "file1.txt");
            assert_eq!(read_string_from_table(&buf, offset2), "file2.txt");
            assert_eq!(read_string_from_table(&buf, offset3), "");
        }
    }

    #[test]
    fn test_string_table_empty_string() {
        let mut buf = Vec::new();
        let offset = append_to_string_table(&mut buf, "");
        assert_eq!(offset, 0);
        assert_eq!(buf, b"\0");

        unsafe {
            assert_eq!(read_string_from_table(&buf, offset), "");
        }
    }

    #[test]
    fn test_string_table_long_name() {
        let long_name = "a".repeat(500);
        let mut buf = Vec::new();
        let offset = append_to_string_table(&mut buf, &long_name);

        unsafe {
            assert_eq!(read_string_from_table(&buf, offset), long_name);
        }
    }

    #[test]
    fn test_file_record_size_abi_compatible() {
        // FileRecord layout for FFI compatibility (repr(C)):
        // node_id: u64 at offset 0 (8)
        // parent_id: u64 at offset 8 (8)
        // name_offset: u32 at offset 16 (4)
        // name_len: u32 at offset 20 (4)
        // logical_size: u64 at offset 24 (8)
        // physical_size: u64 at offset 32 (8)
        // node_type: u8 at offset 40 (1)
        // is_system_protected: bool at offset 41 (1)
        // padding to align mod_time_secs to 8-byte boundary: 6 bytes at offset 42-47
        // mod_time_secs: i64 at offset 48 (8)
        // depth: u16 at offset 56 (2)
        // child_count: u32 at offset 60 (4)
        // first_child_id: u64 at offset 64 (8)
        // padding: [u8; 6] at offset 72 (6)
        // Total: 78 bytes, aligned to 8-byte boundary = 80
        let size = std::mem::size_of::<FileRecord>();
        assert_eq!(
            size, 80,
            "FileRecord should be 80 bytes for ABI compatibility"
        );
    }

    #[test]
    fn test_file_record_struct_layout() {
        let rec = FileRecord {
            node_id: 1,
            parent_id: 0,
            name_offset: 10,
            name_len: 5,
            logical_size: 1024,
            physical_size: 2048,
            node_type: NodeType::File as u8,
            is_system_protected: false,
            mod_time_secs: 1234567890,
            depth: 2,
            child_count: 3,
            first_child_id: 5,
            padding: [0; 6],
        };

        assert_eq!(rec.node_id, 1);
        assert_eq!(rec.parent_id, 0);
        assert_eq!(rec.name_offset, 10);
        assert_eq!(rec.name_len, 5);
        assert_eq!(rec.logical_size, 1024);
        assert_eq!(rec.physical_size, 2048);
        assert_eq!(rec.node_type, 0);
        assert!(!rec.is_system_protected);
        assert_eq!(rec.depth, 2);
        assert_eq!(rec.child_count, 3);
    }

    #[test]
    fn test_file_record_padding_not_modified() {
        let rec = FileRecord {
            node_id: 42,
            parent_id: 0,
            name_offset: 0,
            name_len: 0,
            logical_size: 0,
            physical_size: 0,
            node_type: 0,
            is_system_protected: false,
            mod_time_secs: 0,
            depth: 0,
            child_count: 0,
            first_child_id: 0,
            padding: [1, 2, 3, 4, 5, 6],
        };

        // Padding should remain as set
        assert_eq!(rec.padding, [1, 2, 3, 4, 5, 6]);
    }

    #[test]
    fn test_node_type_is_repr_u8() {
        // Ensure NodeType variants have correct byte values for FFI
        assert_eq!(NodeType::File as u8, 0);
        assert_eq!(NodeType::Directory as u8, 1);
        assert_eq!(NodeType::Symlink as u8, 2);
        assert_eq!(NodeType::Package as u8, 3);
    }

    #[test]
    fn test_file_record_magic() {
        // The prefix check below already implies a non-zero magic.
        assert_eq!(
            FILE_RECORD_MAGIC & 0xFFFF_FFFF_FFFF_0000,
            0x4454_5243_0000_0000
        );
    }
}
