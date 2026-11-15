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
/// from the open-source moteus hardware project. The housed layout imports it
/// as the motor controller and on-axis output sensor: its centered AS5047P chip
/// faces a diameter/height-parameterized magnet on the output shaft across a
/// parameterized air gap. © mjbots and the moteus contributors, Apache-2.0.
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
    "magnetDiam": @cli.opt_double(
      6.0,
      help="Output encoder magnet diameter in mm",
    ),
    "magnetHeight": @cli.opt_double(
      2.5,
      help="Output encoder magnet height in mm",
    ),
    "sensorGap": @cli.opt_double(
      2.7,
      help="Air gap between the AS5047P chip and the magnet top in mm",
    ),
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
  let magnet_diameter_mm = args.double("magnetDiam")
  let magnet_height_mm = args.double("magnetHeight")
  let sensor_gap_mm = args.double("sensorGap")
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
      // The moteus C1 is the output sensor/controller; there is no separate
      // small PCB on the cover.
      output_sensor="none",
      magnet_diameter_mm~,
      magnet_height_mm~,
    )
    // The exact moteus C1 r1.2 board (Apache-2.0, © mjbots). Its AS5047P
    // chip U6 is at the board center on the bottom face; the measured package
    // bottom is 1.2 mm below the board origin and the PCB bottom is 0.8 mm
    // above it.
    // Vendored at examples/02-planetary-actuator/20240305-moteus-c1-r1_2.step.
    let board_path = "examples/02-planetary-actuator/20240305-moteus-c1-r1_2.step"
    let board_data = @fs.read_file(board_path) catch {
      _ => {
        @cli.eprintln("error: cannot read " + board_path)
        abort("")
      }
    }
    let board_text = board_data.text() catch {
      _ => {
        @cli.eprintln("error: cannot decode " + board_path + " as text")
        abort("")
      }
    }
    let magnet_top_z = match act.get_mate("output_shaft") {
      Some(mate) => mate.placement.apply_point((0.0, 0.0, 0.0)).2
      None => abort("error: actuator has no output_shaft mate")
    }
    let sensor_base_z = match act.get_mate("sensor_base") {
      Some(mate) => mate.placement.apply_point((0.0, 0.0, 0.0)).2
      None => abort("error: actuator has no sensor_base mate")
    }
    // Put the chip bottom `sensor_gap_mm` above the magnet top. With the board
    // rotated +90 deg about X, local +Y is world +Z and local -Y (the chip
    // side) faces the magnet.
    let board_z = magnet_top_z + sensor_gap_mm + 1.2
    let board_pcb_bottom_z = board_z + 0.8
    let standoff_length_mm = board_pcb_bottom_z - sensor_base_z
    let board_part = @cad.PartMeta::new(
      "MOTEUS-C1-R1.2",
      description="moteus C1 r1.2 controller board",
      supplier="mjbots",
      supplier_url="https://github.com/mjbots/moteus",
      material="FR-4",
      process="purchased",
      unit_cost_usd=99.0,
    )
    let board_screw_part = @cad.PartMeta::new(
      "ISO4762-M3x10",
      description="ISO 4762 socket head cap screw M3 x 10 mm",
      material="steel",
      process="purchased",
      unit_cost_usd=0.35,
    )
    let standoff_part = @cad.PartMeta::new(
      "STANDOFF-M3-SENSOR",
      description="M3 tapped hex standoff 5 mm AF x " +
        @step_cad.fmt_double(standoff_length_mm, Some(0.1)) +
        " mm",
      material="brass",
      process="purchased",
      unit_cost_usd=1.2,
    )
    let mut board = @cad.Component::new(
        "moteus_c1",
        description="moteus C1 r1.2 controller and on-axis output sensor",
      )
      .add_body(
        @cad.BodyPart::imported_step(
          "moteus_c1_body",
          board_text,
          source=board_path,
          density=@urdf.Density::g_per_cm3(1.85),
          color=@step_cad.Rgb::green(),
          part=Some(board_part),
          z_mm=board_z,
          rx_deg=90.0,
        ),
      )
      .add_port(
        @cad.Port::new("power", @cad.PortKind::Power, spec="24 V, 15 A"),
      )
      .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
      .add_port(@cad.Port::new("motor", @cad.PortKind::Power, spec="3-phase"))
      .add_port(
        @cad.Port::new(
          "encoder",
          @cad.PortKind::Sensor,
          spec="On-board AS5047P, SPI/ABZ",
        ),
      )
      .with_sensor(
        @cad.SensorSpec::new(
          @cad.SensorKind::Encoder,
          model="AS5047P",
          interface="SPI/ABZ",
          voltage_v=3.3,
          current_ma=15.0,
          range="360 deg",
          resolution="14-bit (0.022 deg)",
        ),
      )
      .add_fastener(
        @cad.Fastener::new(
          "board_mount_screws",
          @cad.FastenerKind::Screw,
          thread="M3",
          length_mm=10.0,
          engagement_mm=4.0,
          quantity=4,
          torque_nm=0.6,
          references=["moteus_c1_body"],
          part=Some(board_screw_part),
        ),
      )
    // Four M3 tapped standoffs reach from the cover-plate top to the board's
    // 6 mm corner holes. They are outside the cover boss and the board's edge
    // components, so the chip can sit close to the magnet.
    for i in 0..<4 {
      let sx = if i % 2 == 0 { 16.0 } else { -16.0 }
      let sy = if i < 2 { -16.0 } else { 16.0 }
      board = board.add_body(
        @cad.BodyPart::tube_mm(
          "board_standoff_\{i}",
          5.77,
          2.5,
          standoff_length_mm,
          x_mm=sx,
          y_mm=sy,
          z_mm=(sensor_base_z + board_pcb_bottom_z) / 2.0,
          density=@urdf.Density::g_per_cm3(8.5),
          color=@step_cad.Rgb::grey(),
        ).with_part(standoff_part),
      )
    }
    // Reusing the sensor-mount frame keeps the attach snap an identity.
    let sensor_mount = match act.get_mate("sensor_mount") {
      Some(mate) => mate
      None => {
        @cli.eprintln("error: actuator has no sensor_mount mate")
        abort("")
      }
    }
    board = board.add_mate({ ..sensor_mount, name: "mount", })
    let mut assembly = act.attach(
      "sensor_merge",
      parent_mate="sensor_mount",
      board,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
    assembly = assembly.add_wire_run(
      @cad.WireRun::new(
        "motor_can",
        from_component="bldc_actuator",
        from_port="can",
        to_component="moteus_c1",
        to_port="can",
        gauge_awg=24,
        length_mm=180.0,
      ),
    )
    assembly = assembly.add_wire_run(
      @cad.WireRun::new(
        "motor_phases",
        from_component="bldc_actuator_motor_stator",
        from_port="phases",
        to_component="moteus_c1",
        to_port="motor",
        gauge_awg=16,
        length_mm=120.0,
      ),
    )
    assembly = assembly
      .add_cable_route(
        @cad.CableRoute::new(
          "actuator_harness",
          points=[(0.0, 0.0, 0.0), (20.0, 0.0, 40.0), (40.0, 0.0, 44.0)],
          jacket_diameter_mm=6.0,
          wire_names=["motor_can"],
          material="PVC",
          from_component="bldc_actuator",
          from_port="can",
          to_component="moteus_c1",
          to_port="can",
        ),
      )
      .add_cable_route(
        @cad.CableRoute::new(
          "motor_phase_harness",
          points=[(0.0, 0.0, 0.0), (12.0, 0.0, 36.0), (30.0, 0.0, 44.0)],
          jacket_diameter_mm=5.0,
          wire_names=["motor_phases"],
          material="PVC",
          from_component="bldc_actuator_motor_stator",
          from_port="phases",
          to_component="moteus_c1",
          to_port="motor",
        ),
      )
    positions.set("bldc_actuator_motor_rotor_joint", motor_angle)
    assembly
  }
  @common.write_output(comp, output, joint_positions=positions)
}
