#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
# Separate from slam_entrypoint.sh (shared with the Gazebo-sim `slam` service,
# which already gets an RViz window from robot_spawn_entrypoint.sh with
# Fixed Frame: world — a frame that doesn't exist here, since real-robot
# mapping has no Gazebo world TF). slam_real.rviz is a copy of
# renee_rbvogui_navigation/config/rviz_config.rviz with Fixed Frame changed
# to robot_map, the frame slam_toolbox actually publishes.
ros2 run rviz2 rviz2 -d $RENEE_SRC_PATH/configs/slam_real.rviz &
# online_async_launch.py defaults use_sim_time to true (Gazebo-oriented
# default). There's no /clock publisher anywhere in the real-robot pipeline
# (no Gazebo), so slam_toolbox would be waiting on a sim clock that never
# arrives while everything else (rviz2, the bridged sensor data) runs on
# real wall-clock time — the resulting clock-domain mismatch is what caused
# the persistent "extrapolation into the future" TF errors in rviz.
ros2 launch slam_toolbox online_async_launch.py use_sim_time:=false slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_online_async.yaml
