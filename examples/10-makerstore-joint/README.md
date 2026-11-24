# 10 — Maker Store Joint

A Maker Store 40 x 40 L plate (`PLATE-40X40L`) with a stack of two metric
aluminum spacers (`SHIM-SPAC`) over its centre hole, assembled through named
`Datum` mates. It exercises the Maker Store wrappers, their mate connectors,
and the BOM/sourcing/URDF bundle path.

```bash
# Flat STEP of the assembly
./run-example.sh 10-makerstore-joint --headless --out /tmp/makerstore-joint.step

# Full bundle: BOM, sourcing.csv, START-HERE.html, printable parts, and URDF
./run-example.sh 10-makerstore-joint --headless \
  --bundle /tmp/makerstore-joint-bundle
python3 scripts/validate_urdf.py /tmp/makerstore-joint-bundle --check-meshes

# Build package (adds control stubs and a sourcing worksheet)
./run-example.sh 10-makerstore-joint --headless \
  --package /tmp/makerstore-joint-package
```

The L plate and spacers are purchased Maker Store USA parts (`supplier` in the
BOM); the sourcing rows live in `catalog/suppliers.txt`.
