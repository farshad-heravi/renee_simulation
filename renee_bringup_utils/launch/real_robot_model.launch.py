"""Publish the RB-Vogui rover model for RViz on the real robot.

The real robot, relayed by vogui_ros1_ros2_bridge, provides the base TF but no
robot_description. This launch publishes /robot_description from
urdf/rbvogui_base_only.urdf.xacro (rover body only: no arm, sensors or tool
changer) and lets the robot's own TF place the links. robot_state_publisher
is used only to latch the description; its TF goes to private topics, so
nothing here overrides the robot's real TF.

The URDF's steering-housing links (robot_*_base_wheel) are called
robot_*_motor_wheel on the real robot, at the same pose (base_link offset
±0.368/±0.235, identity to the wheel), so they're attached with identity
static transforms and follow the real steering. robot_base_docking_contact
isn't on the real robot either; it gets the URDF's fixed offset from chassis.
"""
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.substitutions import Command
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue

PREFIX = 'robot_'
WHEELS = ['front_left', 'front_right', 'back_left', 'back_right']


def static_tf(parent, child, xyz=('0', '0', '0')):
    return Node(
        package='tf2_ros',
        executable='static_transform_publisher',
        name=f'real_robot_model_{child}_tf',
        arguments=['--x', xyz[0], '--y', xyz[1], '--z', xyz[2],
                   '--frame-id', parent, '--child-frame-id', child],
    )


def generate_launch_description():
    xacro_file = os.path.join(
        get_package_share_directory('renee_bringup_utils'),
        'urdf', 'rbvogui_base_only.urdf.xacro')
    robot_description = ParameterValue(
        Command(['xacro ', xacro_file, f' prefix:={PREFIX}']), value_type=str)

    return LaunchDescription([
        Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            name='real_robot_model_state_publisher',
            parameters=[{'robot_description': robot_description,
                         'use_sim_time': False}],
            remappings=[
                ('/tf', '/robot_model_viz/tf'),
                ('/tf_static', '/robot_model_viz/tf_static'),
            ],
        ),
        *[static_tf(f'{PREFIX}{w}_motor_wheel', f'{PREFIX}{w}_base_wheel') for w in WHEELS],
        static_tf(f'{PREFIX}chassis_link', f'{PREFIX}base_docking_contact',
                  ('0.5235', '0', '0.09265')),
    ])
