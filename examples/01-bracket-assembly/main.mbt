///|
/// 01-bracket-assembly
///
/// A parametric L bracket carries a rigidly merged flange plate, a NEMA
/// stepper, a shaft coupler on the motor rotor, and an output bearing.

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
      description="Parametric mounting bracket and stepper assembly.",
    )
    is Some(args) else {
    return
  }
  let bracket = @cad.l_bracket(width_mm=args.double("bracketWidth"))
  let flange = @cad.flange_plate(name="mount_flange")
  let stepper = @cad.nema_stepper()
  let coupler = @cad.shaft_coupler()
  let bearing = @cad.ball_bearing(name="output_bearing")
  let comp = bracket
    .attach(
      "flange_merge",
      parent_mate="base_mount",
      flange,
      child_mate="bottom",
      spec=@cad.JointSpec::merge_rigid(),
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
      child_mate="bottom",
      spec=@cad.JointSpec::fixed(),
    )
  let positions : Map[String, Double] = Map([])
  positions.set(
    "nema17_shaft_joint",
    args.double("shaftAngleDeg") * @math.PI / 180.0,
  )
  @common.write_output(
    comp,
    @common.output_paths(args),
    joint_positions=positions,
  )
}
