#!/bin/bash
set -e
cd /renee
source install/setup.bash
ros2 launch renee_rbvogui_plus_moveit_config start_moveit.launch.py