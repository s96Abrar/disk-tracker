use criterion::{Criterion, criterion_group, criterion_main};
use disk_tracker_engine::scanner::{scan_directory, ScanConfig};
use std::fs;
use std::path::Path;
use tempfile::TempDir;

/// Create a test directory with `file_count` files distributed across `dir_depth` levels
fn create_test_files(base: &Path, file_count: usize, dir_depth: usize) -> std::io::Result<()> {
    let files_per_dir = (file_count / dir_depth).max(1);
    let mut created = 0;

    for depth in 0..dir_depth {
        let dir_name = format!("level_{}", depth);
        let dir_path = base.join(&dir_name);
        fs::create_dir_all(&dir_path)?;

        let files_in_this_dir = if depth == dir_depth - 1 {
            // Last level gets any remainder
            file_count - created
        } else {
            files_per_dir
        };

        for i in 0..files_in_this_dir {
            let file_path = dir_path.join(format!("file_{}.txt", i));
            fs::write(&file_path, format!("test content {}", created * 1000 + i))?;
            created += 1;
            if created >= file_count {
                break;
            }
        }
        if created >= file_count {
            break;
        }
    }
    Ok(())
}

/// Benchmark scanning a small directory (100 files)
fn bench_scan_small(c: &mut Criterion) {
    let temp_dir = TempDir::new().unwrap();
    create_test_files(temp_dir.path(), 100, 5).unwrap();

    c.bench_function("scan_100_files", |b| {
        b.iter(|| {
            let config = ScanConfig::default();
            let _result = scan_directory(temp_dir.path(), config, |_| {});
        });
    });
}

/// Benchmark scanning a medium directory (1000 files)
fn bench_scan_medium(c: &mut Criterion) {
    let temp_dir = TempDir::new().unwrap();
    create_test_files(temp_dir.path(), 1000, 10).unwrap();

    c.bench_function("scan_1000_files", |b| {
        b.iter(|| {
            let config = ScanConfig::default();
            let _result = scan_directory(temp_dir.path(), config, |_| {});
        });
    });
}

/// Benchmark scanning 10K files
fn bench_scan_large(c: &mut Criterion) {
    let temp_dir = TempDir::new().unwrap();
    create_test_files(temp_dir.path(), 10_000, 20).unwrap();

    c.bench_function("scan_10000_files", |b| {
        b.iter(|| {
            let config = ScanConfig::default();
            let _result = scan_directory(temp_dir.path(), config, |_| {});
        });
    });
}

/// Verify performance targets are met
#[test]
fn test_performance_1000_files() {
    let temp_dir = TempDir::new().unwrap();
    create_test_files(temp_dir.path(), 1000, 10).unwrap();

    let config = ScanConfig::default();
    let start = std::time::Instant::now();
    let result = scan_directory(temp_dir.path(), config, |_| {}).unwrap();
    let elapsed = start.elapsed();

    // 1000 files should scan in under 1 second
    assert!(
        elapsed.as_secs() < 1,
        "1000 files should scan in <1s, took {:?}",
        elapsed
    );

    // Verify we got results
    assert!(!result.records.is_empty(), "Should have scan results");
    assert!(
        result.records.len() >= 1000,
        "Should have scanned at least 1000 entries"
    );
}

#[test]
fn test_performance_10000_files() {
    let temp_dir = TempDir::new().unwrap();
    create_test_files(temp_dir.path(), 10_000, 20).unwrap();

    let config = ScanConfig::default();
    let start = std::time::Instant::now();
    let result = scan_directory(temp_dir.path(), config, |_| {}).unwrap();
    let elapsed = start.elapsed();

    // 10K files target: <3 seconds (scales from 15s for 1M)
    assert!(
        elapsed.as_secs() < 3,
        "10000 files should scan in <3s, took {:?}",
        elapsed
    );

    // Verify we got results
    assert!(!result.records.is_empty(), "Should have scan results");
    assert!(
        result.records.len() >= 10_000,
        "Should have scanned at least 10000 entries"
    );
}

criterion_group!(
    benches,
    bench_scan_small,
    bench_scan_medium,
    bench_scan_large
);
criterion_main!(benches);
