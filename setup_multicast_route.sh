#!/bin/bash
# One-time-per-boot host prerequisite for the simulation stack.
#
# gz-transport (gz sim's own pub/sub, separate from ROS) discovers peers via
# UDP multicast. By default the kernel routes that multicast traffic out
# through whatever interface has the default route — on this host that's
# wifi, and wifi hardware/drivers generally don't loop multicast packets
# back to local receivers. Result: gz sim loads fine internally but nothing
# (not `gz topic -l`, not the ros_gz_bridge) can ever discover its topics,
# so `/clock` never appears and `wait_for_ros` times out — no amount of
# waiting fixes it, since it's a routing gap, not a timing one.
#
# The compose services run with `network_mode: host`, so this route must be
# set on the host itself (a container can't set it: the image doesn't even
# ship iproute2, and there's no separate network namespace to fix from
# inside anyway). It does not survive a reboot, so re-run this once after
# each boot before `docker compose up`.
#
# (ROS's own discovery, via CycloneDDS, is a separate mechanism unaffected
# by this route — that one is fixed in docker-compose.yaml directly via
# CYCLONEDDS_URI, which pins CycloneDDS to loopback and disables multicast
# entirely.)
set -e

if ip route show | grep -q '^224\.0\.0\.0/4 dev lo'; then
  echo "Multicast loopback route already present, nothing to do."
  exit 0
fi

sudo ip route add 224.0.0.0/4 dev lo
echo "Added: 224.0.0.0/4 dev lo"
