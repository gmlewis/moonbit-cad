///|
/// # `gmlewis/cad`
///
/// A pluggable parametric CAD and robotics component library for MoonBit.
///
/// `gmlewis/cad` joins the exact B-Rep CAD kernel from
/// [`gmlewis/step`](https://github.com/gmlewis/moonbit-step) to the URDF
/// kinematics and inertia model from
/// [`gmlewis/urdf`](https://github.com/gmlewis/moonbit-urdf). One parametric
/// `Component` tree compiles to a STEP assembly, a glTF scene, a Blender
/// script, a URDF robot, or a complete ROS 2 package bundle.
///
/// ## Design model
///
/// A `Component` is a reusable, parameterized mechanical or robotic module: a
/// bracket, bearing, stepper motor, planetary gearbox, leg link, wheel, or an
/// entire robot. It holds:
///
/// | Field | Purpose |
/// | --- | --- |
/// | `parameters : Map[String, String]` | Self-documenting design parameters (`"module": "3.0"`). |
/// | `bodies : Array[BodyPart]` | Rigid solids with CAD geometry, density, exact inertia, and collision primitives. |
/// | `mates : Map[String, @urdf.MateConnector]` | Named attachment frames other components snap onto. |
/// | `attachments : Array[Attachment]` | Child components plus the joint that connects them. |
/// | `part : PartMeta?` | Purchasing/manufacturing data (part number, supplier, material, process, cost). |
/// | `ports : Array[Port]` | Typed electrical/mechanical interfaces (power, signal, bus, sensor). |
/// | `fasteners : Array[Fastener]` | Fastener schedule: thread, length, engagement, quantity, torque, references. |
/// | `fits : Array[Fit]` | Named fits with a nominal size and allowed min/max range. |
/// | `actuator : ActuatorSpec?` | Voltage, current, torque, driver, control interface, and encoder for a motor. |
/// | `sensor : SensorSpec?` | Kind, interface, supply, current draw, range, and resolution for a sensor. |
/// | `pcb : PcbSpec?` | Board outline, thickness, mounting holes, height limit, and connectors. |
/// | `wiring : Array[WireRun]` | Point-to-point cable runs with gauge, length, and endpoints. |
/// | `control : Array[ControlBinding]` | Joint → actuator/channel/pins, direction, gear ratio, soft limits, homing/limit inputs. |
/// | `cables : Array[CableRoute]` | Routed cable bundles: polyline, jacket diameter, carried wire runs, material. |
///
/// A `BodyPart` stores both representations of one solid: a
/// `@step_cad.SceneNode` in millimeters/degrees and a `@urdf.Inertial` in
/// meters/radians, so CAD and simulation never drift apart.
///
/// Components snap together through `JointSpec`:
///
/// - `JointSpec::merge_rigid()` folds the child's bodies, collisions, and
///   inertia directly into the parent link. No extra URDF `<joint>` is
///   emitted, which is how a bolted bracket, stator, or coupler becomes one
///   rigid body.
/// - `JointSpec::fixed()`, `revolute(limit)`, `continuous(limit?)`, and
///   `prismatic(limit)` emit a kinematic `<joint>`, rebase the child link onto
///   its chosen mate, and optionally register a `<transmission>` or `<mimic>`.
///
/// `Component::attach_to(name, ...)` attaches to a named component anywhere in
/// the tree, so a load can be snapped onto a motor's nested rotor link.
///
/// ## Units and origins
///
/// - CAD (`@step_cad`) lengths are **millimeters**; rotations are **degrees**
///   (`R = Rz * Ry * Rx`).
/// - URDF (`@urdf`) lengths are **meters**; angles are **radians**; inertia is
///   in `kg·m²`.
/// - URDF `Box` and `Cylinder` geometry is **centered** on its frame. The
///   `centered_cuboid_node`, `centered_cylinder_node`, `centered_tube_node`,
///   and `centered_extruded_profile_node` bridges make the CAD primitives
///   centered too, so local origin, center of mass, and URDF inertia always
///   agree.
///
/// ## Compilers
///
/// | Method | Result |
/// | --- | --- |
/// | `comp.compile_links()` | `CompiledLink`s, `@urdf.Joint`s, and `@urdf.Transmission`s. |
/// | `comp.to_robot()` | Complete `@urdf.Robot` with combined inertials and diagnostics. |
/// | `comp.to_urdf_bundle()` | ROS 2 bundle: `urdf/<robot>.urdf`, `package.xml`, per-link `.gltf` meshes, and printable `.step` parts. |
/// | `comp.to_design(joint_positions~)` | Posed `@step_cad.Design` solved through `forward_kinematics`. |
/// | `comp.to_step_file()`, `to_assembly_step()`, `to_gltf()`, `to_blender_python()` | Posed exports in the requested format. |
///
/// ## Three-tier architecture
///
/// - **Tier 1** (`gmlewis/step/components/*`) provides parametrized STEP
///   primitives with `DetailLevel` and `ThreadRepresentation`.
/// - **Tier 2** (`gmlewis/cad/components`) wraps those primitives with mates,
///   URDF kinematics, inertia, BOM metadata, ports, wiring, and control.
/// - **Tier 3** (`examples/`) builds specialized printable and simulatable
///   models and exports STEP, glTF, URDF, ROS 2 bundles, and printable parts.
///
/// ## Hardware components
///
/// - `components/hardware` — ISO 4762/4017/4032/7089/DIN 976 wrappers, hex
///   standoffs, cylindrical spacers, bushings, bearings, T-slot extrusions and
///   frames, compression springs, shaft couplers, flange plates, L/U brackets,
///   and heat-set inserts (all with `PartMeta`).
/// - `components/actuators` — NEMA steppers, quasi-direct-drive BLDC actuator
///   pods, and hub-motor wheels. Each is a stator/rotor `Component` pair with a
///   joint and transmission.
/// - `components/gears` — a parameterized herringbone planetary gearbox built from
///   true involute swept B-Rep gears, with mimic-coupled planets and carrier.
/// - `components/mobility` — reusable box-tube struts, printable robot leg
///   segments, treaded wheels, quadruped legs, and a steerable suspension fork.
/// - `components/grippers` — a 1-DOF parallel-jaw gripper and a motorized,
///   threaded lead-screw gripper (exposed screw/nut/rails, matched jaws,
///   bolt-ready plates, limit switches, and a controller PCB).
/// - `components/sensors` — limit switches, magnetic encoders, IMUs, cameras,
///   force sensors, and PCB envelopes with mounting holes.
/// - `components/harness` — polyline cable bundles with jacket geometry, carried
///   wire runs, and a length-based purchased part number.
/// - `components/kicad` — KiCad `.pos` CSV import: board envelope, mounting holes,
///   connector placements, and ports.
///
/// ## Quick start
///
/// ```mbt
/// let bracket = @cad.l_bracket(width_mm=44.0)
/// let stepper = @cad.nema_stepper()
/// let coupler = @cad.shaft_coupler()
/// let assembly = bracket
///   .attach(
///     "stepper_mount",
///     parent_mate="wall_mount",
///     stepper,
///     child_mate="face_mount",
///     spec=@cad.JointSpec::fixed(),
///   )
///   .attach_to(
///     "nema17_rotor",
///     "coupler_mount",
///     parent_mate="shaft_tip",
///     coupler,
///     child_mate="input_shaft",
///     spec=@cad.JointSpec::fixed(),
///   )
///
/// let step_text = assembly.to_step_file()
/// let robot = assembly.to_robot()
/// ```
///
/// ## Bill of materials
///
/// `Component::bom()` aggregates every part once: a component with its own
/// `part` is one purchased/assembled item (its bodies are not double-counted),
/// internal attachments such as a motor rotor are skipped, and external ones
/// are collected. Fastener schedules add their quantities. Any body or
/// fastener without `PartMeta` is counted in `Bom::unassigned` and appears as
/// an `UNASSIGNED` row rather than being silently dropped.
///
/// ```mbt
/// let bom = assembly.bom()
/// let csv = bom.to_csv()
/// let total = bom.total_cost_usd()
/// ```
///
/// `Component::assembly_plan()` derives an ordered build sequence from the
/// same tree (children before the attach step, fasteners at the step that
/// joins their components), and `assembly_plan_text()` renders it with tools
/// and torque. `Component::assembly_checks()` reports inconsistent hardware
/// data such as engagement longer than the screw or an invalid fit range.
///
/// ## Power and IO budget
///
/// Actuators carry an `ActuatorSpec` (voltage, rated/stall current, torque,
/// driver, control interface, encoder), sensors carry a `SensorSpec`, and
/// boards carry a `PcbSpec`. Ports and `WireRun`s declare the electrical
/// interfaces and harness. `CableRoute` adds routed jacket geometry with its
/// carried wire runs, and `Component::harness_checks()` verifies route geometry
/// and that each wire is long enough for its route. `Component::wiring_checks()`
/// resolves every wire and route endpoint to a component and port, rejects
/// self-connections, and confirms each carried wire matches its route. `Component::power_budget()`
/// collects all of it, with per-voltage rated/stall current and power totals,
/// and `PowerBudget::to_text()` renders the actuator, power, sensor, port,
/// wiring, and cable-route report.
///
/// ```mbt
/// let budget = assembly.power_budget()
/// let report = budget.to_text()
/// let same = assembly.report_text()
/// ```
///
/// ## Control export
///
/// `ControlBinding` maps a commandable joint to its actuator, bus channel or
/// MCU pins, direction, gear ratio, soft limits, and homing/limit inputs.
/// `Component::to_ros2_control_yaml()` writes a `ros2_control` configuration
/// (joint-state broadcaster, trajectory controller, hardware parameters, and
/// sensors), `Component::to_pin_map_csv()` writes the matching firmware pin
/// map, and `Component::firmware_header()` writes the same bindings and sensor
/// tables as a C header. `Component::control_checks()` verifies that every commandable robot
/// joint is bound and that every referenced joint, actuator, and input exists.
///
/// ```mbt
/// let yaml = assembly.to_ros2_control_yaml()
/// let pins = assembly.to_pin_map_csv()
/// let warnings = assembly.control_checks()
/// ```
///
/// ## Build package
///
/// `Component::build_package_files()` returns the text files for a complete
/// build package: the manifest, BOM, sourcing with supplier links, print/cut
/// list with process settings, fastener torque table, assembly and test
/// procedure, power/IO report, `ros2_control` configuration, pin map, firmware
/// header, and PCB connector placements. The example CLI's `--package <dir>` also writes the
/// posed assembly STEP and the URDF/glTF/per-link-STEP bundle.
///
/// ```mbt
/// for file in assembly.build_package_files() {
///   write_text_file(file.content, Some(dir + "/" + file.path))
/// }
/// ```
///
/// ## Module map
///
/// | File | Contents |
/// | --- | --- |
/// | `primitives.mbt` | Centered CAD/URDF primitive bridges and `SceneNode` transform helpers. |
/// | `component.mbt` | `BodyPart`, `JointSpec`, `Attachment`, the `Component` AST, and builders. |
/// | `assembly.mbt` | `PartMeta`, `Port`, `Fit`, `Fastener`, assembly plans, and bill-of-materials roll-up/CSV. |
/// | `electronics.mbt` | `ActuatorSpec`, `SensorSpec`, `PcbSpec`, `WireRun`, and the power/IO budget report. |
/// | `control.mbt` | `ControlBinding`, `ros2_control` YAML, firmware pin map, and control-completeness checks. |
/// | `harness.mbt` | `CableRoute` length, tree collection, and harness checks (route geometry and wire reach). |
/// | `build.mbt` | Sourcing, print/cut list, fastener torque table, procedure, build-package manifest, and standalone printable parts. |
/// | `step-bridge.mbt` | `@step_common.Component` → CAD bodies/components, detail/thread parsing, and chamfered-prism flattening. |
/// | `analysis.mbt` | World-posed bodies and the `gmlewis/step/components/collision` interference audit. |
/// | `compile-step.mbt` | `Component` → posed `@step_cad.Design` through forward kinematics. |
/// | `compile-urdf.mbt` | `Component` → `@urdf.Robot` and `@urdf.UrdfBundle` (with real `.gltf` and `.step` assets). |
/// | `components/hardware.mbt` | ISO fasteners, standoffs, bearings, T-slot parts, couplers, and L/U/flange brackets. |
/// | `components/actuators.mbt` | NEMA steppers, BLDC actuator pods, hub motors, and servos. |
/// | `components/gears.mbt` | Herringbone involute planetary gearbox (STEP + mimic URDF). |
/// | `components/mobility.mbt` | Structural tubes, leg segments, wheels, quadruped legs, and suspension fork. |
/// | `components/grippers.mbt` | Parallel-jaw and lead-screw grippers. |
/// | `components/harness.mbt` | Polyline cable-route bundles with jacket geometry and part metadata. |
/// | `components/kicad.mbt` | KiCad position-file parser and PCB envelope builder. |
///
/// ## Booleans are nominal in the STEP backend
///
/// `Shape::difference()` and `Shape::union_all()` concatenate child faces; they
/// do not trim or subtract. Real booleans live in the Blender backend. A
/// boolean nested inside another boolean contributes no faces and is reported
/// as an error by `Design::diagnostics()`; `Design::to_step_file_checked()`
/// refuses such designs.
///
/// ## Examples and tooling
///
/// Runnable programs live under `examples/`. Run one by number or name:
///
/// ```bash
/// ./run-example.sh 01 --out bracket.step
/// ./run-example.sh 05-galileo-quadruped --bundle /tmp/galileo_bundle
/// ```
///
/// Validation and rendering helpers live under `scripts/`:
///
/// ```bash
/// python3 scripts/validate_step.py --no-mesh model.step
/// python3 scripts/validate_urdf.py --check-meshes model.urdf
/// python3 scripts/render_step.py model.step preview.png
/// python3 scripts/render_solidcraft.py model.step preview-shaded.png
/// ```

///|
/// Explicit trait-method promotion declarations for the derived `Eq` and
/// `Debug` implementations, mirroring the sibling `gmlewis/urdf` package.

///|
pub extend ConnectionKind with Debug::{to_repr}

///|
pub extend ConnectionKind with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ConnectionKind with Eq::{not_equal}

///|
pub extend JointSpec with Debug::{to_repr}

///|
pub extend JointSpec with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend JointSpec with Eq::{not_equal}
