#!/bin/bash
set -euo pipefail

# test_watcher_e2e.sh
# End-to-end tests for inotify/fs event debouncing, trigger pipeline execution, and error handling.
# The product code is pending implementation.

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

WATCH_DIR="$TEST_DIR/watch"
mkdir -p "$WATCH_DIR"

PIPELINE_LOG="$TEST_DIR/pipeline.log"
PIPELINE_SCRIPT="$TEST_DIR/pipeline.sh"
cat << 'MOCK' > "$PIPELINE_SCRIPT"
#!/bin/bash
echo "pipeline triggered" >> "$PIPELINE_LOG"
MOCK
chmod +x "$PIPELINE_SCRIPT"

WATCHER_LOG="$TEST_DIR/watcher.log"
ERROR_LOG="$TEST_DIR/error.log"

WATCHER_BIN="${WATCHER_BIN:-./lib/inotify-watcher.sh}"

FAIL() {
    echo "FAIL: $1"
    kill -s TERM $$
}

test_debouncing() {
    echo "Running test_debouncing..."
    if [ ! -x "$WATCHER_BIN" ]; then
        echo "SKIP: Watcher binary not found. Product code pending."
        return 0
    fi
    > "$PIPELINE_LOG"
    "$WATCHER_BIN" --watch-dir "$WATCH_DIR" --pipeline "$PIPELINE_SCRIPT" > "$WATCHER_LOG" 2> "$ERROR_LOG" &
    WATCHER_PID=$!
    sleep 1

    # Trigger multiple rapid events
    touch "$WATCH_DIR/file1.txt"
    touch "$WATCH_DIR/file2.txt"
    echo "data" > "$WATCH_DIR/file1.txt"
    rm "$WATCH_DIR/file2.txt"

    sleep 3
    kill "$WATCHER_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true

    run_count=$(wc -l < "$PIPELINE_LOG")
    if [ "$run_count" -ne 1 ]; then
        FAIL "Expected pipeline to run 1 time, but ran $run_count times."
    fi
    echo "test_debouncing passed."
}

test_trigger_pipeline() {
    echo "Running test_trigger_pipeline..."
    if [ ! -x "$WATCHER_BIN" ]; then
        echo "SKIP: Watcher binary not found. Product code pending."
        return 0
    fi
    > "$PIPELINE_LOG"
    "$WATCHER_BIN" --watch-dir "$WATCH_DIR" --pipeline "$PIPELINE_SCRIPT" > "$WATCHER_LOG" 2> "$ERROR_LOG" &
    WATCHER_PID=$!
    sleep 1

    # Trigger a single event
    touch "$WATCH_DIR/trigger.txt"

    sleep 3
    kill "$WATCHER_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true

    if ! grep -q "pipeline triggered" "$PIPELINE_LOG"; then
        FAIL "Pipeline was not executed on fs event."
    fi
    echo "test_trigger_pipeline passed."
}

test_error_handling() {
    echo "Running test_error_handling..."
    if [ ! -x "$WATCHER_BIN" ]; then
        echo "SKIP: Watcher binary not found. Product code pending."
        return 0
    fi
    > "$PIPELINE_LOG"
    > "$ERROR_LOG"

    cat << 'MOCK' > "$PIPELINE_SCRIPT"
#!/bin/bash
echo "pipeline failing" >> "$PIPELINE_LOG"
# Simulate failure
kill -s TERM $$
MOCK

    "$WATCHER_BIN" --watch-dir "$WATCH_DIR" --pipeline "$PIPELINE_SCRIPT" > "$WATCHER_LOG" 2> "$ERROR_LOG" &
    WATCHER_PID=$!
    sleep 1

    touch "$WATCH_DIR/error_trigger.txt"
    sleep 3

    if ! kill -0 "$WATCHER_PID" 2>/dev/null; then
        FAIL "Watcher crashed on pipeline error."
    fi

    kill "$WATCHER_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true

    if [ ! -s "$ERROR_LOG" ] && ! grep -qi "error" "$WATCHER_LOG"; then
        FAIL "Watcher did not log an error for pipeline failure."
    fi

    echo "test_error_handling passed."
}

test_debouncing
test_trigger_pipeline
test_error_handling

echo "All tests passed."
