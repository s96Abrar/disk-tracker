//! `scanner.rs` — High-level scanner for directory traversal.

use crate::directory_walker;
use crate::file_record::{append_to_string_table, FileRecord, NodeType};
use rayon::scope;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

/// Scan configuration mirrored from the Swift side.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct ScanConfig {
    pub exclude_system_paths: bool,
    pub exclude_hidden_files: bool,
    pub follow_symlinks: bool,
    pub max_depth: u32,
}

impl Default for ScanConfig {
    fn default() -> Self {
        ScanConfig {
            exclude_system_paths: true, // Safety: exclude system paths by default
            exclude_hidden_files: false,
            follow_symlinks: false,
            max_depth: u32::MAX, // Unlimited depth by default
        }
    }
}

/// Per-scan mutable state shared across worker threads.
pub struct ScanState {
    pub config: ScanConfig,
    pub cancelled: AtomicBool,
    pub progress: AtomicU64,
    pub results: Mutex<Vec<FileRecord>>,
    pub string_table: Mutex<Vec<u8>>,
    pub next_id: Mutex<u64>,
}

impl ScanState {
    pub fn new(config: ScanConfig) -> Self {
        ScanState {
            config,
            cancelled: AtomicBool::new(false),
            progress: AtomicU64::new(0),
            results: Mutex::new(Vec::with_capacity(4096)),
            string_table: Mutex::new(Vec::with_capacity(256 * 1024)),
            next_id: Mutex::new(1), // 0 = root
        }
    }
}

/// Scan result returned to the FFI layer.
#[derive(Debug)]
pub struct ScanResult {
    pub records: Vec<FileRecord>,
    pub string_table: Vec<u8>,
}

/// How often the progress monitor samples the entry counter.
const PROGRESS_POLL_MS: u64 = 50;

/// Start a recursive scan of `root_path`.
///
/// `on_progress` receives the number of entries seen so far, sampled every
/// `PROGRESS_POLL_MS`, plus one final exact count. The total is unknowable
/// until the walk finishes, so this is a count and not a 0.0–1.0 fraction.
pub fn scan_directory(
    root_path: &std::path::Path,
    config: ScanConfig,
    on_progress: impl Fn(u64) + Send + Sync + 'static,
) -> Result<ScanResult, ScanError> {
    let state = Arc::new(ScanState::new(config));

    // Add the root directory itself first, so it has a real node_id > 0.
    // All top-level items scanned under root will use this as their parent_id.
    {
        let mut records = state.results.lock().unwrap();
        let mut strings = state.string_table.lock().unwrap();
        let mut next_id = state.next_id.lock().unwrap();
        let name = root_path.file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| root_path.to_string_lossy().into_owned());
        let name_offset = append_to_string_table(&mut strings, &name);
        let node_id = *next_id;
        *next_id += 1;
        let root_record = FileRecord {
            node_id,
            parent_id: 0,
            name_offset,
            name_len: name.len() as u32,
            logical_size: 0,
            physical_size: 0,
            node_type: NodeType::Directory as u8,
            is_system_protected: false,
            mod_time_secs: 0,
            depth: 0,
            child_count: 0,
            first_child_id: 0,
            padding: [0; 6],
        };
        records.push(root_record);
    }

    // ponytail: ScanState.progress AtomicU64 set (fetch_add) but never queried; progress contract partial. Read available if needed.
    // Parallel traversal: one Rayon task per directory. The expensive part is
    // the read_dir + per-entry stat() in walk_directory, which runs without
    // holding any lock. Record building + node_id assignment happen under the
    // shared lock (cheap, memcpy-only), keeping ids unique. Children are
    // spawned after the parent's records are committed, so parent_id is always
    // known. ponytail: scope-based work stealing — no manual thread pool.
    // Progress reporting: one thread polls the shared counter, rather than
    // threading a callback down through every walk task. Emits a final exact
    // count after the walk stops.
    let monitor_state = state.clone();
    let scanning = Arc::new(AtomicBool::new(true));
    let monitor_flag = scanning.clone();
    let monitor = std::thread::spawn(move || {
        while monitor_flag.load(Ordering::Relaxed) {
            std::thread::sleep(std::time::Duration::from_millis(PROGRESS_POLL_MS));
            on_progress(monitor_state.progress.load(Ordering::Relaxed));
        }
        on_progress(monitor_state.progress.load(Ordering::Relaxed));
    });

    let root_state = state.clone();
    scope(|s| {
        s.spawn(move |s| walk_dir_task(s, root_path.to_path_buf(), 1, 1, &root_state));
    });

    scanning.store(false, Ordering::Relaxed);
    let _ = monitor.join();

    // Build child_link from the accumulated results, then patch
    // first_child_id / child_count for all directory records.
    let mut records = state.results.lock().unwrap();
    let mut child_link: std::collections::HashMap<u64, (u64, u32)> = std::collections::HashMap::new();

    for rec in records.iter() {
        // Include root (parent_id=0) so root gets first_child_id/child_count.
        let entry = child_link.entry(rec.parent_id).or_insert((rec.node_id, 0));
        entry.1 += 1;
    }

    // Now update parent records: those whose node_id is a key in child_link
    for rec in records.iter_mut() {
        if let Some((first_child_node_id, count)) = child_link.get(&rec.node_id) {
            rec.first_child_id = *first_child_node_id;
            rec.child_count = *count;
        }
    }

    let string_table = state.string_table.lock().unwrap().clone();
    let result_records = records.clone();

    Ok(ScanResult { records: result_records, string_table })
}

/// Process one directory: walk it (no lock), build records under the shared
/// lock, then spawn a child task for each subdirectory. `scope` provides
/// work-stealing parallelism; failures walking a single dir are skipped.
fn walk_dir_task<'sc>(
    s: &rayon::Scope<'sc>,
    path: PathBuf,
    depth: u16,
    parent_id: u64,
    state: &Arc<ScanState>,
) {
    if state.cancelled.load(Ordering::Relaxed) {
        return;
    }

    // Expensive I/O outside the lock: read_dir + per-entry metadata().
    let entries = match directory_walker::walk_directory(&path, state.config.exclude_hidden_files) {
        Ok(e) => e,
        Err(_) => return,
    };
    if entries.is_empty() {
        return;
    }

    // Build records for this dir under the shared lock. memcpy-only, so the
    // critical section is short; ids stay unique because this is the only
    // place `next_id` advances.
    let mut children: Vec<(PathBuf, u64)> = Vec::new();
    let entry_count = entries.len() as u64;
    {
        let mut records = state.results.lock().unwrap();
        let mut strings = state.string_table.lock().unwrap();
        let mut next_id = state.next_id.lock().unwrap();
        let max_depth_ok = state.config.max_depth == u32::MAX || (depth as u32) < state.config.max_depth;

        for entry in entries {
            let name_offset = append_to_string_table(&mut strings, &entry.name);
            let node_id = *next_id;
            *next_id += 1;

            let record = FileRecord {
                node_id,
                parent_id,
                name_offset,
                name_len: entry.name.len() as u32,
                logical_size: entry.size,
                physical_size: entry.physical_size,
                node_type: if entry.is_dir {
                    NodeType::Directory as u8
                } else if entry.is_symlink {
                    NodeType::Symlink as u8
                } else {
                    NodeType::File as u8
                },
                is_system_protected: false,
                mod_time_secs: entry.mtime,
                depth,
                child_count: 0,
                first_child_id: 0,
                padding: [0; 6],
            };
            records.push(record);

            if entry.is_dir && max_depth_ok {
                let mut child_path = PathBuf::from(&path);
                child_path.push(&entry.name);
                children.push((child_path, node_id));
            }
        }
        // Count entries, not directories — this is what the UI reports as
        // "items scanned".
        state.progress.fetch_add(entry_count, Ordering::Relaxed);
    } // lock released before spawning children

    for (child_path, child_id) in children {
        let st = state.clone();
        s.spawn(move |s| walk_dir_task(s, child_path, depth + 1, child_id, &st));
    }
}

#[derive(Debug)]
pub enum ScanError {
    Io(std::io::Error),
    Cancelled,
}

impl From<std::io::Error> for ScanError {
    fn from(e: std::io::Error) -> Self {
        ScanError::Io(e)
    }
}
