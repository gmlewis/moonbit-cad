# 11 — Hiwin Guide

A Hiwin HGR15 linear-guideway rail (`HGR15R400`) with an HGH15CA carriage
(`HGH15CA`) seated at a named mate 180 mm along the rail. It exercises the
Hiwin wrappers, their counterbored rail holes and tapped carriage bolt
patterns, and the BOM/sourcing/URDF bundle path.

```bash
# Flat STEP of the assembly
./run-example.sh 11-hiwin-guide --headless --out /tmp/hiwin-guide.step

# Full bundle: BOM, sourcing.csv, START-HERE.html, printable parts, and URDF
./run-example.sh 11-hiwin-guide --headless \
  --bundle /tmp/hiwin-guide-bundle
python3 scripts/validate_urdf.py /tmp/hiwin-guide-bundle/urdf/rail.urdf --check-meshes

# Build package (adds control stubs and a sourcing worksheet)
./run-example.sh 11-hiwin-guide --headless \
  --package /tmp/hiwin-guide-package
```

The rail and carriage are purchased Hiwin parts (`supplier` in the BOM); the
sourcing rows live in `catalog/suppliers.txt`.
