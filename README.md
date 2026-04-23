# renee_simulation

### Cloning and Building the packages
Use the following command to clone the repo and submodules inside your ws folder
```
mkdir src && cd src
git clone --recursive-submodules git@github.com:farshad-heravi/renee_simulation.git
```

For the initial building, run
```
docker compose up builder
```

### How to use
For spawning the world and the robot
```
docker compose up world spawn-robot
```

In the second terminal
```
docker compose up navigation localization
```

In the third terminal
```
docker compose up moveit
```

