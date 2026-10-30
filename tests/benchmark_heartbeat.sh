#!/bin/bash
set -e

echo "Benchmarking heartbeat-patrol.sh..."
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR"
mkdir -p "$TEST_DIR/.openclaw/workspace/heartbeats"
mkdir -p "$TEST_DIR/.hermes/heartbeats"

for i in hermes_daily_doctor hermes_upstream_watch hermes_weekly_review hermes_monthly_compress hermes_daily_study; do
    echo "$(date -Iseconds) interval=24h grace=6h job=$i" > "$TEST_DIR/.openclaw/workspace/heartbeats/$i.last"
    echo "$(date -Iseconds) interval=24h grace=6h job=$i" > "$TEST_DIR/.hermes/heartbeats/$i.last"
done

time for i in {1..20}; do
    ./lib/heartbeat-patrol.sh --self hermes_daily_doctor >/dev/null
done

rm -rf "$TEST_DIR"
