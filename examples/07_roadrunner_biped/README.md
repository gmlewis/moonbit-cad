# 07 — Roadrunner bipedal wheeled robot

Parametric model inspired by the RAI Institute **Roadrunner** 15 kg
multi-modal bipedal wheeled robot:

- **Torso drum:** 230 mm OD × 210 mm cylindrical lateral drum with purple curved
  outer wrap, gold structural end rings, white upper cheek shrouds, dual top
  tether hoops, internal 48 V battery + compute pack, and IMU.
- **Symmetric 8-DOF legs:** Hip abduction/roll, continuous symmetric hip pitch,
  brushed-silver cylindrical thighs with side ESC pods, bidirectional symmetric
  knees (`±140°`), slim twin-bar dark calves, and 180 mm (7-inch) multi-spoke
  wheels with compact hub motors.
- **Locomotion presets (`--mode`):**
  - `side-by-side` (default)
  - `in-line` (tandem skating / stair approach, knees symmetric fore/aft)
  - `one-wheel` (one-wheel dynamic balance with raised tucked leg)
  - `wide` (ground stand-up recovery stance)

```sh
./run-example.sh 07 --headless
./run-example.sh 07 --headless --mode in-line
./run-example.sh 07 --headless --mode one-wheel
./build-part.sh 7
```
