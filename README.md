# FoundationPoseROS2: Multi-Object Pose Estimation and Tracking of Novel Objects in ROS2 with RealSense2

<p align="center">
  <img src="assets/demo.gif" alt="Demo Video" width="330">
  <img src="assets/demo_robot.gif" alt="Robot Demo Video" width="434"><br>
</p>

FoundationPoseROS2 is a ROS2-integrated system for 6D object pose estimation and tracking, based on the FoundationPose architecture. It uses RealSense2 with the Segment Anything Model 2 (SAM2) framework for end-to-end, model-based, real-time pose estimation and tracking of novel objects.

It is built on top of [FoundationPose](https://github.com/NVlabs/FoundationPose) and [live-pose](https://github.com/Kaivalya192/live-pose).

The main advantages to the previous repositories and [isaac_ros_foundationpose](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_pose_estimation/tree/main/isaac_ros_foundationpose):
1. ROS2-based real-time framework that works with 8GB GPU, unlike [isaac_ros_foundationpose](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_pose_estimation/tree/main/isaac_ros_foundationpose) which requires more than 64GB GPU.
2. SAM2-based automatic segmentation of the objects
3. Multi-object pose estimation and tracking
4. End-to-end assignment of object models with the segmented masks

Furthermore, it provides an interactive GUI for object model-to-mask assignment for end-to-end multi-pose estimation and tracking.

## Prerequisites

- **Ubuntu (20/22)**
- **ROS2 (Foxy/Humble)**
- **Minimum 8GB NVIDIA GPU**
- **CUDA 12.x**
- **Intel RealSense Camera**

## Docker (Recommended)

The Docker workflow mirrors the working conda setup while keeping the image reasonably small. The image includes CUDA 12.1 development tools, ROS2 Humble, RealSense ROS packages, and the system libraries needed for Tk/OpenCV/OpenGL windows. Large and frequently changing assets are kept out of image layers and are bootstrapped into a host-mounted cache at runtime.

### Host prerequisites

- Docker Engine + Docker Compose plugin
- NVIDIA Container Toolkit for GPU access in the `app` service
- X11 access for Tk/OpenCV windows
- Intel RealSense camera visible on the host
- RealSense udev rules installed on the host so the non-root container user can read the USB device

For WSL2, attach the RealSense USB device to the Linux distro first, then confirm it appears under `/dev/bus/usb` before starting the container.

### One-time host setup

```bash
# In repo root
mkdir -p .fp_cache rosbags
export LOCAL_UID=$(id -u)
export LOCAL_GID=$(id -g)

# Allow local docker containers to access your X server
xhost +local:docker
```

### Build

```bash
docker compose build
```

### Run with a RealSense camera

```bash
# Starts the RealSense ROS node and the FoundationPoseROS2 app.
docker compose --profile camera up realsense app
```

On first startup, the container bootstraps dependencies into `./.fp_cache`:
- Python virtual environment
- `FoundationPose` clone
- FoundationPose weights
- SAM / torch / pip caches
- compiled extension artifacts

The first `app` run can take a while because it installs the Python stack and compiles CUDA extensions. Subsequent startups reuse the same cache and skip the heavy setup.

### Run only the camera node

```bash
docker compose --profile camera up realsense
```

The `realsense` service intentionally skips the FoundationPose bootstrap, so it is quick to use for camera/topic checks.

### Run rosbag player (profile)

Put your rosbag under `./rosbags` or set `ROSBAG_DIR` and `ROSBAG_PATH`.

```bash
export ROSBAG_DIR=./rosbags
export ROSBAG_PATH=/rosbags/cube_demo_data_rosbag2
docker compose --profile rosbag up rosbag app
```

The `rosbag` service also skips the FoundationPose bootstrap. The `app` service performs the bootstrap when needed.

### Useful modes

```bash
# Force full re-bootstrap (for dependency updates)
FP_BOOTSTRAP=force docker compose up app

# Skip bootstrap and run directly
FP_BOOTSTRAP=skip docker compose up app

# Open a shell in the app environment
docker compose run --rm app shell
```

### Cache layout

All persistent data lives in `./.fp_cache` (host side), including:
- `venv/` (persistent Python environment)
- `src/FoundationPose/`
- `cache/` (pip/torch/ultralytics/huggingface cache)
- `bootstrap/bootstrap.version` (bootstrap sentinel)

Delete `./.fp_cache/bootstrap/bootstrap.version` or run with `FP_BOOTSTRAP=force` if you need to rebuild the cached Python/FoundationPose environment.

### Validate the container setup

```bash
# 1) Build succeeds without baking model weights into the image
docker compose build

# 2) Verify the RealSense node can see the camera
docker compose --profile camera up realsense

# 3) First app run performs bootstrap into .fp_cache
docker compose up app

# 4) Warm restart should skip heavy bootstrap steps
docker compose up app
```

If the camera is not detected, check that `lsusb` sees the RealSense device on the host, that the host udev rules are installed, and that `/dev/bus/usb` exists inside the `realsense` container.


## Dependencies

```bash
# Install ROS2 on Ubuntu
sudo apt install ros-<ROS_DISTRO>-desktop

# Install librealsense2
sudo apt install ros-<ROS_DISTRO>-librealsense2*

# Install debian realsense2 package
sudo apt install ros-<ROS_DISTRO>-realsense2-*

# Setup CUDA 12.x
sudo apt-get --purge remove 'nvidia-*'
sudo apt-get autoremove
sudo reboot

wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb
sudo dpkg -i cuda-keyring_1.0-1_all.deb
sudo apt-get update
sudo apt-get -y install cuda

# Install Miniconda
mkdir -p ~/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
rm ~/miniconda3/miniconda.sh

source ~/miniconda3/bin/activate
```

## Env setup: conda 

```bash
# Clone repository
git clone https://github.com/ammar-n-abbas/FoundationPoseROS2.git
```

```bash
# Create conda environment
conda create -n foundationpose_ros python=3.10 -y

# Activate conda environment
conda activate foundationpose_ros
```
> [!NOTE]
> Conda environment must be created with the correct Python version according to the ROS2 distribution to ensure compatibility. For example, use Python 3.8 for ROS Foxy and Python 3.10 for ROS Humble.

```bash
# Build extensions
cd FoundationPoseROS2 && export PATH=/usr/local/<YOUR_cuda-12.X_VERSION>/bin${PATH:+:${PATH}}~ && bash build_all_conda.sh
```
> [!IMPORTANT]
> In the `setup.py` file located at `/FoundationPose/bundlesdf/mycuda/`, the C++ flags should be updated from **C++14** to **C++17** for compatibility with newer Nvidia GPUs. It is located at lines 18 and 19 in the file's `nvcc_flags` and c_flags section.


## Run model-based demo

```bash
# Run camera node
source /opt/ros/<ROS_DISTRO>/setup.bash && ros2 launch realsense2_camera rs_launch.py enable_rgbd:=true enable_sync:=true align_depth.enable:=true enable_color:=true enable_depth:=true pointcloud.enable:=true
```

In a separate terminal

```bash
# Run foundationpose_ros_multi
conda activate foundationpose_ros && source /opt/ros/<ROS_DISTRO>/setup.bash && export PATH=/usr/local/<YOUR_cuda-12.X_VERSION>/bin${PATH:+:${PATH}}~ && python ./FoundationPoseROS2/foundationpose_ros_multi.py
```
> [!NOTE]
> Check the camera topics and edit accordingly in the Python file.

<div align="center">
  <video src="https://github.com/user-attachments/assets/4ef1f4cf-8900-451d-b006-47942b9f4606" width="200" />
</div>


## Run model-based demo through Rosbag2

### 1. Download the Recorded rosbag

First, download the recorded rosbag from the following link:

[Download Recorded rosbag](https://drive.google.com/drive/folders/17FRQog_fpqVxo_T85ItfpEa6fUo5fhZ7?usp=sharing)

### 2. Play the Recorded rosbag

Once you've downloaded the rosbag file, navigate to the directory where it's located, and play it back with the following command:

```bash
# Play the downloaded rosbag
source /opt/ros/<ROS_DISTRO>/setup.bash && ros2 bag play cube_demo_data_rosbag2
```

Replace `<path_to_your_rosbag_file>` with the path to the rosbag directory you downloaded.

### 3. Run FoundationPoseROS2

In a separate terminal, activate your conda environment, export the correct CUDA version path and run the FoundationPoseROS2 script to start object pose estimation and tracking:

```bash
# Activate the conda environment and run foundationpose_ros_multi
conda activate foundationpose_ros && source /opt/ros/<ROS_DISTRO>/setup.bash && export PATH=/usr/local/<YOUR_cuda-12.X_VERSION>/bin${PATH:+:${PATH}}~ && python ./FoundationPoseROS2/foundationpose_ros_multi.py
```

<p align="center">
  <a href="https://youtu.be/p-QBK7yJKWs">
    <img src="https://img.youtube.com/vi/p-QBK7yJKWs/0.jpg" alt="Demo data rosbag screen recording">
  </a>
</p>

[Demo data rosbag terminal log](https://github.com/ammar-n-abbas/FoundationPoseROS2/blob/main/_misc/demo_data_terminal_log.txt)

## Run on novel objects

Add the mesh file in .obj or .stl format to the folder:
```bash
"./FoundationPoseROS2/demo_data/object_name/<OBJECT_MESH>.obj"
```

```bash
# Run
conda activate foundationpose_ros && source /opt/ros/<ROS_DISTRO>/setup.bash && export PATH=/usr/local/<YOUR_cuda-12.X_VERSION>/bin${PATH:+:${PATH}}~ && python ./FoundationPoseROS2/foundationpose_ros_multi.py
```

> [!NOTE]
> Check the camera topics and edit accordingly in the Python file.


## Features

- **Object Selection GUI**: Choose and reorder object files (.obj, .stl) using a simple Tkinter GUI.
- **Segmentation and Tracking**: SAM2 is used for object segmentation in real-time colour and depth images from a camera.
- **Pose Estimation**: Calculates and publishes the pose of detected objects based on camera images.
- **3D Visualization**: Visualize the objects’ pose with bounding boxes and axes.


## Pipeline

<p align="center">
    <img src="assets/pipeline.svg" alt="Algorithm Pipeline" style="width: 30%; height: auto;"/>
</p>

[![Star History Chart](https://api.star-history.com/svg?repos=ammar-n-abbas/FoundationPoseROS2&type=Date)](https://star-history.com/#ammar-n-abbas/FoundationPoseROS2&Date)

## Acknowledgement
This project has emanated from research conducted with the financial support of the EU Commission Recovery and Resilience Facility under the Science Foundation Ireland Future Digital Challenge Grant Number 22/NCF/FD/10929.
