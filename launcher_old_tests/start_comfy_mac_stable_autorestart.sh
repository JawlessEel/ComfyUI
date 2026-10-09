#!/usr/bin/env bash
set -u
set -o pipefail

COMFY_DIR="${COMFY_DIR:-/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI}"
HOST="${COMFY_HOST:-0.0.0.0}"
PORT="${COMFY_PORT:-8188}"
RESTART_DELAY_SECONDS="${RESTART_DELAY_SECONDS:-5}"
MIN_UPTIME_SECONDS="${MIN_UPTIME_SECONDS:-20}"
MAX_QUICK_RESTARTS="${MAX_QUICK_RESTARTS:-3}"

cd "$COMFY_DIR" || exit 1

if [[ -f "venv/bin/activate" ]]; then
  source "venv/bin/activate"
elif [[ -f ".venv/bin/activate" ]]; then
  source ".venv/bin/activate"
else
  echo "[ERROR] No venv/bin/activate or .venv/bin/activate found."
  exit 1
fi

PYTHON_REAL="$(python - <<'PY'
import os, sys
print(os.path.realpath(sys.executable))
PY
)"

case "$PYTHON_REAL" in
  "$COMFY_DIR"/venv/bin/python*|"$COMFY_DIR"/.venv/bin/python*)
    ;;
  *)
    echo "[ERROR] Wrong Python detected:"
    echo "$PYTHON_REAL"
    exit 1
    ;;
esac

export PYTHONNOUSERSITE=1
export PIP_REQUIRE_VIRTUALENV=true
export PATH="$(dirname "$PYTHON_REAL"):$PATH"

export PYTORCH_ENABLE_MPS_FALLBACK="${PYTORCH_ENABLE_MPS_FALLBACK:-1}"
export PYTORCH_MPS_HIGH_WATERMARK_RATIO="${PYTORCH_MPS_HIGH_WATERMARK_RATIO:-0.95}"
export PYTORCH_MPS_LOW_WATERMARK_RATIO="${PYTORCH_MPS_LOW_WATERMARK_RATIO:-0.80}"

cat > "$COMFY_DIR/comfy_pip_install.sh" <<'PIPSH'
#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI}"
cd "$COMFY_DIR"

if [[ -x "venv/bin/python" ]]; then
  PY="./venv/bin/python"
elif [[ -x ".venv/bin/python" ]]; then
  PY="./.venv/bin/python"
else
  echo "[ERROR] No ComfyUI venv Python found."
  exit 1
fi

export PYTHONNOUSERSITE=1
export PIP_REQUIRE_VIRTUALENV=true

echo "[INFO] Using Python:"
"$PY" - <<'PY'
import sys
print(sys.executable)
PY
echo "[INFO] Pip:"
"$PY" -m pip --version
echo

if [[ "$#" -eq 0 ]]; then
  echo "Usage:"
  echo "  ./comfy_pip_install.sh install package_name"
  echo "  ./comfy_pip_install.sh install -r custom_nodes/SomeNode/requirements.txt"
  echo "  ./comfy_pip_install.sh list"
  echo "  ./comfy_pip_install.sh show package_name"
  exit 0
fi

exec "$PY" -m pip "$@"
PIPSH

chmod +x "$COMFY_DIR/comfy_pip_install.sh"

LOG_DIR="$COMFY_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/comfy_stable_autorestart_$(date +%Y%m%d-%H%M%S).log"

echo "[INFO] ComfyUI directory: $COMFY_DIR"
echo "[INFO] Python: $PYTHON_REAL"
echo "[INFO] Python version: $(python -V 2>&1)"
echo "[INFO] Pip: $(python -m pip --version 2>&1)"
echo "[INFO] Pip helper: $COMFY_DIR/comfy_pip_install.sh"
echo "[INFO] Listening on: $HOST:$PORT"
echo "[INFO] Log file: $LOG_FILE"
echo "[INFO] PYTHONNOUSERSITE=$PYTHONNOUSERSITE"
echo "[INFO] PIP_REQUIRE_VIRTUALENV=$PIP_REQUIRE_VIRTUALENV"
echo "[INFO] PYTORCH_ENABLE_MPS_FALLBACK=$PYTORCH_ENABLE_MPS_FALLBACK"
echo "[INFO] PYTORCH_MPS_HIGH_WATERMARK_RATIO=$PYTORCH_MPS_HIGH_WATERMARK_RATIO"
echo "[INFO] PYTORCH_MPS_LOW_WATERMARK_RATIO=$PYTORCH_MPS_LOW_WATERMARK_RATIO"

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
    echo "[WARN] Unsupported flag skipped: $flag $*"
  fi
}

add_arg_if_supported "--enable-manager"
add_arg_if_supported "--enable-manager-legacy-ui"
add_arg_if_supported "--listen" "$HOST"
add_arg_if_supported "--port" "$PORT"
add_arg_if_supported "--preview-method" "none"
add_arg_if_supported "--cache-lru" "1"
add_arg_if_supported "--fast-disk"
add_arg_if_supported "--normalvram"
add_arg_if_supported "--cpu-vae"
add_arg_if_supported "--fp16-unet"
add_arg_if_supported "--fp16-text-enc"
add_arg_if_supported "--use-split-cross-attention"

if [[ -n "${COMFY_EXTRA_ARGS:-}" ]]; then
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

  if [[ "$status" -eq 137 ]]; then
    echo "[ERROR] ComfyUI was killed by macOS memory pressure. Not auto-restarting into another memory death spiral." | tee -a "$LOG_FILE"
    echo "[ERROR] Clear the queue, lower batch count, or disable heavy scanner nodes before restarting." | tee -a "$LOG_FILE"
    exit "$status"
  fi

  if [[ "$runtime_seconds" -lt "$MIN_UPTIME_SECONDS" ]]; then
    quick_restart_count=$((quick_restart_count + 1))
    echo "[WARN] Quick exit detected: $quick_restart_count/$MAX_QUICK_RESTARTS" | tee -a "$LOG_FILE"
  else
    quick_restart_count=0
  fi

  if [[ "$quick_restart_count" -ge "$MAX_QUICK_RESTARTS" ]]; then
    echo "[ERROR] Too many quick exits. Stopping." | tee -a "$LOG_FILE"
    exit "$status"
  fi

  echo "[INFO] Restarting ComfyUI in ${RESTART_DELAY_SECONDS}s." | tee -a "$LOG_FILE"
  sleep "$RESTART_DELAY_SECONDS"
done
