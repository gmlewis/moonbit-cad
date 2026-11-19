# 03 — Hip joint actuator (2-stage 28.4:1 A12 planetary)

Preserves the two-stage (`28.44:1`) A12 8318 100KV 4-elbow print-in-place
planetary gearbox for high-torque low-speed hip pitch / hip swivel actuation on
Galileo X (`--noTire` output flange hub with twin spaced `FR8-2RS` output
bearings and `MG-MOTEUS-SHROUD`).

This package is structured as an importable MoonBit library
(`gmlewis/cad/examples/03_hip_joint`) with a thin CLI entrypoint under `cmd/`.

```sh
./run-example.sh 03 --headless
./build-part.sh 3
```
