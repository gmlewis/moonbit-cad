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
/// A standalone fabricated/3D-printable part: its own design in its local
/// datum frame, without purchased motors, fasteners, bearings, or PCBs.
pub(all) struct PrintablePart {
  part_number : String
  component_name : String
  meta : PartMeta
  /// The print-ready design: oriented, lifted to `z = 0`, and centered in XY.
  design : @step_cad.Design
  /// Solid volume of the selected bodies, in mm^3.
  volume_mm3 : Double
  /// Solid mass at 100% infill, in kg.
  mass_kg : Double
}

///|
/// Returns true when a part is fabricated in-house rather than purchased.
pub fn is_fabricated_part(meta : PartMeta) -> Bool {
  meta.process != "" && meta.process != "purchased"
}

///|
/// Makes a part number safe for use as a file name.
pub fn sanitize_part_number(part_number : String) -> String {
  part_number
  .replace(old="/", new="-")
  .replace(old="\\", new="-")
  .replace(old=" ", new="-")
}

///|
/// Returns true when `body` belongs to the printable part `part_number`.
fn body_matches_part(body : BodyPart, part_number : String) -> Bool {
  match body.part {
    Some(meta) => meta.part_number == part_number || meta.part_number == ""
    None => true
  }
}

///|
/// Builds a local-frame design from the bodies of one component.
fn design_from_bodies(
  name : String,
  description : String,
  documentation : String,
  bodies : Array[BodyPart],
  part_number : String,
) -> @step_cad.Design {
  let mut design = @step_cad.Design::new(name~, description~, documentation~)
  for body in bodies {
    if body_matches_part(body, part_number) {
      design = design.add(body.node)
    }
  }
  design
}

///|
/// Bounding box of every node in a design, or `None` for an empty design.
fn design_bbox(
  design : @step_cad.Design,
) -> (Double, Double, Double, Double, Double, Double)? {
  let mut first = true
  let mut min_x = 0.0
  let mut max_x = 0.0
  let mut min_y = 0.0
  let mut max_y = 0.0
  let mut min_z = 0.0
  let mut max_z = 0.0
  for node in design.nodes {
    let (x0, x1, y0, y1, z0, z1) = node.bounding_box()
    if first {
      min_x = x0
      max_x = x1
      min_y = y0
      max_y = y1
      min_z = z0
      max_z = z1
      first = false
    } else {
      min_x = if x0 < min_x { x0 } else { min_x }
      max_x = if x1 > max_x { x1 } else { max_x }
      min_y = if y0 < min_y { y0 } else { min_y }
      max_y = if y1 > max_y { y1 } else { max_y }
      min_z = if z0 < min_z { z0 } else { min_z }
      max_z = if z1 > max_z { z1 } else { max_z }
    }
  }
  if first {
    None
  } else {
    Some((min_x, max_x, min_y, max_y, min_z, max_z))
  }
}

///|
/// Chooses the rotation that puts the smallest bounding-box extent on Z for
/// `AutoFlatLargestFace`, or the explicit angles for `RotateDeg`.
fn print_rotation_deg(
  orient : PrintBedOrient,
  design : @step_cad.Design,
) -> (Double, Double, Double) {
  match orient {
    KeepAsIs => (0.0, 0.0, 0.0)
    RotateDeg(rx, ry, rz) => (rx, ry, rz)
    AutoFlatLargestFace =>
      match design_bbox(design) {
        None => (0.0, 0.0, 0.0)
        Some((x0, x1, y0, y1, z0, z1)) => {
          let ex = x1 - x0
          let ey = y1 - y0
          let ez = z1 - z0
          if ez <= ex && ez <= ey {
            (0.0, 0.0, 0.0)
          } else if ey <= ex {
            // Rx(-90 deg) maps the Y extent onto Z.
            (-90.0, 0.0, 0.0)
          } else {
            // Ry(90 deg) maps the X extent onto Z.
            (0.0, 90.0, 0.0)
          }
        }
      }
  }
}

///|
/// Orients a printable design on the print bed: apply the requested rotation,
/// then translate so `min_z == 0` and the XY bounding-box center is `(0, 0)`.
pub fn orient_print_design(
  design : @step_cad.Design,
  orient~ : PrintBedOrient = AutoFlatLargestFace,
) -> @step_cad.Design {
  let (rx, ry, rz) = print_rotation_deg(orient, design)
  let rot = @step_common.Placement::rotation_deg(rx, ry, rz)
  let rot_xform : @step_cad.Transform = {
    rot: rot.rot,
    trans: (0.0, 0.0, 0.0),
  }
  let mut rotated = @step_cad.Design::new(
    name=design.name,
    description=design.description,
    documentation=design.documentation,
  )
  for node in design.nodes {
    rotated = rotated.add(transform_scene_node(node, rot_xform))
  }
  let (dx, dy, dz) = match design_bbox(rotated) {
    None => (0.0, 0.0, 0.0)
    Some((x0, x1, y0, y1, z0, _z1)) => (-(x0 + x1) / 2.0, -(y0 + y1) / 2.0, -z0)
  }
  let mut out = @step_cad.Design::new(
    name=design.name,
    description=design.description,
    documentation=design.documentation,
  )
  for node in rotated.nodes {
    out = out.add(node.translate(x=dx, y=dy, z=dz))
  }
  out
}

///|
fn round1(value : Double) -> Double {
  (value * 10.0).round() / 10.0
}

///|
/// Formats a non-negative dimension with exactly one decimal place.
fn fmt1(value : Double) -> String {
  let scaled = (value * 10.0).round().to_int()
  let whole = scaled / 10
  let tenths = (scaled % 10).abs()
  whole.to_string() + "." + tenths.to_string()
}

///|
fn bbox_label(bbox : (Double, Double, Double)) -> String {
  let (w, d, h) = bbox
  fmt1(w) + "x" + fmt1(d) + "x" + fmt1(h)
}

///|
fn printable_infill_fraction(line : BomLine) -> Double {
  let text = print_infill(line)
  if text == "" {
    return 1.0
  }
  let percent = @string.parse_double(text) catch { _ => 100.0 }
  percent / 100.0
}

///|
/// Rough print-time factor: minutes per gram of deposited material.
const PRINT_MIN_PER_GRAM : Double = 1.2

///|
pub fn PrintablePart::bbox_mm(
  self : PrintablePart,
) -> (Double, Double, Double)? {
  match design_bbox(self.design) {
    Some((x0, x1, y0, y1, z0, z1)) => Some((x1 - x0, y1 - y0, z1 - z0))
    None => None
  }
}

///|
pub fn PrintablePart::bbox_label(self : PrintablePart) -> String {
  match self.bbox_mm() {
    Some(bbox) => bbox_label(bbox)
    None => ""
  }
}

///|
pub fn PrintablePart::fits_bed(
  self : PrintablePart,
  bed : PrintBedSpec,
) -> Bool {
  match self.bbox_mm() {
    Some((w, d, h)) => bed.fits(w, d, h)
    None => false
  }
}

///|
/// Estimated printed mass in grams: solid mass scaled by the line's infill.
pub fn PrintablePart::est_mass_g(
  self : PrintablePart,
  line : BomLine,
) -> Double {
  round1(self.mass_kg * 1000.0 * printable_infill_fraction(line))
}

///|
/// Rough print time in minutes; zero for non-print processes.
pub fn PrintablePart::est_print_min(
  self : PrintablePart,
  line : BomLine,
) -> Double {
  if !line.process.contains("print") {
    return 0.0
  }
  round1(self.est_mass_g(line) * PRINT_MIN_PER_GRAM)
}

///|
fn printable_part_map(
  parts : Array[PrintablePart],
) -> Map[String, PrintablePart] {
  let map : Map[String, PrintablePart] = Map([])
  for part in parts {
    map.set(part.part_number, part)
  }
  map
}

///|
/// Collects standalone printable/fabricated designs from this component tree.
///
/// A whole component marked fabricated is exported with all its bodies. A
/// body-level part number collects every body sharing that number. Pre-order
/// traversal and part-number de-duplication make each printable part appear
/// once.
pub fn Component::printable_parts(self : Component) -> Array[PrintablePart] {
  let out : Array[PrintablePart] = []
  let seen : Array[String] = []
  self.collect_printable_parts(out, seen)
  out
}

///|
fn make_printable_part(
  component_name : String,
  documentation : String,
  bodies : Array[BodyPart],
  meta : PartMeta,
) -> PrintablePart {
  let matching = bodies.filter(fn(body) {
    body_matches_part(body, meta.part_number)
  })
  // Repeated copies of one part (twin ears, mirrored brackets) print once;
  // the BOM line's quantity says how many to print.
  let selected = if meta.single_body_print && matching.length() > 1 {
    [matching[0]]
  } else {
    matching
  }
  let design = design_from_bodies(
    meta.part_number,
    meta.description,
    documentation,
    selected,
    meta.part_number,
  )
  let mut volume_mm3 = 0.0
  let mut mass_kg = 0.0
  for body in selected {
    mass_kg = mass_kg + body.inertial.mass
    let density = body.density.to_kg_per_m3()
    if density > 0.0 {
      volume_mm3 = volume_mm3 + body.inertial.mass / density * 1.0e9
    }
  }
  {
    part_number: meta.part_number,
    component_name,
    meta,
    design: orient_print_design(design, orient=meta.print_bed_orient),
    volume_mm3,
    mass_kg,
  }
}

///|
fn Component::collect_printable_parts(
  self : Component,
  out : Array[PrintablePart],
  seen : Array[String],
) -> Unit {
  match self.part {
    Some(meta) =>
      if is_fabricated_part(meta) &&
        self.bodies.length() > 0 &&
        !seen.contains(meta.part_number) {
        seen.push(meta.part_number)
        out.push(
          make_printable_part(
            self.name,
            self.format_documentation(),
            self.bodies,
            meta,
          ),
        )
      }
    None => ()
  }
  for body in self.bodies {
    match body.part {
      Some(meta) =>
        if is_fabricated_part(meta) && !seen.contains(meta.part_number) {
          seen.push(meta.part_number)
          out.push(
            make_printable_part(
              self.name,
              self.format_documentation(),
              self.bodies,
              meta,
            ),
          )
        }
      None => ()
    }
  }
  for att in self.attachments {
    att.child.collect_printable_parts(out, seen)
  }
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
/// Manufactured (non-purchased) parts with print/cut settings, print-bed fit,
/// and rough mass/time estimates.
pub fn Component::print_list_csv(
  self : Component,
  bed~ : PrintBedSpec = PrintBedSpec::default(),
) -> String {
  let header : Array[String] = [
    "part_number", "description", "quantity", "material", "process", "orientation",
    "layer_height_mm", "infill_percent", "support", "notes", "bbox_mm", "fits_bed",
    "est_mass_g", "est_print_min",
  ]
  let rows : Array[String] = [csv_row(header.map(fn(v) { csv_field(v) }))]
  let cartridges = parse_cartridges(
    self.parameters.get("print_in_place_gearset").unwrap_or(""),
  )
  let parts = printable_part_map(self.printable_parts())
  for line in self.bom().lines {
    if line.process != "purchased" {
      if is_gearset_layer_for(line.part_number, cartridges) {
        continue
      }
      let (bbox_cell, fits_cell, mass_cell, time_cell) = match
        parts.get(line.part_number) {
        Some(part) =>
          (
            csv_field(part.bbox_label()),
            csv_field(if part.fits_bed(bed) { "YES" } else { "NO" }),
            csv_field(fmt1(part.est_mass_g(line))),
            csv_field(
              if line.process.contains("print") {
                fmt1(part.est_print_min(line))
              } else {
                ""
              },
            ),
          )
        None => (csv_field(""), csv_field(""), csv_field(""), csv_field(""))
      }
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
          bbox_cell,
          fits_cell,
          mass_cell,
          time_cell,
        ]),
      )
    }
  }
  for cartridge in cartridges {
    rows.push(
      csv_row([
        csv_field(cartridge),
        csv_field("Print-in-place herringbone gear set (sun, planets, ring)"),
        "1",
        csv_field("PETG / carbon fiber nylon"),
        csv_field("3D print"),
        csv_field("flat on the build plate, gears already in place"),
        "0.20",
        "40",
        "none",
        csv_field("print in place; do not assemble the gears afterward"),
        csv_field(""),
        csv_field(""),
        csv_field(""),
        csv_field(""),
      ]),
    )
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
/// Escapes text for a Markdown table cell.
fn md_cell(text : String) -> String {
  text.replace(old="|", new="\\|").replace(old="\n", new=" ")
}

///|
/// Splits a comma-separated `print_in_place_gearset` parameter into trimmed
/// cartridge part numbers.
fn parse_cartridges(raw : String) -> Array[String] {
  let out : Array[String] = []
  if raw == "" {
    return out
  }
  for entry in raw.split(",") {
    let trimmed = entry.trim().to_owned()
    if trimmed != "" {
      out.push(trimmed)
    }
  }
  out
}

///|
/// True for the sun/ring/planet layers that are replaced by a single
/// print-in-place cartridge when the gearbox requests it.
fn is_gearset_layer(part_number : String) -> Bool {
  part_number == "PGB-SUN" ||
  part_number == "PGB-RING" ||
  part_number.has_prefix("PGB-PLANET")
}

///|
/// True when `part_number` is printed inside one of `cartridges` instead of as
/// an individual piece.
fn is_gearset_layer_for(
  part_number : String,
  cartridges : Array[String],
) -> Bool {
  if cartridges.length() == 0 {
    return false
  }
  if cartridges.contains("PGB-CARTRIDGE") && is_gearset_layer(part_number) {
    return true
  }
  for cartridge in cartridges {
    if cartridge.has_prefix("MG-STAGE") && cartridge.has_suffix("-CARTRIDGE") {
      let stage_tag = String::unsafe_substring(
        cartridge,
        start=8,
        end=cartridge.length() - 10,
      )
      if part_number == "MG-CASING-" + stage_tag ||
        part_number == "MG-SUN-" + stage_tag ||
        part_number == "MG-PLANET-" + stage_tag {
        return true
      }
    }
  }
  false
}

///|
/// Collects the CAD names that appear in the assembly procedure and maps each
/// to the part a builder should pick up.
fn collect_name_key(
  component : Component,
  procedure : String,
  out : Array[(String, String)],
  seen : Array[String],
) -> Unit {
  let name = component.name
  if procedure.contains(name) && !seen.contains(name) {
    match component.part {
      Some(meta) => {
        seen.push(name)
        out.push((name, meta.part_number + " — " + meta.description))
      }
      None => {
        let mut first = ""
        for body in component.bodies {
          match body.part {
            Some(meta) =>
              if first == "" {
                first = meta.part_number + " — " + meta.description
              }
            None => ()
          }
        }
        if first != "" {
          seen.push(name)
          out.push((name, first))
        }
      }
    }
  }
  for body in component.bodies {
    if procedure.contains(body.name) && !seen.contains(body.name) {
      match body.part {
        Some(meta) => {
          seen.push(body.name)
          out.push((body.name, meta.part_number + " — " + meta.description))
        }
        None => ()
      }
    }
  }
  for fastener in component.fasteners {
    if procedure.contains(fastener.name) && !seen.contains(fastener.name) {
      match fastener.part {
        Some(meta) => {
          seen.push(fastener.name)
          out.push(
            (fastener.name, meta.part_number + " — " + meta.description),
          )
        }
        None => ()
      }
    }
  }
  for att in component.attachments {
    collect_name_key(att.child, procedure, out, seen)
  }
}

///|
/// The one-page beginner guide shipped at the root of every build package.
///
/// It answers exactly three questions in order: what to print, what to buy,
/// and how to assemble it. The engineering manifest, CSVs, and bundle remain
/// available for advanced users.

///|
/// Interactive 3D panel shown at the top of START-HERE.md.
///
/// The panel starts as the isometric render and is replaced by a WebGL canvas
/// only after `viewer.js` has loaded `assembly.gltf`, so an offline or
/// `file://` page keeps the static image.
fn viewer_html() -> String {
  "<div class=\"model-panel\">\n" +
  "  <img class=\"model-fallback\" src=\"views/iso.png\" alt=\"Isometric assembly view\">\n" +
  "  <canvas hidden aria-label=\"Interactive 3D assembly view\"></canvas>\n" +
  "  <div class=\"model-hint\" hidden></div>\n" +
  "</div>\n" +
  "<script type=\"importmap\">{\"imports\":{\"three\":\"https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js\",\"three/addons/\":\"https://cdn.jsdelivr.net/npm/three@0.170.0/examples/jsm/\"}}</script>\n" +
  "<script type=\"module\" src=\"viewer.js\"></script>\n\n"
}

///|
/// Markdown/HTML gallery of the multi-angle renders written by
/// `scripts/render_views.py`. Missing images hide their figure instead of
/// showing a broken icon, so a build without `solidcraft-cli` still reads well.
fn view_gallery_html() -> String {
  let views : Array[(String, String)] = [
    ("iso", "Isometric"),
    ("front", "Front"),
    ("left", "Left"),
    ("top", "Top"),
    ("exploded", "Exploded"),
  ]
  let mut out = "## Visual overview\n\n"
  out = out +
    "Shaded renders of the assembled package (and the exploded view when one is generated). " +
    "`scripts/render_views.py` refreshes these images on every build when `solidcraft-cli` is on `PATH`.\n\n"
  out = out + "<div class=\"view-grid\">\n"
  for view in views {
    out = out +
      "<figure><a href=\"views/" +
      view.0 +
      ".png\"><img src=\"views/" +
      view.0 +
      ".png\" alt=\"" +
      view.1 +
      " view\" onerror=\"this.closest('figure').style.display='none'\"></a><figcaption>" +
      view.1 +
      "</figcaption></figure>\n"
  }
  out + "</div>\n\n"
}

///|
pub fn Component::start_here_text(
  self : Component,
  name~ : String = "",
  bed~ : PrintBedSpec = PrintBedSpec::default(),
) -> String {
  let package_name = if name == "" { self.display_name() } else { name }
  let bom = self.bom()
  let printable = self.printable_parts()
  let printable_files : Array[String] = printable.map(fn(part) {
    sanitize_part_number(part.part_number)
  })
  let cartridges = parse_cartridges(
    self.parameters.get("print_in_place_gearset").unwrap_or(""),
  )
  let mut out = "# Start here — " + package_name + "\n\n"
  out = out +
    "This folder contains everything you need. Do these three steps in order.\n\n"
  let exploded_view = self.parameters.get("exploded_view").unwrap_or("")
  if exploded_view != "" {
    out = out +
      "**Want to see every part?** Open `" +
      exploded_view +
      "` in a STEP viewer for the exploded, color-coded view.\n\n"
  }
  out = out +
    "**Interactive 3D preview** — drag to orbit and scroll to zoom; the static\n" +
    "gallery below stays available offline.\n\n"
  out = out + viewer_html()
  out = out + view_gallery_html()
  out = out + "## 1. 3D-print these files\n\n"
  if cartridges.contains("PGB-CARTRIDGE") {
    out = out +
      "> **Important — the gear set is print-in-place.** Print `printable/PGB-CARTRIDGE.step` as one job. Do not print the separate PGB-SUN, PGB-RING, or PGB-PLANET files, and do not try to assemble the gears afterward — the 4-elbow herringbone teeth cannot be inserted into the ring. You can still press the planet bearings into the captive planets from above, and skip the step that attaches the sun to the ring housing (the sun is already captive).\n\n"
  }
  let mg_cartridges = cartridges.filter(fn(c) { c.has_prefix("MG-STAGE") })
  if mg_cartridges.length() > 0 {
    out = out +
      "> **Important — the planetary stages are print-in-place.** Print each `MG-STAGE*-CARTRIDGE.step` file flat on the build plate (`z = 0`) as one job — do not separate the `MG-CASING-*`, `MG-SUN-*`, or `MG-PLANET-*` files, because the 4-elbow herringbone teeth interlock inside the ring. After printing, press the `FR8-2RS` flanged bearings into each captive planet from above until flush in the top counterbore (trapped from above by `MG-CARRIER-*`); no washers are needed because the flanged bearings seat against their top counterbores and the herringbone teeth lock each planet axially.\n\n"
  }
  out = out +
    "Open the `printable/` folder. Print one copy of each file unless the Qty column says more. " +
    "Use the material and infill below, and put the largest flat face on the build plate.\n\n"
  out = out +
    "| File to print | What it is | Qty | Material | Process | Infill | Orientation | Size (mm) | Fits bed | Est. mass | Est. time |\n"
  out = out +
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n"
  let part_map = printable_part_map(printable)
  let mut printed_count = 0
  for line in bom.lines {
    if is_gearset_layer_for(line.part_number, cartridges) {
      continue
    }
    if line.process != "purchased" &&
      printable_files.contains(sanitize_part_number(line.part_number)) {
      printed_count = printed_count + line.quantity
      let infill = print_infill(line)
      let (size, bed_fit, mass, time) = match part_map.get(line.part_number) {
        Some(part) =>
          (
            part.bbox_label(),
            if part.fits_bed(bed) {
              "YES"
            } else {
              "**NO**"
            },
            if line.process.contains("print") {
              fmt1(part.est_mass_g(line)) + " g"
            } else {
              "—"
            },
            if line.process.contains("print") {
              fmt1(part.est_print_min(line)) + " min"
            } else {
              "—"
            },
          )
        None => ("—", "—", "—", "—")
      }
      out = out +
        "| `printable/" +
        sanitize_part_number(line.part_number) +
        ".step` | " +
        md_cell(line.description) +
        " | " +
        line.quantity.to_string() +
        " | " +
        md_cell(line.material) +
        " | " +
        md_cell(line.process) +
        " | " +
        (if infill == "" { "—" } else { infill + "%" }) +
        " | " +
        md_cell(print_orientation(line)) +
        " | " +
        size +
        " | " +
        bed_fit +
        " | " +
        mass +
        " | " +
        time +
        " |\n"
    }
  }
  for cartridge in cartridges {
    printed_count = printed_count + 1
    out = out +
      "| `printable/" +
      cartridge +
      ".step` | Print-in-place herringbone gear set (sun + planets + ring) | 1 | PETG / carbon fiber nylon | 3D print | 40% | flat on the build plate, gears already in place | — | — | — | — |\n"
  }
  out = out +
    "\nThat is **" +
    printed_count.to_string() +
    " printed pieces**. `print-list.csv` has the same list with layer height and support notes.\n\n"
  out = out + "## 2. Buy these parts\n\n"
  out = out +
    "| Qty | What to buy | Supplier | Unit price | Line total | Link | Notes |\n"
  out = out + "| --- | --- | --- | --- | --- | --- | --- |\n"
  let mut purchase_total = 0.0
  for line in bom.lines {
    if line.process == "purchased" {
      purchase_total = purchase_total + line.total_cost_usd
      let link = if line.supplier_url == "" {
        "—"
      } else {
        "[open](" + line.supplier_url + ")"
      }
      out = out +
        "| " +
        line.quantity.to_string() +
        " | " +
        md_cell(line.description) +
        " (" +
        md_cell(line.part_number) +
        ") | " +
        md_cell(if line.supplier == "" { "any" } else { line.supplier }) +
        " | $" +
        round2(line.unit_cost_usd).to_string() +
        " | $" +
        round2(line.total_cost_usd).to_string() +
        " | " +
        link +
        " | " +
        md_cell(line.notes) +
        " |\n"
    }
  }
  out = out +
    "\n**Estimated purchase total: $" +
    round2(purchase_total).to_string() +
    "** (per-part estimate plus shipping; linked kits may include spares, so the cart total can differ). " +
    "`sourcing.csv` has the same list in spreadsheet form.\n\n"
  out = out + "## 3. Assemble it\n\n"
  out = out +
    "Check that all printed pieces are cleaned up and all purchased parts are on the bench. " +
    "You will need a 3D printer (step 1), a clean bench, and these hex keys: "
  let procedure = self.build_procedure_text()
  let display_procedure = if !cartridges.contains("PGB-CARTRIDGE") {
    procedure
  } else {
    let lines : Array[String] = procedure
      .split("\n")
      .collect()
      .map(fn(part) { part.to_owned() })
    lines.filter(fn(line) { !line.contains("_stage1_sun to ") }).join("\n")
  }
  let sizes : Array[String] = ["2", "2.5", "3", "4", "5", "6", "8", "10"]
  let keys : Array[String] = []
  for size in sizes {
    if procedure.contains("[" + size + " mm hex key") {
      keys.push(size + " mm")
    }
  }
  out = out +
    (if keys.length() == 0 {
      "none listed in the steps.\n\n"
    } else {
      keys.join(", ") + ".\n\n"
    })
  out = out +
    "If a step uses a name you do not recognize, open `NAME-KEY.md`; it maps every name to the part it means.\n\n"
  let step_count = self.assembly_plan().length()
  if step_count <= 80 {
    out = out + "```\n" + display_procedure + "```\n\n"
  } else {
    out = out +
      "This design has **" +
      step_count.to_string() +
      " steps**. Open `assembly.txt` and follow it in order.\n\n"
  }
  out = out +
    "---\n\nAdvanced files: `README.md` (manifest), `bom.csv`, `sourcing.csv`, " +
    "`print-list.csv`, `fasteners.csv`, `assembly.txt`, and `bundle/` (URDF/glTF).\n"
  out
}

///|
/// Maps the CAD names used in the assembly steps to the part a builder picks
/// up. Long names with a shared prefix are capped so the file stays readable.
pub fn Component::name_key_text(
  self : Component,
  name~ : String = "",
) -> String {
  let package_name = if name == "" { self.display_name() } else { name }
  let procedure = self.build_procedure_text()
  let name_key : Array[(String, String)] = []
  collect_name_key(self, procedure, name_key, [])
  let mut out = "# Name key — " + package_name + "\n\n"
  out = out +
    "The assembly steps use the CAD names below. Find the name in the first column to see the part it means.\n\n"
  if name_key.length() == 0 {
    return out + "No named parts were found.\n"
  }
  out = out + "| Name in the steps | Part |\n| --- | --- |\n"
  let shown = if name_key.length() > 80 { 80 } else { name_key.length() }
  for i in 0..<shown {
    let (cad_name, part) = name_key[i]
    out = out + "| `" + md_cell(cad_name) + "` | " + md_cell(part) + " |\n"
  }
  if name_key.length() > shown {
    out = out +
      "\nThe rest of the names are in `bom.csv` and `link-parts.csv`.\n"
  }
  out = out +
    "\nFiles: `print-list.csv` (printed parts), `bom.csv` (all parts), `assembly.txt` (steps).\n"
  out
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
  out = out +
    "| `START-HERE.md` | Beginner guide: what to print, what to buy, and how to assemble. |\n"
  out = out +
    "| `NAME-KEY.md` | Maps the CAD names in the assembly steps to real parts. |\n"
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
  bed~ : PrintBedSpec = PrintBedSpec::default(),
  joint_positions~ : Map[String, Double] = Map([]),
) -> Array[BuildFile] {
  let files : Array[BuildFile] = [
    BuildFile::new("START-HERE.md", self.start_here_text(name~, bed~)),
    BuildFile::new("NAME-KEY.md", self.name_key_text(name~)),
    BuildFile::new("README.md", self.build_manifest(name~)),
    BuildFile::new("bom.csv", self.to_bom_csv()),
    BuildFile::new("sourcing.csv", self.sourcing_csv()),
    BuildFile::new("print-list.csv", self.print_list_csv(bed~)),
    BuildFile::new("fasteners.csv", self.fastener_table_csv()),
    BuildFile::new("assembly.txt", self.build_procedure_text()),
    BuildFile::new("report.txt", self.report_text()),
    BuildFile::new("control.yaml", self.to_ros2_control_yaml()),
    BuildFile::new("pins.csv", self.to_pin_map_csv()),
    BuildFile::new("pcb-connectors.csv", self.pcb_placements_csv()),
    BuildFile::new("link-parts.csv", self.link_parts_csv()),
    BuildFile::new("firmware.h", self.firmware_header()),
    BuildFile::new(
      "control_params.h",
      self.control_params_header(joint_positions~),
    ),
    BuildFile::new("lqr_model.py", self.lqr_model_python(joint_positions~)),
    BuildFile::new("inspect.json", self.inspect_json(bed~, joint_positions~)),
  ]
  if self.rl_task is Some(_) {
    files.push(
      BuildFile::new("rl_task.json", self.rl_task_json(joint_positions~)),
    )
  }
  let cartridges = parse_cartridges(
    self.parameters.get("print_in_place_gearset").unwrap_or(""),
  )
  for part in self.printable_parts() {
    if is_gearset_layer_for(part.part_number, cartridges) {
      continue
    }
    files.push(
      BuildFile::new(
        "printable/\{sanitize_part_number(part.part_number)}.step",
        part.design.to_step_file(),
      ),
    )
  }
  files
}
