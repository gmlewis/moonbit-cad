///|
/// Assembly metadata: purchasing/manufacturing data, fasteners, ports, fits,
/// and bill-of-materials roll-up.
///
/// These records are additive; geometry and kinematics stay in `Component` and
/// `BodyPart`.

///|
/// Purchasing and manufacturing metadata for one part.
pub(all) struct PartMeta {
  part_number : String
  description : String
  supplier : String
  supplier_url : String
  material : String
  process : String
  finish : String
  unit_cost_usd : Double
  notes : String
}

///|
pub fn PartMeta::new(
  part_number : String,
  description~ : String = "",
  supplier~ : String = "",
  supplier_url~ : String = "",
  material~ : String = "",
  process~ : String = "",
  finish~ : String = "",
  unit_cost_usd~ : Double = 0.0,
  notes~ : String = "",
) -> PartMeta {
  {
    part_number,
    description,
    supplier,
    supplier_url,
    material,
    process,
    finish,
    unit_cost_usd,
    notes,
  }
}

///|
pub fn PartMeta::with_notes(self : PartMeta, notes : String) -> PartMeta {
  { ..self, notes, }
}

///|
pub fn PartMeta::with_supplier_url(
  self : PartMeta,
  supplier_url : String,
) -> PartMeta {
  { ..self, supplier_url, }
}

///|
/// The kind of hardware a fastener record describes.
pub(all) enum FastenerKind {
  Bolt
  Screw
  Nut
  Washer
  Insert
}

///|
/// A fastener schedule entry: thread, length, quantity, torque, and the parts
/// or mates it joins.
pub(all) struct Fastener {
  name : String
  kind : FastenerKind
  thread : String
  length_mm : Double
  /// Thread engagement in the receiving part, mm.
  engagement_mm : Double
  quantity : Int32
  torque_nm : Double
  references : Array[String]
  part : PartMeta?
}

///|
pub fn Fastener::new(
  name : String,
  kind : FastenerKind,
  thread~ : String = "",
  length_mm~ : Double = 0.0,
  engagement_mm~ : Double = 0.0,
  quantity~ : Int32 = 1,
  torque_nm~ : Double = 0.0,
  references~ : Array[String] = [],
  part~ : PartMeta? = None,
) -> Fastener {
  {
    name,
    kind,
    thread,
    length_mm,
    engagement_mm,
    quantity,
    torque_nm,
    references,
    part,
  }
}

///|
pub fn Fastener::with_part(self : Fastener, part : PartMeta) -> Fastener {
  { ..self, part: Some(part), }
}

///|
/// A typed interface exposed by a component.
pub(all) enum PortKind {
  Mechanical
  Power
  Signal
  Bus
  Fluid
  Sensor
  Ground
}

///|
pub(all) struct Port {
  name : String
  kind : PortKind
  spec : String
}

///|
pub fn Port::new(name : String, kind : PortKind, spec~ : String = "") -> Port {
  { name, kind, spec, }
}

///|
/// A fit record: nominal size plus the allowed range.
pub(all) enum FitClass {
  Nominal
  Clearance
  Transition
  Interference
}

///|
pub(all) struct Fit {
  name : String
  fit_class : FitClass
  nominal_mm : Double
  min_mm : Double
  max_mm : Double
}

///|
pub fn Fit::new(
  name : String,
  fit_class : FitClass,
  nominal_mm~ : Double = 0.0,
  min_mm~ : Double = 0.0,
  max_mm~ : Double = 0.0,
) -> Fit {
  { name, fit_class, nominal_mm, min_mm, max_mm, }
}

///|
/// One aggregated bill-of-materials line.
pub(all) struct BomLine {
  part_number : String
  description : String
  quantity : Int32
  supplier : String
  supplier_url : String
  material : String
  process : String
  finish : String
  unit_cost_usd : Double
  total_cost_usd : Double
  notes : String
}

///|
/// A bill of materials: aggregated part lines and a count of bodies without
/// part metadata (explicit placeholders).
pub(all) struct Bom {
  lines : Array[BomLine]
  mut unassigned : Int32
}

///|
pub fn Bom::new() -> Bom {
  { lines: [], unassigned: 0, }
}

///|
/// Adds `quantity` of `part`, aggregating by part number.
pub fn Bom::add(self : Bom, part : PartMeta, quantity : Int32) -> Bom {
  if quantity <= 0 {
    return self
  }
  for i in 0..<self.lines.length() {
    if self.lines[i].part_number == part.part_number {
      let line = self.lines[i]
      let total_qty = line.quantity + quantity
      self.lines[i] = {
        ..line,
        quantity: total_qty,
        total_cost_usd: line.unit_cost_usd * total_qty.to_double(),
      }
      return self
    }
  }
  self.lines.push({
    part_number: part.part_number,
    description: part.description,
    quantity,
    supplier: part.supplier,
    supplier_url: part.supplier_url,
    material: part.material,
    process: part.process,
    finish: part.finish,
    unit_cost_usd: part.unit_cost_usd,
    total_cost_usd: part.unit_cost_usd * quantity.to_double(),
    notes: part.notes,
  })
  self
}

///|
/// Counts a body or fastener that has no `PartMeta`.
pub fn Bom::add_unassigned(self : Bom, quantity : Int32) -> Bom {
  self.unassigned = self.unassigned + quantity
  self
}

///|
pub fn Bom::total_cost_usd(self : Bom) -> Double {
  self.lines.fold(init=0.0, fn(acc, line) { acc + line.total_cost_usd })
}

///|
fn csv_field(value : String) -> String {
  "\"" + value.replace(old="\"", new="\"\"") + "\""
}

///|
fn csv_row(fields : Array[String]) -> String {
  fields.fold(init="", fn(acc, field) {
    if acc == "" {
      field
    } else {
      acc + "," + field
    }
  })
}

///|
/// Renders the bill of materials as CSV with a header and a final newline.
pub fn Bom::to_csv(self : Bom) -> String {
  let header : Array[String] = [
    "part_number", "description", "quantity", "supplier", "supplier_url", "material",
    "process", "finish", "unit_cost_usd", "total_cost_usd", "notes",
  ]
  let rows : Array[String] = [csv_row(header.map(fn(v) { csv_field(v) }))]
  for line in self.lines {
    rows.push(
      csv_row([
        csv_field(line.part_number),
        csv_field(line.description),
        line.quantity.to_string(),
        csv_field(line.supplier),
        csv_field(line.supplier_url),
        csv_field(line.material),
        csv_field(line.process),
        csv_field(line.finish),
        csv_field(line.unit_cost_usd.to_string()),
        csv_field(line.total_cost_usd.to_string()),
        csv_field(line.notes),
      ]),
    )
  }
  if self.unassigned > 0 {
    rows.push(
      csv_row([
        csv_field(""),
        csv_field("UNASSIGNED"),
        self.unassigned.to_string(),
        csv_field(""),
        csv_field(""),
        csv_field(""),
        csv_field(""),
        csv_field("0.0"),
        csv_field("0.0"),
        csv_field("bodies or fasteners without PartMeta"),
      ]),
    )
  }
  rows.fold(init="", fn(acc, row) { acc + row + "\n" })
}

///|
/// Builds the bill of materials for this component tree.
///
/// A component with `part` is treated as a purchased/assembled item: its own
/// bodies are represented by that part, while attachments marked
/// `bom_external` (the default) are still collected. Internal attachments such
/// as a motor's rotor are marked non-external and are not counted separately.
pub fn Component::bom(self : Component) -> Bom {
  let bom = Bom::new()
  self.collect_bom(bom, false)
  bom
}

///|
/// Convenience: the bill of materials as CSV.
pub fn Component::to_bom_csv(self : Component) -> String {
  self.bom().to_csv()
}

///|
fn Component::collect_bom(
  self : Component,
  bom : Bom,
  skip_bodies : Bool,
) -> Unit {
  let is_part = self.part is Some(_)
  if is_part {
    match self.part {
      Some(part) => {
        let _ = bom.add(part, 1)
      }
      None => ()
    }
  } else if !skip_bodies {
    for body in self.bodies {
      match body.part {
        Some(part) => {
          let _ = bom.add(part, 1)
        }
        None => {
          let _ = bom.add_unassigned(1)
        }
      }
    }
  }
  for fastener in self.fasteners {
    match fastener.part {
      Some(part) => {
        let _ = bom.add(part, fastener.quantity)
      }
      None => {
        let _ = bom.add_unassigned(fastener.quantity)
      }
    }
  }
  for att in self.attachments {
    let child_skip = if att.bom_external {
      false
    } else {
      skip_bodies || is_part
    }
    att.child.collect_bom(bom, child_skip)
  }
}

///|
/// Sets purchasing/manufacturing metadata for the whole component.
pub fn Component::with_part(self : Component, part : PartMeta) -> Component {
  { ..self, part: Some(part), }
}

///|
/// Adds a typed interface port.
pub fn Component::add_port(self : Component, port : Port) -> Component {
  self.ports.push(port)
  self
}

///|
/// Adds a fastener schedule entry.
pub fn Component::add_fastener(
  self : Component,
  fastener : Fastener,
) -> Component {
  self.fasteners.push(fastener)
  self
}

///|
/// Adds an explicit fit record.
pub fn Component::add_fit(self : Component, fit : Fit) -> Component {
  self.fits.push(fit)
  self
}

///|
/// One step in a derived assembly plan: a fastener installation or a child
/// attachment, numbered in the order the tree should be built.
pub(all) struct AssemblyStep {
  sequence : Int32
  title : String
  /// Slash-separated path from the root component.
  component : String
  /// The joint used to attach this component, when this is an attach step.
  joint : String?
  /// Fastener schedule entries installed in this step.
  fasteners : Array[String]
  /// Tools required by those fasteners.
  tools : Array[String]
  notes : String
}

///|
pub fn AssemblyStep::new(
  sequence : Int32,
  title : String,
  component~ : String,
  joint~ : String? = None,
  fasteners~ : Array[String] = [],
  tools~ : Array[String] = [],
  notes~ : String = "",
) -> AssemblyStep {
  { sequence, title, component, joint, fasteners, tools, notes, }
}

///|
/// Renders one step as a single human-readable line.
pub fn AssemblyStep::to_line(self : AssemblyStep) -> String {
  let joint = match self.joint {
    Some(name) => " (" + name + ")"
    None => ""
  }
  let fasteners = if self.fasteners.length() == 0 {
    ""
  } else {
    ", fasteners: " + array_join(self.fasteners, ", ")
  }
  let tools = if self.tools.length() == 0 {
    ""
  } else {
    " [" + array_join(self.tools, ", ") + "]"
  }
  let notes = if self.notes == "" { "" } else { " -- " + self.notes }
  self.sequence.to_string() +
  ". " +
  self.title +
  " @ " +
  leaf_name(self.component) +
  joint +
  fasteners +
  tools +
  notes
}

///|
/// The last slash-separated segment of a component path.
fn leaf_name(path : String) -> String {
  path.split("/").fold(init="", fn(_, part) { part.to_owned() })
}

///|
fn array_has(items : Array[String], item : String) -> Bool {
  items.fold(init=false, fn(acc, value) { acc || value == item })
}

///|
fn array_join(items : Array[String], separator : String) -> String {
  items.fold(init="", fn(acc, item) {
    if acc == "" {
      item
    } else {
      acc + separator + item
    }
  })
}

///|
/// Hex-key size for a metric socket-head thread, using the standard sizes.
fn hex_key_for_thread(thread : String) -> String {
  match thread {
    "M2" => "1.5 mm hex key"
    "M2.5" => "2 mm hex key"
    "M3" => "2.5 mm hex key"
    "M4" => "3 mm hex key"
    "M5" => "4 mm hex key"
    "M6" => "5 mm hex key"
    "M8" => "6 mm hex key"
    "M10" => "8 mm hex key"
    _ => "hex key"
  }
}

///|
fn tool_for_fastener(fastener : Fastener) -> String {
  match fastener.kind {
    Bolt | Screw => hex_key_for_thread(fastener.thread)
    Nut => "wrench"
    Washer => "hand tools"
    Insert => "soldering iron"
  }
}

///|
fn fastener_note(fastener : Fastener) -> String {
  let quantity = fastener.quantity.to_string()
  let thread = if fastener.thread == "" { "" } else { " " + fastener.thread }
  let length = if fastener.length_mm > 0.0 {
    " x " + fastener.length_mm.to_string() + " mm"
  } else {
    ""
  }
  let torque = if fastener.torque_nm > 0.0 {
    ", " + fastener.torque_nm.to_string() + " N·m"
  } else {
    ""
  }
  quantity + " x" + thread + length + torque
}

///|
fn Component::collect_component_names(
  self : Component,
  names : Array[String],
) -> Unit {
  names.push(self.name)
  for att in self.attachments {
    // A fastener that references the joint that installs it is a mounting
    // fastener, so it belongs to the attach step rather than this component's
    // internal build.
    names.push(att.joint_name)
    att.child.collect_component_names(names)
  }
}

///|
/// A fastener is a mounting fastener when it references another component in
/// the tree; otherwise it is installed while building its own component.
fn fastener_is_mounting(
  fastener : Fastener,
  self_name : String,
  component_names : Array[String],
) -> Bool {
  fastener.references.fold(init=false, fn(acc, reference) {
    acc || (reference != self_name && array_has(component_names, reference))
  })
}

///|
/// Builds the assembly plan by walking the tree depth first.
///
/// A component's own (internal) fasteners are installed first, then each child
/// is built and attached, so children are complete before they are installed.
/// A fastener that references another component in the tree is installed with
/// the attach step that joins those two components.
pub fn Component::assembly_plan(self : Component) -> Array[AssemblyStep] {
  let component_names : Array[String] = []
  self.collect_component_names(component_names)
  let steps : Array[AssemblyStep] = []
  self.collect_assembly_steps(self.name, component_names, steps)
  steps
}

///|
/// The assembly plan as one numbered line per step.
pub fn Component::assembly_plan_text(self : Component) -> String {
  self
  .assembly_plan()
  .fold(init="", fn(acc, step) { acc + step.to_line() + "\n" })
}

///|
fn Component::collect_assembly_steps(
  self : Component,
  path : String,
  component_names : Array[String],
  steps : Array[AssemblyStep],
) -> Unit {
  let attach_fasteners : Array[String] = []
  for att in self.attachments {
    for fastener in self.fasteners {
      if fastener.references.fold(init=false, fn(acc, reference) {
          acc || reference == att.child.name || reference == att.joint_name
        }) {
        if !array_has(attach_fasteners, fastener.name) {
          attach_fasteners.push(fastener.name)
        }
      }
    }
  }
  for fastener in self.fasteners {
    if !fastener_is_mounting(fastener, self.name, component_names) &&
      !array_has(attach_fasteners, fastener.name) {
      let tools : Array[String] = [tool_for_fastener(fastener)]
      steps.push(
        AssemblyStep::new(
          steps.length() + 1,
          "Install " + fastener.name,
          component=path,
          fasteners=[fastener.name],
          tools~,
          notes=fastener_note(fastener),
        ),
      )
    }
  }
  for att in self.attachments {
    let child_path = path + "/" + att.child.name
    att.child.collect_assembly_steps(child_path, component_names, steps)
    let used_fasteners : Array[String] = []
    let tools : Array[String] = []
    for fastener in att.child.fasteners {
      if fastener.references.fold(init=false, fn(acc, reference) {
          acc || reference == self.name || reference == att.joint_name
        }) {
        used_fasteners.push(fastener.name)
        let tool = tool_for_fastener(fastener)
        if !array_has(tools, tool) {
          tools.push(tool)
        }
      }
    }
    for fastener in self.fasteners {
      if fastener.references.fold(init=false, fn(acc, reference) {
          acc || reference == att.child.name || reference == att.joint_name
        }) {
        if !array_has(used_fasteners, fastener.name) {
          used_fasteners.push(fastener.name)
        }
        let tool = tool_for_fastener(fastener)
        if !array_has(tools, tool) {
          tools.push(tool)
        }
      }
    }
    steps.push(
      AssemblyStep::new(
        steps.length() + 1,
        "Attach " + att.child.name + " to " + self.name,
        component=child_path,
        joint=Some(att.joint_name),
        fasteners=used_fasteners,
        tools~,
        notes="mate " +
          self.name +
          "/" +
          att.parent_mate +
          " -> " +
          att.child.name +
          "/" +
          att.child_mate,
      ),
    )
  }
}

///|
/// Checks the hardware data for problems that would make the assembly
/// unbuildable: bad fastener lengths/engagement/torque, missing parts, invalid
/// fits, and duplicate names.  Returns one message per problem; an empty array
/// means the data is consistent.
pub fn Component::assembly_checks(self : Component) -> Array[String] {
  let warnings : Array[String] = []
  self.collect_assembly_checks(self.name, false, warnings)
  warnings
}

///|
fn Component::collect_assembly_checks(
  self : Component,
  path : String,
  covered_by_part : Bool,
  warnings : Array[String],
) -> Unit {
  let self_is_part = match self.part {
    Some(_) => true
    None => false
  }
  let self_covered = covered_by_part || self_is_part
  let seen_fasteners : Array[String] = []
  for fastener in self.fasteners {
    if array_has(seen_fasteners, fastener.name) {
      warnings.push(path + ": duplicate fastener name '" + fastener.name + "'")
    } else {
      seen_fasteners.push(fastener.name)
    }
    if fastener.quantity <= 0 {
      warnings.push(
        path +
        ": fastener '" +
        fastener.name +
        "' has quantity " +
        fastener.quantity.to_string(),
      )
    }
    if fastener.length_mm <= 0.0 {
      warnings.push(path + ": fastener '" + fastener.name + "' has no length")
    }
    if fastener.engagement_mm <= 0.0 {
      warnings.push(
        path + ": fastener '" + fastener.name + "' has no thread engagement",
      )
    } else if fastener.length_mm > 0.0 &&
      fastener.engagement_mm > fastener.length_mm {
      warnings.push(
        path +
        ": fastener '" +
        fastener.name +
        "' engages " +
        fastener.engagement_mm.to_string() +
        " mm of a " +
        fastener.length_mm.to_string() +
        " mm screw",
      )
    }
    match fastener.kind {
      Bolt | Screw =>
        if fastener.torque_nm <= 0.0 {
          warnings.push(
            path + ": fastener '" + fastener.name + "' has no torque",
          )
        }
      _ => ()
    }
    if fastener.references.length() == 0 {
      warnings.push(
        path + ": fastener '" + fastener.name + "' has no references",
      )
    }
    match fastener.part {
      None =>
        warnings.push(
          path + ": fastener '" + fastener.name + "' has no PartMeta",
        )
      Some(_) => ()
    }
  }
  let seen_ports : Array[String] = []
  for port in self.ports {
    if array_has(seen_ports, port.name) {
      warnings.push(path + ": duplicate port name '" + port.name + "'")
    } else {
      seen_ports.push(port.name)
    }
  }
  let seen_fits : Array[String] = []
  for fit in self.fits {
    if array_has(seen_fits, fit.name) {
      warnings.push(path + ": duplicate fit name '" + fit.name + "'")
    } else {
      seen_fits.push(fit.name)
    }
    if fit.min_mm > fit.max_mm {
      warnings.push(path + ": fit '" + fit.name + "' has min > max")
    } else if fit.nominal_mm < fit.min_mm || fit.nominal_mm > fit.max_mm {
      warnings.push(
        path +
        ": fit '" +
        fit.name +
        "' nominal " +
        fit.nominal_mm.to_string() +
        " mm is outside [" +
        fit.min_mm.to_string() +
        ", " +
        fit.max_mm.to_string() +
        "] mm",
      )
    }
  }
  if !self_covered {
    for body in self.bodies {
      match body.part {
        None =>
          warnings.push(path + ": body '" + body.name + "' has no PartMeta")
        Some(_) => ()
      }
    }
  }
  self.collect_electronics_checks(path, warnings)
  for att in self.attachments {
    // An internal attachment belongs to this purchased/assembled item; an
    // external one is a separate item even when the parent has a part.
    let child_covered = if att.bom_external { false } else { self_covered }
    att.child.collect_assembly_checks(
      path + "/" + att.child.name,
      child_covered,
      warnings,
    )
  }
}
