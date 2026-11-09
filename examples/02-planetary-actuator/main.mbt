///|
/// 02-planetary-actuator
///
/// A NEMA stepper drives a herringbone planetary gearbox with mimic-coupled
/// planets and an output carrier.

///|
async fn main {
  let base_spec = {
    "module": @cli.opt_double(3.0, help="Gear module (tooth size)"),
    "numTeeth": @cli.opt_int(12, help="Sun gear tooth count"),
    "numPlanets": @cli.opt_int(3, help="Number of orbiting planets"),
    "gearLength": @cli.opt_double(30.0, help="Gear length in mm"),
    "sunAngleDeg": @cli.opt_double(0.0, help="Sun gear angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="02-planetary-actuator",
      description="Geared NEMA17 plus herringbone planetary gearbox.",
    )
    is Some(args) else {
    return
  }
  let base_params = @catalog.PlanetaryGearboxParams::default()
  let params : @catalog.PlanetaryGearboxParams = {
    ..base_params,
    gear_module: args.double("module"),
    sun_teeth: args.int("numTeeth"),
    num_planets: args.int("numPlanets"),
    gear_length_mm: args.double("gearLength"),
  }
  let gearbox = @catalog.planetary_gearbox(params~)
  let stepper = @catalog.nema_stepper()
  let comp = gearbox.attach(
    "motor_flange_joint",
    parent_mate="input_flange",
    stepper,
    child_mate="face_mount",
    spec=@cad.JointSpec::fixed(),
  )
  let angle = args.double("sunAngleDeg") * @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  positions.set("planetary_gearbox_sun_joint", angle)
  positions.set("nema17_shaft_joint", angle)
  @common.write_output(
    comp,
    @common.output_paths(args),
    joint_positions=positions,
  )
}
