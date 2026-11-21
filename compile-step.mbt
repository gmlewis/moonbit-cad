///|
/// Compiles a `Component` tree into a posed `@step_cad.Design` in world
/// coordinates, using the URDF forward kinematics result for every link.

///|
/// Replaces a revolved solid with a coaxial bounding cylinder (or hollow tube
/// when the revolved profile has a through-bore) for glTF visualization.
///
/// The STEP exporter keeps the exact spherical, conical, and toroidal
/// surfaces. The glTF tessellator only handles planes, cylinders, and linear
/// extrusions, so revolved profiles become a cylinder or tube that covers the
/// same axial span and radial extent.
fn gltf_safe_revolved(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  let (x0, x1, y0, y1, z0, z1) = node.shape.bounding_box()
  let sx = if x1 - x0 > 1.0e-6 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-6 { y1 - y0 } else { 1.0 }
  let outer_d = if sx > sy { sx } else { sy }
  let height = if z1 - z0 > 1.0e-6 { z1 - z0 } else { 1.0 }
  let inner_d = match node.shape {
    @step_cad.Shape::RevolvedProfile(rev) => {
      let mut r_min = 1.0e30
      for seg in rev.segments {
        let (a, b) = match seg {
          @step_cad.RevLine(a, b) => (a, b)
          @step_cad.RevArc(a, b, _) => (a, b)
        }
        if a.0.abs() < r_min {
          r_min = a.0.abs()
        }
        if b.0.abs() < r_min {
          r_min = b.0.abs()
        }
      }
      if r_min < 1.0e29 {
        2.0 * r_min
      } else {
        0.0
      }
    }
    _ => 0.0
  }
  let shape = if inner_d > 1.0 && inner_d < outer_d - 1.0 {
    @step_cad.tube(outer_d, inner_d, height, segments=36)
  } else {
    @step_cad.Cylinder::new(outer_d, height)
  }
  let proxy = shape
    .with_name(node.name)
    .with_color(node.color)
    .translate(x=(x0 + x1) / 2.0, y=(y0 + y1) / 2.0, z=z0)
  transform_scene_node(proxy, @step_cad.Transform::from_node(node))
}

///|
/// Normalizes an angular difference into `(-pi, pi]`.
fn gltf_arc_signed_sweep(a : Double) -> Double {
  let two_pi = 2.0 * @math.PI
  let mut x = a
  while x > @math.PI {
    x = x - two_pi
  }
  while x <= -@math.PI {
    x = x + two_pi
  }
  x
}

///|
/// Samples a closed loop of `ProfileSegment`s into a 2D polygon for glTF
/// extrusion.
fn gltf_sample_arc_loop(
  segs : Array[@step_cad.ProfileSegment],
  arc_steps~ : Int32 = 4,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  let steps = if arc_steps < 2 { 2 } else { arc_steps }
  for seg in segs {
    match seg {
      @step_cad.SegmentLine(a, _) => pts.push(a)
      @step_cad.SegmentArc(a, b, c) => {
        let dx = a.0 - c.0
        let dy = a.1 - c.1
        let rho = (dx * dx + dy * dy).sqrt()
        let a0 = @math.atan2(dy, dx)
        let a1 = @math.atan2(b.1 - c.1, b.0 - c.0)
        let delta = gltf_arc_signed_sweep(a1 - a0)
        for k in 0..<steps {
          let ang = a0 + delta * k.to_double() / steps.to_double()
          pts.push((c.0 + rho * @math.cos(ang), c.1 + rho * @math.sin(ang)))
        }
      }
    }
  }
  pts
}

///|
/// Converts an `ExtrudedArcProfile` into a glTF-safe `ExtrudedProfile`, tube,
/// or cylinder.
fn gltf_safe_extruded_arc(
  node : @step_cad.SceneNode,
  e : @step_cad.ExtrudedArcProfile,
) -> @step_cad.SceneNode {
  if e.segments.length() <= 16 && e.holes.length() <= 1 && e.round_bore is None {
    let outer = gltf_sample_arc_loop(e.segments)
    let holes = e.holes.map(fn(h) { gltf_sample_arc_loop(h) })
    if outer.length() >= 3 {
      let ext = @step_cad.ExtrudedProfile::new(outer, e.height_mm, holes~)
        .with_name(node.name)
        .with_color(node.color)
      return transform_scene_node(ext, @step_cad.Transform::from_node(node))
    }
  }
  let (x0, x1, y0, y1, z0, z1) = node.shape.bounding_box()
  let sx = if x1 - x0 > 1.0e-6 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-6 { y1 - y0 } else { 1.0 }
  let outer_d = if sx > sy { sx } else { sy }
  let height = if z1 - z0 > 1.0e-6 { z1 - z0 } else { 1.0 }
  if (sx - sy).abs() <= 0.25 * outer_d {
    let inner_d = match e.round_bore {
      Some((_, bore_d)) => bore_d
      None => 0.0
    }
    let shape = if inner_d > 1.0 && inner_d < outer_d - 1.0 {
      @step_cad.tube(outer_d, inner_d, height, segments=36)
    } else {
      @step_cad.Cylinder::new(outer_d, height)
    }
    let proxy = shape
      .with_name(node.name)
      .with_color(node.color)
      .translate(x=(x0 + x1) / 2.0, y=(y0 + y1) / 2.0, z=z0)
    transform_scene_node(proxy, @step_cad.Transform::from_node(node))
  } else {
    gltf_safe_bounding_box(node)
  }
}

///|
/// Replaces a swept solid with a coaxial cylinder/tube (for circular gears and
/// rings) or an accurately positioned bounding box for glTF visualization.
///
/// Herringbone gear flanks are swept B-spline surfaces; the glTF tessellator
/// only handles planes, cylinders, and linear extrusions. The STEP exporter
/// keeps the exact swept B-Rep, while the glTF proxy uses a coaxial hollow
/// tube or cylinder matching the gear's true outer and bore diameters.
fn gltf_safe_swept(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  let (x0, x1, y0, y1, z0, z1) = node.shape.bounding_box()
  let sx = if x1 - x0 > 1.0e-6 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-6 { y1 - y0 } else { 1.0 }
  let sz = if z1 - z0 > 1.0e-6 { z1 - z0 } else { 1.0 }
  let cx = (x0 + x1) / 2.0
  let cy = (y0 + y1) / 2.0
  let cz = (z0 + z1) / 2.0
  match node.shape {
    @step_cad.Shape::SweptProfile(s) => {
      let hole_diam_xy = fn() -> Double {
        if s.profile.holes.length() == 0 {
          return 0.0
        }
        let hole = s.profile.holes[0]
        if hole.length() < 3 {
          return 0.0
        }
        let mut hx0 = hole[0].0
        let mut hx1 = hole[0].0
        let mut hy0 = hole[0].1
        let mut hy1 = hole[0].1
        for pt in hole {
          if pt.0 < hx0 {
            hx0 = pt.0
          }
          if pt.0 > hx1 {
            hx1 = pt.0
          }
          if pt.1 < hy0 {
            hy0 = pt.1
          }
          if pt.1 > hy1 {
            hy1 = pt.1
          }
        }
        (hx1 - hx0 + (hy1 - hy0)) / 2.0
      }
      let hole_diam_xz = fn() -> Double {
        if s.profile.holes.length() == 0 {
          return 0.0
        }
        let hole = s.profile.holes[0]
        if hole.length() < 3 {
          return 0.0
        }
        let mut hx0 = hole[0].0
        let mut hx1 = hole[0].0
        let mut hz0 = hole[0].2
        let mut hz1 = hole[0].2
        for pt in hole {
          if pt.0 < hx0 {
            hx0 = pt.0
          }
          if pt.0 > hx1 {
            hx1 = pt.0
          }
          if pt.2 < hz0 {
            hz0 = pt.2
          }
          if pt.2 > hz1 {
            hz1 = pt.2
          }
        }
        (hx1 - hx0 + (hz1 - hz0)) / 2.0
      }
      let max_xy = if sx > sy { sx } else { sy }
      let max_xz = if sx > sz { sx } else { sz }
      if (sx - sy).abs() <= 0.15 * max_xy {
        let inner_d = hole_diam_xy()
        let shape = if inner_d > 1.0 && inner_d < max_xy - 1.0 {
          @step_cad.tube(max_xy, inner_d, sz, segments=36)
        } else {
          @step_cad.Cylinder::new(max_xy, sz)
        }
        let proxy = shape
          .with_name(node.name)
          .with_color(node.color)
          .translate(x=cx, y=cy, z=z0)
        return transform_scene_node(proxy, @step_cad.Transform::from_node(node))
      } else if (sx - sz).abs() <= 0.15 * max_xz {
        let inner_d = hole_diam_xz()
        let shape = if inner_d > 1.0 && inner_d < max_xz - 1.0 {
          @step_cad.tube(max_xz, inner_d, sy, segments=36)
        } else {
          @step_cad.Cylinder::new(max_xz, sy)
        }
        let proxy = shape
          .with_name(node.name)
          .with_color(node.color)
          .rotate_x(-90.0)
          .translate(x=cx, y=y0, z=cz)
        return transform_scene_node(proxy, @step_cad.Transform::from_node(node))
      }
    }
    _ => ()
  }
  gltf_safe_bounding_box(node)
}

///|
/// Replaces an imported STEP solid with a coaxial cylinder (when the solid has
/// a circular cross-section along X, Y, or Z, such as a round motor controller
/// PCB or wheel hub flange) or an accurately positioned bounding box.
fn gltf_safe_imported_step(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  let (x0, x1, y0, y1, z0, z1) = node.shape.bounding_box()
  let sx = if x1 - x0 > 1.0e-6 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-6 { y1 - y0 } else { 1.0 }
  let sz = if z1 - z0 > 1.0e-6 { z1 - z0 } else { 1.0 }
  let cx = (x0 + x1) / 2.0
  let cy = (y0 + y1) / 2.0
  let cz = (z0 + z1) / 2.0
  let max_xy = if sx > sy { sx } else { sy }
  let max_xz = if sx > sz { sx } else { sz }
  let max_yz = if sy > sz { sy } else { sz }
  if (sx - sy).abs() <= 0.15 * max_xy && sz < 0.8 * max_xy {
    let cyl = @step_cad.Cylinder::new(max_xy, sz)
      .with_name(node.name)
      .with_color(node.color)
      .translate(x=cx, y=cy, z=z0)
    transform_scene_node(cyl, @step_cad.Transform::from_node(node))
  } else if (sx - sz).abs() <= 0.15 * max_xz && sy < 0.8 * max_xz {
    let cyl = @step_cad.Cylinder::new(max_xz, sy)
      .with_name(node.name)
      .with_color(node.color)
      .rotate_x(-90.0)
      .translate(x=cx, y=y0, z=cz)
    transform_scene_node(cyl, @step_cad.Transform::from_node(node))
  } else if (sy - sz).abs() <= 0.15 * max_yz && sx < 0.8 * max_yz {
    let cyl = @step_cad.Cylinder::new(max_yz, sx)
      .with_name(node.name)
      .with_color(node.color)
      .rotate_y(90.0)
      .translate(x=x0, y=cy, z=cz)
    transform_scene_node(cyl, @step_cad.Transform::from_node(node))
  } else {
    gltf_safe_bounding_box(node)
  }
}

///|
/// Replaces any shape the glTF tessellator cannot handle with an accurately
/// positioned axis-aligned bounding box.
///
/// Note that `@step_cad.Cuboid::new(sx, sy, sz)` has its minimum corner at
/// `(0, 0, 0)` and spans `[0..sx, 0..sy, 0..sz]`, so it must be translated by
/// `(x0, y0, z0)` to match `[x0..x1, y0..y1, z0..z1]`.
fn gltf_safe_bounding_box(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  let (x0, x1, y0, y1, z0, z1) = node.shape.bounding_box()
  let sx = if x1 - x0 > 1.0e-6 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-6 { y1 - y0 } else { 1.0 }
  let sz = if z1 - z0 > 1.0e-6 { z1 - z0 } else { 1.0 }
  let box_node = @step_cad.Cuboid::new(sx, sy, sz)
    .with_name(node.name)
    .with_color(node.color)
    .translate(x=x0, y=y0, z=z0)
  transform_scene_node(box_node, @step_cad.Transform::from_node(node))
}

///|
/// Makes a scene node safe for the glTF tessellator.
///
/// Revolved profiles (bearing rings and balls, button and countersunk heads,
/// chamfered shafts, socketed screws) become coaxial bounding cylinders or
/// tubes, swept profiles (herringbone gears) become coaxial tubes or cylinders,
/// imported STEP solids become coaxial cylinders or centered bounding boxes,
/// and booleans are rebuilt from their converted children. Shapes that compile
/// to planes, cylinders, and linear extrusions pass through unchanged, so the
/// STEP output always keeps its exact analytic B-Rep.
pub fn gltf_safe_node(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  match node.shape {
    @step_cad.Shape::Cuboid(_)
    | @step_cad.Shape::Cylinder(_)
    | @step_cad.Shape::ExtrudedProfile(_) => node
    @step_cad.Shape::ChamferedPrism(_) => flatten_chamfered_prism(node)
    @step_cad.Shape::RevolvedProfile(_)
    | @step_cad.Shape::SocketedSolid(_)
    | @step_cad.Shape::ConicalNut(_)
    | @step_cad.Shape::SlitTube(_)
    | @step_cad.Shape::AcornNut(_)
    | @step_cad.Shape::ConicalExtrusion(_)
    | @step_cad.Shape::BevelGearBody(_)
    | @step_cad.Shape::SquareHoleWasher(_)
    | @step_cad.Shape::TabWasher(_)
    | @step_cad.Shape::HexHeadWasherFace(_) => gltf_safe_revolved(node)
    @step_cad.Shape::ExtrudedArcProfile(e) => gltf_safe_extruded_arc(node, e)
    @step_cad.Shape::SweptProfile(_) => gltf_safe_swept(node)
    @step_cad.Shape::ImportedStep(_) => gltf_safe_imported_step(node)
    @step_cad.Shape::Fillet(f) => {
      let base = gltf_safe_node(f.base)
        .with_name(node.name)
        .with_color(node.color)
      transform_scene_node(base, @step_cad.Transform::from_node(node))
    }
    @step_cad.Shape::Chamfer(c) => {
      let base = gltf_safe_node(c.base)
        .with_name(node.name)
        .with_color(node.color)
      transform_scene_node(base, @step_cad.Transform::from_node(node))
    }
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
