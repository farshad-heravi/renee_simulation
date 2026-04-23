#!/bin/bash
set -e
cd /fnh_pkgs
ros2 launch slam_toolbox online_async_launch.py  slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_online_async.yaml