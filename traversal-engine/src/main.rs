//! Rust CLI binary for Disk Tracker.
//! Usage: disk-tracker-engine scan <path> [--format=json]

use disk_tracker_engine::scanner::{scan_directory, ScanConfig};
use std::env;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 3 {
        eprintln!("Usage: disk-tracker-engine scan <path> [--format=json]");
        process::exit(1);
    }

    let cmd = &args[1];
    if cmd != "scan" {
        eprintln!("Unknown command: {}", cmd);
        process::exit(1);
    }

    let path = &args[2];
    let json_mode = args.iter().any(|a| a.contains("json"));

    if !json_mode {
        eprintln!("Use --format=json for machine-readable output");
        process::exit(1);
    }

    let config = ScanConfig::default();
    match scan_directory(std::path::Path::new(path), config, |_| {}) {
        Ok(result) => {
            #[derive(serde::Serialize)]
            struct RRecord {
                node_id: u64,
                parent_id: u64,
                name: String,
                name_offset: u32,
                name_len: u32,
                logical_size: u64,
                physical_size: u64,
                node_type: u8,
                is_system_protected: bool,
                mod_time_secs: i64,
                depth: u16,
                child_count: u32,
                first_child_id: u64,
            }

            #[derive(serde::Serialize)]
            struct RScanOutput<'a> {
                records: Vec<RRecord>,
                string_table: &'a [u8],
            }

            let string_table = &result.string_table;
            let records: Vec<RRecord> = result.records.iter().map(|r| {
                let name = unsafe {
                    let start = string_table.as_ptr().add(r.name_offset as usize);
                    let len = r.name_len as usize;
                    std::slice::from_raw_parts(start, len)
                };
                let name_str = String::from_utf8_lossy(name).to_string();
                RRecord {
                    node_id: r.node_id,
                    parent_id: r.parent_id,
                    name: name_str,
                    name_offset: r.name_offset,
                    name_len: r.name_len,
                    logical_size: r.logical_size,
                    physical_size: r.physical_size,
                    node_type: r.node_type,
                    is_system_protected: r.is_system_protected,
                    mod_time_secs: r.mod_time_secs,
                    depth: r.depth,
                    child_count: r.child_count,
                    first_child_id: r.first_child_id,
                }
            }).collect();

            let output = RScanOutput { records, string_table };
            println!("{}", serde_json::to_string(&output).unwrap());
        }
        Err(e) => {
            eprintln!("Scan error: {:?}", e);
            process::exit(1);
        }
    }
}