#!/usr/bin/env bash
set -uo pipefail

COMFY_DIR="/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI"
RESTART_DELAY_SECONDS="${RESTART_DELAY_SECONDS:-5}"
RESTART_AFTER_KILL="${RESTART_AFTER_KILL:-0}"

cd "$COMFY_DIR" || exit 1

if [[ -x "venv/bin/python" ]]; then
  PY="$COMFY_DIR/venv/bin/python"
  source "$COMFY_DIR/venv/bin/activate"
elif [[ -x ".venv/bin/python" ]]; then
  PY="$COMFY_DIR/.venv/bin/python"
  source "$COMFY_DIR/.venv/bin/activate"
else
  echo "[ERROR] No venv or .venv found in $COMFY_DIR"
  exit 1
fi

export PYTHONNOUSERSITE=1
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO="${PYTORCH_MPS_HIGH_WATERMARK_RATIO:-0.0}"

STOP_REQUESTED=0

stop_now() {
  STOP_REQUESTED=1
  echo
  echo "[INFO] Stop requested. ComfyUI will not restart."
}
trap stop_now INT TERM

while true; do
  echo
  echo "============================================================"
  echo "[INFO] Starting ComfyUI: $(date)"
  echo "[INFO] ComfyUI dir: $COMFY_DIR"
  echo "[INFO] Python: $PY"
  echo "[INFO] Python version: $("$PY" -V 2>&1)"
  echo "[INFO] Pip: $("$PY" -m pip --version 2>&1)"
  echo "[INFO] sys.prefix: $("$PY" -c 'import sys; print(sys.prefix)')"
  echo "[INFO] MPS fallback: $PYTORCH_ENABLE_MPS_FALLBACK"
  echo "[INFO] MPS high watermark: $PYTORCH_MPS_HIGH_WATERMARK_RATIO"
  echo "[INFO] Open: http://127.0.0.1:8188"
  echo "============================================================"
  echo

  "$PY" main.py \
    --enable-manager \
    --enable-manager-legacy-ui \
    --listen 0.0.0.0 \
    --port 8188 \
    --preview-method none \
    --cache-none \
    --fast-disk \
    --lowvram \
    --fp16-vae \
    --fp16-unet \
    --fp16-text-enc

  STATUS="$?"

  echo
  echo "[INFO] ComfyUI exited with status $STATUS at $(date)."

  if [[ "$STOP_REQUESTED" -eq 1 || "$STATUS" -eq 130 || "$STATUS" -eq 143 ]]; then
    echo "[INFO] Stopped by user. No restart."
    exit "$STATUS"
  fi

  if [[ "$STATUS" -eq 137 && "$RESTART_AFTER_KILL" != "1" ]]; then
    echo "[ERROR] ComfyUI was killed by macOS memory pressure."
    echo "[ERROR] Not auto-restarting after Killed: 9 unless RESTART_AFTER_KILL=1 is set."
    echo "[ERROR] This avoids a memory-death restart loop."
    exit "$STATUS"
  fi

  echo "[INFO] Restarting ComfyUI in ${RESTART_DELAY_SECONDS}s..."
  sleep "$RESTART_DELAY_SECONDS"
done
