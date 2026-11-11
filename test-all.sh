#!/bin/bash -ex
moon fmt . components examples/common examples/01-bracket-assembly examples/02-planetary-actuator examples/03-serial-robot-arm examples/04-pan-tilt-turret examples/05-galileo-quadruped examples/06-assistive-scooter
moon info --target native . components examples/common examples/01-bracket-assembly examples/02-planetary-actuator examples/03-serial-robot-arm examples/04-pan-tilt-turret examples/05-galileo-quadruped examples/06-assistive-scooter
moon test -j 12 --target native . components
