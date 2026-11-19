///|
/// Shared parameterized builder and CLI runner for the A12 planetary gearbox
/// subassemblies (`01-motorized-wheel`, `03-hip-joint`, `04-knee-joint`).

///|
/// Configuration for building an A12 planetary gearbox subassembly (with or
/// without the 7-inch tire and with configurable reduction, bearings, and shroud).
pub(all) struct GearboxConfig {
  prog : String
  description : String
  gearbox_name : String
  links_path : String
  num_stages : Int32
  preset : String
  motor_source : String
  modules : String
  sun_teeth : String
  planet_teeth : String
  num_planets : String
  gear_lengths : String
  num_elbows : String
  tolerance_mm : Double
  planet_bearings : String
  casing_wall_mm : Double
  flange_thickness_mm : Double
  flange_extra_mm : Double
  carrier_thickness_mm : Double
  coupling_shaft_mm : Double
  output_bearing : String
  output_free_length_mm : Double
  collar_width_mm : Double
  collar_outer_mm : Double
  no_output_hub : Bool
  no_tire : Bool
  dual_output_bearing : Bool
  tire_mount_flush : Bool
  moteus_shroud : Bool
  motor_deg : Double
}

///|
/// Default configuration helper.
pub fn GearboxConfig::new(
  prog~ : String = "01-motorized-wheel",
  description~ : String = "Compact motorized planetary gearbox.",
  gearbox_name~ : String = "motorized_gearbox",
  links_path~ : String = "examples/01-motorized-wheel/supplier-links.txt",
  num_stages~ : Int32 = 1,
  preset~ : String = "",
  motor_source~ : String = "a12",
  modules~ : String = "2.0",
  sun_teeth~ : String = "12",
  planet_teeth~ : String = "20",
  num_planets~ : String = "4",
  gear_lengths~ : String = "10",
  num_elbows~ : String = "4",
  tolerance_mm~ : Double = 0.2,
  planet_bearings~ : String = "FR8-2RS",
  casing_wall_mm~ : Double = 6.0,
  flange_thickness_mm~ : Double = 6.0,
  flange_extra_mm~ : Double = 8.0,
  carrier_thickness_mm~ : Double = 8.0,
  coupling_shaft_mm~ : Double = 8.0,
  output_bearing~ : String = "FR8-2RS",
  output_free_length_mm~ : Double = 15.0,
  collar_width_mm~ : Double = 11.1,
  collar_outer_mm~ : Double = 25.4,
  no_output_hub~ : Bool = false,
  no_tire~ : Bool = false,
  dual_output_bearing~ : Bool = true,
  tire_mount_flush~ : Bool = true,
  moteus_shroud~ : Bool = true,
  motor_deg~ : Double = 0.0,
) -> GearboxConfig {
  {
    prog,
    description,
    gearbox_name,
    links_path,
    num_stages,
    preset,
    motor_source,
    modules,
    sun_teeth,
    planet_teeth,
    num_planets,
    gear_lengths,
    num_elbows,
    tolerance_mm,
    planet_bearings,
    casing_wall_mm,
    flange_thickness_mm,
    flange_extra_mm,
    carrier_thickness_mm,
    coupling_shaft_mm,
    output_bearing,
    output_free_length_mm,
    collar_width_mm,
    collar_outer_mm,
    no_output_hub,
    no_tire,
    dual_output_bearing,
    tire_mount_flush,
    moteus_shroud,
    motor_deg,
  }
}

///|
/// Builds the assembled `@cad.Component` for `config` (evaluating boolean
/// cutouts once so assembled/exploded STEPs share crisp solids).
pub async fn build_gearbox_component(
  config : GearboxConfig,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> (@cad.Component, Array[@components.MotorizedStageSpec], String, String) {
  build_gearbox_component_with_cache(config, detail~, Map([]))
}

///|
/// Builds the assembled `@cad.Component` for `config` using a shared boolean
/// evaluation cache.
async fn build_gearbox_component_with_cache(
  config : GearboxConfig,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  bool_cache : Map[String, @step_cad.ImportedStep],
) -> (@cad.Component, Array[@components.MotorizedStageSpec], String, String) {
  if config.num_stages < 1 {
    @cli.eprintln("error: --numStages must be at least 1")
    abort("")
  }
  let stage_count = config.num_stages
  let motor_source = config.motor_source
  let preset = if config.preset != "" {
    config.preset
  } else if motor_source == "a12" {
    "a12_8318_100kv"
  } else {
    "5010_360kv"
  }
  let modules = cli_or_abort(
    @cad.parse_double_list(config.modules, stage_count, "module"),
  )
  let sun_teeth = cli_or_abort(
    @cad.parse_int_list(config.sun_teeth, stage_count, "sunTeeth"),
  )
  let planet_teeth = cli_or_abort(
    @cad.parse_int_list(config.planet_teeth, stage_count, "planetTeeth"),
  )
  let planet_counts = cli_or_abort(
    @cad.parse_int_list(config.num_planets, stage_count, "numPlanets"),
  )
  let gear_lengths = cli_or_abort(
    @cad.parse_double_list(config.gear_lengths, stage_count, "gearLength"),
  )
  let elbows = cli_or_abort(
    @cad.parse_int_list(config.num_elbows, stage_count, "numElbows"),
  )
  let bearings = cli_or_abort(
    @cad.parse_string_list(config.planet_bearings, stage_count, "planetBearing"),
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
  let include_tire = !config.no_tire
  if include_tire && config.no_output_hub {
    @cli.eprintln(
      "error: the tire needs the output hub for the printed tire mount's three M4 screws; drop --noOutputHub",
    )
    abort("")
  }
  let tire_spec = @step_motion.tire_spec()
  let mount_spec = @step_motion.tire_mount_spec()
  let tire_mount_insert_hole_mm = 6.0
  let output_shaft_diam = @components.resolve_flanged_bearing(
      config.output_bearing,
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
    0.0
  } else {
    config.output_free_length_mm
  }
  let flush_mount = include_tire && config.tire_mount_flush
  let mut assembly = @components.motorized_gearbox(
    name=config.gearbox_name,
    preset~,
    stages=stage_specs,
    casing_wall_mm=config.casing_wall_mm,
    flange_thickness_mm=config.flange_thickness_mm,
    flange_extra_mm=config.flange_extra_mm,
    carrier_thickness_mm=config.carrier_thickness_mm,
    coupling_shaft_mm=config.coupling_shaft_mm,
    tolerance_mm=config.tolerance_mm,
    output_bearing=config.output_bearing,
    output_free_length_mm=output_free,
    output_collar_width_mm=config.collar_width_mm,
    output_collar_outer_diam_mm=config.collar_outer_mm,
    output_hub=!config.no_output_hub,
    output_hub_diam_mm=if include_tire { 80.0 } else { 60.0 },
    output_hub_thickness_mm=10.0,
    tire_mount_bolt_circle_mm=if include_tire {
      mount_spec.bolt_hole_circle_diameter_mm
    } else {
      0.0
    },
    tire_mount_bolt_count=mount_spec.bolt_hole_count,
    tire_mount_bolt_phase_deg=mount_spec.bolt_hole_phase_deg,
    tire_mount_bolt_hole_mm=tire_mount_insert_hole_mm,
    dual_output_bearing=config.dual_output_bearing,
    tire_mount_flush=flush_mount,
    moteus_shroud=config.moteus_shroud,
    detail~,
    motor_source~,
  )
  let pip_cartridges : Array[String] = []
  for i in 0..<stage_count {
    if stage_specs[i].num_elbows >= 4 {
      pip_cartridges.push("MG-STAGE\{i + 1}-CARTRIDGE")
    }
  }
  if pip_cartridges.length() > 0 {
    assembly = assembly.with_param(
      "print_in_place_gearset",
      pip_cartridges.join(","),
    )
  }
  let hub_name = config.gearbox_name + "_output_hub"
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
    let tire_bolt_phase_deg = mount_spec.bolt_hole_phase_deg
    let tire_bolt_length_mm = 30.0
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
      supplier="in-house",
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
    let nominal_mount = @cad.Component::from_step_component(
      "tire_mount",
      mount_step,
      density=@urdf.Density::carbon_fiber(),
      part=Some(mount_part),
    )
    let eval_body = @cad.BodyPart::imported_step(
      "tire_mount_tire-mount",
      mount_eval,
      source="TIRE-MOUNT-86.3 (OCCT-evaluated)",
      density=@urdf.Density::carbon_fiber(),
      color=@step_cad.Rgb::new(0.68, 0.42, 0.12),
      part=Some(mount_part),
    )
    // Keep the analytical Difference inertial computed before OCCT export.
    let kept_inertial = if nominal_mount.bodies.length() > 0 {
      nominal_mount.bodies[0].inertial
    } else {
      eval_body.inertial
    }
    let mount = {
      ..nominal_mount,
      bodies: [{ ..eval_body, inertial: kept_inertial, }],
    }.attach(
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
  let board_path = "components/vendor/20240305-moteus-c1-r1_2.step"
  let board_text = @fs.read_file(board_path).text() catch {
    _ => {
      @cli.eprintln("error: cannot read " + board_path)
      abort("")
    }
  }
  assembly = assembly.attach_to(
    config.gearbox_name + "_motor_stator",
    "rotor_sensor_merge",
    parent_mate="encoder_mount",
    @components.moteus_c1_board(board_text, name="moteus"),
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let links_text = @fs.read_file(config.links_path).text() catch { _ => "" }
  let evaluated = eval_boolean_component_cached(assembly, bool_cache)
    .with_supplier_links(@cad.parse_supplier_links(links_text))
    .with_param("exploded_view", "exploded.step")
  (evaluated, stage_specs, motor_source, preset)
}

///|
/// Shared CLI entrypoint for gearbox examples (`01`, `03`, `04`).
pub async fn run_gearbox_cli(defaults : GearboxConfig) -> Unit {
  let base_spec = {
    "numStages": @cli.opt_int(
      defaults.num_stages,
      help="Number of planetary stages",
    ),
    "preset": @cli.opt_string(
      help="BLDC preset: 5010_360kv, 5008_335kv, 5208_180kv, 5065_270kv, 6354_190kv",
    ),
    "module": @cli.opt_string(
      help="Comma-separated gear modules per stage (default \{defaults.modules})",
    ),
    "sunTeeth": @cli.opt_string(
      help="Comma-separated sun tooth counts per stage (default \{defaults.sun_teeth})",
    ),
    "planetTeeth": @cli.opt_string(
      help="Comma-separated planet tooth counts per stage (default \{defaults.planet_teeth})",
    ),
    "numPlanets": @cli.opt_string(
      help="Comma-separated planet counts per stage (default \{defaults.num_planets})",
    ),
    "gearLength": @cli.opt_string(
      help="Comma-separated gear face widths in mm per stage (default \{defaults.gear_lengths})",
    ),
    "numElbows": @cli.opt_string(
      help="Comma-separated herringbone elbow counts per stage (default \{defaults.num_elbows}; 0 = straight gears)",
    ),
    "tolerance": @cli.opt_double(
      defaults.tolerance_mm,
      help="Radial/flank printing clearance in mm (e.g. 0.042 for 1Off PETG, 0.25 for IVI PLA)",
    ),
    "planetBearing": @cli.opt_string(
      help="Comma-separated planet bearings per stage (default \{defaults.planet_bearings})",
    ),
    "casingWall": @cli.opt_double(
      defaults.casing_wall_mm,
      help="Minimum radial wall at the integrated ring gear in mm",
    ),
    "flangeThickness": @cli.opt_double(
      defaults.flange_thickness_mm,
      help="Axial thickness of the bolted casing flanges in mm",
    ),
    "flangeExtra": @cli.opt_double(
      defaults.flange_extra_mm,
      help="Radial protrusion of the bolted casing flanges beyond the barrel in mm",
    ),
    "carrierThickness": @cli.opt_double(
      defaults.carrier_thickness_mm,
      help="Carrier plate thickness in mm",
    ),
    "couplingShaft": @cli.opt_double(
      defaults.coupling_shaft_mm,
      help="Intermediate carrier/sun coupling shaft diameter in mm",
    ),
    "outputBearing": @cli.opt_string(
      help="Output bearing designation (default \{defaults.output_bearing})",
    ),
    "outputFree": @cli.opt_double(
      defaults.output_free_length_mm,
      help="Exposed output shaft length beyond the output hub in mm (forced to 0 when the tire is fitted)",
    ),
    "collarWidth": @cli.opt_double(
      defaults.collar_width_mm,
      help="Shaft collar width in mm",
    ),
    "collarOuter": @cli.opt_double(
      defaults.collar_outer_mm,
      help="Shaft collar outside diameter in mm",
    ),
    "noOutputHub": @cli.flag(help="Omit the output bolt-circle hub"),
    "noTire": @cli.flag(
      help="Build the bare gearbox without the tier-1 tire (default for hip/knee joints)",
    ),
    "singleBearing": @cli.flag(
      help="Use a single output bearing instead of twin spaced bearings",
    ),
    "noShroud": @cli.flag(help="Omit the protective rear shroud over moteus C1"),
    "motorSource": @cli.opt_string(
      help="Motor geometry: a12 (measured A12 8318 100KV + housing), preset (compact), or brushless; default \{defaults.motor_source}",
    ),
    "motorDeg": @cli.opt_double(
      defaults.motor_deg,
      help="Motor shaft angle in degrees",
    ),
    "explode": @cli.flag(
      help="Write an exploded, color-coded view instead of the assembled STEP",
    ),
  }
  let spec = with_output_args(base_spec)
  guard @cli.parse(spec, prog=defaults.prog, description=defaults.description)
    is Some(args) else {
    return
  }
  let output = output_paths(args)
  let detail = output.detail_level()
  let cfg : GearboxConfig = {
    ..defaults,
    num_stages: args.int("numStages"),
    preset: args.string_opt("preset").unwrap_or(defaults.preset),
    motor_source: args
    .string_opt("motorSource")
    .unwrap_or(defaults.motor_source),
    modules: args.string_opt("module").unwrap_or(defaults.modules),
    sun_teeth: args.string_opt("sunTeeth").unwrap_or(defaults.sun_teeth),
    planet_teeth: args
    .string_opt("planetTeeth")
    .unwrap_or(defaults.planet_teeth),
    num_planets: args.string_opt("numPlanets").unwrap_or(defaults.num_planets),
    gear_lengths: args.string_opt("gearLength").unwrap_or(defaults.gear_lengths),
    num_elbows: args.string_opt("numElbows").unwrap_or(defaults.num_elbows),
    tolerance_mm: args.double("tolerance"),
    planet_bearings: args
    .string_opt("planetBearing")
    .unwrap_or(defaults.planet_bearings),
    casing_wall_mm: args.double("casingWall"),
    flange_thickness_mm: args.double("flangeThickness"),
    flange_extra_mm: args.double("flangeExtra"),
    carrier_thickness_mm: args.double("carrierThickness"),
    coupling_shaft_mm: args.double("couplingShaft"),
    output_bearing: args
    .string_opt("outputBearing")
    .unwrap_or(defaults.output_bearing),
    output_free_length_mm: args.double("outputFree"),
    collar_width_mm: args.double("collarWidth"),
    collar_outer_mm: args.double("collarOuter"),
    no_output_hub: args.flag("noOutputHub"),
    no_tire: defaults.no_tire || args.flag("noTire"),
    dual_output_bearing: defaults.dual_output_bearing &&
    !args.flag("singleBearing"),
    moteus_shroud: defaults.moteus_shroud && !args.flag("noShroud"),
    motor_deg: args.double("motorDeg"),
  }
  let bool_cache : Map[String, @step_cad.ImportedStep] = Map([])
  let (assembly, stage_specs, motor_source, preset) = build_gearbox_component_with_cache(
    cfg,
    detail~,
    bool_cache,
  )
  let command_joint = assembly.parameters
    .get("command_joint")
    .unwrap_or(cfg.gearbox_name + "_motor_rotor_joint")
  let positions : Map[String, Double] = Map([])
  positions.set(command_joint, cfg.motor_deg * @math.PI / 180.0)
  write_output(
    assembly,
    output,
    joint_positions=positions,
    example_dir="examples/" + cfg.prog,
  )
  match output.build_package {
    Some(dir) =>
      for k in 0..<cfg.num_stages {
        if stage_specs[k].num_elbows >= 4 {
          let raw_cart = @components.motorized_stage_cartridge(
            name=cfg.gearbox_name,
            preset~,
            stages=stage_specs,
            stage_index=k + 1,
            casing_wall_mm=cfg.casing_wall_mm,
            flange_thickness_mm=cfg.flange_thickness_mm,
            flange_extra_mm=cfg.flange_extra_mm,
            carrier_thickness_mm=cfg.carrier_thickness_mm,
            coupling_shaft_mm=cfg.coupling_shaft_mm,
            tolerance_mm=cfg.tolerance_mm,
            motor_source~,
            detail~,
          )
          let cart_comp = eval_boolean_component_cached(raw_cart, bool_cache)
          @step_cad.write_text_file(
            cart_comp.to_design().to_step_file(),
            Some(dir + "/printable/MG-STAGE\{k + 1}-CARTRIDGE.step"),
          )
        }
      }
    None => ()
  }
  let explode = args.flag("explode")
  let exploded_target = match output.build_package {
    Some(dir) => Some(dir + "/exploded.step")
    None =>
      if explode {
        Some("/tmp/\{defaults.prog}-exploded.step")
      } else {
        None
      }
  }
  if exploded_target is Some(_) || explode {
    let exploded = gearbox_exploded_design(
      assembly.to_design(joint_positions=positions),
      name="\{defaults.prog}-exploded",
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
