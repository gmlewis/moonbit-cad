///|
/// 01_motorized_wheel
///
/// A proof-of-concept motorized wheel built from the compact multi-stage
/// `motorized_gearbox` component and the measured tier-1 tire envelope from
/// `../moonbit-17-step`.
///
/// The gearbox casing carries the integrated planetary ring gears, the motor
/// bolts to the casing's motor cap, and the final carrier's output shaft turns
/// in a flanged bearing in the output cap. A printed tire mount
/// (`@step_motion.measured_tire_mount`) bolts to three heat-set inserts in the
/// output hub at a 55.85 mm bolt circle. The purchased budrash 72-107 wheel's
/// plastic hub is drilled with three 4.5 mm holes and bolted to that mount with
/// three M4 x 40 screws; the mount's hub post centers the wheel.
///
/// Stage parameters are comma-separated lists: the first value goes to stage 1,
/// the second to stage 2, and so on. A shorter list repeats its last value.
///
/// ```sh
/// ./run-example.sh 01 --headless
/// ./run-example.sh 01 --numStages 3 --numElbows 0,1,2 --headless
/// ./build-part.sh 1
/// ```

///|
/// Unwraps a shared parser result, aborting with a clean message on failure.
fn[T] cli_or_abort(result : Result[T, String]) -> T {
  match result {
    Ok(value) => value
    Err(message) => abort("error: " + message)
  }
}

///|
/// Prefixes every body name so a multi-body purchased or printed part stays
/// identifiable and moves as one unit in the exploded view.
fn prefix_body_names(comp : @cad.Component, prefix : String) -> @cad.Component {
  let bodies = comp.bodies.map(fn(body) {
    let name = prefix + "_" + body.name
    { ..body, name, node: body.node.with_name(name), }
  })
  { ..comp, bodies, }
}

///|
/// The zero-based stage index of a stage-scoped CAD name, or `-1` when the
/// part does not belong to a planetary stage.
fn stage_index(name : String, stage_count : Int32) -> Int32 {
  for i in 0..<stage_count {
    if name.contains("_stage" + (i + 1).to_string() + "_") {
      return i
    }
  }
  -1
}

///|
/// Display-only offset for the exploded, color-coded view.
///
/// `elbows` holds each stage's herringbone elbow count. A stage with any
/// herringbone sweep (`elbows > 0`) is print-in-place: its sun and planets are
/// captive in the casing's integrated ring, so they keep their assembled
/// position and move with the casing module as one unit.
fn explode_offset(
  name : String,
  elbows : Array[Int32],
) -> (Double, Double, Double) {
  let stage = stage_index(name, elbows.length())
  let stage_z = if stage < 0 { 0.0 } else { stage.to_double() * 80.0 }
  let print_in_place = stage >= 0 && elbows[stage] > 0
  if name.contains("tire_bolt") {
    (0.0, 0.0, 450.0)
  } else if name.contains("tire_mount") || name.contains("tire-mount") {
    (0.0, 0.0, 360.0)
  } else if name.contains("tire") {
    // The purchased wheel is one part: keep its ring, hub, plate, and ribs
    // together instead of letting the carrier prefix split them apart.
    (0.0, 0.0, 420.0)
  } else if name.contains("output_hub_collar") {
    (0.0, 0.0, 330.0)
  } else if name.contains("output_hub") {
    (0.0, 0.0, 300.0)
  } else if name.contains("output_bearing") {
    (0.0, 0.0, 270.0)
  } else if name.contains("output_cap") {
    (0.0, 0.0, 240.0)
  } else if name.contains("motor_cap") {
    (0.0, 0.0, -150.0)
  } else if name.contains("_motor") {
    (0.0, 0.0, -220.0)
  } else if name.contains("planet") {
    if print_in_place && !name.contains("bearing") {
      // A print-in-place planet is captive in the casing's integrated ring.
      (0.0, 0.0, stage_z)
    } else {
      (160.0, 0.0, stage_z)
    }
  } else if name.contains("_sun") {
    if print_in_place {
      // A print-in-place sun is captive in the casing's integrated ring.
      (0.0, 0.0, stage_z)
    } else {
      (90.0, 0.0, stage_z)
    }
  } else if name.contains("carrier") {
    (-150.0, 0.0, stage_z)
  } else if name.contains("insert") || name.contains("screw") {
    (-160.0, 0.0, stage_z + 60.0)
  } else if name.contains("_ring") ||
    name.contains("casing_sleeve") ||
    name.contains("_flange") {
    (0.0, 0.0, stage_z)
  } else {
    (0.0, 0.0, 0.0)
  }
}

///|
/// A distinct display color for each kind of part in the exploded view.
fn explode_color(name : String) -> @step_cad.Rgb {
  if name.contains("tire_bolt") {
    @step_cad.Rgb::new(0.40, 0.75, 0.95)
  } else if name.contains("tire_mount") || name.contains("tire-mount") {
    @step_cad.Rgb::new(0.68, 0.42, 0.12)
  } else if name.contains("tire") {
    @step_cad.Rgb::new(0.08, 0.08, 0.08)
  } else if name.contains("casing") || name.contains("_ring") {
    @step_cad.Rgb::new(0.12, 0.12, 0.14)
  } else if name.contains("motor_cap") {
    @step_cad.Rgb::new(0.22, 0.24, 0.30)
  } else if name.contains("output_cap") {
    @step_cad.Rgb::new(0.28, 0.30, 0.36)
  } else if name.contains("output_hub") {
    @step_cad.Rgb::new(0.95, 0.55, 0.15)
  } else if name.contains("collar") {
    @step_cad.Rgb::new(0.60, 0.02, 0.02)
  } else if name.contains("_sun") {
    @step_cad.Rgb::new(1.00, 0.68, 0.10)
  } else if name.contains("bearing") {
    @step_cad.Rgb::new(0.78, 0.78, 0.82)
  } else if name.contains("planet") {
    @step_cad.Rgb::new(0.15, 0.65, 0.95)
  } else if name.contains("carrier") {
    @step_cad.Rgb::new(0.20, 0.80, 0.40)
  } else if name.contains("insert") {
    @step_cad.Rgb::new(0.95, 0.75, 0.10)
  } else if name.contains("screw") {
    @step_cad.Rgb::new(0.40, 0.75, 0.95)
  } else if name.contains("_motor") {
    @step_cad.Rgb::new(0.55, 0.55, 0.60)
  } else {
    @step_cad.Rgb::new(0.50, 0.50, 0.55)
  }
}

///|
/// Builds a display-only exploded design from the assembled design.
fn exploded_design(
  design : @step_cad.Design,
  name~ : String,
  elbows~ : Array[Int32],
) -> @step_cad.Design {
  let mut out = @step_cad.Design::new(
    name~,
    description="Exploded, color-coded view",
  )
  for node in design.nodes() {
    let (dx, dy, dz) = explode_offset(node.name, elbows)
    out = out.add(
      node.with_color(explode_color(node.name)).translate(x=dx, y=dy, z=dz),
    )
  }
  out
}

///|
async fn main {
  let base_spec = {
    "numStages": @cli.opt_int(2, help="Number of planetary stages"),
    "preset": @cli.opt_string(
      help="BLDC preset: 5010_360kv, 5008_335kv, 5208_180kv, 5065_270kv, 6354_190kv (default 5010_360kv)",
    ),
    "module": @cli.opt_string(
      help="Comma-separated gear modules per stage (default 2.0)",
    ),
    "sunTeeth": @cli.opt_string(
      help="Comma-separated sun tooth counts per stage (default 12)",
    ),
    "planetTeeth": @cli.opt_string(
      help="Comma-separated planet tooth counts per stage (default 20)",
    ),
    "numPlanets": @cli.opt_string(
      help="Comma-separated planet counts per stage (default 4)",
    ),
    "gearLength": @cli.opt_string(
      help="Comma-separated gear face widths in mm per stage (default 10)",
    ),
    "numElbows": @cli.opt_string(
      help="Comma-separated herringbone elbow counts per stage (default 4, print-in-place herringbone; 0 = straight gears)",
    ),
    "planetBearing": @cli.opt_string(
      help="Comma-separated planet bearings per stage (default FR8-2RS)",
    ),
    "casingWall": @cli.opt_double(
      6.0,
      help="Minimum radial wall at the integrated ring gear in mm",
    ),
    "flangeThickness": @cli.opt_double(
      6.0,
      help="Axial thickness of the bolted casing flanges in mm",
    ),
    "flangeExtra": @cli.opt_double(
      8.0,
      help="Radial protrusion of the bolted casing flanges beyond the barrel in mm",
    ),
    "carrierThickness": @cli.opt_double(
      8.0,
      help="Carrier plate thickness in mm",
    ),
    "couplingShaft": @cli.opt_double(
      8.0,
      help="Intermediate carrier/sun coupling shaft diameter in mm",
    ),
    "outputBearing": @cli.opt_string(
      help="Output bearing designation (default FR8-2RS, a 1/2 inch bore)",
    ),
    "outputFree": @cli.opt_double(
      15.0,
      help="Exposed output shaft length beyond the output hub collar in mm (forced to 0 by the tire mount when the tire is fitted)",
    ),
    "collarWidth": @cli.opt_double(
      11.1,
      help="Shaft collar width in mm (default 7/16 in)",
    ),
    "collarOuter": @cli.opt_double(
      25.4,
      help="Shaft collar outside diameter in mm",
    ),
    "noOutputHub": @cli.flag(help="Omit the output bolt-circle hub"),
    "noTire": @cli.flag(help="Build the bare gearbox without the tier-1 tire"),
    "motorSource": @cli.opt_string(
      help="Motor geometry: preset (compact) or brushless (measured tier-1 envelope); default preset",
    ),
    "motorDeg": @cli.opt_double(0.0, help="Motor shaft angle in degrees"),
    "explode": @cli.flag(
      help="Write an exploded, color-coded view instead of the assembled STEP",
    ),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="01_motorized_wheel",
      description="Compact multi-stage motorized gearbox driving a 7-inch wheel.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let num_stages = args.int("numStages")
  if num_stages < 1 {
    @cli.eprintln("error: --numStages must be at least 1")
    abort("")
  }
  let stage_count = num_stages
  let preset = args.string_opt("preset").unwrap_or("5010_360kv")
  let modules = cli_or_abort(
    @cad.parse_double_list(
      args.string_opt("module").unwrap_or("2.0"),
      stage_count,
      "module",
    ),
  )
  let sun_teeth = cli_or_abort(
    @cad.parse_int_list(
      args.string_opt("sunTeeth").unwrap_or("12"),
      stage_count,
      "sunTeeth",
    ),
  )
  let planet_teeth = cli_or_abort(
    @cad.parse_int_list(
      args.string_opt("planetTeeth").unwrap_or("20"),
      stage_count,
      "planetTeeth",
    ),
  )
  let planet_counts = cli_or_abort(
    @cad.parse_int_list(
      args.string_opt("numPlanets").unwrap_or("4"),
      stage_count,
      "numPlanets",
    ),
  )
  let gear_lengths = cli_or_abort(
    @cad.parse_double_list(
      args.string_opt("gearLength").unwrap_or("10"),
      stage_count,
      "gearLength",
    ),
  )
  let elbows = cli_or_abort(
    @cad.parse_int_list(
      args.string_opt("numElbows").unwrap_or("4"),
      stage_count,
      "numElbows",
    ),
  )
  let bearings = cli_or_abort(
    @cad.parse_string_list(
      args.string_opt("planetBearing").unwrap_or("FR8-2RS"),
      stage_count,
      "planetBearing",
    ),
  )
  let stage_specs : Array[@components.MotorizedStageSpec] = []
  for i in 0..<stage_count {
    stage_specs.push(
      @components.MotorizedStageSpec::new(
        module_mm=modules[i],
        sun_teeth=sun_teeth[i],
        planet_teeth=planet_teeth[i],
        planet_count=planet_counts[i],
        gear_length_mm=gear_lengths[i],
        num_elbows=elbows[i],
        planet_bearing=bearings[i],
      ),
    )
  }
  let include_tire = !args.flag("noTire")
  if include_tire && args.flag("noOutputHub") {
    @cli.eprintln(
      "error: the tire needs the output hub for the printed tire mount's three M4 screws; drop --noOutputHub",
    )
    abort("")
  }
  let collar_width = args.double("collarWidth")
  let tire_spec = @step_motion.tire_spec()
  let mount_spec = @step_motion.tire_mount_spec()
  let tire_mount_insert_hole_mm = 6.0
  let output_bearing_name = args
    .string_opt("outputBearing")
    .unwrap_or("FR8-2RS")
  let output_shaft_diam = @components.resolve_flanged_bearing(
      output_bearing_name,
    ).bore_mm
  if include_tire &&
    (output_shaft_diam - tire_spec.hub_bore_diameter_mm).abs() > 0.2 {
    @cli.eprintln(
      "error: the tire's " +
      tire_spec.hub_bore_diameter_mm.to_string() +
      " mm hub bore needs an output shaft of the same diameter; use an output bearing with that bore",
    )
    abort("")
  }
  let output_free = if include_tire {
    // The printed tire mount sits on the output hub collar, so the shaft must
    // not protrude into its solid front plate.
    0.0
  } else {
    args.double("outputFree")
  }
  let gearbox_name = if include_tire {
    "wheel_gearbox"
  } else {
    "motorized_gearbox"
  }
  let mut assembly = @components.motorized_gearbox(
    name=gearbox_name,
    preset~,
    stages=stage_specs,
    casing_wall_mm=args.double("casingWall"),
    flange_thickness_mm=args.double("flangeThickness"),
    flange_extra_mm=args.double("flangeExtra"),
    carrier_thickness_mm=args.double("carrierThickness"),
    coupling_shaft_mm=args.double("couplingShaft"),
    output_bearing=output_bearing_name,
    output_free_length_mm=output_free,
    output_collar_width_mm=collar_width,
    output_collar_outer_diam_mm=args.double("collarOuter"),
    output_hub=!args.flag("noOutputHub"),
    // A 55.85 mm bolt circle needs a hub larger than the old 60 mm flange.
    output_hub_diam_mm=if include_tire { 80.0 } else { 60.0 },
    tire_mount_bolt_circle_mm=if include_tire {
      mount_spec.bolt_hole_circle_diameter_mm
    } else {
      0.0
    },
    tire_mount_bolt_count=mount_spec.bolt_hole_count,
    tire_mount_bolt_phase_deg=mount_spec.bolt_hole_phase_deg,
    tire_mount_bolt_hole_mm=tire_mount_insert_hole_mm,
    detail~,
    motor_source=args.string_opt("motorSource").unwrap_or("preset"),
  )
  let hub_name = gearbox_name + "_output_hub"
  let mut tire_mount_step : @step_common.Component? = None
  if include_tire {
    let tire_part = @cad.PartMeta::new(
      "WHEEL-7IN",
      description="budrash 72-107 7 x 1.5 in wheel and tire with a 1/2 in bore and a 1-3/8 in hard-plastic hub; drill 3 x 4.5 mm holes at 55.85 mm BCD for the printed tire mount",
      supplier="Amazon",
      supplier_url="https://www.amazon.com/budrash-72-107-Replaces-Universal-Utility/dp/B09XMGXFDN",
      material="rubber tire on a hard plastic hub",
      process="purchased",
      unit_cost_usd=9.50,
      notes="2-pack. Drill 3 x 4.5 mm holes in the plastic hub at the printed tire mount's 55.85 mm bolt circle before assembly.",
    )
    let tire_step = match @step_motion.measured_tire() {
      Ok(comp) => comp
      Err(_) => {
        @cli.eprintln("error: could not build the tier-1 tire envelope")
        abort("")
      }
    }
    let tire = prefix_body_names(
      @cad.Component::from_step_component(
        "tire",
        tire_step,
        density=@urdf.Density::kg_per_m3(1100.0),
        part=Some(tire_part),
      ),
      "tire",
    )
    // The purchased wheel is one part. The tire's rib phase and the mount's
    // slot phase are both zero in their local frames, so snapping the wheel's
    // `hub-bore` mate onto the mount's `hub-post` mate seats the ribs in the
    // slots with no twist. Three drilled holes in the wheel's plastic back
    // plate share the mount's 55.85 mm bolt circle and hole phase, and sit
    // in the gaps halfway between the ribs.
    let tire_bolt_phase_deg = mount_spec.bolt_hole_phase_deg
    let tire_bolt_length_mm = 40.0
    let bolt_radius = mount_spec.bolt_hole_circle_diameter_mm / 2.0
    let bolt_plate_x = -(tire_spec.hub_inset_mm + tire_spec.inset_thickness_mm)
    let mut wheel = tire
    for i in 0..<mount_spec.bolt_hole_count {
      let theta = (
          tire_bolt_phase_deg +
          360.0 * i.to_double() / mount_spec.bolt_hole_count.to_double()
        ) *
        @math.PI /
        180.0
      let bolt_name = "tire_bolt_" + i.to_string()
      let screw = prefix_body_names(
        @components.iso_shcs_screw(
          name=bolt_name,
          size=@step_standards.M4,
          length_mm=tire_bolt_length_mm,
          detail~,
        ),
        bolt_name,
      )
      wheel = wheel
        .add_mate_mm_deg(
          bolt_name,
          x=bolt_plate_x,
          y=bolt_radius * @math.cos(theta),
          z=bolt_radius * @math.sin(theta),
          ry_deg=-90.0,
        )
        .attach(
          bolt_name + "_merge",
          parent_mate=bolt_name,
          screw,
          child_mate="head_seat",
          spec=@cad.JointSpec::merge_rigid(),
        )
    }
    let mount_part = @cad.PartMeta::new(
      "TIRE-MOUNT-86.3",
      description="Printed tire mount for the budrash 72-107 wheel; three M4 through-holes at 55.85 mm BCD, six rib slots, and a 12.7 mm hub post",
      material="carbon fiber nylon",
      process="3D print",
      unit_cost_usd=2.50,
    )
    let mount_step = match @step_motion.measured_tire_mount() {
      Ok(comp) => comp
      Err(_) => {
        @cli.eprintln("error: could not build the printed tire mount")
        abort("")
      }
    }
    tire_mount_step = Some(mount_step)
    // The mount is a boolean-cut printed part. Evaluate it with OCCT so the
    // assembled and exploded STEP files show the real through-holes and
    // slots instead of the flat writer's nominal untrimmed booleans, then
    // import the evaluated solid as the component's single body.
    let mount_eval = mount_step.to_step_evaluated() catch {
      @step_cad.CsgEvalError(msg) => {
        @cli.eprintln("error: could not evaluate the tire mount: " + msg)
        abort("")
      }
      _ => {
        @cli.eprintln("error: could not evaluate the tire mount")
        abort("")
      }
    }
    let mount = {
      ..@cad.Component::from_step_component(
        "tire_mount",
        mount_step,
        density=@urdf.Density::carbon_fiber(),
        part=Some(mount_part),
      ),
      bodies: [
        @cad.BodyPart::imported_step(
          "tire_mount_tire-mount",
          mount_eval,
          source="TIRE-MOUNT-86.3 (OCCT-evaluated)",
          density=@urdf.Density::carbon_fiber(),
          color=@step_cad.Rgb::new(0.68, 0.42, 0.12),
          part=Some(mount_part),
        ),
      ],
    }
    // The mount's front plate faces the gearbox; its hub post and rib slots
    // face outboard into the wheel. The wheel snaps onto the hub post with no
    // twist — fins land in the slots and the bolt holes land halfway between
    // fins. The +30 deg mount twist aligns both three-hole patterns with the
    // output hub's heat-set inserts.
    let mount = mount.attach(
      "tire_joint",
      parent_mate="hub-post",
      wheel,
      child_mate="hub-bore",
      spec=@cad.JointSpec::merge_rigid(),
    )
    assembly = assembly.attach_to(
      hub_name,
      "tire_mount_joint",
      parent_mate="tire_mount",
      mount,
      child_mate="front-face",
      spec=@cad.JointSpec::merge_rigid(angle_deg=mount_spec.bolt_hole_phase_deg),
    )
  }
  let command_joint = assembly.parameters
    .get("command_joint")
    .unwrap_or(gearbox_name + "_motor_rotor_joint")
  let positions : Map[String, Double] = Map([])
  positions.set(command_joint, args.double("motorDeg") * @math.PI / 180.0)
  let links_path = "examples/01_motorized_wheel/supplier-links.txt"
  let links_text = @fs.read_file(links_path).text() catch { _ => "" }
  let assembly = assembly
    .with_supplier_links(@cad.parse_supplier_links(links_text))
    .with_param("exploded_view", "exploded.step")
  @common.write_output(assembly, output, joint_positions=positions)
  // The tire mount is a boolean-cut printed part, so replace the nominal
  // printable export with the OCCT-evaluated, watertight solid.
  let print_dir = match output.build_package {
    Some(dir) => Some(dir + "/printable")
    None =>
      match output.print_parts {
        Some(dir) => Some(dir)
        None => None
      }
  }
  match (tire_mount_step, print_dir) {
    (Some(mount_step), Some(dir)) =>
      mount_step.write_step_evaluated(
        Some(dir + "/" + @cad.sanitize_part_number("TIRE-MOUNT-86.3") + ".step"),
      )
    _ => ()
  }
  // The build package always gets an exploded, color-coded view.
  let explode = args.flag("explode")
  let exploded_target = match output.build_package {
    Some(dir) => Some(dir + "/exploded.step")
    None =>
      if explode {
        Some("/tmp/01_motorized_wheel-exploded.step")
      } else {
        None
      }
  }
  if exploded_target is Some(_) || explode {
    let exploded = exploded_design(
      assembly.to_design(joint_positions=positions),
      name="01_motorized_wheel-exploded",
      elbows~,
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
