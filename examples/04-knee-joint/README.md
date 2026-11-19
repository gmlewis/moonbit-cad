# 04 — Knee joint actuator (2-stage 28.4:1 A12 planetary)

Preserves the two-stage (`28.44:1`) A12 8318 100KV 4-elbow print-in-place
planetary gearbox for high-torque knee pitch actuation on Galileo X (`--noTire`
output flange hub with twin spaced `FR8-2RS` output bearings and
`MG-MOTEUS-SHROUD`).

This package is structured as an importable MoonBit library
(`gmlewis/cad/examples/04-knee-joint`) with a thin CLI entrypoint under `cmd/`.

```sh
./run-example.sh 04 --headless
./build-part.sh 4
```
