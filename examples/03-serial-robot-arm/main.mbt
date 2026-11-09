///|
/// 03-serial-robot-arm
///
/// A six-axis modular serial arm assembled from flange plates, QDD actuator
/// pods, box-tube links, and a U-bracket wrist gripper.

///|
async fn main {
  let base_spec = {
    "link1Len": @cli.opt_double(250.0, help="Upper arm length in mm"),
    "link2Len": @cli.opt_double(220.0, help="Forearm length in mm"),
    "shoulderDeg": @cli.opt_double(25.0, help="Shoulder angle in degrees"),
    "elbowDeg": @cli.opt_double(-45.0, help="Elbow angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="03-serial-robot-arm",
      description="Six-DOF modular serial robot arm.",
    )
    is Some(args) else {
    return
  }
  let link1_len = args.double("link1Len")
  let link2_len = args.double("link2Len")
  let base = @cad.flange_plate(
    name="base_flange",
    outer_diam_mm=160.0,
    center_bore_mm=40.0,
    bolt_count=6,
  )
  let waist = @cad.bldc_actuator_pod(
    name="waist",
    housing_diam_mm=120.0,
    housing_length_mm=70.0,
    output_diam_mm=80.0,
    output_thickness_mm=12.0,
  )
  let upper_arm = @cad.box_tube_strut(
    "upper_arm",
    width_mm=90.0,
    height_mm=70.0,
    length_mm=link1_len,
  )
  let shoulder = @cad.bldc_actuator_pod(
    name="shoulder",
    housing_diam_mm=96.0,
    housing_length_mm=54.0,
    output_diam_mm=56.0,
    output_thickness_mm=8.0,
  )
  let forearm = @cad.box_tube_strut(
    "forearm",
    width_mm=70.0,
    height_mm=60.0,
    length_mm=link2_len,
  )
  let elbow = @cad.bldc_actuator_pod(
    name="elbow",
    housing_diam_mm=80.0,
    housing_length_mm=48.0,
    output_diam_mm=48.0,
    output_thickness_mm=8.0,
  )
  let wrist_pitch = @cad.bldc_actuator_pod(
    name="wrist_pitch",
    housing_diam_mm=64.0,
    housing_length_mm=40.0,
    output_diam_mm=38.0,
    output_thickness_mm=6.0,
  )
  let wrist_roll = @cad.bldc_actuator_pod(
    name="wrist_roll",
    housing_diam_mm=52.0,
    housing_length_mm=34.0,
    output_diam_mm=32.0,
    output_thickness_mm=6.0,
  )
  let gripper = @cad.u_bracket(
    name="gripper",
    inner_span_mm=70.0,
    arm_length_mm=60.0,
    width_mm=45.0,
  )
  let comp = base
    .attach(
      "waist_mount",
      parent_mate="top",
      waist,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "waist_rotor",
      "upper_arm_mount",
      parent_mate="output_flange",
      upper_arm,
      child_mate="start",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "upper_arm",
      "shoulder_mount",
      parent_mate="end",
      shoulder,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "shoulder_rotor",
      "forearm_mount",
      parent_mate="output_flange",
      forearm,
      child_mate="start",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "forearm",
      "elbow_mount",
      parent_mate="end",
      elbow,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "elbow_rotor",
      "wrist_pitch_mount",
      parent_mate="output_flange",
      wrist_pitch,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "wrist_pitch_rotor",
      "wrist_roll_mount",
      parent_mate="output_flange",
      wrist_roll,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "wrist_roll_rotor",
      "gripper_mount",
      parent_mate="output_flange",
      gripper,
      child_mate="base_mount",
      spec=@cad.JointSpec::fixed(),
    )
  let positions : Map[String, Double] = Map([])
  positions.set("shoulder_joint", args.double("shoulderDeg") * @math.PI / 180.0)
  positions.set("elbow_joint", args.double("elbowDeg") * @math.PI / 180.0)
  @common.write_output(
    comp,
    @common.output_paths(args),
    joint_positions=positions,
  )
}
