#!/usr/bin/env bash
set -euo pipefail

declare -a WEIGHTS_ROOT_CANDIDATES=()

# Highest priority: user override via environment variable
if [ -n "${FP_WEIGHTS_ROOT:-}" ]; then
  WEIGHTS_ROOT_CANDIDATES+=("${FP_WEIGHTS_ROOT}")
fi

# Default locations inside the container image
WEIGHTS_ROOT_CANDIDATES+=(
  "/workspace/FoundationPose/weights"
  "/workspace/FoundationPoseROS2/FoundationPose/weights"
)

# When executed from a checked-out repo (e.g., host tooling), prefer a local path
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root_guess="$(cd "${script_dir}/.." && pwd)"
  if [ -d "${repo_root_guess}" ]; then
    WEIGHTS_ROOT_CANDIDATES+=("${repo_root_guess}/FoundationPose/weights")
  fi
fi

WEIGHTS_ROOT=""
for candidate in "${WEIGHTS_ROOT_CANDIDATES[@]}"; do
  [ -z "${candidate}" ] && continue
  if mkdir -p "${candidate}" >/dev/null 2>&1; then
    WEIGHTS_ROOT="${candidate}"
    break
  fi
done

if [ -z "${WEIGHTS_ROOT}" ]; then
  echo "[weights] Error: unable to determine a writable weights directory." >&2
  exit 1
fi

# Maintain the legacy path expected by FoundationPose if we selected an alternative root
DEFAULT_ROOT="/workspace/FoundationPose/weights"
if [ "${WEIGHTS_ROOT}" != "${DEFAULT_ROOT}" ]; then
  if [ ! -e "${DEFAULT_ROOT}" ]; then
    mkdir -p "$(dirname "${DEFAULT_ROOT}")"
    ln -s "${WEIGHTS_ROOT}" "${DEFAULT_ROOT}" 2>/dev/null || true
  fi
fi

echo "[weights] Using weights directory: ${WEIGHTS_ROOT}"
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
