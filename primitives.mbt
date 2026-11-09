///|
/// Bridges between the CAD (STEP, millimeters/degrees) and robotics (URDF,
/// meters/radians) worlds, plus centered primitive builders.
///
/// `@step_cad` places `Cuboid` corners at the origin and `Cylinder`/`tube`
/// bases at `Z = 0`, while URDF geometry is centered on its frame. The
/// `centered_*_node` helpers reconcile that difference so a `BodyPart`'s CAD
/// node and its URDF inertia/collision share one center of mass.

///|
/// Converts a CAD RGB color to a URDF RGBA color with an optional alpha.
pub fn rgb_to_rgba(c : @step_cad.Rgb, a~ : Double = 1.0) -> @urdf.Rgba {
  @urdf.Rgba::new(c.r, c.g, c.b, a~)
}

///|
/// Converts a URDF RGBA color to a CAD RGB color, dropping alpha.
pub fn rgba_to_rgb(c : @urdf.Rgba) -> @step_cad.Rgb {
  @step_cad.Rgb::new(c.r, c.g, c.b)
}

///|
/// Converts a URDF rotation matrix (radians) to a CAD rotation matrix (degrees
/// are only applied when a transform is converted; the matrix itself is
/// identical).
pub fn urdf_to_step_matrix(m : @urdf.Matrix3x3) -> @step_cad.Matrix3x3 {
  {
    m00: m.m00,
    m01: m.m01,
    m02: m.m02,
    m10: m.m10,
    m11: m.m11,
    m12: m.m12,
    m20: m.m20,
    m21: m.m21,
    m22: m.m22,
  }
}

///|
/// Converts a CAD rotation matrix to a URDF rotation matrix.
pub fn step_to_urdf_matrix(m : @step_cad.Matrix3x3) -> @urdf.Matrix3x3 {
  {
    m00: m.m00,
    m01: m.m01,
    m02: m.m02,
    m10: m.m10,
    m11: m.m11,
    m12: m.m12,
    m20: m.m20,
    m21: m.m21,
    m22: m.m22,
  }
}

///|
/// Converts a URDF transform (meters) to a CAD transform (millimeters).
pub fn urdf_to_step_transform(t : @urdf.Transform) -> @step_cad.Transform {
  {
    rot: urdf_to_step_matrix(t.rot),
    trans: (t.trans.0 * 1000.0, t.trans.1 * 1000.0, t.trans.2 * 1000.0),
  }
}

///|
/// Converts a CAD transform (millimeters) to a URDF transform (meters).
pub fn step_to_urdf_transform(t : @step_cad.Transform) -> @urdf.Transform {
  {
    rot: step_to_urdf_matrix(t.rot),
    trans: (t.trans.0 / 1000.0, t.trans.1 / 1000.0, t.trans.2 / 1000.0),
  }
}

///|
/// Applies a CAD transform (millimeters, degrees) to a scene node by composing
/// it with the node's own placement and re-deriving translation and extrinsic
/// Euler angles.
pub fn transform_scene_node(
  node : @step_cad.SceneNode,
  xform_mm : @step_cad.Transform,
) -> @step_cad.SceneNode {
  let composed = xform_mm.compose(@step_cad.Transform::from_node(node))
  let (rx, ry, rz) = @step_cad.matrix_to_euler(composed.rot)
  let (tx, ty, tz) = composed.trans
  // SceneNode is read-only outside the step package, so rebuild it from its
  // shape with the composed extrinsic Euler angles and translation.
  node.shape
  .with_name(node.name)
  .with_color(node.color)
  .rotate_x(rx)
  .rotate_y(ry)
  .rotate_z(rz)
  .translate(x=tx, y=ty, z=tz)
}

///|
/// Applies a URDF transform (meters) to a scene node.
pub fn transform_scene_node_urdf(
  node : @step_cad.SceneNode,
  urdf_xform : @urdf.Transform,
) -> @step_cad.SceneNode {
  transform_scene_node(node, urdf_to_step_transform(urdf_xform))
}

///|
/// Builds a cuboid whose geometric center is at the origin.
pub fn centered_cuboid_node(
  sx_mm : Double,
  sy_mm : Double,
  sz_mm : Double,
  name~ : String = "cuboid",
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @step_cad.SceneNode {
  @step_cad.Cuboid::new(sx_mm, sy_mm, sz_mm)
  .with_name(name)
  .with_color(color)
  .translate(x=-sx_mm / 2.0, y=-sy_mm / 2.0, z=-sz_mm / 2.0)
}

///|
/// Builds a cylinder whose geometric center is at the origin, axis along Z.
pub fn centered_cylinder_node(
  diameter_mm : Double,
  length_mm : Double,
  name~ : String = "cylinder",
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @step_cad.SceneNode {
  @step_cad.Cylinder::new(diameter_mm, length_mm)
  .with_name(name)
  .with_color(color)
  .translate(z=-length_mm / 2.0)
}

///|
/// Builds a hollow tube whose geometric center is at the origin, axis along Z.
pub fn centered_tube_node(
  outer_diam_mm : Double,
  inner_diam_mm : Double,
  length_mm : Double,
  segments~ : Int32 = 36,
  name~ : String = "tube",
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @step_cad.SceneNode {
  @step_cad.tube(outer_diam_mm, inner_diam_mm, length_mm, segments~)
  .with_name(name)
  .with_color(color)
  .translate(z=-length_mm / 2.0)
}

///|
/// Builds an extruded profile whose geometric center is at the origin along Z.
pub fn centered_extruded_profile_node(
  outer : Array[(Double, Double)],
  height_mm : Double,
  holes~ : Array[Array[(Double, Double)]] = [],
  name~ : String = "extrusion",
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @step_cad.SceneNode {
  @step_cad.ExtrudedProfile::new(outer, height_mm, holes~)
  .with_name(name)
  .with_color(color)
  .translate(z=-height_mm / 2.0)
}

///|
/// Builds a URDF transform from a millimeter/degree origin.
pub fn urdf_transform_from_mm_deg(
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> @urdf.Transform {
  @urdf.Transform::from_origin(
    @urdf.Origin::from_mm_deg(x=x_mm, y=y_mm, z=z_mm, rx_deg~, ry_deg~, rz_deg~),
  )
}
