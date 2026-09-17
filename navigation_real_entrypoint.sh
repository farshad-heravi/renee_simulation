#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
# Real-robot Nav2 bring-up, analogous to navigation_entrypoint.sh (Gazebo-sim
# `navigation` service). Two overrides beyond use_sim:=false, both required
# for the vogui_ros1_ros2_bridge path (see nav2_task.launch.py comments):
# - controller_config/behavior_config: the _real.yaml variants, which set
#   enable_stamped_cmd_vel: false and use_sim_time: false in their nested
#   local_costmap/behavior_server blocks.
# - cmd_vel_topic:=move_base/cmd_vel: the only cmd_vel topic the bridge
#   relays into the robot's twist_mux.
ros2 launch renee_rbvogui_navigation navigation.launch.py use_sim:=false robot_id:=robot \
    controller_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/controller_server_real.yaml \
    behavior_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/behavior_server_real.yaml \
    cmd_vel_topic:=move_base/cmd_vel
