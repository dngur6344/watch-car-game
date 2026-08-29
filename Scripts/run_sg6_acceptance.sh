#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 <presentation|fps|memory> <iOS simulator name> <OS version> [timeout seconds]" >&2
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
    usage
    exit 64
fi

MODE="$1"
DEVICE_NAME="$2"
OS_VERSION="$3"

case "$MODE" in
    presentation)
        SUMMARY_PREFIX="SG6_PRESENTATION_SUMMARY"
        DEFAULT_TIMEOUT=60
        START_DELAY=0
        ;;
    fps)
        SUMMARY_PREFIX="SG6_FPS_SUMMARY"
        DEFAULT_TIMEOUT=540
        START_DELAY=1
        ;;
    memory)
        SUMMARY_PREFIX="SG6_MEMORY_SUMMARY"
        DEFAULT_TIMEOUT=900
        START_DELAY=8
        ;;
    *)
        usage
        exit 64
        ;;
esac

TIMEOUT_SECONDS="${4:-$DEFAULT_TIMEOUT}"
if [[ ! "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Timeout must be a positive integer number of seconds." >&2
    exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/WatchCarRacer.xcodeproj"
BUNDLE_ID="com.woohyuk.WatchCarRacer"
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
DEVICE_SLUG="$(printf '%s' "$DEVICE_NAME" | tr -cs '[:alnum:].-' '_')"
EVIDENCE_ROOT="${SG6_EVIDENCE_ROOT:-$PROJECT_ROOT/.woohyuk/sg6-acceptance}"
EVIDENCE_DIR="$EVIDENCE_ROOT/${TIMESTAMP}-${MODE}-${DEVICE_SLUG}-iOS${OS_VERSION}"
DERIVED_DATA="${SG6_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/watch-car-racer-sg6-derived-data}"
UNIFIED_LOG="$EVIDENCE_DIR/unified.log"
TRACE_PID=""
LOG_STREAM_PID=""

mkdir -p "$EVIDENCE_DIR"
mkdir -p "$DERIVED_DATA"

stop_trace_process() {
    if [[ -z "$TRACE_PID" ]] || ! kill -0 "$TRACE_PID" 2>/dev/null; then
        TRACE_PID=""
        return
    fi

    kill -TERM "$TRACE_PID" 2>/dev/null || true
    for (( trace_stop_wait = 0; trace_stop_wait < 5; trace_stop_wait += 1 )); do
        if ! kill -0 "$TRACE_PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if kill -0 "$TRACE_PID" 2>/dev/null; then
        kill -KILL "$TRACE_PID" 2>/dev/null || true
    fi
    wait "$TRACE_PID" 2>/dev/null || true
    TRACE_PID=""
}

cleanup() {
    if [[ -n "$LOG_STREAM_PID" ]] && kill -0 "$LOG_STREAM_PID" 2>/dev/null; then
        kill -INT "$LOG_STREAM_PID" 2>/dev/null || true
        wait "$LOG_STREAM_PID" 2>/dev/null || true
    fi
    if [[ -n "$TRACE_PID" ]] && kill -0 "$TRACE_PID" 2>/dev/null; then
        stop_trace_process
    fi
    if [[ -n "${SIMULATOR_UDID:-}" ]]; then
        xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

RUNTIME_HEADER="-- iOS ${OS_VERSION} --"
SIMULATOR_UDID="$({
    xcrun simctl list devices available | awk \
        -v runtime="$RUNTIME_HEADER" \
        -v device="$DEVICE_NAME" '
            $0 == runtime { inside = 1; next }
            /^-- / { inside = 0 }
            inside && candidate == "" && index($0, "    " device " (") == 1 {
                prefix = "    " device " ("
                candidate = substr($0, length(prefix) + 1)
                sub(/\).*/, "", candidate)
            }
            END { print candidate }
        '
} || true)"

if [[ -z "$SIMULATOR_UDID" ]]; then
    echo "No available simulator named '$DEVICE_NAME' with iOS $OS_VERSION." >&2
    exit 69
fi
SIMULATOR_LOG_DIRECTORY="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_UDID/data/var/db/diagnostics"

{
    echo "mode=$MODE"
    echo "device=$DEVICE_NAME"
    echo "os=$OS_VERSION"
    echo "udid=$SIMULATOR_UDID"
    echo "timeoutSeconds=$TIMEOUT_SECONDS"
    echo "derivedData=$DERIVED_DATA"
    echo "simulatorLogDirectory=$SIMULATOR_LOG_DIRECTORY"
    echo "startedUTC=$TIMESTAMP"
} > "$EVIDENCE_DIR/run-metadata.txt"

set -o pipefail
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme WatchCarRacer \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$OS_VERSION" \
    -derivedDataPath "$DERIVED_DATA" \
    build 2>&1 | tee "$EVIDENCE_DIR/build.log"

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/WatchCarRacer.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Debug app bundle was not produced at $APP_PATH." >&2
    exit 70
fi

xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
if ! xcrun simctl bootstatus "$SIMULATOR_UDID" -b; then
    echo "Unable to boot simulator $SIMULATOR_UDID." >&2
    exit 70
fi
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

LOG_START="$(date -u '+%Y-%m-%d %H:%M:%S%z')"
/usr/bin/log stream \
    --style compact \
    --level info \
    --predicate "subsystem == '$BUNDLE_ID' AND category == 'SG6Acceptance'" \
    > "$UNIFIED_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 1
if ! kill -0 "$LOG_STREAM_PID" 2>/dev/null; then
    wait "$LOG_STREAM_PID" 2>/dev/null || true
    echo "Host unified-log stream failed to start." >&2
    exit 70
fi

LAUNCH_OUTPUT="$(xcrun simctl launch \
    --terminate-running-process \
    "$SIMULATOR_UDID" \
    "$BUNDLE_ID" \
    "--sg6-$MODE" \
    --sg6-start-delay \
    "$START_DELAY")"
printf '%s\n' "$LAUNCH_OUTPUT" | tee "$EVIDENCE_DIR/launch.log"
APP_PID="${LAUNCH_OUTPUT##*: }"
if [[ ! "$APP_PID" =~ ^[0-9]+$ ]]; then
    echo "Unable to parse launched app PID from: $LAUNCH_OUTPUT" >&2
    exit 70
fi

if [[ "$MODE" == "memory" ]]; then
    sleep 2
    xcrun xctrace record \
        --quiet \
        --template "Game Memory" \
        --attach "$APP_PID" \
        --output "$EVIDENCE_DIR/memory-game-memory.trace" \
        --no-prompt \
        > "$EVIDENCE_DIR/xctrace.log" 2>&1 &
    TRACE_PID=$!
    sleep 3
    if ! kill -0 "$TRACE_PID" 2>/dev/null; then
        wait "$TRACE_PID" 2>/dev/null || true
        TRACE_PID=""
        echo "Game Memory trace failed to start; continuing runtime checks so the runner can report complete failure evidence." >&2
    fi
fi

summary_count() {
    local log_path="$1"
    awk \
        -v pid_marker="WatchCarRacer[$APP_PID:" \
        -v prefix="$SUMMARY_PREFIX" '
            index($0, pid_marker) && index($0, prefix) { count += 1 }
            END { print count + 0 }
        ' "$log_path"
}

stop_log_stream() {
    if [[ -n "$LOG_STREAM_PID" ]] && kill -0 "$LOG_STREAM_PID" 2>/dev/null; then
        kill -INT "$LOG_STREAM_PID" 2>/dev/null || true
        wait "$LOG_STREAM_PID" 2>/dev/null || true
    fi
    LOG_STREAM_PID=""
}

capture_unified_log_snapshot() {
    local destination="$1"
    /usr/bin/log show \
        --style compact \
        --directory "$SIMULATOR_LOG_DIRECTORY" \
        --start "$LOG_START" \
        --predicate \
        "processIdentifier == $APP_PID AND subsystem == '$BUNDLE_ID' AND category == 'SG6Acceptance'" \
        > "$destination" 2>&1 || true
}

START_SECONDS=$SECONDS
SUMMARY_COUNT=0
while (( SECONDS - START_SECONDS < TIMEOUT_SECONDS )); do
    SUMMARY_COUNT="$(summary_count "$UNIFIED_LOG")"
    if (( SUMMARY_COUNT > 0 )); then
        break
    fi
    sleep 2
done

stop_log_stream
SUMMARY_COUNT="$(summary_count "$UNIFIED_LOG")"
if (( SUMMARY_COUNT == 0 )); then
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    for flush_wait in 1 2 3 4 5; do
        sleep "$flush_wait"
        capture_unified_log_snapshot "$EVIDENCE_DIR/unified-show.log"
        SUMMARY_COUNT="$(summary_count "$EVIDENCE_DIR/unified-show.log")"
        if (( SUMMARY_COUNT > 0 )); then
            mv "$UNIFIED_LOG" "$EVIDENCE_DIR/unified-stream.log"
            mv "$EVIDENCE_DIR/unified-show.log" "$UNIFIED_LOG"
            break
        fi
    done
fi
awk \
    -v pid_marker="WatchCarRacer[$APP_PID:" \
    -v prefix="$SUMMARY_PREFIX" '
        index($0, pid_marker) && index($0, prefix) { print }
    ' "$UNIFIED_LOG" > "$EVIDENCE_DIR/summary.log"

if [[ "$MODE" == "memory" && -n "$TRACE_PID" ]] && kill -0 "$TRACE_PID" 2>/dev/null; then
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    for (( trace_finalize_wait = 0; trace_finalize_wait < 30; trace_finalize_wait += 1 )); do
        if ! kill -0 "$TRACE_PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if kill -0 "$TRACE_PID" 2>/dev/null; then
        stop_trace_process
    else
        wait "$TRACE_PID" 2>/dev/null || true
        TRACE_PID=""
    fi
fi

if [[ "$MODE" == "memory" ]]; then
    if [[ ! -d "$EVIDENCE_DIR/memory-game-memory.trace" ]] || ! xcrun xctrace export \
        --input "$EVIDENCE_DIR/memory-game-memory.trace" \
        --toc \
        --output "$EVIDENCE_DIR/memory-game-memory-toc.xml" \
        > "$EVIDENCE_DIR/xctrace-export.log" 2>&1; then
        echo "Memory summary was collected without an exportable continuous Game Memory trace." >&2
        exit 1
    fi
fi

if (( SUMMARY_COUNT != 1 )); then
    echo "Expected exactly one $SUMMARY_PREFIX record; found $SUMMARY_COUNT." >&2
    echo "Evidence: $EVIDENCE_DIR" >&2
    exit 1
fi

if ! grep -F -q "$SUMMARY_PREFIX pass=true" "$EVIDENCE_DIR/summary.log"; then
    echo "SG6 $MODE acceptance reported pass=false." >&2
    cat "$EVIDENCE_DIR/summary.log" >&2
    echo "Evidence: $EVIDENCE_DIR" >&2
    exit 1
fi

cat "$EVIDENCE_DIR/summary.log"
echo "SG6 $MODE acceptance evidence: $EVIDENCE_DIR"
