#!/usr/bin/env bash
# Docker healthcheck wrapper for wait_for_ros.
#
# Sources the ROS 2 workspace, then runs `wait_for_ros` with a short timeout
# suitable for a single HEALTHCHECK invocation — Compose polls this on its
# own interval, so this call must return quickly rather than block for the
# whole startup window.
#
# Usage (from docker-compose.yaml):
#   healthcheck.sh topic /clock --msg
#   healthcheck.sh controller /robot/controller_manager arm_controller --state active
set -e
source /opt/ros/jazzy/setup.bash
if [ -f /fnh_pkgs/install/setup.bash ]; then
    source /fnh_pkgs/install/setup.bash
fi
exec wait_for_ros --timeout "${HEALTHCHECK_TIMEOUT:-3}" "$@"
