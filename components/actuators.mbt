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
) -> @cad.Component {
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
