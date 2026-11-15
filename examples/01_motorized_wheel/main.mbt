///|
/// 01_motorized_wheel
///
/// A proof-of-concept motorized wheel built from the compact multi-stage
/// `motorized_gearbox` component and the measured tier-1 tire envelope from
/// `../moonbit-17-step`.
///
/// The gearbox casing carries the integrated planetary ring gears, the motor
/// bolts to the casing's motor cap, and the final carrier's output shaft turns
/// in a flanged bearing in the output cap. The tire's 1/2" hub bore rides on
/// the 1/2" output shaft and is clamped between two shaft collars.
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
/// Parses the pipe-separated supplier-link file.
///
/// Format: `part_number | supplier | supplier_url | notes | cost`; blank
/// lines and lines starting with `#` are ignored.
fn parse_supplier_links(text : String) -> Array[@cad.SupplierLink] {
  let out : Array[@cad.SupplierLink] = []
  for raw_line in text.split("\n") {
    let line = raw_line.to_owned().trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    let fields : Array[String] = line
      .split("|")
      .collect()
      .map(fn(field) { field.to_owned().trim().to_owned() })
    if fields.length() < 3 {
      continue
    }
    let cost : Double? = if fields.length() > 4 && fields[4] != "" {
      Some(@string.parse_double(fields[4])) catch {
        _ => None
      }
    } else {
      None
    }
    out.push(
      @cad.SupplierLink::new(
        part_number=fields[0],
        supplier=if fields.length() > 1 { fields[1] } else { "" },
        supplier_url=if fields.length() > 2 { fields[2] } else { "" },
        notes=if fields.length() > 3 { fields[3] } else { "" },
        unit_cost_usd?=cost,
      ),
    )
  }
  out
}

///|
/// Parses a comma-separated double list and extends it to `count` entries by
/// repeating the last value.
fn parse_double_list(
  text : String,
  count : Int32,
  label : String,
) -> Array[Double] {
  let values : Array[Double] = []
  for raw in text.split(",") {
    let item = raw.trim().to_owned()
    if item == "" {
      continue
    }
    values.push(
      @string.parse_double(item) catch {
        _ =>
          abort(
            "error: --" +
            label +
            " expects comma-separated numbers; got '" +
            item +
            "'",
          )
      },
    )
  }
  if values.length() == 0 {
    abort("error: --" + label + " needs at least one value")
  }
  let out : Array[Double] = []
  for i in 0..<count {
    let index = if i < values.length() { i } else { values.length() - 1 }
    out.push(values[index])
  }
  out
}

///|
/// Parses a comma-separated integer list and repeats the last value.
fn parse_int_list(text : String, count : Int32, label : String) -> Array[Int32] {
  let values : Array[Int32] = []
  for raw in text.split(",") {
    let item = raw.trim().to_owned()
    if item == "" {
      continue
    }
    values.push(
      @string.parse_int(item) catch {
        _ =>
          abort(
            "error: --" +
            label +
            " expects comma-separated integers; got '" +
            item +
            "'",
          )
      },
    )
  }
  if values.length() == 0 {
    abort("error: --" + label + " needs at least one value")
  }
  let out : Array[Int32] = []
  for i in 0..<count {
    let index = if i < values.length() { i } else { values.length() - 1 }
    out.push(values[index])
  }
  out
}

///|
/// Parses a comma-separated string list and repeats the last value.
fn parse_string_list(
  text : String,
  count : Int32,
  label : String,
) -> Array[String] {
  let values : Array[String] = []
  for raw in text.split(",") {
    let item = raw.trim().to_owned()
    if item == "" {
      continue
    }
    values.push(item)
  }
  if values.length() == 0 {
    abort("error: --" + label + " needs at least one value")
  }
  let out : Array[String] = []
  for i in 0..<count {
    let index = if i < values.length() { i } else { values.length() - 1 }
    out.push(values[index])
  }
  out
}

///|
/// Display-only offset for the exploded, color-coded view.
fn explode_offset(name : String) -> (Double, Double, Double) {
  let stage_z = if name.contains("_stage1_") {
    0.0
  } else if name.contains("_stage2_") {
    80.0
  } else if name.contains("_stage3_") {
    160.0
  } else {
    0.0
  }
  if name.contains("tire_collar") {
    (0.0, 0.0, 360.0)
  } else if name.contains("tire") {
    (0.0, 0.0, 390.0)
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
    (160.0, 0.0, stage_z)
  } else if name.contains("_sun") {
    (90.0, 0.0, stage_z)
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
  if name.contains("casing") || name.contains("_ring") {
    @step_cad.Rgb::new(0.12, 0.12, 0.14)
  } else if name.contains("motor_cap") {
    @step_cad.Rgb::new(0.22, 0.24, 0.30)
  } else if name.contains("output_cap") {
    @step_cad.Rgb::new(0.28, 0.30, 0.36)
  } else if name.contains("output_hub") {
    @step_cad.Rgb::new(0.95, 0.55, 0.15)
  } else if name.contains("collar") {
    @step_cad.Rgb::new(0.60, 0.02, 0.02)
  } else if name.contains("tire") {
    @step_cad.Rgb::new(0.08, 0.08, 0.08)
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
) -> @step_cad.Design {
  let mut out = @step_cad.Design::new(
    name~,
    description="Exploded, color-coded view",
  )
  for node in design.nodes() {
    let (dx, dy, dz) = explode_offset(node.name)
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
      help="Comma-separated herringbone elbow counts per stage (default 0, straight gears)",
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
      help="Exposed output shaft length beyond the output hub collar in mm (overridden by the tire when fitted)",
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
  let modules = parse_double_list(
    args.string_opt("module").unwrap_or("2.0"),
    stage_count,
    "module",
  )
  let sun_teeth = parse_int_list(
    args.string_opt("sunTeeth").unwrap_or("12"),
    stage_count,
    "sunTeeth",
  )
  let planet_teeth = parse_int_list(
    args.string_opt("planetTeeth").unwrap_or("20"),
    stage_count,
    "planetTeeth",
  )
  let planet_counts = parse_int_list(
    args.string_opt("numPlanets").unwrap_or("4"),
    stage_count,
    "numPlanets",
  )
  let gear_lengths = parse_double_list(
    args.string_opt("gearLength").unwrap_or("10"),
    stage_count,
    "gearLength",
  )
  let elbows = parse_int_list(
    args.string_opt("numElbows").unwrap_or("0"),
    stage_count,
    "numElbows",
  )
  let bearings = parse_string_list(
    args.string_opt("planetBearing").unwrap_or("FR8-2RS"),
    stage_count,
    "planetBearing",
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
      "error: the tire needs the output hub so it can seat on a flat flange; drop --noOutputHub",
    )
    abort("")
  }
  let collar_width = args.double("collarWidth")
  let tire_spec = @step_motion.tire_spec()
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
    // The tire hub slides over the shaft after the output hub collar.
    tire_spec.hub_length_mm + collar_width + 2.0
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
    detail~,
    motor_source=args.string_opt("motorSource").unwrap_or("preset"),
  )
  if include_tire {
    let tire_part = @cad.PartMeta::new(
      "WHEEL-7IN",
      description="7-inch wheel and tire envelope with a 1/2 inch hub bore (measured tier-1 model)",
      supplier="generic",
      material="rubber/TPU tire on a printed hub",
      process="purchased",
      unit_cost_usd=30.0,
    )
    let tire_step = match @step_motion.measured_tire() {
      Ok(comp) => comp
      Err(_) => {
        @cli.eprintln("error: could not build the tier-1 tire envelope")
        abort("")
      }
    }
    let tire = @cad.Component::from_step_component(
      "tire",
      tire_step,
      density=@urdf.Density::kg_per_m3(1100.0),
      part=Some(tire_part),
    )
    let hub_name = gearbox_name + "_output_hub"
    // The tire hub rear face seats on the output hub's clamp collar. The
    // `tire_mount` mate carries the -90 deg frame rotation that maps the
    // tire's +X wheel axis onto the gearbox's +Z output axis.
    assembly = assembly.attach_to(
      hub_name,
      "tire_mount_joint",
      parent_mate="tire_mount",
      tire,
      child_mate="hub-bore",
      spec=@cad.JointSpec::merge_rigid(),
    )
    let tire_collar = @components.shaft_collar(
      name="tire_collar",
      bore_diam_mm=output_shaft_diam,
      outer_diam_mm=args.double("collarOuter"),
      width_mm=collar_width,
      style="set_screw",
      thread_size=@step_standards.M4,
    )
    assembly = assembly.attach_to(
      hub_name,
      "tire_collar_joint",
      parent_mate="output_face",
      tire_collar,
      child_mate="bore",
      spec=@cad.JointSpec::merge_rigid(
        offset_mm=collar_width + tire_spec.hub_length_mm + collar_width / 2.0,
      ),
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
    .with_supplier_links(parse_supplier_links(links_text))
    .with_param("exploded_view", "exploded.step")
  @common.write_output(assembly, output, joint_positions=positions)
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
