# gmlewis/cad (MoonBit)

A pluggable parametric CAD and robotics component library for MoonBit.

`gmlewis/cad` unites the exact B-Rep CAD kernel from
[`gmlewis/step`](https://github.com/gmlewis/moonbit-step) with the URDF
kinematics and inertia model from
[`gmlewis/urdf`](https://github.com/gmlewis/moonbit-urdf). One parametric
`Component` tree compiles to a STEP assembly, a glTF scene, a Blender script,
a URDF robot, or a complete ROS 2 package bundle.

## Build a part in one command

```bash
./build-part.sh 02
```

This writes `build/02/` and produces a styled, self-contained
`build/02/START-HERE.html`. Open that page; it has exactly three sections:

1. the STEP files to 3D-print (in `printable/`, with material and infill),
2. the shopping list (quantities, prices, and supplier links),
3. the numbered assembly steps.

Use `./build-part.sh 05` or `./build-part.sh 06` for the other maintained
examples. Nothing is opened on your screen while the package is generated.

To render any Markdown file nicely in your browser:

```bash
./view-md.sh README.md
```

It uses `pandoc` and an embedded stylesheet, so the resulting `.html` is
self-contained and easy to share. Install pandoc once with
`brew install pandoc` if needed.

## Architecture

A **`Component`** is a reusable, parameterized mechanical or robotic module: a
bracket, a bearing, a stepper motor, a planetary gearbox, a leg link, a wheel,
or an entire robot. It contains:

| Field | Purpose |
| --- | --- |
| `parameters : Map[String, String]` | Self-documenting design parameters (`"module": "3.0"`). |
| `bodies : Array[BodyPart]` | Rigid solids with CAD geometry, density, exact inertia, and collision primitives. |
| `mates : Map[String, @urdf.MateConnector]` | Named attachment frames other components snap onto. |
| `attachments : Array[Attachment]` | Child components plus the joint that connects them. |
| `part : PartMeta?` | Purchasing/manufacturing data (part number, supplier and URL, material, process, cost). |
| `ports : Array[Port]` | Typed electrical/mechanical interfaces (power, signal, bus, sensor). |
| `fasteners : Array[Fastener]` | Fastener schedule: thread, length, engagement, quantity, torque, references. |
| `fits : Array[Fit]` | Named fits with a nominal size and allowed min/max range. |
| `actuator : ActuatorSpec?` | Voltage, current, torque, driver, control interface, and encoder for a motor. |
| `sensor : SensorSpec?` | Kind, interface, supply, current draw, range, and resolution for a sensor. |
| `pcb : PcbSpec?` | Board outline, thickness, mounting holes, height limit, and connectors. |
| `wiring : Array[WireRun]` | Point-to-point cable runs with gauge, length, and endpoints. |
| `control : Array[ControlBinding]` | Joint → actuator/channel/pins, direction, gear ratio, soft limits, homing/limit inputs. |
| `cables : Array[CableRoute]` | Routed cable bundles: polyline, jacket diameter, carried wire runs, material. |

A **`BodyPart`** stores both representations of one solid: a
`@step_cad.SceneNode` in millimeters/degrees and a `@urdf.Inertial` in
meters/radians, so CAD and simulation never drift apart.

Mates snap together through **`JointSpec`**:

- `JointSpec::merge_rigid()` folds the child's bodies, collisions, and inertia
  directly into the parent link. No extra URDF `<joint>` is emitted, which is
  how a bolted bracket, stator, or coupler becomes one rigid body.
- `JointSpec::fixed()`, `revolute(limit)`, `continuous(limit?)`, and
  `prismatic(limit)` emit a kinematic `<joint>`, rebase the child link onto its
  chosen mate, and optionally register a `<transmission>` or `<mimic>`.

`Component::attach_to(name, ...)` attaches to a named component anywhere in the
tree, so a load can be snapped onto a motor's nested rotor link.

### Units and origins

- CAD (`@step_cad`) lengths are **millimeters**; rotations are **degrees**
  (`R = Rz * Ry * Rx`).
- URDF (`@urdf`) lengths are **meters**; angles are **radians**; inertia is in
  `kg·m²`.
- URDF `Box` and `Cylinder` geometry is **centered** on its frame. The
  `centered_cuboid_node`, `centered_cylinder_node`, `centered_tube_node`, and
  `centered_extruded_profile_node` bridges make the CAD primitives centered too,
  so local origin, center of mass, and URDF inertia always agree.

### Compilers

| Method | Result |
| --- | --- |
| `comp.compile_links()` | `CompiledLink`s, `@urdf.Joint`s, and `@urdf.Transmission`s. |
| `comp.to_robot()` | Complete `@urdf.Robot` with combined inertials and diagnostics. |
| `comp.to_urdf_bundle()` | ROS 2 bundle: `urdf/<robot>.urdf`, `package.xml`, per-link `.gltf` meshes, and printable `.step` parts. |
| `comp.to_design(joint_positions~)` | Posed `@step_cad.Design` solved through `forward_kinematics`. |
| `comp.to_step_file()`, `to_assembly_step()`, `to_gltf()`, `to_blender_python()` | Posed exports in the requested format. |

## Three-tier architecture

- **Tier 1 — `gmlewis/step/components/*`** — low-level, parametrized STEP
  hardware primitives: ISO fasteners, bearings, shafts, spacers, T-slot
  extrusions, gears, and frames. Every primitive accepts
  `detail~ : DetailLevel` (`Simplified`, `Detailed`, `FullyModeled`) and an
  optional `threads? : ThreadRepresentation` (`None`, `Cosmetic`, `Helical`).
- **Tier 2 — `gmlewis/cad/components`** — reusable robotic and mechatronic
  sub-assemblies that wrap Tier-1 primitives with named mates, URDF
  kinematics, analytical inertia, collision geometry, `PartMeta`, fastener
  schedules, fits, ports, actuator/sensor/PCB specs, wiring, and control
  bindings. Every builder accepts `detail~` (and `threads?` for threaded
  hardware) and forwards it to Tier 1.
- **Tier 3 — `examples/`** — specialized, parameterized, printable, and
  simulatable end-to-end models. Every example accepts `--detail` and
  `--threads` and can emit STEP, glTF, URDF, a ROS 2 bundle, a manufacturing
  package, and standalone printable STEP parts.

## Hardware components

- **`components/hardware`** — ISO 4762/4017/4032/7089/DIN 976 wrappers,
  hex standoffs, spacers, bushings, ball bearings, T-slot extrusions and
  frames, compression springs, shaft couplers, flange plates, L/U brackets, and
  heat-set inserts. Each carries `PartMeta` so it can flow into a bill of
  materials and the printable-part export.
- **`components/actuators`** — NEMA steppers, quasi-direct-drive BLDC actuator
  pods, hub-motor wheels, and the integrated low-KV `planetary_bldc_actuator`
  / `bldc_actuator_pod`. At `Detailed`/`FullyModeled` the low-KV outrunner adds
  rear ventilation louvres, three modeled phase leads and a connector stub, a
  bell flux ring, a keyed output shaft, and an AS5047P-class rotor encoder
  board with a 1 mm magnet gap. Example 02 builds the actuator with heat-set
  inserts in the 6 mm housing wall and a set-screw clamp collar between the
  output bearings.
- **`components/gears`** — a parameterized herringbone planetary gearbox built
  from true involute swept B-Rep gears with mimic-coupled planets and carrier
  (a local port of `moonbit-17-step/examples/38-planetary-gearbox`), plus
  `spur_gear_part` and `planetary_gearset_stage`. The stage wraps the Tier-1
  `planetary_gear_set` assembly and is what example 02 uses; sun, planet, ring,
  and carrier are individually printable. Tier-1 does not yet expose a
  herringbone gearbox component, only the involute planetary assembly.
- **`components/motorized-gearbox`** — a compact multi-stage motorized
  planetary gearbox: each stage's internal ring gear is printed as part of that
  stage's outer casing module, the motor bolts to the casing's end cap, every
  later stage's sun rides directly on the previous carrier's output shaft, and
  the final carrier drives a flanged output shaft plus a 40 mm bolt-circle hub.
  Planet bearings default to flanged, sealed `FR8-2RS` bearings pressed into the
  planets from the lower face; the flange seats flush and prevents the bearing
  sliding through the gear. Example 01 builds a motorized wheel from it.
- **`components/mobility`** — reusable box-tube struts, printable robot leg
  segments with bored proximal hubs, dual spars, lightening ribs, cable clips,
  and a distal motor cup, treaded wheels with a printed rim and chevron/lug
  TPU tread, 4-DOF quadruped legs, and a steerable suspension fork. Every
  quadruped leg joint is a real `planetary_bldc_actuator`: the actuator's motor
  rotor is the commanded joint, its printed carrier is the moving output, and
  the next link bolts to the carrier's output shaft. A reusable
  `joystick_pod` (2-axis Hall stick, E-stop, power button, printed housing)
  serves assistive vehicles. Whole robots live in `examples/05` and
  `examples/06`.
- **`components/grippers`** — a 1-DOF parallel-jaw gripper and a motorized,
  threaded lead-screw gripper (NEMA stepper, exposed screw/nut/rails, matched
  jaws, printable brackets, two limit switches, and a controller PCB).
- **`components/sensors`** — micro limit switches, magnetic encoders, six-axis
  IMUs, camera modules, force sensors, printable sensor-mount brackets, and PCB
  envelopes with mounting holes and optional standoffs.
- **`components/harness`** — polyline cable bundles with jacket diameter,
  carried wire runs, a length-based purchased part number, and jacket geometry.
- **`components/kicad`** — KiCad `.pos` CSV import: board envelope with mounting
  holes, connector placements, and ports.

## Low-KV BLDC and planetary actuators

The component package now builds realistic, inexpensive robotic actuators from
the Tier-1 STEP primitives:

- `bldc_preset` / `bldc_preset_names` — `5010_360kv`, `5008_335kv`,
  `5208_180kv`, `5065_270kv`, and `6354_190kv` outrunners with KV, pole pairs,
  voltage/current, shaft, bearing, mass, and price data.
- `bldc_torque_constant` / `bldc_rated_torque` — `Kt = 8.27 / KV` N·m/A and the
  rated motor torque.
- `low_kv_bldc_motor` — stator with endbell, stack, mounting flange, sensor
  boss, bearings, ventilation louvres, phase leads, and a rotor encoder board;
  out-runner bell, flux ring, a keyed shaft, and sensor magnet on a continuous
  `<name>_rotor_joint`. Phase resistance, thermal resistance, pole count, KV,
  and rated/peak current are carried as design parameters.
- `step_brushless_motor` — the measured Tier-1
  `@step_motors.brushless_motor` outrunner envelope adapted to the same
  two-link stator/rotor contract: the bell and shaft rotate on
  `<name>_rotor_joint`, the stator hub carries the `mount` face, and every
  preset is mapped proportionally. Example 02 uses it in both layouts;
  `low_kv_bldc_motor` remains the default for examples 05/06 and the legacy
  actuator path.
- `planetary_bldc_actuator` — a low-KV motor driving a Tier-1 herringbone or
  exact-arc planetary stage (or two compounded stages), with a printed housing,
  a clamped sun input, 688 planet bearings on steel carrier pins, a two-bearing
  608 output cartridge, an on-axis AS5047P output encoder, and mimic-linked
  gears. The output carrier is a true mimic joint; the output sensor supplies
  absolute joint feedback rather than a second command binding.
- `motorized_gearbox` — the compact, arbitrary-stage alternative used by
  example 01. Stage ring gears are the casing; the default planet bearing is
  the flanged `FR8-2RS`; the motor's fixed side bolts to the casing; and the
  final carrier carries a standard output hub. Every stage parameter is
  independent, and the command input is the motor rotor joint.
- `bldc_actuator_pod` — the preferred factory name for the integrated
  actuator; `qdd_actuator_pod` remains for compatibility.
- `planetary_gearset_stage` — the exposed stage used by example 02's
  `--motor exposed` variant. It prints a ring outer housing by default (the
  exposed variant passes `housing=false`) and carries the overall reduction on
  its carrier joint.
- `planetary_wheel_drive_unit` — a heavy `6354_190kv` two-stage wheel drive for
  the wheelchair, and `caster_fork_assembly` for its front casters. The drive
  extends the carrier's real 8 mm output shaft past the printed cover; the
  wheel hub bore, a 608 hub bearing, and a set-screw clamp collar all match that
  shaft, so the wheel is a closed load path from motor to tyre with no synthetic
  axle frame.
- `joystick_pod` — a reusable two-axis Hall stick with an E-stop and power
  button, a printable housing, and `signal`/`estop`/`power`/`ground` ports.

Examples 01, 02, 05, and 06 use these modules. Example 02 uses the measured
Tier-1 `step_brushless_motor` in both layouts and also accepts `--motor
exposed` for the exposed-stage variant; example 01 uses the compact multi-stage
`motorized_gearbox`; example 05 accepts `--foot` for a rubber-foot quadruped;
example 06 accepts `--layout scooter` for the lighter single-fork vehicle.

## Showcase examples

Each example is a MoonBit executable under `examples/`. Run one by number or
name:

```bash
./run-example.sh 01 --numStages 2 --headless
./run-example.sh 05-galileo-quadruped --bundle /tmp/galileo_bundle
./run-example.sh 06 --out scooter.step --urdf scooter.urdf
```

Every example supports the shared output flags:

- `--detail simplified|detailed|fully-modeled` — geometry detail.
- `--threads none|cosmetic|helical` — thread representation override.
- `--print-parts <dir>` — standalone 3D-printable STEP parts and
  `print-list.csv`, each part in its own local datum frame with purchased
  motors, screws, bearings, and PCBs excluded.
- `--posed-parts <dir>` — world-posed per-link STEP files for exact
  interference analysis.
- `--collisions` — conservative OBB/AABB collision and interference audit.
- `-o`, `--assembly`, `--gltf`, `--blender`, `--urdf`, `--bundle`,
  `--package`, `--bom`, `--control`, `--pins`, and `--check`.

| Example | Description |
| --- | --- |
| `01_motorized_wheel` | Compact multi-stage planetary gearbox whose ring gears are the outer casing, with a 1/2" flanged-bearing planet set, a printed three-hole `tire_mount`, and a 40 mm output bolt circle, driving a purchased budrash 72-107 7-inch wheel. Stage parameters are comma-separated lists (`--numStages 3 --numElbows 0,1,2`). |
| `02-planetary-actuator` | Measured Tier-1 BLDC outrunner (`@step_motors.brushless_motor`) driving a print-in-place, four-elbow, four-planet Tier-1 planetary gearbox — housed with a twin-bearing output cartridge and the moteus C1 on-axis AS5047P sensor, or exposed as a bench/viewing stage. |
| `05-galileo-quadruped` | Wheeled quadruped with a V-slot chassis and four 4-DOF legs; every leg joint is a real low-KV BLDC planetary actuator driving the next printed link from its carrier output shaft. STEP, glTF, URDF, or full ROS 2 bundle. |
| `06-assistive-scooter` | Motorized wheelchair with two-stage planetary rear drives whose wheels bolt to the actuator output shafts, a V-slot frame, seat, armrests, a reusable joystick pod, and front casters (or a steerable fork). Rear and caster tyre bottoms share the `z = 0` ground plane. |

Example 02 vendors and imports the exact moteus C1 r1.2 controller board
(`components/vendor/20240305-moteus-c1-r1_2.step`) as its on-axis
output sensor, © mjbots and the moteus contributors, under the Apache-2.0
license. See
[`examples/02-planetary-actuator/README.md`](examples/02-planetary-actuator/README.md)
for the upstream link, sensor mounting, and attribution.

The Galileo bundle contains `urdf/galileo_quadruped.urdf`, `package.xml`, glTF
meshes, and the printable STEP parts:

```bash
./run-example.sh 05 -- --bundle /tmp/galileo_bundle
python3 scripts/validate_urdf.py --check-meshes \
  /tmp/galileo_bundle/urdf/galileo_quadruped.urdf
```

### Bill of materials and assembly plan

Every example accepts `--bom <file.csv>`, which rolls the component tree up
into aggregated part lines (part number, description, quantity, supplier,
supplier URL, material, process, finish, unit and total cost, notes). Components with their
own `part` are counted as one purchased/assembled item and their bodies are not
double-counted; attachments marked `bom_external=false` (such as a motor's
rotor) stay internal, while bolted-on children are collected. Any body or
fastener without `PartMeta` is reported in an `UNASSIGNED` row rather than
silently dropped.

`--plan <file.txt>` writes the ordered assembly plan derived from the same
tree: each child subassembly is built before it is attached, fasteners are
installed at the step that joins the components they reference, and every step
names its tool (e.g. `2.5 mm hex key`) and torque. `--check` prints warnings
for inconsistent hardware data (engagement longer than the screw, invalid fits,
duplicate names, missing part metadata); example 05 reports zero warnings.

```bash
./run-example.sh 05 --bom 05-bom.csv --plan 05-plan.txt
```

### Power and IO budget

`--report <file.txt>` writes the electrical budget derived from the tree:
actuator ratings (voltage, rated/stall current, torque, driver, control
interface, encoder), per-voltage totals and power, sensor supply/draw/interface,
the full port map, the declared wire runs (endpoints, gauge, length), and the
routed cable bundles (jacket diameter, path length, carried wires).
`Component::wiring_checks()` verifies that every wire and route endpoint
resolves to a declared component and port, that no wire connects a component to
itself, and that each carried wire matches its route's components.

```bash
./run-example.sh 05 --report 05-report.txt
```

Example 05 declares sixteen low-KV BLDC planetary leg joints on CAN, plus the
chassis bus, battery, IMU, and depth camera. Example 06
declares left and right wheelchair drives, two caster swivels and wheels (or a
steering fork), a joystick, IMU, camera, and controller PCB.
`Component::power_budget()` returns the same data programmatically.

### Control export

`--control <file.yaml>` writes a `ros2_control` configuration with a joint-state
broadcaster, a joint trajectory controller, and a hardware section mapping every
bound joint to its actuator, CAN node or STEP/DIR channel, MCU pins, direction,
gear ratio, soft limits, and homing/limit inputs. The same file lists the
declared sensors and their interfaces. `--pins <file.csv>` writes the matching
firmware pin map, and the build package's `firmware.h` carries the same bindings
and sensor tables as C structs for MCU firmware. `Component::control_checks()`
verifies that every commandable joint is bound and that every referenced joint,
actuator, and input resolves.

```bash
./run-example.sh 05 --control 05-control.yaml --pins 05-pins.csv
```

### Build package

`--package <dir>` writes everything needed to source, fabricate, assemble, and
test one example:

| File | Contents |
| --- | --- |
| `README.md` | Manifest: part counts, cost, assembly steps, warnings, file list, validation commands. |
| `bom.csv` | Aggregated bill of materials. |
| `sourcing.csv` | Suppliers, supplier links, quantities, and cost roll-up. |
| `print-list.csv` | Fabricated parts with orientation, layer height, infill, supports, and process notes. |
| `fasteners.csv` | Fastener schedule and torque table. |
| `assembly.txt` | Ordered steps, torque table, electrical checkout, and test sequence. |
| `report.txt` | Power, IO, and wiring budget. |
| `control.yaml`, `pins.csv` | `ros2_control` configuration and firmware pin map. |
| `pcb-connectors.csv` | Imported PCB connector placements (reference, value, footprint, position, side). |
| `link-parts.csv` | Link-to-part map used by the drawing generator. |
| `firmware.h` | C header: joint bindings, gear ratios, limits, pins, and sensors. |
| `assembly.step` | Posed assembly STEP. |
| `bundle/` | URDF, `package.xml`, glTF meshes, and per-link STEP parts. |

```bash
./run-example.sh 05 --package build/05 --check
python3 scripts/validate_step.py --no-mesh build/05/assembly.step
python3 scripts/validate_urdf.py --check-meshes build/05/bundle/urdf/*.urdf
```

### Drawings

`scripts/make_drawings.py` turns a package into formal A3 drawing sheets. For
every fabricated link it exports front, top, right, and isometric DXF views
with SolidCraft (near-orthographic cameras), composes an SVG sheet with a title
block and print settings, converts it to PDF when Inkscape is available, and
writes `drawings/index.md`. The raw DXF views are kept in `drawings/dxf/`.

```bash
python3 scripts/make_drawings.py build/05
# drawings/index.md, <link>.svg, <link>.pdf,
# drawings/dxf/<link>-{front,top,right,iso}.dxf
```

### KiCad PCB import

`parse_kicad_pos()` reads a KiCad position-file CSV and `pcb_from_kicad()`
builds a board envelope with mounting holes, connector placements, ports, and
mounting hardware. The build package then includes `pcb-connectors.csv` with
each connector's reference, value, footprint, position, rotation, and side.
The import is a library API used by a component builder; the placement layer is
imported, and full STEP B-Rep geometry import remains future work.

## Development

```bash
./test-all.sh
```

`test-all.sh` runs `moon fmt`, `moon info`, and `moon test -j 12` across the
workspace. The unit tests cover primitive bridges, component
composition, URDF compilation (including rigid merges), posed STEP export,
bill-of-materials roll-up, assembly plans and hardware checks, power/IO
budgets, cable-route length and wire checks, control export and
joint-completeness checks, forward-kinematics pose smoke tests, build-package
generation (sourcing, print list, torque table, manifest), KiCad placement
import, every component builder at all detail levels, printable-part extraction,
the sensor and harness components, the mimic-coupled gearbox, the real
planetary-actuator quadruped legs, the driven wheelchair wheel, and the
joystick pod. Drawing sheets are generated by `scripts/make_drawings.py` from
a built package.

Validation and rendering helpers live in `scripts/` (they run from a clone of
this repository alone; only the external tools named below are required):

```bash
./run-example.sh 05 --headless --validate                       # STEP + URDF checks
./run-example.sh 05 --headless --bundle build/05 --validate --validate-meshes
python3 scripts/validate_step.py --no-mesh model.step
python3 scripts/validate_urdf.py --check-meshes model.urdf
python3 scripts/check_interferences.py --parts-dir posed/       # exact OCCT link interference
./run-example.sh 05 --headless --detail detailed --posed-parts posed/05
python3 scripts/render_step.py model.step preview.png          # OCCT + Inkscape
python3 scripts/render_solidcraft.py model.step preview-shaded.png  # SolidCraft + Inkscape
python3 scripts/make_drawings.py build/05                      # SolidCraft (+ Inkscape for PDF)
python3 scripts/validate_control.py control.yaml robot.urdf --pins pins.csv  # PyYAML
```

Agents must always pass `--headless` (or call `solidcraft-cli` directly) and
must never use `--view`, `open -a SolidCraft`, or raise the SolidCraft window
while validating.

`render_step.py` uses OCCT `DRAWEXE` (plus `sips` or ImageMagick for PPM
conversion). `render_solidcraft.py` uses `solidcraft-cli snapshot` for shaded
views. Both composite four views into one PNG with Inkscape; without Inkscape
they write the isometric view alone.

## License

Apache-2.0

## Status

The code has been updated to support compiler:

```bash
$ moon version --all
moon 0.1.20261117 (eb64713 2026-11-17) ~/.moon/bin/moon
moonc v0.10.21+06da1ed44 (2026-11-16) ~/.moon/bin/moonc
moonrun 0.1.20261117 (eb64713 2026-11-17) ~/.moon/bin/moonrun

```
