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
you would see the following windows
<img width="1851" height="1174" alt="Screenshot from 2026-04-23 16-06-33" src="https://github.com/user-attachments/assets/c4094aa8-d5e2-498b-89ee-a330c584e47d" />


In the second terminal
```
docker compose up navigation localization
```

In the third terminal
```
docker compose up moveit
```

