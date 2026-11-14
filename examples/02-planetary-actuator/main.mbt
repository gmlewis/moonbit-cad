///|
/// 02-planetary-actuator
///
/// A motorized, printable planetary actuator. The default build is an
/// inexpensive low-KV BLDC outrunner driving a printed herringbone planetary
/// stage inside a printed housing. The sun is clamped to the motor shaft, the
/// planets run on 688 bearings on steel carrier pins, and the carrier output
/// shaft turns in two 608 bearings in a printed cover. An on-axis AS5047P
/// reads a diametrically magnetized magnet on the output shaft, giving absolute
/// joint position for a moteus-style controller.
///
/// `--motor nema` builds a NEMA stepper variant instead.

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
    let designation = if motor_kind.contains("23") {
      "NEMA23"
    } else {
      "NEMA17"
    }
    let (pilot_mm, nema_bolt_mm, nema_hole_mm, nema_shaft_mm) = @components.nema_frame_dims(
      designation,
    )
    let sun_bore = nema_shaft_mm + 0.2
    // A 688 bearing needs a planet root radius above about 9.5 mm.
    let use_planet_bearing = module_mm * (planet_teeth.to_double() / 2.0 - 1.25) >
      9.5
    let planet_bore = if use_planet_bearing { 16.0 } else { sun_bore }
    let stage = @components.planetary_gearset_stage(
      name="planetary_gearbox",
      module_mm~,
      sun_teeth~,
      planet_teeth~,
      planet_count~,
      face_width_mm=gear_length,
      pressure_angle_deg=20.0,
      sun_bore_mm=sun_bore,
      planet_bore_mm=planet_bore,
      carrier_pin_diam_mm=if use_planet_bearing { 8.0 } else { 0.0 },
      carrier_bearing=if use_planet_bearing { "688" } else { "" },
      smooth=gear_type == "spur",
      detail~,
    )
    // The adapter matches the NEMA pilot and bolt pattern, not an arbitrary
    // bolt circle. The motor face sits directly against the adapter, so the
    // shaft reaches the sun and no screws bridge a gap.
    let adapter = @components.flange_plate(
      name="motor_adapter",
      outer_diam_mm=if designation == "NEMA23" { 80.0 } else { 60.0 },
      center_bore_mm=pilot_mm,
      thickness_mm=6.0,
      bolt_count=4,
      bolt_circle_mm=nema_bolt_mm,
      bolt_diam_mm=nema_hole_mm,
    )
    let stepper = @components.nema_stepper(
      name="nema_motor",
      designation~,
      detail~,
    )
    // Drop the adapter and motor together so the planet retaining washers
    // (which sit just below the gear faces) clear the adapter plate.
    let adapter_drop = 1.5
    let mut assembly = stage
      .attach(
        "adapter_merge",
        parent_mate="input_flange",
        adapter,
        child_mate="bottom",
        spec=@cad.JointSpec::merge_rigid(offset_mm=adapter_drop),
      )
      .attach(
        "motor_flange_joint",
        parent_mate="input_flange",
        stepper,
        child_mate="face_mount",
        spec=@cad.JointSpec::fixed(offset_mm=adapter_drop),
      )
    // Clamp the sun onto the NEMA shaft. The motor mount screws are a
    // fastener schedule on the motor; they are not modeled through its solid
    // envelope.
    assembly = assembly.attach_to(
      "planetary_gearbox_sun",
      "nema_sun_hub_merge",
      parent_mate="bottom",
      @components.sun_clamp_hub(
        "nema_sun_hub",
        sun_bore,
        if designation == "NEMA23" {
          14.0
        } else {
          12.0
        },
        4.5,
        detail,
      ),
      child_mate="top",
      spec=@cad.JointSpec::merge_rigid(),
    )
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
    // The actuator carries a flat controller pad on the housing side.
    let controller = @components.pcb_board(
      name="foc_driver",
      // Small enough that all four mounting screws land in the 30 mm-tall
      // housing wall behind the pad.
      length_mm=40.0,
      width_mm=28.0,
      connectors=["power", "can", "motor", "encoder"],
      // The board sits flat on the actuator's printed pad, so it does not need
      // the detailed PCB's underside standoffs.
      detail=@step_common.DetailLevel::Simplified,
    ).add_port(
      @cad.Port::new(
        "encoder",
        @cad.PortKind::Sensor,
        spec="SPI/ABZ, 3.3 V from AS5047P",
      ),
    )
    let mut assembly = act.attach(
      "controller_merge",
      parent_mate="controller_mount",
      controller,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
    // Four M2.5 screws hold the board to the pad; the board's own bolt mates
    // keep them from piling up at one point.
    for i in 0..<4 {
      assembly = assembly.attach_to(
        "foc_driver",
        "controller_screw_merge_\{i}",
        parent_mate="bolt_\{i}",
        @components.iso_shcs_screw(
          name="controller_screw_\{i}",
          size=@step_standards.M2_5,
          length_mm=6.0,
          detail~,
          threads?,
        ),
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
        bom_external=false,
      )
    }
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
    assembly = assembly.add_wire_run(
      @cad.WireRun::new(
        "output_encoder_spi",
        from_component="bldc_actuator_output_sensor",
        from_port="spi",
        to_component="foc_driver",
        to_port="encoder",
        gauge_awg=28,
        length_mm=120.0,
      ),
    )
    assembly = assembly.add_wire_run(
      @cad.WireRun::new(
        "output_encoder_power",
        from_component="bldc_actuator_output_sensor",
        from_port="power",
        to_component="foc_driver",
        to_port="power",
        gauge_awg=28,
        length_mm=120.0,
      ),
    )
    assembly = assembly
      .add_cable_route(
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
      .add_cable_route(
        @cad.CableRoute::new(
          "sensor_harness",
          points=[(0.0, 0.0, 0.0), (10.0, 20.0, 0.0), (40.0, 20.0, 4.0)],
          jacket_diameter_mm=4.0,
          wire_names=["output_encoder_spi", "output_encoder_power"],
          material="PVC",
          from_component="bldc_actuator_output_sensor",
          from_port="spi",
          to_component="foc_driver",
          to_port="encoder",
        ),
      )
    positions.set("bldc_actuator_motor_rotor_joint", motor_angle)
    assembly
  }
  @common.write_output(comp, output, joint_positions=positions)
}
