#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 --device <name> --os <version> [--mode full|development]" >&2
    echo "       development also requires --track <coastal|alpine|desert> --weather <clear|rain|fog|storm> --tier <baseline|enhanced> --duration <seconds>" >&2
}

MODE=full
DEVICE_NAME=""
OS_VERSION=""
TRACK=""
WEATHER=""
TIER=""
DURATION=""
ENFORCE_PERFORMANCE=false

while (($# > 0)); do
    case "$1" in
        --mode) MODE="${2:-}"; shift 2 ;;
        --device) DEVICE_NAME="${2:-}"; shift 2 ;;
        --os) OS_VERSION="${2:-}"; shift 2 ;;
        --track) TRACK="${2:-}"; shift 2 ;;
        --weather) WEATHER="${2:-}"; shift 2 ;;
        --tier) TIER="${2:-}"; shift 2 ;;
        --duration) DURATION="${2:-}"; shift 2 ;;
        --enforce-performance) ENFORCE_PERFORMANCE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 64 ;;
    esac
done

case "$MODE" in full|development) ;; *) usage; exit 64 ;; esac
if [[ -z "$DEVICE_NAME" || -z "$OS_VERSION" ]]; then
    usage
    exit 64
fi
if [[ "$MODE" == "development" ]]; then
    case "$TRACK" in coastal|alpine|desert) ;; *) usage; exit 64 ;; esac
    case "$WEATHER" in clear|rain|fog|storm) ;; *) usage; exit 64 ;; esac
    case "$TIER" in baseline|enhanced) ;; *) usage; exit 64 ;; esac
    if [[ ! "$DURATION" =~ ^([5-9]|[1-9][0-9]+)(\.[0-9]+)?$ ]]; then
        usage
        exit 64
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
EVIDENCE_DIR="$PROJECT_ROOT/.woohyuk/racing-environment-acceptance/$TIMESTAMP"
SCENARIO_EVIDENCE="$EVIDENCE_DIR/scenarios"
DERIVED_DATA="${RACING_ENVIRONMENT_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/watch-car-racer-racing-environment-derived-data}"
RUNNER="$SCRIPT_DIR/run_sg6_acceptance.sh"
mkdir -p "$SCENARIO_EVIDENCE" "$DERIVED_DATA" "$EVIDENCE_DIR/screenshots"

SCENARIO_COUNT=0

run_environment() {
    local label="$1"
    local track="$2"
    local weather="$3"
    local tier="$4"
    local duration="$5"
    local route_cycles="$6"
    local trigger_memory="$7"
    local enforce_performance="$8"
    local screenshot="$9"
    local timeout
    local attempt=1
    local attempt_log
    local status
    timeout="$(awk -v duration="$duration" -v cycles="$route_cycles" 'BEGIN { print int(duration + cycles * 8 + 180) }')"

    while (( attempt <= 2 )); do
        attempt_log="$EVIDENCE_DIR/$label-attempt$attempt.log"
        if SG6_EVIDENCE_ROOT="$SCENARIO_EVIDENCE" \
            SG6_DERIVED_DATA_PATH="$DERIVED_DATA" \
            SG8_TRACK="$track" \
            SG8_WEATHER="$weather" \
            SG8_TIER="$tier" \
            SG8_DURATION="$duration" \
            SG8_ROUTE_CYCLES="$route_cycles" \
            SG8_TRIGGER_MEMORY_WARNING="$trigger_memory" \
            SG8_ENFORCE_PERFORMANCE="$enforce_performance" \
            SG8_SCREENSHOT_DESTINATION="$screenshot" \
            "$RUNNER" environment "$DEVICE_NAME" "$OS_VERSION" "$timeout" \
                > "$attempt_log" 2>&1; then
            cp "$attempt_log" "$EVIDENCE_DIR/$label.log"
            break
        else
            status=$?
        fi
        if [[ "$status" != "75" || "$attempt" == "2" ]]; then
            cat "$attempt_log" >&2
            return "$status"
        fi
        printf 'scenario=%s attempt=%s result=known-simulator-framework-startup-crash retrying=true\n' \
            "$label" "$attempt" >> "$EVIDENCE_DIR/retry.log"
        attempt=$((attempt + 1))
    done
    SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
}

run_sensory() {
    local label="$1"
    local reduce_motion="$2"
    local reduce_transparency="$3"
    local simulator_udid="$4"
    local attempt=1
    local attempt_log
    local status
    printf 'scenario=%s reduceMotion=%s reduceTransparency=%s source=launch-override\n' \
        "$label" "$reduce_motion" "$reduce_transparency" \
        >> "$EVIDENCE_DIR/accessibility-config.log"
    while (( attempt <= 2 )); do
        attempt_log="$EVIDENCE_DIR/$label-attempt$attempt.log"
        if SG6_EVIDENCE_ROOT="$SCENARIO_EVIDENCE" \
            SG6_DERIVED_DATA_PATH="$DERIVED_DATA" \
            SG8_TRACK=coastal \
            SG8_WEATHER=storm \
            SG8_TIER=baseline \
            SG8_DURATION=5 \
            SG8_EXPECT_REDUCE_MOTION="$reduce_motion" \
            SG8_EXPECT_REDUCE_TRANSPARENCY="$reduce_transparency" \
            "$RUNNER" sensory "$DEVICE_NAME" "$OS_VERSION" 180 \
                > "$attempt_log" 2>&1; then
            cp "$attempt_log" "$EVIDENCE_DIR/$label.log"
            break
        else
            status=$?
        fi
        if [[ "$status" != "75" || "$attempt" == "2" ]]; then
            cat "$attempt_log" >&2
            return "$status"
        fi
        printf 'scenario=%s attempt=%s result=known-simulator-framework-startup-crash retrying=true\n' \
            "$label" "$attempt" >> "$EVIDENCE_DIR/retry.log"
        attempt=$((attempt + 1))
    done
    SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
}

if [[ "$MODE" == "development" ]]; then
    screenshot="$EVIDENCE_DIR/screenshots/development-${TRACK}-${WEATHER}-${TIER}.png"
    run_environment \
        "development-${TRACK}-${WEATHER}-${TIER}" \
        "$TRACK" "$WEATHER" "$TIER" "$DURATION" 0 false \
        "$ENFORCE_PERFORMANCE" "$screenshot"
else
    for track in coastal alpine desert; do
        for weather in clear rain fog storm; do
            run_environment \
                "visual-${track}-${weather}-baseline" \
                "$track" "$weather" baseline 10 0 false false \
                "$EVIDENCE_DIR/screenshots/${track}-${weather}-baseline.png"
        done
        run_environment \
            "forced-${track}-enhanced" \
            "$track" clear enhanced 8 0 false false \
            "$EVIDENCE_DIR/screenshots/${track}-clear-enhanced.png"
    done

    for track in coastal alpine desert; do
        for weather in clear storm; do
            run_environment \
                "fps-${track}-${weather}-baseline" \
                "$track" "$weather" baseline 60 0 false true ""
        done
    done
    run_environment "soak-desert-storm-baseline" desert storm baseline 300 0 false true ""
    run_environment "route-cycles" coastal clear baseline 5 10 false false ""
    run_environment "adaptive-memory-warning" coastal storm enhanced 8 0 true false ""

    RUNTIME_HEADER="-- iOS ${OS_VERSION} --"
    SIMULATOR_UDID="$({
        xcrun simctl list devices available | awk -v runtime="$RUNTIME_HEADER" -v device="$DEVICE_NAME" '
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
        echo "Unable to resolve simulator for accessibility matrix." >&2
        exit 69
    fi
    xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null
    run_sensory accessibility-false-false false false "$SIMULATOR_UDID"
    run_sensory accessibility-false-true false true "$SIMULATOR_UDID"
    run_sensory accessibility-true-false true false "$SIMULATOR_UDID"
    run_sensory accessibility-true-true true true "$SIMULATOR_UDID"
fi

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/WatchCarRacer.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Acceptance build product is missing: $APP_PATH" >&2
    exit 1
fi
APP_PATH="$(cd "$APP_PATH" && pwd -P)"
"$SCRIPT_DIR/measure_compiled_texture_memory.swift" "$APP_PATH" \
    > "$EVIDENCE_DIR/texture-memory.log" 2>&1

EXPECTED_SCREENSHOTS=1
if [[ "$MODE" == "full" ]]; then
    EXPECTED_SCREENSHOTS=15
fi
ACTUAL_SCREENSHOTS="$(find "$EVIDENCE_DIR/screenshots" -type f -name '*.png' -size +0c | wc -l | tr -d ' ')"
if [[ "$ACTUAL_SCREENSHOTS" != "$EXPECTED_SCREENSHOTS" ]]; then
    echo "Expected $EXPECTED_SCREENSHOTS screenshots; found $ACTUAL_SCREENSHOTS." >&2
    exit 1
fi

SUMMARY="RACING_ENVIRONMENT_ACCEPTANCE_RUN_SUMMARY pass=true mode=$MODE scenarios=$SCENARIO_COUNT screenshots=$ACTUAL_SCREENSHOTS evidence=$EVIDENCE_DIR"
printf '%s\n' "$SUMMARY" | tee "$EVIDENCE_DIR/summary.log"
