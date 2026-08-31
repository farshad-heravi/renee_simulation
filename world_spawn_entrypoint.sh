#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
export GZ_SIM_RESOURCE_PATH=$RENEE_SRC_PATH/campetella_sim/models:$GZ_SIM_RESOURCE_PATH
echo $GZ_SIM_RESOURCE_PATH
ros2 launch robotnik_gazebo_ignition spawn_world.launch.py \
world_path:=$RENEE_SRC_PATH/../../install/renee_rbvogui_navigation/share/renee_rbvogui_navigation/world/campetella.sdf &

# Campetella is spawned through its stable package facade.
# Publish static TF: world -> robot_map; x y z should match with those when spawning the robot in spawn docker service
ros2 run tf2_ros static_transform_publisher \
  --x 7.0 --y 2.0 --z 0.0 \
  --roll 0 --pitch 0 --yaw 0 \
  --frame-id world \
  --child-frame-id robot_map &

# Wait for the Gazebo world to actually be running (clock publishing)
wait_for_ros --timeout 60 topic /clock --msg
ros2 launch campetella_sim spawn_campetella.launch.py \
x:=4.5 y:=3.0 z:=0.2
tail -f /dev/null


# -file /fnh_pkgs/src/renee_simulation/campetella_sim/models/campetella_CRC/urdf/test_box.sdf \
# -x 4.5 -y 3.0 -z 0.2
# gui:=false \
# world_path:=/fnh_pkgs/install/renee_rbvogui_navigation/share/renee_rbvogui_navigation/world/fnh_world.sdf
# world_path:=/fnh_pkgs/src/campetella_sim/worlds/campetella.sdf.world
# world_path:=/fnh_pkgs/demo1.sdf
