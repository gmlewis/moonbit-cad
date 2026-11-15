---
name: sourcing-parts
description: Fill and validate supplier purchase links for every purchased part in a gmlewis/cad build package produced by ./build-part.sh. Use when a BOM has generic or missing suppliers, when adding or changing an example, or before publishing build/<n>/. Preferred sources include Amazon, McMaster-Carr, VXB, BearingsDirect, Digi-Key, Mouser, JLCPCB, PCBWay, AliExpress (US), OnlineMetals, HobbyKing, Pololu, Adafruit, SparkFun, CMS Magnetics, Magnet4Sale, Monster Scooter Parts, ElectricScooterParts, SendCutSend, OSH Cut, MISUMI, SDP/SI, ServoCity, RobotShop, mjbots, ODrive, and eBay.
---

# Sourcing purchase links for a build package

A build package is not finished until its "Buy these parts" section has a
viable link for **every purchased BOM line**. The generated package can answer
what to print from the STEP files; this skill makes it answer what to buy.

## Definition of done

- `build/<n>/bom.csv` has no purchased line with supplier `generic` or an empty
  `supplier_url`.
- `examples/<example>/supplier-links.txt` contains a row for each purchased
  part number, in the format below.
- `./build-part.sh <n>` rebuilds without the missing-link warning.
- `./run-example.sh <n> --headless --detail detailed --package build/<n>` has
  been run after the last change, so `bom.csv`, `sourcing.csv`,
  `START-HERE.md`, and `START-HERE.html` all carry the links.
- `python3 scripts/check_supplier_links.py build/<n>` prints `OK`.

## Workflow

1. Refresh the detailed BOM (the build package uses `--detail detailed`):

   ```bash
   ./run-example.sh <n> --headless --detail detailed --bom /tmp/<n>-bom.csv
   ```

2. List the purchased lines only:

   ```bash
   python3 - <<'PY'
   import csv
   for r in csv.DictReader(open("/tmp/<n>-bom.csv")):
       if r["process"] == "purchased":
           print(r["part_number"], "qty", r["quantity"], r["description"])
   PY
   ```

3. Classify each line and search the preferred sources in the matrix below.
   Use `WebSearch`/`WebFetch`; do not rely on memory for prices or stock.
   Prefer a **direct product page** over a category or search page.

4. Edit `examples/<example>/supplier-links.txt` (create it if missing). Keep
   the exact default-BOM part numbers; lengths and diameters are encoded in
   them, so regenerate the BOM after a design change.

5. Rebuild the package and run the checker:

   ```bash
   ./run-example.sh <n> --headless --detail detailed --package build/<n>
   python3 scripts/check_supplier_links.py build/<n>
   ```

   `./build-part.sh <n>` also runs the checker and prints a warning when links
   are missing.

6. Inspect `build/<n>/START-HERE.html` section 2 (or `sourcing.csv`) and verify
   that each row has a supplier, a URL, a sensible unit cost, and a note that
   explains kits, substitutions, and cut-to-length operations.

## File format

`examples/<example>/supplier-links.txt` is pipe-separated. Blank lines and
lines starting with `#` are ignored; the example applies it before writing the
package, so `bom.csv`, `sourcing.csv`, and `START-HERE` all use it.

```text
part_number | supplier | supplier_url | notes | unit_cost_usd
```

- `part_number` must match the BOM exactly (`ISO4762-M3x10.0`,
  `BEARING-FR8-2RS`, `SHAFT-12.7x45.9`, ...).
- `supplier` is the shop name (`McMaster-Carr`, `Amazon`, `VXB`, `Digi-Key`,
  ...). Do not leave it `generic` for a linked part.
- `supplier_url` is the product page. Use the canonical product URL.
- `notes` explains kit coverage, the closest stocked size, cut-to-length, or a
  second source for a hard-to-find item.
- `unit_cost_usd` is per piece. Kits include spares; the cart total may differ
  from the estimate. Update it to a realistic current price.

## Source matrix

| What | Preferred sources | Notes |
| --- | --- | --- |
| M3/M4/M5 screws, set screws, heat-set inserts, standoffs | Amazon assortment kits; McMaster-Carr; AliExpress (US) | A single labeled kit often covers several BOM lines. Note the kit coverage and per-piece cost. |
| Ball bearings | **VXB (vxb.com)**, BearingsDirect, Amazon 10-packs, McMaster-Carr | Verify bore x OD x width and flange/seal type. VXB is a good specialist source; Amazon 10-packs are often cheapest when a design needs many identical bearings. |
| Shafts, rods, dowel pins | McMaster-Carr, OnlineMetals; SendCutSend / OSH Cut for plates | Buy stock and cut to length, or a standard pin slightly longer than modeled. Note the tolerance and the cut operation. |
| BLDC motors, ESCs, hubs | HobbyKing, Amazon, GetFPV, AliExpress (US) | Match KV, shaft diameter, mounting bolt circle, and body length. |
| Encoders, ICs, connectors, breakouts | Digi-Key, Mouser, Pololu, Adafruit, SparkFun | Prefer a named board with a datasheet. Note if an evaluation board includes the magnet. |
| Custom PCBs / assembly | JLCPCB, PCBWay, OSH Park (small US runs) | Link the fabrication service, not a specific order; record the board revision in notes. |
| Magnets | CMS Magnetics, Magnet4Sale, mjbots | The owner has done business with CMS Magnetics and Magnet4Sale. Check axial vs diametric magnetization. |
| Tires, wheels, casters | Amazon, Monster Scooter Parts, ElectricScooterParts | Match OD, width, hub bore, hub length, and offset. Consumer scooter wheels often use 8/10/12 mm bearings, not 1/2 in. |
| Extrusion, frames, enclosures | 80/20, McMaster-Carr, SendCutSend | Note the profile and cut length. |
| Precision mechanics, gears, pulleys | MISUMI, SDP/SI, KHK, QTC Gears | Use when a printed or catalog part needs a precise bore/pitch. |
| Robotics hardware, controllers | ServoCity, RobotShop, mjbots, ODrive, VESC suppliers | Prefer the manufacturer's own store for firmware-matched electronics. |
| Obsolete or odd lots | eBay | Last resort; note condition, quantity, and return policy. |

## Hard rules

- **Never invent a URL.** Search, open the product page when possible, and
  confirm the dimensions, thread, bore, length, KV, or board revision.
- Prefer a direct product page. If only a category page exists, say so in the
  note and give the exact filter values.
- Prefer inexpensive kits for small hardware, but name the kit contents and
  what it covers. Do not hide a $20 kit behind a $0.05 per-piece estimate.
- If the exact size is not stocked, link the closest standard part and state
  the modification: cut to length, grind, ream, or use a thin spacer.
- Do not link affiliate or referral URLs. Use manufacturer, distributor, or
  reputable retailer pages.
- Keep the link file for the **default** build. If a parameter changes a part
  number (shaft length, motor preset, bearing designation), regenerate the BOM
  and update or add the row.
- In-house printed parts (`3D print`) do not need purchase links. Do not add
  rows for them.
- For custom shafts/pins, link the stock or a standard pin and note the cut.
  For custom PCBs, link the board house and record the revision.

## Checker

`scripts/check_supplier_links.py` reads a build directory or a `bom.csv` and
fails when a purchased line lacks a supplier or URL:

```bash
python3 scripts/check_supplier_links.py build/01
python3 scripts/check_supplier_links.py build/01/bom.csv
```

`build-part.sh` calls it automatically and prints a warning (not an error).
The script uses only the Python standard library and never accesses the
network.

## Worked examples

Example 02 (`examples/02-planetary-actuator/supplier-links.txt`) established
the kit strategy: an M3 socket-head kit covers several lengths, an M3 grub
screw kit covers the set screws, an M3 heat-set kit covers the inserts, and
McMaster supplies the dowel pins, shims, and collar. The diametric magnet came
from mjbots because CMS Magnetics and Magnet4Sale only stocked axial discs at
the required size.

Example 01 (`examples/01_motorized_wheel/supplier-links.txt`) shows the
current pattern:

| Part | Source | Why |
| --- | --- | --- |
| `BEARING-FR8-2RS` | Amazon 10-pack; VXB alternative | 9 identical bearings; VXB is the specialist source for the exact flanged bearing |
| `BLDC-5010_360kv` | Amazon (GoolRC) | 5010 360KV, 4 mm shaft, 19 mm bolt circle |
| `ENC-AS5047P` | Digi-Key | AS5047P adapter/evaluation board with the diametric magnet |
| `SHAFT-8.0x31.0` | McMaster-Carr | 8 mm 303 rotary shaft, cut to length |
| `SHAFT-12.7x45.9` | OnlineMetals | 1/2 in 303 rod, cut to length |
| `COLLAR-12.7-25.4` | McMaster-Carr | 1/2 in bore x 1 in OD x 7/16 in wide set-screw collar |
| `WHEEL-7IN` | Amazon | budrash 72-107 7 x 1.5 in wheel, 2-pack, 1/2 in bore, 1-3/8 in hub; 3 holes drilled for the printed tire mount (ASIN B09XMGXFDN) |
| `TIRE-MOUNT-86.3` | 3D print | Printed adapter; the purchased wheel's plastic hub is drilled to its 55.85 mm M4 bolt circle |
| `INSERT-4` / `ISO4762-M4x40` | Amazon | M4 heat-set insert kit and M4 x 40 mm socket-head screws for the three-hole tire mount |
| M3/M4 screws, inserts, set screws | Amazon kits | One or two labeled kits cover the whole fastener schedule |

Always re-verify links and prices before publishing; product pages and stock
change. The notes are part of the deliverable, not an afterthought.
