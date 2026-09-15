//! Scale tests — the performance targets from `2_BUILD_PLAN.md` §3, measured.
//!
//! The existing `performance_tests.rs` stops at 10K files against a 1M target,
//! which proves the scanner runs but not that it meets its budget.
//!
//! The 1M case is opt-in: building the tree takes minutes and a few GB of disk,
//! which is not something to do on every `cargo test`. Run it deliberately:
//!
//! ```sh
//! DISK_TRACKER_SCALE=1m cargo test --release --test scale_tests -- --nocapture
//! ```
//!
//! Numbers are reported on stdout even when a test passes, so a regression that
//! stays inside the budget is still visible.

use disk_tracker_engine::scanner::{scan_directory, ScanConfig};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::time::Instant;
use tempfile::TempDir;

// ---------------------------------------------------------------------------
// Budgets — 1_PROJECT_GUIDE.md §1.3
// ---------------------------------------------------------------------------

const TARGET_100K_SECS: f64 = 3.0;
const TARGET_1M_SECS: f64 = 15.0;
const TARGET_MEMORY_MB_PER_1M: f64 = 300.0;

/// Peak resident set size for this process, in bytes.
///
/// `ru_maxrss` is a high-water mark, so it survives the allocation being freed
/// before the test reads it — which is exactly what makes it usable here.
/// Darwin reports bytes; Linux reports kilobytes.
fn peak_rss_bytes() -> u64 {
    let mut usage: libc::rusage = unsafe { std::mem::zeroed() };
    // SAFETY: `usage` is a live, correctly sized rusage for the duration.
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut usage) } != 0 {
        return 0;
    }
    if cfg!(target_os = "macos") {
        usage.ru_maxrss as u64
    } else {
        usage.ru_maxrss as u64 * 1024
    }
}

fn mb(bytes: u64) -> f64 {
    bytes as f64 / (1024.0 * 1024.0)
}

/// Builds `file_count` files spread over a wide, shallow tree.
///
/// Shape matters as much as count: a wide tree exercises the `getattrlistbulk`
/// batching (many entries per directory), and the nesting exercises Rayon's
/// work stealing. A flat directory of a million files would measure neither.
fn build_tree(base: &Path, file_count: usize) -> std::io::Result<()> {
    // ~250 files per leaf, so each directory needs several bulk calls to drain.
    let leaves = (file_count / 250).max(1);
    // Two levels, so the work-stealing queue actually has branches to hand out.
    let branches = (leaves as f64).sqrt().ceil() as usize;

    let payload = b"disk-tracker scale test payload\n";
    let mut created = 0usize;

    'outer: for a in 0..branches {
        for b in 0..branches {
            let dir = base.join(format!("b{a:03}/l{b:03}"));
            fs::create_dir_all(&dir)?;
            for i in 0..250 {
                if created >= file_count {
                    break 'outer;
                }
                let mut f = fs::File::create(dir.join(format!("f{i:03}.dat")))?;
                f.write_all(payload)?;
                created += 1;
            }
        }
    }
    Ok(())
}

struct Measurement {
    elapsed_secs: f64,
    records: usize,
    rss_growth_bytes: u64,
}

fn measure(path: &Path) -> Measurement {
    let before = peak_rss_bytes();
    let start = Instant::now();
    let result = scan_directory(path, ScanConfig::default(), |_| {}).expect("scan failed");
    let elapsed = start.elapsed();
    let after = peak_rss_bytes();

    Measurement {
        elapsed_secs: elapsed.as_secs_f64(),
        records: result.records.len(),
        rss_growth_bytes: after.saturating_sub(before),
    }
}

fn report(label: &str, m: &Measurement, budget_secs: f64, budget_mb: f64) {
    println!(
        "\n{label}\n  {:>10} records\n  {:>10.2} s   (budget {:.1} s)\n  {:>10.1} MB  peak growth (budget {:.0} MB)\n  {:>10.0} files/sec",
        m.records,
        m.elapsed_secs,
        budget_secs,
        mb(m.rss_growth_bytes),
        budget_mb,
        m.records as f64 / m.elapsed_secs.max(0.000_001),
    );
}

#[test]
fn scan_100k_files_within_budget() {
    let dir = TempDir::new().unwrap();
    build_tree(dir.path(), 100_000).unwrap();

    let m = measure(dir.path());
    report("100K files", &m, TARGET_100K_SECS, TARGET_MEMORY_MB_PER_1M / 10.0);

    assert!(
        m.records >= 100_000,
        "expected at least 100k records, got {}",
        m.records
    );
    assert!(
        m.elapsed_secs < TARGET_100K_SECS,
        "100K files took {:.2}s, budget is {TARGET_100K_SECS}s",
        m.elapsed_secs
    );
    // A tenth of the 1M budget: the records are the bulk of the allocation and
    // they scale linearly, so the per-file budget is the meaningful one.
    let budget_mb = TARGET_MEMORY_MB_PER_1M / 10.0;
    assert!(
        mb(m.rss_growth_bytes) < budget_mb,
        "100K files used {:.1}MB, budget is {budget_mb:.0}MB",
        mb(m.rss_growth_bytes)
    );
}

/// The headline target. Opt-in — see the module comment.
#[test]
fn scan_1m_files_within_budget() {
    if std::env::var("DISK_TRACKER_SCALE").unwrap_or_default() != "1m" {
        eprintln!("skipping 1M scale test — set DISK_TRACKER_SCALE=1m to run it");
        return;
    }

    let dir = TempDir::new().unwrap();
    eprintln!("building 1M files, this takes a few minutes…");
    let build_start = Instant::now();
    build_tree(dir.path(), 1_000_000).unwrap();
    eprintln!("built in {:.0}s", build_start.elapsed().as_secs_f64());

    let m = measure(dir.path());
    report("1M files", &m, TARGET_1M_SECS, TARGET_MEMORY_MB_PER_1M);

    assert!(
        m.records >= 1_000_000,
        "expected at least 1M records, got {}",
        m.records
    );
    assert!(
        m.elapsed_secs < TARGET_1M_SECS,
        "1M files took {:.2}s, budget is {TARGET_1M_SECS}s",
        m.elapsed_secs
    );
    assert!(
        mb(m.rss_growth_bytes) < TARGET_MEMORY_MB_PER_1M,
        "1M files used {:.1}MB, budget is {TARGET_MEMORY_MB_PER_1M:.0}MB",
        mb(m.rss_growth_bytes)
    );
}

/// Cost per file must not climb with tree size. A super-linear scan passes at
/// 100K and blows the budget at 1M, which is the failure this catches early.
#[test]
fn cost_per_file_stays_flat() {
    let small = TempDir::new().unwrap();
    build_tree(small.path(), 20_000).unwrap();
    let a = measure(small.path());

    let large = TempDir::new().unwrap();
    build_tree(large.path(), 100_000).unwrap();
    let b = measure(large.path());

    let per_file_small = a.elapsed_secs / a.records as f64;
    let per_file_large = b.elapsed_secs / b.records as f64;
    println!(
        "\nper-file cost\n  20K:  {:.3} µs\n  100K: {:.3} µs",
        per_file_small * 1e6,
        per_file_large * 1e6
    );

    // Generous: this is a smoke test for quadratic behaviour, not a
    // microbenchmark, and a loaded CI machine adds noise.
    assert!(
        per_file_large < per_file_small * 3.0,
        "per-file cost grew {:.1}x from 20K to 100K files — scan is super-linear",
        per_file_large / per_file_small
    );
}
