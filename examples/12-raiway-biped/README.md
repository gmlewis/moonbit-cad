# 12-raiway-biped — Large-Wheeled Bipedal Robot (KAIST RAIWAY-Inspired)

Parametric CAD & URDF model inspired by KAIST RAI Lab's **RAIWAY** large-wheeled
bipedal robot ([video](https://www.youtube.com/watch?v=Ch0divLg64w)), built
around six **A12 8318 100KV** brushless motors with purpose-matched 4-elbow
print-in-place herringbone planetary gearboxes and 20-inch spoked bicycle wheels.

## Exact Dimensions (from `raiway-large-wheel-robot.png`)

| Feature | Dimension |
|---|---|
| Total standing height | `1,140 mm` (`z = 0` to torso top) |
| Vertical electronics torso height | `488 mm` (houses PC, Powerboard, Battery, IMU) |
| Upper leg (thigh + four-bar link) | `320 mm` |
| Lower leg (shin / calf) | `320 mm` |
| Wheel radius / diameter | `254 mm` radius / `Ø508 mm` (20-inch bicycle tire + red foam insert) |
| Wheel track width (center-to-center) | `586 mm` (`y = ±293 mm`) |

## Actuators & Gearboxes (6 × A12 8318 100KV)

- **2 × Hip + 2 × Knee Actuators (coaxial at hip; knee drives shin via 4-bar link):**
  `6.0:1` high-torque 4-elbow herringbone planetary (`m = 2.0 mm`, `12/24/60`,
  `L = 14 mm`) for stair-climbing torque (`150 mm` steps).
- **2 × Wheel Actuators (at lower shin with bolted Wheel Hub adapter):**
  `4.0:1` high-speed, low-inertia 4-elbow herringbone planetary (`m = 2.0 mm`,
  `20/20/60`, `L = 12 mm`, `tire_mount_bcd_mm = 55.85`, same 60-tooth outer
  ring envelope as hip/knee) for fast rolling and
  backdrivable contact-informed blind locomotion.

## Quick Start

```sh
# View standing pose (1,140 mm tall) in SolidCraft
./run-example.sh 12 --view

# View asymmetric 150 mm stair-climbing pose
./run-example.sh 12 --pose stair --view

# Export complete build package (STEP, URDF, BOM, views, printable cartridges)
./build-part.sh 12
```
