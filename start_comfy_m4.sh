#!/bin/bash
# ComfyUI launcher tuned for Apple Silicon M4 / 32 GB unified memory.
#
# Differences vs start_comfy_mac.sh, and why:
#   --lowvram     REMOVED  streams weights layer-by-layer to spare VRAM. On unified
#                          memory RAM *is* VRAM, so it only adds copy overhead.
#   --cache-none  REMOVED  forced a full 6.5 GB checkpoint re-read from disk on every
#                          run. --cache-lru 2 keeps two models resident instead.
#   --cpu-vae     REMOVED  VAE decode on CPU. Workaround for an old MPS fp16 VAE bug
#   --fp32-vae    REMOVED  that is fixed in the PyTorch 2.13 nightly you are running.
#   WATERMARK     0.0->0.8 0.0 disables the MPS allocator ceiling entirely, so instead
#                          of a clean OOM macOS silently swaps. 0.8 keeps work in RAM.
#
# Revert at any time by running start_comfy_mac.sh instead. Nothing was overwritten.

set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI}"
HOST="${COMFY_HOST:-0.0.0.0}"
PORT="${COMFY_PORT:-8188}"

cd "$COMFY_DIR" || { echo "[ERROR] Cannot enter $COMFY_DIR"; exit 1; }

if [[ -f "venv/bin/activate" ]]; then
  source "venv/bin/activate"
elif [[ -f ".venv/bin/activate" ]]; then
  source ".venv/bin/activate"
else
  echo "[ERROR] No venv found in $COMFY_DIR"; exit 1
fi

# Let unsupported MPS ops fall back to CPU instead of hard-failing.
export PYTORCH_ENABLE_MPS_FALLBACK=1

# Cap the MPS allocator at 80% of unified memory. Prevents swap thrash on 32 GB.
# Raise toward 0.9 if you never OOM; lower to 0.7 if you do.
export PYTORCH_MPS_HIGH_WATERMARK_RATIO="${PYTORCH_MPS_HIGH_WATERMARK_RATIO:-0.8}"
export PYTORCH_MPS_LOW_WATERMARK_RATIO="${PYTORCH_MPS_LOW_WATERMARK_RATIO:-0.5}"

export PIP_REQUIRE_VIRTUALENV=true
export PYTHONNOUSERSITE=1

PY="$(command -v python)"
echo "[INFO] python : $PY"
echo "[INFO] MPS fallback   : $PYTORCH_ENABLE_MPS_FALLBACK"
echo "[INFO] MPS watermark  : $PYTORCH_MPS_HIGH_WATERMARK_RATIO (was 0.0 = unlimited)"
echo "[INFO] profile        : M4 / 32 GB unified, normalvram + LRU cache"

LOG_DIR="$COMFY_DIR/user"
mkdir -p "$LOG_DIR"

exec "$PY" main.py \
  --enable-manager \
  --enable-manager-legacy-ui \
  --listen "$HOST" \
  --port "$PORT" \
  --preview-method none \
  --cache-lru 2 \
  --fp16-unet \
  --fp16-text-enc \
  2>&1 | tee -a "$LOG_DIR/comfyui_m4.log"
