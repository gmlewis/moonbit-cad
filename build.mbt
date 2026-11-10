///|
/// Build-package generation: sourcing, a print/cut list, a fastener torque
/// table, an assembly and test procedure, and a manifest.
///
/// The CLI writes these files plus the STEP/glTF/URDF bundle for one example,
/// giving a third party everything needed to source, fabricate, assemble, and
/// test it.

///|
/// One file in a generated build package.
pub(all) struct BuildFile {
  path : String
  content : String
}

///|
pub fn BuildFile::new(path : String, content : String) -> BuildFile {
  { path, content, }
}

///|
fn fastener_kind_name(kind : FastenerKind) -> String {
  match kind {
    Bolt => "bolt"
    Screw => "screw"
    Nut => "nut"
    Washer => "washer"
    Insert => "insert"
  }
}

///|
fn Component::collect_fasteners(
  self : Component,
  path : String,
  rows : Array[(String, Fastener)],
) -> Unit {
  for fastener in self.fasteners {
    rows.push((path, fastener))
  }
  for att in self.attachments {
    att.child.collect_fasteners(path + "/" + att.child.name, rows)
  }
}

///|
/// Sourcing lines derived from the BOM, including supplier links and cost.
pub fn Component::sourcing_csv(self : Component) -> String {
  let header : Array[String] = [
    "part_number", "description", "quantity", "supplier", "supplier_url", "unit_cost_usd",
    "total_cost_usd",
  ]
  let rows : Array[String] = [csv_row(header.map(fn(v) { csv_field(v) }))]
  for line in self.bom().lines {
    rows.push(
      csv_row([
        csv_field(line.part_number),
        csv_field(line.description),
        line.quantity.to_string(),
        csv_field(line.supplier),
        csv_field(line.supplier_url),
        csv_field(line.unit_cost_usd.to_string()),
        csv_field(line.total_cost_usd.to_string()),
      ]),
    )
  }
  rows.fold(init="", fn(acc, row) { acc + row + "\n" })
}

///|
fn print_orientation(line : BomLine) -> String {
  if line.process.contains("print") {
    if line.part_number.contains("GEAR") ||
      line.part_number.contains("PGB") ||
      line.part_number.contains("CARRIER") {
      "flat face down, teeth vertical"
    } else {
      "largest flat face down"
    }
  } else if line.process.contains("CNC") {
    "as modeled, datum faces down"
  } else if line.process.contains("cut") {
    "lay flat for cutting"
  } else {
    "as modeled"
  }
}

///|
fn print_layer_height(line : BomLine) -> String {
  if line.process.contains("print") {
    "0.20"
  } else {
    ""
  }
}

///|
fn print_infill(line : BomLine) -> String {
  if !line.process.contains("print") {
    return ""
  }
  if line.material.contains("TPU") {
    "100"
  } else if line.part_number.contains("GEAR") ||
    line.part_number.contains("PGB") ||
    line.part_number.contains("CARRIER") {
    "40"
  } else {
    "20"
  }
}

///|
fn print_support(line : BomLine) -> String {
  if line.process.contains("print") {
    "tree if overhang > 45 deg"
  } else {
    ""
  }
}

///|
fn manufacturing_notes(line : BomLine) -> String {
  if line.process.contains("print") {
    "0.4 mm nozzle; dry filament"
  } else if line.process.contains("CNC") {
    "3-axis mill; deburr edges"
  } else if line.process.contains("cut/weld") {
    "weld; stress relieve"
  } else if line.process.contains("cut") {
    "cut to length; deburr"
  } else if line.process.contains("assembly") {
    "inspect and program before install"
  } else {
    ""
  }
}

///|
/// Manufactured (non-purchased) parts with print/cut settings.
pub fn Component::print_list_csv(self : Component) -> String {
  let header : Array[String] = [
    "part_number", "description", "quantity", "material", "process", "orientation",
    "layer_height_mm", "infill_percent", "support", "notes",
  ]
  let rows : Array[String] = [csv_row(header.map(fn(v) { csv_field(v) }))]
  for line in self.bom().lines {
    if line.process != "purchased" {
      rows.push(
        csv_row([
          csv_field(line.part_number),
          csv_field(line.description),
          line.quantity.to_string(),
          csv_field(line.material),
          csv_field(line.process),
          csv_field(print_orientation(line)),
          csv_field(print_layer_height(line)),
          csv_field(print_infill(line)),
          csv_field(print_support(line)),
          csv_field(manufacturing_notes(line)),
        ]),
      )
    }
  }
  rows.fold(init="", fn(acc, row) { acc + row + "\n" })
}

///|
/// The fastener schedule with torque, one row per component entry.
pub fn Component::fastener_table_csv(self : Component) -> String {
  let header : Array[String] = [
    "component", "name", "kind", "thread", "length_mm", "engagement_mm", "quantity",
    "torque_nm", "references", "part_number",
  ]
  let rows : Array[String] = [csv_row(header.map(fn(v) { csv_field(v) }))]
  let entries : Array[(String, Fastener)] = []
  self.collect_fasteners(self.name, entries)
  for entry in entries {
    let path = entry.0
    let fastener = entry.1
    let part_number = match fastener.part {
      Some(part) => part.part_number
      None => ""
    }
    rows.push(
      csv_row([
        csv_field(leaf_name(path)),
        csv_field(fastener.name),
        csv_field(fastener_kind_name(fastener.kind)),
        csv_field(fastener.thread),
        csv_field(fastener.length_mm.to_string()),
        csv_field(fastener.engagement_mm.to_string()),
        fastener.quantity.to_string(),
        csv_field(fastener.torque_nm.to_string()),
        csv_field(array_join(fastener.references, "; ")),
        csv_field(part_number),
      ]),
    )
  }
  rows.fold(init="", fn(acc, row) { acc + row + "\n" })
}

///|
fn Component::fastener_entry_count(self : Component) -> Int32 {
  let entries : Array[(String, Fastener)] = []
  self.collect_fasteners(self.name, entries)
  entries.length()
}

///|
fn Component::fastener_table_text(self : Component) -> String {
  let entries : Array[(String, Fastener)] = []
  self.collect_fasteners(self.name, entries)
  if entries.length() == 0 {
    return "(none)\n"
  }
  entries.fold(init="", fn(acc, entry) {
    let path = entry.0
    let fastener = entry.1
    acc +
    leaf_name(path) +
    " | " +
    fastener.name +
    " | " +
    fastener.quantity.to_string() +
    " x " +
    fastener.thread +
    " x " +
    fastener.length_mm.to_string() +
    " mm | " +
    fastener.torque_nm.to_string() +
    " N·m | " +
    array_join(fastener.references, "; ") +
    "\n"
  })
}

///|
/// Assembly, torque, electrical-checkout, and test procedure.
pub fn Component::build_procedure_text(self : Component) -> String {
  let mut out = "Assembly and test procedure\n===========================\n\n"
  out = out + self.assembly_plan_text()
  out = out + "\nFastener torque table\n---------------------\n"
  out = out + self.fastener_table_text()
  out = out + "\nElectrical checkout\n-------------------\n"
  for binding in self.control_bindings() {
    out = out +
      binding.joint +
      ": actuator " +
      binding.actuator +
      ", channel " +
      binding.channel +
      ", gear " +
      binding.gear_ratio.to_string() +
      ":1"
    if binding.mcu_pins != "" {
      out = out + ", pins " + binding.mcu_pins
    }
    match binding.homing_input {
      Some(input) => out = out + ", home with " + input
      None => ()
    }
    match binding.limit_input {
      Some(input) => out = out + ", limit " + input
      None => ()
    }
    out = out + "\n"
  }
  let sensors = self.power_budget().sensors
  for line in sensors {
    out = out +
      leaf_name(line.path) +
      ": " +
      sensor_kind_name(line.spec.kind) +
      ", " +
      line.spec.interface +
      ", " +
      line.spec.voltage_v.to_string() +
      " V, " +
      line.spec.current_ma.to_string() +
      " mA\n"
  }
  out = out + "\nTest sequence\n-------------\n"
  out = out +
    "1. Verify every joint moves in its commanded direction; reverse\n"
  out = out + "   direction in control.yaml if it does not.\n"
  out = out +
    "2. Home each joint that declares a homing input, then verify the\n"
  out = out + "   far-end limit and the soft limits.\n"
  out = out +
    "3. Confirm mimic joints follow their driver (the gripper jaw travel\n"
  out = out + "   follows the motor lead).\n"
  out = out +
    "4. Run the power/IO report and confirm each bus stays within the\n"
  out = out + "   rated current totals.\n"
  out
}

///|
fn Component::collect_link_parts(
  self : Component,
  rows : Array[(String, String, Int32, Bool)],
) -> Unit {
  let part_numbers : Array[String] = []
  let mut fabricated = false
  match self.part {
    Some(part) => {
      part_numbers.push(part.part_number)
      if part.process != "purchased" {
        fabricated = true
      }
    }
    None => ()
  }
  for body in self.bodies {
    match body.part {
      Some(part) =>
        if !array_has(part_numbers, part.part_number) {
          part_numbers.push(part.part_number)
          if part.process != "purchased" {
            fabricated = true
          }
        }
      None => ()
    }
  }
  rows.push(
    (
      self.name,
      array_join(part_numbers, "; "),
      self.bodies.length(),
      fabricated,
    ),
  )
  for att in self.attachments {
    att.child.collect_link_parts(rows)
  }
}

///|
/// Maps each exportable link (component) to the BOM part numbers of its bodies.
pub fn Component::link_parts_csv(self : Component) -> String {
  let header : Array[String] = [
    "link", "part_numbers", "body_count", "fabricated",
  ]
  let rows : Array[String] = [csv_row(header.map(fn(v) { csv_field(v) }))]
  let entries : Array[(String, String, Int32, Bool)] = []
  self.collect_link_parts(entries)
  for entry in entries {
    rows.push(
      csv_row([
        csv_field(entry.0),
        csv_field(entry.1),
        entry.2.to_string(),
        csv_field(if entry.3 { "true" } else { "false" }),
      ]),
    )
  }
  rows.fold(init="", fn(acc, row) { acc + row + "\n" })
}

///|
fn Component::collect_pcb_specs(
  self : Component,
  path : String,
  rows : Array[(String, PcbSpec)],
) -> Unit {
  match self.pcb {
    Some(spec) => rows.push((path, spec))
    None => ()
  }
  for att in self.attachments {
    att.child.collect_pcb_specs(path + "/" + att.child.name, rows)
  }
}

///|
fn Component::pcb_placement_count(self : Component) -> Int32 {
  let rows : Array[(String, PcbSpec)] = []
  self.collect_pcb_specs(self.name, rows)
  let mut count = 0
  for entry in rows {
    count = count + entry.1.placements.length()
  }
  count
}

///|
/// KiCad/PCB placement map: one row per imported connector placement.
pub fn Component::pcb_placements_csv(self : Component) -> String {
  let header : Array[String] = [
    "component", "reference", "value", "footprint", "x_mm", "y_mm", "rotation_deg",
    "side",
  ]
  let rows : Array[String] = [csv_row(header.map(fn(v) { csv_field(v) }))]
  let specs : Array[(String, PcbSpec)] = []
  self.collect_pcb_specs(self.name, specs)
  for entry in specs {
    for placement in entry.1.placements {
      rows.push(
        csv_row([
          csv_field(leaf_name(entry.0)),
          csv_field(placement.reference),
          csv_field(placement.value),
          csv_field(placement.footprint),
          csv_field(placement.x_mm.to_string()),
          csv_field(placement.y_mm.to_string()),
          csv_field(placement.rotation_deg.to_string()),
          csv_field(placement.side),
        ]),
      )
    }
  }
  rows.fold(init="", fn(acc, row) { acc + row + "\n" })
}

///|
/// The package manifest: part counts, cost, step count, warnings, and files.
pub fn Component::build_manifest(
  self : Component,
  name~ : String = "",
) -> String {
  let package_name = if name == "" { self.display_name() } else { name }
  let bom = self.bom()
  let mut fabricated = 0
  let mut purchased = 0
  for line in bom.lines {
    if line.process == "purchased" {
      purchased = purchased + 1
    } else {
      fabricated = fabricated + 1
    }
  }
  let assembly_warnings = self.assembly_checks()
  let control_warnings = self.control_checks()
  let harness_warnings = self.harness_checks()
  let wiring_warnings = self.wiring_checks()
  let mut out = "# Build package: " + package_name + "\n\n"
  out = out + "Generated by gmlewis/cad.\n\n"
  out = out + "| Metric | Value |\n| --- | --- |\n"
  out = out + "| BOM lines | " + bom.lines.length().to_string() + " |\n"
  out = out + "| Fabricated parts | " + fabricated.to_string() + " |\n"
  out = out + "| Purchased parts | " + purchased.to_string() + " |\n"
  out = out +
    "| Estimated cost | $" +
    round2(bom.total_cost_usd()).to_string() +
    " |\n"
  out = out +
    "| Assembly steps | " +
    self.assembly_plan().length().to_string() +
    " |\n"
  out = out +
    "| Fastener entries | " +
    self.fastener_entry_count().to_string() +
    " |\n"
  out = out +
    "| Control bindings | " +
    self.control_bindings().length().to_string() +
    " |\n"
  out = out +
    "| Sensors | " +
    self.power_budget().sensors.length().to_string() +
    " |\n"
  out = out +
    "| Cable routes | " +
    self.cable_routes().length().to_string() +
    " |\n"
  out = out +
    "| Wire runs | " +
    self.power_budget().wires.length().to_string() +
    " |\n"
  out = out +
    "| PCB placements | " +
    self.pcb_placement_count().to_string() +
    " |\n"
  out = out +
    "| Hardware warnings | " +
    (assembly_warnings.length() +
    control_warnings.length() +
    harness_warnings.length() +
    wiring_warnings.length()).to_string() +
    " |\n"
  out = out + "\n## Files\n\n"
  out = out + "| File | Contents |\n| --- | --- |\n"
  out = out + "| `bom.csv` | Aggregated bill of materials. |\n"
  out = out + "| `sourcing.csv` | Suppliers, links, quantities, and costs. |\n"
  out = out +
    "| `print-list.csv` | Fabricated parts with print/cut settings. |\n"
  out = out + "| `fasteners.csv` | Fastener schedule and torque table. |\n"
  out = out +
    "| `assembly.txt` | Ordered assembly, torque, and test procedure. |\n"
  out = out + "| `report.txt` | Power, IO, and wiring budget. |\n"
  out = out + "| `control.yaml` | `ros2_control` configuration. |\n"
  out = out + "| `pins.csv` | Firmware pin map. |\n"
  out = out + "| `pcb-connectors.csv` | Imported PCB connector placements. |\n"
  out = out +
    "| `link-parts.csv` | Link-to-part map for drawing generation. |\n"
  out = out +
    "| `firmware.h` | C header with joint bindings and sensor interfaces. |\n"
  out = out +
    "| `bundle/` | URDF, `package.xml`, glTF meshes, and per-link STEP parts. |\n"
  out = out + "\n## Validation\n\n"
  out = out + "```bash\n"
  out = out +
    "python3 scripts/validate_step.py --no-mesh bundle/parts/<part>.step\n"
  out = out +
    "python3 scripts/validate_urdf.py --check-meshes bundle/urdf/*.urdf\n"
  out = out +
    "python3 scripts/validate_control.py control.yaml bundle/urdf/*.urdf --pins pins.csv\n"
  out = out + "```\n"
  out
}

///|
/// Every text file in the build package, ready to write into a directory.
pub fn Component::build_package_files(
  self : Component,
  name~ : String = "",
) -> Array[BuildFile] {
  [
    BuildFile::new("README.md", self.build_manifest(name~)),
    BuildFile::new("bom.csv", self.to_bom_csv()),
    BuildFile::new("sourcing.csv", self.sourcing_csv()),
    BuildFile::new("print-list.csv", self.print_list_csv()),
    BuildFile::new("fasteners.csv", self.fastener_table_csv()),
    BuildFile::new("assembly.txt", self.build_procedure_text()),
    BuildFile::new("report.txt", self.report_text()),
    BuildFile::new("control.yaml", self.to_ros2_control_yaml()),
    BuildFile::new("pins.csv", self.to_pin_map_csv()),
    BuildFile::new("pcb-connectors.csv", self.pcb_placements_csv()),
    BuildFile::new("link-parts.csv", self.link_parts_csv()),
    BuildFile::new("firmware.h", self.firmware_header()),
  ]
}
