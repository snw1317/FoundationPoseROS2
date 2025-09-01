#!/usr/bin/env bash
set -euo pipefail

# Configurables via env:
#  - FP_AUTO_WEIGHTS=1 to auto-download weights at start (default 1)
#  - FP_CAMERA_WAIT=5 seconds to wait before app start (default 5)
#  - FP_MODE=camera|rosbag to select source (default camera)
#  - FP_ROSBAG_PATH=/data/rosbag.db3 or folder when FP_MODE=rosbag
#  - FP_ROSBAG_ARGS='--loop' extra args for rosbag play

export QT_X11_NO_MITSHM="${QT_X11_NO_MITSHM:-1}"
export ROS_DISTRO="${ROS_DISTRO:-humble}"

# Source ROS 2 without nounset to avoid unbound vars (e.g., AMENT_TRACE_SETUP_FILES)
if [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
  set +u
  # Ensure the variable exists to satisfy scripts that read it
  : "${AMENT_TRACE_SETUP_FILES:=}"
  source "/opt/ros/${ROS_DISTRO}/setup.bash"
  set -u
fi

# Attempt to fetch weights unless disabled
if [ "${FP_AUTO_WEIGHTS:-1}" = "1" ]; then
  if command -v fp_get_weights.sh >/dev/null 2>&1; then
    echo "[entrypoint] Fetching FoundationPose weights (may be throttled by Google Drive)"
    fp_get_weights.sh || true
  fi
fi

MODE="${FP_MODE:-camera}"
PRODUCER_PID=""
cleanup() {
  if [ -n "${PRODUCER_PID}" ]; then
    echo "[entrypoint] Stopping background producer (PID ${PRODUCER_PID})"
    kill "${PRODUCER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [ "$MODE" = "rosbag" ]; then
  if [ -z "${FP_ROSBAG_PATH:-}" ]; then
    echo "[entrypoint] FP_MODE=rosbag but FP_ROSBAG_PATH not set" >&2
    exit 2
  fi
  if [ ! -e "$FP_ROSBAG_PATH" ]; then
    echo "[entrypoint] FP_ROSBAG_PATH '$FP_ROSBAG_PATH' does not exist in container" >&2
    exit 2
  fi
  echo "[entrypoint] Playing rosbag: $FP_ROSBAG_PATH ${FP_ROSBAG_ARGS:-}"
  # Support folder or .db3 file path
  if [ -d "$FP_ROSBAG_PATH" ]; then
    ros2 bag play "$FP_ROSBAG_PATH" ${FP_ROSBAG_ARGS:-} &
  else
    # For a direct .db3 file, play its parent folder
    ros2 bag play "$(dirname "$FP_ROSBAG_PATH")" ${FP_ROSBAG_ARGS:-} &
  fi
  PRODUCER_PID=$!
else
  # Launch RealSense camera driver in background
  echo "[entrypoint] Starting RealSense camera node"
  ros2 launch realsense2_camera rs_launch.py \
    enable_rgbd:=true enable_sync:=true align_depth.enable:=true \
    enable_color:=true enable_depth:=true pointcloud.enable:=true &
  PRODUCER_PID=$!
fi

sleep "${FP_CAMERA_WAIT:-5}"

cd /workspace/FoundationPoseROS2
export PYTHONPATH="/workspace/FoundationPose:/workspace/FoundationPose/nvdiffrast:${PYTHONPATH:-}"

echo "[entrypoint] Launching FoundationPoseROS2 application"
exec python3 foundationpose_ros_multi.py
