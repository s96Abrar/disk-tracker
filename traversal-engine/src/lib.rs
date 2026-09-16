//! disk-tracker-engine
//!
//! macOS file-system traversal engine.
//!
//! The app runs the `disk-tracker-engine` binary as a subprocess and reads the
//! flat scan buffer from its stdout (see [`wire`]). There is deliberately no
//! C FFI: this crate used to export a full `scanner_create` /`scanner_start` /
//! `scanner_get_result` surface that nothing ever called, because the Swift
//! side had always used the subprocess. Two transports meant two things to keep
//! correct and one of them was never exercised.
//!
//! The subprocess is also the more defensive choice. A traversal engine walks
//! whatever a user points it at, and a crash on a malformed volume takes down a
//! child process rather than the app. Restoring an in-process FFI is only worth
//! it if profiling shows the pipe copy mattering — the buffer measures 62MB
//! for a million records, well inside the memory budget.

pub mod directory_walker;
pub mod file_record;
pub mod scanner;
pub mod wire;

// Re-export key types for consumers.
pub use file_record::{FileRecord, NodeType};
pub use scanner::ScanResult;
