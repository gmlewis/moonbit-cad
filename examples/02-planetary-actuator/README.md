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

## Viewing the design

The assembled `--view` is mechanically correct but hides most purchased parts
inside the housing and gear train. Use the exploded, color-coded view:

```bash
./run-example.sh 02-planetary-actuator --view --explode
```

or open `build/02/exploded.step` from the build package.

The print-in-place sun/planet/ring cartridge moves as **one unit** and is
never split apart. Purchased parts — bearings, motor, board, standoffs,
screws — also keep all their sub-bodies together, so each purchased item
stays identifiable. Every kind of part has its own color:

| Color | Part kind |
| --- | --- |
| near-black | printed housing |
| blue-grey | output cover |
| orange | motor bell |
| gold | sun gear |
| cyan | planet gears |
| grey | ring gear |
| green | carrier |
| silver | 608 bearings |
| steel blue | 688 planet bearings |
| blue / light blue | M3 x 10 / M3 x 12 screws |
| bright brass / dark brass | heat-set inserts / sensor standoffs |
| purple | encoder magnet |
| red / dark red | output collar / set screws |
| grey-blue | moteus C1 board |

## Purchasing links

`supplier-links.txt` maps every purchased part to a real product page. The
example reads it before writing the build package, so `START-HERE.md/.html`,
`sourcing.csv`, and `bom.csv` all carry the links and notes. The file format is:

```
part_number | supplier | supplier_url | notes | unit_cost_usd
```

Notes on the current choices:

- The exact 6 x 2.5 mm **diametrically magnetized** magnet is the mjbots sense
  magnet. CMS Magnetics and Magnet4Sale carry 6 mm discs, but those are
  axially magnetized; their diametric stock starts at other sizes.
- The M3 screws, heat-set inserts, and set screws are inexpensive Amazon kits
  that cover the required lengths with spares.
- The 8 mm carrier shaft and dowel pins start as 8 x 20 mm DIN 6325 hardened
  pins and are cut to length.
- The modeled output collar is a 2 mm spacer; the linked standard collar is
  8 mm wide, so thin it or use a thin clamp collar.
- Prices are per-piece estimates. Kits usually cost more than the summed
  per-piece estimate but include spares.

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
