//! `directory_walker.rs` — Portable directory walking with stat()-based fallback.
//!
//! getattrlistbulk(2) requires complex setup; for MVP we use a reliable
//! std::fs + stat()-based walk.  The bulk path is wired once the Darwin
//! FFI stabilises.

use std::fs;
use std::io;
use std::path::Path;

/// One directory entry returned by the walker.
#[derive(Debug, Clone)]
pub struct BulkEntry {
    pub name: String,
    pub size: u64,
    /// Physical size on disk (equals `size` on non-APFS).
    pub physical_size: u64,
    pub mode: u32,
    pub mtime: i64,
    pub is_dir: bool,
    pub is_symlink: bool,
}

/// Read entries from a directory using the standard library.
/// This is the portable fallback; `getattrlistbulk(2)` will replace it in Phase 2.
pub fn walk_directory<P: AsRef<Path>>(
    path: P,
    exclude_hidden: bool,
) -> io::Result<Vec<BulkEntry>> {
    let mut entries = Vec::new();
    let dir = fs::read_dir(path.as_ref())?;
    
    for entry in dir {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        
        if exclude_hidden && name.starts_with('.') {
            continue;
        }
        
        let md = entry.metadata()?;
        let is_dir = md.is_dir();
        let is_symlink = md.is_symlink();

        // For symlinks, size is of the target (metadata follows symlinks)
        let size = md.len();
        
        let mtime = md.modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        
        entries.push(BulkEntry {
            name,
            size,
            physical_size: size,  // TODO: query ATTR_FILE_ALLOCSIZE on APFS
            mode: 0,              // not needed for MVP
            mtime,
            is_dir,
            is_symlink,
        });
    }
    
    Ok(entries)
}

/// Open a directory for reading (compatibility shim for getattrlistbulk path).
pub fn open_dir<P: AsRef<Path>>(_path: P) -> io::Result<fs::DirEntry> {
    // Not used in fallback implementation
    Err(io::Error::new(io::ErrorKind::Unsupported, "use walk_directory"))
}

/// Close directory — no-op for std::fs fallback.
pub fn close_dir(_fd: i32) {}

/// Bulk read — not used with std::fs fallback; kept for API compat.
pub fn bulk_read(_dir_fd: i32, _buf: &mut [u8]) -> io::Result<(Vec<BulkEntry>, bool)> {
    Err(io::Error::new(io::ErrorKind::Unsupported, "use walk_directory"))
}
