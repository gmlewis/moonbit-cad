# 09-fox-bot — FOX_BOT Wheeled-Quadruped Active-Suspension Robot

A parametric wheeled-quadruped modeled after **FOX_BOT** (ATTRACLAB), re-engineered around **8× A12 8318 100KV** brushless outrunner motors, **8× 4-elbow print-in-place herringbone planetary gearboxes** (`@components.a12_planetary_actuator`), **4× `TIRE-MOUNT-86.3`** (`@step_motion.measured_tire_mount`), and **4× 7-inch `WHEEL-7IN` budrash tires** (`@step_motion.measured_tire`).

## Architecture Highlights
- **4× Symmetric Closed-Chain 4-Bar Suspension Legs (`LF`, `RF`, `RR`, `LR`):** Solved analytically via `@mechanisms.solve_four_bar(..., upper_branch=true)` with all 4 Pivot `D` loop constraints exported natively into MuJoCo MJCF (`<equality><connect>`).
- **FOX_BOT Differential Mixer & Poses:** `--pose mid | crouched | tall | roll | pitch | pounce | ref`, plus continuous `--rollDeg`, `--pitchDeg`, and `--heave`.
- **Exact FOX_BOT CAN ID Map:** Wheels `1..4` and Hips `5..8` (`LF, RF, RR, LR`), 100 Hz control loop, BNO055 IMU (auto-emitting `<accelerometer>`/`<gyro>` sensors in MJCF), ESP32-S3 (`AT_ZMOAB_ROS`), RPi 5 / Jetson Orin Nano, Intel RealSense D455, and dual 6S LiPo packs.
- **Tolerance-Invariant Print-in-Place Gears:** Switch between `--tolerance 0.042` (1OffManufacturing PETG) and `--tolerance 0.25` (home PLA) without changing outer dimensions or bolt holes.

## Quick Start

```bash
# Build complete package (instanced assembly.step, exploded.step, printable/, URDF, MJCF, views/, START-HERE.html)
./build-part.sh 09

# Analyze mass, CoM, inertia, static joint torque safety margins, and ground contact
./run-example.sh 09 --headless --analyze

# Pose into differential roll, pitch, or forward pounce
./run-example.sh 09 --headless --pose roll --out /tmp/fox-roll.step
./run-example.sh 09 --headless --pose pounce --out /tmp/fox-pounce.step

# Launch interactive parameter customizer
./customize.sh 09

# Simulate closed-chain MJCF in MuJoCo
./scripts/simulate.sh 09 --steps 500 --headless
```
