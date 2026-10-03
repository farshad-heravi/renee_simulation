#!/bin/bash
set -e
cd /renee
source install/setup.bash
ros2 launch renee_behavior_tree renee_bt.launch.py
