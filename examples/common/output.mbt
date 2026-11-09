///|
/// Shared output destinations for the showcase examples.
///
/// Each example builds its own geometry options, calls `with_output_args` to
/// add the standard export flags, then calls `write_output` with the assembled
/// `Component`.
pub(all) struct OutputPaths {
  step : String?
  assembly : String?
  eval : String?
  gltf : String?
  bpy : String?
  blend : String?
  urdf : String?
  bundle : String?
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
      help="Write ROS 2 URDF bundle (with .gltf & .step link assets) to directory",
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
    blend: args.string_opt("blend"),
    urdf: args.string_opt("urdf"),
    bundle: args.string_opt("bundle"),
  }
}

///|
fn any_output(output : OutputPaths) -> Bool {
  output.step is Some(_) ||
  output.assembly is Some(_) ||
  output.eval is Some(_) ||
  output.gltf is Some(_) ||
  output.bpy is Some(_) ||
  output.blend is Some(_) ||
  output.urdf is Some(_) ||
  output.bundle is Some(_)
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
  if !any_output(output) {
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
    Some(path) => design.to_gltf_file(Some(path))
    None => ()
  }
  match output.bpy {
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
}
