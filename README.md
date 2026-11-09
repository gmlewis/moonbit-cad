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
  shaft couplers, flange plates, L brackets, and U brackets.
- **`catalog/actuators`** — NEMA steppers, quasi-direct-drive BLDC actuator pods,
  and hub-motor wheels. Each is a stator/rotor `Component` pair with a joint and
  transmission.
- **`catalog/gears`** — a parameterized herringbone planetary gearbox built from
  true involute swept B-Rep gears, with mimic-coupled planets and carrier.
- **`catalog/mobility`** — box-tube struts, robot leg segments, treaded wheels, a
  17-link wheeled quadruped, and an assistive mobility scooter.
- **`catalog/grippers`** — a 1-DOF parallel-jaw gripper and a motorized
  lead-screw gripper (NEMA stepper, screw, nut, guide rails, mimic-driven jaw).

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
| `03-serial-robot-arm` | Six-axis modular arm: waist yaw, shoulder/elbow pitch, and a pitch-roll-pitch wrist with a motorized lead-screw parallel-jaw gripper. |
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

## Development

```bash
./test-all.sh
```

`test-all.sh` formats the root package, regenerates its interface, and runs the
native unit tests. The unit tests cover primitive bridges, component
composition, URDF compilation (including rigid merges), posed STEP export,
every catalog component, the mimic-coupled gearbox, and the 17-link quadruped.

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
