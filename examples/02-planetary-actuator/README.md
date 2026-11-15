# 02 — Planetary Actuator

A low-KV BLDC outrunner (`@step_motors.brushless_motor`) driving a Tier-1
planetary gearbox, either housed with a twin-bearing output cartridge and an
AS5047P output encoder, or exposed as a bench/viewing stage.

Run it from the repository root:

```bash
./run-example.sh 02-planetary-actuator --headless --check
./run-example.sh 02-planetary-actuator --headless --package /tmp/ex02
./run-example.sh 02-planetary-actuator --view --motor exposed
```

## Third-party assets

### moteus C1 r1.2 controller board

`20240305-moteus-c1-r1_2.step` is the exact moteus C1 r1.2 controller board
from the open-source moteus hardware project. It is vendored here and imported
into the housed example as the actuator's controller board; the flat STEP
output carries its exact vendor B-Rep, mounted 6.5 mm off the printed pad on
four M3 tapped standoffs.

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
