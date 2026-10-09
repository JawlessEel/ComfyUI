cd /Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI

cp start_comfy_mac.sh "start_comfy_mac.sh.bak.$(date +%Y%m%d-%H%M%S)"

cat > start_comfy_mac.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI"
cd "$COMFY_DIR"

if [[ -f "venv/bin/activate" ]]; then
  source "venv/bin/activate"
elif [[ -f ".venv/bin/activate" ]]; then
  source ".venv/bin/activate"
else
  echo "[ERROR] No venv or .venv found in $COMFY_DIR"
  exit 1
fi

# Apple Silicon / PyTorch MPS settings.
# 0.0 disables the hard MPS memory cap. It can prevent MPS OOM errors,
# but close LM Studio, browsers, Photoshop, etc. before big runs.
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO="${PYTORCH_MPS_HIGH_WATERMARK_RATIO:-0.0}"

echo "[INFO] ComfyUI dir: $COMFY_DIR"
echo "[INFO] Python: $(which python)"
echo "[INFO] MPS fallback: $PYTORCH_ENABLE_MPS_FALLBACK"
echo "[INFO] MPS high watermark: $PYTORCH_MPS_HIGH_WATERMARK_RATIO"

exec python main.py \
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
SH

chmod +x start_comfy_mac.sh

./start_comfy_mac.sh