# 08-wbr-biped — Ascento-Inspired 4-Bar Wheeled Bipedal Robot (A12 + 4-Elbow Planetary)

A parameterized, 3D-printable wheeled bipedal robot (WBR) inspired by the
Ascento / POW EKF+LQR wheeled biped (`https://youtu.be/rpD8mo0Jbuc`), scaled
and engineered around **4× A12 8318 100KV** brushless outrunner motors and
**4-elbow print-in-place herringbone planetary gearboxes**.

## Quick Start

```bash
# Build complete print/buy/assemble package in build/08/
./build-part.sh 08

# Validate URDF bundle with meshes
python3 scripts/validate_urdf.py --check-meshes --package-root build/08/bundle build/08/bundle/urdf/wbr_biped.urdf
```

## Scaling & Customization for DIY Builders

A DIY-er can resize the entire robot with `--scale` or tune individual linkage,
wheel, gearbox, and printer-tolerance parameters without changing the outer
actuator housing dimensions:

```bash
# Compact indoor build (0.85x) for 1OffManufacturing PETG (tol=0.042 mm)
./run-example.sh 08 --headless --release --scale 0.85 --tolerance 0.042 --package /tmp/wbr-compact

# Standard A12 build (1.0x) for home PLA printer (tol=0.25 mm), crouched pose
./run-example.sh 08 --headless --release --tolerance 0.25 --pose crouched --out /tmp/wbr-crouched.step

# Heavy outdoor rover build (1.3x) with taller stance
./run-example.sh 08 --headless --release --scale 1.3 --pose tall --out /tmp/wbr-tall.step

# Exploded, color-coded view
./run-example.sh 08 --headless --release --explode --out /tmp/wbr-exploded.step
```

## Kinematic Architecture

Each leg uses a planar closed-chain 4-bar linkage (`A–B–D–C`):

- **Pivot A (Rear-upper chassis wall):** Actuated by an inboard A12 8318 +
  4-elbow herringbone planetary gearbox (`5.33:1`) driving the curved upper hip
  crank (`WBR-HIP-CRANK`, `L1 = 128 mm * scale`).
- **Pivot C (Forward-lower chassis wall):** Passive `FR8-2RS` bearing pivot
  driving the forward parallel guide rocker (`WBR-GUIDE-LINK`,
  `L3 = 165 mm * scale`).
- **Calf Strut (`WBR-CALF-STRUT`):** Rigid coupler connecting knee pivots `B`
  and `D` (`L2 = 76 mm * scale`) down to the wheel axle `W`
  (`L_calf = 225 mm * scale`), carrying an inboard A12 + 4-elbow planetary
  wheel drive and an outboard 10-spoke wheel (`178 mm * scale`).
