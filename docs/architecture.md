# gmlewis/cad architecture

This document records the target structure for making the examples
mechanically realistic, motorized, sensored, and eventually buildable. It is a
living document: add to it as the layers below gain content.

## Current state

- The module root package `gmlewis/cad` is the **core framework**: shapes,
  scene graph, `Component`, `BodyPart`, `JointSpec`, `Attachment`, primitive
  bridges, and the STEP/URDF compilers.
- `gmlewis/cad/catalog` holds the stock hardware: fasteners, actuators, gears,
  mobility, and grippers. Examples import `@cad` for the framework and
  `@catalog` for hardware.
- Examples are separate executable packages under `examples/`.

## Target layers

| Layer | Contents | Package |
| --- | --- | --- |
| Core | Shapes, scene graph, `Component`, `BodyPart`, mates, joints, transforms, units, compilers | `gmlewis/cad` (root) |
| Mechanical catalog | Structural members, fasteners, bearings, couplers, brackets, mechanisms, grippers | `gmlewis/cad/catalog` |
| Actuation | Motors, drivers, encoders, transmissions, brake/limit hardware | `gmlewis/cad` (`electronics.mbt`) + `catalog/actuators` |
| Sensing | Limit switches, encoders, IMUs, cameras, force sensors | `gmlewis/cad` (`electronics.mbt`) + `catalog/sensors` |
| Electronics | PCB envelopes, connectors, keepouts, wiring/harness | `gmlewis/cad` (`electronics.mbt`); KiCad import future |
| Assembly | BOM, fastener schedules, fits/clearances, assembly steps, part numbers | `gmlewis/cad` (`assembly.mbt`; steps future) |
| Export | STEP/URDF/SDF/glTF, `ros2_control`, firmware pin maps, BOM, build package, drawings | `gmlewis/cad` (`control.mbt`, `assembly.mbt`, `electronics.mbt`, `build.mbt`) + `scripts/make_drawings.py` |

Create a future package only when it has real content; do not add empty
placeholder packages.

## Data model

The current `Component`/`BodyPart` model is geometry + inertia + mates. The
realistic layers add orthogonal records rather than bloating `Component`:

- `PartMeta` — part number, name, supplier, material, process (print/CNC/
  purchased), cost, mass, finish. **Implemented** in `assembly.mbt`.
- `Port` — a typed interface: mechanical mate, electrical port (power, signal,
  bus), fluid/pneumatic, or sensor port; direction and specs. **Implemented.**
- `Fastener` — bolt/screw/insert/washer; thread, length, clearance hole,
  engagement, torque, quantity; references the fastened bodies/mates.
  **Implemented**, with a fastener catalog in `catalog/fasteners.mbt`.
- `Fit` — nominal, clearance, transition, interference; per-face clearance is
  already present in the profile helpers. **Implemented** (`Fit` records).
- `ActuatorSpec` — voltage, current (stall/rated), torque, driver, control
  interface (PWM/STEP-DIR/CAN), encoder type. **Implemented.**
- `SensorSpec` — type, range, resolution, interface, supply, current draw.
  **Implemented**, with builders in `catalog/sensors.mbt`.
- `PcbSpec` / `pcb_board` — outline, thickness, mounting holes, height limit,
  connectors, placements, and bolt-hole mates. **Implemented.**
- KiCad position-file import (`parse_kicad_pos`, `pcb_from_kicad`) — board
  envelope, mounting holes, connector placements, and ports. **Implemented**;
  full STEP B-Rep geometry import remains future.
- `WireRun` — endpoints, gauge, length, notes; collected into the power/IO
  report. **Implemented.**
- `CableRoute` — polyline jacket geometry, diameter, material, and the wire
  runs it carries; checked for length against each wire. **Implemented** in
  `harness.mbt` + `catalog/harness.mbt`. Connector mating is checked by
  `Component::wiring_checks()`.
- `ControlBinding` — joint → actuator channel → MCU pins/bus; direction, gear
  ratio, soft limits, homing/limit inputs. **Implemented**, with
  `ros2_control` YAML, a firmware pin map, and completeness checks.
- `BomLine` — aggregated roll-ups, **implemented** with CSV export.
- `AssemblyStep` — ordered assembly instructions with tools and torque,
  **implemented** (`Component::assembly_plan()`), with consistency checks in
  `Component::assembly_checks()`. Tool-access geometry checks are still future.

These are additive: a `Component` can carry `PartMeta`, `Port`s, and
`ControlBinding`s alongside its bodies and mates.

## Validation ladder

Run these in order; each layer has a check:

1. Geometry and interference (`inspect.interference`; intentional weld
   overlaps are marked, accidental clashes are errors).
2. Mass, centre of mass, and inertia (`measure`, URDF).
3. Joint limits, mimic/transmission consistency, diagnostics (`to_robot`).
4. Power budget per actuator and per bus (`Component::power_budget()`);
   thermal budgeting is still future.
5. Structural check (FEA or hand calculations) at the worst pose.
6. Manufacturing rules: minimum wall, hole sizes, print orientation, CNC radii.
7. Assembly rules: tool access, insertion order, fastener reach.
8. Electrical rules: voltage/current/bus compatibility; connector mate
   (`Component::wiring_checks()`).
9. Control sanity: every commandable joint has a binding; every sensor has an
   input; firmware pin map matches the harness. `Component::control_checks()`
   covers the first two; `scripts/validate_control.py` independently checks the
   URDF, control YAML, and pin map, including soft limits.

## Import/export boundaries

- **Import:** STEP/IGES for purchased parts and PCB envelopes (KiCad export);
  glTF for vendor assets. Do not re-model bought electronics in B-rep.
- **Export:** STEP (mechanical), URDF/SDF (kinematics + inertials), glTF
  (visualization), `ros2_control` (control), BOM (CSV/JSON), firmware pin maps,
  drawings (PDF/DXF), assembly steps.
- The CAD library is the **mechanical/assembly/control hub**, not an ECAD tool.

## Conventions

- CAD lengths in millimeters and degrees; URDF/SI lengths in meters and
  radians; `Component` bridges both.
- Joint axes are expressed in the joint frame (URDF convention); mate frames
  orient the components.
- A `merge_rigid` attachment folds bodies into one link; a revolute/prismatic/
  continuous attachment creates a kinematic joint.
- STEP booleans are nominal in the convenience DSL. Real booleans live in the
  Blender/OCCT paths; for a buildable model, design real material overlaps at
  welds and bolts.
- Intentional weld/bolt overlaps are allowed and should be documented; zero
  clearance contact is not a joint.

## Example levels

- **L0 — kinematic mock-up:** joints and poses only (many current examples).
- **L1 — mechanism-realistic:** real actuator, screw/rack/linkage, guides,
  bearings, fasteners, fits, BOM. *Target for example 3's gripper.*
- **L2 — sensored/electronic:** limit switches, encoder, PCB envelope,
  connectors, power budget.
- **L3 — control-ready:** `ros2_control`/firmware mapping, simulation
  validation, harness list.
- **L4 — buildable:** drawings, print settings, assembly/test procedure,
  suppliers, validated prototype.
