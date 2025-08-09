# CUDA 12.1 + cuDNN on Ubuntu 22.04 (matches torch==2.1.0+cu121)
FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
    QT_X11_NO_MITSHM=1 \
    LANG=C.UTF-8

# Base deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales tzdata ca-certificates curl wget git ssh sudo \
    build-essential cmake ninja-build pkg-config \
    python3 python3-pip python3-dev python3-tk \
    # X11/GUI + OpenGL/EGL
    libgl1 libglvnd0 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libx11-6 libxcomposite1 libxrandr2 libxi6 libxtst6 \
    libxkbcommon-x11-0 libfontconfig1 \
    # USB for RealSense
    libusb-1.0-0-dev udev \
    # C++ deps
    libeigen3-dev pybind11-dev \
    # ROS2 apt setup
    gnupg lsb-release \
 && rm -rf /var/lib/apt/lists/*

# ROS 2 Humble desktop + msgs + cv_bridge + realsense2_camera
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
      | tee /etc/apt/sources.list.d/ros2.list \
 && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc \
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

# Torch/cu121 + pytorch3d
RUN python3 -m pip install --upgrade pip wheel setuptools \
 && python3 -m pip install --extra-index-url https://download.pytorch.org/whl/cu121 \
      torch==2.1.0+cu121 torchvision==0.16.0+cu121 torchaudio==2.1.0 \
 && python3 -m pip install "git+https://github.com/facebookresearch/pytorch3d.git@stable"

# Install requirements (skip cv_bridge — provided by apt)
RUN grep -vE '^\s*cv_bridge\s*$' /workspace/requirements.txt > /workspace/requirements_noros.txt \
 && python3 -m pip install -r /workspace/requirements_noros.txt

# FoundationPose sources + native pieces
RUN git clone https://github.com/NVlabs/FoundationPose.git /workspace/FoundationPose

# nvdiffrast
RUN cd /workspace/FoundationPose/nvdiffrast && python3 -m pip install .

# mycpp (C++ lib)
RUN cd /workspace/FoundationPose/mycpp && \
    rm -rf build && mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j"$(nproc)"

# bundlesdf/mycuda (CUDA extension)
# If you see C++14 build errors, edit setup.py to C++17 and rerun the install.
RUN cd /workspace/FoundationPose/bundlesdf/mycuda && \
    rm -rf build *egg* *.so && \
    python3 -m pip install -e .

# Weights helper
COPY _misc/fp_get_weights.sh /usr/local/bin/fp_get_weights.sh
RUN chmod +x /usr/local/bin/fp_get_weights.sh

# Let Python find FoundationPose modules
ENV PYTHONPATH=/workspace/FoundationPose:/workspace/FoundationPose/nvdiffrast:${PYTHONPATH}

ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["source /opt/ros/humble/setup.bash && bash"]
