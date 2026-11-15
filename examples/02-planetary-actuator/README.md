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

## Gearbox

The default stage is a 12T sun, 18T planets, and a 48T ring with **four**
orbiting planets for load sharing (5:1 reduction). `--numPlanets` overrides
the count; the equally spaced 12/48 combination supports 3, 4, 6, or 12
planets.

The stage uses the **4-elbow herringbone** geometry (`--numElbows 4`). This
gear set is **print-in-place**: the sun, planets, and ring interlock and cannot
be assembled after printing. The build package prints them as one
`printable/PGB-CARTRIDGE.step` job, then adds the separately printed carrier,
bearings, hub, housing, and output hardware.

## Drivetrain

The motor rotor directly drives the sun gear. In the housed layout the rotor
shaft spans roughly `z = -28..14 mm`; the sun clamp hub occupies
`z = -0.5..4 mm` and the sun gear `z = 4..14 mm` for the default 10 mm stage.
The shaft passes through both the clamp hub and the full sun bore. The sun
joint is a 1:1 mimic of the motor rotor joint
(`set_joint_mimic(..., multiplier=1.0)`); the carrier and planets then follow
the sun through the planetary tooth ratios. The printed housing hides this in
the housed layout — `--motor exposed` shows the same shaft-to-sun path openly.

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
