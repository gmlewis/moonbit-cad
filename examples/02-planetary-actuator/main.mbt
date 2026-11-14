///|
/// 02-planetary-actuator
///
/// A showcase for the Tier-1 planetary gearboxes and motors. The default build
/// is an inexpensive low-KV BLDC outrunner driving a printed herringbone
/// planetary stage inside a printed housing; `--motor nema` builds a NEMA
/// stepper variant instead.

///|
async fn main {
  let base_spec = {
    "motor": @cli.opt_string(
      help="Motor: bldc (low-KV outrunner) or nema (stepper); default bldc",
    ),
    "preset": @cli.opt_string(
      help="BLDC preset: 5010_360kv, 5008_335kv, 5208_180kv, 5065_270kv, 6354_190kv (default 5010_360kv)",
    ),
    "gearType": @cli.opt_string(
      help="Gear type: herringbone (swept) or spur (smooth exact arcs); default herringbone",
    ),
    "stages": @cli.opt_int(1, help="Planetary stages: 1 or 2"),
    "module": @cli.opt_double(1.5, help="Gear module (tooth size)"),
    "sunTeeth": @cli.opt_int(12, help="Sun gear tooth count"),
    "planetTeeth": @cli.opt_int(18, help="Planet gear tooth count"),
    "numPlanets": @cli.opt_int(3, help="Number of orbiting planets"),
    "gearLength": @cli.opt_double(10.0, help="Face width in mm"),
    "motorDeg": @cli.opt_double(0.0, help="Motor shaft angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="02-planetary-actuator",
      description="Low-KV BLDC plus a Tier-1 planetary gearbox actuator module.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let threads = output.thread_rep()
  let motor_kind = args.string_opt("motor").unwrap_or("bldc")
  let preset = args.string_opt("preset").unwrap_or("5010_360kv")
  let gear_type = args.string_opt("gearType").unwrap_or("herringbone")
  let stages = args.int("stages")
  let module_mm = args.double("module")
  let sun_teeth = args.int("sunTeeth")
  let planet_teeth = args.int("planetTeeth")
  let planet_count = args.int("numPlanets")
  let gear_length = args.double("gearLength")
  let deg = @math.PI / 180.0
  let motor_angle = args.double("motorDeg") * deg
  let positions : Map[String, Double] = Map([])
  let comp = if motor_kind.has_prefix("nema") {
    let stage = @components.planetary_gearset_stage(
      name="planetary_gearbox",
      module_mm~,
      sun_teeth~,
      planet_teeth~,
      planet_count~,
      face_width_mm=gear_length,
      pressure_angle_deg=20.0,
      sun_bore_mm=6.0,
      smooth=gear_type == "spur",
      detail~,
    )
    let adapter = @components.flange_plate(
      name="motor_adapter",
      outer_diam_mm=60.0,
      center_bore_mm=22.0,
      thickness_mm=6.0,
      bolt_count=4,
      bolt_circle_mm=44.0,
    )
    let designation = if motor_kind.contains("23") {
      "NEMA23"
    } else {
      "NEMA17"
    }
    let stepper = @components.nema_stepper(
      name="nema_motor",
      designation~,
      detail~,
    )
    let mut assembly = stage
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
      assembly = assembly.attach(
        "adapter_screw_merge_\{i}",
        parent_mate="motor_adapter.bolt_\{i}",
        @components.iso_shcs_screw(
          name="adapter_screw_\{i}",
          size=@step_standards.M3,
          length_mm=10.0,
          detail~,
          threads?,
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
    positions.set("nema_motor_shaft_joint", motor_angle)
    assembly
  } else {
    let act = @components.planetary_bldc_actuator(
      name="bldc_actuator",
      preset~,
      stages~,
      module_mm~,
      sun_teeth~,
      planet_teeth~,
      planet_count~,
      gear_length_mm=gear_length,
      gear_type~,
      detail~,
    )
    let controller = @components.pcb_board(
      name="foc_driver",
      length_mm=45.0,
      width_mm=35.0,
      connectors=["power", "can", "motor", "encoder"],
      detail~,
    )
    let mut assembly = act
      .add_mate_mm_deg("controller_mount", x=40.0, z=gear_length / 2.0)
      .attach(
        "controller_merge",
        parent_mate="controller_mount",
        controller,
        child_mate="mount",
        spec=@cad.JointSpec::merge_rigid(),
      )
    for i in 0..<4 {
      assembly = assembly.attach(
        "controller_standoff_merge_\{i}",
        parent_mate="controller_mount",
        @components.hex_standoff(
          name="controller_standoff_\{i}",
          length_mm=6.0,
          across_flats_mm=5.0,
          bore_diam_mm=2.7,
        ),
        child_mate="bottom",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
    let encoder = @components.magnetic_encoder(name="output_encoder")
    assembly = assembly.attach(
      "encoder_merge",
      parent_mate="output_face",
      encoder,
      child_mate="shaft",
      spec=@cad.JointSpec::merge_rigid(),
    )
    assembly = assembly.add_wire_run(
      @cad.WireRun::new(
        "motor_can",
        from_component="bldc_actuator",
        from_port="can",
        to_component="foc_driver",
        to_port="can",
        gauge_awg=24,
        length_mm=180.0,
      ),
    )
    assembly = assembly.add_cable_route(
      @cad.CableRoute::new(
        "actuator_harness",
        points=[(0.0, 0.0, 0.0), (20.0, 0.0, 0.0), (40.0, 0.0, 4.0)],
        jacket_diameter_mm=6.0,
        wire_names=["motor_can"],
        material="PVC",
        from_component="bldc_actuator",
        from_port="can",
        to_component="foc_driver",
        to_port="can",
      ),
    )
    positions.set("bldc_actuator_motor_rotor_joint", motor_angle)
    assembly
  }
  @common.write_output(comp, output, joint_positions=positions)
}
