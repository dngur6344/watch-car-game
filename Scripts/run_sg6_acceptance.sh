#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 <presentation|fps|memory|sensory|environment> <iOS simulator name> <OS version> [timeout seconds]" >&2
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
    usage
    exit 64
fi

MODE="$1"
DEVICE_NAME="$2"
OS_VERSION="$3"
ACCEPTANCE_LABEL="SG6 $MODE"

case "$MODE" in
    presentation)
        SUMMARY_PREFIX="SG6_PRESENTATION_SUMMARY"
        LAUNCH_ARGUMENT="--sg6-presentation"
        DEFAULT_TIMEOUT=60
        START_DELAY=0
        ;;
    fps)
        SUMMARY_PREFIX="SG6_FPS_SUMMARY"
        LAUNCH_ARGUMENT="--sg6-fps"
        DEFAULT_TIMEOUT=540
        START_DELAY=1
        ;;
    memory)
        SUMMARY_PREFIX="SG6_MEMORY_SUMMARY"
        LAUNCH_ARGUMENT="--sg6-memory"
        DEFAULT_TIMEOUT=900
        START_DELAY=8
        ;;
    sensory)
        SUMMARY_PREFIX="SG8_SENSORY_SUMMARY"
        LAUNCH_ARGUMENT="--sg8-sensory"
        ACCEPTANCE_LABEL="SG8 sensory"
        DEFAULT_TIMEOUT=120
        START_DELAY=1
        ;;
    environment)
        SUMMARY_PREFIX="RACING_ENVIRONMENT_ACCEPTANCE_SUMMARY"
        LAUNCH_ARGUMENT="--sg8-racing-environment"
        ACCEPTANCE_LABEL="racing environment"
        DEFAULT_TIMEOUT=900
        START_DELAY=1
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
LAUNCH_ARGUMENTS=(
    "$LAUNCH_ARGUMENT"
    --sg6-start-delay
    "$START_DELAY"
)

if [[ "$MODE" == "sensory" ]]; then
    if [[ -n "${SG8_EFFECT_INTENSITY:-}" ]]; then
        case "$SG8_EFFECT_INTENSITY" in
            balanced|reduced)
                LAUNCH_ARGUMENTS+=(
                    --sg8-effect-intensity "$SG8_EFFECT_INTENSITY"
                )
                ;;
            *)
                echo "SG8_EFFECT_INTENSITY must be balanced or reduced." >&2
                exit 64
                ;;
        esac
    fi
    for expectation in SG8_EXPECT_REDUCE_MOTION SG8_EXPECT_REDUCE_TRANSPARENCY; do
        value="${!expectation:-}"
        if [[ -z "$value" ]]; then
            continue
        fi
        if [[ "$value" != "true" && "$value" != "false" ]]; then
            echo "$expectation must be true or false." >&2
            exit 64
        fi
        argument="--$(printf '%s' "$expectation" | tr '[:upper:]_' '[:lower:]-')"
        LAUNCH_ARGUMENTS+=("$argument" "$value")
    done
fi

if [[ "$MODE" == "environment" ]]; then
    : "${SG8_TRACK:?SG8_TRACK is required for environment mode}"
    : "${SG8_WEATHER:?SG8_WEATHER is required for environment mode}"
    : "${SG8_TIER:?SG8_TIER is required for environment mode}"
    : "${SG8_DURATION:?SG8_DURATION is required for environment mode}"
    SG8_ROUTE_CYCLES="${SG8_ROUTE_CYCLES:-0}"
    case "$SG8_TRACK" in coastal|alpine|desert) ;; *) echo "Invalid SG8_TRACK." >&2; exit 64 ;; esac
    case "$SG8_WEATHER" in clear|rain|fog|storm) ;; *) echo "Invalid SG8_WEATHER." >&2; exit 64 ;; esac
    case "$SG8_TIER" in baseline|enhanced) ;; *) echo "Invalid SG8_TIER." >&2; exit 64 ;; esac
    if [[ ! "$SG8_DURATION" =~ ^([5-9]|[1-9][0-9]+)(\.[0-9]+)?$ ]]; then
        echo "SG8_DURATION must be a finite number of at least 5 seconds." >&2
        exit 64
    fi
    if [[ ! "$SG8_ROUTE_CYCLES" =~ ^([0-9]|10)$ ]]; then
        echo "SG8_ROUTE_CYCLES must be an integer from 0 through 10." >&2
        exit 64
    fi
    LAUNCH_ARGUMENTS+=(
        --sg8-track "$SG8_TRACK"
        --sg8-weather "$SG8_WEATHER"
        --sg8-tier "$SG8_TIER"
        --sg8-duration "$SG8_DURATION"
        --sg8-route-cycles "$SG8_ROUTE_CYCLES"
        "--watch-car-racer-environment-quality=$SG8_TIER"
    )
    if [[ "${SG8_TRIGGER_MEMORY_WARNING:-false}" == "true" ]]; then
        LAUNCH_ARGUMENTS+=(--sg8-trigger-memory-warning)
    fi
    if [[ "${SG8_ENFORCE_PERFORMANCE:-false}" == "true" ]]; then
        LAUNCH_ARGUMENTS+=(--sg8-enforce-performance)
    fi
    if [[ -n "${SG8_SCREENSHOT_DESTINATION:-}" ]]; then
        LAUNCH_ARGUMENTS+=(--sg8-require-racing-screenshot)
    fi
fi

if [[ "$MODE" == "sensory" && -n "${SG8_TRACK:-}" ]]; then
    : "${SG8_WEATHER:?SG8_WEATHER is required when SG8_TRACK is set}"
    : "${SG8_TIER:?SG8_TIER is required when SG8_TRACK is set}"
    LAUNCH_ARGUMENTS+=(
        --sg8-track "$SG8_TRACK"
        --sg8-weather "$SG8_WEATHER"
        --sg8-tier "$SG8_TIER"
        --sg8-duration "${SG8_DURATION:-5}"
        --sg8-route-cycles 0
        "--watch-car-racer-environment-quality=$SG8_TIER"
    )
fi

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
    if [[ "$MODE" == "sensory" ]]; then
        echo "effectIntensity=${SG8_EFFECT_INTENSITY:-stored}"
        echo "expectedReduceMotion=${SG8_EXPECT_REDUCE_MOTION:-unspecified}"
        echo "expectedReduceTransparency=${SG8_EXPECT_REDUCE_TRANSPARENCY:-unspecified}"
    fi
    if [[ "$MODE" == "environment" ]]; then
        echo "track=$SG8_TRACK"
        echo "weather=$SG8_WEATHER"
        echo "tier=$SG8_TIER"
        echo "duration=$SG8_DURATION"
        echo "routeCycles=$SG8_ROUTE_CYCLES"
        echo "triggerMemoryWarning=${SG8_TRIGGER_MEMORY_WARNING:-false}"
        echo "enforcePerformance=${SG8_ENFORCE_PERFORMANCE:-false}"
        echo "requiresRacingScreenshot=$([[ -n "${SG8_SCREENSHOT_DESTINATION:-}" ]] && echo true || echo false)"
    fi
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
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
if [[ "$MODE" == "environment" || "$MODE" == "sensory" ]]; then
    xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
fi
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

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
    "${LAUNCH_ARGUMENTS[@]}")"
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

screenshot_readiness_count() {
    local log_path="$1"
    awk \
        -v pid_marker="WatchCarRacer[$APP_PID:" \
        -v prefix="RACING_ENVIRONMENT_SCREENSHOT_READY " '
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
SCREENSHOT_CAPTURED=false
SCREENSHOT_READINESS_COUNT=0
KNOWN_SIMULATOR_STARTUP_CRASH=false

capture_known_simulator_startup_crash() {
    local report=""
    local candidate
    for crash_wait in 1 2 3 4 5; do
        while IFS= read -r candidate; do
            if grep -E -q "\"pid\"[[:space:]]*:[[:space:]]*$APP_PID([,}]|$)" "$candidate" \
                && grep -F -q 'com.apple.spritekit.preloadQueue' "$candidate" \
                && grep -F -q 'SKTextureAtlas' "$candidate" \
                && grep -F -q 'UIScreen currentMode' "$candidate"; then
                report="$candidate"
                break
            fi
        done < <(
            find "$HOME/Library/Logs/DiagnosticReports" \
                -maxdepth 1 -type f -name 'WatchCarRacer*.ips' -mmin -5 -print \
                2>/dev/null
        )
        if [[ -n "$report" ]]; then
            cp "$report" "$EVIDENCE_DIR/known-simulator-framework-startup-crash.ips"
            echo "Known Simulator SpriteKit/UIScreen startup crash for PID $APP_PID." >&2
            return 0
        fi
        sleep 1
    done
    return 1
}

while (( SECONDS - START_SECONDS < TIMEOUT_SECONDS )); do
    if [[ -n "${SG8_SCREENSHOT_DESTINATION:-}" && "$SCREENSHOT_CAPTURED" == "false" ]]; then
        SCREENSHOT_READINESS_COUNT="$(screenshot_readiness_count "$UNIFIED_LOG")"
        if (( SCREENSHOT_READINESS_COUNT > 1 )); then
            echo "Expected one racing screenshot readiness token; found $SCREENSHOT_READINESS_COUNT." >&2
            break
        fi
        if (( SCREENSHOT_READINESS_COUNT == 1 )); then
            mkdir -p "$(dirname "$SG8_SCREENSHOT_DESTINATION")"
            awk \
                -v pid_marker="WatchCarRacer[$APP_PID:" \
                -v prefix="RACING_ENVIRONMENT_SCREENSHOT_READY " '
                    index($0, pid_marker) && index($0, prefix) { print }
                ' "$UNIFIED_LOG" > "$EVIDENCE_DIR/screenshot-readiness.log"
            if ! grep -F -q "route=playing phase=racing rendered=true countdownOverlay=false sampleCount=1 " \
                "$EVIDENCE_DIR/screenshot-readiness.log"; then
                echo "Racing screenshot readiness token did not satisfy the rendered racing contract." >&2
                break
            fi
            xcrun simctl io "$SIMULATOR_UDID" screenshot "$SG8_SCREENSHOT_DESTINATION"
            {
                echo "capturedUTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
                echo "destination=$SG8_SCREENSHOT_DESTINATION"
            } > "$EVIDENCE_DIR/screenshot-capture.log"
            SCREENSHOT_CAPTURED=true
        fi
    fi
    SUMMARY_COUNT="$(summary_count "$UNIFIED_LOG")"
    if (( SUMMARY_COUNT > 0 )); then
        break
    fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "Launched app process $APP_PID exited before emitting $SUMMARY_PREFIX." >&2
        if capture_known_simulator_startup_crash; then
            KNOWN_SIMULATOR_STARTUP_CRASH=true
        fi
        break
    fi
    sleep 2
done

if [[ "$KNOWN_SIMULATOR_STARTUP_CRASH" != "true" \
      && -n "${SG8_SCREENSHOT_DESTINATION:-}" \
      && ! -s "$SG8_SCREENSHOT_DESTINATION" ]]; then
    echo "Requested screenshot was not captured at $SG8_SCREENSHOT_DESTINATION." >&2
    exit 1
fi

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

if [[ "$KNOWN_SIMULATOR_STARTUP_CRASH" == "true" && "$SUMMARY_COUNT" == "0" ]]; then
    echo "Known Simulator framework startup crash evidence: $EVIDENCE_DIR" >&2
    exit 75
fi

if (( SUMMARY_COUNT != 1 )); then
    echo "Expected exactly one $SUMMARY_PREFIX record; found $SUMMARY_COUNT." >&2
    echo "Evidence: $EVIDENCE_DIR" >&2
    exit 1
fi

if ! grep -F -q "$SUMMARY_PREFIX pass=true" "$EVIDENCE_DIR/summary.log"; then
    echo "$ACCEPTANCE_LABEL acceptance reported pass=false." >&2
    cat "$EVIDENCE_DIR/summary.log" >&2
    echo "Evidence: $EVIDENCE_DIR" >&2
    exit 1
fi

if [[ -n "${SG8_SCREENSHOT_DESTINATION:-}" ]]; then
    SCREENSHOT_READINESS_COUNT="$(screenshot_readiness_count "$UNIFIED_LOG")"
    if (( SCREENSHOT_READINESS_COUNT != 1 )); then
        echo "Expected exactly one racing screenshot readiness token; found $SCREENSHOT_READINESS_COUNT." >&2
        exit 1
    fi
    for field in \
        "screenshotRequired=true" \
        "screenshotReady=true" \
        "screenshotRendered=true" \
        "screenshotCountdownOverlay=false" \
        "screenshotReadinessSamples=1"; do
        if ! grep -F -q "$field" "$EVIDENCE_DIR/summary.log"; then
            echo "Screenshot acceptance summary is missing required field: $field" >&2
            exit 1
        fi
    done
fi

cat "$EVIDENCE_DIR/summary.log"
echo "$ACCEPTANCE_LABEL acceptance evidence: $EVIDENCE_DIR"
