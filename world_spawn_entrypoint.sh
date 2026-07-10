#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
export GZ_SIM_RESOURCE_PATH=$RENEE_SRC_PATH/campetella_sim/models:$GZ_SIM_RESOURCE_PATH
echo $GZ_SIM_RESOURCE_PATH
ros2 launch robotnik_gazebo_ignition spawn_world.launch.py \
world_path:=$RENEE_SRC_PATH/../../install/renee_rbvogui_navigation/share/renee_rbvogui_navigation/world/campetella.sdf &

# Publish Campetella robot description (for MoveIt usage)
ros2 run robot_state_publisher robot_state_publisher \
  --ros-args \
  -p robot_description:="$(xacro $RENEE_SRC_PATH/campetella_sim/models/campetella_CRC/urdf/campetella.urdf.xacro)" \
  -r robot_description:=/campetella_robot_description \
  -r joint_states:=/campetella_robot/joint_states \
  --remap __node:=campetella_robot_state_publisher &

# Publish static TF: world -> campetella_base_link; x y z should match with those at the bottom command (for Gazebo spawner)
ros2 run tf2_ros static_transform_publisher \
  --x 4.5 --y 3.0 --z 0.2 \
  --roll 0 --pitch 0 --yaw 0 \
  --frame-id world \
  --child-frame-id campetella_base_link &

# Publish static TF: world -> robot_map; x y z should match with those when spawning the robot in spawn docker service
ros2 run tf2_ros static_transform_publisher \
  --x 7.0 --y 2.0 --z 0.0 \
  --roll 0 --pitch 0 --yaw 0 \
  --frame-id world \
  --child-frame-id robot_map &

# Wait for the Gazebo world to actually be running (clock publishing)
wait_for_ros --timeout 60 topic /clock --msg && ros2 run ros_gz_sim create -name campetella \
-topic /campetella_robot_description \
-x 4.5 -y 3.0 -z 0.2
tail -f /dev/null


# -file /fnh_pkgs/src/renee_simulation/campetella_sim/models/campetella_CRC/urdf/test_box.sdf \
# -x 4.5 -y 3.0 -z 0.2
# gui:=false \
# world_path:=/fnh_pkgs/install/renee_rbvogui_navigation/share/renee_rbvogui_navigation/world/fnh_world.sdf
# world_path:=/fnh_pkgs/src/campetella_sim/worlds/campetella.sdf.world
# world_path:=/fnh_pkgs/demo1.sdf
