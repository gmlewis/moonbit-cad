///|
/// Parametric fasteners, bearings, couplers, and brackets.
///
/// Every builder returns a `@cad.Component` with centered bodies and named mates so
/// assemblies can be snapped together without hand-computed coordinates.

///|
/// Builds a hexagonal threaded-standoff substitute with a central bore.
pub fn hex_standoff(
  name~ : String = "standoff",
  outer_flat_mm~ : Double = 6.0,
  bore_mm~ : Double = 3.0,
  length_mm~ : Double = 20.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
) -> @cad.Component {
  let circumradius = outer_flat_mm / @math.cos(@math.PI / 6.0) / 2.0
  let circumdiameter = 2.0 * circumradius
  let outer = @step_cad.Profile2D::polygon(6, circumdiameter)
  let holes = [@step_cad.Profile2D::centered_circle(bore_mm)]
  @cad.Component::new(name, description="Hex standoff")
  .with_param("outer_flat_mm", outer_flat_mm.to_string())
  .with_param("bore_mm", bore_mm.to_string())
  .with_param("length_mm", length_mm.to_string())
  .add_body(
    @cad.BodyPart::extruded_profile_mm(
      name + "_body",
      outer,
      length_mm,
      holes~,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("bottom", z=-length_mm / 2.0)
  .add_mate_mm_deg("top", z=length_mm / 2.0)
}

///|
/// Builds a plain cylindrical spacer tube.
pub fn cylindrical_spacer(
  name~ : String = "spacer",
  outer_diam_mm~ : Double = 8.0,
  inner_diam_mm~ : Double = 4.2,
  length_mm~ : Double = 10.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  @cad.Component::new(name, description="Cylindrical spacer")
  .with_param("outer_diam_mm", outer_diam_mm.to_string())
  .with_param("inner_diam_mm", inner_diam_mm.to_string())
  .with_param("length_mm", length_mm.to_string())
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_body",
      outer_diam_mm,
      inner_diam_mm,
      length_mm,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("bottom", z=-length_mm / 2.0)
  .add_mate_mm_deg("top", z=length_mm / 2.0)
}

///|
/// Builds a simplified three-band ball bearing: inner race, cage/seal, and
/// outer race.
pub fn ball_bearing(
  name~ : String = "bearing_608",
  inner_diam_mm~ : Double = 8.0,
  outer_diam_mm~ : Double = 22.0,
  width_mm~ : Double = 7.0,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
) -> @cad.Component {
  let wall = (outer_diam_mm - inner_diam_mm) / 4.0
  let inner_race_od = inner_diam_mm + wall
  let outer_race_id = outer_diam_mm - wall
  let seal_width = width_mm * 0.85
  let unit_cost_usd = 3.0
  let part = purchased_part(
    "BEARING-" +
    inner_diam_mm.to_string() +
    "-" +
    outer_diam_mm.to_string() +
    "-" +
    width_mm.to_string(),
    "Ball bearing " +
    inner_diam_mm.to_string() +
    "x" +
    outer_diam_mm.to_string() +
    "x" +
    width_mm.to_string(),
    "steel",
    unit_cost_usd,
    supplier_url="https://www.mcmaster.com/bearings/",
  )
  @cad.Component::new(name, description="Ball bearing")
  .with_param("inner_diam_mm", inner_diam_mm.to_string())
  .with_param("outer_diam_mm", outer_diam_mm.to_string())
  .with_param("width_mm", width_mm.to_string())
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_inner_race",
      inner_race_od,
      inner_diam_mm,
      width_mm,
      density~,
      color=@step_cad.Rgb::grey(),
    ),
  )
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_seal",
      outer_race_id,
      inner_race_od,
      seal_width,
      density~,
      color=@step_cad.Rgb::blue(),
    ),
  )
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_outer_race",
      outer_diam_mm,
      outer_race_id,
      width_mm,
      density~,
      color=@step_cad.Rgb::grey(),
    ),
  )
  .add_mate_mm_deg("center")
  .add_mate_mm_deg("bottom", z=-width_mm / 2.0)
  .add_mate_mm_deg("top", z=width_mm / 2.0)
  .with_part(part)
}

///|
/// Builds a rigid shaft coupler with two different bores.
pub fn shaft_coupler(
  name~ : String = "coupler",
  outer_diam_mm~ : Double = 19.0,
  bore_in_mm~ : Double = 5.0,
  bore_out_mm~ : Double = 8.0,
  length_mm~ : Double = 25.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::cyan(),
) -> @cad.Component {
  let half = length_mm / 2.0
  let unit_cost_usd = 6.0
  let part = purchased_part(
    "COUPLER-" + outer_diam_mm.to_string() + "-" + length_mm.to_string(),
    "Shaft coupler " + outer_diam_mm.to_string() + " mm",
    "aluminum",
    unit_cost_usd,
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
/// Builds a circular flange plate with a center bore and a bolt circle.
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
  let profile = @step_cad.Profile2D::new(
      @step_cad.Profile2D::centered_circle(outer_diam_mm),
    )
    .with_hole_at(0.0, 0.0, center_bore_mm)
    .with_bolt_circle(bolt_count, bolt_circle_mm / 2.0, bolt_diam_mm)
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
  let unit_cost_usd = 15.0
  let part = fabricated_part(
    "FLANGE-" + outer_diam_mm.to_string() + "-" + thickness_mm.to_string(),
    "Flange plate " +
    outer_diam_mm.to_string() +
    " x " +
    thickness_mm.to_string(),
    "6061-T6",
    "CNC",
    unit_cost_usd,
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
/// Builds a simple L-shaped mounting bracket: a base plate, an upright wall,
/// and a clearance hole through the upright for a motor boss/shaft.
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
  let base_outer = @step_cad.Profile2D::centered_rect(width_mm, leg_a_mm)
  let hole = @step_cad.Profile2D::centered_circle(hole_diam_mm)
  // Shift the single mounting hole toward the far end of the base leg.
  let hole_at = @step_cad.translate_pts(hole, 0.0, leg_a_mm * 0.3)
  // The upright is an XZ profile extruded along Y.  `wall_mount` sits on its
  // back face (Y = 0) at Z = leg_b_mm * 0.6, so put the clearance hole there.
  let wall_z = leg_b_mm * 0.6
  let upright_center_z = (thickness_mm + leg_b_mm) / 2.0
  let wall_hole_y = upright_center_z - wall_z
  let unit_cost_usd = 18.0
  let part = fabricated_part(
    "LBRACKET-" +
    width_mm.to_string() +
    "x" +
    leg_a_mm.to_string() +
    "x" +
    leg_b_mm.to_string(),
    "L bracket " +
    width_mm.to_string() +
    " x " +
    leg_a_mm.to_string() +
    " x " +
    leg_b_mm.to_string(),
    "6061-T6",
    "CNC",
    unit_cost_usd,
  )
  let wall_holes : Array[Array[(Double, Double)]] = if wall_hole_diam_mm > 0.0 {
    [
      @step_cad.translate_pts(
        @step_cad.Profile2D::circle(wall_hole_diam_mm),
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
  // +Z points out of the upright's back face (Y = 0), so a motor mounted here
  // sits behind the wall with its shaft passing through it.
  .add_mate_mm_deg("wall_mount", z=leg_b_mm * 0.6, rx_deg=-90.0)
  .with_part(part)
}

///|
/// Builds a clevis / servo U-bracket with two parallel arms and a pivot bore.
pub fn u_bracket(
  name~ : String = "u_bracket",
  inner_span_mm~ : Double = 50.0,
  arm_length_mm~ : Double = 45.0,
  width_mm~ : Double = 36.0,
  thickness_mm~ : Double = 5.0,
  bore_mm~ : Double = 8.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let half_span = (inner_span_mm + thickness_mm) / 2.0
  let unit_cost_usd = 16.0
  let part = fabricated_part(
    "UBRACKET-" + inner_span_mm.to_string() + "x" + arm_length_mm.to_string(),
    "U bracket " + inner_span_mm.to_string() + " x " + arm_length_mm.to_string(),
    "6061-T6",
    "CNC",
    unit_cost_usd,
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
    z=thickness_mm / 2.0 + arm_length_mm * 0.7,
    axis=(1.0, 0.0, 0.0),
  )
  .with_part(part)
}

///|
/// Builds a socket-head cap screw: a cylindrical head and a shank.
///
/// Local frame: the head occupies `Z = 0..head_height_mm`; the shank occupies
/// `Z = -length_mm..0`.  `seat` is at the head underside with axis `-Z` (the
/// insertion direction); `head` is at the top of the head.
pub fn socket_head_screw(
  name~ : String = "socket_head_screw",
  thread~ : String = "M3",
  length_mm~ : Double = 12.0,
  head_diam_mm~ : Double = 5.5,
  head_height_mm~ : Double = 3.0,
  shank_diam_mm~ : Double = 3.0,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let unit_cost_usd = 0.35
  let part = purchased_part(
    "SHCS-" + thread + "x" + length_mm.to_string(),
    "Socket head cap screw " + thread + " x " + length_mm.to_string() + " mm",
    "steel",
    unit_cost_usd,
    supplier_url="https://www.mcmaster.com/screws/socket-head-cap-screws/",
  )
  @cad.Component::new(name, description="Socket head cap screw")
  .with_param("thread", thread)
  .with_param("length_mm", length_mm.to_string())
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_head",
      head_diam_mm,
      head_height_mm,
      z_mm=head_height_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_shank",
      shank_diam_mm,
      length_mm,
      z_mm=-length_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("seat", axis=(0.0, 0.0, -1.0))
  .add_mate_mm_deg("head", z=head_height_mm)
  .with_part(part)
}

///|
/// Builds a hex nut with a central clearance bore.
pub fn hex_nut(
  name~ : String = "hex_nut",
  thread~ : String = "M3",
  across_flats_mm~ : Double = 5.5,
  height_mm~ : Double = 2.4,
  bore_diam_mm~ : Double = 3.2,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let unit_cost_usd = 0.10
  let part = purchased_part(
    "HEX-NUT-" + thread,
    "Hex nut " + thread,
    "steel",
    unit_cost_usd,
  )
  let half_angle = @math.PI / 6.0
  let circumradius = across_flats_mm / 2.0 / @math.cos(half_angle)
  let circumdiameter = 2.0 * circumradius
  let outer = @step_cad.Profile2D::polygon(6, circumdiameter)
  let bore = @step_cad.Profile2D::circle(bore_diam_mm).rev()
  @cad.Component::new(name, description="Hex nut")
  .with_param("thread", thread)
  .add_body(
    @cad.BodyPart::extruded_profile_mm(
      name + "_body",
      outer,
      height_mm,
      holes=[bore],
      z_mm=height_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("seat")
  .add_mate_mm_deg("top", z=height_mm)
  .with_part(part)
}

///|
/// Builds a flat washer.
pub fn washer(
  name~ : String = "washer",
  inner_diam_mm~ : Double = 3.2,
  outer_diam_mm~ : Double = 7.0,
  thickness_mm~ : Double = 0.5,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let unit_cost_usd = 0.03
  let part = purchased_part(
    "WASHER-" + inner_diam_mm.to_string(),
    "Flat washer " + inner_diam_mm.to_string() + " mm",
    "steel",
    unit_cost_usd,
  )
  @cad.Component::new(name, description="Flat washer")
  .with_param("inner_diam_mm", inner_diam_mm.to_string())
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_body",
      outer_diam_mm,
      inner_diam_mm,
      thickness_mm,
      z_mm=thickness_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("seat")
  .add_mate_mm_deg("top", z=thickness_mm)
  .with_part(part)
}

///|
/// Builds a heat-set threaded insert.
pub fn heat_set_insert(
  name~ : String = "heat_set_insert",
  outer_diam_mm~ : Double = 4.0,
  inner_diam_mm~ : Double = 3.0,
  length_mm~ : Double = 5.0,
  density~ : @urdf.Density = @urdf.Density::kg_per_m3(8500.0),
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
) -> @cad.Component {
  let unit_cost_usd = 0.08
  let part = purchased_part(
    "INSERT-" + inner_diam_mm.to_string(),
    "Heat-set insert " + inner_diam_mm.to_string() + " mm",
    "brass",
    unit_cost_usd,
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
