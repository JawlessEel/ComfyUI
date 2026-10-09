#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="/Volumes/MacMoneyMakerSSD/Ai_apps/ComfyUI"
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

echo "[INFO] Using Python:"
"$PY" -c 'import sys; print(sys.executable)'
echo "[INFO] sys.prefix:"
"$PY" -c 'import sys; print(sys.prefix)'
echo "[INFO] Using pip:"
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
