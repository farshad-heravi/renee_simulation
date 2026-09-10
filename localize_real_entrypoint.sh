#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
# Real-robot localization against the map built by slam-real, analogous to
# how slam_real_entrypoint.sh relates to slam_entrypoint.sh: separate from
# localization_entrypoint.sh (Gazebo-sim `localization` service, untouched)
# since the data source, params file, and clock (use_sim_time) all differ.
ros2 run rviz2 rviz2 -d $RENEE_SRC_PATH/configs/slam_real.rviz &
ros2 launch slam_toolbox localization_launch.py use_sim_time:=false \
    slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_localization_real.yaml
