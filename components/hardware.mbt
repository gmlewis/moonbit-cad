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
  thread_size? : @step_standards.MetricSize,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
  density~ : @urdf.Density = @urdf.Density::kg_per_m3(8500.0),
) -> @cad.Component {
  let _ = thread_size
  let _ = threads
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
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let _ = detail
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
  flange_outer_mm? : Double,
  flange_thickness_mm? : Double,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let _ = detail
  let _ = flange_outer_mm
  let _ = flange_thickness_mm
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
  let step_comp = match @step_motion.bearing(size, detail~) {
    Ok(comp) => comp
    Err(error) => step_error("bearing", error)
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
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let _ = detail
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
  bore_out_mm~ : Double = 8.0,
  length_mm~ : Double = 25.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::cyan(),
) -> @cad.Component {
  let segments = @step_common.DetailPolicy::for_level(detail).circle_segments
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
      segments~,
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
      segments~,
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
/// A circular flange plate with a center bore and a bolt circle.
pub fn flange_plate(
  name~ : String = "flange_plate",
  outer_diam_mm~ : Double = 60.0,
  center_bore_mm~ : Double = 22.0,
  thickness_mm~ : Double = 6.0,
  bolt_count~ : Int32 = 4,
  bolt_circle_mm~ : Double = 44.0,
  bolt_diam_mm~ : Double = 4.2,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let segments = @step_common.DetailPolicy::for_level(detail).circle_segments
  let profile = @step_cad.Profile2D::new(
      @step_cad.Profile2D::centered_circle(outer_diam_mm, segments~),
    )
    .with_hole_at(0.0, 0.0, center_bore_mm, segments~)
    .with_bolt_circle(bolt_count, bolt_circle_mm / 2.0, bolt_diam_mm, segments~)
  let mut comp = @cad.Component::new(name, description="Flange plate")
    .with_param("outer_diam_mm", outer_diam_mm.to_string())
    .with_param("center_bore_mm", center_bore_mm.to_string())
    .with_param("thickness_mm", thickness_mm.to_string())
    .with_param("bolt_count", bolt_count.to_string())
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_body",
        profile.outer,
        thickness_mm,
        holes=profile.holes,
        density~,
        color~,
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
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let segments = @step_common.DetailPolicy::for_level(detail).circle_segments
  let base_outer = @step_cad.Profile2D::centered_rect(width_mm, leg_a_mm)
  let hole = @step_cad.Profile2D::centered_circle(hole_diam_mm, segments~)
  let hole_at = @step_cad.translate_pts(hole, 0.0, leg_a_mm * 0.3)
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
  let wall_holes : Array[Array[(Double, Double)]] = if wall_hole_diam_mm > 0.0 {
    [
      @step_cad.translate_pts(
        @step_cad.Profile2D::circle(wall_hole_diam_mm, segments~),
        0.0,
        wall_hole_y,
      ).rev(),
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
    @cad.BodyPart::extruded_profile_mm(
      name + "_base",
      base_outer,
      thickness_mm,
      holes=[hole_at],
      y_mm=leg_a_mm / 2.0,
      z_mm=thickness_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_body(
    @cad.BodyPart::extruded_profile_mm(
      name + "_upright",
      @step_cad.Profile2D::centered_rect(width_mm, leg_b_mm - thickness_mm),
      thickness_mm,
      holes=wall_holes,
      y_mm=thickness_mm / 2.0,
      z_mm=upright_center_z,
      rx_deg=-90.0,
      density~,
      color~,
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
  bore_mm~ : Double = 8.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let _ = detail
  let _ = bore_mm
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
  .with_param("bore_mm", bore_mm.to_string())
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
