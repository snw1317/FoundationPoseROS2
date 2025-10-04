# CUDA 12.1 + cuDNN on Ubuntu 22.04 (matches torch==2.1.0+cu121)
FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
    QT_X11_NO_MITSHM=1 \
    LANG=C.UTF-8 \
    PIP_DEFAULT_TIMEOUT=180 \
    ROS_DISTRO=humble

# Base deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales tzdata ca-certificates curl wget git ssh sudo \
    build-essential cmake ninja-build pkg-config \
    python3 python3-pip python3-dev python3-tk \
    # X11/GUI + OpenGL/EGL (PySide6/Tk/OpenGL)
    libgl1 libglvnd0 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libx11-6 libxcomposite1 libxrandr2 libxi6 libxtst6 \
    libxkbcommon-x11-0 libfontconfig1 libxcb-cursor0 \
    # USB for RealSense
    libusb-1.0-0-dev udev \
    # C++ deps
    libeigen3-dev pybind11-dev \
    # ROS2 apt setup
    gnupg lsb-release \
 && rm -rf /var/lib/apt/lists/*

# ROS 2 Humble desktop + msgs + cv_bridge + realsense2_camera
RUN install -d /usr/share/keyrings \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
      | tee /etc/apt/sources.list.d/ros2.list \
 && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg \
 && apt-get update && apt-get install -y --no-install-recommends \
      ros-humble-desktop \
      ros-humble-cv-bridge \
      ros-humble-image-transport \
      ros-humble-message-filters \
      ros-humble-sensor-msgs \
      ros-humble-geometry-msgs \
      ros-humble-realsense2-camera \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-lc"]
RUN echo "source /opt/ros/humble/setup.bash" >> /etc/bash.bashrc

# Workspace
WORKDIR /workspace
COPY requirements.txt /workspace/requirements.txt
COPY . /workspace/FoundationPoseROS2

# Torch/cu121 + pytorch3d (pin setuptools/wheel; build pytorch3d w/o isolation)
RUN python3 -m pip install --upgrade pip \
 && python3 -m pip install "setuptools==69.5.1" "wheel==0.41.2" "packaging<24" \
 && python3 -m pip install --extra-index-url https://download.pytorch.org/whl/cu121 \
      torch==2.1.0+cu121 torchvision==0.16.0+cu121 torchaudio==2.1.0 \
 && python3 -m pip install --no-build-isolation --no-cache-dir \
      "git+https://github.com/facebookresearch/pytorch3d.git@stable"

# Install requirements (skip cv_bridge — provided by apt)
RUN awk 'BEGIN{IGNORECASE=1} \
  /^\s*#/ {next} \
  /^\s*$/ {next} \
  /^cv_bridge\s*$/ {next} \
  /^setuptools(==.*)?\s*$/ {next} \
  /^opencv_python(headless)?(==.*)?\s*$/ {next} \
  {print}' /workspace/requirements.txt > /workspace/requirements_sanitized.txt \
 && python3 -m pip install --no-cache-dir -r /workspace/requirements_sanitized.txt

# FoundationPose sources + native pieces
RUN git clone --depth 1 https://github.com/NVlabs/FoundationPose.git /workspace/FoundationPose

# nvdiffrast (install from NVLabs repo)
RUN python3 -m pip install --no-cache-dir "git+https://github.com/NVlabs/nvdiffrast.git"

# mycpp (C++ lib)
RUN cd /workspace/FoundationPose/mycpp && \
    rm -rf build && mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j"$(nproc)"

# bundlesdf/mycuda (CUDA extension)
# Force explicit arch list so PyTorch's extension builder doesn't infer from GPU (none during build)
# Default to Pascal (GTX 1060 is compute 6.1). Override with --build-arg TORCH_CUDA_ARCH_LIST="X.Y;..." if needed.
ARG TORCH_CUDA_ARCH_LIST="6.1"
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}
RUN cd /workspace/FoundationPose/bundlesdf/mycuda && \
    sed -i "s/-std=c++14/-std=c++17/g" setup.py || true && \
    rm -rf build *egg* *.so && \
    CXXFLAGS="-std=c++17" python3 -m pip install --no-cache-dir -e .

# Weights helper
COPY _misc/fp_get_weights.sh /usr/local/bin/fp_get_weights.sh
COPY _misc/run_foundationpose.sh /usr/local/bin/run_foundationpose.sh
RUN chmod +x /usr/local/bin/fp_get_weights.sh /usr/local/bin/run_foundationpose.sh

# Optional: prefetch weights during build with --build-arg FP_FETCH_WEIGHTS=1
ARG FP_FETCH_WEIGHTS=0
RUN if [ "${FP_FETCH_WEIGHTS}" = "1" ]; then \
      echo "Prefetching FoundationPose weights at build time" && \
      fp_get_weights.sh || true; \
    else \
      echo "Skipping weight prefetch (FP_FETCH_WEIGHTS=${FP_FETCH_WEIGHTS})"; \
    fi

# Let Python find FoundationPose modules (nvdiffrast is installed site-wide)
# Keep it simple to avoid undefined-var lint warnings during build
ENV PYTHONPATH=/workspace/FoundationPose

# Provide a symlink so scripts using relative './FoundationPose' work from repo root
RUN ln -s /workspace/FoundationPose /workspace/FoundationPoseROS2/FoundationPose || true

# Default to auto-start camera + app (override with --entrypoint for a shell)
ENTRYPOINT ["/usr/local/bin/run_foundationpose.sh"]
