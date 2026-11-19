# 01 — Motorized wheel (Galileo X wheeled foot)

A compact single-stage (`5.33:1`) motorized wheel built from the
`motorized_gearbox` component, the printed `TIRE-MOUNT-86.3` flange from
[`../moonbit-17-step`](https://github.com/gmlewis/moonbit-17-step), and a
purchased budrash 7-inch wheel.

This package is structured as an importable MoonBit library
(`gmlewis/cad/examples/01_motorized_wheel`) with a thin CLI entrypoint under
`cmd/`. The original two-stage (`28.4:1`) high-torque gearbox configuration is
preserved in `examples/03_hip_joint` and `examples/04_knee_joint`.

```sh
./run-example.sh 01 --headless              # single stage, 5.33:1 (Galileo X foot)
./run-example.sh 01 --numStages 2 --headless
./build-part.sh 1                           # complete print/buy/assemble package
```

## Key features

- **Single-stage `5.33:1` reduction (`--numStages 1`) with A12 8318 100KV:**
  Delivers ~900 RPM no-load (~8.4 m/s theoretical on the 7-inch wheel) and
  ~23.8 N·m rated output torque inside a compact axial package suited for
  Galileo X's calf tips.
- **Twin spaced `FR8-2RS` output bearings:** `MG-OUTPUT-CAP` incorporates a
  revolved bearing turret (`dual_output_bearing=true`) supporting two spaced
  `FR8-2RS` bearings (`22 mm` housing / `25 mm` flange-to-flange) to carry
  cantilevered radial wheel loads without single-bearing wobble.
- **Flush bolted tire mount (`tire_mount_flush=true`):** `TIRE-MOUNT-86.3`
  bolts flush against the 80 mm `MG-OUTPUT-HUB` face (`0 mm` air gap) with
  three `ISO 4762 M4 x 30` screws engaging the three M4 heat-set inserts, while
  two radial `SET-M4x10` screws through radial `INSERT-4` inserts lock the hub
  onto the 12.7 mm steel output shaft.
- **Protective `MG-MOTEUS-SHROUD`:** A bolted rear cover (`4 x M3 x 8` into
  `INSERT-3` housing bosses) shields `moteus C1 r1.2` from ground debris and
  impacts while providing dual 45° cable-exit arches for CAN and power leads.
- **Print-in-place herringbone gear cartridge (`--numElbows 4`):** Prints
  `MG-STAGE1-CARTRIDGE.step` flat on the build plate (`z = 0`) without
  supports; press `FR8-2RS` bearings into the planets from above.

## Verification

```sh
./build-part.sh 1
python3 scripts/validate_step.py --no-mesh build/01/assembly.step
python3 scripts/validate_urdf.py --check-meshes build/01/bundle/urdf/wheel_gearbox_casing.urdf
python3 scripts/check_supplier_links.py build/01
```
