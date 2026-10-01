#!/bin/bash
# Entry point for the wrist_camera_calibration services (see docker-compose.yaml).
#   calibrate : GUI + automatic hand-eye capture   (extra launch args as further arguments)
#   tf        : publish the saved calibration into TF (extra launch args as further arguments)
#   mock      : mock GrabFrame camera server for tests without the real ZED
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
  *) echo "usage: $0 {calibrate|tf|mock}" >&2; exit 2 ;;
esac
exec ros2 launch wrist_camera_calibration "$launch" "${@:2}"
