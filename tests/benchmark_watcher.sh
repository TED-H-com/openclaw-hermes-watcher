#!/bin/bash
set -e

echo "Benchmarking watcher.sh..."
export BASELINE_DIR=$(mktemp -d)
export JOURNAL="$BASELINE_DIR/journal.jsonl"
export INTERVAL_SEC=1
for i in {1..50}; do
    touch "$BASELINE_DIR/file$i.yaml"
done
touch "$BASELINE_DIR/.expected-hashes"
touch "$BASELINE_DIR/.expected-hashes.sha256"
# fake hash
echo "hash .expected-hashes" > "$BASELINE_DIR/.expected-hashes.sha256"

cp lib/watcher.sh "$BASELINE_DIR/watcher_lib.sh"
sed -i 's/^main[[:space:]]*$/#main/' "$BASELINE_DIR/watcher_lib.sh"
source "$BASELINE_DIR/watcher_lib.sh"

echo "Timing check_immutability..."
time for i in {1..50}; do
    check_immutability >/dev/null
done

echo "Timing emit_event..."
time for i in {1..50}; do
    emit_event "test" "details" >/dev/null
done

rm -rf "$BASELINE_DIR"
