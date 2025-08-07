# CUDA 12.x base image on Ubuntu 22.04
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies and set up locale
RUN apt-get update && apt-get install -y \
    locales curl gnupg2 lsb-release \
    git wget build-essential cmake \
    python3-pip python3-opencv python3-tk \
    libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* && \
    locale-gen en_US en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8

# Add ROS 2 Humble sources
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | apt-key add - && \
    echo "deb [arch=amd64] http://packages.ros.org/ros2/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros2.list

# Install ROS 2 Humble and related packages
RUN apt-get update && apt-get install -y \
    ros-humble-ros-base \
    ros-humble-cv-bridge \
    ros-humble-sensor-msgs \
    ros-humble-geometry-msgs \
    ros-humble-nav-msgs \
    ros-humble-std-msgs \
    ros-humble-visualization-msgs \
    ros-humble-message-filters \
    ros-humble-tf-transformations \
    ros-humble-rclpy \
    python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
WORKDIR /app
COPY . /app

# Ensure build script is executable and run it
RUN chmod +x build_all_conda.sh && sed -i 's/\r$//' build_all_conda.sh && ./build_all_conda.sh

# Expose FoundationPose to Python
ARG PYTHONPATH
ENV PYTHONPATH=/app/FoundationPose:${PYTHONPATH}

# Default entrypoint
ENTRYPOINT ["/bin/bash", "-c", "source /opt/ros/humble/setup.bash && python3 foundationpose_ros_multi.py"]

