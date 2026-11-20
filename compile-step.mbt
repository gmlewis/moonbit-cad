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
/// Replaces a swept solid with an axis-aligned bounding box for glTF
/// visualization.
///
/// Herringbone gear flanks are swept B-spline surfaces; the glTF tessellator
/// only handles planes, cylinders, and linear extrusions. The STEP exporter
/// keeps the exact swept B-Rep, while the glTF proxy is a box spanning the same
/// extents.
fn gltf_safe_swept(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  let (x0, x1, y0, y1, z0, z1) = node.shape.bounding_box()
  let sx = if x1 - x0 > 1.0e-6 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-6 { y1 - y0 } else { 1.0 }
  let sz = if z1 - z0 > 1.0e-6 { z1 - z0 } else { 1.0 }
  let box_node = @step_cad.Cuboid::new(sx, sy, sz)
    .with_name(node.name)
    .with_color(node.color)
    .translate(x=(x0 + x1) / 2.0, y=(y0 + y1) / 2.0, z=(z0 + z1) / 2.0)
  transform_scene_node(box_node, @step_cad.Transform::from_node(node))
}

///|
/// Replaces any shape the glTF tessellator cannot handle with a bounding box.
fn gltf_safe_bounding_box(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  gltf_safe_swept(node)
}

///|
/// Makes a scene node safe for the glTF tessellator.
///
/// Revolved profiles (bearing balls, button and countersunk heads, chamfered
/// shafts) become bounding cylinders, swept profiles (herringbone gear flanks)
/// and any remaining analytic shape the tessellator cannot handle become
/// bounding boxes, and booleans are rebuilt from their converted children.
/// Shapes that compile to planes, cylinders, and linear extrusions pass through
/// unchanged, so the STEP output always keeps its exact analytic B-Rep.
pub fn gltf_safe_node(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  match node.shape {
    @step_cad.Shape::RevolvedProfile(_) => gltf_safe_revolved(node)
    @step_cad.Shape::SweptProfile(_) => gltf_safe_swept(node)
    @step_cad.Shape::Cuboid(_)
    | @step_cad.Shape::Cylinder(_)
    | @step_cad.Shape::ExtrudedProfile(_) => node
    @step_cad.Shape::ExtrudedArcProfile(_) => gltf_safe_revolved(node)
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
    _ => gltf_safe_bounding_box(node)
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

///|
/// Cumulative explosion state used while walking the component tree.
priv struct ExplodeCtx {
  fk : Map[String, @urdf.Transform]
  offsets : Map[String, (Double, Double, Double)]
  traces : Array[((Double, Double, Double), (Double, Double, Double))]
  scale : Double
}

///|
fn explode_transform_of_placement(
  p : @step_common.Placement,
) -> @step_cad.Transform {
  let t : @step_cad.Transform = { rot: p.rot, trans: p.trans, }
  t
}

///|
fn explode_unit(v : (Double, Double, Double)) -> (Double, Double, Double) {
  let len = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).sqrt()
  if len < 1.0e-12 {
    (0.0, 0.0, 1.0)
  } else {
    (v.0 / len, v.1 / len, v.2 / len)
  }
}

///|
fn explode_displacement(
  spec : ExplodeSpec,
  parent_world : @step_cad.Transform,
  parent_mate : @step_common.MateConnector,
  flip_axis : Bool,
  scale : Double,
) -> (Double, Double, Double) {
  match spec {
    AlongMate(distance_mm, order) => {
      let mut axis = explode_unit(parent_mate.axis)
      if flip_axis {
        axis = (-axis.0, -axis.1, -axis.2)
      }
      let world_axis = parent_world.apply_dir(axis)
      let d = distance_mm * order.to_double() * scale
      (world_axis.0 * d, world_axis.1 * d, world_axis.2 * d)
    }
    AlongMateLocal(distance_mm, order) => {
      // axis is authored in the mate's own rotated frame for this variant.
      let mate_frame : @step_cad.Transform = {
        rot: parent_mate.placement.rot,
        trans: (0.0, 0.0, 0.0),
      }
      let mut axis = explode_unit(mate_frame.apply_dir(parent_mate.axis))
      if flip_axis {
        axis = (-axis.0, -axis.1, -axis.2)
      }
      let world_axis = parent_world.apply_dir(axis)
      let d = distance_mm * order.to_double() * scale
      (world_axis.0 * d, world_axis.1 * d, world_axis.2 * d)
    }
    OffsetMm(dx, dy, dz, order) => {
      let world = parent_world.apply_dir((dx, dy, dz))
      let d = order.to_double() * scale
      (world.0 * d, world.1 * d, world.2 * d)
    }
  }
}

///|
fn collect_explode_offsets(
  comp : Component,
  parent_offset : (Double, Double, Double),
  world : @step_cad.Transform,
  ctx : ExplodeCtx,
) -> Unit {
  ctx.offsets.set(comp.name, parent_offset)
  for att in comp.attachments {
    let pair = att.spec.pair
    let p_mate = comp.mates
      .get(pair.parent)
      .unwrap_or(@step_common.MateConnector::new(pair.parent))
    let c_mate = att.child.mates
      .get(pair.child)
      .unwrap_or(@step_common.MateConnector::new(pair.child))
    let (snap_placement, _) = @step_common.snap_connectors(
      p_mate,
      c_mate,
      offset_mm=pair.offset_mm,
      twist_rad=pair.twist_deg * @math.PI / 180.0,
      flip_axis=pair.flip_axis,
    )
    let snap_world = world.compose(
      explode_transform_of_placement(snap_placement),
    )
    let child_world = match ctx.fk.get(att.child.name) {
      Some(t) => urdf_to_step_transform(t)
      None => snap_world
    }
    let child_offset = match att.explode {
      Some(spec) =>
        if att.spec.kind is MergeRigid {
          // A rigidly merged child is welded into the parent link, so it moves
          // with the parent; only its kinematic descendants can separate.
          parent_offset
        } else {
          let d = explode_displacement(
            spec,
            world,
            p_mate,
            pair.flip_axis,
            ctx.scale,
          )
          let offset = (
            parent_offset.0 + d.0,
            parent_offset.1 + d.1,
            parent_offset.2 + d.2,
          )
          if d.0 * d.0 + d.1 * d.1 + d.2 * d.2 > 1.0e-12 {
            let from = world.apply(p_mate.placement.trans)
            let to = (
              child_world.trans.0 + offset.0,
              child_world.trans.1 + offset.1,
              child_world.trans.2 + offset.2,
            )
            ctx.traces.push((from, to))
          }
          offset
        }
      None => parent_offset
    }
    collect_explode_offsets(att.child, child_offset, child_world, ctx)
  }
}

///|
fn explode_is_default_color(color : @step_cad.Rgb) -> Bool {
  // `BodyPart` builders default to `Rgb::grey()`; treat that as "no explicit
  // color" so the exploded view can apply a role palette.
  (color.r - 0.2).abs() < 1.0e-9 &&
  (color.g - 0.2).abs() < 1.0e-9 &&
  (color.b - 0.2).abs() < 1.0e-9
}

///|
fn explode_name_matches(name : String, needles : Array[String]) -> Bool {
  needles.fold(init=false, fn(acc, needle) { acc || name.contains(needle) })
}

///|
/// Deterministic role-based color for an exploded-view body.
fn explode_role_color(link_name : String, body_name : String) -> @step_cad.Rgb {
  let name = (link_name + "/" + body_name).to_lower()
  if explode_name_matches(name, [
      "gear", "planet", "ring", "sun", "pinion", "herringbone",
    ]) {
    @step_cad.Rgb::new(0.10, 0.55, 0.55)
  } else if explode_name_matches(name, [
      "bearing", "bolt", "screw", "pin", "shaft", "dowel", "washer", "fastener",
      "spring",
    ]) {
    @step_cad.Rgb::new(0.55, 0.58, 0.62)
  } else if explode_name_matches(name, [
      "pcb", "moteus", "imu", "mcu", "board", "sensor", "encoder", "camera",
    ]) {
    @step_cad.Rgb::new(0.12, 0.48, 0.20)
  } else if explode_name_matches(name, [
      "battery", "tire", "rubber", "tpu", "cable", "gasket",
    ]) {
    @step_cad.Rgb::new(0.12, 0.12, 0.14)
  } else if explode_name_matches(name, [
      "housing", "barrel", "backplate", "cap", "cover", "shroud", "casing", "lid",
    ]) {
    @step_cad.Rgb::new(0.36, 0.42, 0.52)
  } else if explode_name_matches(name, [
      "crank", "link", "strut", "arm", "yoke", "rod", "guide", "pivot",
    ]) {
    @step_cad.Rgb::new(0.84, 0.86, 0.90)
  } else {
    @step_cad.Rgb::new(0.72, 0.72, 0.75)
  }
}

///|
fn explode_add_trace(
  design : @step_cad.Design,
  from : (Double, Double, Double),
  to : (Double, Double, Double),
) -> @step_cad.Design {
  let d = (to.0 - from.0, to.1 - from.1, to.2 - from.2)
  let len = (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).sqrt()
  if len < 0.5 {
    return design
  }
  let dir = (d.0 / len, d.1 / len, d.2 / len)
  let cos_angle = if dir.2 > 1.0 {
    1.0
  } else if dir.2 < -1.0 {
    -1.0
  } else {
    dir.2
  }
  let angle = @math.acos(cos_angle)
  let (axis, angle) = if cos_angle > 0.999999 {
    ((0.0, 0.0, 1.0), 0.0)
  } else if cos_angle < -0.999999 {
    ((1.0, 0.0, 0.0), @math.PI)
  } else {
    ((-dir.1, dir.0, 0.0), angle)
  }
  let rot = @step_common.Placement::rotation_axis_angle(axis, angle)
  let (rx, ry, rz) = @step_cad.matrix_to_euler(rot.rot)
  let dashes = 5
  let dash_len = len / (2.0 * dashes.to_double())
  let mut out = design
  for i in 0..<dashes {
    let start = 2.0 * i.to_double() * dash_len
    let node = @step_cad.Cylinder::new(1.4, dash_len)
      .with_name("explode_trace_" + out.nodes.length().to_string())
      .with_color(@step_cad.Rgb::new(0.25, 0.35, 0.85))
      .rotate_x(rx)
      .rotate_y(ry)
      .rotate_z(rz)
      .translate(
        x=from.0 + dir.0 * start,
        y=from.1 + dir.1 * start,
        z=from.2 + dir.2 * start,
      )
    out = out.add(node)
  }
  out
}

///|
/// Produces an exploded, role-colored design for this component tree.
///
/// Each `ExplodeSpec` on an attachment moves that child and every descendant
/// cumulatively, so a leg that separates also carries its wheel. `scale`
/// multiplies every separation (0 reproduces the assembled placement, 2 doubles
/// it). `trace_lines` adds thin dashed coaxial guides between each parent mate
/// origin and its exploded child mate origin.
///
/// Bodies keep an explicit color; the builder's default grey is replaced by a
/// deterministic role palette.
pub fn Component::to_exploded_design(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
  scale~ : Double = 1.0,
  trace_lines~ : Bool = false,
) -> @step_cad.Design {
  let (links, _, _) = self.compile_links()
  let robot = self.to_robot()
  let fk = robot.forward_kinematics(joint_positions~)
  let root_world = match fk.get(self.name) {
    Some(t) => urdf_to_step_transform(t)
    None => @step_cad.Transform::identity()
  }
  let offsets : Map[String, (Double, Double, Double)] = Map([])
  let traces : Array[((Double, Double, Double), (Double, Double, Double))] = []
  let ctx : ExplodeCtx = { fk, offsets, traces, scale, }
  collect_explode_offsets(self, (0.0, 0.0, 0.0), root_world, ctx)
  let mut design = @step_cad.Design::new(
    name=self.display_name(),
    description=self.description,
    documentation=self.format_documentation(),
  )
  for link in links {
    let world = fk.get(link.name).unwrap_or(@urdf.Transform::identity())
    let offset = offsets.get(link.name).unwrap_or((0.0, 0.0, 0.0))
    for body in link.bodies {
      let placed = transform_scene_node_urdf(body.node, world).with_name(
        "\{link.name}_\{body.name}",
      )
      let colored = if explode_is_default_color(placed.color) {
        placed.with_color(explode_role_color(link.name, body.name))
      } else {
        placed
      }
      design = design.add(colored.translate(x=offset.0, y=offset.1, z=offset.2))
    }
  }
  if trace_lines {
    for trace in ctx.traces {
      design = explode_add_trace(design, trace.0, trace.1)
    }
  }
  design
}
