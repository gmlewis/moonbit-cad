# 02 — Planetary Actuator

A low-KV BLDC outrunner (`@step_motors.brushless_motor`) driving a Tier-1
planetary gearbox, either housed with a twin-bearing output cartridge and the
moteus C1 on-axis output sensor, or exposed as a bench/viewing stage.

Run it from the repository root:

```bash
./run-example.sh 02-planetary-actuator --headless --check
./run-example.sh 02-planetary-actuator --headless --package /tmp/ex02
./run-example.sh 02-planetary-actuator --view --motor exposed
```

## Output sensor

The housed layout mounts the exact moteus C1 r1.2 board horizontally above the
output cover. Its AS5047P chip U6 is at the board centre on the bottom face, so
the board is centred on the output shaft and rotated chip-down. A
diametrically magnetized cylinder magnet sits on the output carrier shaft. The
chip-to-magnet gap and the magnet size are CLI parameters:

```bash
./run-example.sh 02-planetary-actuator --headless \
  --magnetDiam 6 --magnetHeight 2.5 --sensorGap 2.7
```

The measured board geometry puts the U6 package bottom 1.2 mm below the board
origin and the PCB bottom 0.8 mm above it. With the default gap the board's
lowest edge connector just clears the cover boss; the gap is the minimum for
this board and cover without a relief cut. The board is held by four M3 tapped
standoffs at its 6 mm corner holes, reaching from the output cover plate.

## Third-party assets

### moteus C1 r1.2 controller board

`20240305-moteus-c1-r1_2.step` is the exact moteus C1 r1.2 controller board
from the open-source moteus hardware project. It is vendored here and imported
into the housed example as the motor controller and output sensor; the flat
STEP output carries its exact vendor B-Rep.

- **Project:** moteus — <https://github.com/mjbots/moteus>
- **Source file:** <https://github.com/mjbots/moteus/blob/main/hw/c1/r1.2/20240305-moteus-c1-r1_2.step>
- **Copyright:** mjbots and the moteus contributors
- **License:** Apache License 2.0 — <https://www.apache.org/licenses/LICENSE-2.0>
- **Vendored:** 2026-11-14

The file is included unchanged, and its original STEP header is preserved.
If this asset is redistributed or modified, keep this attribution and the
upstream Apache-2.0 notice.

The exact B-Rep appears in the flat STEP output and in the housing link's
`bundle/parts/*.step`. The URDF/glTF visual for that link uses the board's
bounding box, because the importer places the vendor B-Rep but does not
tessellate it; use the STEP asset when the board's exact shape matters.
