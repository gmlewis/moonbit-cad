///|
/// Hardware: ISO fasteners, motion parts, T-slot extrusions, and the
/// structural brackets and couplers that compose them.
///
/// Every builder delegates primitive geometry to
/// `gmlewis/step/components/*` and adds named mates, purchasing metadata, and
/// CAD/URDF bodies.

///|
fn[T] step_error(context : String, error : @step_common.SpecError) -> T {
  abort("\{context}: \{error.to_string()}")
}

///|
/// True for `Detailed` or `FullyModeled`.
fn detail_is_rich(detail : @step_common.DetailLevel) -> Bool {
  match detail {
    @step_common.DetailLevel::Simplified => false
    _ => true
  }
}

///|
fn[T] expect_step(
  context : String,
  result : Result[T, @step_common.SpecError],
) -> T {
  match result {
    Ok(value) => value
    Err(error) => step_error(context, error)
  }
}

///|
/// A socket-head cap screw (ISO 4762) with the head seat at `z = 0`.
///
/// The shank extends along `-Z` and the head along `+Z`.
pub fn iso_shcs_screw(
  name~ : String = "shcs",
  size~ : @step_standards.MetricSize = @step_standards.M3,
  length_mm~ : Double = 12.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let step_comp = match
    @step_fasteners.iso4762_screw(size, length_mm, detail~, threads?) {
    Ok(comp) => comp
    Err(error) => step_error("ISO 4762 screw", error)
  }
  let dims = match @step_standards.iso4762_size(size) {
    Ok(dims) => dims
    Err(error) => step_error("ISO 4762 dimensions", error)
  }
  let part = purchased_part(
    "ISO4762-\{size.designation()}x\{length_mm}",
    "ISO 4762 socket head cap screw \{size.designation()} x \{length_mm} mm",
    "steel",
    0.35,
    supplier_url="https://www.mcmaster.com/screws/socket-head-cap-screws/",
  )
  // The STEP component already uses the head-seat frame: head 0..k, shank
  // -length..0. Do not translate it again.
  @cad.Component::from_step_component(name, step_comp, part=Some(part))
  .add_mate_mm_deg("head_seat")
  .add_mate_mm_deg("tip", z=-length_mm)
  .add_mate_mm_deg("head_top", z=dims.head_height_mm)
  .with_param("thread", size.designation())
  .with_param("length_mm", length_mm.to_string())
}

///|
/// A countersunk flat-head socket screw (ISO 10642) with its flush head top
/// at `z = 0`.
///
/// Both head and shank extend along `-Z` to `-length_mm`.
pub fn iso_cs_screw(
  name~ : String = "cs_screw",
  size~ : @step_standards.MetricSize = @step_standards.M4,
  length_mm~ : Double = 8.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let step_comp = match
    @step_fasteners.iso10642_screw(size, length_mm, detail~, threads?) {
    Ok(comp) => comp
    Err(error) => step_error("ISO 10642 screw", error)
  }
  let dims = match @step_standards.iso10642_size(size) {
    Ok(dims) => dims
    Err(error) => step_error("ISO 10642 dimensions", error)
  }
  let part = purchased_part(
    "ISO10642-\{size.designation()}x\{length_mm}",
    "ISO 10642 countersunk socket head cap screw \{size.designation()} x \{length_mm} mm",
    "steel",
    0.35,
    supplier_url="https://www.mcmaster.com/screws/flat-head-socket-cap-screws/",
  )
  @cad.Component::from_step_component(name, step_comp, part=Some(part))
  .add_mate_mm_deg("head_top")
  .add_mate_mm_deg("head_seat", z=-dims.head_height_mm)
  .add_mate_mm_deg("tip", z=-length_mm)
  .with_param("thread", size.designation())
  .with_param("length_mm", length_mm.to_string())
}

///|
/// A hex-head bolt (ISO 4017) with the head seat at `z = 0`.
pub fn iso_hex_bolt(
  name~ : String = "hex_bolt",
  size~ : @step_standards.MetricSize = @step_standards.M6,
  length_mm~ : Double = 25.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let step_comp = match
    @step_fasteners.iso4017(size, length_mm, detail~, threads?) {
    Ok(comp) => comp
    Err(error) => step_error("ISO 4017 bolt", error)
  }
  let spec = match @step_standards.iso4017_spec(size, length_mm) {
    Ok(spec) => spec
    Err(error) => step_error("ISO 4017 dimensions", error)
  }
  let part = purchased_part(
    "ISO4017-\{size.designation()}x\{length_mm}",
    "ISO 4017 hex bolt \{size.designation()} x \{length_mm} mm",
    "steel",
    0.40,
  )
  // The STEP component already uses the head-seat frame: head 0..k, shank
  // -length..0. Do not translate it again.
  @cad.Component::from_step_component(name, step_comp, part=Some(part))
  .add_mate_mm_deg("head_seat")
  .add_mate_mm_deg("tip", z=-length_mm)
  .add_mate_mm_deg("head_top", z=spec.size_dims.head_height_mm)
  .with_param("thread", size.designation())
  .with_param("length_mm", length_mm.to_string())
}

///|
/// A hex nut (ISO 4032) with its bearing face at `z = 0`.
pub fn iso_hex_nut(
  name~ : String = "hex_nut",
  size~ : @step_standards.MetricSize = @step_standards.M3,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let step_comp = match @step_fasteners.iso4032_nut(size, detail~, threads?) {
    Ok(comp) => comp
    Err(error) => step_error("ISO 4032 nut", error)
  }
  let dims = match @step_standards.iso4032_size(size) {
    Ok(dims) => dims
    Err(error) => step_error("ISO 4032 dimensions", error)
  }
  let part = purchased_part(
    "ISO4032-\{size.designation()}",
    "ISO 4032 hex nut \{size.designation()}",
    "steel",
    0.10,
  )
  @cad.Component::from_step_component(name, step_comp, part=Some(part))
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=dims.height_mm)
  .with_param("thread", size.designation())
}

///|
/// A flat washer (ISO 7089) with its bottom face at `z = 0`.
pub fn iso_flat_washer(
  name~ : String = "washer",
  size~ : @step_standards.MetricSize = @step_standards.M3,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let step_comp = match @step_fasteners.iso7089_washer(size, detail~) {
    Ok(comp) => comp
    Err(error) => step_error("ISO 7089 washer", error)
  }
  let dims = match @step_standards.iso7089_size(size) {
    Ok(dims) => dims
    Err(error) => step_error("ISO 7089 dimensions", error)
  }
  let part = purchased_part(
    "ISO7089-\{size.designation()}",
    "ISO 7089 flat washer \{size.designation()}",
    "steel",
    0.03,
  )
  @cad.Component::from_step_component(name, step_comp, part=Some(part))
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=dims.thickness_mm)
}

///|
/// A threaded rod / stud (DIN 976) centered on `z = 0`.
pub fn din976_stud(
  name~ : String = "stud",
  size~ : @step_standards.MetricSize = @step_standards.M3,
  length_mm~ : Double = 30.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let step_comp = match
    @step_fasteners.din976(size, length_mm, detail~, threads?) {
    Ok(comp) => comp
    Err(error) => step_error("DIN 976 stud", error)
  }
  let part = purchased_part(
    "DIN976-\{size.designation()}x\{length_mm}",
    "DIN 976 threaded rod \{size.designation()} x \{length_mm} mm",
    "steel",
    0.60,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    part=Some(part),
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("bottom", z=-length_mm / 2.0)
  .add_mate_mm_deg("top", z=length_mm / 2.0)
}

///|
/// A hex standoff centered on `z = 0`.
pub fn hex_standoff(
  name~ : String = "standoff",
  length_mm~ : Double = 20.0,
  across_flats_mm~ : Double = 6.0,
  bore_diam_mm~ : Double = 3.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::kg_per_m3(8500.0),
) -> @cad.Component {
  let step_comp = match
    @step_motion.standoff(across_flats_mm, length_mm, bore_diam_mm, detail~) {
    Ok(comp) => comp
    Err(error) => step_error("hex standoff", error)
  }
  let part = purchased_part(
    "STANDOFF-\{across_flats_mm}-\{length_mm}",
    "Hex standoff \{across_flats_mm} mm AF x \{length_mm} mm",
    "brass",
    1.20,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("bottom", z=-length_mm / 2.0)
  .add_mate_mm_deg("top", z=length_mm / 2.0)
}

///|
/// A cylindrical spacer centered on `z = 0`.
pub fn cylindrical_spacer(
  name~ : String = "spacer",
  outer_diam_mm~ : Double = 8.0,
  bore_diam_mm~ : Double = 4.2,
  length_mm~ : Double = 10.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = match
    @step_motion.spacer(outer_diam_mm, bore_diam_mm, length_mm) {
    Ok(comp) => comp
    Err(error) => step_error("spacer", error)
  }
  let part = purchased_part(
    "SPACER-\{outer_diam_mm}x\{bore_diam_mm}x\{length_mm}",
    "Spacer \{outer_diam_mm} x \{bore_diam_mm} x \{length_mm} mm",
    "aluminum",
    0.80,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("bottom", z=-length_mm / 2.0)
  .add_mate_mm_deg("top", z=length_mm / 2.0)
}

///|
/// A sleeve or flanged bushing centered on `z = 0`.
pub fn sleeve_bushing(
  name~ : String = "bushing",
  bore_diam_mm~ : Double = 8.0,
  outer_diam_mm~ : Double = 12.0,
  length_mm~ : Double = 10.0,
) -> @cad.Component {
  let step_comp = match
    @step_motion.bushing(outer_diam_mm, bore_diam_mm, length_mm) {
    Ok(comp) => comp
    Err(error) => step_error("bushing", error)
  }
  let part = purchased_part(
    "BUSHING-\{outer_diam_mm}x\{bore_diam_mm}x\{length_mm}",
    "Bushing \{outer_diam_mm} x \{bore_diam_mm} x \{length_mm} mm",
    "bronze",
    1.50,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::kg_per_m3(8500.0),
    part=Some(part),
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("bottom", z=-length_mm / 2.0)
  .add_mate_mm_deg("top", z=length_mm / 2.0)
  .add_mate_mm_deg("bore")
}

///|
/// A radial ball bearing centered on `z = 0`.
///
/// Give a bearing designation such as `"608"` or explicit bore/outer/width
/// dimensions.
pub fn ball_bearing(
  name~ : String = "bearing",
  designation~ : String = "",
  outer_diam_mm~ : Double = 22.0,
  inner_diam_mm~ : Double = 8.0,
  width_mm~ : Double = 7.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
) -> @cad.Component {
  let size = if designation != "" {
    match @step_motion.bearing_size(designation) {
      Ok(size) => size
      Err(error) => step_error("bearing size", error)
    }
  } else {
    {
      designation: "\{inner_diam_mm}x\{outer_diam_mm}x\{width_mm}",
      bore_mm: inner_diam_mm,
      outer_mm: outer_diam_mm,
      width_mm,
    }
  }
  // Rich detail uses the Tier-1 deep-groove bearing (races, balls, and
  // shields); simplified detail keeps the cheap ring/ball primitive.
  let step_comp = if detail_is_rich(detail) {
    match @step_motion.deep_groove_bearing(size, detail~) {
      Ok(comp) => comp
      Err(error) => step_error("deep groove bearing", error)
    }
  } else {
    match @step_motion.bearing(size, detail~) {
      Ok(comp) => comp
      Err(error) => step_error("bearing", error)
    }
  }
  let part = purchased_part(
    "BEARING-\{size.designation}",
    "Radial ball bearing \{size.designation}",
    "steel",
    4.50,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
    z_mm=-size.width_mm / 2.0,
  )
  .add_mate_mm_deg("origin")
  .add_mate_mm_deg("center")
  .add_mate_mm_deg("bore")
  .add_mate_mm_deg("bottom", z=-size.width_mm / 2.0)
  .add_mate_mm_deg("top", z=size.width_mm / 2.0)
  .with_param("bore_mm", size.bore_mm.to_string())
  .with_param("outer_mm", size.outer_mm.to_string())
  .with_param("width_mm", size.width_mm.to_string())
}

///|
/// A T-slot extrusion strut centered on `z = 0`.
pub fn tslot_extrusion_strut(
  name~ : String,
  profile~ : @step_profiles.TSlotProfile = @step_profiles.TSlotProfile::generic_2020(),
  length_mm~ : Double = 200.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let step_comp = match @step_profiles.extrusion(profile, length_mm, detail~) {
    Ok(comp) => comp
    Err(error) => step_error("T-slot extrusion", error)
  }
  let part = fabricated_part(
    "TSLOT-\{profile.designation()}-\{length_mm}",
    "T-slot extrusion \{profile.designation()} x \{length_mm} mm",
    "6063-T5",
    "cut",
    2.40,
  )
  let (width, height) = profile.size()
  @cad.Component::from_step_component(
    name,
    step_comp,
    part=Some(part),
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("start", z=-length_mm / 2.0)
  .add_mate_mm_deg("end", z=length_mm / 2.0)
  .add_mate_mm_deg("side_px", x=width / 2.0, ry_deg=90.0, axis=(1.0, 0.0, 0.0))
  .add_mate_mm_deg(
    "side_nx",
    x=-width / 2.0,
    ry_deg=-90.0,
    axis=(-1.0, 0.0, 0.0),
  )
  .add_mate_mm_deg(
    "side_py",
    y=height / 2.0,
    rx_deg=-90.0,
    axis=(0.0, 1.0, 0.0),
  )
  .add_mate_mm_deg(
    "side_ny",
    y=-height / 2.0,
    rx_deg=90.0,
    axis=(0.0, -1.0, 0.0),
  )
  .with_param("profile", profile.designation())
  .with_param("length_mm", length_mm.to_string())
}

///|
/// Converts a STEP assembly into one CAD component.
fn component_from_assembly(
  name : String,
  description : String,
  assembly : @step_assemblies.Assembly,
) -> @cad.Component {
  let mut comp = @cad.Component::new(name, description~)
  for item in assembly.items() {
    for node in item.component.nodes_under(item.placement) {
      let (x0, x1, y0, y1, z0, z1) = node.bounding_box()
      let sx = if x1 - x0 > 1.0e-3 { x1 - x0 } else { 1.0 }
      let sy = if y1 - y0 > 1.0e-3 { y1 - y0 } else { 1.0 }
      let sz = if z1 - z0 > 1.0e-3 { z1 - z0 } else { 1.0 }
      let origin = @urdf.Origin::from_mm_deg(
        x=(x0 + x1) / 2.0,
        y=(y0 + y1) / 2.0,
        z=(z0 + z1) / 2.0,
      )
      let inertial = @urdf.Inertial::from_box_density(
        sx / 1000.0,
        sy / 1000.0,
        sz / 1000.0,
        density=@urdf.Density::aluminum_6061(),
        origin~,
      )
      let collision = @urdf.Collision::new(
        @urdf.Geometry::box_mm(sx, sy, sz),
        name=Some(node.name),
        origin~,
      )
      comp = comp.add_body(
        @cad.BodyPart::custom(
          node.name,
          node,
          inertial,
          collisions=[collision],
          density=@urdf.Density::aluminum_6061(),
        ),
      )
    }
  }
  comp
}

///|
/// A bolted T-slot extrusion frame, resting on `z = 0`.
pub fn tslot_frame(
  name~ : String = "extrusion_frame",
  width_mm~ : Double = 300.0,
  depth_mm~ : Double = 200.0,
  height_mm~ : Double = 200.0,
  profile~ : @step_profiles.TSlotProfile = @step_profiles.TSlotProfile::generic_2020(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let assembly = match
    @step_assemblies.extrusion_frame(
      width_mm,
      depth_mm,
      height_mm,
      profile,
      detail~,
    ) {
    Ok(assembly) => assembly
    Err(error) => step_error("extrusion frame", error)
  }
  component_from_assembly(name, "T-slot extrusion frame", assembly)
  .with_param("width_mm", width_mm.to_string())
  .with_param("depth_mm", depth_mm.to_string())
  .with_param("height_mm", height_mm.to_string())
  .with_part(
    fabricated_part(
      "TSLOT-FRAME-\{width_mm}x\{depth_mm}x\{height_mm}",
      "T-slot extrusion frame",
      "6063-T5",
      "cut",
      40.0,
    ),
  )
}

///|
/// A compression spring centered on `z = 0`.
pub fn compression_spring_part(
  name~ : String = "spring",
  wire_diam_mm~ : Double = 3.0,
  mean_diam_mm~ : Double = 24.0,
  free_length_mm~ : Double = 60.0,
  active_coils~ : Int32 = 6,
) -> @cad.Component {
  let step_comp = match
    @step_motion.compression_spring(
      mean_diam_mm, wire_diam_mm, free_length_mm, active_coils,
    ) {
    Ok(comp) => comp
    Err(error) => step_error("compression spring", error)
  }
  let part = purchased_part(
    "SPRING-\{wire_diam_mm}x\{mean_diam_mm}x\{free_length_mm}",
    "Compression spring \{wire_diam_mm} x \{mean_diam_mm} x \{free_length_mm} mm",
    "spring steel",
    2.00,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    part=Some(part),
    z_mm=-free_length_mm / 2.0,
  )
  .add_mate_mm_deg("bottom", z=-free_length_mm / 2.0)
  .add_mate_mm_deg("top", z=free_length_mm / 2.0)
}

///|
/// A rigid shaft coupler with two different bores.
pub fn shaft_coupler(
  name~ : String = "coupler",
  outer_diam_mm~ : Double = 19.0,
  bore_in_mm~ : Double = 5.0,
  bore_out_mm~ : Double = 5.0,
  length_mm~ : Double = 25.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::cyan(),
) -> @cad.Component {
  // Equal bores use the Tier-1 rigid coupling. Stepped bores keep the
  // two-bore composite that the lead-screw gripper needs.
  if bore_in_mm == bore_out_mm {
    return rigid_coupling_part(
        name~,
        outer_diam_mm~,
        bore_diam_mm=bore_in_mm,
        length_mm~,
      )
      .with_param("outer_diam_mm", outer_diam_mm.to_string())
      .with_param("bore_in_mm", bore_in_mm.to_string())
      .with_param("bore_out_mm", bore_out_mm.to_string())
      .with_param("length_mm", length_mm.to_string())
  }
  let half = length_mm / 2.0
  let part = purchased_part(
    "COUPLER-\{outer_diam_mm}-\{length_mm}",
    "Shaft coupler \{outer_diam_mm} mm",
    "aluminum",
    6.0,
    supplier_url="https://www.mcmaster.com/shaft-couplings/",
  )
  @cad.Component::new(name, description="Shaft coupler")
  .with_param("outer_diam_mm", outer_diam_mm.to_string())
  .with_param("bore_in_mm", bore_in_mm.to_string())
  .with_param("bore_out_mm", bore_out_mm.to_string())
  .with_param("length_mm", length_mm.to_string())
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_input",
      outer_diam_mm,
      bore_in_mm,
      half,
      z_mm=-half / 2.0,
      density~,
      color~,
    ),
  )
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_output",
      outer_diam_mm,
      bore_out_mm,
      half,
      z_mm=half / 2.0,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("input_shaft", z=-length_mm / 2.0)
  .add_mate_mm_deg("output_shaft", z=length_mm / 2.0)
  .with_part(part)
}

///|
/// Translates a closed line/arc profile by `(dx, dy)` millimeters.
fn arc_segments_at(
  segments : Array[@step_cad.ProfileSegment],
  dx : Double,
  dy : Double,
) -> Array[@step_cad.ProfileSegment] {
  let shift = fn(point : (Double, Double)) { (point.0 + dx, point.1 + dy) }
  segments.map(fn(segment) {
    match segment {
      @step_cad.SegmentLine(a, b) => @step_cad.SegmentLine(shift(a), shift(b))
      @step_cad.SegmentArc(a, b, center) =>
        @step_cad.SegmentArc(shift(a), shift(b), shift(center))
    }
  })
}

///|
/// A centered rectangle as a counter-clockwise line loop.
fn rect_arc_segments(
  width_mm : Double,
  height_mm : Double,
) -> Array[@step_cad.ProfileSegment] {
  let hx = width_mm / 2.0
  let hy = height_mm / 2.0
  let p0 : (Double, Double) = (-hx, -hy)
  let p1 : (Double, Double) = (hx, -hy)
  let p2 : (Double, Double) = (hx, hy)
  let p3 : (Double, Double) = (-hx, hy)
  [
    @step_cad.SegmentLine(p0, p1),
    @step_cad.SegmentLine(p1, p2),
    @step_cad.SegmentLine(p2, p3),
    @step_cad.SegmentLine(p3, p0),
  ]
}

///|
/// Builds a body from a closed line/arc profile with exact circular edges.
fn arc_profile_body(
  name : String,
  outer : Array[@step_cad.ProfileSegment],
  height_mm : Double,
  holes : Array[Array[@step_cad.ProfileSegment]],
  density : @urdf.Density,
  color : @step_cad.Rgb,
  z_mm : Double,
) -> @cad.BodyPart {
  let profile = @step_cad.ExtrudedArcProfile::new(outer, height_mm, holes~)
  let node = profile
    .as_shape()
    .with_name(name)
    .with_color(color)
    .translate(z=z_mm)
  let (x0, x1, y0, y1, z0, z1) = node.bounding_box()
  let sx = if x1 - x0 > 1.0e-3 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-3 { y1 - y0 } else { 1.0 }
  let sz = if z1 - z0 > 1.0e-3 { z1 - z0 } else { 1.0 }
  let origin = @urdf.Origin::from_mm_deg(
    x=(x0 + x1) / 2.0,
    y=(y0 + y1) / 2.0,
    z=(z0 + z1) / 2.0,
  )
  let mass = profile.volume() / 1.0e9 * density.to_kg_per_m3()
  let inertial = @urdf.Inertial::from_box(
    sx / 1000.0,
    sy / 1000.0,
    sz / 1000.0,
    mass~,
    origin~,
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::cylinder_mm(sx / 2.0, height_mm),
    name=Some(name),
    origin=@urdf.Origin::from_mm_deg(z=(z0 + z1) / 2.0),
  )
  @cad.BodyPart::custom(name, node, inertial, collisions=[collision], density~)
}

///|
/// A circular flange plate with a center bore and a bolt circle.
pub fn flange_plate(
  name~ : String = "flange_plate",
  outer_diam_mm~ : Double = 60.0,
  center_bore_mm~ : Double = 22.0,
  thickness_mm~ : Double = 6.0,
  bolt_count~ : Int32 = 4,
  bolt_circle_mm~ : Double = 44.0,
  bolt_diam_mm~ : Double = 4.2,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  // Exact line/arc loops: the rim and every hole are true cylindrical
  // surfaces, not 48- or 64-sided polygon approximations.
  let outer = @step_gears.arc_circle_segments(outer_diam_mm)
  let hole_loops : Array[Array[@step_cad.ProfileSegment]] = []
  if center_bore_mm > 0.0 {
    hole_loops.push(@step_gears.arc_circle_segments(center_bore_mm))
  }
  let radius = bolt_circle_mm / 2.0
  for i in 0..<bolt_count {
    let theta = 2.0 * @math.PI * i.to_double() / bolt_count.to_double()
    hole_loops.push(
      arc_segments_at(
        @step_gears.arc_circle_segments(bolt_diam_mm),
        radius * @math.cos(theta),
        radius * @math.sin(theta),
      ),
    )
  }
  let mut comp = @cad.Component::new(name, description="Flange plate")
    .with_param("outer_diam_mm", outer_diam_mm.to_string())
    .with_param("center_bore_mm", center_bore_mm.to_string())
    .with_param("thickness_mm", thickness_mm.to_string())
    .with_param("bolt_count", bolt_count.to_string())
    .add_body(
      arc_profile_body(
        name + "_body",
        outer,
        thickness_mm,
        hole_loops,
        density,
        color,
        -thickness_mm / 2.0,
      ),
    )
    .add_mate_mm_deg("bottom", z=-thickness_mm / 2.0)
    .add_mate_mm_deg("top", z=thickness_mm / 2.0)
  let part = fabricated_part(
    "FLANGE-\{outer_diam_mm}-\{thickness_mm}",
    "Flange plate \{outer_diam_mm} x \{thickness_mm}",
    "6061-T6",
    "3D print / CNC",
    15.0,
  )
  let radius = bolt_circle_mm / 2.0
  for i in 0..<bolt_count {
    let theta = 2.0 * @math.PI * i.to_double() / bolt_count.to_double()
    comp = comp.add_mate_mm_deg(
      "bolt_\{i}",
      x=radius * @math.cos(theta),
      y=radius * @math.sin(theta),
    )
  }
  comp.with_part(part)
}

///|
/// An L-shaped mounting bracket: a base plate, an upright wall, and a
/// clearance hole through the upright.
pub fn l_bracket(
  name~ : String = "l_bracket",
  width_mm~ : Double = 40.0,
  leg_a_mm~ : Double = 45.0,
  leg_b_mm~ : Double = 45.0,
  thickness_mm~ : Double = 5.0,
  hole_diam_mm~ : Double = 5.0,
  wall_hole_diam_mm~ : Double = 22.5,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let wall_z = leg_b_mm * 0.6
  let upright_center_z = (thickness_mm + leg_b_mm) / 2.0
  let wall_hole_y = upright_center_z - wall_z
  let part = fabricated_part(
    "LBRACKET-\{width_mm}x\{leg_a_mm}x\{leg_b_mm}",
    "L bracket \{width_mm} x \{leg_a_mm} x \{leg_b_mm}",
    "6061-T6",
    "3D print / CNC",
    18.0,
  )
  let base_holes : Array[Array[@step_cad.ProfileSegment]] = if hole_diam_mm >
    0.0 {
    [
      arc_segments_at(
        @step_gears.arc_circle_segments(hole_diam_mm),
        0.0,
        leg_a_mm * 0.3,
      ),
    ]
  } else {
    []
  }
  let wall_holes : Array[Array[@step_cad.ProfileSegment]] = if wall_hole_diam_mm >
    0.0 {
    [
      arc_segments_at(
        @step_gears.arc_circle_segments(wall_hole_diam_mm),
        0.0,
        wall_hole_y,
      ),
    ]
  } else {
    []
  }
  @cad.Component::new(name, description="L bracket")
  .with_param("width_mm", width_mm.to_string())
  .with_param("leg_a_mm", leg_a_mm.to_string())
  .with_param("leg_b_mm", leg_b_mm.to_string())
  .with_param("thickness_mm", thickness_mm.to_string())
  .with_param("wall_hole_diam_mm", wall_hole_diam_mm.to_string())
  .add_body(
    arc_profile_body(
      name + "_base",
      rect_arc_segments(width_mm, leg_a_mm),
      thickness_mm,
      base_holes,
      density,
      color,
      0.0,
    ).transform_by(
      @cad.urdf_transform_from_mm_deg(
        y_mm=leg_a_mm / 2.0,
        z_mm=thickness_mm / 2.0,
      ),
    ),
  )
  .add_body(
    arc_profile_body(
      name + "_upright",
      rect_arc_segments(width_mm, leg_b_mm - thickness_mm),
      thickness_mm,
      wall_holes,
      density,
      color,
      0.0,
    ).transform_by(
      @cad.urdf_transform_from_mm_deg(
        y_mm=thickness_mm / 2.0,
        z_mm=upright_center_z,
        rx_deg=-90.0,
      ),
    ),
  )
  .add_mate_mm_deg("base_mount", y=leg_a_mm * 0.6)
  .add_mate_mm_deg("base_top", y=leg_a_mm * 0.6, z=thickness_mm)
  .add_mate_mm_deg("wall_mount", z=leg_b_mm * 0.6, rx_deg=-90.0)
  .with_part(part)
}

///|
/// A clevis / servo U-bracket with two parallel arms and a pivot bore.
pub fn u_bracket(
  name~ : String = "u_bracket",
  inner_span_mm~ : Double = 50.0,
  arm_length_mm~ : Double = 45.0,
  width_mm~ : Double = 36.0,
  thickness_mm~ : Double = 5.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let half_span = (inner_span_mm + thickness_mm) / 2.0
  let part = fabricated_part(
    "UBRACKET-\{inner_span_mm}x\{arm_length_mm}",
    "U bracket \{inner_span_mm} x \{arm_length_mm}",
    "6061-T6",
    "3D print / CNC",
    16.0,
  )
  @cad.Component::new(name, description="U bracket")
  .with_param("inner_span_mm", inner_span_mm.to_string())
  .with_param("arm_length_mm", arm_length_mm.to_string())
  .with_param("width_mm", width_mm.to_string())
  .with_param("thickness_mm", thickness_mm.to_string())
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_base",
      inner_span_mm + 2.0 * thickness_mm,
      width_mm,
      thickness_mm,
      density~,
      color~,
    ),
  )
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_arm_left",
      thickness_mm,
      width_mm,
      arm_length_mm,
      x_mm=-half_span,
      z_mm=thickness_mm / 2.0 + arm_length_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_arm_right",
      thickness_mm,
      width_mm,
      arm_length_mm,
      x_mm=half_span,
      z_mm=thickness_mm / 2.0 + arm_length_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("base_mount", z=-thickness_mm / 2.0)
  .add_mate_mm_deg(
    "pivot",
    z=thickness_mm / 2.0 + arm_length_mm * 0.9,
    ry_deg=90.0,
    axis=(1.0, 0.0, 0.0),
  )
  .with_part(part)
}

///|
/// A heat-set threaded insert.
pub fn heat_set_insert(
  name~ : String = "heat_set_insert",
  outer_diam_mm~ : Double = 4.0,
  inner_diam_mm~ : Double = 3.0,
  length_mm~ : Double = 5.0,
  density~ : @urdf.Density = @urdf.Density::kg_per_m3(8500.0),
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
) -> @cad.Component {
  let part = purchased_part(
    "INSERT-\{inner_diam_mm}",
    "Heat-set insert \{inner_diam_mm} mm",
    "brass",
    0.08,
  )
  // The Tier-1 M3 insert models the knurled body; custom sizes use a plain
  // tube of the requested dimensions.
  if inner_diam_mm == 3.0 {
    let step_comp = match @step_fasteners.heat_set_insert_m3("short") {
      Ok(comp) => comp
      Err(error) => step_error("heat-set insert", error)
    }
    return hardware_from_step(
        name,
        step_comp,
        "Heat-set insert",
        part,
        ["seat", "top"],
        density~,
      )
      .with_param("inner_diam_mm", inner_diam_mm.to_string())
      .with_param("outer_diam_mm", outer_diam_mm.to_string())
      .with_param("length_mm", length_mm.to_string())
  }
  @cad.Component::new(name, description="Heat-set insert")
  .with_param("inner_diam_mm", inner_diam_mm.to_string())
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_body",
      outer_diam_mm,
      inner_diam_mm,
      length_mm,
      z_mm=length_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("seat")
  .add_mate_mm_deg("top", z=length_mm)
  .with_part(part)
}

///|
/// Wraps a Tier-1 STEP component as purchased hardware with named mates.
fn hardware_from_step(
  name : String,
  step_comp : @step_common.Component,
  description : String,
  part : @cad.PartMeta,
  mates : Array[String],
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  z_mm~ : Double = 0.0,
) -> @cad.Component {
  let mut comp = @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
    z_mm~,
  )
  for mate in mates {
    comp = comp.add_mate_mm_deg(mate)
  }
  comp.with_description(description)
}

///|
/// Wraps a Tier-1 STEP component as fabricated hardware with named mates.
fn fabricated_from_step(
  name : String,
  step_comp : @step_common.Component,
  description : String,
  part : @cad.PartMeta,
  mates : Array[String],
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  z_mm~ : Double = 0.0,
) -> @cad.Component {
  let mut comp = @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
    z_mm~,
  )
  for mate in mates {
    comp = comp.add_mate_mm_deg(mate)
  }
  comp.with_description(description)
}

///|
/// A V-Slot aluminum extrusion strut centered on `z = 0`.
pub fn vslot_extrusion_strut(
  name~ : String,
  profile~ : @step_profiles.VSlotProfile = @step_profiles.VSlotProfile::vslot_2020(),
  length_mm~ : Double = 200.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let step_comp = expect_step(
    "V-slot extrusion",
    @step_profiles.vslot_extrusion(profile, length_mm, detail~),
  )
  let part = fabricated_part(
    "VSLOT-\{profile.designation()}-\{length_mm}",
    "V-slot extrusion \{profile.designation()} x \{length_mm} mm",
    "6063-T5",
    "cut",
    3.0,
  )
  let (width, height) = profile.size()
  hardware_from_step(
    name,
    step_comp,
    "V-slot extrusion strut",
    part,
    ["start", "end", "side_px", "side_nx", "side_py", "side_ny"],
    density=@urdf.Density::aluminum_6061(),
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("start", z=-length_mm / 2.0)
  .add_mate_mm_deg("end", z=length_mm / 2.0)
  .with_param("profile", profile.designation())
  .with_param("width_mm", width.to_string())
  .with_param("height_mm", height.to_string())
  .with_param("length_mm", length_mm.to_string())
}

///|
/// An extruded T-slot / V-slot nut (drop-in or roll-in).
pub fn extrusion_tnut_part(
  name~ : String = "tnut",
  thread~ : String = "M5",
  slot_width_mm~ : Double = 5.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let spec = expect_step(
    "extrusion T-nut spec",
    @step_fasteners.extrusion_tnut_spec(thread, slot_width_mm~),
  )
  let step_comp = expect_step(
    "extrusion T-nut",
    @step_fasteners.extrusion_tnut(spec, detail~),
  )
  let part = purchased_part(
    "TNUT-\{thread}-\{slot_width_mm}",
    "Extrusion T-nut \{thread}",
    "steel",
    0.25,
  )
  hardware_from_step(name, step_comp, "Extrusion T-nut", part, [
    "seat", "thread",
  ]).with_param("thread", thread)
}

///|
/// A clamp- or set-screw shaft collar centered on `z = 0`.
pub fn shaft_collar(
  name~ : String = "shaft_collar",
  bore_diam_mm~ : Double = 8.0,
  outer_diam_mm~ : Double = 16.0,
  width_mm~ : Double = 8.0,
  style~ : String = "clamp",
  thread_size~ : @step_standards.MetricSize = @step_standards.M3,
) -> @cad.Component {
  let color = @step_cad.Rgb::grey()
  let step_comp = if style == "set_screw" {
    expect_step(
      "set-screw shaft collar",
      @step_motion.set_screw_shaft_collar(
        bore_diam_mm,
        outer_diam_mm,
        width_mm,
        thread=thread_size,
        color~,
      ),
    )
  } else {
    expect_step(
      "clamp shaft collar",
      @step_motion.clamp_shaft_collar(
        bore_diam_mm,
        outer_diam_mm,
        width_mm,
        thread=thread_size,
        color~,
      ),
    )
  }
  let part = purchased_part(
    "COLLAR-\{bore_diam_mm}-\{outer_diam_mm}",
    "Shaft collar \{bore_diam_mm} x \{outer_diam_mm} mm",
    "aluminum",
    1.50,
    supplier_url="https://www.mcmaster.com/shaft-collars/",
  )
  hardware_from_step(
    name,
    step_comp,
    "Shaft collar",
    part,
    ["bore"],
    density=@urdf.Density::aluminum_6061(),
    z_mm=-width_mm / 2.0,
  ).with_param("bore_diam_mm", bore_diam_mm.to_string())
}

///|
/// A flanged bearing housing / pillow block.
pub fn flanged_bearing_block(
  name~ : String = "flanged_bearing_block",
  bearing_outer_mm~ : Double = 22.0,
  bearing_width_mm~ : Double = 7.0,
  flange_diam_mm~ : Double = 0.0,
  bolt_circle_mm~ : Double = 0.0,
) -> @cad.Component {
  let step_comp = expect_step(
    "flanged bearing housing",
    @step_motion.flanged_bearing_housing(
      bearing_outer_mm,
      bearing_width_mm,
      flange_diameter_mm=flange_diam_mm,
      bolt_circle_diameter_mm=bolt_circle_mm,
    ),
  )
  let part = fabricated_part(
    "BEARING-HOUSING-\{bearing_outer_mm}",
    "Flanged bearing housing \{bearing_outer_mm} mm",
    "6061-T6",
    "3D print / CNC",
    7.0,
  )
  hardware_from_step(
    name,
    step_comp,
    "Flanged bearing housing",
    part,
    ["mount", "bore"],
    density=@urdf.Density::aluminum_6061(),
  )
}

///|
/// A GT2 timing pulley.
pub fn gt2_pulley_part(
  name~ : String = "gt2_pulley",
  teeth~ : Int32 = 20,
  belt_width_mm~ : Double = 6.0,
  bore_diam_mm~ : Double = 5.0,
  flanges~ : Bool = true,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let step_comp = expect_step(
    "GT2 pulley",
    @step_motion.gt2_pulley(
      teeth,
      belt_width_mm,
      bore_diam_mm,
      flanges~,
      detail~,
    ),
  )
  let part = purchased_part(
    "GT2-\{teeth}T",
    "GT2 timing pulley \{teeth} teeth",
    "aluminum",
    2.20,
  )
  hardware_from_step(
    name,
    step_comp,
    "GT2 timing pulley",
    part,
    ["bore", "top"],
    density=@urdf.Density::aluminum_6061(),
  ).with_param("teeth", teeth.to_string())
}

///|
/// A multi-diameter stepped shaft with filleted shoulders.
pub fn stepped_shaft_part(
  name~ : String = "stepped_shaft",
  segments~ : Array[(Double, Double)] = [(8.0, 20.0), (10.0, 30.0), (8.0, 20.0)],
  fillet_radius_mm~ : Double = 0.5,
) -> @cad.Component {
  let step_comp = expect_step(
    "stepped shaft",
    @step_motion.filleted_stepped_shaft(segments, fillet_radius_mm~),
  )
  let part = purchased_part(
    "SHAFT-STEPPED-\{segments.length()}",
    "Stepped shaft",
    "steel",
    6.0,
  )
  let total = segments.fold(init=0.0, fn(acc, seg) { acc + seg.1 })
  hardware_from_step(
    name,
    step_comp,
    "Stepped shaft",
    part,
    ["input", "output"],
    z_mm=-total / 2.0,
  )
  .add_mate_mm_deg("input", z=-total / 2.0)
  .add_mate_mm_deg("output", z=total / 2.0)
}

///|
/// A parallel key for a shaft keyway.
pub fn key_part(
  name~ : String = "key",
  length_mm~ : Double = 20.0,
  width_mm~ : Double = 4.0,
  height_mm~ : Double = 4.0,
) -> @cad.Component {
  let step_comp = expect_step(
    "key",
    @step_motion.key(length_mm, width_mm, height_mm),
  )
  let part = purchased_part(
    "KEY-\{width_mm}x\{height_mm}x\{length_mm}",
    "Parallel key",
    "steel",
    0.40,
  )
  hardware_from_step(
    name,
    step_comp,
    "Parallel key",
    part,
    ["center"],
    z_mm=-height_mm / 2.0,
  )
}

///|
/// A rectangular stock plate with optional holes and slots, centered on the
/// origin in X/Y and `z = 0` to `thickness_mm`.
pub fn stock_plate_part(
  name~ : String = "plate",
  width_mm~ : Double = 60.0,
  height_mm~ : Double = 40.0,
  thickness_mm~ : Double = 5.0,
  holes~ : Array[@step_stock.PlateHole] = [],
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let step_comp = expect_step(
    "stock plate",
    @step_stock.plate(width_mm, height_mm, thickness_mm, holes~, detail~),
  )
  let part = fabricated_part(
    "PLATE-\{width_mm}x\{height_mm}x\{thickness_mm}",
    "Stock plate \{width_mm} x \{height_mm} x \{thickness_mm}",
    "6061-T6",
    "3D print / CNC",
    8.0,
  )
  fabricated_from_step(name, step_comp, "Stock plate", part, ["top", "bottom"])
  .add_mate_mm_deg("top", z=thickness_mm)
  .add_mate_mm_deg("bottom")
}

///|
/// A bearing plate with a bearing bore and bolt holes.
pub fn bearing_plate_part(
  name~ : String = "bearing_plate",
  bearing_outer_mm~ : Double = 22.0,
  bore_fit_mm~ : Double = 0.1,
  width_mm~ : Double = 60.0,
  height_mm~ : Double = 60.0,
  thickness_mm~ : Double = 6.0,
  bolt_hole_mm~ : Double = 4.2,
  bolt_spacing_mm~ : Double = 40.0,
) -> @cad.Component {
  let step_comp = expect_step(
    "bearing plate",
    @step_stock.bearing_plate(
      bearing_outer_mm, bore_fit_mm, width_mm, height_mm, thickness_mm, bolt_hole_mm,
      bolt_spacing_mm,
    ),
  )
  let part = fabricated_part(
    "BEARING-PLATE-\{width_mm}x\{height_mm}",
    "Bearing plate \{width_mm} x \{height_mm}",
    "6061-T6",
    "3D print / CNC",
    10.0,
  )
  fabricated_from_step(name, step_comp, "Bearing plate", part, [
    "top", "bottom", "bearing_bore",
  ])
  .add_mate_mm_deg("top", z=thickness_mm)
  .add_mate_mm_deg("bottom")
}

///|
/// An equal-leg angle bar.
pub fn angle_bar_part(
  name~ : String = "angle_bar",
  leg_a_mm~ : Double = 40.0,
  leg_b_mm~ : Double = 40.0,
  thickness_mm~ : Double = 4.0,
  root_radius_mm~ : Double = 4.0,
  toe_radius_mm~ : Double = 1.0,
  length_mm~ : Double = 200.0,
) -> @cad.Component {
  let section = expect_step(
    "angle section",
    @step_stock.angle_section(
      leg_a_mm~,
      leg_b_mm~,
      thickness_mm~,
      root_radius_mm~,
      toe_radius_mm~,
    ),
  )
  let step_comp = expect_step(
    "angle bar",
    @step_stock.angle_bar(section, length_mm),
  )
  let part = purchased_part(
    "ANGLE-\{leg_a_mm}x\{leg_b_mm}x\{thickness_mm}-\{length_mm}",
    "Equal angle \{leg_a_mm} x \{leg_b_mm} x \{thickness_mm}",
    "6061-T6",
    6.0,
  )
  fabricated_from_step(
    name,
    step_comp,
    "Angle bar",
    part,
    ["start", "end"],
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("start", z=-length_mm / 2.0)
  .add_mate_mm_deg("end", z=length_mm / 2.0)
}

///|
/// A V-slot corner bracket.
pub fn vslot_corner_bracket_part(
  name~ : String = "vslot_corner_bracket",
  leg_mm~ : Double = 20.0,
  width_mm~ : Double = 20.0,
  thickness_mm~ : Double = 4.0,
) -> @cad.Component {
  let step_comp = expect_step(
    "V-slot corner bracket",
    @step_profiles.vslot_corner_bracket(leg_mm~, width_mm~, thickness_mm~),
  )
  let part = purchased_part(
    "VSLOT-BRACKET-\{leg_mm}",
    "V-slot corner bracket \{leg_mm} mm",
    "aluminum",
    1.10,
  )
  hardware_from_step(
    name,
    step_comp,
    "V-slot corner bracket",
    part,
    ["mount_a", "mount_b"],
    density=@urdf.Density::aluminum_6061(),
  )
}

///|
/// A V-slot joining plate.
pub fn vslot_joining_plate_part(
  name~ : String = "vslot_joining_plate",
  length_mm~ : Double = 40.0,
  width_mm~ : Double = 20.0,
  thickness_mm~ : Double = 4.0,
  slot_pitch_mm~ : Double = 20.0,
  slot_length_mm~ : Double = 12.0,
  slot_width_mm~ : Double = 5.0,
) -> @cad.Component {
  let step_comp = expect_step(
    "V-slot joining plate",
    @step_stock.vslot_joining_plate(
      length_mm, width_mm, thickness_mm, slot_pitch_mm, slot_length_mm, slot_width_mm,
    ),
  )
  let part = purchased_part(
    "VSLOT-JOIN-\{length_mm}",
    "V-slot joining plate \{length_mm} mm",
    "aluminum",
    1.40,
  )
  hardware_from_step(
    name,
    step_comp,
    "V-slot joining plate",
    part,
    ["top", "bottom"],
    density=@urdf.Density::aluminum_6061(),
  )
}

///|
/// A rigid shaft coupling.
pub fn rigid_coupling_part(
  name~ : String = "rigid_coupling",
  outer_diam_mm~ : Double = 20.0,
  bore_diam_mm~ : Double = 6.0,
  length_mm~ : Double = 25.0,
) -> @cad.Component {
  let step_comp = expect_step(
    "rigid coupling",
    @step_motion.rigid_coupling(bore_diam_mm, outer_diam_mm, length_mm),
  )
  let part = purchased_part(
    "COUPLING-\{outer_diam_mm}-\{bore_diam_mm}-\{length_mm}",
    "Rigid shaft coupling \{outer_diam_mm} mm",
    "aluminum",
    6.0,
  )
  hardware_from_step(
    name,
    step_comp,
    "Rigid shaft coupling",
    part,
    ["input_shaft", "output_shaft"],
    density=@urdf.Density::aluminum_6061(),
    z_mm=-length_mm / 2.0,
  )
  .add_mate_mm_deg("input_shaft", z=-length_mm / 2.0)
  .add_mate_mm_deg("output_shaft", z=length_mm / 2.0)
}

///|
/// A deep-groove ball bearing selected by ISO designation.
pub fn deep_groove_bearing_part(
  name~ : String = "bearing",
  designation~ : String = "608",
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let size = expect_step("bearing size", @step_motion.bearing_size(designation))
  let step_comp = expect_step(
    "deep groove bearing",
    @step_motion.deep_groove_bearing(size, detail~),
  )
  let part = purchased_part(
    "BEARING-\{size.designation}",
    "Deep-groove ball bearing \{size.designation}",
    "steel",
    4.50,
  )
  hardware_from_step(
    name,
    step_comp,
    "Deep-groove ball bearing",
    part,
    ["center", "bottom", "top", "bore"],
    z_mm=-size.width_mm / 2.0,
  )
  .add_mate_mm_deg("bottom", z=-size.width_mm / 2.0)
  .add_mate_mm_deg("top", z=size.width_mm / 2.0)
  .with_param("bore_mm", size.bore_mm.to_string())
  .with_param("outer_mm", size.outer_mm.to_string())
  .with_param("width_mm", size.width_mm.to_string())
}

///|
/// A plate with counterbored through-holes.
pub fn counterbored_plate_part(
  name~ : String = "counterbored_plate",
  width_mm~ : Double = 60.0,
  height_mm~ : Double = 40.0,
  thickness_mm~ : Double = 6.0,
  holes~ : Array[@step_stock.CounterboredHole] = [],
) -> @cad.Component {
  let step_comp = expect_step(
    "counterbored plate",
    @step_stock.plate_with_counterbores(
      width_mm,
      height_mm,
      thickness_mm,
      holes~,
    ),
  )
  let part = fabricated_part(
    "CBORE-PLATE-\{width_mm}x\{height_mm}x\{thickness_mm}",
    "Counterbored plate \{width_mm} x \{height_mm} x \{thickness_mm}",
    "6061-T6",
    "3D print / CNC",
    9.0,
  )
  fabricated_from_step(
    name,
    step_comp,
    "Counterbored plate",
    part,
    ["top", "bottom"],
    density=@urdf.Density::aluminum_6061(),
  )
  .add_mate_mm_deg("top", z=thickness_mm)
  .add_mate_mm_deg("bottom")
}

///|
/// A NEMA stepper mounting plate.
pub fn nema_mount_plate_part(
  name~ : String = "nema_mount_plate",
  designation~ : String = "NEMA17",
  width_mm~ : Double = 60.0,
  height_mm~ : Double = 60.0,
  thickness_mm~ : Double = 5.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let frame = expect_step("NEMA frame", @step_motors.nema_frame(designation))
  let step_comp = expect_step(
    "NEMA mounting plate",
    @step_motors.nema_mounting_plate(
      frame,
      width_mm,
      height_mm,
      thickness_mm,
      detail~,
    ),
  )
  let part = fabricated_part(
    "NEMA-PLATE-\{frame.designation}-\{width_mm}x\{height_mm}",
    "NEMA mounting plate \{frame.designation}",
    "6061-T6",
    "3D print / CNC",
    9.0,
  )
  fabricated_from_step(name, step_comp, "NEMA mounting plate", part, [
    "top", "bottom", "motor_face",
  ])
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=thickness_mm)
}

///|
/// A purchased Maker Store USA part with its real supplier, SKU, and URL.
fn makerstore_part(
  part_number : String,
  description : String,
  material : String,
  finish : String,
  unit_cost_usd : Double,
  supplier_url~ : String,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="Maker Store USA",
    supplier_url~,
    material~,
    process="purchased",
    finish~,
    unit_cost_usd~,
  )
}

///|
/// A Maker Store 20-series L plate with a centred hole grid (SKU
/// `PLATE-40X40L` / `PLATE-40X80L`).
///
/// Inherits the STEP component's face and per-hole `CylindricalBore` mates. The
/// default 40 x 40 x 3 mm plate with a 3 x 3 grid of 5 mm holes on 10 mm centres
/// matches the Maker Store dimensioned drawing.
pub fn makerstore_l_plate(
  name~ : String = "l_plate",
  leg_a_mm~ : Double = 40.0,
  leg_b_mm~ : Double = 40.0,
  width_mm~ : Double = 40.0,
  thickness_mm~ : Double = 3.0,
  hole_diam_mm~ : Double = 5.0,
  pitch_mm~ : Double = 10.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "Maker Store L plate",
    @step_mechanisms.makerstore_l_plate(
      leg_a_mm~,
      leg_b_mm~,
      width_mm~,
      thickness_mm~,
      hole_diameter_mm=hole_diam_mm,
      pitch_mm~,
    ),
  )
  let (sku, price) = if leg_a_mm > 60.0 {
    ("PLATE-40X80L", 6.75)
  } else {
    ("PLATE-40X40L", 4.73)
  }
  let part = makerstore_part(
    sku,
    "Maker Store L plate \{leg_a_mm} x \{leg_b_mm} x \{width_mm} mm",
    "aluminium",
    "black anodized",
    price,
    supplier_url="https://makerstore.cc/product/joining-plates/",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  )
}

///|
/// A Maker Store metric aluminum spacer (SKU `SHIM-SPAC`), OD 10 / ID 5 by
/// default. Inherits the STEP component's bore, outer-seat, and face mates.
pub fn makerstore_aluminum_spacer(
  name~ : String = "spacer",
  length_mm~ : Double = 10.0,
  outer_diam_mm~ : Double = 10.0,
  bore_diam_mm~ : Double = 5.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "Maker Store aluminum spacer",
    @step_motion.makerstore_aluminum_spacer(
      length_mm~,
      outer_diameter_mm=outer_diam_mm,
      inner_diameter_mm=bore_diam_mm,
    ),
  )
  let part = makerstore_part(
    "SHIM-SPAC",
    "Maker Store aluminum spacer OD \{outer_diam_mm} / ID \{bore_diam_mm} x \{length_mm} mm",
    "aluminium",
    "plain",
    0.25,
    supplier_url="https://makerstore.cc/product/metric-aluminum-spacers/",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  )
}

///|
/// A Maker Store 20-series hex sliding T-nut (SKU `HARD-TNUT-SLIDING`).
pub fn makerstore_hex_tnut(
  name~ : String = "tnut",
  thread~ : String = "M5",
  slot_width_mm~ : Double = 5.0,
) -> @cad.Component {
  let step_comp = expect_step(
    "Maker Store sliding T-nut",
    @step_fasteners.makerstore_hex_tnut(thread, slot_width_mm~),
  )
  let part = makerstore_part(
    "HARD-TNUT-SLIDING-\{thread}",
    "Maker Store sliding T-nut \{thread}",
    "steel",
    "plain",
    0.65,
    supplier_url="https://makerstore.cc/product/sliding-t-nut/",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::steel_mild(),
    part=Some(part),
  )
}

///|
/// A Maker Store 40-series sliding block T-nut (SKU
/// `HARD-40S-TNUT-STEEL-SLID-18`).
pub fn makerstore_sliding_tnut(
  name~ : String = "tnut40",
  thread~ : String = "M6",
  slot_width_mm~ : Double = 7.7,
) -> @cad.Component {
  let step_comp = expect_step(
    "Maker Store 40-series sliding T-nut",
    @step_fasteners.makerstore_sliding_tnut(thread, slot_width_mm~),
  )
  let part = makerstore_part(
    "HARD-40S-TNUT-STEEL-SLID-18-\{thread}",
    "Maker Store 40-series sliding T-nut \{thread}",
    "steel",
    "plain",
    0.65,
    supplier_url="https://makerstore.cc/product/hard-40s-tnut-steel-slid-18-1pc/",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::steel_mild(),
    part=Some(part),
  )
}

///|
/// A Maker Store gusseted V-Slot corner bracket (SKU `BRAC-90CAST` at 20 mm,
/// `BRAC-40S-90CAST-B` at 40 mm).
pub fn makerstore_corner_bracket(
  name~ : String = "corner_bracket",
  leg_mm~ : Double = 20.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "Maker Store corner bracket",
    @step_profiles.makerstore_corner_bracket(leg_mm~),
  )
  let (sku, price) = if leg_mm < 30.0 {
    ("BRAC-90CAST", 1.80)
  } else {
    ("BRAC-40S-90CAST-B", 3.40)
  }
  let part = makerstore_part(
    sku,
    "Maker Store V-Slot corner bracket \{leg_mm} mm",
    "aluminium",
    "cast",
    price,
    supplier_url="https://makerstore.cc/product/cast-90-degree-corner-bracket/",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  )
}

///|
/// A Maker Store thrust bearing envelope (SKU `BEAR-F`).
pub fn makerstore_thrust_bearing(
  name~ : String = "thrust_bearing",
  designation~ : String = "F5-10M",
) -> @cad.Component {
  let size = expect_step(
    "Maker Store thrust bearing size",
    @step_motion.thrust_bearing_size(designation),
  )
  let step_comp = expect_step(
    "Maker Store thrust bearing",
    @step_motion.thrust_bearing(size),
  )
  let part = makerstore_part(
    "BEAR-\{designation}",
    "Maker Store thrust bearing \{designation}",
    "bearing steel",
    "ground",
    3.45,
    supplier_url="https://makerstore.cc/product/thrust-bearings/",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::steel_mild(),
    part=Some(part),
  )
}

///|
/// zero_pad_left left-pads a non-negative integer with zeros.
fn zero_pad_left(value : Int32, width : Int32) -> String {
  let mut text = value.to_string()
  while text.length() < width {
    text = "0" + text
  }
  text
}

///|
/// A goBILDA 1120-series U-channel with the measured 8 mm pattern on the base
/// and both legs (SKU `1120-00NN-LLLL`).
pub fn gobilda_u_channel(
  name~ : String = "u_channel",
  holes~ : Int32 = 8,
  length_mm? : Double,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "goBILDA U-channel",
    @step_gobilda.gobilda_u_channel(holes~, length_mm?),
  )
  let length = match length_mm {
    Some(v) => v
    None => (holes.to_double() + 1.0) * 24.0
  }
  let part = purchased_part(
    "1120-00\{zero_pad_left(holes, 2)}-\{zero_pad_left(length.to_int(), 4)}",
    "goBILDA 1120-series U-channel \{holes} hole (\{length} mm)",
    "aluminium",
    0.0,
    supplier_url="https://www.gobilda.com/1120-series-u-channel",
    supplier="goBILDA",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  ).with_param("holes", holes.to_string())
}

///|
/// A goBILDA 1106-series square beam with M4 end tap drills (SKU
/// `1106-00NN-LLLL`).
pub fn gobilda_square_beam(
  name~ : String = "square_beam",
  holes~ : Int32 = 4,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "goBILDA square beam",
    @step_gobilda.gobilda_square_beam(holes~),
  )
  let length = holes.to_double() * 8.0
  let part = purchased_part(
    "1106-00\{zero_pad_left(holes, 2)}-\{zero_pad_left(length.to_int(), 4)}",
    "goBILDA 1106-series square beam \{holes} hole (\{length} mm)",
    "aluminium",
    0.0,
    supplier_url="https://www.gobilda.com/1106-series-square-beam-4-hole-32mm-length",
    supplier="goBILDA",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  ).with_param("holes", holes.to_string())
}

///|
/// A goBILDA 1309 Sonic hub with the measured flexure profile (SKU
/// `1309-0016-4008`).
pub fn gobilda_sonic_hub(
  name~ : String = "sonic_hub",
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "goBILDA Sonic hub",
    @step_gobilda.gobilda_sonic_hub(),
  )
  let part = purchased_part(
    "1309-0016-4008",
    "goBILDA 1309 Sonic hub (8 mm REX bore)",
    "aluminium",
    0.0,
    supplier_url="https://www.gobilda.com/1309-series-sonic-hub-8mm-rex-bore",
    supplier="goBILDA",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  )
}

///|
/// A MotEDis B-type metric T-slot profile with the measured section (20/30/40).
pub fn motedis_b_profile(
  name~ : String = "motedis_b",
  series~ : String = "40",
  length_mm~ : Double = 500.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "MotEDis B-type profile",
    @step_profiles.mot_edis_b_profile_of(series, length_mm~),
  )
  let slot = match series {
    "20" => "6"
    "30" => "8"
    _ => "10"
  }
  let part = purchased_part(
    "P-series-\{series}x\{series}-B\{slot}",
    "MotEDis B-type \{series}x\{series} T-slot profile (slot \{slot})",
    "aluminium",
    0.0,
    supplier_url="https://www.motedis.com/en/B-Type-slot-\{slot}/Slot-profiles",
    supplier="MotEDis",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  )
  .with_param("series", series)
  .with_param("length_mm", length_mm.to_string())
}

///|
/// A Hiwin HGR linear-guideway rail with counterbored mounting holes.
pub fn hiwin_hgr_rail(
  name~ : String = "hgr_rail",
  size~ : String = "HGR15",
  length_mm~ : Double = 400.0,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
) -> @cad.Component {
  let step_comp = expect_step(
    "Hiwin HGR rail",
    @step_mechanisms.hiwin_hgr_rail(size~, length_mm~),
  )
  let part = purchased_part(
    "\{size}R\{length_mm.to_int()}",
    "Hiwin \{size} linear guideway rail (\{length_mm} mm)",
    "bearing steel",
    0.0,
    supplier_url="https://www.hiwin.com/linear-guideways.html",
    supplier="Hiwin",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  )
  .with_param("size", size)
  .with_param("length_mm", length_mm.to_string())
}

///|
/// A Hiwin HGH linear-guideway carriage with the published B x C bolt pattern.
pub fn hiwin_hgh_block(
  name~ : String = "hgh_block",
  size~ : String = "HGH15CA",
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
) -> @cad.Component {
  let step_comp = expect_step(
    "Hiwin HGH carriage",
    @step_mechanisms.hiwin_hgh_block(size~),
  )
  let part = purchased_part(
    size,
    "Hiwin \{size} linear guideway carriage",
    "bearing steel",
    0.0,
    supplier_url="https://www.hiwin.com/linear-guideways.html",
    supplier="Hiwin",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  ).with_param("size", size)
}

///|
/// A Maker Store M5 low-profile socket screw (SKU `SCREWS-M5-LP`), 6-65 mm.
pub fn makerstore_low_profile_screw(
  name~ : String = "low_profile_screw",
  length_mm~ : Double = 16.0,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
) -> @cad.Component {
  let step_comp = expect_step(
    "Maker Store low-profile screw",
    @step_fasteners.low_profile_screw(length_mm~),
  )
  let part = purchased_part(
    "SCREWS-M5-LP-\{length_mm.to_int()}",
    "Maker Store M5 low-profile screw \{length_mm} mm",
    "alloy steel",
    0.0,
    supplier_url="https://makerstore.cc/product/m5-low-profile-screws/",
    supplier="Maker Store USA",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  )
  .add_mate_mm_deg("head-seat")
  .add_mate_mm_deg("thread")
  .with_param("length_mm", length_mm.to_string())
}

///|
/// A REV DUO 15 x 15 mm extrusion with the measured section (REV-41-1568 and
/// its length siblings).
pub fn rev_15mm_extrusion(
  name~ : String = "rev_15mm",
  length_mm~ : Double = 120.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "REV 15 mm extrusion",
    @step_profiles.rev_15mm_extrusion(length_mm~),
  )
  let sku = match length_mm.to_int() {
    120 => "REV-41-1568"
    225 => "REV-41-1431"
    420 => "REV-41-1432"
    1000 => "REV-41-1017"
    _ => "REV-41-15MM"
  }
  let part = purchased_part(
    sku,
    "REV DUO 15 x 15 mm extrusion (\{length_mm} mm)",
    "aluminium 6063-T5",
    0.0,
    supplier_url="https://www.revrobotics.com/15mm-extrusions/",
    supplier="REV Robotics",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  ).with_param("length_mm", length_mm.to_string())
}

///|
/// A REV DUO 45 x 45 mm U-channel with the measured section (REV-41-1741 and
/// its length siblings).
pub fn rev_45mm_uchannel(
  name~ : String = "rev_45mm_uchannel",
  length_mm~ : Double = 440.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let step_comp = expect_step(
    "REV 45 mm U-channel",
    @step_profiles.rev_45mm_uchannel(length_mm~),
  )
  let sku = match length_mm.to_int() {
    24 => "REV-41-1755"
    56 => "REV-41-1753"
    88 => "REV-41-1752"
    152 => "REV-41-1750"
    248 => "REV-41-1747"
    312 => "REV-41-1745"
    376 => "REV-41-1743"
    408 => "REV-41-1742"
    440 => "REV-41-1741"
    1000 => "REV-41-1740"
    _ => "REV-41-45MM-U"
  }
  let part = purchased_part(
    sku,
    "REV DUO 45 x 45 mm U-channel (\{length_mm} mm)",
    "aluminium 6063-T6",
    0.0,
    supplier_url="https://www.revrobotics.com/45mm-u-channels/",
    supplier="REV Robotics",
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
  ).with_param("length_mm", length_mm.to_string())
}
