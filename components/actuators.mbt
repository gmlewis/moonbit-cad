///|
/// Actuated components: stepper motors, quasi-direct-drive pods, and hub
/// motors. Each actuator is a two-link `@cad.Component` tree whose rotor is
/// connected to the stator by a joint with an optional transmission.
///
/// At `Detailed` and above, shafts come from the STEP motion primitives, and
/// real bearings and mounting screws are merged into the stator.

///|
/// Builds a NEMA-style stepper motor: a rounded stator body, a front boss, a
/// keyed rotor shaft, and four faceplate mounting screws.
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
  // Modern delegation path: use the Tier-1 NEMA motor envelope when a
  // designation is supplied. The custom frame-size path below is kept for
  // odd envelopes and for callers that predate `@step_motors`.
  if designation != "" {
    let mut comp = nema_motor_by_designation(
      name~,
      designation~,
      body_length_mm~,
      detail~,
    )
    if mount_plate {
      comp = comp.attach(
        "mount_plate_merge",
        parent_mate="face_mount",
        nema_mount_plate_part(
          name=name + "_mount_plate",
          designation~,
          width_mm=frame_size_mm * 1.6,
          height_mm=frame_size_mm * 1.6,
          thickness_mm=5.0,
          detail~,
        ),
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
    return comp
  }
  let stator_name = name + "_stator"
  let rotor_name = name + "_rotor"
  let policy = @step_common.DetailPolicy::for_level(detail)
  // `rounded_rect` is anchored at (0, 0); center it so the stator body is
  // concentric with the front boss and the rotor shaft.
  let stator_profile = @step_cad.translate_pts(
    @step_cad.Profile2D::rounded_rect(
      frame_size_mm,
      frame_size_mm,
      2.0,
      segments=policy.circle_segments,
    ),
    -frame_size_mm / 2.0,
    -frame_size_mm / 2.0,
  )
  let mount_offset = frame_size_mm * 0.365
  let mut stator = @cad.Component::new(
      stator_name,
      description="NEMA stepper stator",
    )
    .with_param("frame_size_mm", frame_size_mm.to_string())
    .with_param("body_length_mm", body_length_mm.to_string())
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        stator_name + "_body",
        stator_profile,
        body_length_mm,
        z_mm=-body_length_mm / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        stator_name + "_boss",
        boss_diam_mm,
        boss_height_mm,
        z_mm=boss_height_mm / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_mate_mm_deg("face_mount")
    .add_mate_mm_deg("rear_mount", z=-body_length_mm)
    .add_mate_mm_deg("shaft_base", z=boss_height_mm)
  let mount_points : Array[(Double, Double)] = [
    (mount_offset, mount_offset),
    (-mount_offset, mount_offset),
    (-mount_offset, -mount_offset),
    (mount_offset, -mount_offset),
  ]
  for i, (x, y) in mount_points {
    stator = stator.add_mate_mm_deg("mount_hole_\{i}", x~, y~)
  }
  let rotor_bodies = if !detail_is_rich(detail) {
    [
      @cad.BodyPart::cylinder_mm(
        rotor_name + "_shaft",
        shaft_diam_mm,
        shaft_length_mm,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ),
    ]
  } else {
    let keyed = expect_step(
      "keyed shaft",
      @step_motion.keyed_shaft(
        shaft_diam_mm,
        shaft_length_mm,
        shaft_diam_mm * 0.3,
        shaft_diam_mm * 0.15,
        segments=policy.circle_segments,
      ),
    )
    @cad.BodyPart::from_step_component(
      keyed,
      density=@urdf.Density::steel_mild(),
      z_mm=-shaft_length_mm / 2.0,
    )
  }
  let rotor = @cad.Component::new(rotor_name, description="NEMA stepper rotor")
    .with_param("shaft_diam_mm", shaft_diam_mm.to_string())
    .with_param("shaft_length_mm", shaft_length_mm.to_string())
    .add_bodies(rotor_bodies)
    .add_mate_mm_deg("base", z=-shaft_length_mm / 2.0)
    .add_mate_mm_deg("shaft_tip", z=shaft_length_mm / 2.0)
  if detail_is_rich(detail) {
    let mount_screw_length = 8.0
    for i in 0..<4 {
      stator = stator.attach(
        "mount_screw_\{i}",
        parent_mate="mount_hole_\{i}",
        iso_shcs_screw(
          name="mount_screw_\{i}",
          size=@step_standards.M3,
          length_mm=mount_screw_length,
          detail~,
          threads?,
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
  }
  let part = purchased_part(
    "NEMA-\{frame_size_mm}",
    "NEMA stepper \{frame_size_mm} mm",
    "mixed",
    12.0,
    supplier_url="https://www.omc-stepperonline.com/",
  )
  let nema_small_frame_mm = 25.0
  let small_rated_current_a = 0.6
  let large_rated_current_a = 1.5
  let stall_factor = 1.25
  let rated_current_a = if frame_size_mm <= nema_small_frame_mm {
    small_rated_current_a
  } else {
    large_rated_current_a
  }
  let spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Stepper,
    model="NEMA " + frame_size_mm.to_string(),
    voltage_v=24.0,
    current_rated_a=rated_current_a,
    current_stall_a=rated_current_a * stall_factor,
    torque_rated_nm=max_effort_nm,
    driver="A4988",
    interface="STEP/DIR",
    encoder="none",
  )
  stator
  .with_actuator(spec)
  .add_port(
    @cad.Port::new(
      "power",
      @cad.PortKind::Power,
      spec="24 V, " + rated_current_a.to_string() + " A",
    ),
  )
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
  .with_part(part)
}

///|
/// Builds a quasi-direct-drive (QDD) robotic joint module with a housing, a
/// mounting flange, an internal bearing, and a rotating output horn.
pub fn bldc_actuator_pod(
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
  let policy = @step_common.DetailPolicy::for_level(detail)
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
        segments=policy.circle_segments,
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
  let policy = @step_common.DetailPolicy::for_level(detail)
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
        segments=policy.circle_segments,
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
        bearing_designation: "608",
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
        bearing_designation: "608",
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
        bearing_designation: "6000",
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
        bearing_designation: "6001",
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
        bearing_designation: "6002",
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
) -> @cad.Component {
  let p = resolve_bldc_preset(preset)
  let policy = @step_common.DetailPolicy::for_level(detail)
  let stator_name = name + "_stator"
  let rotor_name = name + "_rotor"
  let rotor_joint = name + "_rotor_joint"
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
        segments=policy.circle_segments,
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
  // Rear sensor/encoder boss and mounting bolt circle.
  stator = stator.add_body(
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
    for i in 0..<2 {
      let bearing = ball_bearing(
        name="\{stator_name}_bearing_\{i}",
        designation=p.bearing_designation,
        detail~,
        density=@urdf.Density::steel_mild(),
      )
      stator = stator.attach(
        "bearing_merge_\{i}",
        parent_mate="front_face",
        bearing,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      let insert = heat_set_insert(
        name="\{stator_name}_insert_\{i}",
        outer_diam_mm=4.5,
        inner_diam_mm=3.0,
        length_mm=6.0,
      )
      stator = stator.attach(
        "insert_merge_\{i}",
        parent_mate="mount_hole_\{i}",
        insert,
        child_mate="seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
      let _ = theta
    }
  }
  let rotor_part = purchased_part(
    "BLDC-ROTOR-\{p.name}",
    "Low-KV BLDC rotor \{p.name}",
    "mixed",
    0.0,
  )
  let mut rotor = @cad.Component::new(
      rotor_name,
      description="Low-KV BLDC rotor",
    )
    .with_param("shaft_diameter_mm", p.shaft_diameter_mm.to_string())
    .with_param("shaft_length_mm", p.shaft_length_mm.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        rotor_name + "_shaft",
        p.shaft_diameter_mm,
        p.shaft_length_mm,
        z_mm=p.shaft_length_mm / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(rotor_part),
    )
  if detail_is_rich(detail) {
    rotor = rotor
      .add_body(
        @cad.BodyPart::tube_mm(
          rotor_name + "_bell",
          p.diameter_mm,
          p.diameter_mm - 2.0 * bell_wall,
          p.body_length_mm - 8.0,
          segments=policy.circle_segments,
          z_mm=-p.body_length_mm / 2.0 - 2.0,
          density=@urdf.Density::aluminum_6061(),
          color=@step_cad.Rgb::black(),
        ).with_part(rotor_part),
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          rotor_name + "_sensor_magnet",
          8.0,
          2.0,
          z_mm=-p.body_length_mm - 1.0,
          density=@urdf.Density::kg_per_m3(5000.0),
          color=@step_cad.Rgb::purple(),
        ).with_part(rotor_part),
      )
  }
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
    encoder="AS5600",
  )
  stator
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
fn set_joint_mimic(
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
/// Builds an integrated planetary BLDC actuator: an inexpensive low-KV BLDC
/// outrunner driving a printed Tier-1 planetary gearbox inside a printed
/// housing with a rear motor plate, heat-set inserts, output bearings, and a
/// bolted output carrier.
///
/// `stages = 1` gives a ~5:1–9:1 reduction; `stages = 2` compounds it to
/// ~16:1–25:1 for a motorized wheelchair drive. The motor rotor is the
/// command input and the gearbox sun mimics it, so one continuous joint drives
/// the whole train.
pub fn planetary_bldc_actuator(
  name~ : String = "bldc_actuator",
  preset~ : String = "5010_360kv",
  stages~ : Int32 = 1,
  module_mm~ : Double = 1.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 12,
  planet_count~ : Int32 = 3,
  gear_length_mm~ : Double = 10.0,
  gear_type~ : String = "herringbone",
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let _ = threads
  let p = resolve_bldc_preset(preset)
  let stage_count = if stages < 1 { 1 } else { stages }
  // Simplified actuators use exact line/arc gears for fast simulation meshes;
  // herringbone sweeps are reserved for detailed and fully modeled builds.
  let smooth = gear_type == "spur" || !detail_is_rich(detail)
  let motor = low_kv_bldc_motor(name=name + "_motor", preset~, detail~)
  let rotor_joint = name + "_motor_rotor_joint"
  let motor_plate_mm = 6.0
  let housing_wall = 4.0
  let first = pgb_build(
    name + "_stage1",
    {
      gear_module: module_mm,
      gear_length_mm,
      helix_angle_deg: 30.0,
      sun_teeth,
      planet_teeth,
      num_planets: planet_count,
      pressure_angle_deg: 20.0,
      num_elbows: 2,
      resolution: 5,
      bore_radius_mm: p.shaft_diameter_mm / 2.0,
      tolerance_mm: 0.1,
      outer_thickness_mm: 6.0,
      include_carrier: true,
    },
    smooth,
    detail,
    false,
  )
  let ring_outer = module_mm *
    (sun_teeth.to_double() + 2.0 * planet_teeth.to_double()) /
    2.0 +
    module_mm +
    6.0
  let housing_part = fabricated_part(
    "ACT-HOUSING", "Printed planetary actuator housing", "carbon fiber nylon", "3D print",
    18.0,
  )
  let plate_part = fabricated_part(
    "ACT-MOTOR-PLATE", "Rear motor mounting plate", "carbon fiber nylon", "3D print",
    10.0,
  )
  let mut housing = @cad.Component::new(
      name,
      description="Planetary BLDC actuator",
    )
    .with_param("preset", p.name)
    .with_param("stages", stage_count.to_string())
    .with_param("module_mm", module_mm.to_string())
    .with_param("reduction_per_stage", gear_type)
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_motor_plate",
        p.diameter_mm * 1.18,
        if p.shaft_diameter_mm * 1.8 > 8.0 {
          p.shaft_diameter_mm * 1.8
        } else {
          8.0
        },
        motor_plate_mm,
        z_mm=-motor_plate_mm / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::black(),
      ).with_part(plate_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_housing",
        (ring_outer + housing_wall) * 2.0,
        (ring_outer + 0.5) * 2.0,
        gear_length_mm * stage_count.to_double() + 2.0 * motor_plate_mm,
        z_mm=gear_length_mm * stage_count.to_double() / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::black(),
      ).with_part(housing_part),
    )
    .add_mate_mm_deg(
      "motor_mount",
      z=-motor_plate_mm - 4.0,
      axis=(0.0, 0.0, -1.0),
    )
    .add_mate_mm_deg("gearbox_mount")
    .add_mate_mm_deg("output_face", z=gear_length_mm * stage_count.to_double())
    .add_mate_mm_deg(
      "output_flange",
      z=gear_length_mm * stage_count.to_double(),
    )
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
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  if detail_is_rich(detail) {
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      let insert = heat_set_insert(
        name="\{name}_insert_\{i}",
        outer_diam_mm=4.5,
        inner_diam_mm=3.0,
        length_mm=6.0,
      )
      housing = housing
        .add_mate_mm_deg(
          "cover_hole_\{i}",
          x=p.diameter_mm * 0.45 * @math.cos(theta),
          y=p.diameter_mm * 0.45 * @math.sin(theta),
          z=-motor_plate_mm,
        )
        .attach(
          "insert_merge_\{i}",
          parent_mate="cover_hole_\{i}",
          insert,
          child_mate="seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
    for i in 0..<2 {
      let bearing = ball_bearing(
        name="\{name}_output_bearing_\{i}",
        designation="6002",
        detail~,
        density=@urdf.Density::steel_mild(),
      )
      housing = housing.attach(
        "output_bearing_merge_\{i}",
        parent_mate="output_face",
        bearing,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(offset_mm=6.0),
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
    spec=@cad.JointSpec::merge_rigid(offset_mm=motor_plate_mm + 1.0),
  )
  set_joint_mimic(
    housing,
    name + "_stage1_sun_joint",
    @urdf.JointMimic::new(rotor_joint, multiplier=1.0),
  )
  let mut output_joint = name + "_stage1_carrier_joint"
  let mut output_carrier = name + "_stage1_carrier"
  let per_stage = 1.0 +
    (sun_teeth.to_double() + 2.0 * planet_teeth.to_double()) /
    sun_teeth.to_double()
  if stage_count >= 2 {
    let second = pgb_build(
      name + "_stage2",
      {
        gear_module: module_mm,
        gear_length_mm,
        helix_angle_deg: 30.0,
        sun_teeth,
        planet_teeth,
        num_planets: planet_count,
        pressure_angle_deg: 20.0,
        num_elbows: 2,
        resolution: 5,
        bore_radius_mm: p.shaft_diameter_mm / 2.0,
        tolerance_mm: 0.1,
        outer_thickness_mm: 6.0,
        include_carrier: true,
      },
      smooth,
      detail,
      false,
    )
    housing = housing
      .add_mate_mm_deg(
        "stage2_mount",
        z=motor_plate_mm +
          1.0 +
          gear_length_mm +
          pgb_carrier_thickness_mm +
          pgb_output_boss_mm +
          4.0,
      )
      .attach(
        "stage2_mount_merge",
        parent_mate="stage2_mount",
        second,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(offset_mm=1.0),
      )
    set_joint_mimic(
      housing,
      name + "_stage2_sun_joint",
      @urdf.JointMimic::new(output_joint, multiplier=1.0),
    )
    output_joint = name + "_stage2_carrier_joint"
    output_carrier = name + "_stage2_carrier"
  }
  let reduction = if stage_count >= 2 {
    per_stage * per_stage
  } else {
    per_stage
  }
  let efficiency = if stage_count >= 2 { 0.80 } else { 0.90 }
  let output_torque = bldc_rated_torque(p) * reduction * efficiency
  if detail_is_rich(detail) {
    // A rear magnetic encoder reads the rotor magnet.
    let encoder = magnetic_encoder(name=name + "_encoder", detail~)
    housing = housing.attach(
      "encoder_merge",
      parent_mate="rear",
      encoder,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(offset_mm=-(motor_plate_mm + 14.0)),
    )
    // A set-screw collar retains the output carrier's shaft.
    let collar = shaft_collar(
      name=name + "_output_collar",
      bore_diam_mm=p.shaft_diameter_mm,
      outer_diam_mm=p.shaft_diameter_mm * 2.0,
      width_mm=8.0,
      style="set_screw",
      detail~,
    )
    housing = housing.attach_to(
      output_carrier,
      "output_collar_merge",
      parent_mate="output_shaft",
      collar,
      child_mate="bore",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let geared_spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Bldc,
    model="Planetary BLDC " + p.name,
    voltage_v=p.voltage_v,
    current_rated_a=p.current_rated_a,
    current_stall_a=p.current_peak_a,
    torque_rated_nm=output_torque,
    driver="VESC / SimpleFOC",
    interface="CAN",
    encoder="AS5600",
  )
  housing
  .with_actuator(geared_spec)
  .with_param("reduction", reduction.to_string())
  .with_param("output_torque_nm", output_torque.to_string())
  .add_control_binding(
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

///|
/// Builds a NEMA stepper motor from the Tier-1 `@step_motors` primitive.
///
/// This is the modern delegation path for NEMA17/NEMA23; the legacy
/// `nema_stepper` builder is kept for its custom frame sizes and body lengths.
pub fn nema_motor_by_designation(
  name~ : String = "nema_motor",
  designation~ : String = "NEMA17",
  body_length_mm~ : Double = 40.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let step_comp = expect_step(
    "NEMA stepper motor",
    @step_motors.nema_motor_by_designation(designation, body_length_mm, detail~),
  )
  let frame = expect_step("NEMA frame", @step_motors.nema_frame(designation))
  let stator_part = purchased_part(
    "NEMA-\{frame.designation}",
    "NEMA stepper \{frame.designation}",
    "mixed",
    12.0,
    supplier_url="https://www.omc-stepperonline.com/",
  )
  let stator = @cad.Component::from_step_layer(
    name + "_stator",
    step_comp,
    "body",
    density=@urdf.Density::steel_mild(),
    part=Some(stator_part),
  )
  let pilot = @cad.Component::from_step_layer(
    name + "_pilot",
    step_comp,
    "pilot-boss",
    density=@urdf.Density::aluminum_6061(),
  )
  let rotor = @cad.Component::from_step_layer(
    name + "_rotor",
    step_comp,
    "shaft",
    density=@urdf.Density::steel_mild(),
    apply_placement=false,
  )
  stator
  .add_bodies(pilot.bodies)
  .add_mate_mm_deg("face_mount", z=body_length_mm)
  .add_mate_mm_deg("rear_mount")
  .attach(
    "\{name}_shaft_joint",
    parent_mate="face_mount",
    rotor,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=0.45, velocity=30.0)),
      transmission_reduction=Some(1.0),
    ),
    bom_external=false,
  )
  .with_part(stator_part)
}
