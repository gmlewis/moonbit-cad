///|
/// 04-pan-tilt-turret
///
/// A two-axis pan/tilt camera or lidar turret: a flange base, a NEMA pan
/// motor merged into the base link, a U-bracket clevis, a QDD tilt actuator,
/// and a sensor payload housing.

///|
async fn main {
  let base_spec = {
    "panDeg": @cli.opt_double(30.0, help="Pan angle in degrees"),
    "tiltDeg": @cli.opt_double(-15.0, help="Tilt angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="04-pan-tilt-turret",
      description="Two-axis gimbal pan-tilt camera/lidar turret.",
    )
    is Some(args) else {
    return
  }
  let base = @cad.flange_plate(
    name="turret_base",
    outer_diam_mm=140.0,
    center_bore_mm=30.0,
    bolt_count=6,
  )
  let pan_motor = @cad.nema_stepper(
    name="pan_motor",
    frame_size_mm=57.0,
    body_length_mm=56.0,
    shaft_diam_mm=8.0,
    shaft_length_mm=30.0,
    max_effort_nm=2.0,
  )
  let pan_bracket = @cad.u_bracket(
    name="pan_bracket",
    inner_span_mm=60.0,
    arm_length_mm=50.0,
    width_mm=45.0,
  )
  let tilt = @cad.bldc_actuator_pod(
    name="tilt",
    housing_diam_mm=70.0,
    housing_length_mm=40.0,
    output_diam_mm=42.0,
    output_thickness_mm=6.0,
    reduction=4.0,
  )
  let payload = @cad.Component::new(
      "sensor_payload",
      description="Camera and lidar payload housing",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "camera_housing",
        90.0,
        90.0,
        70.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "lens",
        50.0,
        20.0,
        z_mm=45.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::blue(),
      ),
    )
  let tilt_limit = @urdf.JointLimit::new(
    lower=Some(-1.2),
    upper=Some(1.2),
    effort=30.0,
    velocity=10.0,
  )
  let comp = base
    .attach(
      "pan_motor_mount",
      parent_mate="top",
      pan_motor,
      child_mate="rear_mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
    .attach_to(
      "pan_motor_rotor",
      "pan_bracket_mount",
      parent_mate="shaft_tip",
      pan_bracket,
      child_mate="base_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "pan_bracket",
      "tilt_axis_joint",
      parent_mate="pivot",
      tilt,
      child_mate="rear_mount",
      spec=@cad.JointSpec::revolute(
        tilt_limit,
        transmission_reduction=Some(4.0),
      ),
    )
    .attach_to(
      "tilt_rotor",
      "payload_mount",
      parent_mate="output_flange",
      payload,
      child_mate="origin",
      spec=@cad.JointSpec::fixed(),
    )
  let positions : Map[String, Double] = Map([])
  positions.set(
    "pan_motor_shaft_joint",
    args.double("panDeg") * @math.PI / 180.0,
  )
  positions.set("tilt_axis_joint", args.double("tiltDeg") * @math.PI / 180.0)
  @common.write_output(
    comp,
    @common.output_paths(args),
    joint_positions=positions,
  )
}
