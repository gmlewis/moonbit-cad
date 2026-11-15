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
/// `--motor exposed` drives the same low-KV BLDC motor into an exposed
/// `planetary_gearset_stage` with no printed housing, useful for viewing or
/// bench testing the gear train. Only low-KV BLDC motors are supported.
///
/// # Third-party asset
///
/// `20240305-moteus-c1-r1_2.step` is the exact moteus C1 r1.2 controller board
/// from the open-source moteus hardware project, vendored as the controller
/// board reference design. © mjbots and the moteus contributors, Apache-2.0.
/// Upstream:
/// <https://github.com/mjbots/moteus/blob/main/hw/c1/r1.2/20240305-moteus-c1-r1_2.step>.
/// See `examples/02-planetary-actuator/README.md` for the full attribution.

///|
async fn main {
  let base_spec = {
    "motor": @cli.opt_string(
      help="Motor layout: bldc (housed actuator) or exposed (BLDC on an exposed stage); default bldc",
    ),
    "preset": @cli.opt_string(
      help="BLDC preset: 5010_360kv, 5008_335kv, 5208_180kv, 5065_270kv, 6354_190kv (default 5010_360kv)",
    ),
    "gearType": @cli.opt_string(
      help="Gear type: herringbone (swept) or spur (smooth exact arcs); default herringbone",
    ),
    "stages": @cli.opt_int(
      1,
      help="Housed actuator planetary stages: 1 or 2 (the exposed variant is single-stage)",
    ),
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
  if motor_kind != "bldc" && motor_kind != "exposed" {
    @cli.eprintln(
      "error: --motor must be 'bldc' or 'exposed'; NEMA stepper support was removed",
    )
    abort("")
  }
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
  let comp = if motor_kind == "exposed" {
    let p = match @components.bldc_preset(preset) {
      Some(p) => p
      None =>
        abort(
          "unknown BLDC preset '\{preset}'; choose one of " +
          @components.bldc_preset_names().join(", "),
        )
    }
    let sun_bore = p.shaft_diameter_mm + 0.2
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
      output_shaft_length_mm=12.0,
      smooth=gear_type == "spur",
      // The exposed bench variant deliberately has no ring housing.
      housing=false,
      detail~,
    )
    // Adapter plate at the BLDC motor's actual mounting circle. The center
    // bore clears the motor's front bearing, which sits in the motor face.
    let bearing_clearance = @components.bldc_front_bearing_outer(preset) + 0.3
    let adapter_bore = if p.shaft_diameter_mm + 2.0 > bearing_clearance {
      p.shaft_diameter_mm + 2.0
    } else {
      bearing_clearance
    }
    let adapter = @components.flange_plate(
      name="motor_adapter",
      outer_diam_mm=p.diameter_mm * 1.2,
      center_bore_mm=adapter_bore,
      thickness_mm=6.0,
      bolt_count=4,
      bolt_circle_mm=p.bolt_circle_mm,
      bolt_diam_mm=p.mount_hole_mm,
    )
    // The measured Tier-1 brushless-motor envelope from
    // `../moonbit-17-step/components/motors`.
    let motor = @components.step_brushless_motor(
      name="bldc_motor",
      preset~,
      detail~,
    )
    // Drop the adapter and motor together so the planet retaining washers
    // clear the adapter plate.
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
        motor,
        child_mate="mount",
        spec=@cad.JointSpec::fixed(offset_mm=adapter_drop),
      )
    // The motor envelope is a purchased solid, so the mounting hardware is a
    // schedule rather than screws modeled through it.
    let m4 = p.mount_hole_mm > 3.5
    let screw_part = @cad.PartMeta::new(
      if m4 {
        "ISO4762-M4x12"
      } else {
        "ISO4762-M3x10"
      },
      description=if m4 {
        "ISO 4762 socket head cap screw M4 x 12 mm"
      } else {
        "ISO 4762 socket head cap screw M3 x 10 mm"
      },
      material="steel",
      process="purchased",
      unit_cost_usd=if m4 { 0.50 } else { 0.35 },
    )
    assembly = assembly.add_fastener(
      @cad.Fastener::new(
        "motor_mount_screws",
        @cad.FastenerKind::Screw,
        thread=if m4 { "M4" } else { "M3" },
        length_mm=if m4 { 12.0 } else { 10.0 },
        engagement_mm=4.0,
        quantity=4,
        torque_nm=if m4 { 2.0 } else { 0.8 },
        references=["bldc_motor"],
        part=Some(screw_part),
      ),
    )
    // Clamp the sun to the BLDC shaft and make the sun follow the rotor.
    let hub_outer = if p.shaft_diameter_mm > 8.0 {
      p.shaft_diameter_mm * 2.0
    } else {
      12.0
    }
    assembly = assembly.attach_to(
      "planetary_gearbox_sun",
      "bldc_sun_hub_merge",
      parent_mate="bottom",
      @components.sun_clamp_hub(
        "bldc_sun_hub", sun_bore, hub_outer, 4.5, detail,
      ),
      child_mate="top",
      spec=@cad.JointSpec::merge_rigid(),
    )
    @components.set_joint_mimic(
      assembly,
      "planetary_gearbox_sun_joint",
      @urdf.JointMimic::new("bldc_motor_rotor_joint", multiplier=1.0),
    )
    assembly = assembly.add_control_binding(
      @cad.ControlBinding::new(
        "bldc_motor_rotor_joint",
        actuator="bldc_motor_stator",
        channel="can0:1",
        gear_ratio=@components.planetary_reduction(sun_teeth, planet_teeth, 1),
        soft_lower=Some(-1000.0),
        soft_upper=Some(1000.0),
      ),
    )
    positions.set("bldc_motor_rotor_joint", motor_angle)
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
      motor_source="brushless",
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
