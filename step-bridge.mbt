///|
/// Bridges between `gmlewis/step/components/*` and `gmlewis/cad`.
///
/// The STEP component packages model hardware primitives at three explicit
/// levels of detail. This file imports those primitives into the CAD / URDF
/// world: it parses CLI detail and thread options, and it converts a
/// `@step_common.Component` into `BodyPart`s and a `Component`.

///|
/// Parses a detail-level option.
///
/// Accepts `"simplified"`, `"detailed"`, `"fully-modeled"`, `"fully_modeled"`,
/// and `"full"`; returns `None` for anything else.
pub fn parse_detail_level(text : String) -> @step_common.DetailLevel? {
  match text {
    "simplified" | "simple" => Some(@step_common.DetailLevel::Simplified)
    "detailed" | "detail" => Some(@step_common.DetailLevel::Detailed)
    "fully-modeled" | "fully_modeled" | "full" =>
      Some(@step_common.DetailLevel::FullyModeled)
    _ => None
  }
}

///|
/// Parses a thread-representation option.
///
/// Accepts `"none"`, `"cosmetic"`, and `"helical"`; returns `None` for
/// anything else.
pub fn parse_thread_rep(text : String) -> @step_common.ThreadRepresentation? {
  match text {
    "none" | "" => Some(@step_common.ThreadRepresentation::None)
    "cosmetic" => Some(@step_common.ThreadRepresentation::Cosmetic)
    "helical" => Some(@step_common.ThreadRepresentation::Helical)
    _ => None
  }
}

///|
/// The canonical CLI name of a detail level.
pub fn detail_level_name(level : @step_common.DetailLevel) -> String {
  match level {
    @step_common.DetailLevel::Simplified => "simplified"
    @step_common.DetailLevel::Detailed => "detailed"
    @step_common.DetailLevel::FullyModeled => "fully-modeled"
  }
}

///|
/// The canonical CLI name of a thread representation.
pub fn thread_rep_name(rep : @step_common.ThreadRepresentation) -> String {
  match rep {
    @step_common.ThreadRepresentation::None => "none"
    @step_common.ThreadRepresentation::Cosmetic => "cosmetic"
    @step_common.ThreadRepresentation::Helical => "helical"
  }
}

///|
/// The detail level implied by a thread override, if any.
///
/// A `Helical` thread request implies `FullyModeled`; the other modes keep the
/// caller's detail level.
pub fn detail_level_with_threads(
  level : @step_common.DetailLevel,
  threads : @step_common.ThreadRepresentation?,
) -> @step_common.DetailLevel {
  match threads {
    Some(@step_common.ThreadRepresentation::Helical) =>
      @step_common.DetailLevel::FullyModeled
    _ => level
  }
}

///|
/// Replaces a chamfered prism with the equivalent extruded profile.
///
/// The STEP kernel's chamfered-prism compiler chooses face-loop direction from
/// a signed area test that can flip when the solid is translated away from the
/// origin, producing inconsistently oriented shared edges. The imported
/// hardware keeps its outline and bores but drops the small edge chamfer, so
/// every exported STEP validates under translation.
fn flatten_chamfered_prism(node : @step_cad.SceneNode) -> @step_cad.SceneNode {
  match node.shape {
    @step_cad.Shape::ChamferedPrism(prism) => {
      let mut z0 = prism.levels[0].0
      let mut z1 = prism.levels[0].0
      for level in prism.levels {
        if level.0 < z0 {
          z0 = level.0
        }
        if level.0 > z1 {
          z1 = level.0
        }
      }
      let height = if z1 - z0 > 1.0e-9 { z1 - z0 } else { 1.0 }
      let holes = match prism.hole {
        Some(hole) => [hole]
        None => []
      }
      let shape = @step_cad.ExtrudedProfile::new(prism.base, height, holes~)
      let placed = shape
        .with_name(node.name)
        .with_color(node.color)
        .translate(z=z0)
      transform_scene_node(placed, @step_cad.Transform::from_node(node))
    }
    @step_cad.Shape::Union(union) => {
      let children = union.nodes.map(flatten_chamfered_prism)
      let rebuilt = @step_cad.union_all(children, name=node.name).with_color(
        node.color,
      )
      transform_scene_node(rebuilt, @step_cad.Transform::from_node(node))
    }
    @step_cad.Shape::Difference(difference) => {
      let base = flatten_chamfered_prism(difference.base)
      let cutters = difference.cutters.map(flatten_chamfered_prism)
      let rebuilt = @step_cad.difference(base, cutters, name=node.name).with_color(
        node.color,
      )
      transform_scene_node(rebuilt, @step_cad.Transform::from_node(node))
    }
    _ => node
  }
}

///|
/// Materializes one component layer with its placement applied.
fn placed_layer_node(
  layer : @step_common.ComponentLayer,
) -> @step_cad.SceneNode {
  let (rx, ry, rz) = layer.placement.to_euler()
  layer.shape
  .with_name(layer.name)
  .with_color(layer.color)
  .rotate_x(rx)
  .rotate_y(ry)
  .rotate_z(rz)
  .translate(
    x=layer.placement.trans.0,
    y=layer.placement.trans.1,
    z=layer.placement.trans.2,
  )
}

///|
/// The leaf name of a layer or connector path (`"gearbox/sun"` -> `"sun"`).
fn layer_leaf_name(name : String) -> String {
  match name.rev_find("/") {
    Some(index) =>
      String::unsafe_substring(name, start=index + 1, end=name.length())
    None => name
  }
}

///|
/// Builds one `BodyPart` from an already placed scene node.
pub fn BodyPart::from_scene_node(
  node : @step_cad.SceneNode,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  part~ : PartMeta? = None,
) -> BodyPart {
  body_part_from_placed_node(node, density, part)
}

///|
/// Cross product of two 3D vectors.
fn vec3_cross(
  a : (Double, Double, Double),
  b : (Double, Double, Double),
) -> (Double, Double, Double) {
  (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
}

///|
/// Normalizes a 3D vector, returning `(0, 0, 1)` when degenerate.
fn vec3_norm(v : (Double, Double, Double)) -> (Double, Double, Double) {
  let len = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).sqrt()
  if len <= 1.0e-12 {
    (0.0, 0.0, 1.0)
  } else {
    (v.0 / len, v.1 / len, v.2 / len)
  }
}

///|
/// Unsigned shoelace area of a 2D polygon in mm^2.
fn poly_area_2d(pts : Array[(Double, Double)]) -> Double {
  let n = pts.length()
  if n < 3 {
    return 0.0
  }
  let mut sum = 0.0
  for i in 0..<n {
    let a = pts[i]
    let b = pts[(i + 1) % n]
    sum = sum + a.0 * b.1 - b.0 * a.1
  }
  (sum * 0.5).abs()
}

///|
/// Computes mesh-tight bounding box `(x0, x1, y0, y1, z0, z1)` in placed frame.
fn tight_placed_bounds(
  placed : @step_cad.SceneNode,
) -> (Double, Double, Double, Double, Double, Double) {
  match placed.shape.analysis_mesh() {
    Ok((verts, _faces)) if verts.length() > 0 => {
      let t = @step_cad.Transform::from_node(placed)
      let m = t.rot
      let (tx, ty, tz) = t.trans
      let v0 = verts[0]
      let g0x = m.m00 * v0.0 + m.m01 * v0.1 + m.m02 * v0.2 + tx
      let g0y = m.m10 * v0.0 + m.m11 * v0.1 + m.m12 * v0.2 + ty
      let g0z = m.m20 * v0.0 + m.m21 * v0.1 + m.m22 * v0.2 + tz
      let mut x0 = g0x
      let mut x1 = g0x
      let mut y0 = g0y
      let mut y1 = g0y
      let mut z0 = g0z
      let mut z1 = g0z
      for v in verts {
        let gx = m.m00 * v.0 + m.m01 * v.1 + m.m02 * v.2 + tx
        let gy = m.m10 * v.0 + m.m11 * v.1 + m.m12 * v.2 + ty
        let gz = m.m20 * v.0 + m.m21 * v.1 + m.m22 * v.2 + tz
        if gx < x0 {
          x0 = gx
        }
        if gx > x1 {
          x1 = gx
        }
        if gy < y0 {
          y0 = gy
        }
        if gy > y1 {
          y1 = gy
        }
        if gz < z0 {
          z0 = gz
        }
        if gz > z1 {
          z1 = gz
        }
      }
      (x0, x1, y0, y1, z0, z1)
    }
    _ => placed.bounding_box()
  }
}

///|
/// Computes physical inertial in the local frame of `shape` when its true
/// volume/mesh can be determined, falling back cleanly for nominal booleans
/// and swept profiles.
fn local_shape_inertial(
  shape : @step_cad.Shape,
  density : @urdf.Density,
) -> @urdf.Inertial? {
  match shape.analysis_mesh() {
    Ok((verts, faces)) => {
      let triangles : Array[
        (
          (Double, Double, Double),
          (Double, Double, Double),
          (Double, Double, Double),
        ),
      ] = []
      let n_verts = verts.length()
      for face in faces {
        if face.length() < 3 {
          continue
        }
        let i0 = face[0].to_int()
        if i0 < 0 || i0 >= n_verts {
          continue
        }
        for i in 1..<(face.length() - 1) {
          let i1 = face[i].to_int()
          let i2 = face[i + 1].to_int()
          if i1 >= 0 && i1 < n_verts && i2 >= 0 && i2 < n_verts {
            triangles.push((verts[i0], verts[i1], verts[i2]))
          }
        }
      }
      if triangles.length() > 0 {
        let inertial = @urdf.Inertial::from_triangles_mm(triangles, density~)
        if inertial.mass > 1.0e-9 &&
          inertial.inertia.ixx >= 0.0 &&
          inertial.inertia.iyy >= 0.0 &&
          inertial.inertia.izz >= 0.0 {
          return Some(inertial)
        }
      }
    }
    Err(_) => ()
  }
  match shape {
    @step_cad.Shape::SweptProfile(s) => {
      let prof_z = vec3_norm(s.profile.normal_dir)
      let prof_x = vec3_norm(s.profile.right_dir)
      let prof_y = vec3_norm(vec3_cross(prof_z, prof_x))
      let project2d = fn(v : (Double, Double, Double)) -> (Double, Double) {
        let d = (
          v.0 - s.profile.center.0,
          v.1 - s.profile.center.1,
          v.2 - s.profile.center.2,
        )
        (
          d.0 * prof_x.0 + d.1 * prof_x.1 + d.2 * prof_x.2,
          d.0 * prof_y.0 + d.1 * prof_y.1 + d.2 * prof_y.2,
        )
      }
      let outer2d = s.profile.vertices.map(project2d)
      let mut area = poly_area_2d(outer2d)
      for hole in s.profile.holes {
        area = area - poly_area_2d(hole.map(project2d))
      }
      if area < 0.0 {
        area = 0.0
      }
      let pts = s.path.points
      let mut path_len = 0.0
      for i in 0..<(pts.length() - 1) {
        let a = pts[i]
        let b = pts[i + 1]
        let dx = b.0 - a.0
        let dy = b.1 - a.1
        let dz = b.2 - a.2
        path_len = path_len + (dx * dx + dy * dy + dz * dz).sqrt()
      }
      let vol_mm3 = area * path_len
      if vol_mm3 > 1.0e-3 {
        let mass = vol_mm3 * 1.0e-9 * density.to_kg_per_m3()
        let (x0, x1, y0, y1, z0, z1) = shape.bounding_box()
        let sx = if x1 - x0 > 1.0e-3 { x1 - x0 } else { 1.0 }
        let sy = if y1 - y0 > 1.0e-3 { y1 - y0 } else { 1.0 }
        let sz = if z1 - z0 > 1.0e-3 { z1 - z0 } else { 1.0 }
        let origin = @urdf.Origin::from_mm_deg(
          x=(x0 + x1) / 2.0,
          y=(y0 + y1) / 2.0,
          z=(z0 + z1) / 2.0,
        )
        return Some(
          @urdf.Inertial::from_box(
            sx / 1000.0,
            sy / 1000.0,
            sz / 1000.0,
            mass~,
            origin~,
          ),
        )
      }
      None
    }
    @step_cad.Shape::Difference(diff) => {
      let base_in = node_inertial(diff.base, density)
      let mut cut_mass = 0.0
      for cutter in diff.cutters {
        cut_mass = cut_mass + node_inertial(cutter, density).mass
      }
      let min_mass = base_in.mass * 0.08
      let net_mass = if base_in.mass - cut_mass < min_mass {
        min_mass
      } else {
        base_in.mass - cut_mass
      }
      let scale = if base_in.mass > 1.0e-12 {
        net_mass / base_in.mass
      } else {
        1.0
      }
      Some(
        @urdf.Inertial::new(
          net_mass,
          base_in.inertia.scale(scale),
          origin=base_in.origin,
        ),
      )
    }
    @step_cad.Shape::Union(union) => {
      let parts = union.nodes.map(fn(child) { node_inertial(child, density) })
      if parts.length() > 0 {
        Some(@urdf.Inertial::combine(parts))
      } else {
        None
      }
    }
    @step_cad.Shape::Fillet(f) => Some(node_inertial(f.base, density))
    @step_cad.Shape::Chamfer(c) => Some(node_inertial(c.base, density))
    _ => None
  }
}

///|
/// Computes physical inertial for a `SceneNode`, accounting for true shape
/// volume and rigid node placement.
fn node_inertial(
  node : @step_cad.SceneNode,
  density : @urdf.Density,
) -> @urdf.Inertial {
  match local_shape_inertial(node.shape, density) {
    Some(local_in) =>
      local_in.transform_by(
        step_to_urdf_transform(@step_cad.Transform::from_node(node)),
      )
    None => {
      let (x0, x1, y0, y1, z0, z1) = node.bounding_box()
      let sx = if x1 - x0 > 1.0e-3 { x1 - x0 } else { 1.0 }
      let sy = if y1 - y0 > 1.0e-3 { y1 - y0 } else { 1.0 }
      let sz = if z1 - z0 > 1.0e-3 { z1 - z0 } else { 1.0 }
      let origin = @urdf.Origin::from_mm_deg(
        x=(x0 + x1) / 2.0,
        y=(y0 + y1) / 2.0,
        z=(z0 + z1) / 2.0,
      )
      @urdf.Inertial::from_box_density(
        sx / 1000.0,
        sy / 1000.0,
        sz / 1000.0,
        density~,
        origin~,
      )
    }
  }
}

///|
/// Builds one `BodyPart` from an already placed scene node.
fn body_part_from_placed_node(
  placed : @step_cad.SceneNode,
  density : @urdf.Density,
  part : PartMeta?,
) -> BodyPart {
  let (x0, x1, y0, y1, z0, z1) = tight_placed_bounds(placed)
  let sx = if x1 - x0 > 1.0e-3 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-3 { y1 - y0 } else { 1.0 }
  let sz = if z1 - z0 > 1.0e-3 { z1 - z0 } else { 1.0 }
  let origin = @urdf.Origin::from_mm_deg(
    x=(x0 + x1) / 2.0,
    y=(y0 + y1) / 2.0,
    z=(z0 + z1) / 2.0,
  )
  let inertial = node_inertial(placed, density)
  let collision = @urdf.Collision::new(
    @urdf.Geometry::box_mm(sx, sy, sz),
    name=Some(placed.name),
    origin~,
  )
  BodyPart::custom(
    placed.name,
    placed,
    inertial,
    collisions=[collision],
    density~,
    part~,
  )
}

///|
/// Copies a STEP component's semantic mate connectors onto a CAD component.
///
/// Names are preserved (optionally prefixed). The implicit `"origin"` mate
/// always survives, and duplicate names keep the first connector.
fn Component::add_step_connectors(
  self : Component,
  step_comp : @step_common.Component,
  connector_prefix~ : String = "",
  only_prefix~ : String? = None,
) -> Component {
  let mut comp = self
  for connector in step_comp.connectors() {
    let keep = match only_prefix {
      Some(prefix) =>
        connector.name == prefix || connector.name.has_prefix(prefix + "-")
      None => true
    }
    if !keep {
      continue
    }
    let name = connector_prefix + connector.name
    if comp.mates.contains(name) {
      continue
    }
    comp = comp.add_mate({ ..connector, name, })
  }
  comp
}

///|
/// Converts one STEP primitive component into CAD bodies.
///
/// Each layer of the STEP component becomes a `BodyPart` in the local frame
/// placed by the millimeter/degree offset. The first body receives `part` so a
/// multi-layer primitive (a screw shank, head, and socket, or a bearing's
/// rings and balls) counts once in the bill of materials.
pub fn BodyPart::from_step_component(
  step_comp : @step_common.Component,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  part~ : PartMeta? = None,
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> Array[BodyPart] {
  let xform = urdf_transform_from_mm_deg(
    x_mm~,
    y_mm~,
    z_mm~,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let bodies : Array[BodyPart] = []
  let mut first = true
  for node in step_comp.nodes() {
    let safe = flatten_chamfered_prism(node)
    let placed = transform_scene_node_urdf(safe, xform)
    let body_part = if first { part } else { None }
    bodies.push(body_part_from_placed_node(placed, density, body_part))
    first = false
  }
  bodies
}

///|
/// Imports an exact vendor STEP file as a purchased body.
///
/// The imported B-Rep is emitted verbatim (rigidly placed by the body's
/// transform) in the flat STEP output. The URDF, collision checks, and glTF
/// fallback use the imported solid's bounding box, so the body has a real
/// mass, a conservative collision primitive, and a box visual without
/// re-tessellating the vendor geometry.
pub fn BodyPart::imported_step(
  name : String,
  step_text : String,
  source~ : String = "",
  density~ : @urdf.Density = @urdf.Density::g_per_cm3(1.85),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
  part~ : PartMeta? = None,
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> BodyPart {
  let imported = match @step_cad.ImportedStep::from_string(step_text, source~) {
    Ok(imported) => imported.renamed(name)
    Err(info) =>
      abort(
        "error: could not import STEP for body '\{name}'" +
        (if source == "" { "" } else { " from " + source }) +
        ": " +
        info.message,
      )
  }
  let shape = imported.as_shape().with_name(name).with_color(color)
  let xform = urdf_transform_from_mm_deg(
    x_mm~,
    y_mm~,
    z_mm~,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let placed = transform_scene_node_urdf(shape, xform)
  let (x0, x1, y0, y1, z0, z1) = placed.bounding_box()
  let sx = if x1 - x0 > 1.0e-3 { x1 - x0 } else { 1.0 }
  let sy = if y1 - y0 > 1.0e-3 { y1 - y0 } else { 1.0 }
  let sz = if z1 - z0 > 1.0e-3 { z1 - z0 } else { 1.0 }
  let origin = @urdf.Origin::from_mm_deg(
    x=(x0 + x1) / 2.0,
    y=(y0 + y1) / 2.0,
    z=(z0 + z1) / 2.0,
  )
  let inertial = @urdf.Inertial::from_box_density(
    sx / 1000.0,
    sy / 1000.0,
    sz / 1000.0,
    density~,
    origin~,
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::box_mm(sx, sy, sz),
    name=Some(name),
    origin~,
  )
  BodyPart::custom(
    name,
    placed,
    inertial,
    collisions=[collision],
    density~,
    part~,
  )
}

///|
/// Converts a STEP primitive component into a CAD `Component`.
///
/// The component inherits the primitive's description, its metadata as design
/// parameters, and its modeled-feature list.
pub fn Component::from_step_component(
  name : String,
  step_comp : @step_common.Component,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  part~ : PartMeta? = None,
  connector_prefix~ : String = "",
  include_connectors~ : Bool = true,
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> Component {
  let meta = step_comp.metadata()
  let mut comp = Component::new(name, description=step_comp.description())
  comp = comp
    .with_param("designation", meta.designation)
    .with_param("standard", meta.standard)
    .with_param("family", meta.family)
    .with_param("size", meta.size)
    .with_param("features_modeled", step_comp.features().modeled.join(","))
  comp = comp.add_bodies(
    BodyPart::from_step_component(
      step_comp,
      density~,
      part=None,
      x_mm~,
      y_mm~,
      z_mm~,
      rx_deg~,
      ry_deg~,
      rz_deg~,
    ),
  )
  if include_connectors {
    comp = comp.add_step_connectors(step_comp, connector_prefix~)
  }
  match part {
    Some(p) => comp.with_part(p)
    None => comp
  }
}

///|
/// The names of a multi-layer STEP component's layers, in model order.
pub fn step_component_layer_names(
  step_comp : @step_common.Component,
) -> Array[String] {
  step_comp.layers().map(fn(layer) { layer.name })
}

///|
/// Builds a CAD `Component` from the layers of a multi-layer STEP component
/// that match `keep_layer`.
fn Component::from_step_layers_matching(
  name : String,
  step_comp : @step_common.Component,
  keep_layer : (String) -> Bool,
  layer_label : String,
  connector_prefix_filter : String?,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  part~ : PartMeta? = None,
  connector_prefix~ : String = "",
  include_connectors~ : Bool = true,
  apply_placement~ : Bool = true,
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> Component {
  let xform = urdf_transform_from_mm_deg(
    x_mm~,
    y_mm~,
    z_mm~,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let mut comp = Component::new(name, description=step_comp.description())
  let mut first = true
  for layer in step_comp.layers() {
    let leaf = layer_leaf_name(layer.name)
    if !keep_layer(layer.name) && !keep_layer(leaf) {
      continue
    }
    let source = if apply_placement {
      placed_layer_node(layer)
    } else {
      layer.shape.with_name(layer.name).with_color(layer.color)
    }
    let placed = transform_scene_node_urdf(source, xform)
    comp = comp.add_body(
      body_part_from_placed_node(
        placed,
        density,
        if first {
          part
        } else {
          None
        },
      ),
    )
    first = false
  }
  comp = comp
    .with_param("designation", step_comp.metadata().designation)
    .with_param("layer", layer_label)
  if include_connectors {
    comp = comp.add_step_connectors(
      step_comp,
      connector_prefix~,
      only_prefix=connector_prefix_filter,
    )
  }
  match part {
    Some(p) => comp.with_part(p)
    None => comp
  }
}

///|
/// Converts one named layer of a multi-layer STEP component into a CAD
/// `Component`.
///
/// This splits a composite primitive (the sun, planet, and ring layers of a
/// Tier-1 planetary gearbox, or the rolling elements of a bearing) into
/// independent kinematic and printable links while preserving each layer's
/// exact geometry. Semantic mate connectors whose names begin with the layer
/// name are propagated; the implicit `"origin"` mate always exists.
pub fn Component::from_step_layer(
  name : String,
  step_comp : @step_common.Component,
  layer_name : String,
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  part~ : PartMeta? = None,
  connector_prefix~ : String = "",
  include_connectors~ : Bool = true,
  apply_placement~ : Bool = true,
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> Component {
  Component::from_step_layers_matching(
    name,
    step_comp,
    fn(candidate) { candidate == layer_name },
    layer_name,
    Some(layer_name),
    density~,
    part~,
    connector_prefix~,
    include_connectors~,
    apply_placement~,
    x_mm~,
    y_mm~,
    z_mm~,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
}

///|
/// Converts a selected subset of named layers from a multi-layer STEP
/// component into a single CAD `Component` whose bodies move together as one
/// rigid link.
pub fn Component::from_step_layers(
  name : String,
  step_comp : @step_common.Component,
  layer_names : Array[String],
  label~ : String = "",
  density~ : @urdf.Density = @urdf.Density::steel_mild(),
  part~ : PartMeta? = None,
  connector_prefix~ : String = "",
  include_connectors~ : Bool = false,
  apply_placement~ : Bool = true,
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> Component {
  let layer_label = if label == "" { layer_names.join(",") } else { label }
  Component::from_step_layers_matching(
    name,
    step_comp,
    fn(candidate) { layer_names.contains(candidate) },
    layer_label,
    None,
    density~,
    part~,
    connector_prefix~,
    include_connectors~,
    apply_placement~,
    x_mm~,
    y_mm~,
    z_mm~,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
}
