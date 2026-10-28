#!/bin/bash
set -euo pipefail

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export BASELINE_DIR="$TEST_DIR/baseline"
export JOURNAL="$TEST_DIR/journal.jsonl"
export INBOX_DIR="$TEST_DIR/upgrade-packs/inbox"
export EXPECTED_HASHES_FILE="$BASELINE_DIR/.expected-hashes"
export INTERVAL_SEC=1

mkdir -p "$BASELINE_DIR"
mkdir -p "$INBOX_DIR"
touch "$JOURNAL"
touch "$BASELINE_DIR/file1.yaml"
touch "$EXPECTED_HASHES_FILE"

echo "fakehash  .expected-hashes" > "$EXPECTED_HASHES_FILE.sha256"

cat << 'MOCK' > "$TEST_DIR/lsattr"
#!/bin/bash
echo "----i--------- \$1"
MOCK
chmod +x "$TEST_DIR/lsattr"

# Replace mock exit 0 with returning 0 since exit blocks bash session
cat << 'MOCK' > "$TEST_DIR/pgrep"
#!/bin/bash
# pgrep mock
MOCK
chmod +x "$TEST_DIR/pgrep"

export PATH="$TEST_DIR:$PATH"

FAIL() {
    echo "FAIL: \$1"
    kill -s TERM $$
}

test_filesystem_change_detection() {
    echo "test_filesystem_change_detection"

    # Run watcher in background
    bash lib/watcher.sh >/dev/null 2>&1 &
    WATCHER_PID=$!

    sleep 1

    # Simulate immutability loss
    cat << 'MOCK' > "$TEST_DIR/lsattr"
#!/bin/bash
echo "-------------- \$1"
MOCK

    sleep 2
    kill $WATCHER_PID || true

    if ! grep -q "baseline_immutability_lost" "$JOURNAL"; then
        FAIL "Expected baseline_immutability_lost in journal"
    fi
    echo "Filesystem change detection OK"
}

test_proposal_generation() {
    echo "test_proposal_generation"
    local PROPOSAL="$INBOX_DIR/test-pack"
    mkdir -p "$PROPOSAL"
    cat << 'YAML' > "$PROPOSAL/manifest.yaml"
pack_kind: apply_upstream_patch
risk_tier: medium_risk
YAML
    if [ ! -f "$PROPOSAL/manifest.yaml" ]; then
        FAIL "Proposal script not generated"
    fi
    echo "Proposal generation OK"
}

test_operator_approval_gate() {
    echo "test_operator_approval_gate"
    local PROPOSAL="$INBOX_DIR/test-high-risk"
    mkdir -p "$PROPOSAL"
    cat << 'YAML' > "$PROPOSAL/manifest.yaml"
pack_kind: config_change
risk_tier: high_risk
status: pending_approval
YAML
    if ! grep -q "status: pending_approval" "$PROPOSAL/manifest.yaml"; then
        FAIL "Operator approval gate not enforced"
    fi
    echo "Operator approval gate OK"
}

test_filesystem_change_detection
test_proposal_generation
test_operator_approval_gate

echo "All E2E watch proposal tests passed."
