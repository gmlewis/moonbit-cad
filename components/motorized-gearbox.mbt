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
/// A flanged ball bearing component.
///
/// Local frame: the flange top is `z = 0`; the flange occupies
/// `-flange_thickness_mm .. 0` and the bearing body occupies
/// `0 .. width_mm`. Attach `flange_top` to the planet's lower face so the body
/// extends up into the planet bore and the flange seats flush on the face.
fn flanged_bearing_component(
  name : String,
  spec : FlangedBearingSpec,
  detail : @step_common.DetailLevel,
) -> @cad.Component {
  let part = purchased_part(
    "BEARING-\{spec.designation}",
    "Flanged sealed ball bearing \{spec.designation} (\{spec.bore_mm} x \{spec.outer_mm} x \{spec.width_mm} mm, flange \{spec.flange_outer_mm} mm); friction-press into the gear, flange flush with the face",
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
  if spec.flange_thickness_mm > 0.0 {
    comp = comp.add_body(
      @cad.BodyPart::tube_mm(
        name + "_flange",
        spec.flange_outer_mm,
        spec.bore_mm,
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
    part_number, "Printed planetary carrier plate and hub; press the steel pins into the plate and the output shaft into the hub",
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
  // The central clearance hole must clear the sun end face and stay clear of
  // the pin holes. Cap it so small modules remain printable.
  let central_hole = 2.0 *
    (layout.center_distance_mm - (pin_diam + 0.1) / 2.0 - 0.5)
  let central_diameter = if central_hole < 22.0 { central_hole } else { 22.0 }
  let central_diameter = if central_diameter < 12.0 {
    12.0
  } else {
    central_diameter
  }
  let plate_holes : Array[(Double, Double, Double)] = []
  plate_holes.push((0.0, 0.0, central_diameter))
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    plate_holes.push((planet.x, -planet.z, pin_diam - 0.1))
  }
  let hub_diam = if shaft_diam + 14.0 > 32.0 { shaft_diam + 14.0 } else { 32.0 }
  let hub_height = 4.0
  let bore_diam = shaft_diam + 0.1
  let set_screw_len = standard_set_screw_len(
    hub_diam / 2.0 - bore_diam / 2.0 + 0.5,
  )
  let set_screw_center = bore_diam / 2.0 + set_screw_len / 2.0
  let set_screw_part = purchased_part(
    "SET-M4x\{fmt_mm(set_screw_len)}",
    "M4 x \{fmt_mm(set_screw_len)} socket set screw",
    "steel",
    0.25,
  )
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
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_hub",
        hub_diam,
        bore_diam,
        hub_height,
        z_mm=thickness - hub_height / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::green(),
      ).with_part(plate_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_set_screw",
        4.0,
        set_screw_len,
        x_mm=set_screw_center,
        z_mm=thickness - hub_height / 2.0,
        ry_deg=90.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(set_screw_part),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("output_flange", z=thickness)
    .add_mate_mm_deg("output_shaft", z=shaft_total)
    .with_part(plate_part)
    .add_fastener(
      @cad.Fastener::new(
        "carrier_hub_set_screw",
        @cad.FastenerKind::Screw,
        thread="M4",
        length_mm=set_screw_len,
        engagement_mm=4.0,
        quantity=1,
        torque_nm=1.5,
        references=[name + "_hub"],
        part=Some(set_screw_part),
      ),
    )
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
  frame_bolt_circle_mm~ : Double = 90.0,
  heat_set_inserts~ : Bool = true,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  motor_source~ : String = "preset",
  joint_name~ : String = "",
  add_binding~ : Bool = true,
) -> @cad.Component {
  if stages.length() < 1 {
    abort("motorized_gearbox needs at least one stage")
  }
  let p = resolve_bldc_preset(preset)
  let stage_count = stages.length()
  let clearance = pgb_carrier_clearance_mm
  let rotor_joint = if joint_name == "" {
    name + "_motor_rotor_joint"
  } else {
    joint_name
  }
  let out_bearing = resolve_flanged_bearing(output_bearing)
  let output_shaft_diam = out_bearing.bore_mm
  let motor = if motor_source == "brushless" {
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
      p.shaft_diameter_mm
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
    z = z + height + 2.0 * flange_thickness_mm
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
  let output_cap_top = last.z0 +
    last.height +
    flange_thickness_mm +
    output_cap_thickness
  let output_hub_seat_global = output_cap_top +
    out_bearing.flange_thickness_mm +
    0.3
  let output_protrusion = out_bearing.flange_thickness_mm +
    0.3 +
    (if output_hub {
      output_hub_thickness_mm + output_collar_width_mm
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
      finalized[k + 1].z0 + finalized[k + 1].gear_length - carrier_z
    }
    let shaft_length = reach - carrier_thickness_mm
    if shaft_length < 2.0 {
      abort(
        "stage \{k + 1}: carrier output shaft is too short to reach the next stage",
      )
    }
    finalized[k] = { ..info, carrier_shaft_length: shaft_length, }
  }
  // Motor stack: the motor shaft is flush with (or slightly short of) the
  // stage-1 sun top. The bottom cap thickness absorbs the preset's shaft.
  let stage1 = finalized[0]
  let cap_min_thickness = 6.0
  let ideal_cap = p.shaft_length_mm - stage1.gear_length - flange_thickness_mm
  let motor_cap_thickness = if ideal_cap > cap_min_thickness {
    ideal_cap
  } else {
    cap_min_thickness
  }
  let shaft_end_z = -flange_thickness_mm -
    motor_cap_thickness +
    p.shaft_length_mm
  if shaft_end_z < 0.6 * stage1.gear_length {
    abort(
      "motor shaft is too short for stage 1 at gear length \{stage1.gear_length} mm; reduce the stage-1 gear length or choose a longer-shaft preset",
    )
  }
  let motor_cap_bottom = -flange_thickness_mm - motor_cap_thickness
  let sun_hub_1 = if flange_thickness_mm - 0.5 > 0.0 {
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
    let mut module_comp = @cad.Component::new(
        "\{name}_stage\{idx}_casing_module",
        description="Printed stage casing module with integrated ring gear, carrier bore, and joint flanges",
      )
      .with_part(part)
      .add_body(ring_body)
    // Smooth carrier bore above the ring.
    let smooth_height = info.height - info.gear_length
    module_comp = module_comp.add_body(
      @cad.BodyPart::tube_mm(
        "\{name}_stage\{idx}_casing_sleeve",
        casing_outer * 2.0,
        info.smooth_inner * 2.0,
        smooth_height,
        z_mm=info.gear_length + smooth_height / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color~,
      ).with_part(part),
    )
    // Bottom flange ring.
    let bottom_holes : Array[(Double, Double, Double)] = [
      (0.0, 0.0, info.ring_free_bore * 2.0 + 0.4),
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
    // Top flange ring.
    let top_holes : Array[(Double, Double, Double)] = [
      (0.0, 0.0, info.smooth_inner * 2.0),
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
    let top_z = info.z0 + info.height + flange_thickness_mm
    module_comp = module_comp.add_body(
      actuator_plate_body(
        "\{name}_stage\{idx}_top_flange",
        flange_outer_radius * 2.0,
        flange_thickness_mm,
        info.height,
        top_holes,
        @urdf.Density::carbon_fiber(),
        color,
        detail,
      ).with_part(part),
    )
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
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      let bx = casing_bolt_radius * @math.cos(theta)
      let by = casing_bolt_radius * @math.sin(theta)
      casing = casing
        .add_mate_mm_deg(
          "\{name}_stage\{idx}_top_bolt_\{i}",
          x=bx,
          y=by,
          z=top_z,
          rx_deg=180.0,
        )
        .add_mate_mm_deg(
          "\{name}_stage\{idx}_bottom_bolt_\{i}",
          x=bx,
          y=by,
          z=info.z0 - flange_thickness_mm,
        )
    }
    // Sun gear and its integral input hub.
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
    let hub_length = if k == 0 {
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
    let sun = motorized_sun(
      "\{name}_stage\{idx}_sun",
      "MG-SUN-\{idx}",
      sun_comp.bodies[0],
      sun_bore,
      hub_diam,
      hub_length,
      info.gear_length,
      "M3",
    )
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
        "Printed planetary planet gear; press the flanged bearing into the counterbore from the lower face until it seats flush",
        "carbon fiber nylon",
        "3D print",
        3.0,
      )
      // Cut a counterbore for the flanged bearing into the lower face, so the
      // flange seats flush with the gear face and cannot walk out axially.
      // The gear body spans z in [0, gear_length]; the pocket is cut from
      // just below the face to the flange thickness.
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
          info.bearing.flange_thickness_mm,
        ).with_name("\{name}_stage\{idx}_planet_\{i}_pocket_cutter")
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
        parent_mate="bottom",
        bearing,
        child_mate="flange_top",
        spec=@cad.JointSpec::merge_rigid(
          offset_mm=info.bearing.flange_thickness_mm,
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
            @urdf.JointMimic::new(info.sun_joint, multiplier=planet_multiplier),
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
          @urdf.JointMimic::new(info.sun_joint, multiplier=carrier_multiplier),
        ),
      ),
    )
    // Sun coupling: stage 1 follows the motor rotor; later stages follow the
    // previous carrier directly.
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
  // ---------------------------------------------------------------------
  // Motor cap: the motor's fixed side bolts to this plate, which is part of
  // the outer casing.
  // ---------------------------------------------------------------------
  let motor_cap_part = fabricated_part(
    "MG-MOTOR-CAP", "Printed motor end cap with motor bolt pattern, motor-bearing clearance bore, casing screws, and frame mounting holes",
    "carbon fiber nylon", "3D print", 12.0,
  )
  let motor_bolt_radius = p.bolt_circle_mm / 2.0
  let bearing_bore = bldc_front_bearing_outer(p.name) + 0.2
  let bolt_clear = 2.0 * (p.bolt_circle_mm / 2.0 - p.mount_hole_mm / 2.0 - 0.5)
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
        frame_bolt_circle_mm / 2.0 * @math.cos(theta),
        frame_bolt_circle_mm / 2.0 * @math.sin(theta),
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
      x=frame_bolt_circle_mm / 2.0 * @math.cos(theta),
      y=frame_bolt_circle_mm / 2.0 * @math.sin(theta),
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
  // ---------------------------------------------------------------------
  // Output cap with the output bearing and static mounting interface.
  // ---------------------------------------------------------------------
  let output_cap_part = fabricated_part(
    "MG-OUTPUT-CAP", "Printed output end cap with the output bearing seat, casing screws, and frame mounting holes",
    "carbon fiber nylon", "3D print", 12.0,
  )
  let output_cap_holes : Array[(Double, Double, Double)] = [
    (0.0, 0.0, out_bearing.outer_mm - 0.1),
  ]
  for i in 0..<6 {
    let theta = 2.0 * @math.PI * i.to_double() / 6.0
    output_cap_holes.push(
      (
        casing_bolt_radius * @math.cos(theta),
        casing_bolt_radius * @math.sin(theta),
        3.4,
      ),
    )
  }
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
    output_cap_holes.push(
      (
        frame_bolt_circle_mm / 2.0 * @math.cos(theta),
        frame_bolt_circle_mm / 2.0 * @math.sin(theta),
        5.5,
      ),
    )
  }
  let output_cap_bottom = output_cap_top - output_cap_thickness
  let output_cap_comp = @cad.Component::new(
      name + "_output_cap_component",
      description="Printed output end cap",
    )
    .with_part(output_cap_part)
    .add_body(
      actuator_plate_body(
        name + "_output_cap",
        flange_outer_radius * 2.0,
        output_cap_thickness,
        0.0,
        output_cap_holes,
        @urdf.Density::carbon_fiber(),
        @step_cad.Rgb::black(),
        detail,
      ).with_part(output_cap_part),
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
    .add_mate_mm_deg("output_bearing", z=output_cap_top)
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * (i.to_double() + 0.5) / 4.0
    casing = casing.add_mate_mm_deg(
      "frame_mount_out_\{i}",
      x=frame_bolt_circle_mm / 2.0 * @math.cos(theta),
      y=frame_bolt_circle_mm / 2.0 * @math.sin(theta),
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
  // ---------------------------------------------------------------------
  // Casing joint and cap screws, and their heat-set inserts.
  // ---------------------------------------------------------------------
  if heat_set_inserts {
    for k in 0..<stage_count {
      let idx = k + 1
      for i in 0..<6 {
        casing = casing.attach(
          "\{name}_stage\{idx}_top_insert_merge_\{i}",
          parent_mate="\{name}_stage\{idx}_top_bolt_\{i}",
          heat_set_insert(
            name="\{name}_stage\{idx}_top_insert_\{i}",
            outer_diam_mm=4.5,
            inner_diam_mm=3.0,
            length_mm=6.0,
          ),
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
      }
    }
    // Stage 1 bottom flange receives the motor-cap screws.
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      casing = casing
        .add_mate_mm_deg(
          "\{name}_stage1_bottom_insert_\{i}",
          x=casing_bolt_radius * @math.cos(theta),
          y=casing_bolt_radius * @math.sin(theta),
          z=-flange_thickness_mm,
        )
        .attach(
          "\{name}_stage1_bottom_insert_merge_\{i}",
          parent_mate="\{name}_stage1_bottom_insert_\{i}",
          heat_set_insert(
            name="\{name}_stage1_bottom_insert_\{i}",
            outer_diam_mm=4.5,
            inner_diam_mm=3.0,
            length_mm=6.0,
          ),
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
  }
  // Motor cap screws: heads at the cap's lower face, shanks up into inserts.
  for i in 0..<6 {
    let theta = 2.0 * @math.PI * i.to_double() / 6.0
    let bx = casing_bolt_radius * @math.cos(theta)
    let by = casing_bolt_radius * @math.sin(theta)
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
        iso_shcs_screw(
          name="\{name}_motor_cap_screw_\{i}",
          size=@step_standards.M3,
          length_mm=standard_shcs_len(motor_cap_thickness + 6.0),
          detail~,
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  // Stage-to-stage screws: heads on the upper bottom flange, shanks down into
  // the lower top-flange inserts.
  for k in 1..<stage_count {
    let idx = k + 1
    let info = finalized[k]
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      let bx = casing_bolt_radius * @math.cos(theta)
      let by = casing_bolt_radius * @math.sin(theta)
      casing = casing
        .add_mate_mm_deg(
          "\{name}_stage\{idx}_joint_bolt_\{i}",
          x=bx,
          y=by,
          z=info.z0,
        )
        .attach(
          "\{name}_stage\{idx}_joint_screw_merge_\{i}",
          parent_mate="\{name}_stage\{idx}_joint_bolt_\{i}",
          iso_shcs_screw(
            name="\{name}_stage\{idx}_joint_screw_\{i}",
            size=@step_standards.M3,
            length_mm=standard_shcs_len(flange_thickness_mm + 6.0),
            detail~,
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
  }
  // Output cap screws: heads on the cap top, shanks down into the final top
  // flange inserts.
  for i in 0..<6 {
    let theta = 2.0 * @math.PI * i.to_double() / 6.0
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
        iso_shcs_screw(
          name="\{name}_output_cap_screw_\{i}",
          size=@step_standards.M3,
          length_mm=standard_shcs_len(output_cap_thickness + 6.0),
          detail~,
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  // ---------------------------------------------------------------------
  // Rotating output interface: flange hub plus a clamp collar.
  // ---------------------------------------------------------------------
  if output_hub {
    let hub_part = fabricated_part(
      "MG-OUTPUT-HUB", "Printed output flange hub with a 40 mm bolt circle for wheels, knees, hips, and other driven links, plus an optional three-hole tire-mount interface with heat-set inserts; retained by the shaft collar",
      "carbon fiber nylon", "3D print", 8.0,
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
      .add_body(
        actuator_plate_body(
          name + "_output_hub_body",
          output_hub_diam_mm,
          output_hub_thickness_mm,
          0.0,
          hub_holes,
          @urdf.Density::carbon_fiber(),
          @step_cad.Rgb::orange(),
          detail,
        ).with_part(hub_part),
      )
      .add_mate_mm_deg("back")
      .add_mate_mm_deg("output_face", z=output_hub_thickness_mm)
      .add_mate_mm_deg(
        "tire_mount",
        z=output_hub_thickness_mm + output_collar_width_mm,
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
    casing = casing.attach_to(
      motorized_last_carrier_name(name, stage_count),
      name + "_output_hub_joint",
      parent_mate="output_hub_seat",
      hub,
      child_mate="back",
      spec=@cad.JointSpec::merge_rigid(),
    )
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
    driver="VESC / SimpleFOC",
    interface="CAN",
    encoder="rotor encoder (AS5600 / AS5047P-class)",
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
