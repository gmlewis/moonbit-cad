#!/usr/bin/env python3
"""Unit and regression tests for scripts/step_to_glb.py.

Guards against:
  1. Silent index-fallback matching when assembly.step and exploded.step were
     generated with different --detail levels or part counts.
  2. Purchased ball bearings breaking apart (outer-ring, inner-ring, and
     ball-* sub-parts receiving different explode vectors).
  3. Retaining washers disappearing or crossing through planets/carrier in the
     build/02 planetary actuator explode metadata.

Usage:
    python3 scripts/step_to_glb_test.py
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))

import step_to_glb  # noqa: E402


class StepToGlbTest(unittest.TestCase):
    def test_rejects_mismatched_leaf_counts(self) -> None:
        asm = [
            {"name": "bearing-688/outer-ring", "center_mm": (20.0, 0.0, 9.0), "color": None},
            {"name": "bearing-688/ball-1", "center_mm": (24.0, 0.0, 9.0), "color": None},
        ]
        exp = [
            {"name": "bearing-688/outer-ring", "center_mm": (20.0, 0.0, 99.0), "color": None},
        ]
        with self.assertRaisesRegex(ValueError, "do not match"):
            step_to_glb._build_explode_metadata(asm, exp, {"nodes": []})

    def test_rejects_mismatched_part_names(self) -> None:
        asm = [
            {"name": "deep-groove-bearing-608/ball-1", "center_mm": (0.0, 0.0, 30.0), "color": None},
        ]
        exp = [
            {"name": "bearing-608/ball-1", "center_mm": (0.0, 0.0, 240.0), "color": None},
        ]
        with self.assertRaisesRegex(ValueError, "no matching part"):
            step_to_glb._build_explode_metadata(asm, exp, {"nodes": []})

    def test_rejects_bearing_breaking_apart(self) -> None:
        asm = [
            {"name": "planet_0_bearing-688/outer-ring", "center_mm": (22.5, 0.0, 9.0), "color": None},
            {"name": "planet_0_bearing-688/inner-ring", "center_mm": (22.5, 0.0, 9.0), "color": None},
            {"name": "planet_0_bearing-688/ball-1", "center_mm": (26.5, 0.0, 9.0), "color": None},
        ]
        # Ball-1 drifts horizontally relative to outer-ring!
        exp = [
            {"name": "planet_0_bearing-688/outer-ring", "center_mm": (22.5, 0.0, 99.0), "color": None},
            {"name": "planet_0_bearing-688/inner-ring", "center_mm": (22.5, 0.0, 99.0), "color": None},
            {"name": "planet_0_bearing-688/ball-1", "center_mm": (10.0, 5.0, 99.0), "color": None},
        ]
        with self.assertRaisesRegex(ValueError, "broke apart"):
            step_to_glb._build_explode_metadata(asm, exp, {"nodes": []})

    def test_rigid_bearing_moves_as_unit(self) -> None:
        asm = [
            {"name": "planet_0_bearing-688/outer-ring", "center_mm": (22.5, 0.0, 9.0), "color": None},
            {"name": "planet_0_bearing-688/inner-ring", "center_mm": (22.5, 0.0, 9.0), "color": None},
            {"name": "planet_0_bearing-688/ball-1", "center_mm": (26.5, 0.0, 9.0), "color": None},
            {"name": "planet_0_bearing-688/ball-2", "center_mm": (18.5, 0.0, 9.0), "color": None},
        ]
        exp = [
            {"name": nm["name"], "center_mm": (nm["center_mm"][0], nm["center_mm"][1], nm["center_mm"][2] + 96.0), "color": None}
            for nm in asm
        ]
        meta = step_to_glb._build_explode_metadata(asm, exp, {"nodes": []})
        for nm in ("outer-ring", "inner-ring", "ball-1", "ball-2"):
            off = meta["parts"][f"planet_0_bearing-688/{nm}"][0]["offset"]
            self.assertEqual(off, [0.0, 0.0, 0.096])

    def test_build_02_explode_integrity(self) -> None:
        exp_json = REPO / "build" / "02" / "explode.json"
        if not exp_json.is_file():
            self.skipTest("build/02/explode.json not built")
        meta = json.loads(exp_json.read_text(encoding="utf-8"))
        parts = meta["parts"]

        # 1. Every part must explode purely coaxially (zero X/Y shear).
        for name, specs in parts.items():
            for spec in specs:
                dx, dy, _dz = spec["offset"]
                self.assertLess(abs(dx), 1e-4, f"{name} has X shear {dx}")
                self.assertLess(abs(dy), 1e-4, f"{name} has Y shear {dy}")

        # 2. Every bearing (608 and 688) must move as a rigid unit.
        bearing_groups: dict[tuple[str, int], list[tuple[str, list[float]]]] = {}
        for name, specs in parts.items():
            if "bearing-" in name and "/" in name:
                prefix = name.rsplit("/", 1)[0]
                for occ, spec in enumerate(specs):
                    bearing_groups.setdefault((prefix, occ), []).append((name, spec["offset"]))
        self.assertGreater(len(bearing_groups), 0, "expected bearings in build/02")
        for (prefix, occ), members in bearing_groups.items():
            ref_nm, ref_off = members[0]
            self.assertGreater(abs(ref_off[2]), 0.05, f"bearing {prefix} did not explode")
            for mem_nm, mem_off in members[1:]:
                self.assertEqual(
                    ref_off,
                    mem_off,
                    f"bearing {prefix} (occ {occ}) split: {ref_nm}={ref_off} vs {mem_nm}={mem_off}",
                )

        # 3. All 4 pin thrust washers must exist and sit strictly between the
        #    688 planet bearings and the carrier plate.
        washer_z = [
            specs[0]["offset"][2]
            for name, specs in parts.items()
            if "pin_washer" in name
        ]
        self.assertEqual(len(washer_z), 4, "expected 4 pin_washers in build/02")
        bearing_688_z = [
            specs[0]["offset"][2]
            for name, specs in parts.items()
            if "bearing-688/outer-ring" in name
        ]
        carrier_z = [
            specs[0]["offset"][2]
            for name, specs in parts.items()
            if "stage1_carrier" in name
            and "pin" not in name
            and "shaft" not in name
            and "screw" not in name
        ]
        self.assertGreater(len(bearing_688_z), 0)
        self.assertGreater(len(carrier_z), 0)
        for wz in washer_z:
            self.assertGreater(wz, max(bearing_688_z), "washer must sit above 688 bearings")
            self.assertLess(wz, min(carrier_z), "washer must sit below carrier plate")

        # 4. Heat-set inserts: 4 top inserts seated near housing top (+20..24 mm)
        #    and explode upward (+14 mm); 4 bottom inserts seated inside the
        #    housing bottom pockets (-38..-34 mm) and explode downward (-18 mm).
        inserts = [
            spec
            for name, specs in parts.items()
            if "HEATSET" in name
            for spec in specs
        ]
        self.assertEqual(len(inserts), 8, "expected 8 HEATSET inserts in build/02")
        top_ins = [s for s in inserts if s["center"][2] > 0.0]
        bot_ins = [s for s in inserts if s["center"][2] < 0.0]
        self.assertEqual(len(top_ins), 4, "expected 4 top HEATSET inserts")
        self.assertEqual(len(bot_ins), 4, "expected 4 bottom HEATSET inserts")
        for s in top_ins:
            self.assertGreater(s["offset"][2], 0.005, f"top insert should explode up: {s}")
        for s in bot_ins:
            self.assertGreater(s["center"][2], -0.040, f"bottom insert seated below motor plate: {s}")
            self.assertLess(s["offset"][2], -0.005, f"bottom insert should explode down: {s}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
