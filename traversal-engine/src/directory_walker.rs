//! `directory_walker.rs` — Directory reading via `getattrlistbulk(2)`.
//!
//! One `getattrlistbulk` call returns metadata for many entries at once. The
//! `read_dir` + per-entry `metadata()` alternative costs one to two kernel
//! transitions per file, which is what the whole scan-time budget is spent on.
//!
//! `getattrlistbulk` is not available on every filesystem — some network mounts
//! and FUSE volumes reject it — so [`walk_directory`] falls back to the
//! portable path when the syscall fails.

use libc::{
    attrlist, c_void, getattrlistbulk, ATTR_BIT_MAP_COUNT, ATTR_CMN_MODTIME, ATTR_CMN_NAME,
    ATTR_CMN_OBJTYPE, ATTR_CMN_RETURNED_ATTRS, ATTR_FILE_ALLOCSIZE, ATTR_FILE_DATAALLOCSIZE,
    ATTR_FILE_TOTALSIZE, FSOPT_NOFOLLOW,
};
use std::fs::{self, File};
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::Path;

/// One directory entry returned by the walker.
#[derive(Debug, Clone)]
pub struct BulkEntry {
    pub name: String,
    /// Logical size — the file's length.
    pub size: u64,
    /// Bytes actually allocated on disk, from `ATTR_FILE_DATAALLOCSIZE` — the
    /// same number `du` and Finder report. Much smaller than `size` for sparse
    /// files, and rounded up to a block for ordinary ones.
    ///
    /// Note this does **not** deduplicate APFS clones: two clones of one file
    /// each report their full allocation, so summing them counts the shared
    /// storage twice. Every standard tool behaves this way; reporting shared
    /// extents once is deferred.
    pub physical_size: u64,
    pub mode: u32,
    pub mtime: i64,
    pub is_dir: bool,
    pub is_symlink: bool,
}

/// Buffer handed to `getattrlistbulk`, per the 128KB-per-thread design in
/// thread. Larger buffers return more entries per syscall;
/// past this size the gain flattens and the memory is wasted per worker.
const BULK_BUFFER_SIZE: usize = 128 * 1024;

// `fsobj_type_t` values from <sys/vnode.h>.
const VDIR: u32 = 2;
const VLNK: u32 = 5;

/// Read the entries of a directory.
///
/// Tries `getattrlistbulk` first and falls back to `read_dir` if the syscall is
/// unsupported on the underlying filesystem.
pub fn walk_directory<P: AsRef<Path>>(path: P, exclude_hidden: bool) -> io::Result<Vec<BulkEntry>> {
    match bulk_walk(path.as_ref(), exclude_hidden) {
        Ok(entries) => Ok(entries),
        // Only the syscall being unsupported justifies the slow path. A real
        // error (permission, gone) should surface, not be retried and reported
        // as a different error.
        Err(e) if is_unsupported(&e) => fallback_walk(path.as_ref(), exclude_hidden),
        Err(e) => Err(e),
    }
}

fn is_unsupported(e: &io::Error) -> bool {
    matches!(
        e.raw_os_error(),
        Some(libc::ENOTSUP) | Some(libc::EINVAL) | Some(libc::ENOSYS)
    )
}

/// The `getattrlistbulk` path.
fn bulk_walk(path: &Path, exclude_hidden: bool) -> io::Result<Vec<BulkEntry>> {
    let dir = File::open(path)?;

    // ATTR_CMN_RETURNED_ATTRS is always returned first, immediately after the
    // entry length, and says which of the requested attributes this entry
    // actually carries. That is not a formality: file attributes are simply
    // absent from a directory's entry, so the record is a different size and
    // every subsequent field shifts. Parsing must be driven by this bitmap.
    //
    // FSOPT_PACK_INVAL_ATTRS is deliberately not used. It does not zero-fill
    // across attribute groups — a directory entry still omits ALLOCSIZE
    // entirely — so it would not buy a fixed layout, only the illusion of one.
    let mut attrs = attrlist {
        bitmapcount: ATTR_BIT_MAP_COUNT,
        reserved: 0,
        commonattr: ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME,
        volattr: 0,
        // Not requesting ATTR_DIR_ENTRYCOUNT: child counts are recomputed from
        // the records the scanner keeps, which stays correct when entries are
        // filtered out.
        dirattr: 0,
        fileattr: ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE | ATTR_FILE_DATAALLOCSIZE,
        forkattr: 0,
    };

    // NOFOLLOW so a symlink reports itself rather than its target; following
    // would count the target's bytes twice.
    let options = FSOPT_NOFOLLOW as u64;
    let mut buffer = vec![0u8; BULK_BUFFER_SIZE];
    let mut entries = Vec::new();

    loop {
        // SAFETY: `attrs` and `buffer` are live and correctly sized for the
        // duration of the call; the kernel writes at most `buffer.len()` bytes.
        let count = unsafe {
            getattrlistbulk(
                dir.as_raw_fd(),
                &mut attrs as *mut attrlist as *mut c_void,
                buffer.as_mut_ptr() as *mut c_void,
                buffer.len(),
                options,
            )
        };

        if count < 0 {
            return Err(io::Error::last_os_error());
        }
        if count == 0 {
            break; // end of directory
        }

        let mut offset = 0usize;
        for _ in 0..count {
            let (entry, entry_len) = parse_entry(&buffer[offset..])?;
            offset += entry_len;

            if let Some(entry) = entry {
                if exclude_hidden && entry.name.starts_with('.') {
                    continue;
                }
                entries.push(entry);
            }
        }
    }

    Ok(entries)
}

/// Read a little-endian value out of `buf` at `offset`.
///
/// Every attribute the kernel packs is naturally aligned, but the buffer itself
/// is a `Vec<u8>` with no such guarantee, so reads go through `read_unaligned`
/// rather than a reference cast.
fn read_at<T: Copy>(buf: &[u8], offset: usize) -> io::Result<T> {
    let size = std::mem::size_of::<T>();
    if offset + size > buf.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "getattrlistbulk entry truncated",
        ));
    }
    // SAFETY: bounds checked above; T is Copy and read unaligned.
    Ok(unsafe { std::ptr::read_unaligned(buf.as_ptr().add(offset) as *const T) })
}

/// Parse one entry from the start of `buf`.
///
/// Returns the entry (or `None` when its name could not be decoded) and the
/// number of bytes this entry occupies, which is what advances the cursor. The
/// declared length is authoritative — parsing may stop early, but the next
/// entry always begins at `start + length`.
///
/// Attributes are packed in bitmap order with no padding beyond their own
/// 4-byte granularity, and **only attributes flagged in `returned` are
/// present**. A directory entry carries no size fields at all; reading them at
/// a fixed offset yields whatever follows, which is a plausible-looking wrong
/// number rather than an error.
fn parse_entry(buf: &[u8]) -> io::Result<(Option<BulkEntry>, usize)> {
    let length: u32 = read_at(buf, 0)?;
    let length = length as usize;
    if length == 0 || length > buf.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "getattrlistbulk entry length out of range",
        ));
    }

    let mut cursor = std::mem::size_of::<u32>();

    // attribute_set_t — which of the requested attributes this entry carries.
    let returned: [u32; 5] = read_at(buf, cursor)?;
    cursor += std::mem::size_of::<[u32; 5]>();
    let (common_ok, file_ok) = (returned[0], returned[3]);

    // ATTR_CMN_NAME — attrreference_t { i32 offset, u32 length }, where the
    // offset is relative to the start of the reference itself.
    let mut name = None;
    if common_ok & ATTR_CMN_NAME != 0 {
        let ref_at = cursor;
        let data_offset: i32 = read_at(buf, ref_at)?;
        let data_len: u32 = read_at(buf, ref_at + 4)?;
        cursor += 8;

        let start = (ref_at as isize + data_offset as isize) as usize;
        // attr_length counts the trailing NUL.
        let end = start + data_len.saturating_sub(1) as usize;
        if start <= end && end <= buf.len() {
            name = Some(String::from_utf8_lossy(&buf[start..end]).into_owned());
        }
    }

    let mut obj_type = 0u32;
    if common_ok & ATTR_CMN_OBJTYPE != 0 {
        obj_type = read_at(buf, cursor)?;
        cursor += std::mem::size_of::<u32>();
    }

    let mut mtime = 0i64;
    if common_ok & ATTR_CMN_MODTIME != 0 {
        mtime = read_at(buf, cursor)?; // timespec.tv_sec; tv_nsec unused
        cursor += std::mem::size_of::<libc::timespec>();
    }

    // Present on file entries only.
    let mut logical = 0u64;
    if file_ok & ATTR_FILE_TOTALSIZE != 0 {
        let v: i64 = read_at(buf, cursor)?;
        cursor += std::mem::size_of::<i64>();
        logical = v.max(0) as u64;
    }

    // ALLOCSIZE covers every fork, but on APFS it reports the rounded-up
    // logical size even for a sparse file — a 64MB sparse file that occupies
    // no blocks comes back as 64MB. DATAALLOCSIZE reports what is actually
    // allocated and matches `du` exactly, so it wins when both are present.
    // Read in bitmap order: TOTALSIZE (0x2), ALLOCSIZE (0x4), DATAALLOCSIZE
    // (0x400).
    let mut alloc = None;
    if file_ok & ATTR_FILE_ALLOCSIZE != 0 {
        let v: i64 = read_at(buf, cursor)?;
        cursor += std::mem::size_of::<i64>();
        alloc = Some(v.max(0) as u64);
    }
    let mut data_alloc = None;
    if file_ok & ATTR_FILE_DATAALLOCSIZE != 0 {
        let v: i64 = read_at(buf, cursor)?;
        data_alloc = Some(v.max(0) as u64);
    }

    // Last resort is the logical size: under-reporting disk usage is the worse
    // failure, since it makes a large file look harmless.
    let physical = data_alloc.or(alloc).unwrap_or(logical);

    let Some(name) = name else {
        return Ok((None, length));
    };

    let is_dir = obj_type == VDIR;
    let is_symlink = obj_type == VLNK;

    // A directory's own size is not part of the total; its children supply it.
    let (size, physical_size) = if is_dir { (0, 0) } else { (logical, physical) };

    Ok((
        Some(BulkEntry {
            name,
            size,
            physical_size,
            mode: 0,
            mtime,
            is_dir,
            is_symlink,
        }),
        length,
    ))
}

/// Portable `read_dir` path, used when `getattrlistbulk` is unsupported.
///
/// `std::fs::Metadata` exposes `st_blocks`, so allocated size is still
/// available here — the cost is one `stat` per entry rather than one syscall
/// per batch.
fn fallback_walk(path: &Path, exclude_hidden: bool) -> io::Result<Vec<BulkEntry>> {
    use std::os::unix::fs::MetadataExt;

    let mut entries = Vec::new();
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if exclude_hidden && name.starts_with('.') {
            continue;
        }

        // symlink_metadata, not metadata: following a symlink counts the
        // target's bytes a second time.
        let md = entry.path().symlink_metadata()?;
        let is_dir = md.is_dir();
        let size = if is_dir { 0 } else { md.len() };
        // st_blocks is always in 512-byte units, regardless of block size.
        let physical_size = if is_dir { 0 } else { md.blocks() * 512 };

        entries.push(BulkEntry {
            name,
            size,
            physical_size,
            mode: 0,
            mtime: md.mtime(),
            is_dir,
            is_symlink: md.is_symlink(),
        });
    }
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    /// The parser is the risky part: a wrong offset yields plausible-looking
    /// garbage rather than an error. Checking it against `std::fs` on a real
    /// directory is what catches that.
    #[test]
    fn bulk_matches_std_fs() {
        let dir = tempfile::tempdir().unwrap();
        for (name, size) in [("a.txt", 10usize), ("b.bin", 5000), ("empty", 0)] {
            let mut f = File::create(dir.path().join(name)).unwrap();
            f.write_all(&vec![b'x'; size]).unwrap();
        }
        fs::create_dir(dir.path().join("subdir")).unwrap();

        let entries = walk_directory(dir.path(), false).unwrap();
        assert_eq!(entries.len(), 4, "expected 3 files + 1 directory");

        for entry in &entries {
            let md = fs::symlink_metadata(dir.path().join(&entry.name)).unwrap();
            assert_eq!(entry.is_dir, md.is_dir(), "{}: is_dir", entry.name);

            if entry.is_dir {
                continue;
            }
            assert_eq!(entry.size, md.len(), "{}: logical size", entry.name);
            assert!(entry.mtime > 0, "{}: mtime should be populated", entry.name);
            // Allocated size is rounded up to a block, so it is never less than
            // the logical size for a non-sparse file.
            assert!(
                entry.physical_size >= entry.size,
                "{}: allocated {} < logical {}",
                entry.name,
                entry.physical_size,
                entry.size
            );
        }
    }

    /// A sparse file allocates far fewer bytes than its length. This is what
    /// distinguishes a real allocated-size read from the logical size copied
    /// into the physical field, which is the bug this replaced. It also pins
    /// the choice of DATAALLOCSIZE over ALLOCSIZE: on APFS the latter reports
    /// the full 64MB here.
    #[test]
    fn reports_allocated_not_logical_size() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sparse.bin");
        let f = File::create(&path).unwrap();
        f.set_len(64 * 1024 * 1024).unwrap(); // 64MB long, nothing written
        drop(f);

        let entries = walk_directory(dir.path(), false).unwrap();
        let sparse = entries.iter().find(|e| e.name == "sparse.bin").unwrap();

        assert_eq!(sparse.size, 64 * 1024 * 1024, "logical size is the length");
        assert!(
            sparse.physical_size < sparse.size,
            "sparse file allocated {} for a {}-byte length — physical size is \
             still tracking logical",
            sparse.physical_size,
            sparse.size
        );
    }

    /// APFS clones share storage on disk, but each reports its full allocated
    /// size — so a folder holding a file and its clone reports both. `du`,
    /// Finder and every comparable tool agree, and reporting shared extents
    /// once is a deferred feature, so this pins the behaviour rather than
    /// leaving it to be rediscovered as a bug.
    #[test]
    fn clones_are_counted_separately() {
        let dir = tempfile::tempdir().unwrap();
        let orig = dir.path().join("orig.bin");
        let mut f = File::create(&orig).unwrap();
        f.write_all(&vec![b'q'; 3_000_000]).unwrap();
        drop(f);

        // -c asks for a clone; APFS-only, so skip elsewhere.
        let cloned = std::process::Command::new("/bin/cp")
            .arg("-c")
            .arg(&orig)
            .arg(dir.path().join("clone.bin"))
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !cloned {
            return;
        }

        let entries = walk_directory(dir.path(), false).unwrap();
        let total: u64 = entries.iter().map(|e| e.physical_size).sum();
        assert!(
            total >= 6_000_000,
            "clones reported {total} total — if this drops to ~3MB the walker \
             started deduplicating shared extents, which is a behaviour change"
        );
    }

    #[test]
    fn excludes_hidden_when_asked() {
        let dir = tempfile::tempdir().unwrap();
        File::create(dir.path().join("visible.txt")).unwrap();
        File::create(dir.path().join(".hidden")).unwrap();

        let all = walk_directory(dir.path(), false).unwrap();
        assert_eq!(all.len(), 2);

        let visible = walk_directory(dir.path(), true).unwrap();
        assert_eq!(visible.len(), 1);
        assert_eq!(visible[0].name, "visible.txt");
    }

    #[test]
    fn reads_long_names_and_many_entries() {
        // Forces more than one getattrlistbulk call, exercising the outer loop
        // and the name-reference offsets across buffer boundaries.
        let dir = tempfile::tempdir().unwrap();
        for i in 0..600 {
            File::create(dir.path().join(format!("entry-{i:04}-{}", "n".repeat(80)))).unwrap();
        }
        let entries = walk_directory(dir.path(), false).unwrap();
        assert_eq!(entries.len(), 600);
        assert!(entries.iter().all(|e| e.name.starts_with("entry-")));
    }

    #[test]
    fn symlink_is_not_followed() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("target.bin");
        let mut f = File::create(&target).unwrap();
        f.write_all(&vec![b'x'; 100_000]).unwrap();
        std::os::unix::fs::symlink(&target, dir.path().join("link")).unwrap();

        let entries = walk_directory(dir.path(), false).unwrap();
        let link = entries.iter().find(|e| e.name == "link").unwrap();
        assert!(link.is_symlink);
        assert!(
            link.size < 1000,
            "symlink reported {} bytes — the target's size is being counted twice",
            link.size
        );
    }

    #[test]
    fn fallback_agrees_with_bulk() {
        let dir = tempfile::tempdir().unwrap();
        for (name, size) in [("x.txt", 10usize), ("y.bin", 9000)] {
            let mut f = File::create(dir.path().join(name)).unwrap();
            f.write_all(&vec![b'z'; size]).unwrap();
        }

        let mut bulk = bulk_walk(dir.path(), false).unwrap();
        let mut fallback = fallback_walk(dir.path(), false).unwrap();
        bulk.sort_by(|a, b| a.name.cmp(&b.name));
        fallback.sort_by(|a, b| a.name.cmp(&b.name));

        assert_eq!(bulk.len(), fallback.len());
        for (b, f) in bulk.iter().zip(fallback.iter()) {
            assert_eq!(b.name, f.name);
            assert_eq!(b.size, f.size, "{}: logical size disagrees", b.name);
            assert_eq!(
                b.physical_size, f.physical_size,
                "{}: allocated size disagrees between the two paths",
                b.name
            );
        }
    }
}
