#!/bin/bash
set -e
cd /fnh_pkgs
sudo apt-get update
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --packages-skip moveit_ros_tests rviz_ogre_vendor
