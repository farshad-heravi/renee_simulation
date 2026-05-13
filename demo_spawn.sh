#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash

### SPAWN THE WORLD
export GZ_SIM_RESOURCE_PATH=$RENEE_SRC_PATH/campetella_sim/campetella_sim/models:$GZ_SIM_RESOURCE_PATH
echo $GZ_SIM_RESOURCE_PATH
ros2 launch robotnik_gazebo_ignition spawn_world.launch.py \
world_path:=$RENEE_SRC_PATH/../../install/renee_rbvogui_navigation/share/renee_rbvogui_navigation/world/table_cube_world.sdf &

# Publish static TF: world -> robot_map; x y z should match with those when spawning the robot in spawn docker service
ros2 run tf2_ros static_transform_publisher \
  --x 3.0 --y 3.0 --z 0.0 \
  --roll 0 --pitch 0 --yaw 0 \
  --frame-id world \
  --child-frame-id robot_map &


### SPAWN THE MOBILE MANIPULATOR
export ROBOT_MODEL=rbvogui_plus
sleep 5 && ros2 launch robotnik_gazebo_ignition spawn_robot.launch.py robot_id:=robot robot:=rbvogui run_rviz:=true \
x:=2.5 \
y:=2.5 \
rviz_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/rviz_config.rviz \
low_performance_simulation:=true \
end_effector:=rg6 &


# # LOAD MAP and LOCALIZATION
ros2 launch slam_toolbox localization_launch.py use_sim:=true robot_id:=robot \
    slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_localization_demo.yaml &

# # RUN NAVIGATION
ros2 launch renee_rbvogui_navigation navigation.launch.py use_sim:=true robot_id:=robot



