#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash

### SPAWN THE WORLD
export GZ_SIM_RESOURCE_PATH=$RENEE_SRC_PATH/campetella_sim/models:$GZ_SIM_RESOURCE_PATH
echo $GZ_SIM_RESOURCE_PATH
ros2 launch robotnik_gazebo_ignition spawn_world.launch.py \
world_path:=$RENEE_SRC_PATH/../../install/renee_rbvogui_navigation/share/renee_rbvogui_navigation/world/scanning.sdf &

# Publish static TF: world -> robot_map; x y z should match with those when spawning the robot in spawn docker service
ros2 run tf2_ros static_transform_publisher \
  --x 3.0 --y 3.0 --z 0.0 \
  --roll 0 --pitch 0 --yaw 0 \
  --frame-id world \
  --child-frame-id robot_map &

### SPAWN THE CAMPETELLA ROBOT
# Piece selection, collision flags and mode come from campetella_config.yaml.
wait_for_ros --timeout 60 topic /clock --msg
ros2 launch campetella_sim spawn_campetella.launch.py \
x:=1.0 y:=0.0 z:=0.8 &

### SPAWN THE MOBILE MANIPULATOR
export ROBOT_MODEL=rbvogui_plus
# Wait for the Gazebo world to actually be running (clock publishing)
wait_for_ros --timeout 90 topic /clock --msg && ros2 launch robotnik_gazebo_ignition spawn_robot.launch.py robot_id:=robot robot:=rbvogui \
wrist_camera:=realsense_d435i \
run_rviz:=true \
x:=2.5 \
y:=2.5 \
rviz_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/rviz_config.rviz \
low_performance_simulation:=true \
end_effector:=none \
use_tool_changer:=true &

# Spawn all 4 detachable tools (RSPs + Gazebo models + bridges + tool_manager),
# once the robot's arm controller is actually active
# wait_for_ros --timeout 90 controller /robot/controller_manager joint_trajectory_controller --state active \
#   && ros2 launch renee_rbvogui_plus_moveit_config spawn_tools.launch.py &

# Do not start localization/Nav2 until the robot has published its odometry
# transform.  Otherwise Nav2's costmaps start before slam_toolbox can create
# robot_map -> robot_odom, leaving robot_map and robot_base_link disconnected.
wait_for_ros --timeout 120 tf robot_odom robot_base_footprint

# LOAD MAP and LOCALIZATION.  slam_toolbox publishes robot_map -> robot_odom.
ros2 launch slam_toolbox localization_launch.py use_sim_time:=true  \
    slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_localization_scanning.yaml &

# Start Nav2 only after the full map-to-odometry link is available.
wait_for_ros --timeout 120 tf robot_map robot_odom

# RUN NAVIGATION
ros2 launch renee_rbvogui_navigation navigation.launch.py use_sim:=true robot_id:=robot
