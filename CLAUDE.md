# Disk Tracker — Claude Code Guidance

**Reading Order (for AI agents):**
1. `documents/1_PROJECT_GUIDE.md` — Architecture, FFI contract, data models
2. `documents/2_BUILD_PLAN.md` — Feature requirements, MVP phases, implementation checklist
3. `documents/3_STANDARDS.md` — Coding standards, testing, git workflow
4. `documents/market_research.md` — Competitive analysis (external reference)

---

## Quick Start

**Architecture:** Hybrid Rust/Swift. Rust core (`traversal-engine/`) does fast file scanning via `getattrlistbulk(2)` + Rayon. SwiftUI (`DiskTracker/`) handles the GUI with Canvas-based visualizations.

**Key Components:**
| Component | Location | Purpose |
|-----------|----------|---------|
| Rust Scanner | `traversal-engine/src/` | File traversal, FFI |
| Swift App | `DiskTracker/Sources/` | GUI, file operations |
| Privileged Helper | `helper-tool/` | SMAppService + NSXPC |
| DuckDB Cache | Embedded in Rust | Historical scans |

**Performance Targets:**
- Scan 1M files: ≤15 seconds
- Memory: ≤300MB per 1M files
- UI: 60fps

**Global Constraints:**
- macOS Sequoia 15.0+
- Swift 6.0 (strict concurrency)
- Sandbox + NSXPC for privileged ops

---

## Common Commands

```bash
# Build both (default)
./build-disk-tracker

# Build specific target
./build-disk-tracker --rust    # Rust engine only
./build-disk-tracker --swift   # Swift app only

# Clean build artifacts
./build-disk-tracker --clean

# Run
open -a "Disk Tracker"
```

---

## Key Decisions

1. **`getattrlistbulk` over `stat()`** — Bulk kernel call minimizes transitions
2. **Physical size by default** — `ATTR_FIL_ALLOCSIZE` avoids APFS clone double-counting
3. **Rust for traversal** — ARC overhead avoided with compile-time ownership
4. **Immediate-mode Canvas** — Declarative hierarchy doesn't scale past ~1K elements
5. **SMAppService + NSXPC** — Apple-supported path for privileged operations

For complete technical details, FFI API, DuckDB schema, and implementation checklist, see the documents listed above.