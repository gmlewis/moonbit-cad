///|
/// 01-bracket-assembly
///
/// A parametric 3D-printable L bracket carries a flange plate, a 2020 T-slot
/// strut, a NEMA stepper, a shaft coupler, and an output bearing.

///|
async fn main {
  let base_spec = {
    "bracketWidth": @cli.opt_double(44.0, help="L bracket width in mm"),
    "shaftAngleDeg": @cli.opt_double(0.0, help="Stepper shaft angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="01-bracket-assembly",
      description="Parametric printable mounting bracket and stepper assembly.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let threads = output.thread_rep()
  let bracket = @components.l_bracket(
    width_mm=args.double("bracketWidth"),
    detail~,
  )
  let flange = @components.flange_plate(
    name="mount_flange",
    outer_diam_mm=44.0,
    bolt_circle_mm=32.0,
    detail~,
  )
  let strut = @components.tslot_extrusion_strut(
    name="frame_rail",
    length_mm=200.0,
    detail~,
  )
  let stepper = @components.nema_stepper(detail~, threads?)
  let coupler = @components.shaft_coupler(detail~)
  let bearing = @components.ball_bearing(
    name="output_bearing",
    designation="608",
    detail~,
  )
  let mut comp = bracket
    .attach(
      "flange_merge",
      parent_mate="base_top",
      flange,
      child_mate="bottom",
      spec=@cad.JointSpec::merge_rigid(),
    )
    .attach(
      "strut_mount",
      parent_mate="base_mount",
      strut,
      child_mate="start",
      spec=@cad.JointSpec::fixed(),
    )
    .attach(
      "stepper_mount",
      parent_mate="wall_mount",
      stepper,
      child_mate="face_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "nema17_rotor",
      "coupler_mount",
      parent_mate="shaft_tip",
      coupler,
      child_mate="input_shaft",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "coupler",
      "bearing_mount",
      parent_mate="output_shaft",
      bearing,
      child_mate="center",
      spec=@cad.JointSpec::fixed(),
    )
  // Four M3 socket head cap screws and nuts on the flange bolt circle.
  for i in 0..<4 {
    let screw = @components.iso_shcs_screw(
      name="flange_screw_\{i}",
      size=@step_standards.M3,
      length_mm=12.0,
      detail~,
      threads?,
    )
    let nut = @components.iso_hex_nut(
      name="flange_nut_\{i}",
      size=@step_standards.M3,
      detail~,
      threads?,
    )
    comp = comp.attach(
      "flange_screw_merge_\{i}",
      parent_mate="mount_flange.bolt_\{i}",
      screw,
      child_mate="head_seat",
      spec=@cad.JointSpec::merge_rigid(),
    )
    comp = comp.attach(
      "flange_nut_merge_\{i}",
      parent_mate="mount_flange.bolt_\{i}",
      nut,
      child_mate="bottom",
      spec=@cad.JointSpec::merge_rigid(offset_mm=6.0),
    )
  }
  let positions : Map[String, Double] = Map([])
  positions.set(
    "nema17_shaft_joint",
    args.double("shaftAngleDeg") * @math.PI / 180.0,
  )
  @common.write_output(comp, output, joint_positions=positions)
}
