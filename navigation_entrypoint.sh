#!/bin/bash
set -e
cd /fnh_pkgs

source install/setup.bash
ros2 launch renee_rbvogui_navigation navigation.launch.py use_sim:=true robot_id:=robot