#!/usr/bin/env bash
set -euo pipefail

# Root directory for storing weights. Can be overridden by setting WEIGHTS_ROOT
# in the environment; defaults to the location expected by FoundationPose.
WEIGHTS_ROOT="${WEIGHTS_ROOT:-/workspace/FoundationPose/weights}"
mkdir -p "${WEIGHTS_ROOT}"

# Ensure gdown is available for downloading from Google Drive.
if ! command -v gdown >/dev/null 2>&1; then
  python3 -m pip install gdown
fi

download_if_missing() {
  local url="$1"
  local dest="$2"
  local marker="${dest}/model_best.pth"
  if [ -f "${marker}" ]; then
    echo "Found existing weights at ${marker}, skipping download"
  else
    gdown --folder "${url}" -O "${dest}" || true
  fi
}

download_if_missing \
  "https://drive.google.com/drive/folders/1BEQLZH69UO5EOfah-K9bfI3JyP9Hf7wC" \
  "${WEIGHTS_ROOT}/2023-10-28-18-33-37"
download_if_missing \
  "https://drive.google.com/drive/folders/12Te_3TELLes5cim1d7F7EBTwUSe7iRBj" \
  "${WEIGHTS_ROOT}/2024-01-11-20-02-45"

echo "Weights download attempted. If Google Drive throttles, re-run this script."
