///|
/// Actuated components: stepper motors, quasi-direct-drive pods, and hub
/// motors. Each actuator is a two-link `@cad.Component` tree whose rotor is
/// connected to the stator by a joint with an optional transmission.
///
/// At `Detailed` and above, shafts come from the STEP motion primitives, and
/// real bearings and mounting screws are merged into the stator.

///|
/// Builds a NEMA stepper motor from the Tier-1 envelope: a square body with
/// four mounting holes, a front pilot boss, and a rotor shaft.
///
/// `designation` selects a standard frame (NEMA17/NEMA23); the explicit
/// dimensions build a non-standard envelope under the same interface.
pub fn nema_stepper(
  name~ : String = "nema17",
  frame_size_mm~ : Double = 42.3,
  body_length_mm~ : Double = 40.0,
  boss_diam_mm~ : Double = 22.0,
  boss_height_mm~ : Double = 2.0,
  shaft_diam_mm~ : Double = 5.0,
  shaft_length_mm~ : Double = 24.0,
  max_effort_nm~ : Double = 0.45,
  max_vel_rad_s~ : Double = 30.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
  designation~ : String = "",
  mount_plate~ : Bool = false,
) -> @cad.Component {
  let _ = threads
  let frame = if designation != "" {
    expect_step("NEMA frame", @step_motors.nema_frame(designation))
  } else {
    {
      designation: "NEMA-\{frame_size_mm}",
      frame_mm: frame_size_mm,
      bolt_spacing_mm: frame_size_mm * 0.73,
      mounting_hole_diameter_mm: 3.384,
      pilot_diameter_mm: boss_diam_mm,
      pilot_length_mm: boss_height_mm,
      shaft_diameter_mm: shaft_diam_mm,
      default_shaft_length_mm: shaft_length_mm,
    }
  }
  let step_comp = expect_step(
    "NEMA stepper motor",
    @step_motors.nema_stepper_motor(
      frame,
      body_length_mm,
      shaft_length_mm~,
      shaft_diameter_mm=shaft_diam_mm,
      pilot_diameter_mm=boss_diam_mm,
      pilot_length_mm=boss_height_mm,
      detail~,
    ),
  )
  let stator_name = name + "_stator"
  let rotor_name = name + "_rotor"
  let part = purchased_part(
    "NEMA-\{frame.designation}",
    "NEMA stepper \{frame.designation}",
    "mixed",
    12.0,
    supplier_url="https://www.omc-stepperonline.com/",
  )
  let mut stator = @cad.Component::from_step_layer(
    stator_name,
    step_comp,
    "body",
    density=@urdf.Density::steel_mild(),
    part=Some(part),
  )
  let pilot = @cad.Component::from_step_layer(
    stator_name + "_pilot",
    step_comp,
    "pilot-boss",
    density=@urdf.Density::aluminum_6061(),
  )
  stator = stator
    .add_bodies(pilot.bodies)
    .add_mate_mm_deg("face_mount", z=body_length_mm)
    .add_mate_mm_deg("rear_mount")
    .add_mate_mm_deg("shaft_base", z=body_length_mm + boss_height_mm)
  let half_spacing = frame.bolt_spacing_mm / 2.0
  for i in 0..<4 {
    let sx = if i == 0 || i == 3 { half_spacing } else { -half_spacing }
    let sy = if i == 1 || i == 3 { half_spacing } else { -half_spacing }
    stator = stator.add_mate_mm_deg(
      "mount_hole_\{i}",
      x=sx,
      y=sy,
      z=body_length_mm,
    )
  }
  let rotor = if detail_is_rich(detail) {
    let keyed = expect_step(
      "keyed shaft",
      @step_motion.keyed_shaft(
        shaft_diam_mm,
        shaft_length_mm,
        shaft_diam_mm * 0.3,
        shaft_diam_mm * 0.15,
        segments=@step_common.DetailPolicy::for_level(detail).circle_segments,
      ),
    )
    @cad.Component::new(rotor_name, description="NEMA stepper rotor")
    .with_param("shaft_diam_mm", shaft_diam_mm.to_string())
    .with_param("shaft_length_mm", shaft_length_mm.to_string())
    .add_bodies(
      @cad.BodyPart::from_step_component(
        keyed,
        density=@urdf.Density::steel_mild(),
        z_mm=-shaft_length_mm / 2.0,
      ),
    )
    .add_mate_mm_deg("base", z=-shaft_length_mm / 2.0)
    .add_mate_mm_deg("shaft_tip", z=shaft_length_mm / 2.0)
  } else {
    let shaft = @cad.Component::from_step_layer(
      rotor_name,
      step_comp,
      "shaft",
      density=@urdf.Density::steel_mild(),
      apply_placement=false,
    )
    let centered = shaft.bodies.map(fn(body) {
      body.transform_by(
        @cad.urdf_transform_from_mm_deg(z_mm=-shaft_length_mm / 2.0),
      )
    })
    { ..shaft, bodies: centered, }
    .add_mate_mm_deg("base", z=-shaft_length_mm / 2.0)
    .add_mate_mm_deg("shaft_tip", z=shaft_length_mm / 2.0)
  }
  if mount_plate {
    let plate = if designation != "" {
      nema_mount_plate_part(
        name=name + "_mount_plate",
        designation=frame.designation,
        width_mm=frame.frame_mm * 1.6,
        height_mm=frame.frame_mm * 1.6,
        thickness_mm=5.0,
        detail~,
      )
    } else {
      stock_plate_part(
        name=name + "_mount_plate",
        width_mm=frame.frame_mm * 1.6,
        height_mm=frame.frame_mm * 1.6,
        thickness_mm=5.0,
        detail~,
      )
    }
    stator = stator.attach(
      "mount_plate_merge",
      parent_mate="face_mount",
      plate,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Stepper,
    model="NEMA " + frame.designation,
    voltage_v=24.0,
    current_rated_a=1.5,
    current_stall_a=1.9,
    torque_rated_nm=max_effort_nm,
    driver="A4988",
    interface="STEP/DIR",
    encoder="none",
  )
  let m4_mount = frame.mounting_hole_diameter_mm > 3.5
  let mount_thread = if m4_mount { "M4" } else { "M3" }
  let mount_length = if m4_mount { 12.0 } else { 10.0 }
  let mount_part = purchased_part(
    if m4_mount {
      "ISO4762-M4x12"
    } else {
      "ISO4762-M3x10"
    },
    if m4_mount {
      "ISO 4762 socket head cap screw M4 x 12 mm"
    } else {
      "ISO 4762 socket head cap screw M3 x 10 mm"
    },
    "steel",
    if m4_mount {
      0.50
    } else {
      0.35
    },
  )
  stator
  .with_actuator(spec)
  .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V, 1.5 A"))
  .add_port(
    @cad.Port::new("step_dir", @cad.PortKind::Signal, spec="TTL STEP/DIR"),
  )
  .add_port(@cad.Port::new("enable", @cad.PortKind::Signal, spec="TTL"))
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  .attach(
    "\{name}_shaft_joint",
    parent_mate="shaft_base",
    rotor,
    child_mate="base",
    spec=@cad.JointSpec::continuous(
      limit=Some(
        @urdf.JointLimit::new(effort=max_effort_nm, velocity=max_vel_rad_s),
      ),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
      transmission_reduction=Some(1.0),
    ),
    bom_external=false,
  )
  .add_fastener(
    @cad.Fastener::new(
      "motor_mount_screws",
      @cad.FastenerKind::Screw,
      thread=mount_thread,
      length_mm=mount_length,
      engagement_mm=4.0,
      quantity=4,
      torque_nm=if m4_mount { 2.0 } else { 0.8 },
      references=[stator_name],
      part=Some(mount_part),
    ),
  )
  .with_part(part)
}

///|
/// shaft_diameter_mm)` for a NEMA frame designation.
pub fn nema_frame_dims(
  designation : String,
) -> (Double, Double, Double, Double) {
  match @step_motors.nema_frame(designation) {
    Ok(frame) =>
      (
        frame.pilot_diameter_mm,
        frame.bolt_spacing_mm,
        frame.mounting_hole_diameter_mm,
        frame.shaft_diameter_mm,
      )
    Err(_) => abort("unknown NEMA frame '\{designation}'")
  }
}

///|
/// Builds a quasi-direct-drive (QDD) robotic joint module with a housing, a
/// mounting flange, an internal bearing, and a rotating output horn.
pub fn qdd_actuator_pod(
  name~ : String = "actuator_pod",
  housing_diam_mm~ : Double = 96.0,
  housing_length_mm~ : Double = 54.0,
  output_diam_mm~ : Double = 56.0,
  output_thickness_mm~ : Double = 8.0,
  reduction~ : Double = 6.0,
  lower_rad~ : Double = -3.14159,
  upper_rad~ : Double = 3.14159,
  max_effort_nm~ : Double = 45.0,
  max_vel_rad_s~ : Double = 21.0,
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let rotor_name = name + "_rotor"
  let flange_thickness = 5.0
  let mut stator = @cad.Component::new(name, description="QDD actuator stator")
    .with_param("housing_diam_mm", housing_diam_mm.to_string())
    .with_param("housing_length_mm", housing_length_mm.to_string())
    .with_param("reduction", reduction.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_housing",
        housing_diam_mm,
        housing_length_mm,
        density=@urdf.Density::aluminum_6061(),
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_flange",
        housing_diam_mm * 1.18,
        housing_diam_mm * 0.95,
        flange_thickness,
        z_mm=-housing_length_mm / 2.0 + flange_thickness / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color~,
      ),
    )
    .add_mate_mm_deg("rear_mount", z=-housing_length_mm / 2.0)
    .add_mate_mm_deg("side_mount", x=housing_diam_mm / 2.0, ry_deg=90.0)
    .add_mate_mm_deg("bearing_seat", z=housing_length_mm / 2.0)
  if detail_is_rich(detail) {
    // A radial bearing sits in the output seat.
    let bearing = ball_bearing(
      name="\{name}_bearing",
      designation="6002",
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    stator = stator.attach(
      "bearing_merge",
      parent_mate="bearing_seat",
      bearing,
      child_mate="top",
      spec=@cad.JointSpec::merge_rigid(),
    )
    // Six flange screws around the bolt circle.
    let bolt_radius = housing_diam_mm * 0.5
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      let x = bolt_radius * @math.cos(theta)
      let y = bolt_radius * @math.sin(theta)
      stator = stator
        .add_mate_mm_deg("flange_hole_\{i}", x~, y~, z=-housing_length_mm / 2.0)
        .attach(
          "flange_screw_\{i}",
          parent_mate="flange_hole_\{i}",
          iso_shcs_screw(
            name="flange_screw_\{i}",
            size=@step_standards.M3,
            length_mm=10.0,
            detail~,
            threads?,
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
  }
  let rotor = @cad.Component::new(rotor_name, description="QDD actuator rotor")
    .with_param("output_diam_mm", output_diam_mm.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        rotor_name + "_horn",
        output_diam_mm,
        output_thickness_mm,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_mate_mm_deg("base", z=-output_thickness_mm / 2.0)
    .add_mate_mm_deg("output_flange", z=output_thickness_mm / 2.0)
  let part = purchased_part(
    "QDD-\{housing_diam_mm}",
    "QDD actuator pod \{housing_diam_mm} mm",
    "mixed",
    120.0,
    supplier_url="https://www.odriverobotics.com/",
  )
  let spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Bldc,
    model="QDD " + housing_diam_mm.to_string(),
    voltage_v=48.0,
    current_rated_a=8.0,
    current_stall_a=20.0,
    torque_rated_nm=max_effort_nm,
    driver="ODrive",
    interface="CAN",
    encoder="magnetic 14-bit",
  )
  stator
  .with_actuator(spec)
  .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="48 V, 8 A"))
  .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B, 1 Mbps"))
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  .attach(
    "\{name}_joint",
    parent_mate="bearing_seat",
    rotor,
    child_mate="base",
    spec=@cad.JointSpec::revolute(
      @urdf.JointLimit::new(
        lower=Some(lower_rad),
        upper=Some(upper_rad),
        effort=max_effort_nm,
        velocity=max_vel_rad_s,
      ),
      offset_mm=output_thickness_mm / 2.0,
      dynamics=Some(@urdf.JointDynamics::new(damping=0.4, friction=0.08)),
      transmission_reduction=Some(reduction),
    ),
    bom_external=false,
  )
  .with_part(part)
}

///|
/// Builds a hub-motor wheel: a stator axle hub, two hub bearings, and a
/// rotating aluminum rim with a TPU tire.
pub fn hub_motor_assembly(
  name~ : String = "hub_motor",
  stator_diam_mm~ : Double = 70.0,
  stator_width_mm~ : Double = 36.0,
  tire_diam_mm~ : Double = 140.0,
  tire_width_mm~ : Double = 46.0,
  max_effort_nm~ : Double = 18.0,
  max_vel_rad_s~ : Double = 30.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let wheel_name = name + "_wheel"
  let rim_diam = tire_diam_mm * 0.65
  let mut hub = @cad.Component::new(name, description="Hub motor stator")
    .with_param("stator_diam_mm", stator_diam_mm.to_string())
    .with_param("stator_width_mm", stator_width_mm.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_hub",
        stator_diam_mm,
        stator_width_mm,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_mate_mm_deg("axle")
    .add_mate_mm_deg("mount", z=-stator_width_mm / 2.0)
  if detail_is_rich(detail) {
    let axle = expect_step(
      "hub axle shaft",
      @step_motion.shaft(
        stator_diam_mm * 0.3,
        stator_width_mm * 1.25,
        color=@step_cad.Rgb::grey(),
      ),
    )
    hub = hub.add_bodies(
      @cad.BodyPart::from_step_component(
        axle,
        density=@urdf.Density::steel_mild(),
        z_mm=-stator_width_mm * 0.625,
      ),
    )
    let bearing = ball_bearing(
      name="\{name}_bearing",
      designation="6001",
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    hub = hub.attach(
      "bearing_merge",
      parent_mate="axle",
      bearing,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let wheel = @cad.Component::new(wheel_name, description="Hub motor wheel")
    .with_param("tire_diam_mm", tire_diam_mm.to_string())
    .with_param("tire_width_mm", tire_width_mm.to_string())
    .add_body(
      @cad.BodyPart::tube_mm(
        wheel_name + "_rim",
        rim_diam,
        stator_diam_mm + 2.0,
        tire_width_mm,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        wheel_name + "_tire",
        tire_diam_mm,
        rim_diam,
        tire_width_mm,
        density=@urdf.Density::tpu(),
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_mate_mm_deg("spin")
    .add_mate_mm_deg("outer_face", z=tire_width_mm / 2.0)
  let part = purchased_part(
    "HUB-\{tire_diam_mm}",
    "Hub motor wheel \{tire_diam_mm} mm",
    "mixed",
    85.0,
    supplier_url="https://www.alibaba.com/",
  )
  let spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Hub,
    model="HUB " + tire_diam_mm.to_string(),
    voltage_v=36.0,
    current_rated_a=10.0,
    current_stall_a=25.0,
    torque_rated_nm=max_effort_nm,
    driver="integrated",
    interface="CAN",
    encoder="hall",
  )
  hub
  .with_actuator(spec)
  .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="36 V, 10 A"))
  .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B, 1 Mbps"))
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  .attach(
    "\{name}_spin_joint",
    parent_mate="axle",
    wheel,
    child_mate="spin",
    spec=@cad.JointSpec::continuous(
      limit=Some(
        @urdf.JointLimit::new(effort=max_effort_nm, velocity=max_vel_rad_s),
      ),
      transmission_reduction=Some(1.0),
    ),
    bom_external=false,
  )
  .with_part(part)
}

///|
/// A named low-KV brushless outrunner / gimbal motor preset.
///
/// These are inexpensive hobby/robotics motors (roughly \$15–\$40) with a high
/// pole count and smooth low-speed torque, well matched to a printed planetary
/// reduction.
pub(all) struct BldcPreset {
  name : String
  diameter_mm : Double
  body_length_mm : Double
  kv : Double
  pole_pairs : Int32
  voltage_v : Double
  current_rated_a : Double
  current_peak_a : Double
  shaft_diameter_mm : Double
  shaft_length_mm : Double
  mass_g : Double
  cost_usd : Double
  bolt_circle_mm : Double
  mount_hole_mm : Double
  bearing_designation : String
}

///|
/// Resolves a low-KV BLDC preset by name.
///
/// Unknown names return `None`; callers report the valid options.
pub fn bldc_preset(name : String) -> BldcPreset? {
  match name {
    "5010_360kv" =>
      Some({
        name: "5010_360kv",
        diameter_mm: 50.0,
        body_length_mm: 20.0,
        kv: 360.0,
        pole_pairs: 12,
        voltage_v: 24.0,
        current_rated_a: 15.0,
        current_peak_a: 20.0,
        shaft_diameter_mm: 4.0,
        shaft_length_mm: 20.0,
        mass_g: 80.0,
        cost_usd: 16.0,
        bolt_circle_mm: 19.0,
        mount_hole_mm: 3.2,
        bearing_designation: "624",
      })
    "5008_335kv" =>
      Some({
        name: "5008_335kv",
        diameter_mm: 52.0,
        body_length_mm: 25.0,
        kv: 335.0,
        pole_pairs: 12,
        voltage_v: 24.0,
        current_rated_a: 12.0,
        current_peak_a: 18.0,
        shaft_diameter_mm: 4.0,
        shaft_length_mm: 20.0,
        mass_g: 100.0,
        cost_usd: 18.0,
        bolt_circle_mm: 19.0,
        mount_hole_mm: 3.2,
        bearing_designation: "624",
      })
    "5208_180kv" =>
      Some({
        name: "5208_180kv",
        diameter_mm: 52.0,
        body_length_mm: 28.0,
        kv: 180.0,
        pole_pairs: 12,
        voltage_v: 24.0,
        current_rated_a: 12.0,
        current_peak_a: 18.0,
        shaft_diameter_mm: 6.0,
        shaft_length_mm: 22.0,
        mass_g: 110.0,
        cost_usd: 22.0,
        bolt_circle_mm: 25.0,
        mount_hole_mm: 3.2,
        bearing_designation: "626",
      })
    "5065_270kv" =>
      Some({
        name: "5065_270kv",
        diameter_mm: 50.0,
        body_length_mm: 65.0,
        kv: 270.0,
        pole_pairs: 12,
        voltage_v: 36.0,
        current_rated_a: 35.0,
        current_peak_a: 45.0,
        shaft_diameter_mm: 8.0,
        shaft_length_mm: 25.0,
        mass_g: 420.0,
        cost_usd: 32.0,
        bolt_circle_mm: 25.0,
        mount_hole_mm: 3.2,
        bearing_designation: "688",
      })
    "6354_190kv" =>
      Some({
        name: "6354_190kv",
        diameter_mm: 63.0,
        body_length_mm: 54.0,
        kv: 190.0,
        pole_pairs: 14,
        voltage_v: 36.0,
        current_rated_a: 45.0,
        current_peak_a: 55.0,
        shaft_diameter_mm: 10.0,
        shaft_length_mm: 30.0,
        mass_g: 580.0,
        cost_usd: 38.0,
        bolt_circle_mm: 30.0,
        mount_hole_mm: 4.2,
        bearing_designation: "6000",
      })
    "a12_8318_100kv" | "a12" =>
      Some({
        name: "A12-8318-100KV",
        diameter_mm: 91.0,
        body_length_mm: 32.0,
        kv: 100.0,
        pole_pairs: 21,
        voltage_v: 48.0,
        current_rated_a: 60.0,
        current_peak_a: 120.0,
        shaft_diameter_mm: 12.0,
        shaft_length_mm: 0.0,
        mass_g: 510.0,
        cost_usd: 159.0,
        bolt_circle_mm: 32.0,
        mount_hole_mm: 4.5,
        bearing_designation: "6901",
      })
    _ => None
  }
}

///|
/// The names of every built-in low-KV BLDC preset.
pub fn bldc_preset_names() -> Array[String] {
  ["5010_360kv", "5008_335kv", "5208_180kv", "5065_270kv", "6354_190kv"]
}

///|
/// Torque constant `Kt = 8.27 / KV` in N·m per amp.
pub fn bldc_torque_constant(preset : BldcPreset) -> Double {
  8.27 / preset.kv
}

///|
/// The motor's rated torque at its rated current, in N·m.
pub fn bldc_rated_torque(preset : BldcPreset) -> Double {
  bldc_torque_constant(preset) * preset.current_rated_a
}

///|
fn resolve_bldc_preset(preset : String) -> BldcPreset {
  match bldc_preset(preset) {
    Some(p) => p
    None =>
      abort(
        "unknown BLDC preset '\{preset}'; choose one of " +
        bldc_preset_names().join(", "),
      )
  }
}

///|
/// Builds an inexpensive low-KV brushless outrunner / gimbal motor.
///
/// The stator link carries the aluminum rear endbell, stator stack, mounting
/// flange, sensor/encoder boss, and phase-lead ports. The rotor link carries
/// the out-runner bell, flux ring, and output shaft through front and rear
/// bearings, rotating on a continuous `<name>_rotor_joint` along `+Z`. The
/// motor frame puts its mounting face at `z = 0`, the body behind it (`-Z`),
/// and the output shaft in front (`+Z`).
pub fn low_kv_bldc_motor(
  name~ : String = "bldc_motor",
  preset~ : String = "5010_360kv",
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  joint_name~ : String = "",
) -> @cad.Component {
  let p = resolve_bldc_preset(preset)
  let stator_name = name + "_stator"
  let rotor_name = name + "_rotor"
  let rotor_joint = if joint_name == "" {
    name + "_rotor_joint"
  } else {
    joint_name
  }
  let bell_wall = 2.5
  let endbell_thickness = 4.0
  let stack_outer = p.diameter_mm * 0.72
  let stack_inner = p.diameter_mm * 0.42
  let stator_part = purchased_part(
    "BLDC-\{p.name}",
    "Low-KV brushless outrunner \{p.name} (\{p.kv} KV)",
    "mixed",
    p.cost_usd,
    supplier_url="https://www.hobbyking.com/",
  )
  let mut stator = @cad.Component::new(
      stator_name,
      description="Low-KV BLDC stator",
    )
    .with_param("preset", p.name)
    .with_param("kv", p.kv.to_string())
    .with_param("pole_pairs", p.pole_pairs.to_string())
    .with_param("voltage_v", p.voltage_v.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        stator_name + "_endbell",
        p.diameter_mm * 0.88,
        endbell_thickness,
        z_mm=-endbell_thickness / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::black(),
      ).with_part(stator_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        stator_name + "_stack",
        stack_outer,
        stack_inner,
        p.body_length_mm - 2.0 * endbell_thickness,
        z_mm=-p.body_length_mm / 2.0,
        density=@urdf.Density::kg_per_m3(7600.0),
        color=@step_cad.Rgb::orange(),
      ).with_part(stator_part),
    )
    .add_mate_mm_deg("mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("front_face")
    .add_mate_mm_deg("rear", z=-p.body_length_mm)
    .add_mate_mm_deg("sensor_boss", z=-p.body_length_mm, axis=(0.0, 0.0, -1.0))
    .add_port(
      @cad.Port::new(
        "power",
        @cad.PortKind::Power,
        spec=p.voltage_v.to_string() +
          " V, " +
          p.current_rated_a.to_string() +
          " A",
      ),
    )
    .add_port(@cad.Port::new("phases", @cad.PortKind::Power, spec="3-phase"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  // Rear endbell disc, sensor/encoder boss, and mounting bolt circle.
  stator = stator
    .add_body(
      @cad.BodyPart::cylinder_mm(
        stator_name + "_rear_endbell",
        p.diameter_mm * 0.88,
        endbell_thickness,
        z_mm=-p.body_length_mm + endbell_thickness / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::black(),
      ).with_part(stator_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        stator_name + "_sensor_boss",
        12.0,
        10.0,
        4.0,
        z_mm=-p.body_length_mm - 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(stator_part),
    )
    // An on-axis rotor sensor board (for example a moteus C1 r1.2) attaches
    // here, behind the rear endbell, facing the magnet on the back of the
    // rotor across a 2 mm air gap. The board measures the speed of the rotor
    // — and with it the input shaft it drives 1:1.
    .add_mate_mm_deg(
      "encoder_mount",
      z=-p.body_length_mm - 6.7,
      axis=(0.0, 0.0, 1.0),
    )
  let bolt_radius = p.bolt_circle_mm / 2.0
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * i.to_double() / 4.0
    stator = stator.add_mate_mm_deg(
      "mount_hole_\{i}",
      x=bolt_radius * @math.cos(theta),
      y=bolt_radius * @math.sin(theta),
      z=-endbell_thickness,
      axis=(0.0, 0.0, -1.0),
    )
  }
  if detail_is_rich(detail) {
    // Rear endbell ventilation slots: six nominal louvres between radial
    // spokes. They are separate bodies, not a boolean cut, so the printed
    // envelope keeps its exact analytic surfaces.
    let vent_radius = p.diameter_mm * 0.30
    for i in 0..<6 {
      let theta = 2.0 * @math.PI * i.to_double() / 6.0
      stator = stator.add_body(
        @cad.BodyPart::box_mm(
          "\{stator_name}_vent_\{i}",
          2.5,
          6.0,
          1.2,
          x_mm=vent_radius * @math.cos(theta),
          y_mm=vent_radius * @math.sin(theta),
          z_mm=-p.body_length_mm + endbell_thickness / 2.0,
          rz_deg=theta * 180.0 / @math.PI,
          density=@urdf.Density::aluminum_6061(),
          color=@step_cad.Rgb::grey(),
        ).with_part(stator_part),
      )
    }
    // Three phase leads exit the rear endbell and are dressed straight into
    // the rear-mounted controller board (they end just above it).
    let lead_radius = p.diameter_mm * 0.42
    for i in 0..<3 {
      let theta = (30.0 + 120.0 * i.to_double()) * @math.PI / 180.0
      stator = stator.add_body(
        @cad.BodyPart::cylinder_mm(
          "\{stator_name}_phase_lead_\{i}",
          2.0,
          4.0,
          x_mm=lead_radius * @math.cos(theta),
          y_mm=lead_radius * @math.sin(theta),
          z_mm=-p.body_length_mm - 2.0,
          density=@urdf.Density::kg_per_m3(1200.0),
          color=@step_cad.Rgb::red(),
        ).with_part(stator_part),
      )
    }
    stator = stator.add_body(
      @cad.BodyPart::box_mm(
        stator_name + "_connector_stub",
        10.0,
        8.0,
        6.0,
        x_mm=lead_radius,
        z_mm=-p.body_length_mm - 3.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::black(),
      ).with_part(stator_part),
    )
    // Front and rear bearings share the rotor shaft. The preset's bearing bore
    // matches the shaft diameter.
    stator = stator.add_mate_mm_deg(
      "rear_bearing_seat",
      z=-p.body_length_mm + 4.0,
    )
    let front_bearing = ball_bearing(
      name="\{stator_name}_bearing_front",
      designation=p.bearing_designation,
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    let rear_bearing = ball_bearing(
      name="\{stator_name}_bearing_rear",
      designation=p.bearing_designation,
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    stator = stator
      .attach(
        "bearing_front_merge",
        parent_mate="front_face",
        front_bearing,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(),
        bom_external=false,
      )
      .attach(
        "bearing_rear_merge",
        parent_mate="rear_bearing_seat",
        rear_bearing,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(),
        bom_external=false,
      )
  }
  let rotor_part = purchased_part(
    "BLDC-ROTOR-\{p.name}",
    "Low-KV BLDC rotor \{p.name}",
    "mixed",
    0.0,
  )
  // The diametric sense magnet on the shaft end is what the rotor encoder
  // actually reads; it is a separate purchase, not part of the motor.
  let magnet_part = purchased_part(
    "MAG-8x2-DIA",
    "Diametrically magnetized NdFeB disc, 8 x 2 mm; bonds to the rotor shaft end behind the rear endbell",
    "NdFeB",
    2.0,
    supplier_url="https://mjbots.com/products/diametric-disc-magnet",
  )
  let shaft_total_len = p.body_length_mm + p.shaft_length_mm
  let mut rotor = @cad.Component::new(
      rotor_name,
      description="Low-KV BLDC rotor",
    )
    .with_param("shaft_diameter_mm", p.shaft_diameter_mm.to_string())
    .with_param("shaft_length_mm", p.shaft_length_mm.to_string())
  if detail_is_rich(detail) {
    // A keyed shaft transmits torque to the sun clamp hub without relying on
    // clamp friction alone. It runs through both motor bearings.
    let keyed = expect_step(
      "keyed BLDC shaft",
      @step_motion.keyed_shaft(
        p.shaft_diameter_mm,
        shaft_total_len,
        p.shaft_diameter_mm * 0.22,
        p.shaft_diameter_mm * 0.12,
        segments=@step_common.DetailPolicy::for_level(detail).circle_segments,
      ),
    )
    rotor = rotor.add_bodies(
      @cad.BodyPart::from_step_component(
        keyed,
        density=@urdf.Density::steel_mild(),
        z_mm=-p.body_length_mm,
      ).map(fn(body) { body.with_part(rotor_part) }),
    )
  } else {
    rotor = rotor.add_body(
      @cad.BodyPart::cylinder_mm(
        rotor_name + "_shaft",
        p.shaft_diameter_mm,
        shaft_total_len,
        z_mm=(p.shaft_length_mm - p.body_length_mm) / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(rotor_part),
    )
  }
  if detail_is_rich(detail) {
    let bell_inner = p.diameter_mm - 2.0 * bell_wall
    rotor = rotor
      .add_body(
        @cad.BodyPart::tube_mm(
          rotor_name + "_bell",
          p.diameter_mm,
          bell_inner,
          p.body_length_mm - 8.0,
          z_mm=-p.body_length_mm / 2.0 - 2.0,
          density=@urdf.Density::aluminum_6061(),
          color=@step_cad.Rgb::black(),
        ).with_part(rotor_part),
      )
      // An explicit steel flux ring lines the bell skirt.
      .add_body(
        @cad.BodyPart::tube_mm(
          rotor_name + "_flux_ring",
          bell_inner - 0.4,
          bell_inner - 1.4,
          p.body_length_mm - 9.0,
          z_mm=-p.body_length_mm / 2.0 - 2.0,
          density=@urdf.Density::steel_mild(),
          color=@step_cad.Rgb::grey(),
        ).with_part(rotor_part),
      )
  }
  // The rotor sensor magnet is not optional: the rotor position sensor
  // (a rear-mounted AS5047P such as the moteus C1) reads the rotor through
  // it, in every detail level. It is a separate purchase, so it rides on
  // its own component with an external attachment and lands on the BOM.
  let rotor_magnet = @cad.Component::new(
      rotor_name + "_sensor_magnet",
      description="Diametric sense magnet bonded to the rotor shaft end; read by the rear-mounted AS5047P",
    )
    .with_part(magnet_part)
    .add_body(
      @cad.BodyPart::cylinder_mm(
        rotor_name + "_sensor_magnet_body",
        8.0,
        2.0,
        z_mm=0.0,
        density=@urdf.Density::kg_per_m3(5000.0),
        color=@step_cad.Rgb::purple(),
      ).with_part(magnet_part),
    )
    .add_mate_mm_deg("mount")
  rotor = rotor
    .add_mate_mm_deg("magnet_seat", z=-p.body_length_mm - 1.0)
    .attach(
      "rotor_magnet_merge",
      parent_mate="magnet_seat",
      rotor_magnet,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  rotor = rotor
    .add_mate_mm_deg("base")
    .add_mate_mm_deg("shaft", z=p.shaft_length_mm)
  let spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Bldc,
    model="BLDC " + p.name,
    voltage_v=p.voltage_v,
    current_rated_a=p.current_rated_a,
    current_stall_a=p.current_peak_a,
    torque_rated_nm=bldc_rated_torque(p),
    driver="SimpleFOC",
    interface="CAN",
    encoder="AS5047P on the rotor (rear magnet) via a controller such as a moteus C1",
  )
  stator
  .with_param("phase_resistance_ohm", (0.18 * 360.0 / p.kv).to_string())
  .with_param("thermal_resistance_c_per_w", "2.5")
  .with_param("rated_current_a", p.current_rated_a.to_string())
  .with_param("peak_current_a", p.current_peak_a.to_string())
  .with_param("poles", (p.pole_pairs * 2).to_string())
  .with_param(
    "rotor_encoder", "AS5047P on the rotor magnet (e.g. via a moteus C1), on-axis, ~2 mm gap",
  )
  .with_param("rotor_encoder_air_gap_mm", "2.0")
  .with_actuator(spec)
  .with_part(stator_part)
  .attach(
    rotor_joint,
    parent_mate="front_face",
    rotor,
    child_mate="base",
    spec=@cad.JointSpec::continuous(
      limit=Some(
        @urdf.JointLimit::new(
          effort=bldc_rated_torque(p) * 4.0,
          velocity=p.kv * 0.1,
        ),
      ),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.01, friction=0.005)),
      transmission_reduction=Some(1.0),
    ),
    bom_external=false,
  )
}

///|
/// Recursively retargets a named joint's mimic to another joint.
pub fn set_joint_mimic(
  comp : @cad.Component,
  joint_name : String,
  mimic : @urdf.JointMimic,
) -> Unit {
  for i in 0..<comp.attachments.length() {
    let att = comp.attachments[i]
    if att.joint_name == joint_name {
      comp.attachments[i] = {
        ..att,
        spec: { ..att.spec, mimic: Some(mimic), },
      }
    }
    set_joint_mimic(att.child, joint_name, mimic)
  }
}

///|
/// The ideal reduction of a planetary stage with a fixed ring, a sun input, and
/// a carrier output: `1 + ring_teeth / sun_teeth`.
pub fn planetary_reduction(
  sun_teeth : Int32,
  planet_teeth : Int32,
  stages : Int32,
) -> Double {
  let per_stage = 1.0 +
    (sun_teeth.to_double() + 2.0 * planet_teeth.to_double()) /
    sun_teeth.to_double()
  let count = if stages < 1 { 1 } else { stages }
  if count == 1 {
    per_stage
  } else {
    per_stage * per_stage
  }
}

///|
/// Builds a circular plate body with arbitrary bolt holes.
///
/// `holes` are `(x_mm, y_mm, diameter_mm)` in the plate's local frame.
fn actuator_plate_body(
  name : String,
  outer_diam_mm : Double,
  thickness_mm : Double,
  z0_mm : Double,
  holes : Array[(Double, Double, Double)],
  density : @urdf.Density,
  color : @step_cad.Rgb,
  detail : @step_common.DetailLevel,
) -> @cad.BodyPart {
  let _ = detail
  // Exact quarter-arc loops: the rim and every bolt hole are true cylindrical
  // surfaces, not a 64-sided polygon.
  let outer = @step_gears.arc_circle_segments(outer_diam_mm)
  let hole_profiles : Array[Array[@step_cad.ProfileSegment]] = []
  for hole in holes {
    hole_profiles.push(
      arc_segments_at(@step_gears.arc_circle_segments(hole.2), hole.0, hole.1),
    )
  }
  arc_profile_body(
    name, outer, thickness_mm, hole_profiles, density, color, z0_mm,
  )
}

///|
/// Builds an extruded cylindrical housing sleeve with four axial anti-rotation
/// keyway slots at 45/135/225/315 deg using exact analytic arcs and lines (no
/// boolean cut required, so all four keyways appear in assembly.step,
/// exploded.step, GLB, and printable STEP/3MF).
fn keyed_housing_body_mm(
  name : String,
  outer_radius_mm : Double,
  inner_radius_mm : Double,
  keyway_width_mm : Double,
  keyway_depth_mm : Double,
  height_mm : Double,
  z0_mm : Double,
  extra_holes : Array[(Double, Double, Double)],
  density : @urdf.Density,
  color : @step_cad.Rgb,
) -> @cad.BodyPart {
  let outer = @step_gears.arc_circle_segments(outer_radius_mm * 2.0)
  let half_w = keyway_width_mm / 2.0
  let half_ang = @math.asin(half_w / inner_radius_mm)
  let r_back = inner_radius_mm + keyway_depth_mm
  let hole : Array[@step_cad.ProfileSegment] = []
  let deg = @math.PI / 180.0
  for ki in 0..<4 {
    let ang_k = (45.0 + 90.0 * ki.to_double()) * deg
    let ang_next = (45.0 + 90.0 * (ki + 1).to_double()) * deg
    let c = @math.cos(ang_k)
    let s = @math.sin(ang_k)
    let tx = -s
    let ty = c
    let a0 = ang_k - half_ang
    let a1 = ang_k + half_ang
    let p_in0 = (
      inner_radius_mm * @math.cos(a0),
      inner_radius_mm * @math.sin(a0),
    )
    let p_back0 = (r_back * c - half_w * tx, r_back * s - half_w * ty)
    let p_back1 = (r_back * c + half_w * tx, r_back * s + half_w * ty)
    let p_in1 = (
      inner_radius_mm * @math.cos(a1),
      inner_radius_mm * @math.sin(a1),
    )
    let a_next0 = ang_next - half_ang
    let p_next0 = (
      inner_radius_mm * @math.cos(a_next0),
      inner_radius_mm * @math.sin(a_next0),
    )
    hole.push(@step_cad.ProfileSegment::SegmentLine(p_in0, p_back0))
    hole.push(@step_cad.ProfileSegment::SegmentLine(p_back0, p_back1))
    hole.push(@step_cad.ProfileSegment::SegmentLine(p_back1, p_in1))
    hole.push(@step_cad.ProfileSegment::SegmentArc(p_in1, p_next0, (0.0, 0.0)))
  }
  let all_holes : Array[Array[@step_cad.ProfileSegment]] = [hole]
  for eh in extra_holes {
    all_holes.push(
      arc_segments_at(@step_gears.arc_circle_segments(eh.2), eh.0, eh.1),
    )
  }
  arc_profile_body(name, outer, height_mm, all_holes, density, color, z0_mm)
}

///|
/// Builds a regular hexagonal prism (6-sided positive-drive post) matching
/// `hb_polygon_hole(6, inradius_mm)` with vertices at 0, 60, ..., 300 deg.
fn hex_prism_body_mm(
  name : String,
  inradius_mm : Double,
  height_mm : Double,
  z0_mm : Double,
  density : @urdf.Density,
  color : @step_cad.Rgb,
) -> @cad.BodyPart {
  let r = inradius_mm / @math.cos(@math.PI / 6.0)
  let segs : Array[@step_cad.ProfileSegment] = []
  for i in 0..<6 {
    let a0 = 2.0 * @math.PI * i.to_double() / 6.0
    let a1 = 2.0 * @math.PI * ((i + 1) % 6).to_double() / 6.0
    segs.push(
      @step_cad.ProfileSegment::SegmentLine(
        (r * @math.cos(a0), r * @math.sin(a0)),
        (r * @math.cos(a1), r * @math.sin(a1)),
      ),
    )
  }
  arc_profile_body(name, segs, height_mm, [], density, color, z0_mm)
}

///|
/// The front-bearing outside diameter of a BLDC preset, for sizing an adapter
/// plate's bearing clearance bore.
pub fn bldc_front_bearing_outer(preset : String) -> Double {
  match bldc_preset(preset) {
    Some(p) => actuator_bearing_outer(p.bearing_designation)
    None => 20.0
  }
}

///|
/// The outer diameter of a catalogue bearing, falling back to 20 mm.
fn actuator_bearing_outer(designation : String) -> Double {
  match @step_motion.bearing_size(designation) {
    Ok(size) => size.outer_mm
    Err(_) => 20.0
  }
}

///|
/// Builds a printed clamp hub that joins the sun gear to an input shaft.
///
/// The body extends `length_mm` below the `top` face, so attaching `top` to the
/// sun gear's bottom face puts the hub on the input side. A radial M3 set
/// screw locks the hub onto a D-flatted shaft; the screw is on the side, below
/// the sun teeth, and is tightened before the output cover goes on.
pub fn sun_clamp_hub(
  name : String,
  bore_diam_mm : Double,
  outer_diam_mm : Double,
  length_mm : Double,
  detail : @step_common.DetailLevel,
) -> @cad.Component {
  let part = fabricated_part(
    "ACT-SUN-HUB", "Printed sun clamp hub; drill/tap the M3 radial set-screw hole and bond or press the flange to the sun gear",
    "carbon fiber nylon", "3D print", 4.0,
  )
  // Reach from the shaft bore to just past the hub's outer surface.
  let screw_len = outer_diam_mm / 2.0 - bore_diam_mm / 2.0 + 2.0
  let screw_center = (bore_diam_mm / 2.0 + outer_diam_mm / 2.0 + 2.0) / 2.0
  let screw_part = purchased_part(
    "SET-M3x\{screw_len}",
    "M3 x \{screw_len} socket set screw",
    "steel",
    0.15,
  )
  let comp = @cad.Component::new(name, description="Sun clamp hub")
    .with_param("bore_diam_mm", bore_diam_mm.to_string())
    .with_param("outer_diam_mm", outer_diam_mm.to_string())
    .with_param("length_mm", length_mm.to_string())
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_body",
        outer_diam_mm,
        bore_diam_mm,
        length_mm,
        z_mm=-length_mm / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::orange(),
      ).with_part(part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_set_screw",
        3.0,
        screw_len,
        x_mm=screw_center,
        z_mm=-length_mm / 2.0,
        ry_deg=90.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(screw_part),
    )
    .add_mate_mm_deg("top")
    .add_mate_mm_deg("bottom", z=-length_mm)
    .with_part(part)
    .add_fastener(
      @cad.Fastener::new(
        "sun_hub_set_screw",
        @cad.FastenerKind::Screw,
        thread="M3",
        length_mm=screw_len,
        engagement_mm=2.0,
        quantity=1,
        torque_nm=0.6,
        references=[name + "_body"],
        part=Some(screw_part),
      ),
    )
    .add_fit(
      @cad.Fit::new(
        "shaft_bore",
        @cad.FitClass::Clearance,
        nominal_mm=bore_diam_mm,
        min_mm=bore_diam_mm,
        max_mm=bore_diam_mm + 0.15,
      ),
    )
  let _ = detail
  comp
}

///|
/// Maps a `cad` BLDC preset onto the measured Tier-1 brushless-motor envelope.
///
/// The Tier-1 defaults are measured from a 50 x 20 mm 360 KV outrunner, so the
/// 5010 preset reproduces that geometry directly. Larger presets scale the
/// measured proportions radially and axially and widen the stator hub when the
/// preset's bolt circle needs more edge margin.
fn brushless_motor_spec_for_preset(
  p : BldcPreset,
) -> @step_motors.BrushlessMotorSpec {
  let base = @step_motors.brushless_motor_360kv_spec()
  let radial = p.diameter_mm / base.bell_outer_diameter_mm
  let axial = p.body_length_mm / 20.0
  let stator_thickness = base.stator_hub_thickness_mm * axial
  let min_stator_hub = p.bolt_circle_mm + p.mount_hole_mm + 2.0
  let scaled_stator_hub = base.stator_hub_diameter_mm * radial
  let stator_hub = if scaled_stator_hub > min_stator_hub {
    scaled_stator_hub
  } else {
    min_stator_hub
  }
  {
    bell_outer_diameter_mm: p.diameter_mm,
    bell_wall_thickness_mm: base.bell_wall_thickness_mm * radial,
    bell_face_outer_diameter_mm: base.bell_face_outer_diameter_mm * radial,
    bell_face_thickness_mm: base.bell_face_thickness_mm,
    bell_cone_thickness_mm: base.bell_cone_thickness_mm * radial,
    bell_cone_run_mm: base.bell_cone_run_mm * radial,
    bell_rim_start_mm: base.bell_rim_start_mm * axial,
    bell_rim_length_mm: base.bell_rim_length_mm * axial,
    bell_lip_major_radius_mm: base.bell_lip_major_radius_mm * radial,
    bell_lip_minor_radius_mm: base.bell_lip_minor_radius_mm * radial,
    bell_hub_diameter_mm: base.bell_hub_diameter_mm * radial,
    window_count: base.window_count,
    window_inner_diameter_mm: base.window_inner_diameter_mm * radial,
    window_outer_diameter_mm: base.window_outer_diameter_mm * radial,
    window_inner_half_angle_deg: base.window_inner_half_angle_deg,
    window_outer_half_angle_deg: base.window_outer_half_angle_deg,
    window_corner_radius_mm: base.window_corner_radius_mm * radial,
    window_phase_deg: base.window_phase_deg,
    prop_hole_count: base.prop_hole_count,
    prop_hole_diameter_mm: base.prop_hole_diameter_mm * radial,
    prop_hole_circle_diameter_mm: base.prop_hole_circle_diameter_mm * radial,
    stator_hub_diameter_mm: stator_hub,
    stator_hub_start_mm: p.body_length_mm - stator_thickness,
    stator_hub_thickness_mm: stator_thickness,
    mount_hole_count: base.mount_hole_count,
    mount_hole_diameter_mm: p.mount_hole_mm,
    mount_hole_circle_diameter_mm: p.bolt_circle_mm,
    shaft_diameter_mm: p.shaft_diameter_mm,
    shaft_rear_extension_mm: base.shaft_rear_extension_mm * axial,
    shaft_front_extension_mm: p.shaft_length_mm,
  }
}

///|
/// A low-KV BLDC outrunner built from the Tier-1
/// `@step_motors.brushless_motor` envelope.
///
/// The Tier-1 component is one rigid part with separate `bell`, `shaft`, and
/// `stator-hub` layers. This adapter rotates it onto the `cad` motor frame
/// (axis +Z, mounting face at `z = 0`, shaft forward into the gearbox), splits
/// the layers into a fixed stator link and a rotating rotor link, and adds the
/// same mates, ports, and continuous rotor joint as `low_kv_bldc_motor`, so it
/// can drive `planetary_bldc_actuator` and the exposed example-02 stage.
pub fn step_brushless_motor(
  name~ : String = "bldc_motor",
  preset~ : String = "5010_360kv",
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  joint_name~ : String = "",
) -> @cad.Component {
  if preset == "a12_8318_100kv" || preset == "a12" {
    let _ = detail
    return step_a12_motor(name~, joint_name~)
  }
  let _ = detail
  let p = resolve_bldc_preset(preset)
  let measured = brushless_motor_spec_for_preset(p)
  let step_comp = expect_step(
    "Tier-1 brushless motor",
    @step_motors.brushless_motor(measured),
  )
  let stator_name = name + "_stator"
  let rotor_name = name + "_rotor"
  let rotor_joint = if joint_name == "" {
    name + "_rotor_joint"
  } else {
    joint_name
  }
  // The Tier-1 model is built on +X with its mounting face at the stator hub's
  // outboard face. Rotate +X onto +Z and drop that face onto z = 0.
  let mount_x = measured.stator_hub_start_mm + measured.stator_hub_thickness_mm
  let frame_ry = -90.0
  let frame_z = -mount_x
  let stator_part = purchased_part(
    "BLDC-\{p.name}",
    "Low-KV brushless outrunner \{p.name} (\{p.kv} KV), measured Tier-1 envelope",
    "mixed",
    p.cost_usd,
    supplier_url="https://www.hobbyking.com/",
  )
  let mut stator = @cad.Component::from_step_layer(
    stator_name,
    step_comp,
    "stator-hub",
    density=@urdf.Density::aluminum_6061(),
    include_connectors=false,
    ry_deg=frame_ry,
    z_mm=frame_z,
  )
  stator = stator
    .add_mate_mm_deg("mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("front_face")
    .add_mate_mm_deg("rear", z=-p.body_length_mm, axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("sensor_boss", z=-p.body_length_mm, axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("encoder_mount", z=-p.body_length_mm - 4.0, rx_deg=180.0)
    .with_param("preset", p.name)
    .with_param("kv", p.kv.to_string())
    .with_param("pole_pairs", p.pole_pairs.to_string())
    .with_param("voltage_v", p.voltage_v.to_string())
    .with_param("phase_resistance_ohm", (0.18 * 360.0 / p.kv).to_string())
    .with_param("thermal_resistance_c_per_w", "2.5")
    .with_param("rated_current_a", p.current_rated_a.to_string())
    .with_param("peak_current_a", p.current_peak_a.to_string())
    .with_param("poles", (p.pole_pairs * 2).to_string())
    .with_param("rotor_encoder", "AS5600 / AS5047P-class, SPI")
    .with_param("rotor_encoder_air_gap_mm", "1.0")
    .with_param("motor_envelope", "Tier-1 brushless_motor (measured)")
    .add_port(
      @cad.Port::new(
        "power",
        @cad.PortKind::Power,
        spec=p.voltage_v.to_string() +
          " V, " +
          p.current_rated_a.to_string() +
          " A",
      ),
    )
    .add_port(@cad.Port::new("phases", @cad.PortKind::Power, spec="3-phase"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .with_actuator(
      @cad.ActuatorSpec::new(
        @cad.ActuatorKind::Bldc,
        model="BLDC " + p.name,
        voltage_v=p.voltage_v,
        current_rated_a=p.current_rated_a,
        current_stall_a=p.current_peak_a,
        torque_rated_nm=bldc_rated_torque(p),
        driver="SimpleFOC",
        interface="CAN",
        encoder="AS5600",
      ),
    )
    .with_part(stator_part)
  let mut rotor = @cad.Component::from_step_layer(
    rotor_name,
    step_comp,
    "bell",
    density=@urdf.Density::aluminum_6061(),
    include_connectors=false,
    ry_deg=frame_ry,
    z_mm=frame_z,
  )
  let shaft = @cad.Component::from_step_layer(
    name + "_shaft",
    step_comp,
    "shaft",
    density=@urdf.Density::steel_mild(),
    include_connectors=false,
    ry_deg=frame_ry,
    z_mm=frame_z,
  )
  rotor = rotor
    .attach(
      name + "_shaft_merge",
      parent_mate="origin",
      shaft,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
      bom_external=false,
    )
    .add_mate_mm_deg("base")
    .add_mate_mm_deg("shaft", z=p.shaft_length_mm)
  stator.attach(
    rotor_joint,
    parent_mate="front_face",
    rotor,
    child_mate="base",
    spec=@cad.JointSpec::continuous(
      limit=Some(
        @urdf.JointLimit::new(
          effort=bldc_rated_torque(p) * 4.0,
          velocity=p.kv * 0.1,
        ),
      ),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.01, friction=0.005)),
      transmission_reduction=Some(1.0),
    ),
    bom_external=false,
  )
}

///|
/// Wraps the measured Tier-1 A12 8318 100KV brushless outrunner (`a12_motor`)
/// into the fixed-stator / rotating-rotor CAD component interface.
///
/// The Tier-1 model is built on `+X` with its rotating prop adapter at `-X`
/// and fixed stator plate at `+X`. Rotating by `+90` deg about `+Y` maps
/// `stator-mount-face` onto `z = 0` facing `-Z` and places `rotor-output-face`
/// at `z = +32.0` mm facing `+Z` toward the gearbox sun gear. The `rotor` link
/// carries a `shaft_rear` mate at `z = 0` on the exposed `12 mm` stator-side
/// rotor shaft so an on-axis encoder magnet rides with the rotor.
pub fn step_a12_motor(
  name~ : String = "a12_motor",
  joint_name~ : String = "",
) -> @cad.Component {
  let spec = @step_motors.a12_motor_100kv_spec()
  let step_comp = expect_step(
    "A12 8318 100KV motor",
    @step_motors.a12_motor(spec),
  )
  let p = resolve_bldc_preset("a12_8318_100kv")
  let stator_name = name + "_stator"
  let rotor_name = name + "_rotor"
  let rotor_joint = if joint_name == "" {
    name + "_rotor_joint"
  } else {
    joint_name
  }
  let mount_x = spec.stator_plate_start_mm + spec.stator_plate_thickness_mm
  let output_x = -spec.prop_adapter_thickness_mm
  let body_len = mount_x - output_x
  let frame_ry = 90.0
  let frame_z = mount_x
  let stator_layers : Array[String] = [
    "stator-lamination", "stator-plate-neck", "stator-plate", "bearing-tube", "pcb-insulator",
  ]
  for i in 0..<spec.stator_tooth_count {
    stator_layers.push("stator-coil-\{i + 1}")
  }
  let rotor_layers : Array[String] = [
    "bell-face", "bell-skirt", "bell-hub-boss", "prop-adapter", "shaft",
  ]
  for i in 0..<spec.prop_screw_count {
    rotor_layers.push("prop-adapter-screw-\{i + 1}")
  }
  for i in 0..<spec.magnet_count {
    rotor_layers.push("rotor-magnet-\{i + 1}")
  }
  let stator_part = @cad.PartMeta::new(
    "BLDC-A12-8318",
    description="A12 8318 100KV brushless outrunner motor (91 mm OD, 12 mm shaft, 32 mm M4 / 30 mm M3 mount, 23 mm M4 prop adapter)",
    supplier="FreeRcHobby",
    supplier_url="https://www.freerchobby.cc/",
    material="mixed",
    process="purchased",
    unit_cost_usd=p.cost_usd,
  )
  let mut stator = @cad.Component::from_step_layers(
    stator_name,
    step_comp,
    stator_layers,
    label="stator",
    density=@urdf.Density::aluminum_6061(),
    ry_deg=frame_ry,
    z_mm=frame_z,
  )
  stator = stator
    .add_mate_mm_deg("mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("front_face", z=body_len)
    .add_mate_mm_deg("rear", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("sensor_boss", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("encoder_mount", z=-5.6)
    .with_param("preset", p.name)
    .with_param("kv", p.kv.to_string())
    .with_param("pole_pairs", p.pole_pairs.to_string())
    .with_param("voltage_v", p.voltage_v.to_string())
    .with_param("phase_resistance_ohm", "0.045")
    .with_param("thermal_resistance_c_per_w", "1.5")
    .with_param("rated_current_a", p.current_rated_a.to_string())
    .with_param("peak_current_a", p.current_peak_a.to_string())
    .with_param("poles", (p.pole_pairs * 2).to_string())
    .with_param("rotor_encoder", "AS5047P (moteus C1 r1.2), SPI")
    .with_param("rotor_encoder_air_gap_mm", "2.4")
    .with_param("motor_envelope", "Tier-1 A12 8318 100KV (measured)")
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="48 V, 60 A"))
    .add_port(@cad.Port::new("phases", @cad.PortKind::Power, spec="3-phase"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .with_actuator(
      @cad.ActuatorSpec::new(
        @cad.ActuatorKind::Bldc,
        model="A12 8318 100KV",
        voltage_v=p.voltage_v,
        current_rated_a=p.current_rated_a,
        current_stall_a=p.current_peak_a,
        torque_rated_nm=bldc_rated_torque(p),
        driver="moteus C1 / FOC",
        interface="CAN",
        encoder="AS5047P",
      ),
    )
    .with_part(stator_part)
  let m4_radius = spec.mount_m4_circle_diameter_mm / 2.0
  for i in 0..<spec.mount_m4_count {
    let angle = (
        spec.mount_hole_phase_deg +
        45.0 +
        360.0 * i.to_double() / spec.mount_m4_count.to_double()
      ) *
      @math.PI /
      180.0
    // Ry(+90 deg) maps STEP (x, y, z) -> (z, y, -x + mount_x).
    stator = stator.add_mate_mm_deg(
      "m4_hole_\{i}",
      x=m4_radius * @math.sin(angle),
      y=m4_radius * @math.cos(angle),
      axis=(0.0, 0.0, -1.0),
    )
  }
  let mut rotor = @cad.Component::from_step_layers(
    rotor_name,
    step_comp,
    rotor_layers,
    label="rotor",
    density=@urdf.Density::aluminum_6061(),
    ry_deg=frame_ry,
    z_mm=frame_z,
  )
  rotor = rotor
    .add_mate_mm_deg("base")
    .add_mate_mm_deg("output_face", z=body_len)
    .add_mate_mm_deg("shaft", z=body_len)
    .add_mate_mm_deg("shaft_rear", axis=(0.0, 0.0, -1.0))
  let prop_radius = spec.prop_hole_circle_diameter_mm / 2.0
  for i in 0..<spec.prop_hole_count {
    let angle = (
        spec.prop_hole_phase_deg +
        360.0 * i.to_double() / spec.prop_hole_count.to_double()
      ) *
      @math.PI /
      180.0
    rotor = rotor.add_mate_mm_deg(
      "output_hole_\{i}",
      x=prop_radius * @math.sin(angle),
      y=prop_radius * @math.cos(angle),
      z=body_len,
    )
  }
  stator.attach(
    rotor_joint,
    parent_mate="origin",
    rotor,
    child_mate="base",
    spec=@cad.JointSpec::continuous(
      limit=Some(
        @urdf.JointLimit::new(
          effort=bldc_rated_torque(p) * 4.0,
          velocity=p.kv * 0.1,
        ),
      ),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
      transmission_reduction=Some(1.0),
    ),
    bom_external=false,
  )
}

///|
/// Builds an integrated planetary BLDC actuator: an inexpensive low-KV BLDC
/// outrunner driving a printed Tier-1 planetary gearbox inside a printed
/// housing with a rear motor plate, a clamped sun input, planet bearings, a
/// two-bearing output cartridge, and an on-axis absolute output encoder.
///
/// `stages = 1` gives a ~5:1–9:1 reduction; `stages = 2` compounds it to
/// ~16:1–25:1. The motor rotor is the command input and the sun mimics it, so
/// one continuous joint drives the whole train.
pub fn planetary_bldc_actuator(
  name~ : String = "bldc_actuator",
  preset~ : String = "5010_360kv",
  stages~ : Int32 = 1,
  module_mm~ : Double = 1.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 12,
  planet_count~ : Int32 = 4,
  gear_length_mm~ : Double = 10.0,
  gear_type~ : String = "herringbone",
  num_elbows~ : Int32 = 4,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  joint_name~ : String = "",
  add_binding~ : Bool = true,
  output_encoder~ : Bool = true,
  output_shaft_extension_mm~ : Double = 0.0,
  heat_set_inserts~ : Bool = true,
  motor_source~ : String = "preset",
  output_sensor~ : String = "pcb",
  magnet_diameter_mm~ : Double = 6.0,
  magnet_height_mm~ : Double = 2.5,
  high_torque_output~ : Bool = false,
) -> @cad.Component {
  // `output_sensor = "pcb"` keeps the small printed-on-board sensor; `"none"`
  // leaves the magnet and cover boss in place for an external sensor board
  // such as the moteus C1.
  // `motor_source` selects the motor geometry: "preset" uses the compact
  // `low_kv_bldc_motor`; "brushless" uses the measured Tier-1
  // `step_brushless_motor` envelope.
  let p = resolve_bldc_preset(preset)
  let is_a12 = p.name == "A12-8318-100KV" || motor_source == "a12"
  let p = if is_a12 { resolve_bldc_preset("a12_8318_100kv") } else { p }
  let stage_count = if stages < 1 { 1 } else if stages > 2 { 2 } else { stages }
  // Only an explicit spur request uses exact line/arc gears. The default
  // herringbone gear set uses the 4-elbow print-in-place geometry at every
  // detail level; the detail level controls outline resolution, not elbows.
  let smooth = gear_type == "spur"
  let rotor_joint = if joint_name == "" {
    name + "_motor_rotor_joint"
  } else {
    joint_name
  }
  let motor = if is_a12 {
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
  let motor_plate_mm = 6.0
  let motor_mount_z = if is_a12 { -38.0 } else { 0.0 }
  // A 6 mm wall leaves more than 1 mm of printed material around the M3
  // cover screws at the bolt circle.
  let housing_wall = 6.0
  let stage_gap = 4.0
  let carrier_thickness = 8.0
  let gear_outer_thickness = 6.0
  let center_delta = 0.2
  // Printed gears use our calibrated 0.10 mm flank clearance.
  let tolerance = @step_common.DEFAULT_GEAR_TOLERANCE_MM
  let pa_deg = 20.0
  let deg = @math.PI / 180.0
  let ring_outer = module_mm *
    (sun_teeth.to_double() + 2.0 * planet_teeth.to_double()) /
    2.0 +
    module_mm +
    center_delta +
    tolerance / @math.sin(pa_deg * deg) +
    gear_outer_thickness
  let housing_outer = ring_outer + housing_wall
  let barrel_outer = if is_a12 && housing_outer < 53.5 {
    53.5
  } else {
    housing_outer
  }
  // 0.10 mm radial slip fit for the 4-keyed ring cartridge (torque is reacted
  // positively by the four 45-deg axial keyways, not by a plastic press fit).
  let housing_inner = ring_outer + 0.10
  let bolt_circle = (ring_outer + housing_wall / 2.0) * 2.0
  let rear_bolt_circle = (barrel_outer - housing_wall / 2.0) * 2.0
  let stage_pitch = gear_length_mm + carrier_thickness + 8.0
  let housing_top = stage_gap +
    (stage_count - 1).to_double() * stage_pitch +
    gear_length_mm +
    carrier_thickness +
    2.0
  let housing_bottom = if is_a12 { 0.0 } else { -motor_plate_mm }
  let housing_height = housing_top - housing_bottom
  let plate_bottom_z = motor_mount_z - motor_plate_mm
  let cover_plate_mm = 8.0
  // The bearing boss above the cover plate is 8 mm tall. With the on-axis
  // output encoder fitted, an output-shaft extension also raises the boss so
  // the magnet and AS5047P board stay 1 mm apart. Without the encoder (used
  // when a wheel or leg link occupies the outboard end), the extension is a
  // bare shaft protruding past the cover.
  let base_cover_top = housing_top + cover_plate_mm + 8.0
  let cover_tube_mm = if output_encoder {
    8.0 + output_shaft_extension_mm
  } else {
    8.0
  }
  let cover_top = base_cover_top +
    (if output_encoder { output_shaft_extension_mm } else { 0.0 })
  let shaft_end = base_cover_top + 0.5 + output_shaft_extension_mm
  let sensor_mount_z = cover_top + 2.5
  let final_carrier_top = housing_top - 2.0 + pgb_carrier_clearance_mm
  let final_shaft_len = shaft_end - final_carrier_top
  let stage1_shaft_len = if stage_count >= 2 {
    stage_pitch - gear_length_mm - carrier_thickness - pgb_carrier_clearance_mm
  } else {
    final_shaft_len
  }
  let stage1_sun_bore = if is_a12 {
    3.5
  } else {
    p.shaft_diameter_mm / 2.0 + 0.1
  }
  let stage1_sun_hole_type = if is_a12 { "Hexagonal" } else { "" }
  let coupling_shaft_diam = 8.0
  let coupling_bore = coupling_shaft_diam / 2.0 + 0.1
  // A 688 bearing (8 x 16 x 5) needs a planet root radius above about 9.5 mm
  // so at least 1.5 mm of printed material remains around the bore. Smaller
  // planet gears fall back to a plain 4 mm bore on a 3.8 mm pin.
  let planet_root = module_mm * (planet_teeth.to_double() / 2.0 - 1.25)
  let use_planet_bearing = planet_root > 9.5
  let planet_bore_radius = if use_planet_bearing { 8.0 } else { 2.0 }
  let planet_pin_diam = if use_planet_bearing { 8.0 } else { 3.8 }
  let planet_bearing = if use_planet_bearing { "688" } else { "" }
  let mut first = pgb_build(
    name + "_stage1",
    {
      gear_module: module_mm,
      gear_length_mm,
      helix_angle_deg: 30.0,
      sun_teeth,
      planet_teeth,
      num_planets: planet_count,
      pressure_angle_deg: 20.0,
      num_elbows,
      resolution: 5,
      bore_radius_mm: stage1_sun_bore,
      planet_bore_radius_mm: planet_bore_radius,
      carrier_pin_diam_mm: planet_pin_diam,
      carrier_bearing_designation: planet_bearing,
      output_shaft_diam_mm: coupling_shaft_diam,
      carrier_thickness_mm: carrier_thickness,
      output_shaft_length_mm: stage1_shaft_len,
      tolerance_mm: tolerance,
      outer_thickness_mm: gear_outer_thickness,
      include_carrier: true,
    },
    smooth,
    detail,
    false,
    sun_hole_type=stage1_sun_hole_type,
    bolted_output_bcd_mm=if high_torque_output && stage_count == 1 {
      28.0
    } else {
      0.0
    },
  )
  // Add the four matching anti-rotation key lugs onto stage 1's ring gear so
  // assembly.step, exploded.step, and START-HERE.html show the positive lock
  // between the ring gear and ACT-HOUSING's four axial keyway slots.
  let key_width = 6.0
  let key_protrusion = 2.5
  let key_embed = 2.0
  let key_radial_len = key_protrusion + key_embed
  let key_r_center = ring_outer + key_protrusion - key_radial_len / 2.0
  let ring_part_meta = if first.bodies.length() > 0 {
    first.bodies[0].part
  } else {
    None
  }
  for ki in 0..<4 {
    let ang_deg = 45.0 + 90.0 * ki.to_double()
    let lug_node = ramped_ring_key_node(
      name + "_stage1_ring_key_" + ki.to_string(),
      ring_outer,
      key_embed,
      key_protrusion,
      key_width,
      gear_length_mm,
      ang_deg,
    )
    let lug_body : @cad.BodyPart = {
      ..@cad.BodyPart::box_mm(
        name + "_stage1_ring_key_" + ki.to_string(),
        key_radial_len,
        key_width,
        gear_length_mm,
        x_mm=key_r_center * @math.cos(ang_deg * deg),
        y_mm=key_r_center * @math.sin(ang_deg * deg),
        z_mm=gear_length_mm / 2.0,
        rz_deg=ang_deg,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::grey(),
      ),
      node: lug_node,
    }
    let lug_assigned : @cad.BodyPart = match ring_part_meta {
      Some(pm) => lug_body.with_part(pm)
      None => lug_body
    }
    first = first.add_body(lug_assigned)
  }
  let housing_part = fabricated_part(
    "ACT-HOUSING",
    if high_torque_output {
      "Printed planetary actuator housing with four 45-deg anti-rotation keyways and integrated 100x100 mm VESA / 2020-extrusion 4xM5 bench-test mounting ears"
    } else {
      "Printed planetary actuator housing with four 45-deg anti-rotation keyways; slide the keyed ring cartridge in and bolt the cover with M3 screws"
    },
    "carbon fiber nylon",
    "3D print",
    18.0,
  )
  let plate_part = fabricated_part(
    "ACT-MOTOR-PLATE", "Rear motor plate with motor bolt pattern and shaft clearance; the motor's own front bearing runs in the bore",
    "carbon fiber nylon", "3D print", 10.0,
  )
  let cover_part = fabricated_part(
    "ACT-OUTPUT-COVER",
    if high_torque_output {
      "High-torque QDD output bearing cover with 52.2 mm bore and 1 mm retaining shoulder for a 6808-2RS (40x52x7 mm) thin-section output bearing"
    } else {
      "Output bearing cover with AS5047P sensor mount; press the 608 bearings into the 22.2 mm seats"
    },
    "carbon fiber nylon",
    "3D print",
    10.0,
  )
  let cover_boss_part = fabricated_part(
    "ACT-COVER-BOSS", "Printed output cover bearing boss; press the second 608 bearing into this seat",
    "carbon fiber nylon", "3D print", 4.0,
  )
  let motor_bolt_radius = p.bolt_circle_mm / 2.0
  let plate_holes : Array[(Double, Double, Double)] = []
  // Size the plate bore to the motor's own front bearing, but never so large
  // that it breaks into the motor mounting holes.
  let bearing_bore = bldc_front_bearing_outer(p.name) + 0.2
  let bolt_clear = 2.0 * (p.bolt_circle_mm / 2.0 - p.mount_hole_mm / 2.0 - 0.5)
  let plate_bore = if bearing_bore < bolt_clear {
    bearing_bore
  } else {
    bolt_clear
  }
  plate_holes.push((0.0, 0.0, plate_bore))
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * i.to_double() / 4.0
    plate_holes.push(
      (
        motor_bolt_radius * @math.cos(theta),
        motor_bolt_radius * @math.sin(theta),
        p.mount_hole_mm,
      ),
    )
  }
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * i.to_double() / 4.0
    plate_holes.push(
      (
        rear_bolt_circle / 2.0 * @math.cos(theta),
        rear_bolt_circle / 2.0 * @math.sin(theta),
        3.4,
      ),
    )
  }
  // Motor phase-wire pass-through, outside the motor bell but inside the
  // plate rim and clear of the housing-screw holes (which sit on the axes).
  let phase_radius = if is_a12 {
    barrel_outer - housing_wall - 2.0
  } else {
    p.diameter_mm * 0.5 + 3.0
  }
  let phase_angle = @math.PI / 4.0
  plate_holes.push(
    (
      phase_radius * @math.cos(phase_angle),
      phase_radius * @math.sin(phase_angle),
      5.0,
    ),
  )
  // Four M3 heat-set insert holes (4.4 mm dia) at (+/-16, +/-16) mm on the
  // rear motor plate for mounting the rear moteus C1 controller standoffs.
  if is_a12 {
    for i in 0..<4 {
      let sx = if i % 2 == 0 { 16.0 } else { -16.0 }
      let sy = if i < 2 { -16.0 } else { 16.0 }
      plate_holes.push((sx, sy, 4.4))
    }
  }
  let cover_holes : Array[(Double, Double, Double)] = []
  cover_holes.push((0.0, 0.0, actuator_bearing_outer("608") + 0.2))
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * i.to_double() / 4.0
    cover_holes.push(
      (
        bolt_circle / 2.0 * @math.cos(theta),
        bolt_circle / 2.0 * @math.sin(theta),
        3.4,
      ),
    )
  }
  // Build the outer housing tube with four exact analytic axial anti-rotation
  // keyway slots at 45/135/225/315 deg (midway between the M3 cover screws)
  // plus blind 6.0 mm deep M3 heat-set insert pockets (4.4 mm dia; 4 mm insert
  // + 2 mm bolt-tip/melt clearance) at 0/90/180/270 deg on both ends.
  // For the A12 stepped housing, also add a 45-degree internal conical overhang
  // chamfer between the 95 mm motor bore and the keyed ring bore so ACT-HOUSING
  // prints cleanly with zero supports.
  let keyway_width = 6.2
  let keyway_depth = 2.65
  let insert_pocket_depth = 6.0
  let top_insert_holes : Array[(Double, Double, Double)] = []
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * i.to_double() / 4.0
    top_insert_holes.push(
      (
        bolt_circle / 2.0 * @math.cos(theta),
        bolt_circle / 2.0 * @math.sin(theta),
        4.4,
      ),
    )
  }
  let top_pocket_h = if housing_height > insert_pocket_depth + 1.0 {
    insert_pocket_depth
  } else {
    housing_height
  }
  let lower_ring_h = housing_height - top_pocket_h
  let keyed_ring_body = keyed_housing_body_mm(
    name + "_housing",
    housing_outer,
    housing_inner,
    keyway_width,
    keyway_depth,
    top_pocket_h,
    housing_top - top_pocket_h,
    top_insert_holes,
    @urdf.Density::carbon_fiber(),
    @step_cad.Rgb::black(),
  ).with_part(housing_part)
  let extra_housing_bodies : Array[@cad.BodyPart] = []
  if lower_ring_h > 0.1 {
    extra_housing_bodies.push(
      keyed_housing_body_mm(
        name + "_housing_lower",
        housing_outer,
        housing_inner,
        keyway_width,
        keyway_depth,
        lower_ring_h,
        housing_bottom,
        [],
        @urdf.Density::carbon_fiber(),
        @step_cad.Rgb::black(),
      ).with_part(housing_part),
    )
  }
  if is_a12 {
    let barrel_inner_r = 47.5
    let barrel_total_h = -motor_mount_z
    let rear_pocket_h = if barrel_total_h > insert_pocket_depth + 1.0 {
      insert_pocket_depth
    } else {
      barrel_total_h
    }
    let barrel_solid_h = barrel_total_h - rear_pocket_h
    if high_torque_output {
      // Single all-curved G1-tangent 4-lobe VESA-100 (100x100 mm, 4xM5) base
      // flange: zero sharp corners on Layer 1 so the IVI never curls an edge!
      // Lower 6.0 mm carries the 4x M3 rear heat-set insert pockets + 4x M5
      // VESA holes; upper 2.0 mm carries the 4x M5 VESA holes (8 mm total ear
      // thickness). All ACT-HOUSING sections are unioned into one monolithic
      // solid (`solids = 1` in SolidCraft).
      let vesa_outer = vesa_flange_outer_segments(
        barrel_outer,
        (50.0 * 50.0 * 2.0).sqrt(),
        9.5,
        12.0,
      )
      let vesa_rear_holes : Array[Array[@step_cad.ProfileSegment]] = [
        @step_gears.arc_circle_segments(barrel_inner_r * 2.0),
      ]
      for i in 0..<4 {
        let theta = 2.0 * @math.PI * i.to_double() / 4.0
        vesa_rear_holes.push(
          translate_arc_circle(
            4.4,
            rear_bolt_circle / 2.0 * @math.cos(theta),
            rear_bolt_circle / 2.0 * @math.sin(theta),
          ),
        )
      }
      let vesa_upper_holes : Array[Array[@step_cad.ProfileSegment]] = [
        @step_gears.arc_circle_segments(barrel_inner_r * 2.0),
      ]
      let ear_r = (50.0 * 50.0 * 2.0).sqrt()
      for ei in 0..<4 {
        let ang_rad = (45.0 + 90.0 * ei.to_double()) * deg
        let h_m5 = translate_arc_circle(
          5.4,
          ear_r * @math.cos(ang_rad),
          ear_r * @math.sin(ang_rad),
        )
        vesa_rear_holes.push(h_m5)
        vesa_upper_holes.push(h_m5)
      }
      let vesa_lower_node = @step_cad.ExtrudedArcProfile::new(
          vesa_outer,
          rear_pocket_h,
          holes=vesa_rear_holes,
        )
        .as_shape()
        .with_name(name + "_a12_motor_barrel_rear")
        .with_color(@step_cad.Rgb::black())
        .translate(z=motor_mount_z)
      let vesa_upper_node = @step_cad.ExtrudedArcProfile::new(
          vesa_outer,
          2.2,
          holes=vesa_upper_holes,
        )
        .as_shape()
        .with_name(name + "_a12_vesa_flange_upper")
        .with_color(@step_cad.Rgb::black())
        .translate(z=motor_mount_z + rear_pocket_h - 0.2)
      let barrel_above_h = barrel_total_h - (rear_pocket_h + 2.0)
      let barrel_above_node = actuator_plate_body(
          name + "_a12_motor_barrel",
          barrel_outer * 2.0,
          barrel_above_h + 0.4,
          motor_mount_z + rear_pocket_h + 1.8,
          [(0.0, 0.0, barrel_inner_r * 2.0)],
          @urdf.Density::carbon_fiber(),
          @step_cad.Rgb::black(),
          detail,
        ).node
      let mono_nodes : Array[@step_cad.SceneNode] = [
        vesa_lower_node, vesa_upper_node, barrel_above_node,
      ]
      let ramp_h = barrel_inner_r - housing_inner
      if ramp_h > 0.2 {
        let ramp_outer_r = barrel_inner_r + 0.5
        let ramp_profile = @step_cad.RevolvedProfile::polyline(
          [
            (barrel_inner_r, -ramp_h),
            (ramp_outer_r, -ramp_h),
            (ramp_outer_r, 0.2),
            (housing_inner, 0.2),
          ],
          closed=true,
        )
        mono_nodes.push(
          ramp_profile
          .as_shape()
          .with_name(name + "_internal_chamfer")
          .with_color(@step_cad.Rgb::black()),
        )
      }
      if lower_ring_h > 0.1 {
        mono_nodes.push(
          keyed_housing_body_mm(
            name + "_housing_lower",
            housing_outer,
            housing_inner,
            keyway_width,
            keyway_depth,
            lower_ring_h + 0.2,
            housing_bottom,
            [],
            @urdf.Density::carbon_fiber(),
            @step_cad.Rgb::black(),
          ).node,
        )
      }
      mono_nodes.push(keyed_ring_body.node)
      // Replace split housing bodies with one monolithic unioned solid.
      extra_housing_bodies.clear()
      extra_housing_bodies.push(
        {
          ..keyed_ring_body,
          name: name + "_housing",
          node: @step_cad.union_all(mono_nodes, name=name + "_housing").with_color(
            @step_cad.Rgb::black(),
          ),
        }.with_part(housing_part),
      )
    } else {
      let rear_pocket_holes : Array[(Double, Double, Double)] = [
        (0.0, 0.0, barrel_inner_r * 2.0),
      ]
      for i in 0..<4 {
        let theta = 2.0 * @math.PI * i.to_double() / 4.0
        rear_pocket_holes.push(
          (
            rear_bolt_circle / 2.0 * @math.cos(theta),
            rear_bolt_circle / 2.0 * @math.sin(theta),
            4.4,
          ),
        )
      }
      extra_housing_bodies.push(
        actuator_plate_body(
          name + "_a12_motor_barrel_rear",
          barrel_outer * 2.0,
          rear_pocket_h,
          motor_mount_z,
          rear_pocket_holes,
          @urdf.Density::carbon_fiber(),
          @step_cad.Rgb::black(),
          detail,
        ).with_part(housing_part),
      )
      if barrel_solid_h > 0.1 {
        extra_housing_bodies.push(
          actuator_plate_body(
            name + "_a12_motor_barrel",
            barrel_outer * 2.0,
            barrel_solid_h,
            motor_mount_z + rear_pocket_h,
            [(0.0, 0.0, barrel_inner_r * 2.0)],
            @urdf.Density::carbon_fiber(),
            @step_cad.Rgb::black(),
            detail,
          ).with_part(housing_part),
        )
      }
      // 45-degree internal transition chamfer eliminating the 90-degree step
      // overhang from barrel_inner_r (47.5 mm) inward to housing_inner (44.09 mm).
      let ramp_h = barrel_inner_r - housing_inner
      if ramp_h > 0.2 {
        let ramp_outer_r = barrel_inner_r + 0.5
        let ramp_profile = @step_cad.RevolvedProfile::polyline(
          [
            (barrel_inner_r, -ramp_h),
            (ramp_outer_r, -ramp_h),
            (ramp_outer_r, 0.0),
            (housing_inner, 0.0),
          ],
          closed=true,
        )
        let ramp_node = ramp_profile
          .as_shape()
          .with_name(name + "_internal_chamfer")
          .with_color(@step_cad.Rgb::black())
        extra_housing_bodies.push(
          {
            ..keyed_ring_body,
            name: name + "_internal_chamfer",
            node: ramp_node,
          }.with_part(housing_part),
        )
      }
    }
  }
  let mut housing = @cad.Component::new(
      name,
      description="Planetary BLDC actuator",
    )
    .with_param("preset", p.name)
    .with_param("stages", stage_count.to_string())
    .with_param("module_mm", module_mm.to_string())
    .with_param("gear_type", gear_type)
    .with_param("planet_bearing", planet_bearing)
    .with_param("planet_pin_diam_mm", planet_pin_diam.to_string())
    .with_param("output_shaft_diam_mm", coupling_shaft_diam.to_string())
  if !(high_torque_output && is_a12) {
    housing = housing.add_body(keyed_ring_body)
  }
  for hb in extra_housing_bodies {
    housing = housing.add_body(hb)
  }
  housing = housing.add_body(
    actuator_plate_body(
      name + "_motor_plate",
      barrel_outer * 2.0,
      motor_plate_mm,
      plate_bottom_z,
      plate_holes,
      @urdf.Density::carbon_fiber(),
      @step_cad.Rgb::black(),
      detail,
    ).with_part(plate_part),
  )
  if high_torque_output {
    // Monolithic high-torque 6808-2RS (40x52x7 mm) bearing cover:
    // z = housing_top .. housing_top + 1.0 mm: 46.0 mm ID retaining shoulder
    // z = housing_top + 1.0 .. housing_top + 8.0 mm: 52.2 mm bearing seat bore.
    let cover_bolt_holes : Array[(Double, Double, Double)] = []
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      cover_bolt_holes.push(
        (
          bolt_circle / 2.0 * @math.cos(theta),
          bolt_circle / 2.0 * @math.sin(theta),
          3.4,
        ),
      )
    }
    let shoulder_holes : Array[(Double, Double, Double)] = [(0.0, 0.0, 46.0)]
    for h in cover_bolt_holes {
      shoulder_holes.push(h)
    }
    let seat_holes : Array[(Double, Double, Double)] = [(0.0, 0.0, 52.2)]
    for h in cover_bolt_holes {
      seat_holes.push(h)
    }
    let cover_shoulder_body = actuator_plate_body(
      name + "_output_cover_shoulder",
      housing_outer * 2.0,
      1.0,
      housing_top,
      shoulder_holes,
      @urdf.Density::carbon_fiber(),
      @step_cad.Rgb::black(),
      detail,
    )
    let cover_seat_body = actuator_plate_body(
      name + "_output_cover_seat",
      housing_outer * 2.0,
      cover_plate_mm - 1.0,
      housing_top + 1.0,
      seat_holes,
      @urdf.Density::carbon_fiber(),
      @step_cad.Rgb::black(),
      detail,
    )
    let cover_monolith : @cad.BodyPart = {
      ..cover_seat_body,
      name: name + "_output_cover_plate",
      node: @step_cad.union_all(
        [cover_shoulder_body.node, cover_seat_body.node],
        name=name + "_output_cover_plate",
      ).with_color(@step_cad.Rgb::black()),
    }.with_part(cover_part)
    housing = housing.add_body(cover_monolith)
  } else {
    housing = housing
      .add_body(
        actuator_plate_body(
          name + "_output_cover_plate",
          housing_outer * 2.0,
          cover_plate_mm,
          housing_top,
          cover_holes,
          @urdf.Density::carbon_fiber(),
          @step_cad.Rgb::black(),
          detail,
        ).with_part(cover_part),
      )
      .add_body(
        @cad.BodyPart::tube_mm(
          name + "_output_cover_tube",
          32.0,
          22.2,
          cover_tube_mm,
          z_mm=housing_top + cover_plate_mm + cover_tube_mm / 2.0,
          density=@urdf.Density::carbon_fiber(),
          color=@step_cad.Rgb::black(),
        ).with_part(cover_boss_part),
      )
  }
  housing = housing
    .add_mate_mm_deg("motor_mount", z=motor_mount_z, axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("bearing_seat", z=-3.0)
    .add_mate_mm_deg("gearbox_mount")
    .add_mate_mm_deg("output_face", z=housing_top)
    .add_mate_mm_deg("output_flange", z=housing_top)
    .add_mate_mm_deg("output_shaft", z=shaft_end)
    .add_mate_mm_deg("sensor_mount", z=sensor_mount_z, axis=(0.0, 0.0, -1.0))
    // Top of the output cover plate: the support base for an external sensor
    // bracket or long standoffs.
    .add_mate_mm_deg("sensor_base", z=housing_top + cover_plate_mm)
    .add_port(
      @cad.Port::new(
        "power",
        @cad.PortKind::Power,
        spec=p.voltage_v.to_string() +
          " V, " +
          p.current_rated_a.to_string() +
          " A",
      ),
    )
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(
      @cad.Port::new(
        "encoder",
        @cad.PortKind::Sensor,
        spec="AS5047P, SPI/ABZ, 14-bit",
      ),
    )
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .add_fit(
      @cad.Fit::new(
        "ring_seat",
        @cad.FitClass::Clearance,
        nominal_mm=ring_outer * 2.0,
        min_mm=ring_outer * 2.0,
        max_mm=ring_outer * 2.0 + 0.25,
      ),
    )
    .add_fit(
      @cad.Fit::new(
        "output_bearing_seat",
        @cad.FitClass::Transition,
        nominal_mm=22.0,
        min_mm=21.95,
        max_mm=22.05,
      ),
    )
  // Motor and cover bolt mates.
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * i.to_double() / 4.0
    housing = housing
      .add_mate_mm_deg(
        "motor_bolt_\{i}",
        x=motor_bolt_radius * @math.cos(theta),
        y=motor_bolt_radius * @math.sin(theta),
        z=motor_mount_z,
        axis=(0.0, 0.0, -1.0),
      )
      .add_mate_mm_deg(
        "housing_bolt_\{i}",
        x=rear_bolt_circle / 2.0 * @math.cos(theta),
        y=rear_bolt_circle / 2.0 * @math.sin(theta),
        z=plate_bottom_z,
        rx_deg=180.0,
      )
      .add_mate_mm_deg(
        "cover_bolt_\{i}",
        x=bolt_circle / 2.0 * @math.cos(theta),
        y=bolt_circle / 2.0 * @math.sin(theta),
        z=housing_top + cover_plate_mm,
      )
  }
  let sensor_bolt_x = 10.0
  let sensor_bolt_y = 7.5
  let sensor_bolts : Array[(Double, Double)] = [
    (-sensor_bolt_x, -sensor_bolt_y),
    (sensor_bolt_x, -sensor_bolt_y),
    (sensor_bolt_x, sensor_bolt_y),
    (-sensor_bolt_x, sensor_bolt_y),
  ]
  for i in 0..<sensor_bolts.length() {
    housing = housing
      .add_mate_mm_deg(
        "sensor_bolt_\{i}",
        x=sensor_bolts[i].0,
        y=sensor_bolts[i].1,
        z=sensor_mount_z,
      )
      .add_mate_mm_deg(
        "sensor_standoff_\{i}",
        x=sensor_bolts[i].0,
        y=sensor_bolts[i].1,
        z=cover_top,
      )
  }
  // Output bearing cartridge: either a single large 6808-2RS (40x52x7 mm)
  // thin-section QDD bearing in high-torque mode, or two 608 bearings in the
  // standard shaft layout.
  if high_torque_output {
    let qdd_bearing = ball_bearing(
      name="\{name}_output_bearing_0",
      designation="6808",
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    housing = housing
      .add_mate_mm_deg("output_bearing_1", z=housing_top + 4.5)
      .attach(
        "output_bearing_merge_0",
        parent_mate="output_bearing_1",
        qdd_bearing,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(),
      )
  } else {
    housing = housing
      .add_mate_mm_deg("output_bearing_1", z=housing_top + 3.5)
      .add_mate_mm_deg("output_bearing_2", z=housing_top + 12.5)
    for i in 0..<2 {
      let bearing = ball_bearing(
        name="\{name}_output_bearing_\{i}",
        designation="608",
        detail~,
        density=@urdf.Density::steel_mild(),
      )
      let mate_name = if i == 0 {
        "output_bearing_1"
      } else {
        "output_bearing_2"
      }
      housing = housing.attach(
        "output_bearing_merge_\{i}",
        parent_mate=mate_name,
        bearing,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
  }
  // The motor's own front bearing runs in the plate bore, so the actuator does
  // not add a second bearing there. The motor mounting screws pass through the
  // plate's real bolt holes into the purchased motor; they are a fastener
  // schedule rather than solids through the motor's envelope.
  let motor_screw_part = purchased_part(
    "ISO4762-M3x12", "ISO 4762 socket head cap screw M3 x 12 mm", "steel", 0.35,
  )
  housing = housing.add_fastener(
    @cad.Fastener::new(
      "motor_mount_screws",
      @cad.FastenerKind::Screw,
      thread="M3",
      length_mm=12.0,
      engagement_mm=5.0,
      quantity=4,
      torque_nm=0.8,
      references=[name + "_motor_plate"],
      part=Some(motor_screw_part),
    ),
  )
  // Rear plate to housing screws and output cover screws.
  for i in 0..<4 {
    housing = housing
      .attach(
        "housing_screw_merge_\{i}",
        parent_mate="housing_bolt_\{i}",
        iso_shcs_screw(
          name="\{name}_housing_screw_\{i}",
          size=@step_standards.M3,
          length_mm=10.0,
          detail~,
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
      .attach(
        "cover_screw_merge_\{i}",
        parent_mate="cover_bolt_\{i}",
        iso_shcs_screw(
          name="\{name}_cover_screw_\{i}",
          size=@step_standards.M3,
          length_mm=12.0,
          detail~,
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  // Heat-set inserts in the 6 mm housing wall at both screw circles. The four
  // rear inserts run forward from the motor plate, the four cover inserts run
  // back from the cover face, so each screw engages a real threaded insert
  // instead of printed plastic.
  if heat_set_inserts && detail_is_rich(detail) {
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      let bx = bolt_circle / 2.0 * @math.cos(theta)
      let by = bolt_circle / 2.0 * @math.sin(theta)
      let rbx = rear_bolt_circle / 2.0 * @math.cos(theta)
      let rby = rear_bolt_circle / 2.0 * @math.sin(theta)
      housing = housing
        .add_mate_mm_deg(
          "cover_insert_\{i}",
          x=bx,
          y=by,
          z=housing_top,
          rx_deg=180.0,
        )
        .add_mate_mm_deg("rear_insert_\{i}", x=rbx, y=rby, z=motor_mount_z)
        .attach(
          "cover_insert_merge_\{i}",
          parent_mate="cover_insert_\{i}",
          heat_set_insert(
            name="\{name}_cover_insert_\{i}",
            outer_diam_mm=4.5,
            inner_diam_mm=3.0,
            length_mm=4.0,
          ),
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
        .attach(
          "rear_insert_merge_\{i}",
          parent_mate="rear_insert_\{i}",
          heat_set_insert(
            name="\{name}_rear_insert_\{i}",
            outer_diam_mm=4.5,
            inner_diam_mm=3.0,
            length_mm=4.0,
          ),
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
  }
  // The motor bolts onto the rear plate; its shaft points into the gearbox.
  housing = housing.attach(
    name + "_motor_mount_joint",
    parent_mate="motor_mount",
    motor,
    child_mate="mount",
    spec=@cad.JointSpec::fixed(),
  )
  // Stage one ring is fixed to the housing; its sun/planets/carrier remain
  // kinematic children. The sun mimics the motor rotor.
  housing = housing.attach(
    "stage1_mount",
    parent_mate="gearbox_mount",
    first,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(offset_mm=stage_gap),
  )
  set_joint_mimic(
    housing,
    name + "_stage1_sun_joint",
    @urdf.JointMimic::new(rotor_joint, multiplier=1.0),
  )
  // Couple the A12 rotor prop adapter (`output_face` at z = -6.0) to Stage 1 sun
  // (`z = 4.0`) with a bolted 4xM4 flange + raised central cylindrical thrust
  // spacer (clearing the planet gears and sun teeth by 2 mm axially) + integral
  // 6.7 mm across-flats hex drive post engaging the sun gear's hexagonal bore.
  // The 4 M4 SHCS heads are counterbored (7.8 mm dia x 4.4 mm deep) so they sit
  // completely recessed inside the flange with full axial clearance to the gears.
  if is_a12 {
    let adapter_len = -motor_mount_z - 32.0 + stage_gap
    let spacer_h = if adapter_len >= 9.0 { 2.0 } else { 1.0 }
    let flange_h = adapter_len - spacer_h
    let cbore_depth = 4.4
    let bolt_seat_z = if flange_h > cbore_depth + 2.0 {
      flange_h - cbore_depth
    } else {
      flange_h / 2.0
    }
    let hex_post_len = gear_length_mm - 0.5
    let adapter_part = fabricated_part(
      "ACT-ROTOR-ADAPTER", "Printed A12 rotor-to-sun hex drive adapter: counterbored 4xM4x8 flange (2 mm axial gear clearance), 12 mm central sun-hub spacer, and integral 6.7 mm hex drive post",
      "carbon fiber nylon", "3D print", 6.0,
    )
    let prop_bolt_r = 11.5
    let lower_holes : Array[(Double, Double, Double)] = []
    let cbore_holes : Array[(Double, Double, Double)] = []
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      let bx = prop_bolt_r * @math.cos(theta)
      let by = prop_bolt_r * @math.sin(theta)
      lower_holes.push((bx, by, 4.3))
      cbore_holes.push((bx, by, 7.8))
    }
    // Layered ExtrudedArcProfile flange (lower 4.3 mm bolt holes + upper 7.8 mm
    // counterbores) so all 4 counterbores are visible in BOTH SolidCraft AND
    // the 3D glTF viewer with zero boolean artifacts.
    let flange_lower = actuator_plate_body(
      name + "_rotor_adapter_flange_lower",
      34.0,
      bolt_seat_z + 0.1,
      0.0,
      lower_holes,
      @urdf.Density::carbon_fiber(),
      @step_cad.Rgb::orange(),
      detail,
    )
    let flange_upper = actuator_plate_body(
      name + "_rotor_adapter_flange_upper",
      34.0,
      flange_h - bolt_seat_z,
      bolt_seat_z,
      cbore_holes,
      @urdf.Density::carbon_fiber(),
      @step_cad.Rgb::orange(),
      detail,
    )
    // Central 12.0 mm OD cylindrical spacer boss contacts only the co-rotating
    // sun gear hub (r = 6.0 mm < sun root 7.125 mm < planet sweep 7.5 mm),
    // leaving 2.0 mm axial air gap over the outer flange and counterbored bolts.
    let spacer_overlap = 0.5
    let spacer_boss_node = @step_cad.Cylinder::new(
        12.0,
        spacer_h + spacer_overlap,
      )
      .with_name(name + "_rotor_adapter_spacer")
      .translate(z=flange_h - spacer_overlap)
    let hex_post_body = hex_prism_body_mm(
      name + "_rotor_adapter_hex_post",
      3.35,
      hex_post_len + spacer_overlap,
      adapter_len - spacer_overlap,
      @urdf.Density::carbon_fiber(),
      @step_cad.Rgb::orange(),
    )
    let adapter_monolith : @cad.BodyPart = {
      ..flange_lower,
      name: name + "_rotor_adapter_flange",
      node: @step_cad.union_all(
        [
          flange_lower.node,
          flange_upper.node,
          spacer_boss_node,
          hex_post_body.node,
        ],
        name=name + "_rotor_adapter_flange",
      ).with_color(@step_cad.Rgb::orange()),
    }.with_part(adapter_part)
    let mut adapter = @cad.Component::new(
        name + "_rotor_adapter",
        description="Bolted 4xM4 A12 rotor-to-sun hexagonal drive adapter",
      )
      .with_part(adapter_part)
      .add_body(adapter_monolith)
      .add_mate_mm_deg("rotor_seat")
    // Four M4 x 8 mm socket head cap screws seat inside the counterbores at
    // z = bolt_seat_z (3.6 mm), giving 4.4 mm thread engagement into the A12
    // rotor prop mount with heads recessed 0.4 mm below the flange top.
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      adapter = adapter
        .add_mate_mm_deg(
          "adapter_bolt_\{i}",
          x=prop_bolt_r * @math.cos(theta),
          y=prop_bolt_r * @math.sin(theta),
          z=bolt_seat_z,
        )
        .attach(
          "adapter_screw_merge_\{i}",
          parent_mate="adapter_bolt_\{i}",
          iso_shcs_screw(
            name="\{name}_rotor_adapter_screw_\{i}",
            size=@step_standards.M4,
            length_mm=8.0,
            detail~,
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
    housing = housing.attach_to(
      name + "_motor_rotor",
      name + "_rotor_adapter_merge",
      parent_mate="output_face",
      adapter,
      child_mate="rotor_seat",
      spec=@cad.JointSpec::merge_rigid(),
    )
  } else {
    housing = housing.attach_to(
      name + "_stage1_sun",
      "sun_hub_merge",
      parent_mate="bottom",
      sun_clamp_hub(
        name + "_sun_hub",
        p.shaft_diameter_mm + 0.2,
        12.0,
        4.5,
        detail,
      ),
      child_mate="top",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let mut output_joint = name + "_stage1_carrier_joint"
  let mut output_carrier = name + "_stage1_carrier"
  if stage_count >= 2 {
    let mut second = pgb_build(
      name + "_stage2",
      {
        gear_module: module_mm,
        gear_length_mm,
        helix_angle_deg: 30.0,
        sun_teeth,
        planet_teeth,
        num_planets: planet_count,
        pressure_angle_deg: 20.0,
        num_elbows,
        resolution: 5,
        bore_radius_mm: coupling_bore,
        planet_bore_radius_mm: planet_bore_radius,
        carrier_pin_diam_mm: planet_pin_diam,
        carrier_bearing_designation: planet_bearing,
        output_shaft_diam_mm: coupling_shaft_diam,
        carrier_thickness_mm: carrier_thickness,
        output_shaft_length_mm: final_shaft_len,
        tolerance_mm: tolerance,
        outer_thickness_mm: gear_outer_thickness,
        include_carrier: true,
      },
      smooth,
      detail,
      false,
    )
    // Add the four matching 45-deg anti-rotation key lugs to Stage 2's ring
    // gear as well so it locks positively into ACT-HOUSING's four keyways.
    let s2_ring_part = if second.bodies.length() > 0 {
      second.bodies[0].part
    } else {
      None
    }
    for ki in 0..<4 {
      let ang_deg = 45.0 + 90.0 * ki.to_double()
      let ang_rad = ang_deg * deg
      let lug = @cad.BodyPart::box_mm(
        name + "_stage2_ring_key_" + ki.to_string(),
        key_radial_len,
        key_width,
        gear_length_mm,
        x_mm=key_r_center * @math.cos(ang_rad),
        y_mm=key_r_center * @math.sin(ang_rad),
        z_mm=gear_length_mm / 2.0,
        rz_deg=ang_deg,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::grey(),
      )
      let lug_assigned : @cad.BodyPart = match s2_ring_part {
        Some(pm) => lug.with_part(pm)
        None => lug
      }
      second = second.add_body(lug_assigned)
    }
    let stage2_z = stage_gap + stage_pitch
    housing = housing
      .add_mate_mm_deg("stage2_mount", z=stage2_z)
      .attach(
        "stage2_mount_merge",
        parent_mate="stage2_mount",
        second,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(),
      )
    set_joint_mimic(
      housing,
      name + "_stage2_sun_joint",
      @urdf.JointMimic::new(output_joint, multiplier=1.0),
    )
    // The first stage carrier shaft drives the second stage through a clamp
    // hub on the second stage sun.
    housing = housing.attach_to(
      name + "_stage2_sun",
      "coupling_hub_merge",
      parent_mate="bottom",
      sun_clamp_hub(
        name + "_coupling_hub",
        coupling_shaft_diam + 0.2,
        16.0,
        stage1_shaft_len,
        detail,
      ),
      child_mate="top",
      spec=@cad.JointSpec::merge_rigid(),
    )
    output_joint = name + "_stage2_carrier_joint"
    output_carrier = name + "_stage2_carrier"
  }
  // A set-screw clamp collar on the output shaft retains the 608 inner races
  // in the standard shaft layout (not used in the bolted QDD output layout).
  if !high_torque_output {
    housing = housing.attach_to(
      output_carrier,
      name + "_output_collar_merge",
      parent_mate="output_flange",
      shaft_collar(
        name=name + "_output_collar",
        bore_diam_mm=8.0,
        outer_diam_mm=16.0,
        width_mm=2.0,
        style="set_screw",
        thread_size=@step_standards.M2,
      ),
      child_mate="origin",
      spec=@cad.JointSpec::fixed(offset_mm=1.5),
    )
  }
  if output_encoder {
    // Output magnet on the final carrier shaft. Its top face is at the
    // `output_shaft` mate; an external sensor board places its chip above it.
    housing = housing.attach_to(
      output_carrier,
      "output_magnet_merge",
      parent_mate="output_shaft",
      encoder_magnet(
        name=name + "_output_magnet",
        diameter_mm=magnet_diameter_mm,
        thickness_mm=magnet_height_mm,
      ),
      child_mate="top",
      spec=@cad.JointSpec::merge_rigid(),
    )
    if output_sensor != "none" {
      housing = housing.attach(
        "output_sensor_mount",
        parent_mate="sensor_mount",
        moteus_position_sensor(
          name=name + "_output_sensor",
          voltage_v=3.3,
          current_ma=15.0,
          detail~,
        ),
        child_mate="mount",
        spec=@cad.JointSpec::merge_rigid(),
      )
      // Sensor standoffs and screws.
      for i in 0..<sensor_bolts.length() {
        housing = housing.attach(
          "sensor_standoff_merge_\{i}",
          parent_mate="sensor_standoff_\{i}",
          hex_standoff(
            name="\{name}_sensor_standoff_\{i}",
            length_mm=2.5,
            across_flats_mm=5.0,
            bore_diam_mm=2.7,
            detail~,
          ),
          child_mate="bottom",
          spec=@cad.JointSpec::merge_rigid(),
        )
        // The screws belong to the sensor assembly, so the sensor's own
        // fastener schedule is the single BOM entry for them.
        housing = housing.attach_to(
          name + "_output_sensor",
          "sensor_screw_merge_\{i}",
          parent_mate="bolt_\{i}",
          iso_shcs_screw(
            name="\{name}_sensor_screw_\{i}",
            size=@step_standards.M2_5,
            length_mm=6.0,
            detail~,
          ),
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
          bom_external=false,
        )
      }
    }
  }
  let reduction = planetary_reduction(sun_teeth, planet_teeth, stage_count)
  let efficiency = if stage_count >= 2 { 0.80 } else { 0.90 }
  let output_torque = bldc_rated_torque(p) * reduction * efficiency
  let geared_spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Bldc,
    model="Planetary BLDC " + p.name,
    voltage_v=p.voltage_v,
    current_rated_a=p.current_rated_a,
    current_stall_a=p.current_peak_a,
    torque_rated_nm=output_torque,
    driver=if is_a12 { "moteus C1 / FOC" } else { "VESC / SimpleFOC" },
    interface="CAN",
    encoder=if output_encoder {
      "AS5047P output + rotor encoder"
    } else {
      "rotor encoder (AS5600-class)"
    },
  )
  let mut out = housing
    .with_actuator(geared_spec)
    .with_param("reduction", reduction.to_string())
    .with_param("output_torque_nm", output_torque.to_string())
    .with_param("output_shaft_length_mm", final_shaft_len.to_string())
    .with_param("output_joint", output_joint)
    .with_param("output_encoder", output_encoder.to_string())
    .with_param("output_magnet_pocket", "6.1 mm dia x 2.6 mm deep")
    .with_param("sensor_air_gap_mm", "1.0")
    .with_param("command_joint", rotor_joint)
    .add_fit(
      @cad.Fit::new(
        "output_magnet_pocket",
        @cad.FitClass::Clearance,
        nominal_mm=6.1,
        min_mm=6.1,
        max_mm=6.2,
      ),
    )
  if add_binding {
    out = out.add_control_binding(
      @cad.ControlBinding::new(
        rotor_joint,
        actuator=name + "_motor_stator",
        channel="can0:1",
        gear_ratio=reduction,
        soft_lower=Some(-1000.0),
        soft_upper=Some(1000.0),
      ),
    )
  }
  out
}

///|
/// Builds the actuator's stage-1 gear set as one print-in-place cartridge.
///
/// The 4-elbow herringbone teeth cannot be assembled after printing. Export
/// this single multi-body STEP, print it as one job, and then add the
/// separately printed carrier, bearings, housing, and output hardware.
pub fn planetary_actuator_cartridge(
  name~ : String = "planetary_cartridge",
  preset~ : String = "5010_360kv",
  module_mm~ : Double = 1.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 12,
  planet_count~ : Int32 = 4,
  gear_length_mm~ : Double = 10.0,
  num_elbows~ : Int32 = 4,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Detailed,
) -> @cad.Component {
  let p = resolve_bldc_preset(preset)
  let planet_root = module_mm * (planet_teeth.to_double() / 2.0 - 1.25)
  let use_planet_bearing = planet_root > 9.5
  let planet_bore_radius = if use_planet_bearing { 8.0 } else { 2.0 }
  let params : PlanetaryGearboxParams = {
    gear_module: module_mm,
    gear_length_mm,
    helix_angle_deg: 30.0,
    sun_teeth,
    planet_teeth,
    num_planets: planet_count,
    pressure_angle_deg: 20.0,
    num_elbows,
    resolution: 5,
    bore_radius_mm: if p.name == "A12-8318-100KV" {
      3.5
    } else {
      p.shaft_diameter_mm / 2.0 + 0.1
    },
    planet_bore_radius_mm: planet_bore_radius,
    carrier_pin_diam_mm: if use_planet_bearing {
      8.0
    } else {
      3.8
    },
    carrier_bearing_designation: if use_planet_bearing {
      "688"
    } else {
      ""
    },
    output_shaft_diam_mm: 8.0,
    carrier_thickness_mm: 8.0,
    output_shaft_length_mm: 12.0,
    tolerance_mm: @step_common.DEFAULT_GEAR_TOLERANCE_MM,
    outer_thickness_mm: 6.0,
    include_carrier: false,
  }
  let sun_hole_type = if p.name == "A12-8318-100KV" { "Hexagonal" } else { "" }
  let mut cartridge = planetary_print_in_place(
    name~,
    params~,
    detail~,
    sun_hole_type~,
  )
  // Add four integral anti-rotation key lugs at 45/135/225/315 deg around the
  // outer ring gear so it locks positively into ACT-HOUSING's matching axial
  // keyway slots (zero glue, zero plastic-on-plastic slip).
  let pa_deg = 20.0
  let deg = @math.PI / 180.0
  let center_delta = 0.2
  let ring_outer = module_mm *
    (sun_teeth.to_double() + 2.0 * planet_teeth.to_double()) /
    2.0 +
    module_mm +
    center_delta +
    0.1 / @math.sin(pa_deg * deg) +
    6.0
  let key_width = 6.0
  let key_protrusion = 2.5
  let key_embed = 2.0
  let key_radial_len = key_protrusion + key_embed
  let key_r_center = ring_outer + key_protrusion - key_radial_len / 2.0
  let cart_part = if cartridge.bodies.length() > 0 {
    cartridge.bodies[0].part
  } else {
    None
  }
  for ki in 0..<4 {
    let ang_deg = 45.0 + 90.0 * ki.to_double()
    let ang_rad = ang_deg * deg
    let lug_node = ramped_ring_key_node(
      name + "_ring_key_" + ki.to_string(),
      ring_outer,
      key_embed,
      key_protrusion,
      key_width,
      gear_length_mm,
      ang_deg,
    )
    let lug : @cad.BodyPart = {
      ..@cad.BodyPart::box_mm(
        name + "_ring_key_" + ki.to_string(),
        key_radial_len,
        key_width,
        gear_length_mm,
        x_mm=key_r_center * @math.cos(ang_rad),
        y_mm=key_r_center * @math.sin(ang_rad),
        z_mm=gear_length_mm / 2.0,
        rz_deg=ang_deg,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::grey(),
      ),
      node: lug_node,
    }
    let lug_assigned : @cad.BodyPart = match cart_part {
      Some(pm) => lug.with_part(pm)
      None => lug
    }
    cartridge = cartridge.add_body(lug_assigned)
  }
  cartridge
}

///|
fn translate_arc_circle(
  diam : Double,
  hx : Double,
  hy : Double,
) -> Array[@step_cad.ProfileSegment] {
  @step_gears.arc_circle_segments(diam).map(fn(seg) {
    match seg {
      @step_cad.ProfileSegment::SegmentLine((x0, y0), (x1, y1)) =>
        @step_cad.ProfileSegment::SegmentLine(
          (x0 + hx, y0 + hy),
          (x1 + hx, y1 + hy),
        )
      @step_cad.ProfileSegment::SegmentArc((x0, y0), (x1, y1), (cx, cy)) =>
        @step_cad.ProfileSegment::SegmentArc(
          (x0 + hx, y0 + hy),
          (x1 + hx, y1 + hy),
          (cx + hx, cy + hy),
        )
    }
  })
}

///|
/// Builds a 2D regular hexagon hole contour (across-flats = `2 * apothem`)
/// centered at `(hx, hy)` as six `SegmentLine`s for `ExtrudedArcProfile`.
fn hex_hole_segments(
  apothem : Double,
  hx : Double,
  hy : Double,
) -> Array[@step_cad.ProfileSegment] {
  let r = apothem / @math.cos(@math.PI / 6.0)
  let pts : Array[(Double, Double)] = []
  for i in 0..<6 {
    let a = 2.0 * @math.PI * i.to_double() / 6.0
    pts.push((hx + r * @math.cos(a), hy + r * @math.sin(a)))
  }
  let segs : Array[@step_cad.ProfileSegment] = []
  for i in 0..<6 {
    segs.push(@step_cad.ProfileSegment::SegmentLine(pts[i], pts[(i + 1) % 6]))
  }
  segs
}

///|
/// Builds a 100% all-curved G1-tangent 4-lobe VESA-100 mounting flange outer
/// contour (zero straight edges, zero sharp corners on Layer 1).
fn vesa_flange_outer_segments(
  r_barrel : Double,
  ear_r : Double,
  r_ear : Double,
  r_fillet : Double,
) -> Array[@step_cad.ProfileSegment] {
  let a = r_barrel + r_fillet
  let b = r_ear + r_fillet
  let cos_alpha = (ear_r * ear_r + a * a - b * b) / (2.0 * ear_r * a)
  let alpha = @math.acos(cos_alpha)
  let deg = @math.PI / 180.0
  let segs : Array[@step_cad.ProfileSegment] = []
  let pt_on = fn(r : Double, ang : Double) -> (Double, Double) {
    (r * @math.cos(ang), r * @math.sin(ang))
  }
  for k in 0..<4 {
    let theta_prev = (45.0 + 90.0 * ((k + 3) % 4).to_double()) * deg
    let theta = (45.0 + 90.0 * k.to_double()) * deg
    // 1. Barrel arc from previous lobe's exit tangent to this lobe's entry tangent (CCW).
    let b_start = pt_on(r_barrel, theta_prev + alpha)
    let b_in = pt_on(r_barrel, theta - alpha)
    segs.push(@step_cad.ProfileSegment::SegmentArc(b_start, b_in, (0.0, 0.0)))
    // 2. Entry concave fillet arc (CW around f_in).
    let f_in = pt_on(a, theta - alpha)
    let e_center = pt_on(ear_r, theta)
    let e_in = (
      e_center.0 + r_ear / b * (f_in.0 - e_center.0),
      e_center.1 + r_ear / b * (f_in.1 - e_center.1),
    )
    segs.push(@step_cad.ProfileSegment::SegmentArc(b_in, e_in, f_in))
    // 3. Ear tip convex arc split at the outer apex (two CCW arcs < 180 deg).
    let e_apex = pt_on(ear_r + r_ear, theta)
    let f_out = pt_on(a, theta + alpha)
    let e_out = (
      e_center.0 + r_ear / b * (f_out.0 - e_center.0),
      e_center.1 + r_ear / b * (f_out.1 - e_center.1),
    )
    segs.push(@step_cad.ProfileSegment::SegmentArc(e_in, e_apex, e_center))
    segs.push(@step_cad.ProfileSegment::SegmentArc(e_apex, e_out, e_center))
    // 4. Exit concave fillet arc (CW around f_out).
    let b_out = pt_on(r_barrel, theta + alpha)
    segs.push(@step_cad.ProfileSegment::SegmentArc(e_out, b_out, f_out))
  }
  segs
}

///|
/// Builds one anti-rotation ring-gear key lug with a 45-degree bottom-up
/// lead-in ramp so Layer 1 (`z = 0`) is a pure smooth circle with zero sharp
/// protruding corners, ramping cleanly to full square key width by `z = 2.5 mm`.
fn ramped_ring_key_node(
  name : String,
  ring_outer : Double,
  key_embed : Double,
  key_protrusion : Double,
  key_width : Double,
  gear_length_mm : Double,
  ang_deg : Double,
) -> @step_cad.SceneNode {
  let ramp_z = if key_protrusion < gear_length_mm - 1.0 {
    key_protrusion
  } else {
    gear_length_mm * 0.25
  }
  let prof = @step_cad.ExtrudedProfile::new(
    [
      (ring_outer - key_embed, 0.0),
      (ring_outer, 0.0),
      (ring_outer + key_protrusion, ramp_z),
      (ring_outer + key_protrusion, gear_length_mm),
      (ring_outer - key_embed, gear_length_mm),
    ],
    key_width,
  )
  // Rotate profile from local XY into world (radial X, Z) plane, centered on
  // Y = 0, then swing to `ang_deg` around Z.
  let rad = ang_deg * @math.PI / 180.0
  let half_w = key_width / 2.0
  prof
  .with_name(name)
  .with_color(@step_cad.Rgb::grey())
  .rotate_x(90.0)
  .rotate_z(ang_deg)
  .translate(x=-half_w * @math.sin(rad), y=half_w * @math.cos(rad))
}

///|
/// Convenience factory for the standard integrated low-KV BLDC planetary
/// actuator: a Tier-1 motor, a printed Tier-1 planetary stage, a printed
/// housing, planet bearings, a twin-608 output cartridge, and an optional
/// on-axis output encoder.
///
/// This is the preferred name for new designs; `qdd_actuator_pod` is kept for
/// compatibility with earlier models.
pub fn bldc_actuator_pod(
  name~ : String = "bldc_actuator_pod",
  preset~ : String = "5010_360kv",
  stages~ : Int32 = 1,
  module_mm~ : Double = 1.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 12,
  planet_count~ : Int32 = 4,
  gear_length_mm~ : Double = 10.0,
  gear_type~ : String = "herringbone",
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  planetary_bldc_actuator(
    name~,
    preset~,
    stages~,
    module_mm~,
    sun_teeth~,
    planet_teeth~,
    planet_count~,
    gear_length_mm~,
    gear_type~,
    detail~,
  )
}
