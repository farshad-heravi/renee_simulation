#!/bin/bash
set -e
cd /fnh_pkgs
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --packages-skip moveit_ros_tests
