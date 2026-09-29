#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
# slam_toolbox localizes (robot_map -> robot_odom) but publishes its live map on
# /slam_map; map_server serves the fixed maps/${SIM_MAP}.yaml on /map.
# SIM_MAP (default renee_room) selects both maps/<name>.yaml (map_server) and
# maps/<name>.posegraph/.data (slam_toolbox); it must match GZ_WORLD.
SIM_MAP=${SIM_MAP:-renee_room}
echo "[localization] SIM_MAP=$SIM_MAP (GZ_WORLD=${GZ_WORLD:-unset})"
ros2 launch renee_bringup_utils localization_sim.launch.py use_sim_time:=true robot_id:=robot \
    slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_localization.yaml \
    map:=$RENEE_SRC_PATH/maps/$SIM_MAP.yaml \
    map_file_name:=$RENEE_SRC_PATH/maps/$SIM_MAP
