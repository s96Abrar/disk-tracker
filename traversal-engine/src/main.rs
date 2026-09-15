//! Rust CLI binary for Disk Tracker.
//!
//! Usage: `disk-tracker-engine scan <path> [--format=binary|json]
//!        [--exclude-hidden] [--exclude <path>]...`
//!
//! The app spawns this and reads the scan result from stdout. `binary` is the
//! product path (see `wire.rs`); `json` exists so a scan can be inspected by
//! hand without a decoder, and nothing in the app reads it.
//!
//! Progress goes to stderr as `progress <count>` lines, one per sample, so
//! stdout stays a single clean payload.

use disk_tracker_engine::scanner::{scan_directory_excluding, ScanConfig};
use disk_tracker_engine::wire;
use std::env;
use std::io::Write;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 3 || args[1] != "scan" {
        eprintln!(
            "Usage: disk-tracker-engine scan <path> [--format=binary|json] \
             [--exclude-hidden] [--exclude <path>]..."
        );
        process::exit(1);
    }

    let path = &args[2];
    let json_mode = args.iter().any(|a| a == "--format=json");

    let config = ScanConfig {
        exclude_hidden_files: args.iter().any(|a| a == "--exclude-hidden"),
        ..ScanConfig::default()
    };

    // `--exclude <path>`, repeatable. A trailing `--exclude` with no value is
    // ignored rather than treated as an empty path, which would match nothing
    // useful and confuse the caller.
    let mut excluded: Vec<std::path::PathBuf> = Vec::new();
    let mut i = 3;
    while i < args.len() {
        if args[i] == "--exclude" {
            if let Some(value) = args.get(i + 1) {
                excluded.push(std::path::PathBuf::from(value));
                i += 1;
            }
        }
        i += 1;
    }

    let result =
        match scan_directory_excluding(std::path::Path::new(path), config, excluded, |scanned| {
            eprintln!("progress {}", scanned);
        }) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("Scan error: {:?}", e);
                process::exit(1);
            }
        };

    if json_mode {
        print_json(&result);
        return;
    }

    let buf = wire::encode(&result.records, &result.string_table);
    // Lock stdout and write once. `println!` would take the lock per call and
    // this payload is tens of megabytes on a real scan.
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    if let Err(e) = out.write_all(&buf).and_then(|_| out.flush()) {
        // A broken pipe means the app cancelled the scan and closed its end.
        // That is a normal cancellation, not a failure worth reporting.
        if e.kind() != std::io::ErrorKind::BrokenPipe {
            eprintln!("Write error: {}", e);
            process::exit(1);
        }
    }
}

/// Human-readable dump for debugging. Not used by the app.
fn print_json(result: &disk_tracker_engine::scanner::ScanResult) {
    #[derive(serde::Serialize)]
    struct JsonRecord<'a> {
        node_id: u64,
        parent_id: u64,
        name: &'a str,
        logical_size: u64,
        physical_size: u64,
        node_type: u8,
        is_system_protected: bool,
        mod_time_secs: i64,
        depth: u16,
        child_count: u32,
    }

    let table = &result.string_table;
    let records: Vec<JsonRecord> = result
        .records
        .iter()
        .map(|r| {
            let start = r.name_offset as usize;
            let end = (start + r.name_len as usize).min(table.len());
            JsonRecord {
                node_id: r.node_id,
                parent_id: r.parent_id,
                name: std::str::from_utf8(&table[start..end]).unwrap_or(""),
                logical_size: r.logical_size,
                physical_size: r.physical_size,
                node_type: r.node_type,
                is_system_protected: r.is_system_protected,
                mod_time_secs: r.mod_time_secs,
                depth: r.depth,
                child_count: r.child_count,
            }
        })
        .collect();

    println!("{}", serde_json::to_string(&records).unwrap());
}
