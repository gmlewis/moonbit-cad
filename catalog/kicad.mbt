///|
/// KiCad position-file import: parse a KiCad `.pos` CSV and build a PCB
/// envelope with mounting holes, connector placements, ports, and mounting
/// hardware.
///
/// This imports the placement layer (board outline, mounting holes, connectors),
/// not the full STEP B-Rep.  The board body is an extruded rectangle with the
/// mounting holes; connector bodies are not modeled.

///|
/// One footprint from a KiCad position file.  Positions are in KiCad board
/// coordinates (millimetres, Y down).
pub(all) struct KiCadFootprint {
  reference : String
  value : String
  footprint : String
  x_mm : Double
  y_mm : Double
  rotation_deg : Double
  side : String
}

///|
pub fn KiCadFootprint::new(
  reference~ : String = "",
  value~ : String = "",
  footprint~ : String = "",
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  rotation_deg~ : Double = 0.0,
  side~ : String = "",
) -> KiCadFootprint {
  { reference, value, footprint, x_mm, y_mm, rotation_deg, side, }
}

///|
fn kicad_cu_at(s : String, i : Int32) -> Int32 {
  UInt16::to_int(String::code_unit_at(s, i))
}

///|
/// Parses a signed decimal number, returning `None` for an empty or invalid
/// field.
fn parse_kicad_number(text : String) -> Double? {
  let t = text.replace(old="\"", new="").trim().to_owned()
  let n = t.length()
  if n == 0 {
    return None
  }
  let zero = Char::to_int('0')
  let nine = Char::to_int('9')
  let mut i = 0
  let mut sign = 1.0
  let first = kicad_cu_at(t, 0)
  if first == Char::to_int('-') {
    sign = -1.0
    i = 1
  } else if first == Char::to_int('+') {
    i = 1
  }
  let mut value = 0.0
  let mut digits = 0
  while i < n {
    let c = kicad_cu_at(t, i)
    if c >= zero && c <= nine {
      value = value * 10.0 + (c - zero).to_double()
      digits = digits + 1
      i = i + 1
    } else {
      break
    }
  }
  if i < n && kicad_cu_at(t, i) == Char::to_int('.') {
    i = i + 1
    let mut scale = 0.1
    while i < n {
      let c = kicad_cu_at(t, i)
      if c >= zero && c <= nine {
        value = value + (c - zero).to_double() * scale
        scale = scale / 10.0
        digits = digits + 1
        i = i + 1
      } else {
        break
      }
    }
  }
  if digits == 0 {
    return None
  }
  Some(sign * value)
}

///|
fn kicad_fields(line : String) -> Array[String] {
  let fields : Array[String] = []
  for field in line.split(",") {
    fields.push(field.to_owned().replace(old="\"", new="").trim().to_owned())
  }
  fields
}

///|
/// Parses a KiCad position-file CSV (`Ref,Val,Package,PosX,PosY,Rot,Side`).
///
/// Malformed lines and the header are skipped, so a partially edited file still
/// yields the placements it contains.
pub fn parse_kicad_pos(text : String) -> Array[KiCadFootprint] {
  let out : Array[KiCadFootprint] = []
  for raw_line in text.split("\n") {
    let line = raw_line.to_owned().trim().to_owned()
    if line == "" {
      continue
    }
    let fields = kicad_fields(line)
    if fields.length() < 7 {
      continue
    }
    if fields[0] == "Ref" || fields[0] == "Component" {
      continue
    }
    match parse_kicad_number(fields[3]) {
      Some(x) =>
        match parse_kicad_number(fields[4]) {
          Some(y) =>
            match parse_kicad_number(fields[5]) {
              Some(rotation) =>
                out.push(
                  KiCadFootprint::new(
                    reference=fields[0],
                    value=fields[1],
                    footprint=fields[2],
                    x_mm=x,
                    y_mm=y,
                    rotation_deg=rotation,
                    side=fields[6],
                  ),
                )
              None => ()
            }
          None => ()
        }
      None => ()
    }
  }
  out
}

///|
fn kicad_port_name(value : String, reference : String) -> String {
  let raw = if value == "" { reference } else { value }
  raw.replace(old=" ", new="_")
}

///|
fn kicad_port_kind(value : String) -> @cad.PortKind {
  if value.contains("power") {
    @cad.PortKind::Power
  } else if value.contains("can") ||
    value.contains("uart") ||
    value.contains("spi") ||
    value.contains("i2c") {
    @cad.PortKind::Bus
  } else if value.contains("motor") ||
    value.contains("step") ||
    value.contains("dir") ||
    value.contains("pwm") ||
    value.contains("servo") {
    @cad.PortKind::Signal
  } else if value.contains("limit") ||
    value.contains("sensor") ||
    value.contains("imu") ||
    value.contains("camera") {
    @cad.PortKind::Sensor
  } else {
    @cad.PortKind::Mechanical
  }
}

///|
fn is_mounting_hole(footprint : KiCadFootprint, match_text : String) -> Bool {
  footprint.footprint.contains(match_text) ||
  footprint.value.contains(match_text)
}

///|
/// Builds a PCB envelope from KiCad placements.
///
/// `origin_x_mm`/`origin_y_mm` locate the board centre in the KiCad file;
/// `flip_y` mirrors KiCad's Y-down coordinates.  When the board dimensions are
/// omitted, they are derived from the placement extents plus `board_margin_mm`.
pub fn pcb_from_kicad(
  name~ : String = "controller_pcb",
  footprints~ : Array[KiCadFootprint] = [],
  board_len_mm~ : Double = 0.0,
  board_w_mm~ : Double = 0.0,
  thickness_mm~ : Double = 1.6,
  origin_x_mm~ : Double = 0.0,
  origin_y_mm~ : Double = 0.0,
  flip_y~ : Bool = true,
  mounting_hole_match~ : String = "MountingHole",
  mounting_hole_diam_mm~ : Double = 2.7,
  board_margin_mm~ : Double = 5.0,
  max_component_height_mm~ : Double = 12.0,
) -> @cad.Component {
  let placed : Array[(KiCadFootprint, Double, Double)] = []
  for footprint in footprints {
    let x = footprint.x_mm - origin_x_mm
    let y = if flip_y {
      -(footprint.y_mm - origin_y_mm)
    } else {
      footprint.y_mm - origin_y_mm
    }
    placed.push((footprint, x, y))
  }
  let mut min_x = 0.0
  let mut max_x = 0.0
  let mut min_y = 0.0
  let mut max_y = 0.0
  if placed.length() > 0 {
    min_x = placed[0].1
    max_x = placed[0].1
    min_y = placed[0].2
    max_y = placed[0].2
    for entry in placed {
      if entry.1 < min_x {
        min_x = entry.1
      }
      if entry.1 > max_x {
        max_x = entry.1
      }
      if entry.2 < min_y {
        min_y = entry.2
      }
      if entry.2 > max_y {
        max_y = entry.2
      }
    }
  }
  let auto_size = board_len_mm <= 0.0 || board_w_mm <= 0.0
  let center_x = if auto_size { (min_x + max_x) / 2.0 } else { 0.0 }
  let center_y = if auto_size { (min_y + max_y) / 2.0 } else { 0.0 }
  let length_mm = if board_len_mm > 0.0 {
    board_len_mm
  } else {
    max_x - min_x + 2.0 * board_margin_mm
  }
  let width_mm = if board_w_mm > 0.0 {
    board_w_mm
  } else {
    max_y - min_y + 2.0 * board_margin_mm
  }
  let mut profile = @step_cad.Profile2D::new(
    @step_cad.Profile2D::centered_rect(length_mm, width_mm),
  )
  let hole_positions : Array[(Double, Double)] = []
  let placements : Array[@cad.PcbPlacement] = []
  let seen_ports : Array[String] = []
  for entry in placed {
    let footprint = entry.0
    let x = entry.1 - center_x
    let y = entry.2 - center_y
    if is_mounting_hole(footprint, mounting_hole_match) {
      hole_positions.push((x, y))
      profile = profile.with_hole_at(x, y, mounting_hole_diam_mm)
    } else {
      placements.push(
        @cad.PcbPlacement::new(
          reference=footprint.reference,
          value=footprint.value,
          footprint=footprint.footprint,
          x_mm=x,
          y_mm=y,
          rotation_deg=if flip_y {
            -footprint.rotation_deg
          } else {
            footprint.rotation_deg
          },
          side=footprint.side,
        ),
      )
    }
  }
  let connectors : Array[String] = []
  for placement in placements {
    let port_name = kicad_port_name(placement.value, placement.reference)
    if !seen_ports.fold(init=false, fn(acc, name) { acc || name == port_name }) {
      seen_ports.push(port_name)
      connectors.push(port_name)
    }
  }
  let spec = @cad.PcbSpec::new(
    model="KICAD-" + length_mm.to_string() + "x" + width_mm.to_string(),
    length_mm~,
    width_mm~,
    thickness_mm~,
    mounting_holes=hole_positions.length(),
    mounting_hole_diam_mm~,
    max_component_height_mm~,
    connectors~,
    placements~,
  )
  let unit_cost_usd = 18.0
  let part = fabricated_part(
    "PCB-KICAD-" + length_mm.to_string() + "x" + width_mm.to_string(),
    "KiCad-imported PCB " + length_mm.to_string() + " x " + width_mm.to_string(),
    "FR-4",
    "assembly",
    unit_cost_usd,
  )
  let mut comp = @cad.Component::new(name, description="KiCad-imported PCB")
    .with_param("board_len_mm", length_mm.to_string())
    .with_param("board_w_mm", width_mm.to_string())
    .with_param("thickness_mm", thickness_mm.to_string())
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_board",
        profile.outer,
        thickness_mm,
        holes=profile.holes,
        z_mm=thickness_mm / 2.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::green(),
      ),
    )
    .add_mate_mm_deg("mount")
    .with_part(part)
    .with_pcb(spec)
  for i in 0..<hole_positions.length() {
    comp = comp.add_mate_mm_deg(
      "bolt_" + i.to_string(),
      x=hole_positions[i].0,
      y=hole_positions[i].1,
    )
  }
  let added_ports : Array[String] = []
  for placement in placements {
    let port_name = kicad_port_name(placement.value, placement.reference)
    if !added_ports.fold(init=false, fn(acc, name) { acc || name == port_name }) {
      added_ports.push(port_name)
      comp = comp.add_port(
        @cad.Port::new(
          port_name,
          kicad_port_kind(placement.value),
          spec=placement.value + " (" + placement.footprint + ")",
        ),
      )
    }
  }
  if hole_positions.length() > 0 {
    let screw = purchased_part(
      "SHCS-M2.5x6", "Socket head cap screw M2.5 x 6", "steel", 0.25,
    )
    comp = comp.add_fastener(
      @cad.Fastener::new(
        "pcb_screws",
        @cad.FastenerKind::Screw,
        thread="M2.5",
        length_mm=6.0,
        engagement_mm=3.0,
        quantity=hole_positions.length(),
        torque_nm=0.4,
        references=[name + "_board"],
        part=Some(screw),
      ),
    )
  }
  comp
}
