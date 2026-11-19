# Agent Cheatsheet — gmlewis/cad

One page of the names, conventions, and commands an agent needs in this
workspace. The three sibling repos are linked by `moon.work`:

| Repo | Role |
| --- | --- |
| `moonbit-17-step` (`gmlewis/step`) | STEP/AP214 B-Rep kernel, glTF, parametric components, `Sketch2D` |
| `moonbit-18-urdf` (`gmlewis/urdf`) | URDF model/XML, inertia, FK, diagnostics, MJCF |
| `moonbit-19-cad` (`gmlewis/cad`) | Intent tree → STEP/URDF/glTF/BOM/control/build package |

## Conventions

- Units: **millimetres and degrees** at the CAD boundary; URDF and glTF are
  metres/radians (the compilers convert). Masses are kg, torques N·m.
- Axes: **+X forward, +Y left, +Z up**. STEP preserves Z-up; glTF viewers
  rotate the model −90° about X.
- STEP files are authored in the flat/nominal writer. Trimming, fillets, and
  evaluated B-Rep are the SolidCraft/OCCT engine's job (`--eval`,
  `Design::write_step_evaluated()`), not this repo's.
- One `Component` = one intent tree. Keep builders free of CLI concerns; pass
  `@cad.Component` values between examples.
- Write temporary artifacts to `/tmp`; never commit generated STEP/PNG/STL.
- Always pass `--headless` to `run-example.sh`; never raise SolidCraft's GUI.

## Core builders (`@cad`)

```moonbit
@cad.Component::new("base_link", description="...")
  .add_body(@cad.BodyPart::box_mm("block", 40.0, 30.0, 20.0))
  .add_body(@cad.BodyPart::cylinder_mm("boss", 20.0, 8.0, z_mm=10.0))
  .add_body(@cad.BodyPart::tube_mm("bushing", 16.0, 8.0, 6.0))
  .add_body(@cad.BodyPart::extruded_profile_mm("plate", points, 5.0))
  .add_body(@cad.BodyPart::imported_step("vendor_part", step_text))
  .with_part(@cad.PartMeta::new("PLATE-1", process="print", material="PLA"))
```

Mates and joints:

```moonbit
.add_mate_mm_deg("axis", x=10.0, z=20.0, axis=(0.0, 1.0, 0.0))
.attach("arm_joint", parent_mate="axis", child, child_mate="origin",
  spec=@cad.JointSpec::revolute_deg(
    lower_deg=-90.0, upper_deg=15.0, effort=30.0, velocity=10.0))
```

- `JointSpec::fixed()`, `revolute(limit)`, `continuous_limit(effort~, velocity~)`,
  `prismatic(limit)`, `merge_rigid()` (fuses bodies into the parent link).
- `add_loop_constraint(name~, body1~, anchor1~, body2~, anchor2~)` for closed
  chains (URDF extension; MJCF emits `<equality><connect>`).
- `ExplodeSpec::along_mate(distance_mm~)` / `offset_mm(dx~, dy~, dz~)` on
  `attach`; `--package` writes `exploded.step` automatically when any exists.
- Put each mate origin on the physical contact plane so a snap needs no
  offset or twist.

`Sketch2D` (`@step_cad`) for non-box profiles:

```moonbit
let sketch = @step_cad.Sketch2D::rounded_rect(60.0, 40.0, 6.0)
  .with_hole_circle(0.0, 0.0, diam~=8.0)
  .with_bolt_circle(0.0, 0.0, count~=4, bcd~=40.0, hole_diam~=3.4)
  .validate_edge_margins(2.0)   // returns warnings, does not raise
@cad.BodyPart::extruded_sketch_mm(
  "bracket", sketch, @step_cad.Plane::XY, 5.0)
```

`@step_common.MateConnector` carries a mate frame and an optional
`HolePattern` (`BoltCircle`, `BearingSeat`, `SingleBore`); use
`MateConnector::with_hole_pattern` and `Sketch2D::punch_mate_holes`.

Density presets (`@urdf.Density`): `pla`, `petg`, `abs`, `tpu`,
`carbon_fiber`, `cf_nylon`, `aluminum_6061`, `steel_mild`, `steel`, `titanium`,
`brass`, `delrin`, `rubber`, `lipo_battery`, `fr4_pcb`.

## Outputs and CLI

Every example accepts the shared flags (see `examples/common/output.mbt`):

| Flag | Result |
| --- | --- |
| `-o/--out`, `--assembly`, `--assembly-instanced` | STEP variants |
| `--gltf`, `--urdf`, `--bundle <dir>` | glTF, URDF, ROS 2 bundle |
| `--package <dir>` | complete build package (printable parts, BOM, control, `inspect.json`, `assembly.gltf`, `viewer.js`) |
| `--bom`, `--plan`, `--report`, `--control`, `--pins` | CSV/YAML/text outputs |
| `--print-parts <dir>`, `--posed-parts <dir>` | printable and world-posed STEP |
| `--detail simplified\|detailed\|fully-modeled` | geometry detail |
| `--check` | assembly/control/harness/wiring warnings |
| `--analyze` | mass, CoM, inertia, static torque margins |
| `--inspect-json` | JSON summary on stdout (also `inspect.json` in a package) |
| `--collisions` | conservative OBB/AABB overlap audit |

Key package files: `control_params.h` (mass/CoM/inertia, commandable joint
limits, gear ratios, CAN IDs), `lqr_model.py` (same constants plus
`inverted_pendulum_AB()`), `inspect.json` (deterministic machine summary),
`START-HERE.html` (print/buy/assemble guide with an interactive 3D viewer).

Useful commands:

```bash
./test-all.sh
./run-example.sh 08 --headless --check
./run-example.sh 08 --headless --analyze
./run-example.sh 08 --headless --package /tmp/08-package
./build-part.sh 08
python3 scripts/validate_step.py --no-mesh /tmp/08.step
python3 scripts/validate_urdf.py build/08/bundle/urdf/wbr_biped.urdf
python3 scripts/check_interferences.py --parts-dir /tmp/08-posed
python3 scripts/customize_test.py
scripts/new-example.sh 09-demo-arm
./customize.sh 08 --no-open
```

Inspection and rendering:

```bash
solidcraft-cli snapshot --in file.step --out /tmp/view.png --view iso --no-grid
solidcraft-cli eval --in file.step --out /tmp/evaluated.step
scripts/render_views.py build/08
```

`solidcraft-cli snapshot`/`eval` and `mcp__solidcraft__*` run headless. Never
open or activate the SolidCraft GUI from an agent.

## Safety and hygiene

- Never run `./update.sh` (maintainer-only) or `find` on home/toolchain roots.
- Never commit generated artifacts or leave multi-GB build caches.
- Keep source and Markdown files newline-terminated; use `///|` blocks and
  functional style; sort imports and dependencies lexicographically.
- CLI errors: `@cli.eprintln(...)` then `abort("")` (never `println`).
