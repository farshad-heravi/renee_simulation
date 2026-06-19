#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
export ROBOT_MODEL=rbvogui_plus
ros2 launch robotnik_gazebo_ignition spawn_robot.launch.py robot_id:=robot robot:=rbvogui run_rviz:=true \
x:=7.0 \
y:=2.0 \
rviz_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/rviz_config.rviz \
low_performance_simulation:=true \
end_effector:=none
