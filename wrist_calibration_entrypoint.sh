#!/bin/bash
# Entry point for the wrist_camera_calibration services (see docker-compose.yaml).
#   calibrate : GUI + automatic hand-eye capture   (extra launch args as further arguments)
#   tf        : publish the saved calibration into TF (extra launch args as further arguments)
#   mock      : mock GrabFrame camera server for tests without the real ZED
#   servers   : the action servers the calibration needs: arm_joint_motion_plan_server (arm moves) and
#               capture_camera_frames_action_server (real ZED; skip with WCC_CAMERA_SERVER=0)
#   rviz      : RViz with the Calibration Status panel (config: wrist_camera_calibration_rviz/rviz/calibration.rviz)
# Example: WCC_ARGS="num_images:=15 execute:=false" docker compose up wrist-calibration  (compose appends $WCC_ARGS)
set -e
cd /fnh_pkgs
# Same retry as planner_entrypoint.sh: sourcing install/setup.bash occasionally fails to extend
# AMENT_PREFIX_PATH, which makes ros2 report packages as missing.
for i in $(seq 1 8); do
  source install/setup.bash
  [ "${#AMENT_PREFIX_PATH}" -gt 1000 ] && break
  sleep 1
done
mode="${1:-calibrate}"
case "$mode" in
  calibrate) launch=calibrate.launch.py ;;
  tf)        launch=publish_calibration.launch.py ;;
  mock)      launch=mock_camera.launch.py ;;
  servers)
    ros2 run renee_action_servers arm_joint_motion_plan_server --ros-args -p use_sim_time:=false \
      -p move_group_namespace:=robot -p planning_group:=arm "${@:2}" &
    if [ "${WCC_CAMERA_SERVER:-1}" != "0" ]; then
      ros2 run renee_action_servers capture_camera_frames_action_server --ros-args \
        --params-file "$(ros2 pkg prefix --share renee_action_servers)/config/camera_frames_real.yaml" &
    fi
    wait -n; echo "an action server exited, stopping" >&2; kill $(jobs -p) 2>/dev/null; exit 1 ;;
  rviz)      exec ros2 run rviz2 rviz2 -d "$(ros2 pkg prefix --share wrist_camera_calibration_rviz)/rviz/calibration.rviz" "${@:2}" ;;
  *) echo "usage: $0 {calibrate|tf|mock|servers|rviz}" >&2; exit 2 ;;
esac
exec ros2 launch wrist_camera_calibration "$launch" "${@:2}"
