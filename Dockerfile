FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CUDA_HOME=/usr/local/cuda \
    FP_DATA_ROOT=/workspace_data \
    FP_BOOTSTRAP=auto \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-lc"]

# Keep heavyweight Python packages, FoundationPose sources, and model weights out
# of the image. The entrypoint bootstraps those into the host-mounted cache.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    build-essential \
    git \
    gnupg2 \
    lsb-release \
    cmake \
    ninja-build \
    pkg-config \
    wget \
    libgl1 \
    libegl1 \
    libgles2 \
    libglvnd0 \
    libglx0 \
    libglu1-mesa \
    libglib2.0-0 \
    libgomp1 \
    libsm6 \
    libfontconfig1 \
    libusb-1.0-0 \
    libx11-6 \
    libxkbcommon-x11-0 \
    libxcb-xinerama0 \
    libxcursor1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    python3 \
    python3-dev \
    python3-opencv \
    python3-pip \
    python3-setuptools \
    python3-tk \
    python3-venv \
    python3-wheel \
    pybind11-dev \
    libeigen3-dev \
    tk \
    usbutils && \
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc \
      | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/ros2.list && \
    apt-get update && apt-get install -y --no-install-recommends \
      ros-${ROS_DISTRO}-ros-base \
      ros-${ROS_DISTRO}-cv-bridge \
      ros-${ROS_DISTRO}-geometry-msgs \
      ros-${ROS_DISTRO}-image-transport \
      ros-${ROS_DISTRO}-realsense2-camera \
      ros-${ROS_DISTRO}-realsense2-description \
      ros-${ROS_DISTRO}-ros2bag \
      ros-${ROS_DISTRO}-rosbag2-storage-default-plugins \
      ros-${ROS_DISTRO}-sensor-msgs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY . /workspace
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["app"]
