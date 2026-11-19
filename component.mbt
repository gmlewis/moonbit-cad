///|
/// A physical solid inside a component.
///
/// A `BodyPart` carries the exact CAD solid (`node`, millimeters/degrees) and
/// the matching URDF mass properties (`inertial`, meters/radians) so the same
/// geometry feeds both the STEP exporter and the robot simulator. Collisions
/// are cheap analytical primitives in the same local frame.
pub(all) struct BodyPart {
  name : String
  node : @step_cad.SceneNode
  density : @urdf.Density
  inertial : @urdf.Inertial
  collisions : Array[@urdf.Collision]
  /// Purchasing/manufacturing metadata for this solid.
  part : PartMeta?
}

///|
/// Builds a rectangular box body from millimeter dimensions and a
/// millimeter/degree pose.
pub fn BodyPart::box_mm(
  name : String,
  sx_mm : Double,
  sy_mm : Double,
  sz_mm : Double,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> BodyPart {
  let origin = @urdf.Origin::from_mm_deg(
    x=x_mm,
    y=y_mm,
    z=z_mm,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let node = transform_scene_node_urdf(
    centered_cuboid_node(sx_mm, sy_mm, sz_mm, name~, color~),
    @urdf.Transform::from_origin(origin),
  )
  let inertial = @urdf.Inertial::from_box_density(
    sx_mm / 1000.0,
    sy_mm / 1000.0,
    sz_mm / 1000.0,
    density~,
    origin~,
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::box_mm(sx_mm, sy_mm, sz_mm),
    name=Some(name),
    origin~,
  )
  { name, node, density, inertial, collisions: [collision], part: None, }
}

///|
/// Builds a solid cylinder body, axis along Z, centered on its own frame.
pub fn BodyPart::cylinder_mm(
  name : String,
  diameter_mm : Double,
  length_mm : Double,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> BodyPart {
  let origin = @urdf.Origin::from_mm_deg(
    x=x_mm,
    y=y_mm,
    z=z_mm,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let node = transform_scene_node_urdf(
    centered_cylinder_node(diameter_mm, length_mm, name~, color~),
    @urdf.Transform::from_origin(origin),
  )
  let inertial = @urdf.Inertial::from_cylinder_density(
    diameter_mm / 2000.0,
    length_mm / 1000.0,
    density~,
    origin~,
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::cylinder_mm(diameter_mm / 2.0, length_mm),
    name=Some(name),
    origin~,
  )
  { name, node, density, inertial, collisions: [collision], part: None, }
}

///|
/// Builds a hollow tube body, axis along Z, centered on its own frame.
pub fn BodyPart::tube_mm(
  name : String,
  outer_diam_mm : Double,
  inner_diam_mm : Double,
  length_mm : Double,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> BodyPart {
  let origin = @urdf.Origin::from_mm_deg(
    x=x_mm,
    y=y_mm,
    z=z_mm,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let node = transform_scene_node_urdf(
    centered_tube_node(outer_diam_mm, inner_diam_mm, length_mm, name~, color~),
    @urdf.Transform::from_origin(origin),
  )
  let inertial = @urdf.Inertial::from_tube_density(
    inner_diam_mm / 2000.0,
    outer_diam_mm / 2000.0,
    length_mm / 1000.0,
    density~,
    origin~,
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::cylinder_mm(outer_diam_mm / 2.0, length_mm),
    name=Some(name),
    origin~,
  )
  { name, node, density, inertial, collisions: [collision], part: None, }
}

///|
/// Builds an extruded-profile body. Its mass comes from the true net profile
/// area; its inertia and collision use the profile's bounding box.
pub fn BodyPart::extruded_profile_mm(
  name : String,
  outer : Array[(Double, Double)],
  height_mm : Double,
  holes~ : Array[Array[(Double, Double)]] = [],
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> BodyPart {
  let origin = @urdf.Origin::from_mm_deg(
    x=x_mm,
    y=y_mm,
    z=z_mm,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let node = transform_scene_node_urdf(
    centered_extruded_profile_node(outer, height_mm, holes~, name~, color~),
    @urdf.Transform::from_origin(origin),
  )
  // Net cross-sectional area in square millimeters.
  let mut area_mm2 = @step_cad.polygon_area_2d(outer).abs()
  for hole in holes {
    area_mm2 = area_mm2 - @step_cad.polygon_area_2d(hole).abs()
  }
  let mass = area_mm2 / 1.0e6 * (height_mm / 1000.0) * density.to_kg_per_m3()
  // Bounding-box extents of the profile.
  let mut min_x = outer[0].0
  let mut max_x = outer[0].0
  let mut min_y = outer[0].1
  let mut max_y = outer[0].1
  for pt in outer {
    min_x = if pt.0 < min_x { pt.0 } else { min_x }
    max_x = if pt.0 > max_x { pt.0 } else { max_x }
    min_y = if pt.1 < min_y { pt.1 } else { min_y }
    max_y = if pt.1 > max_y { pt.1 } else { max_y }
  }
  let dx = max_x - min_x
  let dy = max_y - min_y
  let inertial = @urdf.Inertial::from_box(
    dx / 1000.0,
    dy / 1000.0,
    height_mm / 1000.0,
    mass~,
    origin~,
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::box_mm(dx, dy, height_mm),
    name=Some(name),
    origin~,
  )
  { name, node, density, inertial, collisions: [collision], part: None, }
}

///|
/// Builds a body from a pre-existing scene node and inertia.
pub fn BodyPart::custom(
  name : String,
  node : @step_cad.SceneNode,
  inertial : @urdf.Inertial,
  collisions~ : Array[@urdf.Collision] = [],
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  part~ : PartMeta? = None,
) -> BodyPart {
  { name, node, density, inertial, collisions, part, }
}

///|
/// Rigidly transforms a body (CAD node, inertia, and collision frames).
pub fn BodyPart::transform_by(
  self : BodyPart,
  urdf_xform : @urdf.Transform,
) -> BodyPart {
  let node = transform_scene_node_urdf(self.node, urdf_xform)
  let inertial = self.inertial.transform_by(urdf_xform)
  let collisions = self.collisions.map(fn(c) {
    let new_origin = urdf_xform
      .compose(@urdf.Transform::from_origin(c.origin))
      .to_origin()
    { ..c, origin: new_origin, }
  })
  { ..self, node, inertial, collisions, }
}

///|
/// Attaches purchasing/manufacturing metadata to this body.
pub fn BodyPart::with_part(self : BodyPart, part : PartMeta) -> BodyPart {
  { ..self, part: Some(part), }
}

///|
/// How an attached child component connects to its parent.
#derive(Debug)
pub(all) enum ConnectionKind {
  MergeRigid
  Fixed
  Revolute(@urdf.JointLimit)
  Continuous(@urdf.JointLimit?)
  Prismatic(@urdf.JointLimit)
}

///|
/// The kinematic parameters of an attachment plus the shared geometric mate
/// pair.
///
/// The pair owns the parent connector name, child connector name, offset, twist,
/// flip, and fit. `JointSpec` keeps only what is kinematic: the joint kind,
/// limits, dynamics, mimic, and transmission reduction.
#derive(Debug)
pub(all) struct JointSpec {
  kind : ConnectionKind
  pair : @step_common.MatePair
  dynamics : @urdf.JointDynamics?
  mimic : @urdf.JointMimic?
  transmission_reduction : Double?
}

///|
/// joint_pair builds the pair template used by the `JointSpec` constructors.
/// The parent and child names are filled in when the attachment is created.
fn joint_pair(
  offset_mm : Double,
  angle_deg : Double,
  flip_axis : Bool,
) -> @step_common.MatePair {
  @step_common.MatePair::new(
    parent="",
    child="",
    offset_mm~,
    twist_deg=angle_deg,
    flip_axis~,
  )
}

///|
/// Folds the child's bodies directly into the parent link: no joint is emitted.
pub fn JointSpec::merge_rigid(
  offset_mm~ : Double = 0.0,
  angle_deg~ : Double = 0.0,
  flip_axis~ : Bool = false,
) -> JointSpec {
  {
    kind: MergeRigid,
    pair: joint_pair(offset_mm, angle_deg, flip_axis),
    dynamics: None,
    mimic: None,
    transmission_reduction: None,
  }
}

///|
/// Creates a fixed kinematic joint.
pub fn JointSpec::fixed(
  offset_mm~ : Double = 0.0,
  angle_deg~ : Double = 0.0,
  flip_axis~ : Bool = false,
) -> JointSpec {
  {
    kind: Fixed,
    pair: joint_pair(offset_mm, angle_deg, flip_axis),
    dynamics: None,
    mimic: None,
    transmission_reduction: None,
  }
}

///|
/// Creates a revolute joint with the given limit.
pub fn JointSpec::revolute(
  limit : @urdf.JointLimit,
  offset_mm~ : Double = 0.0,
  angle_deg~ : Double = 0.0,
  flip_axis~ : Bool = false,
  dynamics~ : @urdf.JointDynamics? = None,
  mimic~ : @urdf.JointMimic? = None,
  transmission_reduction~ : Double? = None,
) -> JointSpec {
  {
    kind: Revolute(limit),
    pair: joint_pair(offset_mm, angle_deg, flip_axis),
    dynamics,
    mimic,
    transmission_reduction,
  }
}

///|
/// Creates a revolute joint from degree-based limits, converting each bound to
/// radians for the URDF joint limit.
pub fn JointSpec::revolute_deg(
  lower_deg~ : Double,
  upper_deg~ : Double,
  effort~ : Double,
  velocity~ : Double,
) -> JointSpec {
  let deg_to_rad = @math.PI / 180.0
  JointSpec::revolute(
    @urdf.JointLimit::new(
      effort~,
      velocity~,
      lower=Some(lower_deg * deg_to_rad),
      upper=Some(upper_deg * deg_to_rad),
    ),
  )
}

///|
/// Creates a continuous joint limited only by effort and velocity (no angular
/// bounds).
pub fn JointSpec::continuous_limit(
  effort~ : Double,
  velocity~ : Double,
) -> JointSpec {
  JointSpec::continuous(limit=Some(@urdf.JointLimit::new(effort~, velocity~)))
}

///|
/// Creates a continuous joint with an optional limit.
pub fn JointSpec::continuous(
  limit~ : @urdf.JointLimit? = None,
  offset_mm~ : Double = 0.0,
  angle_deg~ : Double = 0.0,
  flip_axis~ : Bool = false,
  dynamics~ : @urdf.JointDynamics? = None,
  mimic~ : @urdf.JointMimic? = None,
  transmission_reduction~ : Double? = None,
) -> JointSpec {
  {
    kind: Continuous(limit),
    pair: joint_pair(offset_mm, angle_deg, flip_axis),
    dynamics,
    mimic,
    transmission_reduction,
  }
}

///|
/// Creates a prismatic joint with the given limit.
pub fn JointSpec::prismatic(
  limit : @urdf.JointLimit,
  offset_mm~ : Double = 0.0,
  angle_deg~ : Double = 0.0,
  flip_axis~ : Bool = false,
  dynamics~ : @urdf.JointDynamics? = None,
  mimic~ : @urdf.JointMimic? = None,
  transmission_reduction~ : Double? = None,
) -> JointSpec {
  {
    kind: Prismatic(limit),
    pair: joint_pair(offset_mm, angle_deg, flip_axis),
    dynamics,
    mimic,
    transmission_reduction,
  }
}

///|
/// A child component snapped onto one of its parent's mates.
pub(all) struct Attachment {
  joint_name : String
  child : Component
  /// The resolved relationship: parent/child connector names, offset, twist,
  /// flip, and fit all live in the shared pair inside `spec`.
  spec : JointSpec
  /// False for children that belong to the parent as a purchased/assembled
  /// item (e.g. a motor rotor), so the BOM does not count them separately.
  bom_external : Bool
}

///|
/// A reusable, parameterized CAD + robotics building block.
///
/// Bodies provide B-Rep geometry and mass properties; mates are named frames
/// other components snap onto; attachments hold the child `Component` tree.
pub(all) struct Component {
  name : String
  description : String
  parameters : Map[String, String]
  bodies : Array[BodyPart]
  mates : Map[String, @step_common.MateConnector]
  attachments : Array[Attachment]
  /// Optional name for the exported robot/design when the root link name
  /// differs from the assembly name (e.g. `base_link` inside a Galileo robot).
  robot_name : String?
  /// Purchasing/manufacturing metadata when the whole component is one part.
  part : PartMeta?
  /// Typed electrical/mechanical/fluid/sensor interfaces.
  ports : Array[Port]
  /// Fastener schedule entries for this component.
  fasteners : Array[Fastener]
  /// Explicit fit records (nominal and allowed range).
  fits : Array[Fit]
  /// Electrical ratings when this component is an actuator.
  actuator : ActuatorSpec?
  /// Measuring characteristics when this component is a sensor.
  sensor : SensorSpec?
  /// PCB envelope metadata when this component is a circuit board.
  pcb : PcbSpec?
  /// Point-to-point cable runs belonging to this component.
  wiring : Array[WireRun]
  /// Joint-to-actuator control bindings declared on this component.
  control : Array[ControlBinding]
  /// Routed cable bundles belonging to this component.
  cables : Array[CableRoute]
}

///|
/// Creates an empty component with a default `"origin"` mate.
pub fn Component::new(name : String, description~ : String = "") -> Component {
  let mates : Map[String, @step_common.MateConnector] = Map([])
  mates.set("origin", @step_common.MateConnector::new("origin"))
  {
    name,
    description,
    parameters: Map([]),
    bodies: [],
    mates,
    attachments: [],
    robot_name: None,
    part: None,
    ports: [],
    fasteners: [],
    fits: [],
    actuator: None,
    sensor: None,
    pcb: None,
    wiring: [],
    control: [],
    cables: [],
  }
}

///|
/// Returns the name used for the exported robot and design: the explicit robot
/// name when set, otherwise the root component name.
pub fn Component::display_name(self : Component) -> String {
  self.robot_name.unwrap_or(self.name)
}

///|
/// Sets the exported robot/design name independently of the root link name.
pub fn Component::with_robot_name(self : Component, name : String) -> Component {
  { ..self, robot_name: Some(name), }
}

///|
/// Replaces the component description.
pub fn Component::with_description(
  self : Component,
  description : String,
) -> Component {
  { ..self, description, }
}

///|
/// Records a design parameter for documentation and STEP headers.
pub fn Component::with_param(
  self : Component,
  key : String,
  value : String,
) -> Component {
  self.parameters.set(key, value)
  self
}

///|
/// Appends a body to this component.
pub fn Component::add_body(self : Component, body : BodyPart) -> Component {
  self.bodies.push(body)
  self
}

///|
/// Appends several bodies to this component.
pub fn Component::add_bodies(
  self : Component,
  bodies : Array[BodyPart],
) -> Component {
  for body in bodies {
    self.bodies.push(body)
  }
  self
}

///|
/// Registers a mate connector on this component.
pub fn Component::add_mate(
  self : Component,
  mate : @step_common.MateConnector,
) -> Component {
  self.mates.set(mate.name, mate)
  self
}

///|
/// Registers a mate from millimeter/degree inputs.
pub fn Component::add_mate_mm_deg(
  self : Component,
  name : String,
  x~ : Double = 0.0,
  y~ : Double = 0.0,
  z~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
  axis~ : (Double, Double, Double) = (0.0, 0.0, 1.0),
) -> Component {
  self.add_mate(
    @step_common.MateConnector::from_mm_deg(
      name,
      x~,
      y~,
      z~,
      rx_deg~,
      ry_deg~,
      rz_deg~,
      axis~,
    ),
  )
}

///|
/// Looks up a mate connector by name.
pub fn Component::get_mate(
  self : Component,
  name : String,
) -> @step_common.MateConnector? {
  self.mates.get(name)
}

///|
/// Attaches a child component onto a parent mate.
pub fn Component::attach(
  self : Component,
  joint_name : String,
  parent_mate~ : String,
  child : Component,
  child_mate~ : String = "origin",
  spec~ : JointSpec = JointSpec::fixed(),
  bom_external~ : Bool = true,
) -> Component {
  let pair = @step_common.MatePair::new(
    parent=parent_mate,
    child=child_mate,
    offset_mm=spec.pair.offset_mm,
    twist_deg=spec.pair.twist_deg,
    flip_axis=spec.pair.flip_axis,
    fit=spec.pair.fit,
    description=spec.pair.description,
  )
  let spec = { ..spec, pair, }
  self.attachments.push({ joint_name, child, spec, bom_external, })
  self
}

///|
/// Attaches a child to a named component anywhere in this component's tree.
///
/// The tree's attachment arrays are shared, so this lets an assembly builder
/// reach a nested link (for example a motor's rotor) without rebuilding the
/// intermediate components.
pub fn Component::attach_to(
  self : Component,
  target_name : String,
  joint_name : String,
  parent_mate~ : String,
  child : Component,
  child_mate~ : String = "origin",
  spec~ : JointSpec = JointSpec::fixed(),
  bom_external~ : Bool = true,
) -> Component {
  if self.name == target_name {
    return self.attach(
      joint_name,
      parent_mate~,
      child,
      child_mate~,
      spec~,
      bom_external~,
    )
  }
  for i in 0..<self.attachments.length() {
    let att = self.attachments[i]
    let updated = att.child.attach_to(
      target_name,
      joint_name,
      parent_mate~,
      child,
      child_mate~,
      spec~,
      bom_external~,
    )
    self.attachments[i] = { ..att, child: updated, }
  }
  self
}

///|
/// Recursively sums the mass of every body in the component tree.
pub fn Component::total_mass_kg(self : Component) -> Double {
  let mut mass = 0.0
  for body in self.bodies {
    mass = mass + body.inertial.mass
  }
  for att in self.attachments {
    mass = mass + att.child.total_mass_kg()
  }
  mass
}
