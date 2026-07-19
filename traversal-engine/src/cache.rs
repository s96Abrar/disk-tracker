//! `cache.rs` — Scan cache stub for MVP.
//!
//! Real DuckDB integration deferred to Phase 2.  Uses a simple JSON file for now.

use crate::file_record::FileRecord;
use std::io::{Read, Write};
use std::path::Path;

const CACHE_MAGIC: &[u8] = b"DTKCACHE01";
const CACHE_VERSION: u32 = 1;

/// Minimal binary cache format:
/// [MAGIC: 10 bytes] [VERSION: 4 bytes LE] [COUNT: 4 bytes LE] [FileRecord × N] [Strings…]

/// Save records + strings to a binary cache file.
pub fn save_scan<P: AsRef<Path>>(
    cache_path: P,
    records: &[FileRecord],
    _string_table: &[u8],
) -> Result<(), std::io::Error> {
    let mut file = std::fs::File::create(cache_path)?;
    file.write_all(CACHE_MAGIC)?;
    file.write_all(&CACHE_VERSION.to_le_bytes())?;
    file.write_all(&(records.len() as u32).to_le_bytes())?;
    let bytes = unsafe {
        std::slice::from_raw_parts(
            records.as_ptr() as *const u8,
            std::mem::size_of_val(records),
        )
    };
    file.write_all(bytes)?;
    Ok(())
}

/// Load records from a binary cache file.
pub fn load_latest<P: AsRef<Path>>(
    cache_path: P,
) -> Option<Vec<FileRecord>> {
    let mut file = std::fs::File::open(cache_path).ok()?;
    let mut magic = [0u8; 10];
    file.read_exact(&mut magic).ok()?;
    if &magic != CACHE_MAGIC { return None; }
    let mut version = [0u8; 4];
    file.read_exact(&mut version).ok()?;
    if u32::from_le_bytes(version) != CACHE_VERSION { return None; }
    let mut count_buf = [0u8; 4];
    file.read_exact(&mut count_buf).ok()?;
    let count = u32::from_le_bytes(count_buf) as usize;
    let record_size = std::mem::size_of::<FileRecord>();
    let mut data = vec![0u8; record_size * count];
    file.read_exact(&mut data).ok()?;
    let records = unsafe {
        Vec::from_raw_parts(
            data.as_ptr() as *mut FileRecord,
            count,
            count,
        )
    };
    std::mem::forget(data);
    Some(records)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::file_record::NodeType;
    use tempfile::tempdir;

    fn make_test_record(id: u64, size: u64) -> FileRecord {
        FileRecord {
            node_id: id,
            parent_id: 0,
            name_offset: 0,
            name_len: 8,
            logical_size: size,
            physical_size: size,
            node_type: NodeType::File as u8,
            is_system_protected: false,
            mod_time_secs: 0,
            depth: 0,
            child_count: 0,
            first_child_id: 0,
            padding: [0; 6],
        }
    }

    #[test]
    fn test_cache_save_and_load_roundtrip() {
        let dir = tempdir().unwrap();
        let cache_path = dir.path().join("cache.bin");

        let records = vec![
            make_test_record(1, 1024),
            make_test_record(2, 2048),
            make_test_record(3, 4096),
        ];

        save_scan(&cache_path, &records, &[]).unwrap();
        let loaded = load_latest(&cache_path).unwrap();

        assert_eq!(loaded.len(), 3);
        assert_eq!(loaded[0].node_id, 1);
        assert_eq!(loaded[0].logical_size, 1024);
        assert_eq!(loaded[1].node_id, 2);
        assert_eq!(loaded[2].node_id, 3);
    }

    #[test]
    fn test_cache_empty_records() {
        let dir = tempdir().unwrap();
        let cache_path = dir.path().join("cache_empty.bin");

        let records: Vec<FileRecord> = vec![];
        save_scan(&cache_path, &records, &[]).unwrap();
        let loaded = load_latest(&cache_path).unwrap();

        assert!(loaded.is_empty());
    }

    #[test]
    fn test_cache_corrupted_magic() {
        let dir = tempdir().unwrap();
        let cache_path = dir.path().join("corrupted_magic.bin");

        let records = vec![make_test_record(1, 1024)];
        save_scan(&cache_path, &records, &[]).unwrap();

        // Corrupt the magic bytes
        use std::fs::OpenOptions;
        let mut file = OpenOptions::new().write(true).open(&cache_path).unwrap();
        use std::io::Write;
        file.write_all(b"WRONGMAGIC!").unwrap();

        let loaded = load_latest(&cache_path);
        assert!(loaded.is_none());
    }

    #[test]
    fn test_cache_wrong_version() {
        let dir = tempdir().unwrap();
        let cache_path = dir.path().join("wrong_version.bin");

        let records = vec![make_test_record(1, 1024)];
        save_scan(&cache_path, &records, &[]).unwrap();

        // Corrupt the version bytes
        use std::fs::OpenOptions;
        let mut file = OpenOptions::new().write(true).open(&cache_path).unwrap();
        use std::io::Write;
        file.write_all(&[0xFF, 0xFF, 0xFF, 0xFF]).unwrap(); // Wrong version

        let loaded = load_latest(&cache_path);
        assert!(loaded.is_none());
    }

    #[test]
    fn test_cache_missing_file() {
        let dir = tempdir().unwrap();
        let cache_path = dir.path().join("nonexistent.bin");

        let loaded = load_latest(&cache_path);
        assert!(loaded.is_none());
    }

    #[test]
    fn test_cache_truncated_file() {
        let dir = tempdir().unwrap();
        let cache_path = dir.path().join("truncated.bin");

        // Write only partial header (magic + version but no count/records)
        use std::fs::File;
        use std::io::Write;
        let mut file = File::create(&cache_path).unwrap();
        file.write_all(CACHE_MAGIC).unwrap();
        file.write_all(&CACHE_VERSION.to_le_bytes()).unwrap();
        // Missing: count + records

        let loaded = load_latest(&cache_path);
        assert!(loaded.is_none(), "Truncated file should return None, not panic");
    }

    #[test]
    fn test_cache_single_record() {
        let dir = tempdir().unwrap();
        let cache_path = dir.path().join("single.bin");

        let records = vec![make_test_record(42, 12345)];
        save_scan(&cache_path, &records, &[]).unwrap();
        let loaded = load_latest(&cache_path).unwrap();

        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].node_id, 42);
        assert_eq!(loaded[0].logical_size, 12345);
    }
}
