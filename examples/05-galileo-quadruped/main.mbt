///|
/// 05-galileo-quadruped
///
/// The flagship Galileo X wheeled quadruped: a 17-link robot assembled
/// entirely from parametric components. Exports posed STEP, glTF, URDF, or a
/// complete ROS 2 package bundle with per-link meshes and printable parts.

///|
async fn main {
  let base_spec = {
    "bodyLen": @cli.opt_double(520.0, help="Chassis length in mm"),
    "bodyWidth": @cli.opt_double(240.0, help="Chassis width in mm"),
    "thighLen": @cli.opt_double(220.0, help="Thigh link length in mm"),
    "calfLen": @cli.opt_double(220.0, help="Calf link length in mm"),
    "wheelRadius": @cli.opt_double(90.0, help="Wheel radius in mm"),
    "hipDeg": @cli.opt_double(0.0, help="Hip joint angle in degrees"),
    "thighDeg": @cli.opt_double(35.0, help="Thigh joint angle in degrees"),
    "calfDeg": @cli.opt_double(-70.0, help="Calf joint angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="05-galileo-quadruped",
      description="Galileo X wheeled quadruped robot.",
    )
    is Some(args) else {
    return
  }
  let comp = @cad.galileo_quadruped_robot(
    body_len_mm=args.double("bodyLen"),
    body_width_mm=args.double("bodyWidth"),
    thigh_len_mm=args.double("thighLen"),
    calf_len_mm=args.double("calfLen"),
    wheel_radius_mm=args.double("wheelRadius"),
  )
  let hip = args.double("hipDeg") * @math.PI / 180.0
  let thigh = args.double("thighDeg") * @math.PI / 180.0
  let calf = args.double("calfDeg") * @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  for prefix in ["fl", "fr", "rl", "rr"] {
    positions.set("\{prefix}_hip_joint", hip)
    positions.set("\{prefix}_thigh_joint", thigh)
    positions.set("\{prefix}_calf_joint", calf)
  }
  @common.write_output(
    comp,
    @common.output_paths(args),
    joint_positions=positions,
  )
}
