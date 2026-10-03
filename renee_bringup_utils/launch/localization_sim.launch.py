"""Gazebo-sim localization: slam_toolbox for pose, map_server for a fixed /map.

In localization mode slam_toolbox re-renders its occupancy grid every
map_update_interval from the loaded posegraph plus live scans, so the map it
publishes keeps changing (walls can get wiped or warped). Nav2's static layer
needs a fixed map, so:

  * slam_toolbox (localization_slam_toolbox_node) still does scan matching and
    publishes robot_map -> robot_odom, but its /map, /map_metadata and
    /map_updates outputs are remapped to /slam_map* (debug only).
  * nav2_map_server serves the saved maps/<map>.yaml (default renee_room) on /map
    (transient local) in the same robot_map frame.

Mirrors /opt/ros/jazzy/share/slam_toolbox/launch/localization_launch.py for the
slam_toolbox lifecycle autostart (configure -> activate via launch events).
"""

import os

from launch import LaunchDescription
from launch.actions import (DeclareLaunchArgument, EmitEvent, LogInfo,
                            RegisterEventHandler)
from launch.conditions import IfCondition
from launch.events import matches_action
from launch.substitutions import (AndSubstitution, EnvironmentVariable,
                                  LaunchConfiguration, NotSubstitution,
                                  PathJoinSubstitution)
from launch_ros.actions import LifecycleNode, Node
from launch_ros.event_handlers import OnStateTransition
from launch_ros.events.lifecycle import ChangeState
from lifecycle_msgs.msg import Transition


def generate_launch_description():
    use_sim_time = LaunchConfiguration('use_sim_time')
    use_lifecycle_manager = LaunchConfiguration('use_lifecycle_manager')
    slam_params_file = LaunchConfiguration('slam_params_file')
    autostart = LaunchConfiguration('autostart')
    map_yaml = LaunchConfiguration('map')
    map_frame = LaunchConfiguration('map_frame')
    map_file_name = LaunchConfiguration('map_file_name')

    renee_src = EnvironmentVariable(
        'RENEE_SRC_PATH', default_value='/renee/src/renee_sw')

    declare_args = [
        DeclareLaunchArgument(
            'use_sim_time', default_value='true',
            description='Use simulation/Gazebo clock'),
        DeclareLaunchArgument(
            'slam_params_file',
            default_value=PathJoinSubstitution(
                [renee_src, 'configs', 'mapper_params_localization.yaml']),
            description='slam_toolbox localization params file'),
        DeclareLaunchArgument(
            'autostart', default_value='true',
            description='Automatically configure/activate slam_toolbox and '
                        'map_server. slam_toolbox ignores it when '
                        'use_lifecycle_manager is true.'),
        DeclareLaunchArgument(
            'use_lifecycle_manager', default_value='false',
            description='Enable bond connection during slam_toolbox activation'),
        DeclareLaunchArgument(
            'map',
            default_value=PathJoinSubstitution(
                [renee_src, 'maps', 'renee_room.yaml']),
            description='Static map yaml served on /map by map_server'),
        DeclareLaunchArgument(
            'map_file_name',
            default_value=PathJoinSubstitution([renee_src, 'maps', 'renee_room']),
            description='slam_toolbox serialized posegraph (no extension); '
                        'overrides map_file_name in slam_params_file. Must be '
                        'the same map as `map`.'),
        DeclareLaunchArgument(
            'map_frame', default_value='robot_map',
            description='Frame of the static map; must match slam map_frame'),
        # Accepted for compatibility with the old entrypoint; unused.
        DeclareLaunchArgument('robot_id', default_value='robot'),
    ]

    slam_toolbox_node = LifecycleNode(
        parameters=[
            slam_params_file,
            {
                'use_lifecycle_manager': use_lifecycle_manager,
                'use_sim_time': use_sim_time,
                'map_file_name': map_file_name,
            },
        ],
        package='slam_toolbox',
        executable='localization_slam_toolbox_node',
        name='slam_toolbox',
        output='screen',
        namespace='',
        remappings=[
            ('/map', '/slam_map'),
            ('/map_metadata', '/slam_map_metadata'),
            ('/map_updates', '/slam_map_updates'),
            ('map', '/slam_map'),
            ('map_metadata', '/slam_map_metadata'),
            ('map_updates', '/slam_map_updates'),
        ],
    )

    slam_autostart = IfCondition(
        AndSubstitution(autostart, NotSubstitution(use_lifecycle_manager)))

    configure_event = EmitEvent(
        event=ChangeState(
            lifecycle_node_matcher=matches_action(slam_toolbox_node),
            transition_id=Transition.TRANSITION_CONFIGURE,
        ),
        condition=slam_autostart,
    )

    activate_event = RegisterEventHandler(
        OnStateTransition(
            target_lifecycle_node=slam_toolbox_node,
            start_state='configuring',
            goal_state='inactive',
            entities=[
                LogInfo(msg='[LifecycleLaunch] Slamtoolbox node is activating.'),
                EmitEvent(event=ChangeState(
                    lifecycle_node_matcher=matches_action(slam_toolbox_node),
                    transition_id=Transition.TRANSITION_ACTIVATE,
                )),
            ],
        ),
        condition=slam_autostart,
    )

    map_server_node = Node(
        package='nav2_map_server',
        executable='map_server',
        name='map_server',
        namespace='',
        output='screen',
        parameters=[{
            'yaml_filename': map_yaml,
            'use_sim_time': use_sim_time,
            'topic_name': 'map',
            'frame_id': map_frame,
        }],
    )

    map_lifecycle_manager = Node(
        package='nav2_lifecycle_manager',
        executable='lifecycle_manager',
        name='lifecycle_manager_map',
        namespace='',
        output='screen',
        parameters=[{
            'use_sim_time': use_sim_time,
            'autostart': autostart,
            'node_names': ['map_server'],
        }],
    )

    ld = LaunchDescription()
    for arg in declare_args:
        ld.add_action(arg)
    ld.add_action(slam_toolbox_node)
    ld.add_action(configure_event)
    ld.add_action(activate_event)
    ld.add_action(map_server_node)
    ld.add_action(map_lifecycle_manager)
    return ld
