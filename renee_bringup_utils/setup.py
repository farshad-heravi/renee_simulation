import glob
import os
from setuptools import find_packages, setup

package_name = 'renee_bringup_utils'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('lib', package_name), glob.glob('scripts/*.sh')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Farshad Nozad Heravi',
    maintainer_email='f.n.heravi@gmail.com',
    description='Readiness waiters used to replace fixed-delay bringup choreography with event-based synchronization.',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'wait_for_ros = renee_bringup_utils.wait_for_ros:main',
        ],
    },
)
