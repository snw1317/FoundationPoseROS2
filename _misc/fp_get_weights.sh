#!/usr/bin/env bash
set -euo pipefail
WEIGHTS_ROOT="/workspace/FoundationPose/weights"
mkdir -p "${WEIGHTS_ROOT}"
if ! command -v gdown >/dev/null 2>&1; then python3 -m pip install gdown; fi
gdown --folder https://drive.google.com/drive/folders/1BEQLZH69UO5EOfah-K9bfI3JyP9Hf7wC -O "${WEIGHTS_ROOT}/2023-10-28-18-33-37" || true
gdown --folder https://drive.google.com/drive/folders/12Te_3TELLes5cim1d7F7EBTwUSe7iRBj -O "${WEIGHTS_ROOT}/2024-01-11-20-02-45" || true
echo "Weights download attempted. If Google Drive throttles, re-run this script."
