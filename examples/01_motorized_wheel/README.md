# 01 — Motorized wheel

A proof-of-concept wheel built from the compact multi-stage
`motorized_gearbox` component and the measured tier-1 tire envelope from
[`../moonbit-17-step`](https://github.com/gmlewis/moonbit-17-step).

```sh
./run-example.sh 01 --headless              # two stages, 28.4:1
./run-example.sh 01 --numStages 1 --headless
./run-example.sh 01 --numStages 3 --numElbows 0,1,2 --headless
./build-part.sh 1                           # complete print/buy/assemble package
```

## What is different from the example-2 actuator

- **The ring is the casing.** Each stage's internal ring gear is printed as
  part of that stage's casing module. There is no separate ring pressed into an
  outer housing and no separate housing wall around it. The modules bolt
  flange-to-flange, so the outer surface of the whole gearbox is the sum of the
  stage casings plus the motor and output caps.
- **Any number of stages.** Stage 1's sun sits directly on the motor shaft;
  every later stage's sun sits directly on the previous stage's carrier output
  shaft. Every stage parameter is independent.
- **The motor's fixed side is bolted to the casing.** The stator mounts on the
  motor end cap, which is part of the outer casing; the rotor shaft is the only
  moving input.
- **The final carrier is the output interface.** It drives a 1/2" output shaft
  through a flanged bearing in the output cap, and a printed flange hub with a
  40 mm bolt circle (plus two clamp collars) is the standard attachment point
  for a wheel, knee, hip, or other driven link.
- **Flanged planet bearings.** The default planet bearing is a sealed, flanged
  `FR8-2RS` (1/2" x 1 1/8" x 5/16"). It presses into the planet from the lower
  face; the flange seats flush on that face and stops the bearing sliding
  through the gear.

## Stage parameters

Every stage option is a comma-separated list. The first value goes to stage 1,
the second to stage 2, and so on. A shorter list repeats its last value, so a
single value applies to every stage.

| Option | Default | Meaning |
| --- | --- | --- |
| `--numStages` | `2` | Number of planetary stages |
| `--module` | `2.0` | Gear module (tooth size) |
| `--sunTeeth` | `12` | Sun tooth count |
| `--planetTeeth` | `20` | Planet tooth count |
| `--numPlanets` | `4` | Planets per stage |
| `--gearLength` | `10` | Gear face width in mm |
| `--numElbows` | `0` | `0` = straight, axially assembleable teeth; `>0` = herringbone |
| `--planetBearing` | `FR8-2RS` | Planet bearing; an ISO designation is also accepted |

The default 12/20/52 tooth set gives 5.33:1 per stage (28.4:1 for two stages).
The casing barrel is about 127 mm in diameter, the same as the 7-inch tire's
inner diameter, and the tire sits outboard of the output cap. The bolted joint
flanges are about 143 mm across.

Global options include `--casingWall`, `--carrierThickness`,
`--couplingShaft` (the intermediate 8 mm coupling), `--outputBearing`,
`--outputFree`, `--collarWidth`, `--collarOuter`, `--motorSource`, and
`--motorDeg`. `--noOutputHub` builds a bare output shaft; `--noTire` builds the
gearbox alone. The standard `--detail`, `--package`, `--bom`, `--plan`,
`--explode`, and `--validate` flags are available.

## Tire attachment

The tire is the measured tier-1 wheel envelope with a 1/2" hub bore. Its hub
slides over the 1/2" output shaft after the output-hub collar and is clamped by
a second shaft collar at its outer face. The `tire_mount` mate on the output hub
carries the 90-degree frame rotation that maps the tire's native `+X` wheel
axis onto the gearbox's `+Z` output axis.

The tire model is owner-authored and carries no third-party license, per the
tier-1 repository. All of its dimensions remain parameters in
`@step_motion.tire_spec()`.

## Verification

```sh
./run-example.sh 01 --headless --detail detailed --validate \
  -o /tmp/01.step --urdf /tmp/01.urdf
python3 scripts/validate_step.py --no-mesh /tmp/01.step
```

The printable parts are individually watertight under OCCT tessellation. As
with the other examples, the assembled, kernel-free flat STEP is a nominal
multi-body representation; the build package's `printable/` files are the
authoritative printed solids.
