///|
/// Shared output destinations and export flags for the showcase examples.
///
/// Each example builds its own geometry options, calls `with_output_args` to
/// add the standard export flags, then calls `write_output` with the assembled
/// `Component`.

///|
pub(all) struct OutputPaths {
  step : String?
  assembly : String?
  eval : String?
  gltf : String?
  bpy : String?
  blender : String?
  blend : String?
  urdf : String?
  bundle : String?
  bom : String?
  plan : String?
  report : String?
  control : String?
  pins : String?
  build_package : String?
  print_parts : String?
  posed_parts : String?
  detail : String
  threads : String
  check : Bool
  collisions : Bool
  validate : Bool
  validate_meshes : Bool
}

///|
/// Returns true when a design contains boolean or edge-feature nodes that the
/// flat STEP writer cannot trim.
fn design_has_boolean(design : @step_cad.Design) -> Bool {
  let mut found = false
  for node in design.nodes() {
    match node.shape {
      @step_cad.Shape::Union(_)
      | @step_cad.Shape::Difference(_)
      | @step_cad.Shape::Fillet(_)
      | @step_cad.Shape::Chamfer(_) => found = true
      _ => ()
    }
  }
  found
}

///|
/// Writes one printable part. Parts whose geometry is a boolean or edge
/// feature are OCCT-evaluated so the printed STEP carries the trimmed solid;
/// if OCCT is unavailable the nominal export is written with a warning.
async fn write_print_part(design : @step_cad.Design, path : String) -> Unit {
  if design_has_boolean(design) {
    let evaluated = Some(design.to_step_evaluated()) catch { _ => None }
    match evaluated {
      Some(text) => {
        @step_cad.write_text_file(text, Some(path))
        return
      }
      None =>
        @cli.eprintln(
          "warning: OCCT evaluation failed for " +
          path +
          "; writing the nominal boolean instead",
        )
    }
  }
  @step_cad.write_text_file(design.to_step_file(), Some(path))
}

///|
/// Adds the standard output options to an example's argument spec.
pub fn with_output_args(spec : Map[String, @cli.Arg]) -> Map[String, @cli.Arg] {
  spec.set(
    "out",
    @cli.opt_string(
      short='o',
      help="Write flat STEP file to path ('-' for stdout)",
    ),
  )
  spec.set(
    "assembly",
    @cli.opt_string(help="Write hierarchical assembly STEP file to path"),
  )
  spec.set(
    "eval",
    @cli.opt_string(help="Write OCCT boolean-evaluated STEP file to path"),
  )
  spec.set(
    "gltf",
    @cli.opt_string(help="Write posed Z-up glTF 2.0 file to path"),
  )
  spec.set(
    "bpy",
    @cli.opt_string(help="Write Blender 5.0 Python script to path"),
  )
  spec.set(
    "blender",
    @cli.opt_string(help="Write Blender 5.0 Python script to path"),
  )
  spec.set(
    "blend",
    @cli.opt_string(help="Create .blend file via Blender CLI at path"),
  )
  spec.set(
    "urdf",
    @cli.opt_string(
      short='u',
      help="Write URDF XML file to path ('-' for stdout)",
    ),
  )
  spec.set(
    "bundle",
    @cli.opt_string(
      short='b',
      help="Write ROS 2 URDF bundle (with .gltf, .step, and printable parts) to directory",
    ),
  )
  spec.set(
    "bom",
    @cli.opt_string(help="Write bill-of-materials CSV to path ('-' for stdout)"),
  )
  spec.set(
    "plan",
    @cli.opt_string(help="Write ordered assembly plan to path ('-' for stdout)"),
  )
  spec.set(
    "report",
    @cli.opt_string(
      help="Write power/IO/wiring report to path ('-' for stdout)",
    ),
  )
  spec.set(
    "control",
    @cli.opt_string(help="Write ros2_control YAML to path ('-' for stdout)"),
  )
  spec.set(
    "pins",
    @cli.opt_string(help="Write firmware pin-map CSV to path ('-' for stdout)"),
  )
  spec.set(
    "package",
    @cli.opt_string(
      help="Write the complete build package (BOM, sourcing, printable STEP parts, control, URDF bundle) to a directory",
    ),
  )
  spec.set(
    "posed-parts",
    @cli.opt_string(
      help="Write world-posed per-link STEP files for interference analysis to directory",
    ),
  )
  spec.set(
    "print-parts",
    @cli.opt_string(
      help="Write standalone 3D-printable STEP parts and print-list.csv to directory",
    ),
  )
  spec.set(
    "detail",
    @cli.opt_string(
      help="Geometry detail level: simplified, detailed, or fully-modeled",
    ),
  )
  spec.set(
    "threads",
    @cli.opt_string(help="Thread mode override: none, cosmetic, or helical"),
  )
  spec.set(
    "check",
    @cli.flag(help="Print assembly/hardware warnings to stderr"),
  )
  spec.set(
    "collisions",
    @cli.flag(help="Analyze placed parts for unintended overlaps"),
  )
  spec.set(
    "validate",
    @cli.flag(
      help="Run scripts/validate_step.py --no-mesh and validate_urdf.py on the generated STEP and URDF",
    ),
  )
  spec.set(
    "validate-meshes",
    @cli.flag(
      help="With --validate, also check the URDF bundle meshes (requires --bundle)",
    ),
  )
  spec
}

///|
/// Collects the standard output values from parsed arguments.
pub fn output_paths(args : @cli.Args) -> OutputPaths {
  {
    step: args.string_opt("out"),
    assembly: args.string_opt("assembly"),
    eval: args.string_opt("eval"),
    gltf: args.string_opt("gltf"),
    bpy: args.string_opt("bpy"),
    blender: args.string_opt("blender"),
    blend: args.string_opt("blend"),
    urdf: args.string_opt("urdf"),
    bundle: args.string_opt("bundle"),
    bom: args.string_opt("bom"),
    plan: args.string_opt("plan"),
    report: args.string_opt("report"),
    control: args.string_opt("control"),
    pins: args.string_opt("pins"),
    build_package: args.string_opt("package"),
    print_parts: args.string_opt("print-parts"),
    posed_parts: args.string_opt("posed-parts"),
    detail: args.string_opt("detail").unwrap_or("simplified"),
    threads: args.string_opt("threads").unwrap_or(""),
    check: args.flag("check"),
    collisions: args.flag("collisions"),
    validate: args.flag("validate"),
    validate_meshes: args.flag("validate-meshes"),
  }
}

///|
/// Parses the `--detail` flag, aborting on an invalid value.
pub fn OutputPaths::detail_level(
  self : OutputPaths,
) -> @step_common.DetailLevel {
  match @cad.parse_detail_level(self.detail) {
    Some(level) => level
    None =>
      abort(
        "error: invalid --detail '" +
        self.detail +
        "' (expected simplified, detailed, or fully-modeled)",
      )
  }
}

///|
/// Parses the `--threads` flag, returning `None` when it was not given.
pub fn OutputPaths::thread_rep(
  self : OutputPaths,
) -> @step_common.ThreadRepresentation? {
  if self.threads == "" {
    return None
  }
  match @cad.parse_thread_rep(self.threads) {
    Some(rep) => Some(rep)
    None =>
      abort(
        "error: invalid --threads '" +
        self.threads +
        "' (expected none, cosmetic, or helical)",
      )
  }
}

///|
fn any_output(output : OutputPaths) -> Bool {
  output.step is Some(_) ||
  output.assembly is Some(_) ||
  output.eval is Some(_) ||
  output.gltf is Some(_) ||
  output.bpy is Some(_) ||
  output.blender is Some(_) ||
  output.blend is Some(_) ||
  output.urdf is Some(_) ||
  output.bundle is Some(_) ||
  output.bom is Some(_) ||
  output.plan is Some(_) ||
  output.report is Some(_) ||
  output.control is Some(_) ||
  output.pins is Some(_) ||
  output.build_package is Some(_) ||
  output.print_parts is Some(_) ||
  output.posed_parts is Some(_) ||
  output.collisions ||
  output.validate ||
  output.validate_meshes
}

///|
fn stdout_path(path : String?) -> String? {
  match path {
    Some(p) => if p == "-" { None } else { Some(p) }
    None => None
  }
}

///|
/// Validates the component's robot, then writes every requested output.
pub async fn write_output(
  comp : @cad.Component,
  output : OutputPaths,
  joint_positions~ : Map[String, Double] = Map([]),
) -> Unit {
  let robot = comp.to_robot()
  if robot.has_errors() {
    for diagnostic in robot.diagnostics() {
      if diagnostic.severity().is_error() {
        @cli.eprintln("error: " + diagnostic.message())
      }
    }
    abort("")
  }
  if output.collisions {
    let reports = comp.collision_reports(joint_positions~)
    let mut collisions = 0
    let mut contacts = 0
    let mut fits = 0
    let mut indeterminate = 0
    for report in reports {
      match report.kind {
        @step_collision.CollisionKind::Collision => {
          collisions = collisions + 1
          @cli.eprintln("collision: " + report.summary())
        }
        @step_collision.CollisionKind::Contact => contacts = contacts + 1
        @step_collision.CollisionKind::InterferenceFit => fits = fits + 1
        @step_collision.CollisionKind::Indeterminate => {
          indeterminate = indeterminate + 1
          @cli.eprintln("indeterminate: " + report.summary())
        }
        @step_collision.CollisionKind::Clearance => ()
      }
    }
    @cli.eprintln(
      "collision analysis: " +
      collisions.to_string() +
      " collision(s), " +
      contacts.to_string() +
      " contact(s), " +
      fits.to_string() +
      " declared fit(s), " +
      indeterminate.to_string() +
      " indeterminate",
    )
  }
  if output.check {
    let warnings = comp.assembly_checks()
    for warning in warnings {
      @cli.eprintln("warning: " + warning)
    }
    let control_warnings = comp.control_checks()
    for warning in control_warnings {
      @cli.eprintln("warning: " + warning)
    }
    let harness_warnings = comp.harness_checks()
    for warning in harness_warnings {
      @cli.eprintln("warning: " + warning)
    }
    let wiring_warnings = comp.wiring_checks()
    for warning in wiring_warnings {
      @cli.eprintln("warning: " + warning)
    }
    @cli.eprintln(
      "hardware checks: " +
      (warnings.length() +
      control_warnings.length() +
      harness_warnings.length() +
      wiring_warnings.length()).to_string() +
      " warning(s)",
    )
  }
  if !any_output(output) {
    if output.collisions {
      let reports = comp.collision_reports(joint_positions~)
      let mut collisions = 0
      let mut contacts = 0
      let mut fits = 0
      let mut indeterminate = 0
      for report in reports {
        match report.kind {
          @step_collision.CollisionKind::Collision => {
            collisions = collisions + 1
            @cli.eprintln("collision: " + report.summary())
          }
          @step_collision.CollisionKind::Contact => contacts = contacts + 1
          @step_collision.CollisionKind::InterferenceFit => fits = fits + 1
          @step_collision.CollisionKind::Indeterminate => {
            indeterminate = indeterminate + 1
            @cli.eprintln("indeterminate: " + report.summary())
          }
          @step_collision.CollisionKind::Clearance => ()
        }
      }
      @cli.eprintln(
        "collision analysis: " +
        collisions.to_string() +
        " collision(s), " +
        contacts.to_string() +
        " contact(s), " +
        fits.to_string() +
        " declared fit(s), " +
        indeterminate.to_string() +
        " indeterminate",
      )
    }
    if output.check {
      return
    }
    comp.to_design(joint_positions~).write_step_file(None)
    return
  }
  let design = comp.to_design(joint_positions~)
  match output.step {
    Some(_) => design.write_step_file(stdout_path(output.step))
    None => ()
  }
  match output.assembly {
    Some(_) =>
      @step_cad.write_text_file(
        design.to_assembly_step(assembly_name=comp.display_name()),
        stdout_path(output.assembly),
      )
    None => ()
  }
  match output.eval {
    Some(path) => design.write_step_evaluated(Some(path))
    None => ()
  }
  match output.gltf {
    Some(path) => @cad.gltf_safe_design(design).to_gltf_file(Some(path))
    None => ()
  }
  match output.bpy {
    Some(path) => design.write_blender_python(Some(path))
    None => ()
  }
  match output.blender {
    Some(path) => design.write_blender_python(Some(path))
    None => ()
  }
  match output.blend {
    Some(path) => design.create_blender_file(path)
    None => ()
  }
  match output.urdf {
    Some(_) => robot.write_urdf(stdout_path(output.urdf), checked=true)
    None => ()
  }
  match output.bundle {
    Some(dir) => comp.to_urdf_bundle().write_to_dir(dir, checked=true)
    None => ()
  }
  match output.bom {
    Some(_) =>
      @step_cad.write_text_file(comp.to_bom_csv(), stdout_path(output.bom))
    None => ()
  }
  match output.plan {
    Some(_) =>
      @step_cad.write_text_file(
        comp.assembly_plan_text(),
        stdout_path(output.plan),
      )
    None => ()
  }
  match output.report {
    Some(_) =>
      @step_cad.write_text_file(comp.report_text(), stdout_path(output.report))
    None => ()
  }
  match output.control {
    Some(_) =>
      @step_cad.write_text_file(
        comp.to_ros2_control_yaml(),
        stdout_path(output.control),
      )
    None => ()
  }
  match output.pins {
    Some(_) =>
      @step_cad.write_text_file(comp.to_pin_map_csv(), stdout_path(output.pins))
    None => ()
  }
  match output.posed_parts {
    Some(dir) => {
      @fs.mkdir(dir, recursive=true, allow_exist=true)
      let (links, _, _) = comp.compile_links()
      let fk = robot.forward_kinematics(joint_positions~)
      for link in links {
        let world = fk.get(link.name).unwrap_or(@urdf.Transform::identity())
        let mut design = @step_cad.Design::new(name=link.name)
        for body in link.bodies {
          design = design.add(
            @cad.transform_scene_node_urdf(body.node, world).with_name(
              link.name + "_" + body.name,
            ),
          )
        }
        design.write_step_file(Some(dir + "/" + link.name + ".step"))
      }
    }
    None => ()
  }
  match output.print_parts {
    Some(dir) => {
      @fs.mkdir(dir, recursive=true, allow_exist=true)
      for part in comp.printable_parts() {
        write_print_part(
          part.design,
          dir + "/" + @cad.sanitize_part_number(part.part_number) + ".step",
        )
      }
      @step_cad.write_text_file(
        comp.print_list_csv(),
        Some(dir + "/print-list.csv"),
      )
    }
    None => ()
  }
  match output.build_package {
    Some(dir) => {
      @fs.mkdir(dir, recursive=true, allow_exist=true)
      @fs.mkdir(dir + "/printable", recursive=true, allow_exist=true)
      let written : Array[String] = []
      for file in comp.build_package_files() {
        @step_cad.write_text_file(file.content, Some(dir + "/" + file.path))
        written.push(file.path)
      }
      for part in comp.printable_parts() {
        let rel = "printable/" +
          @cad.sanitize_part_number(part.part_number) +
          ".step"
        if written.contains(rel) && design_has_boolean(part.design) {
          write_print_part(part.design, dir + "/" + rel)
        }
      }
      design.write_step_file(Some(dir + "/assembly.step"))
      comp.to_urdf_bundle().write_to_dir(dir + "/bundle", checked=true)
    }
    None => ()
  }
  if output.validate || output.validate_meshes {
    let tag = comp.name.replace(old=" ", new="-")
    let mut temp_step = false
    let step_path = match output.step {
      Some(path) =>
        if path == "-" {
          @cli.eprintln(
            "error: --validate cannot check a STEP stream on stdout",
          )
          abort("")
        } else {
          path
        }
      None => {
        temp_step = true
        "/tmp/" + tag + ".validate.step"
      }
    }
    if temp_step {
      design.write_step_file(Some(step_path))
    }
    @cli.eprintln(
      "validate: scripts/validate_step.py " + step_path + " --no-mesh",
    )
    let step_code = @process.run("python3", [
      "scripts/validate_step.py", step_path, "--no-mesh",
    ])
    if step_code != 0 {
      if temp_step {
        @fs.remove(step_path, allow_missing=true)
      }
      @cli.eprintln("error: STEP validation failed")
      abort("")
    }
    let mut temp_urdf = false
    let urdf_path = if output.validate_meshes {
      match output.bundle {
        Some(dir) => dir + "/urdf/" + robot.name + ".urdf"
        None => {
          @cli.eprintln(
            "error: --validate-meshes needs --bundle <dir> so the meshes exist",
          )
          abort("")
        }
      }
    } else {
      match output.urdf {
        Some(path) =>
          if path == "-" {
            @cli.eprintln(
              "error: --validate cannot check a URDF stream on stdout",
            )
            abort("")
          } else {
            path
          }
        None => {
          temp_urdf = true
          "/tmp/" + tag + ".validate.urdf"
        }
      }
    }
    if temp_urdf {
      robot.write_urdf(Some(urdf_path), checked=true)
    }
    let urdf_args : Array[String] = ["scripts/validate_urdf.py", urdf_path]
    if output.validate_meshes {
      urdf_args.push("--check-meshes")
    }
    @cli.eprintln("validate: python3 " + urdf_args.join(" "))
    let urdf_code = @process.run("python3", urdf_args)
    if temp_step {
      @fs.remove(step_path, allow_missing=true)
    }
    if temp_urdf {
      @fs.remove(urdf_path, allow_missing=true)
    }
    if urdf_code != 0 {
      @cli.eprintln("error: URDF validation failed")
      abort("")
    }
  }
}
