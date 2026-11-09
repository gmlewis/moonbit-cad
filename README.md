# gmlewis/cad (MoonBit)

A pluggable parametric CAD and robotics component library for MoonBit.

`gmlewis/cad` unites the exact B-Rep CAD kernel from
[`gmlewis/step`](https://github.com/gmlewis/moonbit-step) with the URDF
kinematics and inertia model from
[`gmlewis/urdf`](https://github.com/gmlewis/moonbit-urdf). One parametric
`Component` tree compiles to a STEP assembly, a glTF scene, a Blender script,
a URDF robot, or a complete ROS 2 package bundle.

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

## Hardware catalog

- **`catalog/fasteners`** — hex standoffs, cylindrical spacers, ball bearings,
  shaft couplers, flange plates, L brackets, and U brackets, plus a fastener
  catalog of socket-head screws, hex nuts, washers, and heat-set inserts. Each
  carries `PartMeta` so it can flow into a bill of materials.
- **`catalog/actuators`** — NEMA steppers, quasi-direct-drive BLDC actuator pods,
  and hub-motor wheels. Each is a stator/rotor `Component` pair with a joint and
  transmission.
- **`catalog/gears`** — a parameterized herringbone planetary gearbox built from
  true involute swept B-Rep gears, with mimic-coupled planets and carrier.
- **`catalog/mobility`** — box-tube struts, robot leg segments, treaded wheels, a
  17-link wheeled quadruped, and an assistive mobility scooter.
- **`catalog/grippers`** — a 1-DOF parallel-jaw gripper and a motorized,
  threaded lead-screw gripper (NEMA stepper, exposed screw/nut/rails, matched
  jaws, bolt-ready plates, two limit switches, and a controller PCB).
- **`catalog/sensors`** — micro limit switches, magnetic encoders, six-axis
  IMUs, camera modules, force sensors, and PCB envelopes with mounting holes.
- **`catalog/harness`** — polyline cable bundles with jacket diameter, carried
  wire runs, a length-based purchased part number, and jacket geometry.
- **`catalog/kicad`** — KiCad `.pos` CSV import: board envelope with mounting
  holes, connector placements, and ports.

## Showcase examples

Each example is a MoonBit executable under `examples/`. Run one by number or
name:

```bash
./run-example.sh 01 --out bracket.step
./run-example.sh 05-galileo-quadruped --bundle /tmp/galileo_bundle
./run-example.sh 06 --out scooter.step --urdf scooter.urdf
```

| Example | Description |
| --- | --- |
| `01-bracket-assembly` | L bracket with a rigidly merged flange, NEMA stepper, coupler, and bearing. |
| `02-planetary-actuator` | NEMA stepper driving a herringbone planetary gearbox. |
| `03-serial-robot-arm` | Six-axis modular arm: waist yaw, shoulder/elbow pitch, and a pitch-roll-pitch wrist with a motorized lead-screw gripper, two limit switches, and a controller PCB. |
| `04-pan-tilt-turret` | Two-axis gimbal with `MergeRigid` stator mounting and a revolute tilt axis. |
| `05-galileo-quadruped` | Flagship 17-link wheeled quadruped; STEP, glTF, URDF, or full ROS 2 bundle. |
| `06-assistive-scooter` | Rider-parameterized mobility scooter with a steerable front column. |

The Galileo bundle contains `urdf/galileo_quadruped.urdf`, `package.xml`, 17
glTF meshes, and 17 printable STEP parts:

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
duplicate names, missing part metadata); example 03 reports zero warnings.

```bash
./run-example.sh 03 --bom 03-bom.csv --plan 03-plan.txt
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
./run-example.sh 03 --report 03-report.txt
```

Example 03 declares six 48 V QDD joints on CAN, a 24 V NEMA stepper on
STEP/DIR, two 5 V limit switches on GPIO, and a 24 V controller PCB with four
wire runs. `Component::power_budget()` returns the same data programmatically.

### Control export

`--control <file.yaml>` writes a `ros2_control` configuration with a joint-state
broadcaster, a joint trajectory controller, and a hardware section mapping every
bound joint to its actuator, CAN node or STEP/DIR channel, MCU pins, direction,
gear ratio, soft limits, and homing/limit inputs. The same file lists the
declared sensors and their interfaces. `--pins <file.csv>` writes the matching
firmware pin map. `Component::control_checks()` verifies that every commandable
joint is bound and that every referenced joint, actuator, and input resolves.

```bash
./run-example.sh 03 --control 03-control.yaml --pins 03-pins.csv
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
| `assembly.step` | Posed assembly STEP. |
| `bundle/` | URDF, `package.xml`, glTF meshes, and per-link STEP parts. |

```bash
./run-example.sh 03 --package build/03 --check
python3 scripts/validate_step.py --no-mesh build/03/assembly.step
python3 scripts/validate_urdf.py --check-meshes build/03/bundle/urdf/*.urdf
```

### KiCad PCB import

`parse_kicad_pos()` reads a KiCad position-file CSV and `pcb_from_kicad()`
builds a board envelope with mounting holes, connector placements, ports, and
mounting hardware. The build package then includes `pcb-connectors.csv` with
each connector's reference, value, footprint, position, rotation, and side.
Example 03 ships a fixture:

```bash
./run-example.sh 03 \
  --kicadPos examples/03-serial-robot-arm/kicad/gripper.pos \
  --package build/03-kicad --check
```

This imports the placement layer; full STEP B-Rep geometry import remains
future work.

## Development

```bash
./test-all.sh
```

`test-all.sh` formats the root package, regenerates its interface, and runs the
native unit tests. The unit tests cover primitive bridges, component
composition, URDF compilation (including rigid merges), posed STEP export,
bill-of-materials roll-up, assembly plans and hardware checks, power/IO
budgets, cable-route length and wire checks, control export and
joint-completeness checks, forward-kinematics pose smoke tests, build-package
generation (sourcing, print list, torque table, manifest), KiCad placement
import, every catalog component, the sensor and harness catalogs, the
mimic-coupled gearbox, and the 17-link quadruped.

Validation and rendering helpers live in `scripts/` (they run from a clone of
this repository alone; only the external tools named below are required):

```bash
python3 scripts/validate_step.py --no-mesh model.step
python3 scripts/validate_urdf.py --check-meshes model.urdf
python3 scripts/render_step.py model.step preview.png          # OCCT + Inkscape
python3 scripts/render_solidcraft.py model.step preview-shaded.png  # SolidCraft + Inkscape
```

`render_step.py` uses OCCT `DRAWEXE` (plus `sips` or ImageMagick for PPM
conversion). `render_solidcraft.py` uses `solidcraft-cli snapshot` for shaded
views. Both composite four views into one PNG with Inkscape; without Inkscape
they write the isometric view alone.

## License

Apache-2.0
