#!/bin/bash
set -euo pipefail

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR"
export ALERT_CONF="$HOME/.config/heartbeat-patrol.env"
export ALERT_LOG="$HOME/.openclaw/workspace/heartbeats/_alerts.log"

mkdir -p "$HOME/.config"
mkdir -p "$HOME/.openclaw/workspace/heartbeats/"
mkdir -p "$HOME/.hermes/heartbeats/"

# Mock heartbeats
NOW_ISO=$(date -Iseconds)
echo "$NOW_ISO interval=24h grace=6h job=hermes_upstream_watch" > "$HOME/.openclaw/workspace/heartbeats/hermes_upstream_watch.last"
echo "$NOW_ISO interval=168h grace=24h job=hermes_weekly_review" > "$HOME/.openclaw/workspace/heartbeats/hermes_weekly_review.last"
echo "$NOW_ISO interval=720h grace=72h job=hermes_monthly_compress" > "$HOME/.openclaw/workspace/heartbeats/hermes_monthly_compress.last"
echo "$NOW_ISO interval=24h grace=6h job=hermes_daily_study" > "$HOME/.hermes/heartbeats/hermes_daily_study.last"

echo "Benchmarking heartbeat-patrol.sh (100 iterations)"
time for i in {1..100}; do
    lib/heartbeat-patrol.sh --self hermes_daily_doctor >/dev/null
done
