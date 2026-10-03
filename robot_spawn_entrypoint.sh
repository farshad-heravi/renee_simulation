#!/bin/bash
set -e
cd /renee
source install/setup.bash
export ROBOT_MODEL=rbvogui_plus
source $RENEE_SRC_PATH/world_poses.sh
ros2 launch robotnik_gazebo_ignition spawn_robot.launch.py robot_id:=robot robot:=rbvogui run_rviz:=true \
x:=$ROBOT_SPAWN_X \
y:=$ROBOT_SPAWN_Y \
rviz_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/rviz_config.rviz \
low_performance_simulation:=true \
end_effector:=none
