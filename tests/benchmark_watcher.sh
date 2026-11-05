#!/bin/bash
set -euo pipefail

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export BASELINE_DIR="$TEST_DIR/baseline"
export JOURNAL="$TEST_DIR/journal.jsonl"
export EXPECTED_HASHES_FILE="$BASELINE_DIR/.expected-hashes"

mkdir -p "$BASELINE_DIR"
touch "$JOURNAL"

for i in {1..10}; do
    echo "test$i" > "$BASELINE_DIR/file$i.yaml"
    sha256sum "$BASELINE_DIR/file$i.yaml" | awk '{print $1 " file" '$i'".yaml"}' >> "$EXPECTED_HASHES_FILE"
done

# Source the watcher script (but don't run main)
sed -e '/^main$/d' lib/watcher.sh > "$TEST_DIR/watcher_source.sh"
source "$TEST_DIR/watcher_source.sh"

echo "Benchmarking check_immutability (100 iterations)"
time for i in {1..100}; do
    check_immutability >/dev/null || true
done

echo "Benchmarking check_hashes (100 iterations)"
time for i in {1..100}; do
    check_hashes >/dev/null || true
done
