---
name: solidcraft-inspect
description: Inspect generated CAD geometry in SolidCraft instead of trusting OCCT/DrawEXE four-view PNGs. Use whenever you need to judge how a part actually looks, when fixing models to match photos or drawings, or before telling the user to run ./run-example.sh <example> --view.
---

# Inspect geometry in SolidCraft, not in four-pane OCCT renders

## The rule

`scripts/render_step.py` and `./run-example.sh <example> --png` produce a
four-view PNG from OCCT `DRAWEXE`. It is a smoke test ("did it render at all?"),
**never** acceptance evidence and never a basis for visual judgments. Its
flat/quad shading hides small defects, edge mismatches, and surface seams, and
misrepresents curved/silhouette detail. Even `render_solidcraft.py` quad-view
composites are too small for fine defect analysis. When you need to judge
whether geometry looks right — silhouette, tooth/edge alignment, window and
slot shapes, feature scale, connector placement, internal bores, color intent —
inspect full-resolution SolidCraft 3D screenshots from multiple camera angles
(`solidcraft-cli snapshot` or `mcp__solidcraft__screenshot`), which render lit,
shaded B-Reps at arbitrary zoom levels.

If the user asks you to "look at" or "fix how it looks", they mean SolidCraft.
Never justify keeping a wrong-looking model because "the 4-pane or quad view looks fine".

## No single-view or quad-view acceptance

An isometric view (or quad isometric composite) is for **orientation only**. It
has poor local contrast on shallow cones/bevels, hides gaps, half-size offsets,
detached layers, sliver faces, and internal bore obstructions, and is the worst
possible basis for a "looks right" judgment.

Never accept, report, or hand off a model after one iso render or a quad view.
The minimum inspection set for any changed part is:

- **Six orthographic views** (`front`, `back`, `left`, `right`, `top`, `bottom`
  or functional equivalents) to expose silhouette, symmetry, hole spacing, and
  gaps.
- **Angled 3/4 views from each functional side**, for lighting/shading contrast
  across sloped faces and fillets.
- **Zoomed close-ups** (`--camera` aimed directly at seams, tooth outer ends,
  chamfers, threads, and layer junctions) of every changed feature.
- **Section cutaways (`--section x=0` / `y=0` / `z=0`)** whenever the part has
  internal bores, sockets, hubs, or fluid passages.
- **A numeric layer-connection check**: use `measure` / `body_topology` and
  confirm adjacent layer bounding boxes actually overlap cleanly with zero
  unintended steps.

If you cannot name the views and close-ups you inspected, you have not inspected the model.

## Who drives SolidCraft

- **You (the agent)**: use the headless `mcp__solidcraft__*` tools **or**
  `solidcraft-cli snapshot` / `solidcraft-cli eval` directly. Do not open or
  raise the GUI, do not use `--view` or `open -a SolidCraft`, and never pretend
  a headless render is what the user sees in their window.
- **The user**: runs `./run-example.sh <example> --view` (or opens the STEP in
  SolidCraft) to review the part interactively. Tell them when the model is
  ready for that; they will orbit and zoom freely.

## Headless inspection recipe (agents)

### Option A — via `mcp__solidcraft__*`

1. Generate the STEP under an allowed root. The headless server refuses other
   paths: use the repo's ignored scratch space (`target/`, or
   `components/examples/output/` in moonbit-17-step). `/tmp` is not allowed.
2. `mcp__solidcraft__open` with `up: "z"` (STEP written by this toolchain is
   Z-up). This **replaces** the in-memory design; check `errors` in the reply
   and note `content_sha256`.
3. `mcp__solidcraft__screenshot` with `source: "model"` and an explicit
   `camera` (`{target, yaw, pitch, distance}`, radians/mm) or a named `view`
   (`iso`, `front`, `top`, ...). Set `grid: false, axes: false` for clean
   images. Pass `path` to keep the PNG under an allowed root.
4. Take several angles, not one: an isometric 3/4 view, straight-on shots of
   every functional face (e.g. prop side and mount side of a motor), and
   close-ups of the changed features. `mcp__solidcraft__screenshot` accepts
   `view` or `camera`; there is no "default good angle", so iterate.
5. Iterate: edit the generator → regenerate → `open` again (the in-memory
   design is replaced) → re-screenshot. A render from a stale open shows the old
   model.
6. Cross-check facts with `inspect_design` / `measure` (bodies, joints) and
   `scripts/validate_step.py` for validity. The render is for looks; the
   validators are the acceptance criteria.

### Option B — via `solidcraft-cli` (when MCP tools are not wired in)

`solidcraft-cli` renders shaded PNGs and inspects geometry headlessly without
opening a window or requiring MCP bindings:

```bash
solidcraft-cli snapshot --in target/part.step --out target/left.png \
  --view left --no-grid --no-axes --width 1024 --height 1024
solidcraft-cli snapshot --in target/part.step --out target/right.png \
  --view right --no-grid --no-axes --width 1024 --height 1024
solidcraft-cli snapshot --in target/part.step --out target/front.png \
  --view front --no-grid --no-axes --width 1024 --height 1024
solidcraft-cli snapshot --in target/part.step --out target/rotor_iso.png \
  --camera '{"target":[12,0,0],"yaw":-2.3,"pitch":0.4,"distance":175}' \
  --no-grid --no-axes --width 1024 --height 1024
solidcraft-cli snapshot --in target/part.step --out target/section.png \
  --view iso --section y=0 --no-grid --no-axes --width 1024 --height 1024
solidcraft-cli eval --in target/part.step
```

Always inspect **both** opposite functional faces (e.g., `left` and `right`
along ±X), the side silhouette (`front`), angled 3/4 views, zoomed close-ups of
changed edges/teeth/seams, and `--section` cutaways for internal bores using
`read_file` on the PNGs, then delete scratch PNGs/STEPs when done.

Notes:

- The GUI app and the headless server are separate processes. Your headless
  screenshots never appear on the user's screen; `source: "window"` only works
  against a connected app and shows *their* tab, so prefer `model` renders.
- The GUI caps open designs (~32); irrelevant headless, but do not open tabs on
  the user's behalf.
- STEP import may warn "imported as an open body"; that is often benign —
  confirm with `scripts/validate_step.py` (OCCT `checkshape` is the authority).
  The validator's optional tessellation watertight check is known to be noisy
  on these parts and may fail on a good model.
- Connector axes/genders are invisible in a render; verify them in the emitted
  sidecar (below) and tests, not by eye.

## Comparing against photos or a golden part

- **Calibrate and overlay before editing.** Never eyeball feature counts, spoke
  widths, or window radii from raw photos alone:
  1. Crop and zoom every reference photo (front, rear, side, and oblique views).
  2. Anchor pixel scale (`px/mm`) on a straight-on photo or an un-foreshortened
     axis using known physical datums (outer OD, standard bearing OD such as
     `6901Z` = 12 × 24 × 6 mm, or known bolt-circle diameters).
  3. Draw concentric millimeter rings, angular protractors, and candidate
     window/slot contours onto a scratch copy of the photo (in `target/` or
     `/tmp/`) and view the overlay image to verify radii and angles to ~0.5 mm /
     ~1° before writing CAD code.
- **Verify pattern symmetry, alternation, and nested rings.** Do not assume all
  spokes or slots are identical or single-ring: check whether spokes alternate
  (e.g., 3 solid + 3 forked/slotted spokes on a 6-spoke rotor bell) and look for
  concentric inner hub slots inside raised bosses in addition to outer cooling
  windows.
- **Check what is visible through air gaps and at perimeters.** Verify that
  windings sit inside pole-shoe tips so stator teeth remain visible, bearing
  rings match standard ODs and metallic finishes, insulator rings sit on the
  correct axial side, and side silhouettes capture stepped mount flanges.
- **Separate open mounting holes from screw-filled holes.** Only open
  user-facing mounting holes expose `MateConnector`s. Holes already occupied by
  retaining screws (such as prop-adapter cap screws) should visibly contain the
  fastener solids and must **not** emit mate connectors.
- **Check spoke-hole clearance in 2D, not 1D.** When mounting holes lie on the
  spokes between cooling windows, they are separated *angularly* from the
  windows. Never enforce a 1D radial inequality (`hole_outer_r < win_inner_r`)
  that forces windows artificially outward and makes spokes overly wide; check
  2D hole-to-sector clearance instead so air gaps can reach inward alongside the
  spokes.
- Fix the silhouette and the largest surfaces first, then medium features
  (windows, plates), then small ones (fasteners, slots, screws).
- Keep changes parametric; derive secondary features (such as spoke fork-slot
  radial bounds) from the spec so scaled-down presets remain valid.
- When the golden reference is itself wrong, keep the standard-correct model
  and record the deviation (see the `compare-golden` skill).

## Connector sidecars

`./run-example.sh <example> --headless` writes `<step>.connectors.tsv` next to
the STEP (name, origin, axis, secondary axis, kind, gender, diameter, depth).
The GUI shows these as named joint origins. After touching connectors, check
the sidecar alongside the straight-on SolidCraft renders: kinds are
`cylindrical-shaft` (male), `cylindrical-bore` (female), `plane-face`
(neutral); axes are outward approach directions (a bore's axis points out of
the bore opening). Verify that hole connectors sit solidly on open mounting
holes or spokes — never inside air gaps or screw-filled counterbores. All
motors and sub-assemblies in this repo follow that convention.

## Avoid tessellation by default

Every new or repaired example, component, and CAD primitive must avoid surface
tessellation whenever an analytic or smooth representation exists (unless an EM
or FEA solver explicitly requires piecewise-linear discretization):

- **Circular cylinders, tubes, bosses, and bores**: use `@cad.Cylinder`,
  `@cad.Cone`, `@cad.RevolvedProfile`, or `@cad.ExtrudedProfile(..., round_bore=...)`
  — never approximate circles or holes as N-gon polylines.
- **Arc bends and elbows**: use `@cad.ToroidalBend` (`TOROIDAL_SURFACE`) or
  `@cad.RevolvedProfile` (`Arc`) — never sweep an N-gon circle along a polyline.
- **2D profiles with circular arcs or corner fillets**: use
  `@cad.ExtrudedArcProfile` with `@cad.ArcSegment::Arc(...)`.
- **Helices, springs, and freeform circular tubes**: use `@cad.SweptProfile`
  with `smooth_sides=true, smooth_profile=true` (or `smooth_helix=true`).

## Acceptance checklist

1. `scripts/validate_step.py <file.step>` passes (checkshape authoritative), and
   the STEP surface inventory uses analytic surfaces or seamless B-splines
   rather than faceted strip faces on curved features.
2. Full-resolution SolidCraft 3D renders show the intended silhouette, feature
   counts, edge alignment, and colors across the full orthographic set, angled
   3/4 views from each side, zoomed close-ups of changed features, and
   `--section` cutaways for internal cavities. Never rely on a quad view or
   single iso render.
3. The user can run `./run-example.sh <example> --view` to review interactively.
4. You report which views, close-ups, and sections you inspected and what you
   changed — never "looks good" without saying how you looked.
