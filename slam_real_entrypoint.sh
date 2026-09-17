#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
ros2 run rviz2 rviz2 -d $RENEE_SRC_PATH/configs/slam_real.rviz &
ros2 launch slam_toolbox online_async_launch.py use_sim_time:=false slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_online_async_real.yaml
