# 01 — Motorized wheel

A proof-of-concept wheel built from the compact multi-stage
`motorized_gearbox` component, the printed `tire_mount` from
[`../moonbit-17-step`](https://github.com/gmlewis/moonbit-17-step), and a
purchased 7-inch wheel.

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
- **The default gear set is print-in-place.** Both stages use the 4-elbow
  herringbone (`--numElbows 4`). The sun and planets interlock with the
  casing's integrated ring and cannot be inserted after printing, following the
  same principle as the example-2 cartridge. Use `--numElbows 0` for straight
  teeth that can be assembled axially.
- **Any number of stages.** Stage 1's sun sits directly on the motor shaft;
  every later stage's sun sits directly on the previous stage's carrier output
  shaft. Every stage parameter is independent.
- **The motor's fixed side is bolted to the casing.** The stator mounts on the
  motor end cap, which is part of the outer casing; the rotor shaft is the only
  moving input.
- **The final carrier is the output interface.** It drives a 1/2" output shaft
  through a flanged bearing in the output cap, and a printed flange hub carries
  both a 40 mm bolt circle and the three-hole, 55.85 mm tire-mount interface. A
  clamp collar retains the hub on the shaft.
- **The moteus C1 r1.2 is the motor controller and the input-shaft sensor.**
  The exact vendor board (`components/vendor/20240305-moteus-c1-r1_2.step`)
  hangs off the back of the motor with its AS5047P facing the rotor magnet, so
  it reads the high-speed rotation of the input (sun) shaft 1:1 for FOC and
  odometry.
- **Flanged planet bearings.** The default planet bearing is a sealed, flanged
  `FR8-2RS` (1/2" x 1 1/8" x 5/16"). Each planet is printed with a counterbore
  sized to the bearing flange; the bearing presses in from the lower face and
  the flange seats flush with the gear face, so the bearing cannot walk out of
  the bore. Bearing pockets are part of the printed gear, and the printed gear
  STEP is exported through OCCT so the pocket is a true counterbore.

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
| `--numElbows` | `4` | `0` = straight, axially assembleable teeth; `>0` = print-in-place herringbone |
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

The wheel is a purchased **budrash 72-107** 7 x 1.5 in wheel (Amazon
[B09XMGXFDN](https://www.amazon.com/dp/B09XMGXFDN), sold as a 2-pack). Its
hard-plastic hub has a 1/2" bore, a 1-3/8" hub length, and a back plate that
already has the right size for the mounting interface.

The 3D-printed `tire_mount` (`@step_motion.measured_tire_mount()`) bolts to
three M4 heat-set inserts in the output hub at a 55.85 mm bolt circle. Its
front plate faces the gearbox, and its 12.7 mm hub post and six rib slots face
outboard into the wheel. The wheel's open, ribbed side faces inboard, so the
ribs seat in the mount's slots and the post centers the hub bore. Drill three
4.5 mm holes through the wheel's plastic back plate at the same 55.85 mm bolt
circle, then secure it with three M4 x 30 socket-head screws that pass through
the wheel and the printed mount into the output-hub inserts.

The output hub is widened to 80 mm so the 55.85 mm bolt circle clears its edge,
and the output shaft is left flush with the hub collar so it cannot protrude
into the tire mount. The old tire collar and shaft-riding arrangement are gone.

The CAD wheel envelope is the owner-authored measured model in
[`../moonbit-17-step`](https://github.com/gmlewis/moonbit-17-step); it carries no
third-party model license. The purchased budrash wheel matches that envelope
(7 x 1.5 in, 1/2 in bore, 1-3/8 in hub). All of its dimensions remain parameters
in `@step_motion.tire_spec()`, and the mount dimensions are parameters in
`@step_motion.tire_mount_spec()`.

## Verification

Every purchased part in the build package's "Buy these parts" table has a
researched supplier link in `supplier-links.txt`; the sourcing workflow and
source list are in `.claude/skills/sourcing-parts/SKILL.md`. `./build-part.sh 1`
runs `scripts/check_supplier_links.py` and warns if a purchased BOM line is
still unlinked.

```sh
./run-example.sh 01 --headless --detail detailed --validate \
  -o /tmp/01.step --urdf /tmp/01.urdf
python3 scripts/validate_step.py --no-mesh /tmp/01.step
```

The printable parts are individually watertight under OCCT tessellation. As
with the other examples, the assembled, kernel-free flat STEP is a nominal
multi-body representation; the build package's `printable/` files are the
authoritative printed solids.
