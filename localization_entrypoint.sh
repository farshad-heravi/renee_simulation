#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
ros2 launch slam_toolbox localization_launch.py use_sim_time:=true robot_id:=robot \
    slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_localization.yaml
