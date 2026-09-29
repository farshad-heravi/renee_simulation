#!/bin/bash
# Per-world spawn poses, sourced by world_spawn_entrypoint.sh and
# robot_spawn_entrypoint.sh. Select the world with GZ_WORLD (default:
# renee_room); any value below can be overridden by exporting it first.
#   ROBOT_SPAWN_X/Y   mobile manipulator spawn (also the world->robot_map TF)
#   CAMPETELLA_X/Y/Z  Campetella CRC machine spawn
export GZ_WORLD=${GZ_WORLD:-renee_room}
case "$GZ_WORLD" in
  renee_room)
    # Campetella at the origin, raised onto the stands of world/renee_room.sdf
    # (beam bottom at z=0.80); the stands/fences there assume x=y=yaw=0.
    # Robot in the +y side passage, midway between the H and the wall.
    : "${ROBOT_SPAWN_X:=-1.4}" "${ROBOT_SPAWN_Y:=1.25}"
    : "${CAMPETELLA_X:=0.0}" "${CAMPETELLA_Y:=0.0}" "${CAMPETELLA_Z:=1.0}"
    ;;
  *)
    : "${ROBOT_SPAWN_X:=7.0}" "${ROBOT_SPAWN_Y:=2.0}"
    : "${CAMPETELLA_X:=4.5}" "${CAMPETELLA_Y:=3.0}" "${CAMPETELLA_Z:=0.2}"
    ;;
esac
export ROBOT_SPAWN_X ROBOT_SPAWN_Y CAMPETELLA_X CAMPETELLA_Y CAMPETELLA_Z
