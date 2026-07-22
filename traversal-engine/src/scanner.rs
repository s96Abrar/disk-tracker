//! `scanner.rs` — High-level scanner for directory traversal.

use crate::directory_walker;
use crate::file_record::{append_to_string_table, FileRecord, NodeType};
use rayon::prelude::*;
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

/// Start a recursive scan of `root_path`.
pub fn scan_directory(
    root_path: &std::path::Path,
    config: ScanConfig,
    on_progress: impl Fn(f64) + Send + Sync + 'static,
) -> Result<ScanResult, ScanError> {
    let state = Arc::new(ScanState::new(config));

    // BFS: process directories level by level so parent_id is always known.
    // Each entry is (path, depth, parent_node_id).
    let mut todo: Vec<(PathBuf, u16, u64)> = vec![(root_path.to_path_buf(), 0, 0)];

    while let Some((path, depth, parent_id)) = todo.pop() {
        if state.cancelled.load(Ordering::Relaxed) {
            return Err(ScanError::Cancelled);
        }

        let entries = match directory_walker::walk_directory(&path, state.config.exclude_hidden_files) {
            Ok(e) => e,
            Err(_) => continue,
        };

        let mut records = state.results.lock().unwrap();
        let mut strings = state.string_table.lock().unwrap();
        let mut next_id = state.next_id.lock().unwrap();

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

            // Queue directory children for later processing
            if entry.is_dir && (state.config.max_depth == u32::MAX || (depth as u32) < state.config.max_depth) {
                let mut child_path = PathBuf::from(&path);
                child_path.push(&entry.name);
                todo.push((child_path, depth + 1, node_id));
            }
        }
    }

    on_progress(1.0);

    // Fix child_count and first_child_id by building parent index
    drop(todo);
    let mut records = state.results.lock().unwrap();
    let mut child_link: std::collections::HashMap<u64, (u64, u32)> = std::collections::HashMap::new();

    for rec in records.iter() {
        if rec.parent_id != 0 {
            let entry = child_link.entry(rec.parent_id).or_insert((rec.node_id, 0));
            entry.1 += 1;
        }
    }

    for rec in records.iter_mut() {
        if rec.parent_id != 0 {
            if let Some((first_child_id, count)) = child_link.get(&rec.parent_id) {
                rec.first_child_id = *first_child_id;
                rec.child_count = *count;
            }
        }
    }

    let string_table = state.string_table.lock().unwrap().clone();
    let result_records = records.clone();

    Ok(ScanResult { records: result_records, string_table })
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
