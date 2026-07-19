#!/bin/bash
#
# coverage-report.sh - Generate test coverage reports for disk-tracker
#
# Shows:
#   1. Rust (traversal-engine) coverage using cargo-llvm-cov
#   2. Swift/Xcode (DiskTracker) coverage from XCResult test artifacts
#
# Uses cargo-llvm-cov for coverage analysis
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
TRAVERSAL_ENGINE_DIR="$PROJECT_ROOT/traversal-engine"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color
DIM='[2m'

# Default values
FORMAT="text"
SHOW_DETAILS=false
OPEN_REPORT=false
RUN_RUST=false
RUN_XCODE=false

usage() {
    cat <<EOF
${BOLD}USAGE:${NC} $0 [OPTIONS]

Generate test coverage reports for the disk-tracker project.

${BOLD}OPTIONS:${NC}
    -x, --xcode               Show Xcode (Swift) coverage from latest test run
    -a, --all                 Show both Rust and Xcode coverage
    -f, --format FORMAT       Output format: text (default), html, lcov
    -d, --details             Show detailed per-file coverage
    -o, --open                Open HTML report in browser (implies --format html)
    -h, --help                Show this help message

${BOLD}EXAMPLES:${NC}
    $0                        # Rust coverage summary
    $0 --xcode                # Xcode/Swift coverage summary
    $0 --all                  # Both Rust and Xcode coverage
    $0 --xcode --details      # Xcode coverage with per-file breakdown
    $0 --all --details        # Full coverage report with per-file details
    $0 --format html --open   # Generate and open HTML report (Rust only)

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -x|--xcode)
            RUN_XCODE=true
            shift
            ;;
        -a|--all)
            RUN_RUST=true
            RUN_XCODE=true
            shift
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -d|--details)
            SHOW_DETAILS=true
            shift
            ;;
        -o|--open)
            OPEN_REPORT=true
            FORMAT="html"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# === Utility Functions ===

# Colorize a coverage percentage: <30% red, <70% yellow, >=70% green
colorize_pct() {
    local pct="$1"
    # Strip any trailing non-numeric characters
    pct="${pct%%%}"
    pct="${pct% }"
    if (( $(echo "$pct < 30" | bc -l 2>/dev/null || echo 1) )); then
        echo -e "${RED}${pct}%${NC}"
    elif (( $(echo "$pct < 70" | bc -l 2>/dev/null || echo 1) )); then
        echo -e "${YELLOW}${pct}%${NC}"
    else
        echo -e "${GREEN}${pct}%${NC}"
    fi
}

# Print a section header
section_header() {
    local title="$1"
    local color="$2"
    local width=60
    local title_len=${#title}
    local pad=$(( (width - title_len - 2) / 2 ))
    echo ""
    echo -e "${color}${BOLD}$(printf '%*s' "$width" '' | tr ' ' '=')${NC}"
    echo -e "${color}${BOLD}$(printf "%*s%s%*s" $pad '' "$title" $((width - pad - title_len)) '')${NC}"
    echo -e "${color}${BOLD}$(printf '%*s' "$width" '' | tr ' ' '=')${NC}"
    echo ""
}

# === Rust Coverage (function) ===

run_rust_coverage() {
    # Verify we're in the right directory
    if [[ ! -d "$TRAVERSAL_ENGINE_DIR" ]]; then
        echo -e "${RED}Error: traversal-engine not found at $TRAVERSAL_ENGINE_DIR${NC}"
        return 1
    fi

    # Change to traversal-engine for coverage
    cd "$TRAVERSAL_ENGINE_DIR"

    case $FORMAT in
        text)
            if [[ "$SHOW_DETAILS" == true ]]; then
                echo -e "${BOLD}Per-File Coverage:${NC}"
                echo -e "${CYAN}----------------------------------------${NC}"
            fi

            # Run tests with coverage and show report
            cargo llvm-cov 2>/dev/null || {
                echo -e "${RED}Error: Failed to generate coverage report${NC}"
                echo -e "${YELLOW}Make sure cargo-llvm-cov is installed: cargo install cargo-llvm-cov${NC}"
                return 1
            }

            if [[ "$SHOW_DETAILS" == true ]]; then
                echo ""
                echo -e "${CYAN}----------------------------------------${NC}"
            fi
            ;;

        html)
            local report_dir="$PROJECT_ROOT/coverage-report"
            mkdir -p "$report_dir"

            echo -e "${BOLD}Generating HTML coverage report...${NC}"
            cargo llvm-cov html --output-dir "$report_dir" 2>/dev/null || {
                echo -e "${RED}Error: Failed to generate HTML coverage report${NC}"
                return 1
            }

            echo -e "${GREEN}HTML report generated at: ${BOLD}$report_dir/index.html${NC}"

            if [[ "$OPEN_REPORT" == true ]]; then
                echo -e "${BOLD}Opening report in browser...${NC}"
                open "$report_dir/index.html" 2>/dev/null || \
                    echo -e "${YELLOW}Could not open browser automatically${NC}"
            fi
            ;;

        lcov)
            local output_file="${1:-coverage.info}"
            echo -e "${BOLD}Generating LCOV coverage data...${NC}"
            cargo llvm-cov --lcov --output-path "$output_file" 2>/dev/null || {
                echo -e "${RED}Error: Failed to generate LCOV coverage report${NC}"
                return 1
            }
            echo -e "${GREEN}LCOV report generated at: ${BOLD}$output_file${NC}"
            ;;

        *)
            echo -e "${RED}Unknown format: $FORMAT${NC}"
            usage
            return 1
            ;;
    esac
}

# === Xcode Coverage ===

run_xcode_coverage() {
    # Find the DerivedData directory for the DiskTracker project
    local derived_data
    derived_data=$(find /Users/abrar/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "DiskTracker-*" -type d 2>/dev/null | head -1)

    if [[ -z "$derived_data" ]]; then
        echo -e "${YELLOW}⚠  No DiskTracker DerivedData found. Have you run tests in Xcode?${NC}"
        return 1
    fi

    # Find the latest XCResult test artifact
    local test_logs="$derived_data/Logs/Test"
    if [[ ! -d "$test_logs" ]]; then
        echo -e "${YELLOW}⚠  No test logs found in DerivedData. Have you run tests in Xcode?${NC}"
        return 1
    fi

    local latest_xcresult
    latest_xcresult=$(ls -t "$test_logs/"Test-DiskTracker-*.xcresult 2>/dev/null | head -1)
    # Strip trailing colon that ls -t sometimes adds
    latest_xcresult="${latest_xcresult%:}"

    if [[ -z "$latest_xcresult" || ! -d "$latest_xcresult" ]]; then
        echo -e "${YELLOW}⚠  No XCResult artifacts found. Have you run tests in Xcode?${NC}"
        return 1
    fi

    echo -e "${DIM}Using: $(basename "$latest_xcresult")${NC}"
    echo ""

    # Extract the overall summary line (line 3 of report output: "DiskTracker.app   XX.XX% (N/N)")
    local report_output
    report_output=$(xcrun xccov view --report "$latest_xcresult" 2>&1)

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Error: Failed to read XCResult. Is Xcode Command Line Tools installed?${NC}"
        return 1
    fi

    local app_line
    app_line=$(echo "$report_output" | sed -n '3p')
    local overall_pct
    overall_pct=$(echo "$app_line" | awk '{print $2}')
    local overall_counts
    overall_counts=$(echo "$app_line" | awk '{print $3}')

    # Display overall coverage
    echo -e "${BOLD}Overall Coverage:${NC} $(colorize_pct "$overall_pct") ${DIM}$overall_counts${NC}"
    echo ""

    # Extract and display per-file coverage
    if [[ "$SHOW_DETAILS" == true ]]; then
        echo -e "${BOLD}Per-File Coverage:${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────────────────────────────${NC}"

        # Extract file-level lines (indented by 4 spaces, containing .swift)
        # Format: "    /path/to/File.swift                          XX.XX% (N/N)"
        while IFS= read -r line; do
            local file_path
            file_path=$(echo "$line" | awk '{print $1}')

            local pct coverage_info
            pct=$(echo "$line" | awk '{print $2}')
            coverage_info=$(echo "$line" | awk '{print $3}')

            # Display the file path relative to project root
            local rel_path="${file_path#$PROJECT_ROOT/}"
            if [[ "$rel_path" == "$file_path" ]]; then
                rel_path="$file_path"
            fi

            # Colorize and format
            printf "  %-65s %s %s\n" "$rel_path" "$(colorize_pct "$pct")" "${DIM}$coverage_info${NC}"
        done < <(echo "$report_output" | grep -E '^    /.*\.swift' | grep -v '/\.build/')
    fi

    # Summary statistics
    echo ""
    echo -e "${BOLD}${DIM}── Coverage Summary ──${NC}"
    echo ""

    # Count files by coverage bucket
    local high=0 mid=0 low=0 zero=0 total_files=0
    while IFS= read -r line; do
        local pct_str
        pct_str=$(echo "$line" | awk '{print $2}')
        local pct_val="${pct_str%%%}"
        total_files=$((total_files + 1))
        if (( $(echo "$pct_val == 0" | bc -l 2>/dev/null) )); then
            zero=$((zero + 1))
        elif (( $(echo "$pct_val >= 70" | bc -l 2>/dev/null) )); then
            high=$((high + 1))
        elif (( $(echo "$pct_val >= 30" | bc -l 2>/dev/null) )); then
            mid=$((mid + 1))
        else
            low=$((low + 1))
        fi
    done < <(echo "$report_output" | grep -E '^    /.*\.swift' | grep -v '/\.build/')

    echo -e "  ${GREEN}≥ 70%:${NC}  $high files  ${YELLOW}30-69%:${NC}  $mid files  ${RED}< 30%:${NC}  $low files  ${RED}0%:${NC}   $zero files"
    echo -e "  ${DIM}Total source files: $total_files${NC}"
    echo ""
}

# Default: run Rust coverage only if no specific flags given
if [[ "$RUN_XCODE" == false ]]; then
    RUN_RUST=true
fi

# ──────────────────────────────────────
# Rust Coverage Section
# ──────────────────────────────────────
if [[ "$RUN_RUST" == true ]]; then
    section_header "Rust Engine Coverage (traversal-engine)" "$BLUE"
    run_rust_coverage
fi

# ──────────────────────────────────────
# Xcode Coverage Section
# ──────────────────────────────────────
if [[ "$RUN_XCODE" == true ]]; then
    section_header "Swift/Xcode Coverage (DiskTracker)" "$MAGENTA"
    run_xcode_coverage
fi

echo ""
echo -e "${BOLD}${GREEN}✓ Coverage report complete${NC}"