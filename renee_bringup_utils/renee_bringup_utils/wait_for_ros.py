#!/usr/bin/env python3
"""Generic readiness waiter for ROS 2 bringup.

Blocks until a topic, service, action, controller, tf transform, or node
becomes available, then exits 0. Exits 1 if `--timeout` elapses first.

Used by launch files, entrypoint scripts, and Docker Compose healthchecks
to replace fixed sleeps / TimerActions with actual readiness checks.
"""
import argparse
import importlib
import sys
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data


def _import_msg_type(type_string: str):
    """'pkg_name/msg/MsgName' -> the message class."""
    pkg, _, msg = type_string.split('/')
    mod = importlib.import_module(f'{pkg}.msg')
    return getattr(mod, msg)


def wait_for_topic(node: Node, name: str, timeout: float, require_msg: bool) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.2)
        if node.count_publishers(name) == 0:
            continue
        if not require_msg:
            return True
        types = dict(node.get_topic_names_and_types()).get(name)
        if types:
            try:
                msg_type = _import_msg_type(types[0])
            except (ImportError, AttributeError, ValueError):
                # Can't introspect the type dynamically; presence is enough.
                return True

            received = {'ok': False}

            def _cb(_msg):
                received['ok'] = True

            sub = node.create_subscription(msg_type, name, _cb, qos_profile_sensor_data)
            try:
                msg_deadline = min(deadline, time.monotonic() + timeout)
                while time.monotonic() < msg_deadline and not received['ok']:
                    rclpy.spin_once(node, timeout_sec=0.2)
            finally:
                node.destroy_subscription(sub)
            if received['ok']:
                return True
    return False


def wait_for_service(node: Node, name: str, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.2)
        if name in dict(node.get_service_names_and_types()):
            return True
    return False


def wait_for_action(node: Node, name: str, timeout: float) -> bool:
    # rclpy_action servers publish a GoalStatusArray on "<name>/_action/status".
    return wait_for_topic(node, f'{name}/_action/status', timeout, require_msg=False)


def wait_for_node(node: Node, name: str, timeout: float) -> bool:
    target = name if name.startswith('/') else f'/{name}'
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.2)
        for n_name, n_ns in node.get_node_names_and_namespaces():
            full = n_name if n_ns == '/' else f'{n_ns}/{n_name}'
            if not full.startswith('/'):
                full = f'/{full}'
            if full == target:
                return True
    return False


def wait_for_controller(node: Node, cm_service: str, controller_name: str,
                         desired_state: str, timeout: float) -> bool:
    from controller_manager_msgs.srv import ListControllers

    client = node.create_client(ListControllers, f'{cm_service}/list_controllers')
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            if not client.wait_for_service(timeout_sec=1.0):
                continue
            future = client.call_async(ListControllers.Request())
            rclpy.spin_until_future_complete(node, future, timeout_sec=2.0)
            if future.done() and future.result() is not None:
                for controller in future.result().controller:
                    if controller.name == controller_name and controller.state == desired_state:
                        return True
    finally:
        node.destroy_client(client)
    return False


def wait_for_tf(node: Node, parent: str, child: str, timeout: float) -> bool:
    from tf2_ros import Buffer, TransformListener

    buffer = Buffer()
    listener = TransformListener(buffer, node)  # noqa: F841 - keeps subscription alive
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.2)
        if buffer.can_transform(parent, child, rclpy.time.Time()):
            return True
    return False


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description='Block until a ROS 2 graph entity becomes ready, then exit 0.')
    parser.add_argument('--timeout', type=float, default=60.0,
                         help='Seconds to wait before failing (default: 60)')
    sub = parser.add_subparsers(dest='mode', required=True)

    p_topic = sub.add_parser('topic', help='wait for a topic to have a publisher')
    p_topic.add_argument('name')
    p_topic.add_argument('--msg', action='store_true',
                          help='also wait for one message to be received')

    p_service = sub.add_parser('service', help='wait for a service to be advertised')
    p_service.add_argument('name')

    p_action = sub.add_parser('action', help='wait for an action server')
    p_action.add_argument('name')

    p_node = sub.add_parser('node', help='wait for a node to appear')
    p_node.add_argument('name')

    p_ctrl = sub.add_parser('controller', help='wait for a ros2_control controller state')
    p_ctrl.add_argument('cm_service',
                         help="controller_manager service namespace, e.g. '/robot/controller_manager'")
    p_ctrl.add_argument('controller_name')
    p_ctrl.add_argument('--state', default='active')

    p_tf = sub.add_parser('tf', help='wait for a TF transform to resolve')
    p_tf.add_argument('parent')
    p_tf.add_argument('child')

    return parser


def _summarize(args: argparse.Namespace) -> str:
    d = vars(args).copy()
    d.pop('timeout', None)
    d.pop('mode', None)
    return ' '.join(str(v) for v in d.values())


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    rclpy.init(args=None)
    node = Node('wait_for_ros')
    try:
        if args.mode == 'topic':
            ok = wait_for_topic(node, args.name, args.timeout, args.msg)
        elif args.mode == 'service':
            ok = wait_for_service(node, args.name, args.timeout)
        elif args.mode == 'action':
            ok = wait_for_action(node, args.name, args.timeout)
        elif args.mode == 'node':
            ok = wait_for_node(node, args.name, args.timeout)
        elif args.mode == 'controller':
            ok = wait_for_controller(node, args.cm_service, args.controller_name,
                                      args.state, args.timeout)
        elif args.mode == 'tf':
            ok = wait_for_tf(node, args.parent, args.child, args.timeout)
        else:
            ok = False
    finally:
        node.destroy_node()
        rclpy.shutdown()

    label = f'{args.mode} {_summarize(args)}'
    if ok:
        print(f'[wait_for_ros] ready: {label}')
        return 0
    print(f'[wait_for_ros] TIMEOUT after {args.timeout}s waiting for: {label}', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
