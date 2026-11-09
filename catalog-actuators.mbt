///|
/// Actuated catalog components: stepper motors, quasi-direct-drive pods, and
/// hub motors. Each actuator is a two-link `Component` tree whose rotor is
/// connected to the stator by a joint with an optional transmission.

///|
/// Builds a NEMA-style stepper motor: a rounded stator body, a front boss, and
/// a rotating shaft.
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
) -> Component {
  let stator_name = name + "_stator"
  let rotor_name = name + "_rotor"
  let stator_profile = @step_cad.Profile2D::rounded_rect(
    frame_size_mm, frame_size_mm, 2.0,
  )
  let stator = Component::new(stator_name, description="NEMA stepper stator")
    .with_param("frame_size_mm", frame_size_mm.to_string())
    .with_param("body_length_mm", body_length_mm.to_string())
    .add_body(
      BodyPart::extruded_profile_mm(
        stator_name + "_body",
        stator_profile,
        body_length_mm,
        z_mm=-body_length_mm / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_body(
      BodyPart::cylinder_mm(
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
  let rotor = Component::new(rotor_name, description="NEMA stepper rotor")
    .with_param("shaft_diam_mm", shaft_diam_mm.to_string())
    .with_param("shaft_length_mm", shaft_length_mm.to_string())
    .add_body(
      BodyPart::cylinder_mm(
        rotor_name + "_shaft",
        shaft_diam_mm,
        shaft_length_mm,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_mate_mm_deg("base", z=-shaft_length_mm / 2.0)
    .add_mate_mm_deg("shaft_tip", z=shaft_length_mm / 2.0)
  stator.attach(
    "\{name}_shaft_joint",
    parent_mate="shaft_base",
    rotor,
    child_mate="base",
    spec=JointSpec::continuous(
      limit=Some(
        @urdf.JointLimit::new(effort=max_effort_nm, velocity=max_vel_rad_s),
      ),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
      transmission_reduction=Some(1.0),
    ),
  )
}

///|
/// Builds a quasi-direct-drive (QDD) robotic joint module with a housing, a
/// mounting flange, and a rotating output horn.
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
) -> Component {
  let rotor_name = name + "_rotor"
  let flange_thickness = 5.0
  let stator = Component::new(name, description="QDD actuator stator")
    .with_param("housing_diam_mm", housing_diam_mm.to_string())
    .with_param("housing_length_mm", housing_length_mm.to_string())
    .with_param("reduction", reduction.to_string())
    .add_body(
      BodyPart::cylinder_mm(
        name + "_housing",
        housing_diam_mm,
        housing_length_mm,
        density=@urdf.Density::aluminum_6061(),
        color~,
      ),
    )
    .add_body(
      BodyPart::tube_mm(
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
  let rotor = Component::new(rotor_name, description="QDD actuator rotor")
    .with_param("output_diam_mm", output_diam_mm.to_string())
    .add_body(
      BodyPart::cylinder_mm(
        rotor_name + "_horn",
        output_diam_mm,
        output_thickness_mm,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_mate_mm_deg("base", z=-output_thickness_mm / 2.0)
    .add_mate_mm_deg("output_flange", z=output_thickness_mm / 2.0)
  stator.attach(
    "\{name}_joint",
    parent_mate="bearing_seat",
    rotor,
    child_mate="base",
    spec=JointSpec::revolute(
      @urdf.JointLimit::new(
        lower=Some(lower_rad),
        upper=Some(upper_rad),
        effort=max_effort_nm,
        velocity=max_vel_rad_s,
      ),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.4, friction=0.08)),
      transmission_reduction=Some(reduction),
    ),
  )
}

///|
/// Builds a hub-motor wheel: a stator axle hub plus a rotating aluminum rim
/// with a TPU tire.
pub fn hub_motor_assembly(
  name~ : String = "hub_motor",
  stator_diam_mm~ : Double = 70.0,
  stator_width_mm~ : Double = 36.0,
  tire_diam_mm~ : Double = 140.0,
  tire_width_mm~ : Double = 46.0,
  max_effort_nm~ : Double = 18.0,
  max_vel_rad_s~ : Double = 30.0,
) -> Component {
  let wheel_name = name + "_wheel"
  let rim_diam = tire_diam_mm * 0.65
  let hub = Component::new(name, description="Hub motor stator")
    .with_param("stator_diam_mm", stator_diam_mm.to_string())
    .with_param("stator_width_mm", stator_width_mm.to_string())
    .add_body(
      BodyPart::cylinder_mm(
        name + "_hub",
        stator_diam_mm,
        stator_width_mm,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_mate_mm_deg("axle")
    .add_mate_mm_deg("mount", z=-stator_width_mm / 2.0)
  let wheel = Component::new(wheel_name, description="Hub motor wheel")
    .with_param("tire_diam_mm", tire_diam_mm.to_string())
    .with_param("tire_width_mm", tire_width_mm.to_string())
    .add_body(
      BodyPart::tube_mm(
        wheel_name + "_rim",
        rim_diam,
        stator_diam_mm * 0.5,
        tire_width_mm,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_body(
      BodyPart::tube_mm(
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
  hub.attach(
    "\{name}_spin_joint",
    parent_mate="axle",
    wheel,
    child_mate="spin",
    spec=JointSpec::continuous(
      limit=Some(
        @urdf.JointLimit::new(effort=max_effort_nm, velocity=max_vel_rad_s),
      ),
      transmission_reduction=Some(1.0),
    ),
  )
}
