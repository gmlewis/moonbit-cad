///|
/// Compiles a `Component` tree into URDF links, joints, transmissions, and a
/// complete `@urdf.Robot`, with optional mesh visuals backed by one glTF file
/// per link.

///|
/// How a compiled link's visuals are represented.
pub(all) enum VisualMode {
  /// One primitive visual per body, matching its analytical collision.
  Primitives
  /// One mesh visual per link, referencing `package://<pkg>/meshes/<link>.gltf`.
  MeshPackage(String)
}

///|
/// A URDF link plus the CAD bodies that produced it.
pub(all) struct CompiledLink {
  name : String
  bodies : Array[BodyPart]
  urdf_link : @urdf.Link
}

///|
fn identity_mate(name : String) -> @step_common.MateConnector {
  @step_common.MateConnector::new(name)
}

///|
/// transform_of_placement converts a shared millimetre/degree placement to a
/// URDF metre/radian transform.
fn transform_of_placement(p : @step_common.Placement) -> @urdf.Transform {
  let (xyz, rpy) = @step_common.MateConnector::new("snap", placement=p).to_m_rad()
  @urdf.Transform::from_origin(@urdf.Origin::new(xyz~, rpy~))
}

///|
/// placement_of_transform converts a URDF metre/radian transform to a shared
/// millimetre/degree placement.
fn placement_of_transform(t : @urdf.Transform) -> @step_common.Placement {
  let origin = t.to_origin()
  @step_common.MateConnector::from_m_rad("snap", origin.xyz, origin.rpy).placement
}

///|
fn joint_type_of(kind : ConnectionKind) -> @urdf.JointType {
  match kind {
    Fixed => @urdf.JointType::Fixed
    Revolute(_) => @urdf.JointType::Revolute
    Continuous(_) => @urdf.JointType::Continuous
    Prismatic(_) => @urdf.JointType::Prismatic
    MergeRigid => @urdf.JointType::Fixed
  }
}

///|
fn limit_of(kind : ConnectionKind) -> @urdf.JointLimit? {
  match kind {
    Revolute(limit) => Some(limit)
    Continuous(limit) => limit
    Prismatic(limit) => Some(limit)
    _ => None
  }
}

///|
/// Builds a URDF link from the final bodies in its local frame.
fn build_urdf_link(
  link_name : String,
  bodies : Array[BodyPart],
  mode : VisualMode,
) -> @urdf.Link {
  let mut link = @urdf.Link::new(link_name)
  if bodies.length() > 0 {
    let inertials = bodies.map(fn(b) { b.inertial })
    link = link.with_inertial(@urdf.Inertial::combine(inertials))
  }
  for body in bodies {
    for collision in body.collisions {
      link = link.add_collision(collision)
    }
  }
  match mode {
    Primitives =>
      for body in bodies {
        let rgba = rgb_to_rgba(body.node.color)
        let material = @urdf.Material::color_only(link_name + "_material", rgba)
        if body.collisions.length() > 0 {
          let c = body.collisions[0]
          link = link.add_visual(
            @urdf.Visual::new(c.geometry, origin=c.origin).with_material(
              material,
            ),
          )
        } else {
          let (x0, x1, y0, y1, z0, z1) = body.node.bounding_box()
          let geometry = @urdf.Geometry::box_mm(x1 - x0, y1 - y0, z1 - z0)
          let origin = @urdf.Origin::from_mm_deg(
            x=(x0 + x1) / 2.0,
            y=(y0 + y1) / 2.0,
            z=(z0 + z1) / 2.0,
          )
          link = link.add_visual(
            @urdf.Visual::new(geometry, origin~).with_material(material),
          )
        }
      }
    MeshPackage(pkg) =>
      if bodies.length() > 0 {
        let geometry = @urdf.Geometry::mesh_mm(
          "package://\{pkg}/meshes/\{link_name}.gltf",
        )
        let rgba = rgb_to_rgba(bodies[0].node.color)
        let material = @urdf.Material::color_only(link_name + "_material", rgba)
        link = link.add_visual(
          @urdf.Visual::new(geometry, origin=@urdf.Origin::identity()).with_material(
            material,
          ),
        )
      }
  }
  link
}

///|
/// Mutable accumulator for the recursive compile.
priv struct CompileCtx {
  links : Array[CompiledLink]
  joints : Array[@urdf.Joint]
  transmissions : Array[@urdf.Transmission]
  mode : VisualMode
}

///|
/// Merges a child component's bodies and mates into an existing link frame,
/// queuing any non-merged sub-attachments onto `kinematic_out`.
fn merge_rigid_into(
  bodies : Array[BodyPart],
  mates : Map[String, @step_common.MateConnector],
  kinematic_out : Array[Attachment],
  att : Attachment,
  p_mate : @step_common.MateConnector,
  c_mate : @step_common.MateConnector,
) -> Unit {
  let pair = att.spec.pair
  let (snap_placement, _axis) = @step_common.snap_connectors(
    p_mate,
    c_mate,
    offset_mm=pair.offset_mm,
    twist_rad=pair.twist_deg * @math.PI / 180.0,
    flip_axis=pair.flip_axis,
  )
  let snap_xform = transform_of_placement(snap_placement)
  let snap_shared = placement_of_transform(snap_xform)
  for body in att.child.bodies {
    bodies.push(body.transform_by(snap_xform))
  }
  for mate_name, mate in att.child.mates {
    let rebased = mate.transformed(snap_shared)
    let qualified = "\{att.child.name}.\{mate_name}"
    mates.set(qualified, rebased)
    if !mates.contains(mate_name) {
      mates.set(mate_name, rebased)
    }
  }
  // Re-home the merged child's own attachments onto this link.
  for sub in att.child.attachments {
    let remapped_pair = @step_common.MatePair::new(
      parent="\{att.child.name}.\{sub.spec.pair.parent}",
      child=sub.spec.pair.child,
      offset_mm=sub.spec.pair.offset_mm,
      twist_deg=sub.spec.pair.twist_deg,
      flip_axis=sub.spec.pair.flip_axis,
      fit=sub.spec.pair.fit,
      description=sub.spec.pair.description,
    )
    let remapped = { ..sub, spec: { ..sub.spec, pair: remapped_pair, }, }
    collect_attachment(bodies, mates, kinematic_out, remapped)
  }
}

///|
/// First pass over a link's attachments: folds `MergeRigid` children into
/// `bodies` and `mates` immediately and queues kinematic attachments for the
/// second pass.
fn collect_attachment(
  bodies : Array[BodyPart],
  mates : Map[String, @step_common.MateConnector],
  kinematic_out : Array[Attachment],
  att : Attachment,
) -> Unit {
  match att.spec.kind {
    MergeRigid => {
      let p_mate = mates
        .get(att.spec.pair.parent)
        .unwrap_or(identity_mate(att.spec.pair.parent))
      let c_mate = att.child
        .get_mate(att.spec.pair.child)
        .unwrap_or(identity_mate(att.spec.pair.child))
      merge_rigid_into(bodies, mates, kinematic_out, att, p_mate, c_mate)
    }
    _ => kinematic_out.push(att)
  }
}

///|
/// Emits a kinematic joint and compiles the child as its own link.
fn attach_kinematic(
  ctx : CompileCtx,
  link_name : String,
  att : Attachment,
  p_mate : @step_common.MateConnector,
  c_mate : @step_common.MateConnector,
) -> Unit {
  let rebase_inv = transform_of_placement(c_mate.placement).inverse()
  let rebase_shared = placement_of_transform(rebase_inv)
  let child_bodies : Array[BodyPart] = att.child.bodies.map(fn(b) {
    b.transform_by(rebase_inv)
  })
  let child_mates : Map[String, @step_common.MateConnector] = Map([])
  for mate_name, mate in att.child.mates {
    child_mates.set(mate_name, mate.transformed(rebase_shared))
  }
  let c_mate_at_origin = @step_common.MateConnector::new(
    c_mate.name,
    axis=@step_common.normalize_dir(rebase_inv.apply_dir(c_mate.axis)),
  )
  let pair = att.spec.pair
  let mut joint = @urdf.Joint::from_mates(
    att.joint_name,
    joint_type_of(att.spec.kind),
    parent_link=link_name,
    parent_mate=p_mate,
    child_link=att.child.name,
    child_mate=c_mate_at_origin,
    offset=pair.offset_mm / 1000.0,
    angle_rad=pair.twist_deg * @math.PI / 180.0,
    flip_axis=pair.flip_axis,
    limit=limit_of(att.spec.kind),
    dynamics=att.spec.dynamics,
  )
  match att.spec.mimic {
    Some(mimic) => joint = joint.with_mimic(mimic)
    None => ()
  }
  ctx.joints.push(joint)
  match att.spec.transmission_reduction {
    Some(reduction) =>
      ctx.transmissions.push(
        @urdf.Transmission::simple(
          "\{att.joint_name}_trans",
          att.joint_name,
          "\{att.joint_name}_motor",
          reduction~,
        ),
      )
    None => ()
  }
  compile_link(
    ctx,
    att.child.name,
    child_bodies,
    child_mates,
    att.child.attachments,
  )
}

///|
/// Collects bodies and mates (following rigid merges), emits this link in
/// topological pre-order, and then recursively compiles its kinematic children.
fn compile_link(
  ctx : CompileCtx,
  link_name : String,
  bodies : Array[BodyPart],
  mates : Map[String, @step_common.MateConnector],
  attachments : Array[Attachment],
) -> Unit {
  let kinematic_atts : Array[Attachment] = []
  for att in attachments {
    collect_attachment(bodies, mates, kinematic_atts, att)
  }
  let urdf_link = build_urdf_link(link_name, bodies, ctx.mode)
  ctx.links.push({ name: link_name, bodies, urdf_link, })
  for att in kinematic_atts {
    let p_mate = mates
      .get(att.spec.pair.parent)
      .unwrap_or(identity_mate(att.spec.pair.parent))
    let c_mate = att.child
      .get_mate(att.spec.pair.child)
      .unwrap_or(identity_mate(att.spec.pair.child))
    attach_kinematic(ctx, link_name, att, p_mate, c_mate)
  }
}

///|
/// Compiles this component tree into links, joints, and transmissions.
pub fn Component::compile_links(
  self : Component,
  package_name~ : String? = None,
) -> (Array[CompiledLink], Array[@urdf.Joint], Array[@urdf.Transmission]) {
  let mode = match package_name {
    Some(pkg) => MeshPackage(pkg)
    None => Primitives
  }
  let ctx : CompileCtx = { links: [], joints: [], transmissions: [], mode, }
  let bodies : Array[BodyPart] = []
  for body in self.bodies {
    bodies.push(body)
  }
  let mates : Map[String, @step_common.MateConnector] = Map([])
  for mate_name, mate in self.mates {
    mates.set(mate_name, mate)
  }
  compile_link(ctx, self.name, bodies, mates, self.attachments)
  (ctx.links, ctx.joints, ctx.transmissions)
}

///|
/// Builds a complete URDF robot from the component tree.
pub fn Component::to_robot(
  self : Component,
  package_name~ : String? = None,
) -> @urdf.Robot {
  let (links, joints, transmissions) = self.compile_links(package_name~)
  let mut robot = @urdf.Robot::new(
    self.display_name(),
    documentation=self.description,
  )
  for link in links {
    robot = robot.add_link(link.urdf_link)
  }
  robot = robot.add_joints(joints)
  for transmission in transmissions {
    robot = robot.add_transmission(transmission)
  }
  robot
}

///|
/// Returns a CAD design containing one link's bodies in its local frame.
pub fn Component::link_design(
  self : Component,
  link_name : String,
) -> @step_cad.Design? {
  let (links, _, _) = self.compile_links()
  for link in links {
    if link.name == link_name {
      let mut design = @step_cad.Design::new(name=link.name)
      for body in link.bodies {
        design = design.add(body.node)
      }
      return Some(design)
    }
  }
  None
}

///|
/// Builds a ROS 2 URDF bundle with per-link glTF meshes and printable STEP
/// parts.
pub fn Component::to_urdf_bundle(
  self : Component,
  package_name~ : String = "",
  include_step_parts~ : Bool = true,
) -> @urdf.UrdfBundle {
  let pkg = if package_name == "" { self.display_name() } else { package_name }
  let robot = self.to_robot(package_name=Some(pkg))
  let mut bundle = @urdf.UrdfBundle::new(pkg, robot)
  let (links, _, _) = self.compile_links(package_name=Some(pkg))
  for link in links {
    if link.bodies.length() > 0 {
      let mut design = @step_cad.Design::new(name=link.name)
      for body in link.bodies {
        design = design.add(body.node)
      }
      bundle = bundle.add_mesh_text(
        "meshes/\{link.name}.gltf",
        gltf_safe_design(design).to_gltf(),
      )
      if include_step_parts {
        bundle = bundle.add_mesh_text(
          "parts/\{link.name}.step",
          design.to_step_file(),
        )
      }
    }
  }
  if include_step_parts {
    for part in self.printable_parts() {
      bundle = bundle.add_mesh_text(
        "printable/\{sanitize_part_number(part.part_number)}.step",
        part.design.to_step_file(),
      )
    }
  }
  bundle
}
