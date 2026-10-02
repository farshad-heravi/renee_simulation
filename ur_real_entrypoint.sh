#!/bin/bash
set -e
cd /fnh_pkgs
source install/setup.bash
# UR_HEADLESS_MODE=true: pendant in Remote mode, the driver sends the control
# script itself. false: start External Control on the pendant (Local mode).
# UR_ROBOT_IP: the arm's LAN address. UR_REVERSE_IP: this host's address on
# that same LAN (the External Control URCap on the pendant must point at it).
ros2 launch renee_rbvogui_plus_moveit_config start_moveit_real.launch.py \
    robot_ip:=${UR_ROBOT_IP:-192.168.0.101} \
    reverse_ip:=${UR_REVERSE_IP:-192.168.0.150} \
    kinematics_params_file:=${UR_KINEMATICS_FILE:-/fnh_pkgs/ur5e_calibration.yaml} \
    headless_mode:=${UR_HEADLESS_MODE:-true} \
    end_effector:=${UR_END_EFFECTOR:-none} \
    use_rviz:=${UR_USE_RVIZ:-true}
