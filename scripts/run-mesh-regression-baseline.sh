#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
IMAGE_PATH="${1:-$ROOT_DIR/assets/shoe_input.png}"
PIPELINE_TYPE="${PIPELINE_TYPE:-1024_cascade}"
SEED="${SEED:-42}"
STAGE="${STAGE:-geometry}"
TEXTURE_SIZE="${TEXTURE_SIZE:-1024}"
SIMPLIFY_TARGET_FACES="${SIMPLIFY_TARGET_FACES:-0}"
RUN_TAG="${RUN_TAG:-$(date +"%Y%m%d-%H%M%S")}"
RUN_DIR="${RUN_DIR:-$ROOT_DIR/baseline-results/$RUN_TAG}"
OUTPUT_PREFIX="$RUN_DIR/baseline"
LOG_PATH="$RUN_DIR/run.log"
METRICS_PATH="$RUN_DIR/metrics.json"

if [ ! -x "$PYTHON_BIN" ]; then
    echo "error: missing Python interpreter: $PYTHON_BIN" >&2
    echo "Run bash setup.sh first." >&2
    exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
    echo "error: input image not found: $IMAGE_PATH" >&2
    exit 1
fi

mkdir -p "$RUN_DIR"

CMD=(
    "$PYTHON_BIN"
    "$ROOT_DIR/generate.py"
    "$IMAGE_PATH"
    "--output" "$OUTPUT_PREFIX"
    "--pipeline-type" "$PIPELINE_TYPE"
    "--seed" "$SEED"
    "--stage" "$STAGE"
    "--texture-size" "$TEXTURE_SIZE"
    "--debug-pipeline"
)

if [ "$SIMPLIFY_TARGET_FACES" -gt 0 ]; then
    CMD+=("--simplify-target-faces" "$SIMPLIFY_TARGET_FACES")
fi

echo "== Mesh Regression Baseline =="
echo "Run dir: $RUN_DIR"
echo "Image: $IMAGE_PATH"
echo "Stage: $STAGE"
echo "Pipeline: $PIPELINE_TYPE"
echo "Seed: $SEED"
echo "Texture size: $TEXTURE_SIZE"
echo "Simplify target faces: $SIMPLIFY_TARGET_FACES"
echo "Log: $LOG_PATH"
echo "Metrics: $METRICS_PATH"
echo

(
    cd "$ROOT_DIR"
    "${CMD[@]}"
) 2>&1 | tee "$LOG_PATH"

"$PYTHON_BIN" "$ROOT_DIR/scripts/extract-mesh-metrics.py" "$LOG_PATH" --output "$METRICS_PATH"

echo
echo "Baseline metrics written to:"
echo "  $METRICS_PATH"
