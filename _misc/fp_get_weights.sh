#!/usr/bin/env bash
set -euo pipefail

declare -r WEIGHTS_ROOT="/workspace/FoundationPose/weights"
declare -ra WEIGHT_FOLDERS=(
  "2023-10-28-18-33-37 https://drive.google.com/drive/folders/1BEQLZH69UO5EOfah-K9bfI3JyP9Hf7wC"
  "2024-01-11-20-02-45 https://drive.google.com/drive/folders/12Te_3TELLes5cim1d7F7EBTwUSe7iRBj"
)

mkdir -p "${WEIGHTS_ROOT}"

if ! command -v gdown >/dev/null 2>&1; then
  echo "[weights] Installing gdown (not found in PATH)"
  python3 -m pip install --no-cache-dir gdown
fi

for entry in "${WEIGHT_FOLDERS[@]}"; do
  read -r folder url <<<"${entry}"
  target_dir="${WEIGHTS_ROOT}/${folder}"

  if [ -d "${target_dir}" ] && find "${target_dir}" -mindepth 1 -print -quit >/dev/null 2>&1; then
    echo "[weights] '${folder}' already present; skipping download"
    continue
  fi

  echo "[weights] Downloading '${folder}' from Google Drive"
  mkdir -p "${target_dir}"
  if ! gdown --quiet --folder "${url}" -O "${target_dir}"; then
    echo "[weights] Warning: download for '${folder}' did not complete. Re-run fp_get_weights.sh if needed." >&2
  fi
done

echo "[weights] Download step finished. Existing folders were left untouched."
