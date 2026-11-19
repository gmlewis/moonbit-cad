///|
/// A compact, multi-stage, motorized planetary gearbox.
///
/// The gearbox is built around a **casing-integrated planetary ring**: each
/// stage's internal ring gear is part of that stage's printed casing module,
/// not a separate ring pressed into an outer housing. Stage modules stack
/// axially and bolt flange-to-flange, so the outer casing of the whole
/// gearbox is the sum of those modules plus the motor and output end caps.
///
/// Layout along `+Z`:
///
/// - the motor mounts on the outboard face of the bottom cap and its shaft
///   enters the stage-1 sun directly (no coupling hub);
/// - each later stage's sun sits on the previous stage's carrier output shaft
///   and is locked by a radial set screw;
/// - each planet gear is cut with a counterbore on its lower face sized to the
///   planet bearing's flange, so the flange seats flush with the gear face and
///   the bearing cannot slide through the gear;
/// - the final carrier carries the output shaft and an output flange hub with
///   a standard 40 mm bolt circle for wheels, knees, hips, and other driven
///   links.
///
/// Every stage parameter is independent; the showcase CLI accepts
/// comma-separated lists and assigns the first value to stage 1, the second to
/// stage 2, and so on. A shorter list repeats its last value.
///
/// Straight (`num_elbows = 0`) planet gears are the default because the
/// casing-integrated ring must be assembled axially. A herringbone stage
/// (`num_elbows > 0`) is modeled when requested, but its ring, sun, and
/// planets must then be printed in place rather than dropped into the casing.

///|
/// Radial clearance around the flange of a flanged planet bearing inside its
/// counterbore, in millimetres. Small enough to locate the gear, large enough
/// to print.
const PLANET_POCKET_CLEARANCE_MM : Double = 0.1

///|
/// One planetary stage of a `motorized_gearbox`.
pub(all) struct MotorizedStageSpec {
  /// Gear module in millimeters.
  module_mm : Double
  /// Sun tooth count.
  sun_teeth : Int32
  /// Planet tooth count.
  planet_teeth : Int32
  /// Number of orbiting planets.
  planet_count : Int32
  /// Gear face width in millimeters.
  gear_length_mm : Double
  /// Herringbone sweep elbows. `0` uses straight, axially assembleable gears.
  num_elbows : Int32
  /// Planet bearing: `"FR8-2RS"` or an ISO bearing designation.
  planet_bearing : String
}

///|
/// Builds a stage specification.
pub fn MotorizedStageSpec::new(
  module_mm~ : Double,
  sun_teeth~ : Int32,
  planet_teeth~ : Int32,
  planet_count~ : Int32,
  gear_length_mm~ : Double,
  num_elbows~ : Int32 = 0,
  planet_bearing~ : String = "FR8-2RS",
) -> MotorizedStageSpec {
  {
    module_mm,
    sun_teeth,
    planet_teeth,
    planet_count,
    gear_length_mm,
    num_elbows,
    planet_bearing,
  }
}

///|
/// The default stage: module 2.0, 12/20 teeth, four planets, and straight
/// teeth. Its 52-tooth ring gives a 5.33:1 reduction, and the 127 mm casing
/// barrel fits inside a 7-inch wheel envelope.
pub fn MotorizedStageSpec::default() -> MotorizedStageSpec {
  {
    module_mm: 2.0,
    sun_teeth: 12,
    planet_teeth: 20,
    planet_count: 4,
    gear_length_mm: 10.0,
    num_elbows: 0,
    planet_bearing: "FR8-2RS",
  }
}

///|
/// Boundary dimensions of a flanged radial bearing.
pub(all) struct FlangedBearingSpec {
  designation : String
  bore_mm : Double
  outer_mm : Double
  width_mm : Double
  /// Flange outside diameter. Equal to `outer_mm` for a plain bearing.
  flange_outer_mm : Double
  /// Flange thickness. Zero for a plain bearing.
  flange_thickness_mm : Double
}

///|
/// The default planet and output bearing: a 1/2" x 1 1/8" x 5/16" flanged,
/// sealed ball bearing.
pub fn flanged_bearing_fr8_2rs() -> FlangedBearingSpec {
  {
    designation: "FR8-2RS",
    bore_mm: 12.7,
    outer_mm: 28.575,
    width_mm: 7.9375,
    flange_outer_mm: 31.75,
    flange_thickness_mm: 1.5,
  }
}

///|
/// Resolves a bearing designation to boundary dimensions.
///
/// `FR8-2RS` is the flanged imperial default. An ISO designation resolves
/// through the Tier-1 catalogue and is modeled as a plain (non-flanged)
/// bearing, so it does not have the flange that stops it sliding through a
/// planet.
pub fn resolve_flanged_bearing(designation : String) -> FlangedBearingSpec {
  let key = designation.trim().to_owned()
  if key == "FR8-2RS" || key == "fr8-2rs" || key == "FR8" || key == "fr8" {
    return flanged_bearing_fr8_2rs()
  }
  match @step_motion.bearing_size(key) {
    Ok(size) =>
      {
        designation: size.designation,
        bore_mm: size.bore_mm,
        outer_mm: size.outer_mm,
        width_mm: size.width_mm,
        flange_outer_mm: size.outer_mm,
        flange_thickness_mm: 0.0,
      }
    Err(_) =>
      abort(
        "unknown planet bearing '\{designation}'; use FR8-2RS or an ISO bearing designation",
      )
  }
}

///|
/// Formats a millimeter dimension with one decimal place for part numbers.
fn fmt_mm(value : Double) -> String {
  @step_cad.fmt_double(value, Some(0.1))
}

///|
/// Rounds a millimeter dimension to the nearest stocked length in `options`.
fn nearest_standard(value : Double, options : Array[Double]) -> Double {
  let mut best = options[0]
  let mut best_distance = (value - best).abs()
  for option in options {
    let distance = (value - option).abs()
    if distance < best_distance {
      best = option
      best_distance = distance
    }
  }
  best
}

///|
/// Rounds a set-screw length to a standard stocked length.
fn standard_set_screw_len(value : Double) -> Double {
  nearest_standard(value, [6.0, 8.0, 10.0, 12.0, 16.0, 20.0])
}

///|
/// Rounds a socket-head cap-screw length to a standard stocked length.
fn standard_shcs_len(value : Double) -> Double {
  nearest_standard(value, [6.0, 8.0, 10.0, 12.0, 16.0, 20.0, 25.0, 30.0])
}

///|
/// Prefixes all body and node names in `comp` so every fastener, insert, and
/// bearing retains its owning role name in flattened designs and exploded views.
fn mg_tag_bodies(prefix : String, comp : @cad.Component) -> @cad.Component {
  let bodies = comp.bodies.map(fn(body) {
    let tagged = "\{prefix}_\{body.name}"
    { ..body, name: tagged, node: body.node.with_name(tagged), }
  })
  { ..comp, bodies, }
}

///|
/// A flanged ball bearing component.
///
/// Local frame: the flange shoulder (`flange_top`) is `z = 0`; the outer-race
/// flange rim occupies `-flange_thickness_mm .. 0` and the bearing body occupies
/// `0 .. width_mm`. Attach `flange_top_reversed` at the planet counterbore
/// floor (inserted from above) or at the output cap top face.
fn flanged_bearing_component(
  name : String,
  spec : FlangedBearingSpec,
  detail : @step_common.DetailLevel,
) -> @cad.Component {
  let part = purchased_part(
    "BEARING-\{spec.designation}",
    "Flanged sealed ball bearing \{spec.designation} (\{spec.bore_mm} x \{spec.outer_mm} x \{spec.width_mm} mm, flange \{spec.flange_outer_mm} mm); friction-press into the gear from above, flange flush with the top face",
    "steel",
    3.50,
    supplier_url="https://www.mcmaster.com/ball-bearings/",
  )
  let size : @step_motion.BearingSize = {
    designation: spec.designation,
    bore_mm: spec.bore_mm,
    outer_mm: spec.outer_mm,
    width_mm: spec.width_mm,
  }
  let step_comp = if detail_is_rich(detail) {
    expect_step(
      "flanged bearing",
      @step_motion.deep_groove_bearing(size, detail~),
    )
  } else {
    expect_step("flanged bearing", @step_motion.bearing(size, detail~))
  }
  let mut comp = @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::steel_mild(),
    part=Some(part),
  )
  comp = mg_tag_bodies(name, comp)
  if spec.flange_thickness_mm > 0.0 {
    // Rim the outer race only so the flange does not render as a full-face washer.
    let flange_inner = spec.outer_mm - 0.8
    comp = comp.add_body(
      @cad.BodyPart::tube_mm(
        name + "_flange",
        spec.flange_outer_mm,
        flange_inner,
        spec.flange_thickness_mm,
        z_mm=-spec.flange_thickness_mm / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(part),
    )
  }
  comp
  .add_mate_mm_deg("flange_top")
  .add_mate_mm_deg("flange_top_reversed", rx_deg=180.0)
  .add_mate_mm_deg("flange_bottom", z=-spec.flange_thickness_mm)
  .add_mate_mm_deg(
    "flange_bottom_reversed",
    z=-spec.flange_thickness_mm,
    rx_deg=180.0,
  )
  .add_mate_mm_deg("bottom", z=-spec.flange_thickness_mm)
  .with_param("bore_mm", spec.bore_mm.to_string())
  .with_param("outer_mm", spec.outer_mm.to_string())
  .with_param("width_mm", spec.width_mm.to_string())
  .with_param("flange_outer_mm", spec.flange_outer_mm.to_string())
}

///|
/// Computed geometry and kinematics for one stage.
priv struct MotorizedStage {
  spec : MotorizedStageSpec
  bearing : FlangedBearingSpec
  params : PlanetaryGearboxParams
  layout : @step_planetary.HerringbonePlanetaryLayout
  smooth : Bool
  z0 : Double
  gear_length : Double
  height : Double
  base_outer : Double
  ring_free_bore : Double
  carrier_plate_radius : Double
  smooth_inner : Double
  carrier_shaft_diam : Double
  carrier_shaft_length : Double
  input_shaft_diam : Double
  sun_joint : String
  carrier_joint : String
  sun_mount : String
  carrier_mount : String
  casing_part : @cad.PartMeta
}

///|
/// Builds a printed planetary carrier with steel pins, a steel output shaft,
/// and an optional output-hub seat.
///
/// Local frame: the carrier plate bottom is `z = 0`; the plate spans
/// `0 .. thickness`; the pins extend down to `-(gear_length + clearance)`.
fn motorized_carrier(
  name : String,
  part_number : String,
  layout : @step_planetary.HerringbonePlanetaryLayout,
  params : PlanetaryGearboxParams,
  plate_radius : Double,
  clearance : Double,
  thickness : Double,
  shaft_diam : Double,
  shaft_length : Double,
  output_hub_seat : Double?,
  detail : @step_common.DetailLevel,
) -> @cad.Component {
  let plate_part = fabricated_part(
    part_number, "Printed planetary carrier plate with full-thickness shaft bore; press the steel dowel pins and bond/press-fit the steel output shaft",
    "carbon fiber nylon", "3D print", 8.0,
  )
  let pin_diam = if params.carrier_pin_diam_mm > 0.0 {
    params.carrier_pin_diam_mm
  } else if params.planet_bore_radius_mm > 0.2 {
    params.planet_bore_radius_mm * 2.0 - 0.2
  } else {
    3.0
  }
  let pin_length = layout.gear_length_mm + clearance + thickness
  let pin_part = purchased_part(
    "DOWEL-\{fmt_mm(pin_diam)}x\{fmt_mm(pin_length)}",
    "Hardened dowel pin \{fmt_mm(pin_diam)} x \{fmt_mm(pin_length)} mm",
    "steel",
    0.80,
  )
  let shaft_total = thickness + shaft_length
  let shaft_part = purchased_part(
    "SHAFT-\{fmt_mm(shaft_diam)}x\{fmt_mm(shaft_total)}",
    "Steel carrier output shaft \{fmt_mm(shaft_diam)} x \{fmt_mm(shaft_total)} mm",
    "steel",
    2.50,
  )
  let bore_diam = shaft_diam + 0.05
  let plate_holes : Array[(Double, Double, Double)] = []
  plate_holes.push((0.0, 0.0, bore_diam))
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    plate_holes.push((planet.x, -planet.z, pin_diam - 0.1))
  }
  let mut comp = @cad.Component::new(
      name,
      description="Printed planetary carrier with steel pins and output shaft",
    )
    .with_param("plate_diameter_mm", (plate_radius * 2.0).to_string())
    .with_param("shaft_bore_mm", bore_diam.to_string())
    .with_param("carrier_pin_diam_mm", pin_diam.to_string())
    .add_body(
      actuator_plate_body(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        0.0,
        plate_holes,
        @urdf.Density::carbon_fiber(),
        @step_cad.Rgb::green(),
        detail,
      ).with_part(plate_part),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("output_flange", z=thickness)
    .add_mate_mm_deg("output_shaft", z=shaft_total)
    .with_part(plate_part)
  match output_hub_seat {
    Some(z) => comp = comp.add_mate_mm_deg("output_hub_seat", z~)
    None => ()
  }
  // The purchased output shaft is a child so the BOM counts it once even
  // though the printed carrier owns the component's part metadata.
  let shaft_comp = @cad.Component::new(
      name + "_shaft_component",
      description="Purchased carrier output shaft",
    )
    .with_part(shaft_part)
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        shaft_diam,
        shaft_total,
        z_mm=shaft_total / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(shaft_part),
    )
  comp = comp.attach(
    name + "_shaft_merge",
    parent_mate="origin",
    shaft_comp,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(),
  )
  // The four purchased pins are bodies of one child component so the BOM
  // counts four pins, not one.
  let mut pins_comp = @cad.Component::new(
    name + "_pins_component",
    description="Purchased carrier dowel pins",
  )
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    pins_comp = pins_comp.add_body(
      @cad.BodyPart::cylinder_mm(
        "\{name}_pin_\{i}",
        pin_diam,
        pin_length,
        x_mm=planet.x,
        y_mm=-planet.z,
        z_mm=(thickness - layout.gear_length_mm - clearance) / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(pin_part),
    )
    comp = comp.add_mate_mm_deg(
      "pin_\{i}",
      x=planet.x,
      y=-planet.z,
      z=-layout.gear_length_mm - clearance,
      rz_deg=-planet.phi_deg,
    )
  }
  comp = comp.attach(
    name + "_pins_merge",
    parent_mate="origin",
    pins_comp,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(),
  )
  comp
}

///|
/// Builds a printed sun gear with an integral input hub and set screw.
fn motorized_sun(
  name : String,
  part_number : String,
  sun_body : @cad.BodyPart,
  bore_diam : Double,
  hub_diam : Double,
  hub_length : Double,
  gear_length : Double,
  set_screw_size : String,
) -> @cad.Component {
  let part = fabricated_part(
    part_number, "Printed planetary sun gear with integral input hub; drill/tap the radial set-screw hole",
    "carbon fiber nylon", "3D print", 4.0,
  )
  let set_screw_len = standard_set_screw_len(
    hub_diam / 2.0 - bore_diam / 2.0 + 0.5,
  )
  let set_screw_center = bore_diam / 2.0 + set_screw_len / 2.0
  let set_screw_part = purchased_part(
    "SET-\{set_screw_size}x\{fmt_mm(set_screw_len)}",
    "\{set_screw_size} x \{fmt_mm(set_screw_len)} socket set screw",
    "steel",
    0.15,
  )
  let sun_body = {
    ..sun_body,
    name: name + "_gear",
    node: sun_body.node
    .with_name(name + "_gear")
    .with_color(@step_cad.Rgb::orange()),
    part: Some(part),
  }
  let mut comp = @cad.Component::new(
      name,
      description="Printed sun gear and input hub",
    )
    .with_param("bore_diam_mm", bore_diam.to_string())
    .with_param("hub_diam_mm", hub_diam.to_string())
    .with_param("hub_length_mm", hub_length.to_string())
    .add_body(sun_body)
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("top", z=gear_length)
    .with_part(part)
  if hub_length > 0.0 {
    comp = comp
      .add_body(
        @cad.BodyPart::tube_mm(
          name + "_hub",
          hub_diam,
          bore_diam,
          hub_length,
          z_mm=-hub_length / 2.0,
          density=@urdf.Density::carbon_fiber(),
          color=@step_cad.Rgb::orange(),
        ).with_part(part),
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          name + "_set_screw",
          3.0,
          set_screw_len,
          x_mm=set_screw_center,
          z_mm=-hub_length / 2.0,
          ry_deg=90.0,
          density=@urdf.Density::steel_mild(),
          color=@step_cad.Rgb::grey(),
        ).with_part(set_screw_part),
      )
      .add_fastener(
        @cad.Fastener::new(
          "sun_set_screw",
          @cad.FastenerKind::Screw,
          thread=set_screw_size,
          length_mm=set_screw_len,
          engagement_mm=3.0,
          quantity=1,
          torque_nm=0.6,
          references=[name + "_hub"],
          part=Some(set_screw_part),
        ),
      )
  }
  comp
}

///|
/// The component name of the last stage's carrier.
fn motorized_last_carrier_name(name : String, stage_count : Int32) -> String {
  "\{name}_stage\{stage_count}_carrier"
}

///|
/// Subtracts axial pin drive pockets (and optional SHCS head counterbore) from
/// a flush gear body without touching its swept gear teeth.
fn cut_sun_drive_features(
  body : @cad.BodyPart,
  name : String,
  pin_radius_mm : Double,
  pin_diam_mm : Double,
  pin_depth_mm : Double,
  counterbore_diam_mm : Double,
  counterbore_z0_mm : Double,
  gear_length_mm : Double,
  color : @step_cad.Rgb,
) -> @cad.BodyPart {
  let cutters : Array[@step_cad.SceneNode] = [
    @step_cad.Cylinder::new(pin_diam_mm, pin_depth_mm + 0.5)
    .with_name(name + "_pin_cut_pos")
    .translate(x=pin_radius_mm, z=-0.5),
    @step_cad.Cylinder::new(pin_diam_mm, pin_depth_mm + 0.5)
    .with_name(name + "_pin_cut_neg")
    .translate(x=-pin_radius_mm, z=-0.5),
  ]
  if counterbore_diam_mm > 0.0 && counterbore_z0_mm < gear_length_mm {
    let cb_h = gear_length_mm - counterbore_z0_mm + 0.5
    cutters.push(
      @step_cad.Cylinder::new(counterbore_diam_mm, cb_h)
      .with_name(name + "_cbore_cut")
      .translate(z=counterbore_z0_mm),
    )
  }
  {
    ..body,
    node: @step_cad.difference(body.node, cutters, name=body.name).with_color(
      color,
    ),
  }
}

///|
/// Builds one printed stage casing module (`MG-CASING-{idx}`).
///
/// When `stage_flush` is true, the bottom mounting flange sits flush on `z = 0`
/// (with top-down screw access at `bottom_phase_deg`) and the top flange carries
/// 6 bolt lugs with 45-deg support slopes staggered at `top_phase_deg`, so a
/// 4-elbow print-in-place cartridge rests dead flat on the print bed with zero
/// overhangs and unobstructed top-down hex-key access to every screw.
fn build_stage_casing_comp(
  name : String,
  idx : Int32,
  part : @cad.PartMeta,
  ring_body : @cad.BodyPart,
  gear_length : Double,
  stage_height : Double,
  ring_free_bore : Double,
  smooth_inner : Double,
  casing_outer : Double,
  flange_outer_radius : Double,
  flange_thickness_mm : Double,
  casing_bolt_radius : Double,
  stage_flush : Bool,
  bottom_phase_deg : Double,
  top_phase_deg : Double,
  detail : @step_common.DetailLevel,
  color : @step_cad.Rgb,
) -> @cad.Component {
  let mut module_comp = @cad.Component::new(
      "\{name}_stage\{idx}_casing_module",
      description="Printed stage casing module with integrated ring gear, carrier bore, and joint flanges",
    )
    .with_part(part)
    .add_body(ring_body)
  let smooth_height = stage_height - gear_length
  if !stage_flush {
    module_comp = module_comp.add_body(
      @cad.BodyPart::tube_mm(
        "\{name}_stage\{idx}_casing_sleeve",
        casing_outer * 2.0,
        smooth_inner * 2.0,
        smooth_height,
        z_mm=gear_length + smooth_height / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color~,
      ).with_part(part),
    )
    let bottom_holes : Array[(Double, Double, Double)] = [
      (0.0, 0.0, ring_free_bore * 2.0 + 0.4),
    ]
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      bottom_holes.push(
        (
          casing_bolt_radius * @math.cos(theta),
          casing_bolt_radius * @math.sin(theta),
          3.4,
        ),
      )
    }
    module_comp = module_comp.add_body(
      actuator_plate_body(
        "\{name}_stage\{idx}_bottom_flange",
        flange_outer_radius * 2.0,
        flange_thickness_mm,
        -flange_thickness_mm,
        bottom_holes,
        @urdf.Density::carbon_fiber(),
        color,
        detail,
      ).with_part(part),
    )
    let top_holes : Array[(Double, Double, Double)] = [
      (0.0, 0.0, smooth_inner * 2.0),
    ]
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      top_holes.push(
        (
          casing_bolt_radius * @math.cos(theta),
          casing_bolt_radius * @math.sin(theta),
          3.4,
        ),
      )
    }
    module_comp = module_comp.add_body(
      actuator_plate_body(
        "\{name}_stage\{idx}_top_flange",
        flange_outer_radius * 2.0,
        flange_thickness_mm,
        stage_height,
        top_holes,
        @urdf.Density::carbon_fiber(),
        color,
        detail,
      ).with_part(part),
    )
    return module_comp
  }
  // Flush print-in-place housing shell: bottom flange ring sits on z = [0, ft],
  // carrier sleeve covers z = [gear_length, stage_height + ft], and 6 top bolt
  // lugs at `top_phase_deg` flare at 45 deg for support-free printing.
  let top_z = stage_height + flange_thickness_mm
  let profile = @step_cad.RevolvedProfile::polyline(
      [
        (casing_outer - 0.1, 0.0),
        (flange_outer_radius, 0.0),
        (flange_outer_radius, flange_thickness_mm),
        (casing_outer, flange_thickness_mm),
        (casing_outer, top_z),
        (smooth_inner, top_z),
        (smooth_inner, gear_length),
        (casing_outer - 0.1, gear_length),
      ],
      closed=true,
    )
    .as_shape()
    .with_name("\{name}_stage\{idx}_casing_shell_base")
  let parts : Array[@step_cad.SceneNode] = [profile]
  let overhang = flange_outer_radius - casing_outer
  let z_slope = if stage_height - overhang > gear_length {
    stage_height - overhang
  } else {
    gear_length
  }
  let r_in = casing_outer - 2.0
  let lug_width = 16.0
  for i in 0..<6 {
    let angle_deg = top_phase_deg + 60.0 * i.to_double()
    let angle_rad = angle_deg * @math.PI / 180.0
    // Rx(90) Rz(a) maps extruded d in [0, lug_width] centered at u=w/2 along
    // (+w/2*sin(a), -w/2*cos(a)); negate to center each lug radially on a.
    let lug_prism = @step_cad.ExtrudedProfile::new(
        [
          (r_in, z_slope),
          (flange_outer_radius, stage_height),
          (flange_outer_radius, top_z),
          (r_in, top_z),
        ],
        lug_width,
      )
      .with_name("\{name}_stage\{idx}_top_lug_\{i}")
      .rotate_x(90.0)
      .rotate_z(angle_deg)
      .translate(
        x=-lug_width / 2.0 * @math.sin(angle_rad),
        y=lug_width / 2.0 * @math.cos(angle_rad),
      )
    parts.push(lug_prism)
  }
  let raw_shell = @step_cad.union_all(
    parts,
    name="\{name}_stage\{idx}_casing_shell_raw",
  )
  let cutters : Array[@step_cad.SceneNode] = []
  for i in 0..<6 {
    let b_rad = (bottom_phase_deg + 60.0 * i.to_double()) * @math.PI / 180.0
    cutters.push(
      @step_cad.Cylinder::new(3.4, flange_thickness_mm + 2.0)
      .with_name("bottom_hole_\{i}")
      .translate(
        x=casing_bolt_radius * @math.cos(b_rad),
        y=casing_bolt_radius * @math.sin(b_rad),
        z=-1.0,
      ),
    )
    let t_rad = (top_phase_deg + 60.0 * i.to_double()) * @math.PI / 180.0
    cutters.push(
      @step_cad.Cylinder::new(4.5, flange_thickness_mm + 2.0)
      .with_name("top_insert_hole_\{i}")
      .translate(
        x=casing_bolt_radius * @math.cos(t_rad),
        y=casing_bolt_radius * @math.sin(t_rad),
        z=stage_height - 1.0,
      ),
    )
  }
  let shell_name = "\{name}_stage\{idx}_casing_shell"
  let shell_node = @step_cad.difference(raw_shell, cutters, name=shell_name).with_color(
    color,
  )
  module_comp.add_body(
    @cad.BodyPart::from_scene_node(
      shell_node,
      density=@urdf.Density::carbon_fiber(),
      part=Some(part),
    ),
  )
}

///|
/// Builds the fixed, ventilated stator housing (`MG-MOTOR-HOUSING`) for the
/// A12 8318 100KV motor.
///
/// Local frame matches world frame relative to Stage 1 bottom (`z = 0.0`):
/// - `z = 0.0`: top flange face meeting Stage 1 with 6x M3 heat-set inserts.
/// - `z = -14.0 .. -6.0`: 45-deg support-free flange flare (`126.8 -> 142.8 mm`).
/// - `z = -42.0 .. -14.0`: `98.0 mm` ID barrel with 6 arched cooling windows.
/// - `z = -45.6 .. -42.0`: strong stator floor (`3.6 mm` solid around 4x M4 CSK)
///   with a `15 mm` central sensor through-bore (`R = 7.5 mm`) and localized
///   `R = 10.5 mm` underside chip pocket (`z = -44.8`) leaving `4.2 mm` inward
///   margin around every M4 stator hole.
/// - `z = -46.8 .. -42.0`: flat printer bed ring (`R = 19.2..63.4`) carrying 4x
///   M3 heat-set inserts at `(±16, ±16)` for the moteus C1 PCB and 4x M5 frame
///   holes with external wrench pockets.
fn build_a12_motor_housing(
  name : String,
  casing_outer : Double,
  flange_outer_radius : Double,
  casing_bolt_radius : Double,
  frame_bolt_circle_mm : Double,
  housing_part : @cad.PartMeta,
  heat_set_inserts : Bool,
  moteus_shroud : Bool,
  detail : @step_common.DetailLevel,
) -> (@cad.Component, Double, Double) {
  let stator_z = -42.0
  let floor_bottom_z = -45.6
  let center_pocket_z = -44.8
  let pcb_standoff_z = -46.8
  let barrel_inner_r = 49.0
  let sensor_bore_r = 7.5
  let chip_pocket_r = 10.5
  let relief_r = 19.2
  let flare_start_z = -14.0
  let top_flange_bottom_z = -6.0
  let housing_name = name + "_motor_housing"
  let shell_profile = @step_cad.RevolvedProfile::polyline(
      [
        (sensor_bore_r, center_pocket_z),
        (chip_pocket_r, center_pocket_z),
        (chip_pocket_r, floor_bottom_z),
        (relief_r, floor_bottom_z),
        (relief_r, pcb_standoff_z),
        (casing_outer, pcb_standoff_z),
        (casing_outer, flare_start_z),
        (flange_outer_radius, top_flange_bottom_z),
        (flange_outer_radius, 0.0),
        (barrel_inner_r, 0.0),
        (barrel_inner_r, stator_z),
        (sensor_bore_r, stator_z),
      ],
      closed=true,
    )
    .as_shape()
    .with_name(housing_name + "_shell")
  let cutters : Array[@step_cad.SceneNode] = []
  // 6x top-flange M3 heat-set insert pockets (depth 4.5 mm from z = 0).
  for i in 0..<6 {
    let theta = 2.0 * @math.PI * i.to_double() / 6.0
    cutters.push(
      @step_cad.Cylinder::new(4.5, 5.2)
      .with_name("top_insert_cut_\{i}")
      .translate(
        x=casing_bolt_radius * @math.cos(theta),
        y=casing_bolt_radius * @math.sin(theta),
        z=-4.5,
      ),
    )
  }
  // 6 arched support-free cooling / inspection / cable windows at 30 + k*60 deg.
  let win_half_w = 7.0
  let win_z0 = -36.5
  let win_z1 = -22.5
  let win_peak = win_z1 + win_half_w
  let win_r0 = barrel_inner_r - 4.0
  let win_radial_len = casing_outer - barrel_inner_r + 12.0
  for i in 0..<6 {
    let angle_deg = 30.0 + 60.0 * i.to_double()
    let angle_rad = angle_deg * @math.PI / 180.0
    let win = @step_cad.ExtrudedProfile::new(
        [
          (-win_half_w, win_z0),
          (win_half_w, win_z0),
          (win_half_w, win_z1),
          (0.0, win_peak),
          (-win_half_w, win_z1),
        ],
        win_radial_len,
      )
      .with_name("cooling_win_\{i}")
      .rotate_x(90.0)
      .rotate_z(90.0 + angle_deg)
      .translate(
        x=win_r0 * @math.cos(angle_rad),
        y=win_r0 * @math.sin(angle_rad),
      )
    cutters.push(win)
  }
  // 4x frame M5 mounting holes with external support-free U-wrench pockets.
  let frame_r = frame_bolt_circle_mm / 2.0
  let slot_half_w = 5.2
  let slot_z0 = -40.8
  let slot_z1 = -20.5
  let slot_peak = slot_z1 + slot_half_w
  let slot_r0 = frame_r - 5.2
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
    let fx = frame_r * @math.cos(theta)
    let fy = frame_r * @math.sin(theta)
    cutters.push(
      @step_cad.Cylinder::new(5.5, 9.0)
      .with_name("frame_hole_\{i}")
      .translate(x=fx, y=fy, z=-47.5),
    )
    let angle_deg = 45.0 + 90.0 * i.to_double()
    let pocket = @step_cad.ExtrudedProfile::new(
        [
          (-slot_half_w, slot_z0),
          (slot_half_w, slot_z0),
          (slot_half_w, slot_z1),
          (0.0, slot_peak),
          (-slot_half_w, slot_z1),
        ],
        casing_outer - frame_r + 14.0,
      )
      .with_name("frame_wrench_slot_\{i}")
      .rotate_x(90.0)
      .rotate_z(90.0 + angle_deg)
      .translate(x=slot_r0 * @math.cos(theta), y=slot_r0 * @math.sin(theta))
    cutters.push(pocket)
  }
  // 4x A12 stator M4 countersunk mounting bores at exact stator-mount-hole-m4 angles.
  let spec = @step_motors.a12_motor_100kv_spec()
  let m4_r = spec.mount_m4_circle_diameter_mm / 2.0
  for i in 0..<spec.mount_m4_count {
    let angle = (
        spec.mount_hole_phase_deg +
        45.0 +
        360.0 * i.to_double() / spec.mount_m4_count.to_double()
      ) *
      @math.PI /
      180.0
    let mx = m4_r * @math.sin(angle)
    let my = m4_r * @math.cos(angle)
    cutters.push(
      @step_cad.Cylinder::new(4.5, 5.5)
      .with_name("a12_m4_through_\{i}")
      .translate(x=mx, y=my, z=-46.5),
    )
    cutters.push(
      @step_cad.Cylinder::new(8.6, 2.0)
      .with_name("a12_m4_recess_\{i}")
      .translate(x=mx, y=my, z=-47.5),
    )
    let cone = @step_cad.RevolvedProfile::frustum(4.4, 2.25, 2.15)
      .as_shape()
      .with_name("a12_m4_csk_\{i}")
      .translate(x=mx, y=my, z=-45.7)
    cutters.push(cone)
  }
  // 4x moteus C1 M3 heat-set insert pockets at (±16, ±16).
  let moteus_xy : Array[(Double, Double)] = [
    (-16.0, -16.0),
    (16.0, -16.0),
    (16.0, 16.0),
    (-16.0, 16.0),
  ]
  for i in 0..<moteus_xy.length() {
    let (mx, my) = moteus_xy[i]
    cutters.push(
      @step_cad.Cylinder::new(4.0, 5.0)
      .with_name("moteus_insert_cut_\{i}")
      .translate(x=mx, y=my, z=-47.3),
    )
  }
  let shroud_bolt_radius = 35.0
  let shroud_xy : Array[(Double, Double)] = [
    (shroud_bolt_radius, 0.0),
    (0.0, shroud_bolt_radius),
    (-shroud_bolt_radius, 0.0),
    (0.0, -shroud_bolt_radius),
  ]
  if moteus_shroud {
    for i in 0..<shroud_xy.length() {
      let (sx, sy) = shroud_xy[i]
      cutters.push(
        @step_cad.Cylinder::new(4.0, 5.0)
        .with_name("shroud_insert_cut_\{i}")
        .translate(x=sx, y=sy, z=-47.3),
      )
    }
  }
  let housing_color = @step_cad.Rgb::new(0.20, 0.22, 0.28)
  let housing_node = @step_cad.difference(
    shell_profile,
    cutters,
    name=housing_name + "_body",
  ).with_color(housing_color)
  let mut comp = @cad.Component::new(
      housing_name,
      description="Fixed ventilated A12 stator housing with centered moteus C1 sensor mount",
    )
    .with_part(housing_part)
    .add_body(
      @cad.BodyPart::from_scene_node(
        housing_node,
        density=@urdf.Density::carbon_fiber(),
        part=Some(housing_part),
      ),
    )
    .add_mate_mm_deg("top")
    .add_mate_mm_deg("motor_mount", z=stator_z, axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("frame_mount", z=pcb_standoff_z, axis=(0.0, 0.0, -1.0))
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
    comp = comp.add_mate_mm_deg(
      "frame_mount_\{i}",
      x=frame_r * @math.cos(theta),
      y=frame_r * @math.sin(theta),
      z=pcb_standoff_z,
      axis=(0.0, 0.0, -1.0),
    )
  }
  // Attach 6x M3 inserts in top flange and 4x M3 inserts on moteus corners.
  if heat_set_inserts {
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      comp = comp
        .add_mate_mm_deg(
          "top_insert_\{i}",
          x=casing_bolt_radius * @math.cos(theta),
          y=casing_bolt_radius * @math.sin(theta),
          z=0.0,
          rx_deg=180.0,
        )
        .attach(
          "\{housing_name}_top_insert_merge_\{i}",
          parent_mate="top_insert_\{i}",
          mg_tag_bodies(
            "\{name}_motor_housing_top_insert_\{i}",
            heat_set_insert(
              name="\{housing_name}_top_insert_\{i}",
              outer_diam_mm=4.5,
              inner_diam_mm=3.0,
              length_mm=4.0,
            ),
          ),
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
    for i in 0..<moteus_xy.length() {
      let (mx, my) = moteus_xy[i]
      comp = comp
        .add_mate_mm_deg("moteus_insert_\{i}", x=mx, y=my, z=pcb_standoff_z)
        .attach(
          "\{housing_name}_moteus_insert_merge_\{i}",
          parent_mate="moteus_insert_\{i}",
          mg_tag_bodies(
            "\{name}_motor_housing_moteus_insert_\{i}",
            heat_set_insert(
              name="\{housing_name}_moteus_insert_\{i}",
              outer_diam_mm=4.0,
              inner_diam_mm=3.0,
              length_mm=4.0,
            ),
          ),
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
  }
  // 4x ISO 10642 M4x8 countersunk stator bolts flush at floor underside.
  for i in 0..<spec.mount_m4_count {
    let angle = (
        spec.mount_hole_phase_deg +
        45.0 +
        360.0 * i.to_double() / spec.mount_m4_count.to_double()
      ) *
      @math.PI /
      180.0
    let mx = m4_r * @math.sin(angle)
    let my = m4_r * @math.cos(angle)
    comp = comp
      .add_mate_mm_deg(
        "a12_stator_bolt_\{i}",
        x=mx,
        y=my,
        z=floor_bottom_z,
        rx_deg=180.0,
      )
      .attach(
        "\{housing_name}_stator_screw_merge_\{i}",
        parent_mate="a12_stator_bolt_\{i}",
        mg_tag_bodies(
          "\{name}_motor_stator_screw_\{i}",
          iso_cs_screw(
            name="\{name}_motor_stator_screw_\{i}",
            size=@step_standards.M4,
            length_mm=8.0,
            detail~,
          ),
        ),
        child_mate="head_top",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  // 4x ISO 4762 M3x6 screws securing moteus C1 at (±16, ±16) from below PCB.
  let moteus_pcb_bottom_z = pcb_standoff_z - 1.6
  for i in 0..<moteus_xy.length() {
    let (mx, my) = moteus_xy[i]
    comp = comp
      .add_mate_mm_deg(
        "moteus_bolt_\{i}",
        x=mx,
        y=my,
        z=moteus_pcb_bottom_z,
        rx_deg=180.0,
      )
      .attach(
        "\{housing_name}_moteus_screw_merge_\{i}",
        parent_mate="moteus_bolt_\{i}",
        mg_tag_bodies(
          "\{name}_moteus_screw_\{i}",
          iso_shcs_screw(
            name="\{name}_moteus_screw_\{i}",
            size=@step_standards.M3,
            length_mm=6.0,
            detail~,
          ),
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  if moteus_shroud {
    if heat_set_inserts {
      for i in 0..<shroud_xy.length() {
        let (sx, sy) = shroud_xy[i]
        comp = comp
          .add_mate_mm_deg("shroud_insert_\{i}", x=sx, y=sy, z=pcb_standoff_z)
          .attach(
            "\{housing_name}_shroud_insert_merge_\{i}",
            parent_mate="shroud_insert_\{i}",
            mg_tag_bodies(
              "\{housing_name}_shroud_insert_\{i}",
              heat_set_insert(
                name="\{housing_name}_shroud_insert_\{i}",
                outer_diam_mm=4.0,
                inner_diam_mm=3.0,
                length_mm=4.0,
              ),
            ),
            child_mate="seat",
            spec=@cad.JointSpec::merge_rigid(),
          )
      }
    }
    let shroud_part = fabricated_part(
      "MG-MOTEUS-SHROUD", "Printed protective cap shrouding the rear moteus C1 board with dual 45-deg cable-exit arches (4 x M3x8 mount)",
      "carbon fiber nylon", "3D print", 6.0,
    )
    let shroud_height = 14.5
    let shroud_flange_h = 4.0
    let shroud_blank = @step_cad.RevolvedProfile::polyline(
        [
          (0.0, -shroud_height),
          (33.0, -shroud_height),
          (33.0, -shroud_flange_h),
          (39.5, -shroud_flange_h),
          (39.5, 0.0),
          (29.0, 0.0),
          (29.0, -11.0),
          (0.0, -11.0),
        ],
        closed=false,
      )
      .as_shape()
      .with_name(name + "_moteus_shroud_blank")
    let shroud_cutters : Array[@step_cad.SceneNode] = []
    for i in 0..<shroud_xy.length() {
      let (sx, sy) = shroud_xy[i]
      shroud_cutters.push(
        @step_cad.Cylinder::new(3.4, shroud_flange_h + 2.0)
        .with_name("shroud_bolt_hole_\{i}")
        .translate(x=sx, y=sy, z=-shroud_flange_h - 1.0),
      )
    }
    // Dual cable-exit arches at 45 deg and 225 deg for CAN and XT30 power leads.
    let arch_hw = 8.0
    let arch_h = 8.5
    for idx, angle_deg in [45.0, 225.0] {
      let angle_rad = angle_deg * @math.PI / 180.0
      let arch = @step_cad.ExtrudedProfile::new(
          [
            (-arch_hw, -arch_h),
            (arch_hw, -arch_h),
            (arch_hw, 0.5),
            (-arch_hw, 0.5),
          ],
          16.0,
        )
        .with_name("shroud_cable_arch_\{idx}")
        .rotate_x(90.0)
        .rotate_z(90.0 + angle_deg)
        .translate(x=25.0 * @math.cos(angle_rad), y=25.0 * @math.sin(angle_rad))
      shroud_cutters.push(arch)
    }
    let shroud_body = @step_cad.difference(
      shroud_blank,
      shroud_cutters,
      name=name + "_moteus_shroud_body",
    ).with_color(housing_color)
    let mut shroud_comp = @cad.Component::new(
        name + "_moteus_shroud",
        description="Protective rear shroud covering the moteus C1 controller",
      )
      .with_part(shroud_part)
      .add_body(
        @cad.BodyPart::from_scene_node(
          shroud_body,
          density=@urdf.Density::carbon_fiber(),
          part=Some(shroud_part),
        ),
      )
      .add_mate_mm_deg("mount")
    for i in 0..<shroud_xy.length() {
      let (sx, sy) = shroud_xy[i]
      shroud_comp = shroud_comp
        .add_mate_mm_deg(
          "shroud_bolt_\{i}",
          x=sx,
          y=sy,
          z=-shroud_flange_h,
          rx_deg=180.0,
        )
        .attach(
          "\{name}_shroud_screw_merge_\{i}",
          parent_mate="shroud_bolt_\{i}",
          mg_tag_bodies(
            "\{name}_shroud_screw_\{i}",
            iso_shcs_screw(
              name="\{name}_shroud_screw_\{i}",
              size=@step_standards.M3,
              length_mm=8.0,
              detail~,
            ),
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
    comp = comp
      .add_mate_mm_deg("shroud_mount", z=pcb_standoff_z)
      .attach(
        name + "_moteus_shroud_merge",
        parent_mate="shroud_mount",
        shroud_comp,
        child_mate="mount",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  (comp, stator_z, pcb_standoff_z)
}

///|
/// Builds the bolted coupling (`MG-ROTOR-ADAPTER`) attaching A12's rotating
/// prop adapter to Stage 1's sun gear (`MG-SUN-1`), complete with 4x M4x8
/// mounting bolts, 2x 3x12 steel drive pins, and the central M4 insert.
fn build_a12_rotor_adapter(
  name : String,
  heat_set_inserts : Bool,
  detail : @step_common.DetailLevel,
) -> @cad.Component {
  let adapter_part = fabricated_part(
    "MG-ROTOR-ADAPTER", "Printed rotor-to-sun drive adapter (12.5 mm pilot, 23 mm 4xM4 flange, 15 mm boss with 2x3 mm steel drive pins and central M4 insert)",
    "carbon fiber nylon", "3D print", 6.0,
  )
  let raw_name = name + "_rotor_adapter"
  let base_profile = @step_cad.RevolvedProfile::polyline(
      [
        (2.25, -3.0),
        (6.25, -3.0),
        (6.25, 0.0),
        (15.5, 0.0),
        (15.5, 4.5),
        (7.5, 4.5),
        (7.5, 10.0),
        (3.0, 10.0),
        (3.0, 4.0),
        (2.25, 4.0),
      ],
      closed=true,
    )
    .as_shape()
    .with_name(raw_name + "_base")
  let spec = @step_motors.a12_motor_100kv_spec()
  let prop_r = spec.prop_hole_circle_diameter_mm / 2.0
  let cutters : Array[@step_cad.SceneNode] = [
    @step_cad.Cylinder::new(3.1, 7.0)
    .with_name("drive_pin_hole_pos")
    .translate(x=5.0, z=3.5),
    @step_cad.Cylinder::new(3.1, 7.0)
    .with_name("drive_pin_hole_neg")
    .translate(x=-5.0, z=3.5),
  ]
  for i in 0..<spec.prop_hole_count {
    let angle = (
        spec.prop_hole_phase_deg +
        360.0 * i.to_double() / spec.prop_hole_count.to_double()
      ) *
      @math.PI /
      180.0
    cutters.push(
      @step_cad.Cylinder::new(4.5, 6.0)
      .with_name("prop_bolt_cut_\{i}")
      .translate(
        x=prop_r * @math.sin(angle),
        y=prop_r * @math.cos(angle),
        z=-0.5,
      ),
    )
  }
  let adapter_node = @step_cad.difference(
    base_profile,
    cutters,
    name=raw_name + "_body",
  ).with_color(@step_cad.Rgb::orange())
  let pin_part = purchased_part(
    "DOWEL-3.0x12.0", "Hardened steel dowel pin 3.0 x 12.0 mm (rotor-to-sun torque drive)",
    "steel", 0.35,
  )
  let mut comp = @cad.Component::new(
      raw_name,
      description="Bolted rotor-to-sun drive adapter",
    )
    .with_part(adapter_part)
    .add_body(
      @cad.BodyPart::from_scene_node(
        adapter_node,
        density=@urdf.Density::carbon_fiber(),
        part=Some(adapter_part),
      ),
    )
    .add_mate_mm_deg("rotor_seat")
    .add_mate_mm_deg("sun_seat", z=10.0)
  for i in 0..<spec.prop_hole_count {
    let angle = (
        spec.prop_hole_phase_deg +
        360.0 * i.to_double() / spec.prop_hole_count.to_double()
      ) *
      @math.PI /
      180.0
    let bx = prop_r * @math.sin(angle)
    let by = prop_r * @math.cos(angle)
    comp = comp
      .add_mate_mm_deg("rotor_bolt_\{i}", x=bx, y=by, z=4.5)
      .attach(
        "\{raw_name}_rotor_screw_merge_\{i}",
        parent_mate="rotor_bolt_\{i}",
        mg_tag_bodies(
          "\{raw_name}_screw_\{i}",
          iso_shcs_screw(
            name="\{raw_name}_screw_\{i}",
            size=@step_standards.M4,
            length_mm=8.0,
            detail~,
          ),
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  for sign_idx, sx in [5.0, -5.0] {
    let pin_comp = @cad.Component::new(
        "\{raw_name}_pin_\{sign_idx}",
        description="Rotor-to-sun drive dowel pin",
      )
      .with_part(pin_part)
      .add_body(
        @cad.BodyPart::cylinder_mm(
          "\{raw_name}_drive_pin_\{sign_idx}",
          3.0,
          12.0,
          z_mm=6.0,
          density=@urdf.Density::steel_mild(),
          color=@step_cad.Rgb::grey(),
        ).with_part(pin_part),
      )
      .add_mate_mm_deg("base")
    comp = comp
      .add_mate_mm_deg("drive_pin_\{sign_idx}", x=sx, z=4.0)
      .attach(
        "\{raw_name}_pin_merge_\{sign_idx}",
        parent_mate="drive_pin_\{sign_idx}",
        pin_comp,
        child_mate="base",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  if heat_set_inserts {
    comp = comp
      .add_mate_mm_deg("sun_insert", z=10.0, rx_deg=180.0)
      .attach(
        raw_name + "_insert_merge",
        parent_mate="sun_insert",
        heat_set_insert(
          name=raw_name + "_sun_insert",
          outer_diam_mm=6.0,
          inner_diam_mm=4.0,
          length_mm=6.0,
        ),
        child_mate="seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  comp
}

///|
/// Builds the clamped torque coupler (`MG-STAGE2-COUPLER`) linking a flush
/// print-in-place stage's sun gear down to the previous stage's steel shaft.
fn build_stage_sun_coupler(
  name : String,
  shaft_diam : Double,
  coupler_height : Double,
) -> @cad.Component {
  let part = fabricated_part(
    "MG-STAGE2-COUPLER", "Printed stage-to-stage sun coupler (8 mm shaft bore, M3 set screw, 2x3x12 mm steel drive pins)",
    "carbon fiber nylon", "3D print", 4.0,
  )
  let bore_diam = shaft_diam + 0.1
  let set_screw_part = purchased_part(
    "SET-M3x6.0", "M3 x 6.0 mm socket set screw", "steel", 0.15,
  )
  let pin_part = purchased_part(
    "DOWEL-3.0x12.0", "Hardened steel dowel pin 3.0 x 12.0 mm (inter-stage sun drive)",
    "steel", 0.35,
  )
  let coupler_shell = @step_cad.difference(
    @step_cad.Cylinder::new(18.0, coupler_height).with_name(name + "_blank"),
    [
      @step_cad.Cylinder::new(bore_diam, coupler_height + 1.0)
      .with_name(name + "_center_bore")
      .translate(z=-0.5),
      @step_cad.Cylinder::new(3.1, coupler_height + 1.0)
      .with_name(name + "_pin_bore_pos")
      .translate(x=6.2, z=-0.5),
      @step_cad.Cylinder::new(3.1, coupler_height + 1.0)
      .with_name(name + "_pin_bore_neg")
      .translate(x=-6.2, z=-0.5),
      @step_cad.Cylinder::new(2.7, 9.0)
      .with_name(name + "_set_screw_bore")
      .rotate_x(-90.0)
      .translate(y=bore_diam / 2.0 - 1.0, z=coupler_height / 2.0),
    ],
    name=name + "_body",
  ).with_color(@step_cad.Rgb::orange())
  let mut comp = @cad.Component::new(
      name,
      description="Inter-stage sun drive coupler",
    )
    .with_part(part)
    .add_body(
      @cad.BodyPart::from_scene_node(
        coupler_shell,
        density=@urdf.Density::carbon_fiber(),
        part=Some(part),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_set_screw",
        3.0,
        6.0,
        y_mm=bore_diam / 2.0 + 3.0,
        z_mm=coupler_height / 2.0,
        rx_deg=90.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(set_screw_part),
    )
    .add_fastener(
      @cad.Fastener::new(
        "stage2_coupler_set_screw",
        @cad.FastenerKind::Screw,
        thread="M3",
        length_mm=6.0,
        engagement_mm=4.5,
        quantity=1,
        torque_nm=0.6,
        references=[name + "_body"],
        part=Some(set_screw_part),
      ),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("top", z=coupler_height)
  for sign_idx, sx in [6.2, -6.2] {
    let pin_comp = @cad.Component::new(
        "\{name}_pin_\{sign_idx}",
        description="Stage coupler drive dowel pin",
      )
      .with_part(pin_part)
      .add_body(
        @cad.BodyPart::cylinder_mm(
          "\{name}_drive_pin_\{sign_idx}",
          3.0,
          12.0,
          z_mm=6.0,
          density=@urdf.Density::steel_mild(),
          color=@step_cad.Rgb::grey(),
        ).with_part(pin_part),
      )
      .add_mate_mm_deg("base")
    comp = comp
      .add_mate_mm_deg("drive_pin_\{sign_idx}", x=sx)
      .attach(
        "\{name}_pin_merge_\{sign_idx}",
        parent_mate="drive_pin_\{sign_idx}",
        pin_comp,
        child_mate="base",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  comp
}

///|
/// Builds the single print-in-place STEP assembly (`MG-STAGE{k}-CARTRIDGE`) for
/// stage `stage_index` (1-based) of a multi-stage `motorized_gearbox` with
/// casing ring, bottom flange, carrier sleeve, 45-deg top bolt lugs, captive
/// sun gear, and captive planet gears all resting flat on `z = 0`.
pub fn motorized_stage_cartridge(
  name~ : String = "motorized_gearbox",
  preset~ : String = "5010_360kv",
  stages~ : Array[MotorizedStageSpec],
  stage_index~ : Int32 = 1,
  casing_wall_mm~ : Double = 6.0,
  flange_thickness_mm~ : Double = 6.0,
  flange_extra_mm~ : Double = 8.0,
  carrier_thickness_mm~ : Double = 8.0,
  carrier_margin_mm~ : Double = 2.0,
  casing_radial_clearance_mm~ : Double = 1.0,
  min_smooth_wall_mm~ : Double = 6.0,
  top_gap_mm~ : Double = 1.0,
  coupling_shaft_mm~ : Double = 8.0,
  motor_source~ : String = "preset",
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Detailed,
) -> @cad.Component {
  if stage_index < 1 || stage_index > stages.length() {
    abort("invalid motorized_stage_cartridge stage_index \{stage_index}")
  }
  let p = if motor_source == "a12" {
    resolve_bldc_preset("a12_8318_100kv")
  } else {
    resolve_bldc_preset(preset)
  }
  let clearance = pgb_carrier_clearance_mm
  let is_a12 = motor_source == "a12"
  let mut casing_outer = 0.0
  let stage_entries : Array[
    (
      MotorizedStageSpec,
      FlangedBearingSpec,
      PlanetaryGearboxParams,
      @step_planetary.HerringbonePlanetaryLayout,
      Double,
      Double,
      Double,
      Double,
    ),
  ] = []
  for k in 0..<stages.length() {
    let spec = stages[k]
    let bearing = resolve_flanged_bearing(spec.planet_bearing)
    let input_shaft_diam = if k == 0 {
      if is_a12 {
        4.3
      } else {
        p.shaft_diameter_mm
      }
    } else {
      coupling_shaft_mm
    }
    let trial_outer = 1.0
    let params : PlanetaryGearboxParams = {
      gear_module: spec.module_mm,
      gear_length_mm: spec.gear_length_mm,
      helix_angle_deg: 30.0,
      sun_teeth: spec.sun_teeth,
      planet_teeth: spec.planet_teeth,
      num_planets: spec.planet_count,
      pressure_angle_deg: 20.0,
      num_elbows: spec.num_elbows,
      resolution: 5,
      bore_radius_mm: input_shaft_diam / 2.0 + 0.1,
      planet_bore_radius_mm: bearing.outer_mm / 2.0 - 0.03,
      carrier_pin_diam_mm: bearing.bore_mm,
      carrier_bearing_designation: "",
      output_shaft_diam_mm: coupling_shaft_mm,
      carrier_thickness_mm,
      output_shaft_length_mm: 12.0,
      tolerance_mm: 0.2,
      outer_thickness_mm: trial_outer,
      include_carrier: true,
    }
    let step_params = pgb_step_params(params, spec.num_elbows == 0, detail)
    let layout = @step_planetary.herringbone_planetary_layout(step_params)
    let base_outer = layout.ring_outer_radius_mm - trial_outer
    let carrier_plate_radius = layout.center_distance_mm +
      layout.planet.outer_radius_mm +
      carrier_margin_mm
    let smooth_inner = carrier_plate_radius + casing_radial_clearance_mm
    let height = spec.gear_length_mm +
      clearance +
      carrier_thickness_mm +
      top_gap_mm
    let candidate = if base_outer + casing_wall_mm >
      smooth_inner + min_smooth_wall_mm {
      base_outer + casing_wall_mm
    } else {
      smooth_inner + min_smooth_wall_mm
    }
    if candidate > casing_outer {
      casing_outer = candidate
    }
    stage_entries.push(
      (
        spec, bearing, params, layout, base_outer, carrier_plate_radius, smooth_inner,
        height,
      ),
    )
  }
  let k = stage_index - 1
  let (spec, bearing, base_params, _, base_outer, _, smooth_inner, stage_height) = stage_entries[k]
  let outer_thickness = casing_outer - base_outer
  let params = { ..base_params, outer_thickness_mm: outer_thickness, }
  let smooth = spec.num_elbows == 0
  let step_params = pgb_step_params(params, smooth, detail)
  let layout = @step_planetary.herringbone_planetary_layout(step_params)
  let stage_step = expect_step(
    "cartridge stage \{stage_index}",
    @step_planetary.herringbone_planetary_gearbox(step_params),
  )
  let flange_outer_radius = casing_outer + flange_extra_mm
  let casing_bolt_radius = casing_outer + flange_extra_mm / 2.0
  let part = fabricated_part(
    "MG-STAGE\{stage_index}-CARTRIDGE",
    "Print-in-place stage \{stage_index} herringbone gear cartridge (casing ring, sun, and \{spec.planet_count} planets); print flat on z = 0",
    "carbon fiber nylon",
    "3D print",
    24.0,
  )
  let raw_ring = pgb_gear_part(
      "\{name}_stage\{stage_index}_ring",
      stage_step,
      "ring",
      "Integrated ring",
      part.part_number,
      0.0,
      spec.gear_length_mm,
      smooth,
    ).bodies[0]
  let ring_body = {
    ..raw_ring,
    name: "\{name}_stage\{stage_index}_ring",
    node: raw_ring.node.with_color(@step_cad.Rgb::black()),
    part: Some(part),
  }
  let bottom_phase = if k % 2 == 0 { 0.0 } else { 30.0 }
  let top_phase = if k % 2 == 0 { 30.0 } else { 0.0 }
  let mut comp = build_stage_casing_comp(
    name,
    stage_index,
    part,
    ring_body,
    spec.gear_length_mm,
    stage_height,
    layout.ring.outer_radius_mm,
    smooth_inner,
    casing_outer,
    flange_outer_radius,
    flange_thickness_mm,
    casing_bolt_radius,
    true,
    bottom_phase,
    top_phase,
    detail,
    @step_cad.Rgb::black(),
  )
  let raw_sun = pgb_gear_part(
      "\{name}_stage\{stage_index}_sun",
      stage_step,
      "sun",
      "Planetary sun gear",
      part.part_number,
      0.0,
      spec.gear_length_mm,
      smooth,
    ).bodies[0]
  let pin_depth_mm = if k == 0 { 5.4 } else { spec.gear_length_mm + 1.0 }
  let sun_body = cut_sun_drive_features(
    {
      ..raw_sun,
      name: "\{name}_stage\{stage_index}_sun_gear",
      node: raw_sun.node
      .with_name("\{name}_stage\{stage_index}_sun_gear")
      .with_color(@step_cad.Rgb::orange()),
      part: Some(part),
    },
    "\{name}_stage\{stage_index}_sun",
    if k == 0 {
      5.0
    } else {
      6.2
    },
    3.2,
    pin_depth_mm,
    if k == 0 && is_a12 {
      8.4
    } else {
      0.0
    },
    5.5,
    spec.gear_length_mm,
    @step_cad.Rgb::orange(),
  )
  comp = comp.add_body(sun_body)
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    let raw_p = pgb_gear_part(
        "\{name}_stage\{stage_index}_planet_\{i}",
        stage_step,
        "planet-\{i + 1}",
        "Planet gear",
        part.part_number,
        0.0,
        spec.gear_length_mm,
        smooth,
      ).bodies[0]
    let p_node = if bearing.flange_thickness_mm > 0.0 {
      let pocket_r = bearing.flange_outer_mm / 2.0 + PLANET_POCKET_CLEARANCE_MM
      let cutter = @step_cad.Cylinder::new(
          pocket_r * 2.0,
          bearing.flange_thickness_mm + 0.5,
        )
        .with_name("\{name}_stage\{stage_index}_planet_\{i}_pocket")
        .translate(z=spec.gear_length_mm - bearing.flange_thickness_mm)
      @step_cad.difference(
        raw_p.node,
        [cutter],
        name="\{name}_stage\{stage_index}_planet_\{i}",
      )
    } else {
      raw_p.node
    }
    let placed_p = p_node
      .with_color(@step_cad.Rgb::blue())
      .rotate_z(-planet.phi_deg)
      .translate(x=planet.x, y=-planet.z)
    comp = comp.add_body({
      ..raw_p,
      name: "\{name}_stage\{stage_index}_planet_\{i}",
      node: placed_p,
      part: Some(part),
    })
  }
  comp
}

///|
/// Builds the multi-stage motorized gearbox.
///
/// `stages` is ordered from the motor (stage 1) to the output (last stage).
/// All stage parameters are independent.
pub fn motorized_gearbox(
  name~ : String = "motorized_gearbox",
  preset~ : String = "5010_360kv",
  stages~ : Array[MotorizedStageSpec],
  casing_wall_mm~ : Double = 6.0,
  flange_thickness_mm~ : Double = 6.0,
  flange_extra_mm~ : Double = 8.0,
  carrier_thickness_mm~ : Double = 8.0,
  carrier_margin_mm~ : Double = 2.0,
  casing_radial_clearance_mm~ : Double = 1.0,
  min_smooth_wall_mm~ : Double = 6.0,
  top_gap_mm~ : Double = 1.0,
  coupling_shaft_mm~ : Double = 8.0,
  output_bearing~ : String = "FR8-2RS",
  output_free_length_mm~ : Double = 15.0,
  output_collar_width_mm~ : Double = 11.1,
  output_collar_outer_diam_mm~ : Double = 25.4,
  output_hub~ : Bool = true,
  output_hub_diam_mm~ : Double = 60.0,
  output_hub_thickness_mm~ : Double = 8.0,
  output_bolt_circle_mm~ : Double = 40.0,
  /// Three-hole tire-mount interface on the output hub face. Zero disables it.
  tire_mount_bolt_circle_mm~ : Double = 0.0,
  tire_mount_bolt_count~ : Int32 = 3,
  tire_mount_bolt_phase_deg~ : Double = 30.0,
  /// Printed hole diameter for the tire-mount heat-set inserts.
  tire_mount_bolt_hole_mm~ : Double = 6.0,
  frame_bolt_circle_mm~ : Double = 0.0,
  heat_set_inserts~ : Bool = true,
  dual_output_bearing~ : Bool = false,
  tire_mount_flush~ : Bool = false,
  moteus_shroud~ : Bool = false,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  motor_source~ : String = "preset",
  joint_name~ : String = "",
  add_binding~ : Bool = true,
) -> @cad.Component {
  if stages.length() < 1 {
    abort("motorized_gearbox needs at least one stage")
  }
  let is_a12 = motor_source == "a12"
  let p = if is_a12 {
    resolve_bldc_preset("a12_8318_100kv")
  } else {
    resolve_bldc_preset(preset)
  }
  let eff_frame_bolt_circle = if frame_bolt_circle_mm > 0.0 {
    frame_bolt_circle_mm
  } else if is_a12 {
    114.0
  } else {
    90.0
  }
  let mut stage_flush = is_a12
  for spec in stages {
    if spec.num_elbows > 0 {
      stage_flush = true
    }
  }
  let stage_count = stages.length()
  let clearance = pgb_carrier_clearance_mm
  let rotor_joint = if joint_name == "" {
    name + "_motor_rotor_joint"
  } else {
    joint_name
  }
  let out_bearing = resolve_flanged_bearing(output_bearing)
  let output_shaft_diam = out_bearing.bore_mm
  let mut motor = if is_a12 {
    step_a12_motor(name=name + "_motor", joint_name=rotor_joint)
  } else if motor_source == "brushless" {
    step_brushless_motor(
      name=name + "_motor",
      preset~,
      detail~,
      joint_name=rotor_joint,
    )
  } else {
    low_kv_bldc_motor(
      name=name + "_motor",
      preset~,
      detail~,
      joint_name=rotor_joint,
    )
  }
  // Parent casing carries the gearbox-rated ActuatorSpec; strip the inner motor
  // duplicate so PowerBudget does not double-count bus current.
  motor = { ..motor, actuator: None, }
  // ---------------------------------------------------------------------
  // Pass 1: derive each stage's gear dimensions and axial station.
  // ---------------------------------------------------------------------
  let infos : Array[MotorizedStage] = []
  let mut z = 0.0
  for k in 0..<stage_count {
    let spec = stages[k]
    let bearing = resolve_flanged_bearing(spec.planet_bearing)
    let smooth = spec.num_elbows == 0
    let input_shaft_diam = if k == 0 {
      if is_a12 {
        4.3
      } else {
        p.shaft_diameter_mm
      }
    } else {
      coupling_shaft_mm
    }
    let sun_bore_radius = input_shaft_diam / 2.0 + 0.1
    let planet_bore_radius = bearing.outer_mm / 2.0 - 0.03
    let pin_diam = bearing.bore_mm
    let planet_root = spec.module_mm *
      (spec.planet_teeth.to_double() / 2.0 - 1.25)
    if planet_bore_radius > planet_root - 1.5 {
      abort(
        "stage \{k + 1}: bearing \{spec.planet_bearing} (outer \{bearing.outer_mm} mm) does not fit planet \{spec.planet_teeth} at module \{spec.module_mm}; increase the module, increase the planet tooth count, or use a smaller bearing",
      )
    }
    let trial_outer = 1.0
    let params : PlanetaryGearboxParams = {
      gear_module: spec.module_mm,
      gear_length_mm: spec.gear_length_mm,
      helix_angle_deg: 30.0,
      sun_teeth: spec.sun_teeth,
      planet_teeth: spec.planet_teeth,
      num_planets: spec.planet_count,
      pressure_angle_deg: 20.0,
      num_elbows: spec.num_elbows,
      resolution: 5,
      bore_radius_mm: sun_bore_radius,
      planet_bore_radius_mm: planet_bore_radius,
      carrier_pin_diam_mm: pin_diam,
      carrier_bearing_designation: "",
      output_shaft_diam_mm: coupling_shaft_mm,
      carrier_thickness_mm,
      output_shaft_length_mm: 12.0,
      tolerance_mm: 0.2,
      outer_thickness_mm: trial_outer,
      include_carrier: true,
    }
    let step_params = pgb_step_params(params, smooth, detail)
    let layout = @step_planetary.herringbone_planetary_layout(step_params)
    let base_outer = layout.ring_outer_radius_mm - trial_outer
    let carrier_plate_radius = layout.center_distance_mm +
      layout.planet.outer_radius_mm +
      carrier_margin_mm
    let smooth_inner = carrier_plate_radius + casing_radial_clearance_mm
    let height = spec.gear_length_mm +
      clearance +
      carrier_thickness_mm +
      top_gap_mm
    infos.push({
      spec,
      bearing,
      params,
      layout,
      smooth,
      z0: z,
      gear_length: spec.gear_length_mm,
      height,
      base_outer,
      ring_free_bore: layout.ring.outer_radius_mm,
      carrier_plate_radius,
      smooth_inner,
      carrier_shaft_diam: if k + 1 == stage_count {
        output_shaft_diam
      } else {
        coupling_shaft_mm
      },
      carrier_shaft_length: 0.0,
      input_shaft_diam,
      sun_joint: "\{name}_stage\{k + 1}_sun_joint",
      carrier_joint: "\{name}_stage\{k + 1}_carrier_joint",
      sun_mount: "\{name}_stage\{k + 1}_sun_mount",
      carrier_mount: "\{name}_stage\{k + 1}_carrier_mount",
      casing_part: fabricated_part(
        "MG-CASING-\{k + 1}",
        "Printed stage \{k + 1} casing module with integrated internal ring gear, carrier bore, and joint flanges",
        "carbon fiber nylon",
        "3D print",
        16.0,
      ),
    })
    z = z +
      height +
      (if stage_flush {
        flange_thickness_mm
      } else {
        2.0 * flange_thickness_mm
      })
  }
  // ---------------------------------------------------------------------
  // Pass 2: pick one casing outside diameter and finalize each ring.
  // ---------------------------------------------------------------------
  let mut casing_outer = 0.0
  for info in infos {
    let gear_outer = info.base_outer + casing_wall_mm
    let sleeve_outer = info.smooth_inner + min_smooth_wall_mm
    let candidate = if gear_outer > sleeve_outer {
      gear_outer
    } else {
      sleeve_outer
    }
    if candidate > casing_outer {
      casing_outer = candidate
    }
  }
  let flange_outer_radius = casing_outer + flange_extra_mm
  let casing_bolt_radius = casing_outer + flange_extra_mm / 2.0
  let finalized : Array[MotorizedStage] = []
  for info in infos {
    let outer_thickness = casing_outer - info.base_outer
    let params = { ..info.params, outer_thickness_mm: outer_thickness, }
    let step_params = pgb_step_params(params, info.smooth, detail)
    let layout = @step_planetary.herringbone_planetary_layout(step_params)
    finalized.push({ ..info, params, layout, })
  }
  // ---------------------------------------------------------------------
  // Pass 3: output stack and carrier shaft lengths.
  // ---------------------------------------------------------------------
  let last = finalized[stage_count - 1]
  let output_cap_thickness = if out_bearing.width_mm + 2.0 > 10.0 {
    out_bearing.width_mm + 2.0
  } else {
    10.0
  }
  let output_turret_extra = if dual_output_bearing {
    out_bearing.width_mm + 4.0
  } else {
    0.0
  }
  let output_cap_top = last.z0 +
    last.height +
    flange_thickness_mm +
    output_cap_thickness
  let output_bearing_top = output_cap_top + output_turret_extra
  let output_hub_seat_global = output_bearing_top +
    out_bearing.flange_thickness_mm +
    0.3
  let eff_collar_between = if tire_mount_flush {
    0.0
  } else {
    output_collar_width_mm
  }
  let output_protrusion = output_turret_extra +
    out_bearing.flange_thickness_mm +
    0.3 +
    (if output_hub {
      if tire_mount_flush {
        // Leave shaft 0.5 mm recessed inside MG-OUTPUT-HUB so it never butts
        // against the tire mount's solid front plate when output_free = 0.
        output_hub_thickness_mm - 0.5
      } else {
        output_hub_thickness_mm + eff_collar_between
      }
    } else {
      0.0
    }) +
    output_free_length_mm
  let output_tip = output_cap_top + output_protrusion
  for k in 0..<stage_count {
    let info = finalized[k]
    let carrier_z = info.z0 + info.gear_length + clearance
    let reach = if k + 1 == stage_count {
      output_tip - carrier_z
    } else {
      let end_inset = if stage_flush { 0.5 } else { 0.0 }
      finalized[k + 1].z0 + finalized[k + 1].gear_length - end_inset - carrier_z
    }
    let shaft_length = reach - carrier_thickness_mm
    if shaft_length < 2.0 {
      abort(
        "stage \{k + 1}: carrier output shaft is too short to reach the next stage",
      )
    }
    finalized[k] = { ..info, carrier_shaft_length: shaft_length, }
  }
  // Motor stack: A12 uses its own ventilated stator housing + bolted rotor
  // adapter; compact presets use the flat motor cap and direct shaft engagement.
  let stage1 = finalized[0]
  let cap_min_thickness = 6.0
  let motor_cap_thickness = if is_a12 {
    0.0
  } else {
    let cap_offset = if stage_flush { 0.0 } else { flange_thickness_mm }
    let ideal_cap = p.shaft_length_mm - stage1.gear_length - cap_offset
    let thickness = if ideal_cap > cap_min_thickness {
      ideal_cap
    } else {
      cap_min_thickness
    }
    let shaft_end_z = -cap_offset - thickness + p.shaft_length_mm
    if shaft_end_z < 0.6 * stage1.gear_length {
      abort(
        "motor shaft is too short for stage 1 at gear length \{stage1.gear_length} mm; reduce the stage-1 gear length or choose a longer-shaft preset",
      )
    }
    thickness
  }
  let motor_cap_bottom = (if stage_flush { 0.0 } else { -flange_thickness_mm }) -
    motor_cap_thickness
  let sun_hub_1 = if stage_flush {
    0.0
  } else if flange_thickness_mm - 0.5 > 0.0 {
    flange_thickness_mm - 0.5
  } else {
    0.0
  }
  // ---------------------------------------------------------------------
  // Casing root: all casing modules, caps, and fixed hardware live here.
  // ---------------------------------------------------------------------
  let mut casing = @cad.Component::new(
      name + "_casing",
      description="Motorized multi-stage planetary gearbox casing",
    )
    .with_param("preset", p.name)
    .with_param("stages", stage_count.to_string())
    .with_param("casing_outer_diam_mm", (casing_outer * 2.0).to_string())
    .with_param("flange_outer_diam_mm", (flange_outer_radius * 2.0).to_string())
    .with_param("casing_bolt_circle_mm", (casing_bolt_radius * 2.0).to_string())
    .with_param("output_shaft_diam_mm", output_shaft_diam.to_string())
    .with_param("output_joint", last.carrier_joint)
    .with_param("command_joint", rotor_joint)
  // ---------------------------------------------------------------------
  // Per-stage casing modules, gears, carriers, and planet bearings.
  // ---------------------------------------------------------------------
  for k in 0..<stage_count {
    let info = finalized[k]
    let idx = k + 1
    let part = info.casing_part
    let color = @step_cad.Rgb::black()
    let stage_step = expect_step(
      "planetary gearbox stage \{idx}",
      @step_planetary.herringbone_planetary_gearbox(
        pgb_step_params(info.params, info.smooth, detail),
      ),
    )
    let ring_name = "\{name}_stage\{idx}_ring"
    let ring_comp = pgb_gear_part(
      ring_name,
      stage_step,
      "ring",
      "Integrated planetary ring gear",
      "MG-CASING-\{idx}",
      0.0,
      info.gear_length,
      info.smooth,
    )
    if ring_comp.bodies.length() != 1 {
      abort("stage \{idx}: expected one integrated ring body")
    }
    let raw_ring = ring_comp.bodies[0]
    let ring_body = {
      ..raw_ring,
      name: ring_name,
      node: raw_ring.node.with_name(ring_name).with_color(color),
      part: Some(part),
    }
    let bottom_phase_deg = if stage_flush {
      if k % 2 == 0 {
        0.0
      } else {
        30.0
      }
    } else {
      0.0
    }
    let top_phase_deg = if stage_flush {
      if k % 2 == 0 {
        30.0
      } else {
        0.0
      }
    } else {
      0.0
    }
    let module_comp = build_stage_casing_comp(
      name,
      idx,
      part,
      ring_body,
      info.gear_length,
      info.height,
      info.ring_free_bore,
      info.smooth_inner,
      casing_outer,
      flange_outer_radius,
      flange_thickness_mm,
      casing_bolt_radius,
      stage_flush,
      bottom_phase_deg,
      top_phase_deg,
      detail,
      color,
    )
    let top_z = info.z0 + info.height + flange_thickness_mm
    casing = casing.attach(
      "\{name}_stage\{idx}_casing_module_merge",
      parent_mate="origin",
      module_comp,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(offset_mm=info.z0),
    )
    casing = casing
      .add_mate_mm_deg(info.sun_mount, z=info.z0)
      .add_mate_mm_deg(
        info.carrier_mount,
        z=info.z0 + info.gear_length + clearance,
      )
    for i in 0..<6 {
      let t_theta = (top_phase_deg + 60.0 * i.to_double()) * @math.PI / 180.0
      let b_theta = (bottom_phase_deg + 60.0 * i.to_double()) * @math.PI / 180.0
      casing = casing
        .add_mate_mm_deg(
          "\{name}_stage\{idx}_top_bolt_\{i}",
          x=casing_bolt_radius * @math.cos(t_theta),
          y=casing_bolt_radius * @math.sin(t_theta),
          z=top_z,
          rx_deg=180.0,
        )
        .add_mate_mm_deg(
          "\{name}_stage\{idx}_bottom_bolt_\{i}",
          x=casing_bolt_radius * @math.cos(b_theta),
          y=casing_bolt_radius * @math.sin(b_theta),
          z=if stage_flush {
            info.z0 + flange_thickness_mm
          } else {
            info.z0 - flange_thickness_mm
          },
        )
    }
    // Sun gear and its input coupling.
    let sun_bore = info.input_shaft_diam + 0.2
    let sun_root = info.spec.module_mm *
      (info.spec.sun_teeth.to_double() / 2.0 - 1.25)
    let hub_diam = if sun_root * 2.0 - 2.0 > 24.0 {
      24.0
    } else {
      sun_root * 2.0 - 2.0
    }
    let hub_diam = if hub_diam < sun_bore + 6.0 {
      sun_bore + 6.0
    } else {
      hub_diam
    }
    let hub_length = if stage_flush {
      0.0
    } else if k == 0 {
      sun_hub_1
    } else {
      // Keep the hub above the previous carrier's output hub.
      let available = 2.0 * flange_thickness_mm + top_gap_mm - 1.0
      let desired = 8.0
      if available < desired {
        if available > 0.0 {
          available
        } else {
          0.0
        }
      } else {
        desired
      }
    }
    let sun_comp = pgb_gear_part(
      "\{name}_stage\{idx}_sun",
      stage_step,
      "sun",
      "Planetary sun gear",
      "MG-SUN-\{idx}",
      0.0,
      info.gear_length,
      info.smooth,
    )
    let sun_raw_body = if stage_flush {
      cut_sun_drive_features(
        sun_comp.bodies[0],
        "\{name}_stage\{idx}_sun",
        if k == 0 {
          5.0
        } else {
          6.2
        },
        3.2,
        if k == 0 {
          5.4
        } else {
          info.gear_length + 1.0
        },
        if k == 0 && is_a12 {
          8.4
        } else {
          0.0
        },
        5.5,
        info.gear_length,
        @step_cad.Rgb::orange(),
      )
    } else {
      sun_comp.bodies[0]
    }
    let mut sun = motorized_sun(
      "\{name}_stage\{idx}_sun",
      "MG-SUN-\{idx}",
      sun_raw_body,
      sun_bore,
      hub_diam,
      hub_length,
      info.gear_length,
      "M3",
    )
    let driver_joint = if k == 0 && is_a12 {
      // Physically attach Stage 1 sun to A12's bolted rotor adapter and clamp
      // it with an axial M4 SHCS from the open top face before installing
      // Stage 1 carrier.
      sun = sun
        .add_mate_mm_deg("clamp_seat", z=5.5)
        .attach(
          name + "_stage1_sun_bolt_merge",
          parent_mate="clamp_seat",
          mg_tag_bodies(
            name + "_stage1_sun_bolt",
            iso_shcs_screw(
              name=name + "_stage1_sun_bolt",
              size=@step_standards.M4,
              length_mm=12.0,
              detail~,
            ),
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
      motor = motor.attach_to(
        name + "_motor_rotor",
        name + "_rotor_magnet_merge",
        parent_mate="shaft_rear",
        encoder_magnet(
          name=name + "_rotor_magnet",
          diameter_mm=8.0,
          thickness_mm=2.0,
        ),
        child_mate="top",
        spec=@cad.JointSpec::merge_rigid(),
      )
      motor = motor.attach_to(
        name + "_motor_rotor",
        name + "_rotor_adapter_merge",
        parent_mate="output_face",
        build_a12_rotor_adapter(name, heat_set_inserts, detail),
        child_mate="rotor_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
      motor = motor.attach_to(
        name + "_rotor_adapter",
        info.sun_joint,
        parent_mate="sun_seat",
        sun,
        child_mate="bottom",
        spec=@cad.JointSpec::fixed(),
      )
      rotor_joint
    } else {
      casing = casing.attach(
        info.sun_joint,
        parent_mate=info.sun_mount,
        sun,
        child_mate="bottom",
        spec=@cad.JointSpec::continuous(
          limit=Some(@urdf.JointLimit::new(effort=15.0, velocity=30.0)),
          dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
        ),
      )
      info.sun_joint
    }
    if k > 0 && stage_flush {
      // Add the clamped inter-stage coupler above the previous stage carrier.
      let prev_carrier = "\{name}_stage\{k}_carrier"
      let coupler_height = flange_thickness_mm
      let coupler = build_stage_sun_coupler(
        "\{name}_stage\{idx}_coupler",
        coupling_shaft_mm,
        coupler_height,
      )
      casing = casing.attach_to(
        prev_carrier,
        "\{name}_stage\{idx}_coupler_merge",
        parent_mate="output_flange",
        coupler,
        child_mate="bottom",
        spec=@cad.JointSpec::merge_rigid(offset_mm=top_gap_mm),
      )
    }
    // Carrier.
    let carrier_z = info.z0 + info.gear_length + clearance
    let hub_seat = if k + 1 == stage_count && output_hub {
      Some(output_hub_seat_global - carrier_z)
    } else {
      None
    }
    let mut carrier = motorized_carrier(
      "\{name}_stage\{idx}_carrier",
      "MG-CARRIER-\{idx}",
      info.layout,
      info.params,
      info.carrier_plate_radius,
      clearance,
      carrier_thickness_mm,
      info.carrier_shaft_diam,
      info.carrier_shaft_length,
      hub_seat,
      detail,
    )
    // Planet gears with flanged bearings.
    let z_sun = info.spec.sun_teeth.to_double()
    let z_planet = info.spec.planet_teeth.to_double()
    let z_ring = info.layout.ring_teeth.to_double()
    let carrier_multiplier = z_sun / (z_sun + z_ring)
    let planet_multiplier = -(z_sun * z_ring) / (z_planet * (z_sun + z_ring))
    for i in 0..<info.layout.planets.length() {
      let planet_layer = "planet-\{i + 1}"
      let planet_comp = pgb_gear_part(
        "\{name}_stage\{idx}_planet_\{i}",
        stage_step,
        planet_layer,
        "Planetary planet gear",
        "MG-PLANET-\{idx}",
        0.0,
        info.gear_length,
        info.smooth,
      )
      if planet_comp.bodies.length() != 1 {
        abort("stage \{idx}: expected one body for \{planet_layer}")
      }
      let raw_planet = planet_comp.bodies[0]
      let planet_part = fabricated_part(
        "MG-PLANET-\{idx}",
        "Printed planetary planet gear; press the flanged bearing into the counterbore from the top face until it seats flush",
        "carbon fiber nylon",
        "3D print",
        3.0,
      )
      let planet_body0 = {
        ..raw_planet,
        name: "\{name}_stage\{idx}_planet_\{i}",
        node: raw_planet.node
        .with_name("\{name}_stage\{idx}_planet_\{i}")
        .with_color(@step_cad.Rgb::blue()),
        part: Some(planet_part),
      }
      let planet_body = if info.bearing.flange_thickness_mm > 0.0 {
        let pocket_radius = info.bearing.flange_outer_mm / 2.0 +
          PLANET_POCKET_CLEARANCE_MM
        let pocket_cutter = @step_cad.Cylinder::new(
            pocket_radius * 2.0,
            info.bearing.flange_thickness_mm + 0.5,
          )
          .with_name("\{name}_stage\{idx}_planet_\{i}_pocket_cutter")
          .translate(z=info.gear_length - info.bearing.flange_thickness_mm)
        {
          ..planet_body0,
          node: @step_cad.difference(
            planet_body0.node,
            [pocket_cutter],
            name="\{name}_stage\{idx}_planet_\{i}",
          ).with_color(@step_cad.Rgb::blue()),
        }
      } else {
        planet_body0
      }
      let mut planet = @cad.Component::new(
          "\{name}_stage\{idx}_planet_\{i}",
          description="Printed planetary planet gear with flanged bearing",
        )
        .with_param("bearing", info.bearing.designation)
        .with_param("bearing_press_mm", "0.06")
        .add_body(planet_body)
        .add_mate_mm_deg("bottom")
        .add_mate_mm_deg("top", z=info.gear_length)
        .add_mate_mm_deg("origin")
        .with_part(planet_part)
      let bearing = flanged_bearing_component(
        "\{name}_stage\{idx}_planet_\{i}_bearing",
        info.bearing,
        detail,
      )
      planet = planet.attach(
        "\{name}_stage\{idx}_planet_\{i}_bearing_merge",
        parent_mate="top",
        bearing,
        child_mate="flange_top_reversed",
        spec=@cad.JointSpec::merge_rigid(
          offset_mm=-info.bearing.flange_thickness_mm,
        ),
      )
      carrier = carrier.attach(
        "\{name}_stage\{idx}_planet_\{i}_joint",
        parent_mate="pin_\{i}",
        planet,
        child_mate="origin",
        spec=@cad.JointSpec::continuous(
          limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
          dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
          mimic=Some(
            @urdf.JointMimic::new(driver_joint, multiplier=planet_multiplier),
          ),
        ),
      )
    }
    casing = casing.attach(
      info.carrier_joint,
      parent_mate=info.carrier_mount,
      carrier,
      child_mate="bottom",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
        mimic=Some(
          @urdf.JointMimic::new(driver_joint, multiplier=carrier_multiplier),
        ),
      ),
    )
    // Sun coupling for non-A12 Stage 1 or subsequent continuous sun stages.
    if !(k == 0 && is_a12) {
      let sun_source = if k == 0 {
        rotor_joint
      } else {
        finalized[k - 1].carrier_joint
      }
      set_joint_mimic(
        casing,
        info.sun_joint,
        @urdf.JointMimic::new(sun_source, multiplier=1.0),
      )
    }
  }
  // ---------------------------------------------------------------------
  // Motor cap or ventilated A12 housing: fixed stator mount on casing.
  // ---------------------------------------------------------------------
  if is_a12 {
    let housing_part = fabricated_part(
      "MG-MOTOR-HOUSING", "Printed ventilated A12 stator housing (126.8 mm barrel, 6 cooling windows, 15 mm sensor bore, strong M4 CSK stator mount, and centered M3 moteus C1 standoffs)",
      "carbon fiber nylon", "3D print", 28.0,
    )
    let (housing_comp, _, _) = build_a12_motor_housing(
      name, casing_outer, flange_outer_radius, casing_bolt_radius, eff_frame_bolt_circle,
      housing_part, heat_set_inserts, moteus_shroud, detail,
    )
    casing = casing
      .attach(
        name + "_motor_housing_merge",
        parent_mate="origin",
        housing_comp,
        child_mate="top",
        spec=@cad.JointSpec::merge_rigid(),
      )
      .attach_to(
        name + "_motor_housing",
        name + "_motor_mount_joint",
        parent_mate="motor_mount",
        motor,
        child_mate="mount",
        spec=@cad.JointSpec::fixed(),
      )
  } else {
    let motor_cap_part = fabricated_part(
      "MG-MOTOR-CAP", "Printed motor end cap with motor bolt pattern, motor-bearing clearance bore, casing screws, and frame mounting holes",
      "carbon fiber nylon", "3D print", 12.0,
    )
    let motor_bolt_radius = p.bolt_circle_mm / 2.0
    let bearing_bore = bldc_front_bearing_outer(p.name) + 0.2
    let bolt_clear = 2.0 *
      (p.bolt_circle_mm / 2.0 - p.mount_hole_mm / 2.0 - 0.5)
    let motor_cap_bore = if bearing_bore < bolt_clear {
      bearing_bore
    } else {
      bolt_clear
    }
    let motor_cap_holes : Array[(Double, Double, Double)] = [
      (0.0, 0.0, motor_cap_bore),
    ]
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      motor_cap_holes.push(
        (
          motor_bolt_radius * @math.cos(theta),
          motor_bolt_radius * @math.sin(theta),
          p.mount_hole_mm,
        ),
      )
    }
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      motor_cap_holes.push(
        (
          casing_bolt_radius * @math.cos(theta),
          casing_bolt_radius * @math.sin(theta),
          3.4,
        ),
      )
    }
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
      motor_cap_holes.push(
        (
          eff_frame_bolt_circle / 2.0 * @math.cos(theta),
          eff_frame_bolt_circle / 2.0 * @math.sin(theta),
          5.5,
        ),
      )
    }
    let phase_radius = p.diameter_mm * 0.5 + 3.0
    let phase_angle = @math.PI / 4.0
    motor_cap_holes.push(
      (
        phase_radius * @math.cos(phase_angle),
        phase_radius * @math.sin(phase_angle),
        5.0,
      ),
    )
    let motor_cap_comp = @cad.Component::new(
        name + "_motor_cap_component",
        description="Printed motor end cap",
      )
      .with_part(motor_cap_part)
      .add_body(
        actuator_plate_body(
          name + "_motor_cap",
          flange_outer_radius * 2.0,
          motor_cap_thickness,
          0.0,
          motor_cap_holes,
          @urdf.Density::carbon_fiber(),
          @step_cad.Rgb::black(),
          detail,
        ).with_part(motor_cap_part),
      )
    casing = casing
      .attach(
        name + "_motor_cap_merge",
        parent_mate="origin",
        motor_cap_comp,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(offset_mm=motor_cap_bottom),
      )
      .add_mate_mm_deg("motor_mount", z=motor_cap_bottom, axis=(0.0, 0.0, -1.0))
      .add_mate_mm_deg("frame_mount", z=motor_cap_bottom, axis=(0.0, 0.0, -1.0))
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
      casing = casing.add_mate_mm_deg(
        "frame_mount_\{i}",
        x=eff_frame_bolt_circle / 2.0 * @math.cos(theta),
        y=eff_frame_bolt_circle / 2.0 * @math.sin(theta),
        z=motor_cap_bottom,
        axis=(0.0, 0.0, -1.0),
      )
    }
    // Motor stator fixed to the casing; its rotor joint is the command input.
    casing = casing.attach(
      name + "_motor_mount_joint",
      parent_mate="motor_mount",
      motor,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
    // The motor is a purchased solid, so its mounting screws are a schedule.
    let motor_m4 = p.mount_hole_mm > 3.5
    let motor_screw_thread = if motor_m4 { "M4" } else { "M3" }
    let motor_screw_length = standard_shcs_len(motor_cap_thickness + 4.0)
    let motor_screw_part = purchased_part(
      "ISO4762-\{motor_screw_thread}x\{fmt_mm(motor_screw_length)}",
      "ISO 4762 socket head cap screw \{motor_screw_thread} x \{fmt_mm(motor_screw_length)} mm",
      "steel",
      if motor_m4 {
        0.50
      } else {
        0.35
      },
    )
    casing = casing.add_fastener(
      @cad.Fastener::new(
        "motor_mount_screws",
        @cad.FastenerKind::Screw,
        thread=motor_screw_thread,
        length_mm=motor_screw_length,
        engagement_mm=5.0,
        quantity=4,
        torque_nm=if motor_m4 { 2.0 } else { 0.8 },
        references=[name + "_motor_cap"],
        part=Some(motor_screw_part),
      ),
    )
  }
  // ---------------------------------------------------------------------
  // Output cap with the output bearing and static mounting interface.
  // ---------------------------------------------------------------------
  let last_top_phase_deg = if stage_flush {
    if (stage_count - 1) % 2 == 0 {
      30.0
    } else {
      0.0
    }
  } else {
    0.0
  }
  let output_cap_part = fabricated_part(
    "MG-OUTPUT-CAP", "Printed output end cap with the output bearing seat, casing screws, and frame mounting holes",
    "carbon fiber nylon", "3D print", 12.0,
  )
  let output_cap_holes : Array[(Double, Double, Double)] = [
    (0.0, 0.0, out_bearing.outer_mm - 0.1),
  ]
  for i in 0..<6 {
    let theta = (last_top_phase_deg + 60.0 * i.to_double()) * @math.PI / 180.0
    output_cap_holes.push(
      (
        casing_bolt_radius * @math.cos(theta),
        casing_bolt_radius * @math.sin(theta),
        3.4,
      ),
    )
  }
  let out_frame_bolt_circle = if frame_bolt_circle_mm <= 0.0 &&
    stage_flush &&
    eff_frame_bolt_circle / 2.0 < casing_outer + 2.5 {
    casing_bolt_radius * 2.0
  } else {
    eff_frame_bolt_circle
  }
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
    output_cap_holes.push(
      (
        out_frame_bolt_circle / 2.0 * @math.cos(theta),
        out_frame_bolt_circle / 2.0 * @math.sin(theta),
        5.5,
      ),
    )
  }
  let output_cap_bottom = output_cap_top - output_cap_thickness
  let output_cap_body = if dual_output_bearing {
    let bore_r = (out_bearing.outer_mm - 0.1) / 2.0
    let turret_r = if out_bearing.flange_outer_mm / 2.0 + 1.5 > 17.2 {
      out_bearing.flange_outer_mm / 2.0 + 1.5
    } else {
      17.2
    }
    let total_span = output_cap_thickness + output_turret_extra
    let blank = @step_cad.RevolvedProfile::polyline(
        [
          (bore_r, 0.0),
          (flange_outer_radius, 0.0),
          (flange_outer_radius, output_cap_thickness),
          (turret_r, output_cap_thickness),
          (turret_r, total_span),
          (bore_r, total_span),
        ],
        closed=true,
      )
      .as_shape()
      .with_name(name + "_output_cap_blank")
    let cap_cutters : Array[@step_cad.SceneNode] = []
    for i in 1..<output_cap_holes.length() {
      let (hx, hy, hd) = output_cap_holes[i]
      cap_cutters.push(
        @step_cad.Cylinder::new(hd, output_cap_thickness + 2.0)
        .with_name(name + "_output_cap_hole_\{i}")
        .translate(x=hx, y=hy, z=-1.0),
      )
    }
    @step_cad.difference(blank, cap_cutters, name=name + "_output_cap").with_color(
      @step_cad.Rgb::black(),
    )
  } else {
    actuator_plate_body(
      name + "_output_cap",
      flange_outer_radius * 2.0,
      output_cap_thickness,
      0.0,
      output_cap_holes,
      @urdf.Density::carbon_fiber(),
      @step_cad.Rgb::black(),
      detail,
    ).node
  }
  let output_cap_comp = @cad.Component::new(
      name + "_output_cap_component",
      description="Printed output end cap",
    )
    .with_part(output_cap_part)
    .add_body(
      @cad.BodyPart::from_scene_node(
        output_cap_body,
        density=@urdf.Density::carbon_fiber(),
        part=Some(output_cap_part),
      ),
    )
  casing = casing
    .attach(
      name + "_output_cap_merge",
      parent_mate="origin",
      output_cap_comp,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(offset_mm=output_cap_bottom),
    )
    .add_mate_mm_deg("output_mount", z=output_cap_top)
    .add_mate_mm_deg("frame_mount_out", z=output_cap_top, axis=(0.0, 0.0, 1.0))
    .add_mate_mm_deg("output_bearing", z=output_bearing_top)
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
    casing = casing.add_mate_mm_deg(
      "frame_mount_out_\{i}",
      x=out_frame_bolt_circle / 2.0 * @math.cos(theta),
      y=out_frame_bolt_circle / 2.0 * @math.sin(theta),
      z=output_cap_top,
    )
  }
  let output_bearing_comp = flanged_bearing_component(
    name + "_output_bearing",
    out_bearing,
    detail,
  )
  casing = casing.attach(
    name + "_output_bearing_merge",
    parent_mate="output_bearing",
    output_bearing_comp,
    child_mate="flange_top_reversed",
    spec=@cad.JointSpec::merge_rigid(),
  )
  if dual_output_bearing {
    let inner_bearing_comp = flanged_bearing_component(
      name + "_output_bearing_inner",
      out_bearing,
      detail,
    )
    casing = casing
      .add_mate_mm_deg(
        "output_bearing_inner",
        z=output_cap_bottom,
        axis=(0.0, 0.0, -1.0),
      )
      .attach(
        name + "_output_bearing_inner_merge",
        parent_mate="output_bearing_inner",
        inner_bearing_comp,
        child_mate="flange_top",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  // ---------------------------------------------------------------------
  // Casing joint and cap screws, and their heat-set inserts.
  // ---------------------------------------------------------------------
  let insert_len = if stage_flush { 4.0 } else { 6.0 }
  if heat_set_inserts {
    for k in 0..<stage_count {
      let idx = k + 1
      for i in 0..<6 {
        casing = casing.attach(
          "\{name}_stage\{idx}_top_insert_merge_\{i}",
          parent_mate="\{name}_stage\{idx}_top_bolt_\{i}",
          mg_tag_bodies(
            "\{name}_stage\{idx}_top_insert_\{i}",
            heat_set_insert(
              name="\{name}_stage\{idx}_top_insert_\{i}",
              outer_diam_mm=4.5,
              inner_diam_mm=3.0,
              length_mm=insert_len,
            ),
          ),
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
      }
    }
    if !is_a12 {
      // Compact preset motor cap screws thread up into Stage 1 bottom flange.
      for i in 0..<6 {
        let theta = 2.0 * @math.PI * i.to_double() / 6.0
        casing = casing
          .add_mate_mm_deg(
            "\{name}_stage1_bottom_insert_\{i}",
            x=casing_bolt_radius * @math.cos(theta),
            y=casing_bolt_radius * @math.sin(theta),
            z=if stage_flush { 0.0 } else { -flange_thickness_mm },
          )
          .attach(
            "\{name}_stage1_bottom_insert_merge_\{i}",
            parent_mate="\{name}_stage1_bottom_insert_\{i}",
            mg_tag_bodies(
              "\{name}_stage1_bottom_insert_\{i}",
              heat_set_insert(
                name="\{name}_stage1_bottom_insert_\{i}",
                outer_diam_mm=4.5,
                inner_diam_mm=3.0,
                length_mm=insert_len,
              ),
            ),
            child_mate="seat",
            spec=@cad.JointSpec::merge_rigid(),
          )
      }
    }
  }
  // Stage 1 to motor housing/cap screws.
  for i in 0..<6 {
    let theta = 2.0 * @math.PI * i.to_double() / 6.0
    let bx = casing_bolt_radius * @math.cos(theta)
    let by = casing_bolt_radius * @math.sin(theta)
    if is_a12 {
      // Bolt downward from Stage 1 bottom flange into MG-MOTOR-HOUSING inserts.
      casing = casing
        .add_mate_mm_deg(
          name + "_motor_cap_bolt_\{i}",
          x=bx,
          y=by,
          z=flange_thickness_mm,
        )
        .attach(
          name + "_motor_cap_screw_merge_\{i}",
          parent_mate=name + "_motor_cap_bolt_\{i}",
          mg_tag_bodies(
            "\{name}_motor_cap_screw_\{i}",
            iso_shcs_screw(
              name="\{name}_motor_cap_screw_\{i}",
              size=@step_standards.M3,
              length_mm=standard_shcs_len(flange_thickness_mm + 4.0),
              detail~,
            ),
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    } else {
      casing = casing
        .add_mate_mm_deg(
          name + "_motor_cap_bolt_\{i}",
          x=bx,
          y=by,
          z=motor_cap_bottom,
          rx_deg=180.0,
        )
        .attach(
          name + "_motor_cap_screw_merge_\{i}",
          parent_mate=name + "_motor_cap_bolt_\{i}",
          mg_tag_bodies(
            "\{name}_motor_cap_screw_\{i}",
            iso_shcs_screw(
              name="\{name}_motor_cap_screw_\{i}",
              size=@step_standards.M3,
              length_mm=standard_shcs_len(motor_cap_thickness + insert_len),
              detail~,
            ),
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
  }
  // Stage-to-stage screws: heads on the upper bottom flange, shanks down into
  // the lower top-flange inserts.
  let stage_screw_len = standard_shcs_len(
    flange_thickness_mm + (if stage_flush { 4.0 } else { 6.0 }),
  )
  for k in 1..<stage_count {
    let idx = k + 1
    let info = finalized[k]
    let b_phase_deg = if stage_flush {
      if k % 2 == 0 {
        0.0
      } else {
        30.0
      }
    } else {
      0.0
    }
    for i in 0..<6 {
      let theta = (b_phase_deg + 60.0 * i.to_double()) * @math.PI / 180.0
      let bx = casing_bolt_radius * @math.cos(theta)
      let by = casing_bolt_radius * @math.sin(theta)
      casing = casing
        .add_mate_mm_deg(
          "\{name}_stage\{idx}_joint_bolt_\{i}",
          x=bx,
          y=by,
          z=if stage_flush { info.z0 + flange_thickness_mm } else { info.z0 },
        )
        .attach(
          "\{name}_stage\{idx}_joint_screw_merge_\{i}",
          parent_mate="\{name}_stage\{idx}_joint_bolt_\{i}",
          mg_tag_bodies(
            "\{name}_stage\{idx}_joint_screw_\{i}",
            iso_shcs_screw(
              name="\{name}_stage\{idx}_joint_screw_\{i}",
              size=@step_standards.M3,
              length_mm=stage_screw_len,
              detail~,
            ),
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
  }
  // Output cap screws: heads on the cap top, shanks down into the final top
  // flange inserts.
  for i in 0..<6 {
    let theta = (last_top_phase_deg + 60.0 * i.to_double()) * @math.PI / 180.0
    let bx = casing_bolt_radius * @math.cos(theta)
    let by = casing_bolt_radius * @math.sin(theta)
    casing = casing
      .add_mate_mm_deg(
        name + "_output_cap_bolt_\{i}",
        x=bx,
        y=by,
        z=output_cap_top,
      )
      .attach(
        name + "_output_cap_screw_merge_\{i}",
        parent_mate=name + "_output_cap_bolt_\{i}",
        mg_tag_bodies(
          "\{name}_output_cap_screw_\{i}",
          iso_shcs_screw(
            name="\{name}_output_cap_screw_\{i}",
            size=@step_standards.M3,
            length_mm=standard_shcs_len(output_cap_thickness + 6.0),
            detail~,
          ),
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  // ---------------------------------------------------------------------
  // Rotating output interface: flange hub plus a clamp collar.
  // ---------------------------------------------------------------------
  if output_hub {
    let has_radial_lock = tire_mount_flush ||
      (
        dual_output_bearing &&
        output_hub_diam_mm >= 50.0 &&
        output_hub_thickness_mm >= 9.0
      )
    let hub_part = fabricated_part(
      "MG-OUTPUT-HUB",
      if tire_mount_flush {
        "Printed output flange hub with a 40 mm bolt circle, flush three-hole tire-mount interface with M4 heat-set inserts, and dual radial M4 set-screw shaft clamps"
      } else if has_radial_lock {
        "Printed output flange hub with a 40 mm bolt circle for hips, knees, and driven links, plus dual radial M4 set-screw shaft clamps; retained by the shaft collar"
      } else {
        "Printed output flange hub with a 40 mm bolt circle for wheels, knees, hips, and other driven links, plus an optional three-hole tire-mount interface with heat-set inserts; retained by the shaft collar"
      },
      "carbon fiber nylon",
      "3D print",
      8.0,
    )
    let hub_bore = output_shaft_diam - 0.03
    let hub_holes : Array[(Double, Double, Double)] = [(0.0, 0.0, hub_bore)]
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
      hub_holes.push(
        (
          output_bolt_circle_mm / 2.0 * @math.cos(theta),
          output_bolt_circle_mm / 2.0 * @math.sin(theta),
          4.5,
        ),
      )
    }
    if tire_mount_bolt_circle_mm > 0.0 && tire_mount_bolt_count > 0 {
      for i in 0..<tire_mount_bolt_count {
        let theta = (
            tire_mount_bolt_phase_deg +
            360.0 * i.to_double() / tire_mount_bolt_count.to_double()
          ) *
          @math.PI /
          180.0
        hub_holes.push(
          (
            tire_mount_bolt_circle_mm / 2.0 * @math.cos(theta),
            tire_mount_bolt_circle_mm / 2.0 * @math.sin(theta),
            tire_mount_bolt_hole_mm,
          ),
        )
      }
    }
    let hub_body = if has_radial_lock {
      let blank = @step_cad.Cylinder::new(
        output_hub_diam_mm, output_hub_thickness_mm,
      ).with_name(name + "_output_hub_blank")
      let hub_cutters : Array[@step_cad.SceneNode] = []
      for i, hole in hub_holes {
        let (hx, hy, hd) = hole
        hub_cutters.push(
          @step_cad.Cylinder::new(hd, output_hub_thickness_mm + 2.0)
          .with_name(name + "_output_hub_hole_\{i}")
          .translate(x=hx, y=hy, z=-1.0),
        )
      }
      let hub_r = output_hub_diam_mm / 2.0
      let mid_z = output_hub_thickness_mm / 2.0
      // Radial M4 tap clearance, brass INSERT-4 pockets (r = 10..16), and outer
      // hex-key access bores at 0 deg and 180 deg, clearing both 40 mm (45 deg)
      // and 55.85 mm (30/150/270 deg) bolt circles.
      hub_cutters.push(
        @step_cad.Cylinder::new(4.2, 22.0)
        .with_name(name + "_output_hub_radial_tap")
        .rotate_y(90.0)
        .translate(x=-11.0, z=mid_z),
      )
      for idx, sign in [1.0, -1.0] {
        let rot = if sign > 0.0 { 90.0 } else { -90.0 }
        hub_cutters.push(
          @step_cad.Cylinder::new(5.8, 6.2)
          .with_name(name + "_output_hub_radial_insert_cut_\{idx}")
          .rotate_y(rot)
          .translate(x=sign * 9.9, z=mid_z),
        )
        let access_len = if hub_r > 15.8 { hub_r - 14.5 } else { 4.0 }
        hub_cutters.push(
          @step_cad.Cylinder::new(6.6, access_len)
          .with_name(name + "_output_hub_radial_wrench_\{idx}")
          .rotate_y(rot)
          .translate(x=sign * 15.8, z=mid_z),
        )
      }
      @cad.BodyPart::from_scene_node(
        @step_cad.difference(blank, hub_cutters, name=name + "_output_hub_body").with_color(
          @step_cad.Rgb::orange(),
        ),
        density=@urdf.Density::carbon_fiber(),
        part=Some(hub_part),
      )
    } else {
      actuator_plate_body(
        name + "_output_hub_body",
        output_hub_diam_mm,
        output_hub_thickness_mm,
        0.0,
        hub_holes,
        @urdf.Density::carbon_fiber(),
        @step_cad.Rgb::orange(),
        detail,
      ).with_part(hub_part)
    }
    let mut hub = @cad.Component::new(
        name + "_output_hub",
        description="Output flange hub",
      )
      .with_param("bolt_circle_mm", output_bolt_circle_mm.to_string())
      .with_param(
        "tire_mount_bolt_circle_mm",
        tire_mount_bolt_circle_mm.to_string(),
      )
      .with_param("shaft_bore_mm", hub_bore.to_string())
      .add_body(hub_body)
      .add_mate_mm_deg("back")
      .add_mate_mm_deg("output_face", z=output_hub_thickness_mm)
      .add_mate_mm_deg(
        "tire_mount",
        z=output_hub_thickness_mm + eff_collar_between,
        ry_deg=90.0,
        axis=(1.0, 0.0, 0.0),
      )
      .with_part(hub_part)
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
      hub = hub.add_mate_mm_deg(
        "bolt_\{i}",
        x=output_bolt_circle_mm / 2.0 * @math.cos(theta),
        y=output_bolt_circle_mm / 2.0 * @math.sin(theta),
        z=output_hub_thickness_mm,
      )
    }
    if tire_mount_bolt_circle_mm > 0.0 && tire_mount_bolt_count > 0 {
      for i in 0..<tire_mount_bolt_count {
        let theta = (
            tire_mount_bolt_phase_deg +
            360.0 * i.to_double() / tire_mount_bolt_count.to_double()
          ) *
          @math.PI /
          180.0
        let bx = tire_mount_bolt_circle_mm / 2.0 * @math.cos(theta)
        let by = tire_mount_bolt_circle_mm / 2.0 * @math.sin(theta)
        hub = hub
          .add_mate_mm_deg(
            "tire_mount_bolt_\{i}",
            x=bx,
            y=by,
            z=output_hub_thickness_mm,
          )
          .attach(
            "output_hub_insert_merge_\{i}",
            parent_mate="tire_mount_bolt_\{i}",
            heat_set_insert(
              name=name + "_output_hub_insert_\{i}",
              outer_diam_mm=tire_mount_bolt_hole_mm,
              inner_diam_mm=4.0,
              length_mm=6.0,
            ),
            child_mate="top",
            spec=@cad.JointSpec::merge_rigid(),
          )
      }
    }
    if has_radial_lock {
      let mid_z = output_hub_thickness_mm / 2.0
      let set_screw_part = purchased_part(
        "SET-M4x10.0", "M4 x 10.0 mm socket set screw", "steel", 0.10,
      )
      for idx, sign in [1.0, -1.0] {
        let rot = if sign > 0.0 { 90.0 } else { -90.0 }
        hub = hub
          .add_mate_mm_deg(
            "radial_insert_\{idx}",
            x=sign * 16.0,
            z=mid_z,
            ry_deg=rot,
          )
          .attach(
            "output_hub_radial_insert_merge_\{idx}",
            parent_mate="radial_insert_\{idx}",
            mg_tag_bodies(
              name + "_output_hub_radial_insert_\{idx}",
              heat_set_insert(
                name=name + "_output_hub_radial_insert_\{idx}",
                outer_diam_mm=6.0,
                inner_diam_mm=4.0,
                length_mm=6.0,
              ),
            ),
            child_mate="top",
            spec=@cad.JointSpec::merge_rigid(),
          )
          .add_body(
            @cad.BodyPart::cylinder_mm(
              name + "_output_hub_set_screw_\{idx}",
              4.0,
              10.0,
              x_mm=sign * 11.0,
              z_mm=mid_z,
              ry_deg=rot,
              density=@urdf.Density::steel_mild(),
              color=@step_cad.Rgb::grey(),
            ).with_part(set_screw_part),
          )
      }
      hub = hub.add_fastener(
        @cad.Fastener::new(
          "output_hub_radial_set_screws",
          @cad.FastenerKind::Screw,
          thread="M4",
          length_mm=10.0,
          engagement_mm=6.0,
          quantity=2,
          torque_nm=1.5,
          references=[name + "_output_hub_body"],
          part=Some(set_screw_part),
        ),
      )
    }
    casing = casing.attach_to(
      motorized_last_carrier_name(name, stage_count),
      name + "_output_hub_joint",
      parent_mate="output_hub_seat",
      hub,
      child_mate="back",
      spec=@cad.JointSpec::merge_rigid(),
    )
    if !tire_mount_flush {
      let collar = shaft_collar(
        name=name + "_output_hub_collar",
        bore_diam_mm=output_shaft_diam,
        outer_diam_mm=output_collar_outer_diam_mm,
        width_mm=output_collar_width_mm,
        style="set_screw",
        thread_size=@step_standards.M4,
      )
      casing = casing.attach_to(
        name + "_output_hub",
        name + "_output_hub_collar_joint",
        parent_mate="output_face",
        collar,
        child_mate="bore",
        spec=@cad.JointSpec::merge_rigid(offset_mm=output_collar_width_mm / 2.0),
      )
    }
  }
  // ---------------------------------------------------------------------
  // Stage reduction records, actuator specification, and control binding.
  // ---------------------------------------------------------------------
  let mut total_reduction = 1.0
  for info in finalized {
    let z_sun = info.spec.sun_teeth.to_double()
    let z_ring = info.layout.ring_teeth.to_double()
    total_reduction = total_reduction * (1.0 + z_ring / z_sun)
  }
  let mut efficiency = 1.0
  for _ in 0..<stage_count {
    efficiency = efficiency * 0.9
  }
  let output_torque = bldc_rated_torque(p) * total_reduction * efficiency
  let geared_spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Bldc,
    model="Motorized planetary gearbox " + p.name,
    voltage_v=p.voltage_v,
    current_rated_a=p.current_rated_a,
    current_stall_a=p.current_peak_a,
    torque_rated_nm=output_torque,
    driver=if is_a12 { "moteus C1 / FOC" } else { "VESC / SimpleFOC" },
    interface="CAN",
    encoder="rotor magnet read by a rear-mounted moteus C1 (AS5047P); 1:1 with the input sun gear",
  )
  let mut out = casing
    .with_actuator(geared_spec)
    .with_param("reduction", total_reduction.to_string())
    .with_param("output_torque_nm", output_torque.to_string())
    .with_param("output_shaft_protrusion_mm", output_protrusion.to_string())
    .with_param("motor_cap_thickness_mm", motor_cap_thickness.to_string())
    .with_param("output_cap_thickness_mm", output_cap_thickness.to_string())
    .add_fit(
      @cad.Fit::new(
        "planet_bearing_seat",
        @cad.FitClass::Interference,
        nominal_mm=finalized[0].bearing.outer_mm,
        min_mm=finalized[0].bearing.outer_mm - 0.12,
        max_mm=finalized[0].bearing.outer_mm,
      ),
    )
    .add_fit(
      @cad.Fit::new(
        "output_bearing_seat",
        @cad.FitClass::Transition,
        nominal_mm=out_bearing.outer_mm,
        min_mm=out_bearing.outer_mm - 0.1,
        max_mm=out_bearing.outer_mm,
      ),
    )
    .add_fit(
      @cad.Fit::new(
        "output_hub_bore",
        @cad.FitClass::Interference,
        nominal_mm=output_shaft_diam,
        min_mm=output_shaft_diam - 0.06,
        max_mm=output_shaft_diam,
      ),
    )
  if add_binding {
    out = out.add_control_binding(
      @cad.ControlBinding::new(
        rotor_joint,
        actuator=name + "_motor_stator",
        channel="can0:1",
        gear_ratio=total_reduction,
        soft_lower=Some(-1000.0),
        soft_upper=Some(1000.0),
      ),
    )
  }
  out
}
