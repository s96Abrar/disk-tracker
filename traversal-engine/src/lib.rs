//! disk-tracker-engine
//!
//! High-performance macOS file-system traversal engine.
//! Exposes a C-compatible FFI for SwiftUI consumption.

pub mod cache;
pub mod directory_walker;
pub mod file_record;
pub mod scanner;

use scanner::{scan_directory, ScanConfig};
use std::ffi::{c_char, c_void, CStr};
use std::sync::atomic::{AtomicBool, Ordering};

// Re-export key types for consumers.
pub use file_record::{FileRecord, NodeType};
pub use scanner::ScanResult;

/// Opaque handle for Swift-side management.
pub struct ScannerHandle {
    pub cancelled: AtomicBool,
    pub state_ptr: *mut c_void,
}

unsafe impl Sync for ScannerHandle {}

/// Create a fresh scanner handle.
#[no_mangle]
pub unsafe extern "C" fn scanner_create() -> *mut ScannerHandle {
    let handle = Box::new(ScannerHandle {
        cancelled: AtomicBool::new(false),
        state_ptr: std::ptr::null_mut(),
    });
    Box::into_raw(handle)
}

/// Free a scanner handle.
#[no_mangle]
pub unsafe extern "C" fn scanner_free(handle: *mut ScannerHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Start a scan.  `on_progress` is called from an internal thread with 0.0–1.0.
#[no_mangle]
pub unsafe extern "C" fn scanner_start(
    handle: *mut ScannerHandle,
    path: *const c_char,
    config: ScanConfig,
    on_progress: Option<unsafe extern "C" fn(f64)>,
) {
    if handle.is_null() { return; }
    
    let path_str = CStr::from_ptr(path).to_string_lossy();
    let handle_ref = &mut *handle;
    
    let cb = move |p: f64| {
        if let Some(f) = on_progress {
            f(p);
        }
    };
    
    match scan_directory(std::path::Path::new(&*path_str), config, cb) {
        Ok(result) => {
            let boxed = Box::new(result);
            handle_ref.state_ptr = Box::into_raw(boxed) as *mut c_void;
        }
        Err(e) => {
            eprintln!("scan error: {:?}", e);
        }
    }
}

/// Cancel an in-progress scan.
#[no_mangle]
pub extern "C" fn scanner_cancel(handle: *mut ScannerHandle) {
    if !handle.is_null() {
        unsafe { &*handle }.cancelled.store(true, Ordering::Relaxed);
    }
}

/// Returns true if a scan is currently running.
#[no_mangle]
pub extern "C" fn scanner_is_running(handle: *mut ScannerHandle) -> bool {
    if handle.is_null() { return false; }
    unsafe { (*handle).state_ptr.is_null() == false }
}

/// C-compatible scan result descriptor.
#[repr(C)]
#[derive(Debug)]
pub struct CScanResult {
    pub buffer: *mut u8,
    pub buffer_len: u64,
    pub record_count: u64,
    pub string_table_offset: u64,
}

/// Retrieve the latest scan result.  Caller must call `scanner_free_result`.
#[no_mangle]
pub unsafe extern "C" fn scanner_get_result(
    handle: *mut ScannerHandle,
) -> CScanResult {
    if handle.is_null() { return CScanResult { buffer: std::ptr::null_mut(), buffer_len: 0, record_count: 0, string_table_offset: 0 }; }
    
    let state_ptr = (*handle).state_ptr;
    if state_ptr.is_null() { return CScanResult { buffer: std::ptr::null_mut(), buffer_len: 0, record_count: 0, string_table_offset: 0 }; }
    
    let result = &*(state_ptr as *const ScanResult);
    let records = &result.records;
    let strings = &result.string_table;
    
    let record_count = records.len() as u64;
    let record_bytes = std::mem::size_of_val(records);
    let string_offset = record_bytes as u64;
    
    // Build combined buffer: [FileRecords as bytes][Strings]
    let mut combined = Vec::with_capacity(record_bytes + strings.len());
    // SAFETY: FileRecord is repr(C) so byte layout is stable
    let record_bytes_slice: &[u8] = unsafe {
        std::slice::from_raw_parts(
            records.as_ptr() as *const u8,
            record_bytes
        )
    };
    combined.extend_from_slice(record_bytes_slice);
    combined.extend_from_slice(strings);
    
    let ptr = combined.as_ptr();
    let len = combined.len() as u64;
    
    std::mem::forget(combined);
    
    CScanResult {
        buffer: ptr as *mut u8,
        buffer_len: len,
        record_count,
        string_table_offset: string_offset,
    }
}

/// Free a CScanResult returned by `scanner_get_result`.
#[no_mangle]
pub unsafe extern "C" fn scanner_free_result(result: *mut CScanResult) {
    if result.is_null() { return; }
    let r = &mut *result;
    if !r.buffer.is_null() && r.buffer_len > 0 {
        drop(Vec::from_raw_parts(r.buffer, r.buffer_len as usize, r.buffer_len as usize));
    }
    r.buffer = std::ptr::null_mut();
    r.buffer_len = 0;
    r.record_count = 0;
    r.string_table_offset = 0;
}


