#!/usr/bin/env bash
# ComfyUI Mac mini optimized launcher with auto-restart.
# Designed for heavier SDXL / Illustrious models on Apple Silicon.
#
# Run:
#   cd /Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI
#   ./start_comfy_mac_optimized_autorestart.sh
#
# Stop:
#   Press Ctrl+C in the Terminal window.

set -u
set -o pipefail

COMFY_DIR="${COMFY_DIR:-/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI}"
HOST="${COMFY_HOST:-0.0.0.0}"
PORT="${COMFY_PORT:-8188}"

# Auto-restart settings.
# This is what lets ComfyUI come back after using Manager's restart button.
RESTART_DELAY_SECONDS="${RESTART_DELAY_SECONDS:-5}"
MIN_UPTIME_SECONDS="${MIN_UPTIME_SECONDS:-20}"
MAX_QUICK_RESTARTS="${MAX_QUICK_RESTARTS:-3}"

cd "$COMFY_DIR" || {
  echo "[ERROR] Could not enter ComfyUI directory: $COMFY_DIR"
  exit 1
}

if [[ -f "venv/bin/activate" ]]; then
  source "venv/bin/activate"
elif [[ -f ".venv/bin/activate" ]]; then
  source ".venv/bin/activate"
else
  echo "[ERROR] No venv/bin/activate or .venv/bin/activate found in:"
  echo "        $COMFY_DIR"
  exit 1
fi

# Apple Silicon / PyTorch MPS settings.
# Fallback allows unsupported MPS operations to run on CPU instead of hard-failing.
export PYTORCH_ENABLE_MPS_FALLBACK="${PYTORCH_ENABLE_MPS_FALLBACK:-1}"

# 0.0 disables PyTorch's hard MPS memory cap.
# This can prevent MPS OOM errors on big SDXL/Illustrious loads,
# but close LM Studio, browsers, Photoshop, etc. before heavy generations.
export PYTORCH_MPS_HIGH_WATERMARK_RATIO="${PYTORCH_MPS_HIGH_WATERMARK_RATIO:-0.0}"

LOG_DIR="$COMFY_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/comfy_optimized_autorestart_$(date +%Y%m%d-%H%M%S).log"

echo "[INFO] ComfyUI directory: $COMFY_DIR"
echo "[INFO] Python: $(which python)"
echo "[INFO] Python version: $(python -V 2>&1)"
echo "[INFO] Listening on: $HOST:$PORT"
echo "[INFO] Log file: $LOG_FILE"
echo "[INFO] PYTORCH_ENABLE_MPS_FALLBACK=$PYTORCH_ENABLE_MPS_FALLBACK"
echo "[INFO] PYTORCH_MPS_HIGH_WATERMARK_RATIO=$PYTORCH_MPS_HIGH_WATERMARK_RATIO"

HELP_TEXT="$(python main.py --help 2>&1 || true)"

ARGS=()

add_arg_if_supported() {
  local flag="$1"
  shift || true

  if printf '%s\n' "$HELP_TEXT" | grep -q -- "$flag"; then
    ARGS+=("$flag")
    while [[ "$#" -gt 0 ]]; do
      ARGS+=("$1")
      shift
    done
  else
    echo "[WARN] Skipping unsupported ComfyUI flag: $flag $*"
  fi
}

# Manager flags. These are skipped if your current ComfyUI build does not expose them.
add_arg_if_supported "--enable-manager"
add_arg_if_supported "--enable-manager-legacy-ui"

# Network settings.
add_arg_if_supported "--listen" "$HOST"
add_arg_if_supported "--port" "$PORT"

# Memory-saving / SDXL-heavy workflow settings.
add_arg_if_supported "--preview-method" "none"
add_arg_if_supported "--cache-none"
add_arg_if_supported "--fast-disk"
add_arg_if_supported "--lowvram"
add_arg_if_supported "--cpu-vae"
add_arg_if_supported "--fp16-unet"
add_arg_if_supported "--fp16-text-enc"

# Optional simple override from the shell, for example:
#   COMFY_EXTRA_ARGS="--normalvram" ./start_comfy_mac_optimized_autorestart.sh
if [[ -n "${COMFY_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_FROM_ENV=( $COMFY_EXTRA_ARGS )
  ARGS+=("${EXTRA_FROM_ENV[@]}")
fi

echo "[INFO] Launch args:"
printf '  %q' python main.py "${ARGS[@]}"
echo
echo

STOP_REQUESTED=0

on_stop() {
  STOP_REQUESTED=1
  echo
  echo "[INFO] Stop requested. ComfyUI will not auto-restart."
}
trap on_stop INT TERM

quick_restart_count=0

while true; do
  start_epoch="$(date +%s)"
  echo "============================================================" | tee -a "$LOG_FILE"
  echo "[INFO] Starting ComfyUI at $(date)" | tee -a "$LOG_FILE"
  echo "============================================================" | tee -a "$LOG_FILE"

  set +e
  python main.py "${ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
  status="${PIPESTATUS[0]}"
  set -e

  end_epoch="$(date +%s)"
  runtime_seconds=$((end_epoch - start_epoch))

  echo "[INFO] ComfyUI exited with status $status after ${runtime_seconds}s at $(date)." | tee -a "$LOG_FILE"

  if [[ "$STOP_REQUESTED" -eq 1 || "$status" -eq 130 || "$status" -eq 143 ]]; then
    echo "[INFO] Stopped by user. No restart." | tee -a "$LOG_FILE"
    exit "$status"
  fi

  if [[ "$runtime_seconds" -lt "$MIN_UPTIME_SECONDS" ]]; then
    quick_restart_count=$((quick_restart_count + 1))
    echo "[WARN] Quick exit detected. Quick restart count: $quick_restart_count/$MAX_QUICK_RESTARTS" | tee -a "$LOG_FILE"
  else
    quick_restart_count=0
  fi

  if [[ "$quick_restart_count" -ge "$MAX_QUICK_RESTARTS" ]]; then
    echo "[ERROR] ComfyUI exited too quickly too many times. Stopping so we do not make a crash loop goblin." | tee -a "$LOG_FILE"
    echo "[ERROR] Check the log file:" | tee -a "$LOG_FILE"
    echo "        $LOG_FILE" | tee -a "$LOG_FILE"
    exit "$status"
  fi

  echo "[INFO] Restarting ComfyUI in ${RESTART_DELAY_SECONDS}s. Manager restart button should land right back here." | tee -a "$LOG_FILE"
  sleep "$RESTART_DELAY_SECONDS"
done
