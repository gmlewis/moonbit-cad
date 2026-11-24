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
/// `components/vendor/20240305-moteus-c1-r1_2.step` is the exact moteus C1 r1.2 controller board
/// from the open-source moteus hardware project. The housed layout imports it
/// as the motor controller and on-axis output sensor: its centered AS5047P chip
/// faces a diameter/height-parameterized magnet on the output shaft across a
/// parameterized air gap. © mjbots and the moteus contributors, Apache-2.0.
/// Upstream:
/// <https://github.com/mjbots/moteus/blob/main/hw/c1/r1.2/20240305-moteus-c1-r1_2.step>.
/// See `examples/02-planetary-actuator/README.md` for the full attribution.

///|
/// Display-only coaxial Z-axis offset for the exploded, color-coded view.
/// Every part moves straight along its real physical assembly axis, with
/// `ACT-HOUSING` anchored at z = 0.
fn explode_offset(node : @step_cad.SceneNode) -> (Double, Double, Double) {
  let name = node.name
  if name.contains("herringbone-planetary") {
    // Print-in-place gear set slides straight up out of the housing keyways.
    (0.0, 0.0, 66.0)
  } else if name.contains("pin_washer") {
    // Inner-race thrust shim washers sit on top of the 688 bearings, right
    // between the bearings (+96 mm) and the carrier plate (+122 mm).
    (0.0, 0.0, 108.0)
  } else if name.contains("bearing-688") {
    (0.0, 0.0, 96.0)
  } else if name.contains("moteus") {
    (0.0, 0.0, 305.0)
  } else if name.contains("board_standoff") {
    (0.0, 0.0, 280.0)
  } else if name.contains("output_magnet") {
    (0.0, 0.0, 265.0)
  } else if name.contains("output_collar") {
    (0.0, 0.0, 250.0)
  } else if name.contains("M3-12") {
    (0.0, 0.0, 235.0)
  } else if name.contains("bearing-608") {
    (0.0, 0.0, 210.0)
  } else if name.contains("output_cover") {
    (0.0, 0.0, 180.0)
  } else if name.contains("carrier_pin") ||
    name.contains("carrier_output_shaft") {
    (0.0, 0.0, 150.0)
  } else if name.contains("stage1_carrier") {
    (0.0, 0.0, 122.0)
  } else if name.contains("stage1_sun") ||
    name.contains("stage1_planet") ||
    name.contains("ring_key") ||
    name.contains("/ring") {
    (0.0, 0.0, 66.0)
  } else if name.contains("rear_insert") {
    (0.0, 0.0, -18.0)
  } else if name.contains("cover_insert") || name.contains("HEATSET") {
    if node.tz < 0.0 {
      (0.0, 0.0, -18.0)
    } else {
      (0.0, 0.0, 14.0)
    }
  } else if name.contains("M4-14") {
    // Four M4x14 screws bolting ACT-ROTOR-ADAPTER down onto the A12 rotor.
    (0.0, 0.0, -14.0)
  } else if name.contains("M3-10") {
    (0.0, 0.0, -145.0)
  } else if name.contains("motor_plate") {
    (0.0, 0.0, -110.0)
  } else if name.contains("_rotor_adapter") {
    (0.0, 0.0, -28.0)
  } else if name.contains("a12_motor_barrel") || name.contains("_housing") {
    // Central housing stays anchored at z = 0.
    (0.0, 0.0, 0.0)
  } else if name.contains("_motor") {
    (0.0, 0.0, -65.0)
  } else {
    (0.0, 0.0, 0.0)
  }
}

///|
/// A distinct display color for each kind of part in the exploded view.
fn explode_color(name : String) -> @step_cad.Rgb {
  if name.contains("output_cover") {
    @step_cad.Rgb::new(0.22, 0.24, 0.30)
  } else if name.contains("housing") || name.contains("internal_chamfer") {
    @step_cad.Rgb::new(0.22, 0.24, 0.28)
  } else if name.contains("motor_plate") {
    @step_cad.Rgb::new(0.35, 0.35, 0.40)
  } else if name.contains("HEATSET") {
    @step_cad.Rgb::new(0.95, 0.75, 0.10)
  } else if name.contains("board_standoff") {
    @step_cad.Rgb::new(0.75, 0.55, 0.20)
  } else if name.contains("M3-10") || name.contains("M4-14") {
    @step_cad.Rgb::new(0.20, 0.45, 0.90)
  } else if name.contains("M3-12") {
    @step_cad.Rgb::new(0.40, 0.75, 0.95)
  } else if name.contains("bearing-608") {
    @step_cad.Rgb::new(0.78, 0.78, 0.82)
  } else if name.contains("bearing-688") {
    @step_cad.Rgb::new(0.45, 0.65, 0.85)
  } else if name.contains("set_screw") {
    @step_cad.Rgb::new(0.60, 0.02, 0.02)
  } else if name.contains("output_collar") {
    @step_cad.Rgb::new(0.95, 0.20, 0.20)
  } else if name.contains("output_magnet") {
    @step_cad.Rgb::new(0.65, 0.20, 0.85)
  } else if name.contains("sun_hub") {
    @step_cad.Rgb::new(0.95, 0.55, 0.15)
  } else if name.contains("/sun") {
    @step_cad.Rgb::new(1.00, 0.68, 0.10)
  } else if name.contains("stage1_planet") {
    @step_cad.Rgb::new(0.15, 0.65, 0.95)
  } else if name.contains("/ring") {
    @step_cad.Rgb::new(0.45, 0.45, 0.50)
  } else if name.contains("carrier_output_shaft") ||
    name.contains("carrier_pin") ||
    name.contains("pin_washer") {
    @step_cad.Rgb::new(0.72, 0.72, 0.78)
  } else if name.contains("stage1_carrier") {
    @step_cad.Rgb::new(0.20, 0.80, 0.40)
  } else if name.contains("motor_rotor_bell") {
    @step_cad.Rgb::new(0.95, 0.35, 0.05)
  } else if name.contains("motor_rotor_shaft") {
    @step_cad.Rgb::new(0.80, 0.80, 0.85)
  } else if name.contains("motor_stator") {
    @step_cad.Rgb::new(0.55, 0.55, 0.60)
  } else if name.contains("moteus") {
    @step_cad.Rgb::new(0.10, 0.60, 0.25)
  } else {
    @step_cad.Rgb::new(0.50, 0.50, 0.55)
  }
}

///|
/// Builds a display-only exploded design from the assembled design.
fn exploded_design(
  design : @step_cad.Design,
  name~ : String,
) -> @step_cad.Design {
  let mut out = @step_cad.Design::new(
    name~,
    description="Exploded, color-coded view",
  )
  for node in design.nodes() {
    let (dx, dy, dz) = explode_offset(node)
    out = out.add(
      node.with_color(explode_color(node.name)).translate(x=dx, y=dy, z=dz),
    )
  }
  out
}

///|
async fn main {
  let base_spec = {
    "motor": @cli.opt_string(
      help="Motor layout: bldc (housed actuator) or exposed (BLDC on an exposed stage); default bldc",
    ),
    "preset": @cli.opt_string(
      help="BLDC preset: a12_8318_100kv, 5010_360kv, 5008_335kv, 5208_180kv, 5065_270kv, 6354_190kv (default a12_8318_100kv)",
    ),
    "gearType": @cli.opt_string(
      help="Gear type: herringbone (swept) or spur (smooth exact arcs); default herringbone",
    ),
    "numElbows": @cli.opt_int(
      4,
      help="Herringbone elbows (4 = print-in-place gear set; 0 = straight)",
    ),
    "stages": @cli.opt_int(
      1,
      help="Housed actuator planetary stages: 1 or 2 (the exposed variant is single-stage)",
    ),
    "module": @cli.opt_double(1.5, help="Gear module (tooth size)"),
    "sunTeeth": @cli.opt_int(12, help="Sun gear tooth count"),
    "planetTeeth": @cli.opt_int(18, help="Planet gear tooth count"),
    "numPlanets": @cli.opt_int(
      4,
      help="Number of orbiting planets (default 4 for load sharing)",
    ),
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
    "explode": @cli.flag(
      help="Write an exploded, color-coded view instead of the assembled STEP",
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
  let explode = args.flag("explode")
  let motor_kind = args.string_opt("motor").unwrap_or("bldc")
  if motor_kind != "bldc" && motor_kind != "exposed" {
    @cli.eprintln(
      "error: --motor must be 'bldc' or 'exposed'; NEMA stepper support was removed",
    )
    abort("")
  }
  let preset = args.string_opt("preset").unwrap_or("a12_8318_100kv")
  let is_a12 = preset == "a12_8318_100kv" || preset == "a12"
  let gear_type = args.string_opt("gearType").unwrap_or("herringbone")
  let num_elbows = args.int("numElbows")
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
    let sun_bore = if is_a12 { 4.5 } else { p.shaft_diameter_mm + 0.2 }
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
      num_elbows~,
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
    let motor_offset = if is_a12 { adapter_drop - 32.0 } else { adapter_drop }
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
        spec=@cad.JointSpec::fixed(offset_mm=motor_offset),
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
      num_elbows~,
      detail~,
      motor_source="brushless",
      // The moteus C1 is the output sensor/controller; there is no separate
      // small PCB on the cover.
      output_sensor="none",
      magnet_diameter_mm~,
      magnet_height_mm~,
    )
    // The 4-elbow herringbone gear set is print-in-place. Mark it so the build
    // package lists one cartridge instead of separate sun/planet/ring files.
    let act = if gear_type != "spur" && num_elbows >= 4 && stages == 1 {
      act.with_param("print_in_place_gearset", "PGB-CARTRIDGE")
    } else {
      act
    }
    // The exact moteus C1 r1.2 board (Apache-2.0, © mjbots). Its AS5047P
    // chip U6 is at the board center on the bottom face; the measured package
    // bottom is 1.2 mm below the board origin and the PCB bottom is 0.8 mm
    // above it.
    // Vendored at components/vendor/20240305-moteus-c1-r1_2.step.
    let board_path = "components/vendor/20240305-moteus-c1-r1_2.step"
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
      unit_cost_usd=69.0,
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
  // Apply the checked-in purchasing links so the build package's BOM,
  // sourcing CSV, and START-HERE guide all point at real products.
  let links_path = "examples/02-planetary-actuator/supplier-links.txt"
  let links_text = @fs.read_file(links_path).text() catch { _ => "" }
  let comp = comp
    .with_supplier_links(@cad.parse_supplier_links(links_text))
    .with_param("exploded_view", "exploded.step")
  @common.write_output(
    comp,
    output,
    joint_positions=positions,
    example_dir="examples/02-planetary-actuator",
  )
  // The 4-elbow herringbone gear set is print-in-place. Add its single
  // cartridge STEP to the build package; the package's START-HERE and
  // print-list replace the separate sun/planet/ring files with this one.
  if motor_kind == "bldc" &&
    gear_type != "spur" &&
    num_elbows >= 4 &&
    stages == 1 {
    match output.build_package {
      Some(dir) => {
        let cartridge = @components.planetary_actuator_cartridge(
          preset~,
          module_mm~,
          sun_teeth~,
          planet_teeth~,
          planet_count~,
          gear_length_mm=gear_length,
          num_elbows~,
          detail~,
        )
        @step_cad.write_text_file(
          @cad.orient_print_design(cartridge.to_design()).to_step_file(),
          Some(dir + "/printable/PGB-CARTRIDGE.step"),
        )
      }
      None => ()
    }
  }
  // Exploded, color-coded view: every purchased part is separated from its
  // neighbors so bearings, inserts, screws, pins, washers, the magnet, and the
  // collar are all visible. The package always gets one; --explode also puts
  // it in the main --out file for `./run-example.sh 02 --view --explode`.
  let exploded_target = match output.build_package {
    Some(dir) => Some(dir + "/exploded.step")
    None =>
      if explode {
        Some("/tmp/02-planetary-actuator-exploded.step")
      } else {
        None
      }
  }
  if exploded_target is Some(_) || explode {
    let exploded = exploded_design(
      comp.to_design(joint_positions=positions),
      name="02-planetary-actuator-exploded",
    )
    let text = exploded.to_step_file()
    match exploded_target {
      Some(path) => @step_cad.write_text_file(text, Some(path))
      None => ()
    }
    if explode {
      match output.step {
        Some(path) => @step_cad.write_text_file(text, Some(path))
        None => ()
      }
    }
  }
}
