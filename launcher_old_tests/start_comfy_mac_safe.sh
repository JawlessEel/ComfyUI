#!/usr/bin/env bash

set -o pipefail

COMFY_DIR="/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI"
cd "$COMFY_DIR" || {
  echo "[ERROR] Could not cd into $COMFY_DIR"
  exit 1
}

if [[ -x "$COMFY_DIR/venv/bin/python" ]]; then
  PY="$COMFY_DIR/venv/bin/python"
  source "$COMFY_DIR/venv/bin/activate"
elif [[ -x "$COMFY_DIR/.venv/bin/python" ]]; then
  PY="$COMFY_DIR/.venv/bin/python"
  source "$COMFY_DIR/.venv/bin/activate"
else
  echo "[ERROR] No ComfyUI venv Python found."
  exit 1
fi

VENV_PREFIX="$("$PY" -c 'import sys; print(sys.prefix)')"
BASE_PREFIX="$("$PY" -c 'import sys; print(sys.base_prefix)')"

echo "[INFO] Starting launcher from: $COMFY_DIR"
echo "[INFO] Python command: $PY"
echo "[INFO] sys.prefix: $VENV_PREFIX"
echo "[INFO] sys.base_prefix: $BASE_PREFIX"
echo "[INFO] Python version: $("$PY" -V 2>&1)"
echo "[INFO] Pip version: $("$PY" -m pip --version 2>&1)"

case "$VENV_PREFIX" in
  "$COMFY_DIR/venv"|"$COMFY_DIR/.venv")
    echo "[INFO] Python venv check: OK"
    ;;
  *)
    echo "[ERROR] Python is not using the ComfyUI venv."
    echo "[ERROR] Expected prefix: $COMFY_DIR/venv or $COMFY_DIR/.venv"
    echo "[ERROR] Got prefix:      $VENV_PREFIX"
    exit 1
    ;;
esac

export PYTHONNOUSERSITE=1
export PATH="$(dirname "$PY"):$PATH"

export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.95
export PYTORCH_MPS_LOW_WATERMARK_RATIO=0.80

LOG_DIR="$COMFY_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/comfy_safe_$(date +%Y%m%d-%H%M%S).log"

echo "[INFO] PYTHONNOUSERSITE=$PYTHONNOUSERSITE"
echo "[INFO] PYTORCH_ENABLE_MPS_FALLBACK=$PYTORCH_ENABLE_MPS_FALLBACK"
echo "[INFO] PYTORCH_MPS_HIGH_WATERMARK_RATIO=$PYTORCH_MPS_HIGH_WATERMARK_RATIO"
echo "[INFO] PYTORCH_MPS_LOW_WATERMARK_RATIO=$PYTORCH_MPS_LOW_WATERMARK_RATIO"
echo "[INFO] Log file: $LOG_FILE"
echo "[INFO] Clearing old ComfyUI process on port 8188 if needed..."

OLD_PIDS="$(lsof -tiTCP:8188 -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$OLD_PIDS" ]]; then
  echo "[WARN] Killing old process using port 8188: $OLD_PIDS"
  kill $OLD_PIDS 2>/dev/null || true
  sleep 2
fi

OLD_PIDS="$(lsof -tiTCP:8188 -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$OLD_PIDS" ]]; then
  echo "[WARN] Force killing stubborn process using port 8188: $OLD_PIDS"
  kill -9 $OLD_PIDS 2>/dev/null || true
  sleep 1
fi

echo "[INFO] Launching ComfyUI..."
echo "[INFO] Open: http://127.0.0.1:8188"
echo

"$PY" main.py \
  --enable-manager \
  --enable-manager-legacy-ui \
  --listen 0.0.0.0 \
  --port 8188 \
  --preview-method none \
  --cache-lru 1 \
  --cpu-vae \
  --fp16-unet \
  --fp16-text-enc \
  --use-split-cross-attention 2>&1 | tee -a "$LOG_FILE"
