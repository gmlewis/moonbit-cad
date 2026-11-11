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
    let (x0, x1, y0, y1, z0, z1) = placed.bounding_box()
    let sx = if x1 - x0 > 1.0e-3 { x1 - x0 } else { 1.0 }
    let sy = if y1 - y0 > 1.0e-3 { y1 - y0 } else { 1.0 }
    let sz = if z1 - z0 > 1.0e-3 { z1 - z0 } else { 1.0 }
    let cx = (x0 + x1) / 2.0
    let cy = (y0 + y1) / 2.0
    let cz = (z0 + z1) / 2.0
    let origin = @urdf.Origin::from_mm_deg(x=cx, y=cy, z=cz)
    let inertial = @urdf.Inertial::from_box_density(
      sx / 1000.0,
      sy / 1000.0,
      sz / 1000.0,
      density~,
      origin~,
    )
    let collision = @urdf.Collision::new(
      @urdf.Geometry::box_mm(sx, sy, sz),
      name=Some(placed.name),
      origin~,
    )
    let body_part = if first { part } else { None }
    bodies.push(
      BodyPart::custom(
        placed.name,
        placed,
        inertial,
        collisions=[collision],
        density~,
        part=body_part,
      ),
    )
    first = false
  }
  bodies
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
  match part {
    Some(p) => comp.with_part(p)
    None => comp
  }
}
