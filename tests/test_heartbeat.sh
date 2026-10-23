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

# Mock curl
export CURL_CALLED=0
cat << 'MOCK' > "$TEST_DIR/curl"
#!/bin/bash
echo "$@" >> "$HOME/curl_calls.log"
MOCK
chmod +x "$TEST_DIR/curl"

export PATH="$TEST_DIR:$PATH"

FAIL() {
    echo "FAIL: $1"
    kill -s TERM $$
}

# Test missing args
if lib/heartbeat-patrol.sh 2>/dev/null; then
    FAIL "expected failure on no args"
fi

# Test unknown job
if lib/heartbeat-patrol.sh --self unknown_job 2>/dev/null; then
    FAIL "expected failure on unknown job"
fi

run_patrol_ok() {
    echo "run_patrol_ok"
    rm -f "$ALERT_LOG"
    rm -f "$HOME/curl_calls.log"

    # Write a fresh heartbeat for peer
    NOW_ISO=$(date -Iseconds)
    echo "$NOW_ISO interval=24h grace=6h job=hermes_upstream_watch" > "$HOME/.openclaw/workspace/heartbeats/hermes_upstream_watch.last"

    # Run for self
    lib/heartbeat-patrol.sh --self hermes_daily_doctor >/dev/null

    if [ -f "$ALERT_LOG" ]; then
        if grep -q "hermes_upstream_watch" "$ALERT_LOG"; then
            FAIL "Expected hermes_upstream_watch to be OK, but it alerted."
        fi
    fi
}

run_patrol_stale() {
    echo "run_patrol_stale"
    rm -f "$ALERT_LOG"
    rm -f "$HOME/curl_calls.log"

    # Setup alert env
    echo "TELEGRAM_BOT_TOKEN=fake_token" > "$ALERT_CONF"
    echo "TELEGRAM_CHAT_ID=fake_chat" >> "$ALERT_CONF"

    # Write a stale heartbeat for peer (e.g. 40 hours ago for interval 24 + grace 6 = 30)
    STALE_EPOCH=$(($(date +%s) - 40*3600))
    if date --version >/dev/null 2>&1; then
        STALE_ISO=$(date -Iseconds -d "@$STALE_EPOCH")
    else
        STALE_ISO=$(date -Iseconds -r "$STALE_EPOCH")
    fi

    echo "$STALE_ISO interval=24h grace=6h job=hermes_upstream_watch" > "$HOME/.openclaw/workspace/heartbeats/hermes_upstream_watch.last"

    # Run for self
    lib/heartbeat-patrol.sh --self hermes_daily_doctor >/dev/null

    if ! grep -q "STALE: hermes_upstream_watch" "$ALERT_LOG"; then
        FAIL "expected hermes_upstream_watch to be stale"
    fi

    if ! grep -q "fake_token" "$HOME/curl_calls.log"; then
        FAIL "expected curl to be called with bot token"
    fi
}

run_patrol_missing() {
    echo "run_patrol_missing"
    rm -f "$ALERT_LOG"
    rm -f "$HOME/curl_calls.log"
    rm -f "$HOME/.openclaw/workspace/heartbeats/hermes_upstream_watch.last"

    lib/heartbeat-patrol.sh --self hermes_daily_doctor >/dev/null

    if ! grep -q "STALE: hermes_upstream_watch (no heartbeat ever)" "$ALERT_LOG"; then
        FAIL "expected hermes_upstream_watch to be missing"
    fi
}

run_patrol_ok
run_patrol_stale
run_patrol_missing

echo "Tests pass."
