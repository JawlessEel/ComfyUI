#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI"
cd "$COMFY_DIR"

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

echo "[INFO] ComfyUI dir: $COMFY_DIR"
echo "[INFO] Python: $PY"
echo "[INFO] Python version: $("$PY" -V 2>&1)"
echo "[INFO] Pip: $("$PY" -m pip --version 2>&1)"
echo "[INFO] sys.prefix: $("$PY" -c 'import sys; print(sys.prefix)')"
echo "[INFO] MPS fallback: $PYTORCH_ENABLE_MPS_FALLBACK"
echo "[INFO] MPS high watermark: $PYTORCH_MPS_HIGH_WATERMARK_RATIO"
echo "[INFO] Open: http://127.0.0.1:8188"

exec "$PY" main.py \
  --enable-manager \
  --enable-manager-legacy-ui \
  --listen 0.0.0.0 \
  --port 8188 \
  --preview-method none \
  --cache-none \
  --fast-disk \
  --lowvram \
  --cpu-vae \
  --fp16-unet \
  --fp16-text-enc
