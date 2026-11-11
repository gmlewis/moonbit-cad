///|
/// Compiles a `Component` tree into a posed `@step_cad.Design` in world
/// coordinates, using the URDF forward kinematics result for every link.

///|
/// Replaces a revolved solid with a coaxial bounding cylinder for glTF
/// visualization.
///
/// The STEP exporter keeps the exact spherical, conical, and toroidal
/// surfaces. The glTF tessellator only handles planes, cylinders, and linear
/// extrusions, so revolved profiles become a cylinder that covers the same
/// axial span and maximum radius.
fn gltf_safe_revolved(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  let (x0, x1, y0, y1, z0, z1) = node.shape.bounding_box()
  let max_x = if x1.abs() > x0.abs() { x1.abs() } else { x0.abs() }
  let max_y = if y1.abs() > y0.abs() { y1.abs() } else { y0.abs() }
  let max_r = if max_x > max_y { max_x } else { max_y }
  let height = if z1 - z0 > 1.0e-6 { z1 - z0 } else { 1.0 }
  let cylinder = @step_cad.Cylinder::new(2.0 * max_r, height)
    .with_name(node.name)
    .with_color(node.color)
    .translate(z=z0)
  transform_scene_node(cylinder, @step_cad.Transform::from_node(node))
}

///|
/// Makes a scene node safe for the glTF tessellator.
///
/// Revolved profiles (bearing balls, button and countersunk heads, chamfered
/// shafts) become bounding cylinders, and booleans are rebuilt from their
/// converted children. All other shapes pass through unchanged, so the STEP
/// output keeps its exact analytic B-Rep.
pub fn gltf_safe_node(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  match node.shape {
    @step_cad.Shape::RevolvedProfile(_) => gltf_safe_revolved(node)
    @step_cad.Shape::Union(union) => {
      let children = union.nodes.map(gltf_safe_node)
      let rebuilt = @step_cad.union_all(children, name=node.name).with_color(
        node.color,
      )
      transform_scene_node(rebuilt, @step_cad.Transform::from_node(node))
    }
    @step_cad.Shape::Difference(difference) => {
      let base = gltf_safe_node(difference.base)
      let cutters = difference.cutters.map(gltf_safe_node)
      let rebuilt = @step_cad.difference(base, cutters, name=node.name).with_color(
        node.color,
      )
      transform_scene_node(rebuilt, @step_cad.Transform::from_node(node))
    }
    _ => node
  }
}

///|
/// Makes every node in a design safe for glTF tessellation.
pub fn gltf_safe_design(design : @step_cad.Design) -> @step_cad.Design {
  let mut safe = @step_cad.Design::new(
    name=design.name,
    description=design.description,
    documentation=design.documentation,
  )
  for node in design.nodes {
    safe = safe.add(gltf_safe_node(node))
  }
  safe
}

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
  gltf_safe_design(self.to_design(joint_positions~)).to_gltf()
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
