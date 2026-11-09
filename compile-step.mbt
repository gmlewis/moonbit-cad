///|
/// Compiles a `Component` tree into a posed `@step_cad.Design` in world
/// coordinates, using the URDF forward kinematics result for every link.

///|
/// Compares two strings lexicographically by UTF-16 code unit, independent of
/// their lengths (the standard `Compare` instance uses shortlex order).
fn compare_lexicographic(a : String, b : String) -> Int32 {
  let la = a.length()
  let lb = b.length()
  let n = if la < lb { la } else { lb }
  for i in 0..<n {
    let x = a.get(i).unwrap_or(0)
    let y = b.get(i).unwrap_or(0)
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  la.compare(lb)
}

///|
/// Formats the component's name, description, and sorted parameters for STEP
/// headers.
pub fn Component::format_documentation(self : Component) -> String {
  let lines : Array[String] = [self.display_name()]
  if self.description != "" {
    lines.push(self.description)
  }
  let keys : Array[String] = []
  for key in self.parameters.keys() {
    keys.push(key)
  }
  keys.sort_by(compare_lexicographic)
  for key in keys {
    lines.push("\{key}=\{self.parameters.get(key).unwrap_or("")}")
  }
  lines.join("\n")
}

///|
/// Produces a posed design with every link's bodies in world coordinates
/// (millimeters and degrees) for the given joint positions.
pub fn Component::to_design(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
) -> @step_cad.Design {
  let (links, _, _) = self.compile_links()
  let robot = self.to_robot()
  let fk = robot.forward_kinematics(joint_positions~)
  let mut design = @step_cad.Design::new(
    name=self.display_name(),
    description=self.description,
    documentation=self.format_documentation(),
  )
  for link in links {
    let world_xform = fk.get(link.name).unwrap_or(@urdf.Transform::identity())
    for body in link.bodies {
      let placed_node = transform_scene_node_urdf(body.node, world_xform).with_name(
        "\{link.name}_\{body.name}",
      )
      design = design.add(placed_node)
    }
  }
  design
}

///|
/// Exports the posed design as a flat STEP file.
pub fn Component::to_step_file(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
) -> String {
  self.to_design(joint_positions~).to_step_file()
}

///|
/// Exports the posed design as a hierarchical assembly STEP file.
pub fn Component::to_assembly_step(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
) -> String {
  self
  .to_design(joint_positions~)
  .to_assembly_step(assembly_name=self.display_name())
}

///|
/// Exports the posed design as a Z-up glTF 2.0 JSON document.
pub fn Component::to_gltf(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
) -> String {
  self.to_design(joint_positions~).to_gltf()
}

///|
/// Exports the posed design as a Blender 5.0 Python script.
pub fn Component::to_blender_python(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
  segments~ : Int32 = 36,
) -> String {
  self.to_design(joint_positions~).to_blender_python(segments~)
}
