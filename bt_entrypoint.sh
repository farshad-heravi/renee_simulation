#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
ros2 launch renee_behavior_tree renee_bt.launch.py
