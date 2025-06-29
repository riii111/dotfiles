# Full Stack Code Quality Check

Perform comprehensive code quality checks for both backend (Rust) and frontend (Next.js) simultaneously.

Execute the following in parallel:

## Backend (if backend/ exists):
1. Navigate to backend/ and run:
   - cargo clippy -- -D warnings  
   - source .env && cargo nextest run --workspace
   - cargo audit

## Frontend (if frontend/ exists):
1. Navigate to frontend/ and run:
   - biome check .
   - yarn build

## Parallel Execution Strategy:
- Use background processes (&) or GNU parallel for simultaneous execution
- Capture output from each process
- Wait for all processes to complete
- Provide a consolidated report showing:
  - ✅ Passed checks
  - ❌ Failed checks with error details
  - ⏱️ Execution time for each check
  - 📊 Overall status summary

For maximum efficiency, start all checks simultaneously and collect results as they complete.
Example approach:
```bash
# Start all checks in parallel
(cd backend && cargo fmt --check) &
(cd backend && cargo clippy -- -D warnings) &
(cd backend && source ~/.env && cargo nextest run --workspace) &
(cd backend && cargo audit) &
(cd frontend && biome check .) &
(cd frontend && yarn build) &
(cd frontend && yarn test) &

# Wait for all background jobs
wait

# Collect and report results
```

# script
```bash
#!/bin/bash

# Enhanced Full Stack Quality Check Script
set -e  # immediately terminated by an error

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOG_DIR"

echo "🚀 Enhanced Full Stack Quality Check"
echo "===================================="
echo "📁 Project Root: $PROJECT_ROOT"
echo "📁 Logs Directory: $LOG_DIR"
echo "⏰ Start time: $(date)"
echo ""

# init log file 
> "$LOG_DIR/clippy.log"
> "$LOG_DIR/tests.log"
> "$LOG_DIR/audit.log"
> "$LOG_DIR/biome.log"
> "$LOG_DIR/build.log"

# launching parallel processes
echo "🚀 Starting parallel processes..."

(cd "$PROJECT_ROOT/backend" && echo "🔍 [$(date +%H:%M:%S)] Backend Clippy starting..." && cargo clippy -- -D warnings 2>&1 | tee "$LOG_DIR/clippy.log") &
clippy_pid=$!

(cd "$PROJECT_ROOT/backend" && echo "🧪 [$(date +%H:%M:%S)] Backend Tests starting..." && source .env 2>/dev/null || true && cargo nextest run --workspace 2>&1 | tee "$LOG_DIR/tests.log") &
tests_pid=$!

(cd "$PROJECT_ROOT/backend" && echo "🔒 [$(date +%H:%M:%S)] Backend Audit starting..." && cargo audit 2>&1 | tee "$LOG_DIR/audit.log") &
audit_pid=$!

(cd "$PROJECT_ROOT/frontend" && echo "🎨 [$(date +%H:%M:%S)] Frontend Biome starting..." && yarn biome check . 2>&1 | tee "$LOG_DIR/biome.log") &
biome_pid=$!

(cd "$PROJECT_ROOT/frontend" && echo "🏗️ [$(date +%H:%M:%S)] Frontend Build starting..." && yarn build 2>&1 | tee "$LOG_DIR/build.log") &
build_pid=$!

# process monitoring
echo "⏳ Waiting for all processes to complete..."
wait $clippy_pid $tests_pid $audit_pid $biome_pid $build_pid

echo ""
echo "📊 COMPREHENSIVE RESULTS ANALYSIS"
echo "=================================="
echo ""

analyze_result() {
    local name="$1"
    local log_file="$2"
    local error_pattern="$3"
    local success_pattern="$4"
    
    echo "📋 $name:"
    if [[ -f "$log_file" ]]; then
        if grep -q "$error_pattern" "$log_file"; then
            echo "  ❌ FAILED"
            echo "  📄 Errors found:"
            grep "$error_pattern" "$log_file" | head -3 | sed 's/^/    /'
        else
            echo "  ✅ PASSED"
            if [[ -n "$success_pattern" ]] && grep -q "$success_pattern" "$log_file"; then
                grep "$success_pattern" "$log_file" | tail -1 | sed 's/^/    /'
            fi
        fi
    else
        echo "  ❓ LOG FILE NOT FOUND"
    fi
    echo ""
}

# result by tasks 
analyze_result "🔍 CLIPPY" "$LOG_DIR/clippy.log" "error:" "warning:"
analyze_result "🧪 TESTS" "$LOG_DIR/tests.log" "FAILED\|test result: FAILED" "tests run.*passed"
analyze_result "🔒 AUDIT" "$LOG_DIR/audit.log" "error:\|vulnerabilities found" "Scanning.*dependencies"
analyze_result "🎨 BIOME" "$LOG_DIR/biome.log" "Found.*errors" "Checked.*files"
analyze_result "🏗️ BUILD" "$LOG_DIR/build.log" "Failed to compile\|Error:" "Compiled successfully"

# all aresult 
echo "🎯 OVERALL ASSESSMENT:"
echo "======================"

# count error
total_errors=0
for log in "$LOG_DIR"/*.log; do
    if [[ -f "$log" ]]; then
        case "$(basename "$log")" in
            "clippy.log") grep -q "error:" "$log" && ((total_errors++)) ;;
            "tests.log") grep -q "FAILED\|test result: FAILED" "$log" && ((total_errors++)) ;;
            "biome.log") grep -q "Found.*errors" "$log" && ((total_errors++)) ;;
            "build.log") grep -q "Failed to compile\|Error:" "$log" && ((total_errors++)) ;;
        esac
    fi
done

if [[ $total_errors -eq 0 ]]; then
    echo "🎉 ALL CHECKS PASSED! Ready for deployment."
else
    echo "⚠️  $total_errors check(s) failed. Review logs for details."
fi

echo ""
echo "⏰ End time: $(date)"
echo "📁 Full logs available in: $LOG_DIR"
```
