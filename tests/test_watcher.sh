#!/bin/bash
set -euo pipefail

# Mocks and test setup
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export BASELINE_DIR="$TEST_DIR/baseline"
export JOURNAL="$TEST_DIR/journal.jsonl"
export EXPECTED_HASHES_FILE="$BASELINE_DIR/.expected-hashes"
export INTERVAL_SEC=1

mkdir -p "$BASELINE_DIR"
touch "$JOURNAL"

# Default Mocks
export LSATTR_MOCK_VAL="----i---------"
export PGREP_MOCK_VAL=0

cat << 'MOCK' > "$TEST_DIR/lsattr"
#!/bin/bash
echo "$LSATTR_MOCK_VAL $1"
MOCK
chmod +x "$TEST_DIR/lsattr"

cat << 'MOCK' > "$TEST_DIR/pgrep"
#!/bin/bash
sh -c "exit $PGREP_MOCK_VAL"
MOCK
chmod +x "$TEST_DIR/pgrep"

# For debouncing, mock sleep to do nothing so we can test the main loop without hanging forever
export SLEEP_CALL_COUNT=0
cat << 'MOCK' > "$TEST_DIR/sleep"
#!/bin/bash
# Mock sleep
MOCK
chmod +x "$TEST_DIR/sleep"


export PATH="$TEST_DIR:$PATH"

# Source the watcher script (but don't run main)
sed -e '/^main$/d' lib/watcher.sh > "$TEST_DIR/watcher_source.sh"
# Remove the infinite loop to test main if needed, but it's easier to just unit test the functions.
source "$TEST_DIR/watcher_source.sh"

FAIL() {
    echo "FAIL: $1"
    # Exit within script but not the interactive shell if sourced
    kill -s TERM $$
}

test_immutability_ok() {
    echo "test_immutability_ok"
    > "$JOURNAL"
    touch "$BASELINE_DIR/file1.yaml"
    export LSATTR_MOCK_VAL="----i---------"
    check_immutability
    if grep -q baseline_immutability_lost "$JOURNAL"; then
        FAIL "Expected no immutability loss"
    fi
}

test_immutability_lost() {
    echo "test_immutability_lost"
    > "$JOURNAL"
    export LSATTR_MOCK_VAL="--------------"
    check_immutability || true # should return 1
    if ! grep -q baseline_immutability_lost "$JOURNAL"; then
        FAIL "Expected immutability loss"
    fi
    export LSATTR_MOCK_VAL="----i---------"
}

test_hashes_missing() {
    echo "test_hashes_missing"
    > "$JOURNAL"
    rm -f "$EXPECTED_HASHES_FILE"
    check_hashes || true
    if ! grep -q baseline_hashes_file_missing "$JOURNAL"; then
        FAIL "Expected baseline_hashes_file_missing"
    fi
}

test_hashes_meta_mismatch() {
    echo "test_hashes_meta_mismatch"
    > "$JOURNAL"
    echo "fakehash  .expected-hashes" > "$EXPECTED_HASHES_FILE.sha256"
    touch "$EXPECTED_HASHES_FILE"
    check_hashes || true
    if ! grep -q baseline_meta_hash_mismatch "$JOURNAL"; then
        FAIL "Expected baseline_meta_hash_mismatch"
    fi
    rm -f "$EXPECTED_HASHES_FILE.sha256"
}

test_hashes_mismatch() {
    echo "test_hashes_mismatch"
    > "$JOURNAL"
    touch "$BASELINE_DIR/file1.yaml"
    # Valid meta-hash or no meta hash
    echo "badhash *file1.yaml" > "$EXPECTED_HASHES_FILE"
    check_hashes || true
    if ! grep -q baseline_hash_mismatch "$JOURNAL"; then
        FAIL "Expected baseline_hash_mismatch"
    fi
}

test_gateway_running() {
    echo "test_gateway_running"
    > "$JOURNAL"
    export PGREP_MOCK_VAL=0
    check_openclaw_gateway
    if grep -q openclaw_gateway_not_running "$JOURNAL"; then
        FAIL "Expected gateway running"
    fi
}

test_gateway_not_running() {
    echo "test_gateway_not_running"
    > "$JOURNAL"
    export PGREP_MOCK_VAL=1
    check_openclaw_gateway || true
    if ! grep -q openclaw_gateway_not_running "$JOURNAL"; then
        FAIL "Expected gateway not running"
    fi
    export PGREP_MOCK_VAL=0
}

test_debounce_logic() {
    echo "test_debounce_logic"
    > "$JOURNAL"
    # Emit heartbeat writes watcher_heartbeat
    emit_heartbeat
    if ! grep -q watcher_heartbeat "$JOURNAL"; then
        FAIL "Expected heartbeat in journal"
    fi
}

test_immutability_ok
test_immutability_lost
test_hashes_missing
test_hashes_meta_mismatch
test_hashes_mismatch
test_gateway_running
test_gateway_not_running
test_debounce_logic
echo "Tests pass."
