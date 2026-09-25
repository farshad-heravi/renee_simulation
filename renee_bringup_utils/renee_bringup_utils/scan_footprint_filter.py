#!/usr/bin/env python3
"""Drop laser returns that hit the robot's own body.

Republishes a LaserScan with every return that lands inside the robot's
footprint (+ margin, in base_frame) set to 0.0 — the "no return" value the
Vogui's SICK TiM571s already emit, below range_min, so slam_toolbox and the
Nav2 costmaps skip the beam entirely (no hit, no ray clearing).

Why: the front laser sees parts of the chassis (a steady arc at ~0.30 m and
intermittent points further out, e.g. ~(0.61, -0.22) in robot_base_link at
~0.57 m). slam_toolbox's min_laser_range can only cut by distance, so the
far ones got rasterized as occupied cells along the driven path; with only
the front laser mapping, nothing ever looks back to clear them.

    scan_footprint_filter --ros-args \
        -r scan_in:=/robot/front_laser/scan -r scan_out:=/robot/front_laser/scan_filtered
"""
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from rclpy.time import Time
from sensor_msgs.msg import LaserScan
import tf2_ros


def _yaw_from_quat(q):
    return np.arctan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))


class ScanFootprintFilter(Node):

    def __init__(self):
        super().__init__('scan_footprint_filter')
        self.base_frame = self.declare_parameter('base_frame', 'robot_base_link').value
        # Box around the footprint [[0.6,-0.35],[0.6,0.35],[-0.6,0.35],[-0.6,-0.35]]
        margin = self.declare_parameter('margin', 0.05).value
        self.half_x = self.declare_parameter('footprint_half_x', 0.6).value + margin
        self.half_y = self.declare_parameter('footprint_half_y', 0.35).value + margin

        self.tf_buffer = tf2_ros.Buffer()
        self.tf_listener = tf2_ros.TransformListener(self.tf_buffer, self)
        self.laser_pose = None  # (x, y, yaw, flipped) of the laser in base_frame
        self.cos_sin = None     # cached per-beam direction in base_frame

        self.pub = self.create_publisher(LaserScan, 'scan_out', qos_profile_sensor_data)
        self.create_subscription(LaserScan, 'scan_in', self.callback, qos_profile_sensor_data)

    def _lookup_laser_pose(self, frame_id):
        try:
            tf = self.tf_buffer.lookup_transform(self.base_frame, frame_id, Time())
        except tf2_ros.TransformException as e:
            self.get_logger().warn(f'waiting for {self.base_frame}->{frame_id}: {e}',
                                   throttle_duration_sec=5.0)
            return None
        t, q = tf.transform.translation, tf.transform.rotation
        # The Vogui lasers are mounted upside down (roll = pi): a laser-frame
        # angle a maps to base-frame yaw - a instead of yaw + a. The sign of
        # the rotated z axis tells which.
        z_up = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
        return (t.x, t.y, _yaw_from_quat(q), z_up < 0.0)

    def callback(self, msg):
        if self.laser_pose is None:
            self.laser_pose = self._lookup_laser_pose(msg.header.frame_id)
            if self.laser_pose is None:
                return  # publish nothing rather than unfiltered data
            self.get_logger().info(
                f'{msg.header.frame_id} in {self.base_frame}: '
                f'x={self.laser_pose[0]:.3f} y={self.laser_pose[1]:.3f} '
                f'yaw={self.laser_pose[2]:.3f} flipped={self.laser_pose[3]}; '
                f'dropping returns inside |x|<={self.half_x:.2f} |y|<={self.half_y:.2f}')

        ranges = np.asarray(msg.ranges, dtype=np.float32)
        if self.cos_sin is None or self.cos_sin.shape[1] != ranges.size:
            lx, ly, yaw, flipped = self.laser_pose
            angles = msg.angle_min + msg.angle_increment * np.arange(ranges.size)
            base_angles = yaw - angles if flipped else yaw + angles
            self.cos_sin = np.vstack([np.cos(base_angles), np.sin(base_angles)])

        lx, ly = self.laser_pose[0], self.laser_pose[1]
        x = lx + ranges * self.cos_sin[0]
        y = ly + ranges * self.cos_sin[1]
        on_body = np.isfinite(ranges) & (np.abs(x) <= self.half_x) & (np.abs(y) <= self.half_y)

        out = msg
        filtered = ranges.copy()
        filtered[on_body] = 0.0
        out.ranges = filtered.tolist()
        self.pub.publish(out)


def main():
    rclpy.init()
    node = ScanFootprintFilter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    node.destroy_node()
    rclpy.try_shutdown()


if __name__ == '__main__':
    main()
