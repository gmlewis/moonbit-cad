///|
/// 02-planetary-actuator
///
/// A NEMA stepper drives the Tier-1 involute planetary gear stage, with a
/// printable adapter flange and individually printable ring, sun, planets, and
/// carrier.

///|
async fn main {
  let base_spec = {
    "module": @cli.opt_double(3.0, help="Gear module (tooth size)"),
    "numTeeth": @cli.opt_int(12, help="Sun gear tooth count"),
    "planetTeeth": @cli.opt_int(12, help="Planet gear tooth count"),
    "numPlanets": @cli.opt_int(3, help="Number of orbiting planets"),
    "gearLength": @cli.opt_double(30.0, help="Face width in mm"),
    "sunAngleDeg": @cli.opt_double(0.0, help="Motor shaft angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="02-planetary-actuator",
      description="Geared NEMA17 plus a Tier-1 involute planetary stage.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let threads = output.thread_rep()
  let stage = @components.planetary_gearset_stage(
    name="planetary_gearbox",
    module_mm=args.double("module"),
    sun_teeth=args.int("numTeeth"),
    planet_teeth=args.int("planetTeeth"),
    planet_count=args.int("numPlanets"),
    face_width_mm=args.double("gearLength"),
    sun_bore_mm=6.0,
    planet_bore_mm=4.0,
    detail~,
  )
  let adapter = @components.flange_plate(
    name="motor_adapter",
    outer_diam_mm=60.0,
    center_bore_mm=22.0,
    thickness_mm=6.0,
    bolt_count=4,
    bolt_circle_mm=44.0,
    detail~,
  )
  let stepper = @components.nema_stepper(detail~, threads?)
  let mut comp = stage
    .attach(
      "adapter_merge",
      parent_mate="input_flange",
      adapter,
      child_mate="bottom",
      spec=@cad.JointSpec::merge_rigid(),
    )
    .attach(
      "motor_flange_joint",
      parent_mate="input_flange",
      stepper,
      child_mate="face_mount",
      spec=@cad.JointSpec::fixed(offset_mm=-10.0),
    )
  for i in 0..<4 {
    let screw = @components.iso_shcs_screw(
      name="adapter_screw_\{i}",
      size=@step_standards.M3,
      length_mm=10.0,
      detail~,
      threads?,
    )
    comp = comp.attach(
      "adapter_screw_merge_\{i}",
      parent_mate="motor_adapter.bolt_\{i}",
      screw,
      child_mate="head_seat",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let angle = args.double("sunAngleDeg") * @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  positions.set("nema17_shaft_joint", angle)
  @common.write_output(comp, output, joint_positions=positions)
}
