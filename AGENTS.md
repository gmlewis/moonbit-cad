# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

## Project Structure

- MoonBit packages are organized per directory, for each directory, there is a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (common, ending in `_test.mbt`) and whitebox test files
  (ending in `_wbtest.mbt`).

- In the toplevel directory, this is a `moon.mod` file listing about the
  module and some meta information.

- **Workspace Preference**: Avoid creating separate `moon.mod` files for
  new examples unless absolutely necessary (e.g., when requiring a large
  dependency like a specific font data package that shouldn't be in the root).
  If an example can run using only root dependencies, keep it as part of the
  main workspace.

## Architectural Principles (CAD Package)

The `cad` package follows an **intent-based architecture**. Do not revert to eager B-Rep generation.

1. **Separation of Intent and Implementation**:
   - `Shape` and `SceneNode` capture *what* the user wants (e.g., "a cube at (10,0,0)").
   - `Design` stores a Scene Graph (`Array[SceneNode]`).
   - Compilation to STEP entities is deferred until `Design::compile()` is called.

2. **Decentralized Compilers**:
   - Each shape has its own compiler (e.g., `compiler_cuboid.mbt`).
   - Compilers take a `StepContext` and return a `@step.Ref` to the generated B-Rep solid.

3. **StepContext & Deduplication**:
   - Use `StepContext` for all repository operations.
   - Always use `ctx.direction()`, `ctx.vector()`, and `ctx.cartesian_point()` to ensure geometric primitives are deduplicated, keeping the STEP file efficient.

4. **Fluent API**:
   - Maintain the builder pattern (`Shape::new().with_name().translate()`).
   - All transformations should return a new `SceneNode` or `Shape` intent, never mutate the repository directly.

5. **The kernel boundary is deliberate — SolidCraft is the CAD engine**:
   - This repository is kernel-free **by design**. It authors intent and exact
     STEP; it does not implement a CAD kernel. **SolidCore / SolidCraft is the
     required engine** for boolean trimming, fillets/chamfers, tessellation,
     interactive edits, and vendor-part repair.
   - The layer boundaries, data flow, and conventions are described in
     [`docs/architecture.md`](docs/architecture.md).
   - `difference()`/`union_all()` concatenate child faces in the flat writer.
     That is the kernel-free nominal representation, **not a defect**. Do not
     "fix" it by attempting real CSG in this repo; resolve it with the engine
     (`--view`, `Design::write_step_evaluated()`, or SolidCraft).
   - A boolean nested inside another boolean contributes no faces and is
     reported as an error by `Design::diagnostics()`.
   - Designs containing a nominal boolean carry a one-line notice in the STEP
     header; `Design::to_step_file_checked()` refuses error designs.
   - **Exact vendor STEP parts:** `@cad.BodyPart::imported_step` (backed by
     `@cad.ImportedStep` in `../moonbit-17-step`) places a static vendor B-Rep
     exactly. The flat writer seeds its repository with the parsed STEP and
     bakes the body's rigid transform into the imported points/directions, and
     rewrites the file's shape-representation placement to the identity so it
     is not applied twice; multiple imported STEP files per design are
     supported (the compiler merges them with disjoint entity ids). URDF,
     collision checks, and the glTF fallback use the imported solid's bounding
     box. This
     is placement, not a kernel: do not expect trimming or repair of imported
     geometry.
   - **Boolean-cut parts need the evaluated solid in assemblies:** the nominal
     flat writer does not trim, so a boolean-cut part (for example a printed
     plate with cutouts) appears solid in assembled/exploded STEP exports.
     Evaluate it with OCCT (`Component::to_step_evaluated()`) and import the
     result with `@cad.BodyPart::imported_step` so the exported STEP carries
     the trimmed solid; see `examples/01_motorized_wheel/main.mbt`. Keep the
     nominal component for the printable/evaluated exports and the evaluated
     solid for the assembly/exploded views.
   - **Mate connectors snap to contact planes:** put each mate's origin on the
     face or end of the feature it represents (a bore's mouth, a shaft's tip, a
     plane's contact face) with zero offset/twist, so `merge_rigid()` or a CAD
     snap with no extra parameters lands the part in its final pose. Offsets,
     twists and re-phased mates at the call site are a smell; fix the mate
     definition instead. Expose mate connectors only on open, user-facing
     mounting interfaces (holes already occupied by assembly screws should model
     the fastener and omit mate connectors), and validate spoked-plate hole
     clearances in 2D so cooling air gaps are not pushed outward by 1D radial
     checks.
   - **Reporting rule:** never present nominal booleans, or the flat writer's
     lack of trimming, as a defect, limitation, caveat, or warning in
     user-facing reports. It is the intended kernel boundary. Mention it only
     when the user explicitly asks about boolean evaluation, or when a feature
     specifically requires trimmed B-Rep, and then name the engine path that
     provides it.

## Coding convention

- All source code and markdown files should end in a newline.

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Prefer **functional-style programming**:
  - Use `map`, `filter`, `fold`, etc., over manual `for i = 0...` loops.
  - For simple iteration, use the idiomatic `for x in array { ... }` or `for i in 0..<n { ... }`.
  - **Range Precedence**: To ensure `moon fmt` doesn't break range logic, use explicit parentheses: `0..<(n - 1)`.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

- Try to keep filenames relatively short and consistent; 30+
  characters in a filename is starting to feel pretty long.

- Please keep `using` statement contents lexicographically sorted for fast
  visual recognition.

- Please keep imports within `moon.pkg` and dependencies within `moon.mod`
  lexicographically sorted.

## Tooling & Verification

- `moon fmt` is used to format your code properly.
- `./test-all.sh`: Blazing fast unit tests and format checks. Run this frequently.
- **Never raise the user's SolidCraft window.** For every example run and every
  validation, pass `--headless` to `run-example.sh` (or call `solidcraft-cli`
  directly). Do not use `--view`, `open -a SolidCraft`, or
  `osascript ... activate`.
- `scripts/validate_step.py <file.step>`: STEP syntax/reference checks, per-shell
  edge topology and orientation, PLANE planarity, OCCT checkshape, and
  watertight tessellation (`--no-mesh` skips tessellation; `--gmsh` adds a
  second mesher).
- `scripts/render_step.py <file.step> <out.png>`: Four-view OCCT preview
  (isometric/top/front/side) composited into one PNG. Requires OCCT `DRAWEXE`,
  Inkscape, and `sips` (macOS) or ImageMagick. Smoke test only — never use it to
  judge whether a model looks right or matches a reference photo; inspect geometry
  in SolidCraft instead (see the `solidcraft-inspect` skill). Agents use the
  headless `mcp__solidcraft__*` tools or `solidcraft-cli snapshot` /
  `solidcraft-cli eval` directly, never open the GUI, and cross-check
  `.connectors.tsv` sidecars against straight-on renders. When matching photos,
  calibrate `px/mm` and overlay candidate contours on a scratch copy first.
  - **macOS Rendering Quirk**: `DRAWEXE` must be called via a STDIN pipe (not a
    script file or `-c`) to properly initialize the Cocoa event loop. It emits
    `.ppm`; the script converts it with `sips` or ImageMagick.
- `scripts/render_solidcraft.py <file.step> <out.png>`: Shaded four-view
  preview using `solidcraft-cli snapshot`, composited with Inkscape. Requires
  SolidCraft and Inkscape. Use as a quick overview only — for defect analysis,
  capture full-resolution multi-angle, zoomed `--camera`, and `--section`
  SolidCraft 3D screenshots directly (`solidcraft-cli snapshot` or
  `mcp__solidcraft__screenshot`) as described in `solidcraft-inspect`.
- `scripts/csg_eval.py <file.step> -o <out.step>`: Evaluates a CSG STEP
  boolean tree into a flat B-Rep through OCCT `DRAWEXE`.
- `scripts/validate_urdf.py <file.urdf>`: URDF structural and physical checks;
  `--check-meshes` also verifies referenced mesh files.
- `./build-part.sh <n>` also runs `scripts/check_supplier_links.py`. Every
  purchased BOM line must have a real supplier and URL in the example's
  `supplier-links.txt`; follow `.claude/skills/sourcing-parts/SKILL.md` when
  filling or refreshing those links.
- `scripts/check_interferences.py --parts-dir <dir>`: exact positive-volume
  overlap between world-posed per-link STEP files, compared solid-by-solid
  (generate them with `--posed-parts <dir>`). Uses OCCT `bcommon`; the component collision package
  is the conservative in-library first pass (`--collisions`).
- Note that an agent should _NEVER_ have to call `./update.sh` as that is used
  by the package maintainer when it is known that external dependencies have been updated.

### Disk usage

Keep the working tree light. `moon` rebuilds quickly, so build caches and
generated artifacts are disposable.

- Do **not** regenerate every example after every change. Validate the changed
  artifact(s) directly, e.g.
  `./run-example.sh 02-planetary-actuator --headless --check`
  followed by `python3 scripts/validate_step.py --no-mesh /tmp/<file>.step`.
  Run the full example matrix only at a meaningful checkpoint or when asked.
- `_build/` (the MoonBit build cache) can grow to gigabytes. Delete it when it
  is large; it is generated and safe to remove. Do not leave multi-gigabyte
  caches or repeated generated copies around.
- Write ad-hoc validation STEP/PNG/STL files to `/tmp`, not into the repository.
  Never commit generated artifacts.
- Do not use OCCT/DRAWEXE tessellation or the evaluated export path unless the
  task needs it; they are the slowest and largest steps.

## Documentation

- Committed Markdown is for end users and agents using the repository, not a
  project journal. Keep it concise, task-focused, and free of progress logs,
  dated change notes, and first-person narratives.
- User documentation lives in `README.md`, `ROADMAP.md`, and `docs/`.
- Development-only reference material lives in the ignored scratch files and is
  not published.

## Error Handling

- **CLI/Main**: Never use `println` for errors. Use `@cli.eprintln("msg")` followed by `abort("")` to ensure non-zero exit codes and proper short-circuiting in shell chains (`&&`).
- **Library**: Use `Result` or `raise` for internal logic errors.
