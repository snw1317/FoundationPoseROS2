#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-app}"
if [[ $# -gt 0 ]]; then
  shift
fi

: "${ROS_DISTRO:=humble}"
: "${FP_DATA_ROOT:=/workspace_data}"
: "${FP_BOOTSTRAP:=auto}"

WORKSPACE_DIR="/workspace"
BOOTSTRAP_VERSION="2026-05-11-v2"
BOOTSTRAP_FILE="${FP_DATA_ROOT}/bootstrap/bootstrap.version"
BOOTSTRAP_LOCK_DIR="${FP_DATA_ROOT}/bootstrap.lock"
VENV_DIR="${FP_DATA_ROOT}/venv"
FP_SRC_ROOT="${FP_DATA_ROOT}/src"
FP_REPO_DIR="${FP_SRC_ROOT}/FoundationPose"
NVDIFFRAST_DIR="${FP_REPO_DIR}/nvdiffrast"

log() {
  printf '[entrypoint] %s\n' "$*"
}

wait_for_lock() {
  local i=0
  while [[ -d "${BOOTSTRAP_LOCK_DIR}" ]]; do
    i=$((i+1))
    if (( i > 600 )); then
      log "bootstrap lock timeout after 10 minutes"
      exit 1
    fi
    sleep 1
  done
}

activate_env() {
  if [[ -f "${VENV_DIR}/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "${VENV_DIR}/bin/activate"
  fi

  # ROS setup scripts assume some vars may be unset, which conflicts with nounset.
  set +u
  source "/opt/ros/${ROS_DISTRO}/setup.bash"
  set -u

  export HOME="${FP_DATA_ROOT}"
  export ROS_HOME="${ROS_HOME:-${HOME}/.ros}"
  mkdir -p "${ROS_HOME}"

  export PATH="/usr/local/cuda/bin:${PATH}"
  export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

  export PIP_CACHE_DIR="${FP_DATA_ROOT}/cache/pip"
  export XDG_CACHE_HOME="${FP_DATA_ROOT}/cache/xdg"
  export TORCH_HOME="${FP_DATA_ROOT}/cache/torch"
  export HF_HOME="${FP_DATA_ROOT}/cache/hf"
  export ULTRALYTICS_HOME="${FP_DATA_ROOT}/cache/ultralytics"

  mkdir -p \
    "${FP_DATA_ROOT}/cache/pip" \
    "${FP_DATA_ROOT}/cache/xdg" \
    "${FP_DATA_ROOT}/cache/torch" \
    "${FP_DATA_ROOT}/cache/hf" \
    "${FP_DATA_ROOT}/cache/ultralytics"

  if [[ -d "${FP_REPO_DIR}" && ! -e "${WORKSPACE_DIR}/FoundationPose" ]]; then
    ln -s "${FP_REPO_DIR}" "${WORKSPACE_DIR}/FoundationPose"
  fi
}

install_python_stack() {
  log "Installing Python packages into persistent venv"
  if [[ ! -d "${VENV_DIR}" ]]; then
    python3 -m venv "${VENV_DIR}"
  fi

  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"

  export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
  export PATH="${CUDA_HOME}/bin:${PATH}"

  pip install --upgrade pip setuptools wheel ninja cmake gdown
  pip install torch==2.1.0+cu121 torchvision==0.16.0+cu121 torchaudio==2.1.0+cu121 --index-url https://download.pytorch.org/whl/cu121
  pip install "git+https://github.com/facebookresearch/pytorch3d.git@stable"
  grep -v '^cv_bridge$' "${WORKSPACE_DIR}/requirements.txt" > "${FP_DATA_ROOT}/bootstrap/requirements.pip.txt"
  pip install -r "${FP_DATA_ROOT}/bootstrap/requirements.pip.txt"
}

bootstrap_foundationpose() {
  mkdir -p "${FP_SRC_ROOT}"

  if [[ ! -d "${FP_REPO_DIR}/.git" ]]; then
    log "Cloning FoundationPose"
    git clone https://github.com/NVlabs/FoundationPose.git "${FP_REPO_DIR}"
  else
    log "FoundationPose clone already exists"
  fi

  if [[ ! -d "${NVDIFFRAST_DIR}/.git" ]]; then
    log "Cloning nvdiffrast"
    git clone https://github.com/NVlabs/nvdiffrast "${NVDIFFRAST_DIR}"
  fi

  mkdir -p "${FP_REPO_DIR}/weights/2023-10-28-18-33-37"
  mkdir -p "${FP_REPO_DIR}/weights/2024-01-11-20-02-45"

  if [[ -z "$(ls -A "${FP_REPO_DIR}/weights/2023-10-28-18-33-37" 2>/dev/null || true)" ]]; then
    log "Downloading FoundationPose weights set 2023-10-28-18-33-37"
    gdown --folder https://drive.google.com/drive/folders/1BEQLZH69UO5EOfah-K9bfI3JyP9Hf7wC -O "${FP_REPO_DIR}/weights/2023-10-28-18-33-37"
  fi

  if [[ -z "$(ls -A "${FP_REPO_DIR}/weights/2024-01-11-20-02-45" 2>/dev/null || true)" ]]; then
    log "Downloading FoundationPose weights set 2024-01-11-20-02-45"
    gdown --folder https://drive.google.com/drive/folders/12Te_3TELLes5cim1d7F7EBTwUSe7iRBj -O "${FP_REPO_DIR}/weights/2024-01-11-20-02-45"
  fi

  log "Building mycpp"
  cmake -S "${FP_REPO_DIR}/mycpp" -B "${FP_REPO_DIR}/mycpp/build"
  cmake --build "${FP_REPO_DIR}/mycpp/build" -j"$(nproc)"

  if [[ -f "${FP_REPO_DIR}/bundlesdf/mycuda/setup.py" ]]; then
    sed -i 's/-std=c++14/-std=c++17/g' "${FP_REPO_DIR}/bundlesdf/mycuda/setup.py"
  fi

  log "Installing nvdiffrast + mycuda extension"
  pip install -e "${NVDIFFRAST_DIR}"
  pip install -e "${FP_REPO_DIR}/bundlesdf/mycuda"

  ln -sfn "${FP_REPO_DIR}" "${WORKSPACE_DIR}/FoundationPose"
}

mode_needs_foundationpose_bootstrap() {
  case "${MODE}" in
    app|shell)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_bootstrap_if_needed() {
  mkdir -p "${FP_DATA_ROOT}/bootstrap"

  case "${FP_BOOTSTRAP}" in
    skip)
      log "Skipping bootstrap because FP_BOOTSTRAP=skip"
      return
      ;;
    force)
      log "Forcing bootstrap"
      ;;
    auto)
      if [[ -f "${BOOTSTRAP_FILE}" ]] && grep -qx "${BOOTSTRAP_VERSION}" "${BOOTSTRAP_FILE}"; then
        log "Bootstrap already complete (${BOOTSTRAP_VERSION})"
        return
      fi
      ;;
    *)
      log "Unsupported FP_BOOTSTRAP value: ${FP_BOOTSTRAP}"
      exit 1
      ;;
  esac

  wait_for_lock
  mkdir "${BOOTSTRAP_LOCK_DIR}"
  trap 'rmdir "${BOOTSTRAP_LOCK_DIR}" 2>/dev/null || true' EXIT

  install_python_stack
  bootstrap_foundationpose

  printf '%s\n' "${BOOTSTRAP_VERSION}" > "${BOOTSTRAP_FILE}"
  log "Bootstrap completed"
}

run_mode() {
  cd "${WORKSPACE_DIR}"

  case "${MODE}" in
    app)
      log "Launching FoundationPoseROS2 app"
      exec python3 "${WORKSPACE_DIR}/foundationpose_ros_multi.py" "$@"
      ;;
    realsense)
      log "Launching RealSense camera node"
      exec ros2 launch realsense2_camera rs_launch.py enable_rgbd:=true enable_sync:=true align_depth.enable:=true enable_color:=true enable_depth:=true pointcloud.enable:=true "$@"
      ;;
    rosbag)
      local bag_path="${ROSBAG_PATH:-/rosbags/cube_demo_data_rosbag2}"
      if [[ "${bag_path}" == *.db3 && -f "${bag_path}" ]]; then
        bag_path="$(dirname "${bag_path}")"
      fi
      log "Playing rosbag: ${bag_path}"
      exec ros2 bag play "${bag_path}" "$@"
      ;;
    shell)
      log "Starting interactive shell"
      exec bash "$@"
      ;;
    *)
      log "Unknown mode: ${MODE}"
      log "Valid modes: app | realsense | rosbag | shell"
      exit 1
      ;;
  esac
}

if mode_needs_foundationpose_bootstrap; then
  run_bootstrap_if_needed
else
  log "Skipping FoundationPose bootstrap for ${MODE} mode"
fi
activate_env
run_mode "$@"
