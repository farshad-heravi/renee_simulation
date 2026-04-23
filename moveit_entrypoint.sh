#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
ros2 launch renee_rbvogui_plus_moveit_config start_moveit.launch.py