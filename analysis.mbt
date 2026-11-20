///|
/// Static gravity torque and actuator margin at one joint.
#derive(Debug, Eq)
pub(all) struct JointTorque {
  joint : String
  tau_static_nm : Double
  tau_rated_nm : Double
  safety_factor : Double
  /// True when the joint has no actuator effort limit (a passive linkage).
  passive : Bool
  ok : Bool
}

///|
/// Minimum world Z of one wheel or foot contact link.
#derive(Debug, Eq)
pub(all) struct ContactAlignment {
  name : String
  min_z_m : Double
}

///|
/// Whole-robot statics at one pose.
#derive(Debug, Eq)
pub(all) struct PoseAnalysis {
  name : String
  total_mass_kg : Double
  com_m : (Double, Double, Double)
  inertia : @urdf.Inertia
  joints : Array[JointTorque]
  contacts : Array[ContactAlignment]
  /// Largest left/right contact-link Z difference in metres.
  contact_misalignment_m : Double
}

///|
/// Statics across every requested pose.
#derive(Debug, Eq)
pub(all) struct RobotAnalysis {
  total_mass_kg : Double
  poses : Array[PoseAnalysis]
  warnings : Array[String]
}

///|
/// Placed-shape and interference analysis for a posed component tree.
///
/// The heavy lifting lives in `gmlewis/step/components/collision`: an AABB
/// broad phase followed by an oriented-box separating-axis test. This file
/// materialises each CAD body in its link's world frame so assemblies built
/// from `Component` can be checked for unintended positive-volume overlaps.

///|
/// Every body in the posed component tree as a placed oriented bounding box.
///
/// Bodies inside one link are treated as one rigid instance; merged fasteners
/// and bearings are therefore not reported against their host. The OBB uses
/// the body's exact local bounding box, which is conservative for curved
/// profiles.
pub fn Component::placed_shapes(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
) -> Array[@step_collision.PlacedShape] {
  let (links, _, _) = self.compile_links()
  let robot = self.to_robot()
  let fk = robot.forward_kinematics(joint_positions~)
  let shapes : Array[@step_collision.PlacedShape] = []
  for link in links {
    let world = fk.get(link.name).unwrap_or(@urdf.Transform::identity())
    let placement = @step_common.Placement::{
      rot: urdf_to_step_matrix(world.rot),
      trans: (
        world.trans.0 * 1000.0,
        world.trans.1 * 1000.0,
        world.trans.2 * 1000.0,
      ),
    }
    for body in link.bodies {
      let bounds = body.node.bounding_box()
      shapes.push({
        instance_name: link.name,
        layer_name: body.name,
        obb: @step_collision.Obb::from_placement(placement, bounds),
      })
    }
  }
  shapes
}

///|
/// Classifies every pair of distinct link instances in the posed tree.
pub fn Component::collision_reports(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
  tol~ : @step_collision.TolerancePolicy = @step_collision.TolerancePolicy::default(),
  policy~ : @step_collision.ContactPolicy = @step_collision.ContactPolicy::none(),
) -> Array[@step_collision.CollisionReport] {
  @step_collision.pair_reports(
    self.placed_shapes(joint_positions~),
    tol~,
    policy~,
  )
}

///|
/// One-line summaries of unintended positive-volume overlaps only.
pub fn Component::collision_checks(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
  tol~ : @step_collision.TolerancePolicy = @step_collision.TolerancePolicy::default(),
  policy~ : @step_collision.ContactPolicy = @step_collision.ContactPolicy::none(),
) -> Array[String] {
  let warnings : Array[String] = []
  for report in self.collision_reports(joint_positions~, tol~, policy~) {
    if report.is_collision() {
      warnings.push(report.summary())
    }
  }
  warnings
}

///|
/// A text report of every contact, interference, and collision pair.
pub fn Component::collision_report_text(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
  tol~ : @step_collision.TolerancePolicy = @step_collision.TolerancePolicy::default(),
  policy~ : @step_collision.ContactPolicy = @step_collision.ContactPolicy::none(),
) -> String {
  let reports = self.collision_reports(joint_positions~, tol~, policy~)
  let mut collisions = 0
  let mut contacts = 0
  let mut fits = 0
  let mut indeterminate = 0
  let mut out = "Interference analysis\n---------------------\n"
  for report in reports {
    match report.kind {
      @step_collision.CollisionKind::Collision => {
        collisions = collisions + 1
        out = out + "COLLISION | " + report.summary() + "\n"
      }
      @step_collision.CollisionKind::Contact => {
        contacts = contacts + 1
        out = out + "contact | " + report.summary() + "\n"
      }
      @step_collision.CollisionKind::InterferenceFit => {
        fits = fits + 1
        out = out + "fit | " + report.summary() + "\n"
      }
      @step_collision.CollisionKind::Indeterminate => {
        indeterminate = indeterminate + 1
        out = out + "indeterminate | " + report.summary() + "\n"
      }
      @step_collision.CollisionKind::Clearance => ()
    }
  }
  out +
  "summary: " +
  collisions.to_string() +
  " collision(s), " +
  contacts.to_string() +
  " contact(s), " +
  fits.to_string() +
  " declared fit(s), " +
  indeterminate.to_string() +
  " indeterminate\n"
}

///|
/// Transforms a link-local inertial into the world frame by composing its
/// origin with the link's world transform. The tensor itself is expressed in
/// the inertial frame, whose world orientation is now carried by
/// `origin.rpy`; `Inertial::combine` rotates it by exactly that frame.
fn world_inertial(
  inertial : @urdf.Inertial,
  world : @urdf.Transform,
) -> @urdf.Inertial {
  inertial.transform_by(world)
}

///|
/// Appends every link in the subtree rooted at `link_name` (including it).
fn collect_subtree(
  children : Map[String, Array[String]],
  link_name : String,
  out : Array[String],
) -> Unit {
  out.push(link_name)
  match children.get(link_name) {
    Some(names) =>
      for child in names {
        collect_subtree(children, child, out)
      }
    None => ()
  }
}

///|
fn vec3_dot(
  a : (Double, Double, Double),
  b : (Double, Double, Double),
) -> Double {
  a.0 * b.0 + a.1 * b.1 + a.2 * b.2
}

///|
/// Strips a left/right prefix so `l_wheel_link` and `r_wheel_link` group.
fn contact_group_key(name : String) -> String {
  let n = name.to_lower()
  if n.has_prefix("left_") {
    String::unsafe_substring(n, start=5, end=n.length())
  } else if n.has_prefix("right_") {
    String::unsafe_substring(n, start=6, end=n.length())
  } else if n.has_prefix("l_") || n.has_prefix("r_") {
    String::unsafe_substring(n, start=2, end=n.length())
  } else {
    n
  }
}

///|
/// Minimum world Z of a contact link's bodies, in metres.
fn contact_link_min_z(
  links : Array[CompiledLink],
  fk : Map[String, @urdf.Transform],
  link_name : String,
) -> Double? {
  let world = fk.get(link_name).unwrap_or(@urdf.Transform::identity())
  let mut found = false
  let mut min_z = 1.0e18
  for link in links {
    if link.name != link_name {
      continue
    }
    for body in link.bodies {
      let placed = transform_scene_node_urdf(body.node, world)
      let (_x0, _x1, _y0, _y1, z0, _z1) = placed.bounding_box()
      let z = z0 / 1000.0
      if z < min_z {
        min_z = z
      }
      found = true
    }
  }
  if found {
    Some(min_z)
  } else {
    None
  }
}

///|
fn analyze_pose(
  robot : @urdf.Robot,
  links : Array[CompiledLink],
  joint_positions : Map[String, Double],
  pose_name : String,
) -> PoseAnalysis {
  let fk = robot.forward_kinematics(joint_positions~)
  let world_inertials : Array[@urdf.Inertial] = []
  for link in robot.links {
    match link.inertial {
      Some(inertial) =>
        world_inertials.push(
          world_inertial(
            inertial,
            fk.get(link.name).unwrap_or(@urdf.Transform::identity()),
          ),
        )
      None => ()
    }
  }
  let combined = @urdf.Inertial::combine(world_inertials)
  let total_mass = combined.mass
  let com = combined.origin.xyz

  // Parent -> child link names for subtree torque sums.
  let children : Map[String, Array[String]] = Map([])
  for joint in robot.joints {
    match children.get(joint.parent) {
      Some(names) => names.push(joint.child)
      None => children.set(joint.parent, [joint.child])
    }
  }
  // Link inertials in world, keyed by link, for subtree sums.
  let link_world : Map[String, @urdf.Inertial] = Map([])
  for link in robot.links {
    match link.inertial {
      Some(inertial) =>
        link_world.set(
          link.name,
          world_inertial(
            inertial,
            fk.get(link.name).unwrap_or(@urdf.Transform::identity()),
          ),
        )
      None => ()
    }
  }
  let gravity = 9.80665
  let joints : Array[JointTorque] = []
  for joint in robot.joints {
    let revolute = match joint.joint_type {
      Revolute | Continuous => true
      _ => false
    }
    if !revolute {
      continue
    }
    let child_world = fk.get(joint.child).unwrap_or(@urdf.Transform::identity())
    let r_joint = child_world.trans
    let axis_world = child_world.apply_dir(joint.axis)
    let subtree : Array[String] = []
    collect_subtree(children, joint.child, subtree)
    // Sum the moments of every subtree link before projecting onto the axis so
    // opposing link moments cancel, as they physically do.
    let mut moment = (0.0, 0.0, 0.0)
    for name in subtree {
      match link_world.get(name) {
        Some(inertial) =>
          if inertial.mass > 0.0 {
            let r = (
              inertial.origin.xyz.0 - r_joint.0,
              inertial.origin.xyz.1 - r_joint.1,
              inertial.origin.xyz.2 - r_joint.2,
            )
            let force = (0.0, 0.0, -inertial.mass * gravity)
            let m = vec3_cross(r, force)
            moment = (moment.0 + m.0, moment.1 + m.1, moment.2 + m.2)
          }
        None => ()
      }
    }
    let tau = vec3_dot(moment, axis_world).abs()
    let rated = match joint.limit {
      Some(limit) => limit.effort
      None => 0.0
    }
    // A joint with no actuator effort is a passive linkage (4-bar knee, guide,
    // ...). It still carries gravity, but there is no motor to size.
    let passive = rated <= 0.0
    let safety = if passive {
      0.0
    } else {
      rated / (if tau > 1.0e-6 { tau } else { 1.0e-6 })
    }
    joints.push({
      joint: joint.name,
      tau_static_nm: tau,
      tau_rated_nm: rated,
      safety_factor: safety,
      passive,
      ok: if passive {
        true
      } else {
        safety >= 1.5
      },
    })
  }

  let contacts : Array[ContactAlignment] = []
  let group_min : Map[String, Double] = Map([])
  for link in links {
    let lower = link.name.to_lower()
    // Cosmetic motor bells ride on the wheel axle but are not ground contact.
    if lower.contains("_rotor") {
      continue
    }
    if lower.contains("wheel") ||
      lower.contains("foot") ||
      lower.contains("tire") {
      match contact_link_min_z(links, fk, link.name) {
        Some(min_z) => {
          contacts.push({ name: link.name, min_z_m: min_z, })
          let key = contact_group_key(link.name)
          match group_min.get(key) {
            Some(existing) => if min_z < existing { group_min.set(key, min_z) }
            None => group_min.set(key, min_z)
          }
        }
        None => ()
      }
    }
  }
  // Compare left/right links sharing a group key by their min Z spread.
  let mut misalignment = 0.0
  let group_max : Map[String, Double] = Map([])
  for contact in contacts {
    let key = contact_group_key(contact.name)
    match group_max.get(key) {
      Some(existing) =>
        if contact.min_z_m > existing {
          group_max.set(key, contact.min_z_m)
        }
      None => group_max.set(key, contact.min_z_m)
    }
  }
  for key, minimum in group_min {
    match group_max.get(key) {
      Some(maximum) => {
        let delta = maximum - minimum
        if delta > misalignment {
          misalignment = delta
        }
      }
      None => ()
    }
  }

  {
    name: pose_name,
    total_mass_kg: total_mass,
    com_m: com,
    inertia: combined.inertia,
    joints,
    contacts,
    contact_misalignment_m: misalignment,
  }
}

///|
/// Analyzes whole-robot statics at every requested pose: composite mass and
/// CoM, static gravity torque at each revolute/continuous joint versus the
/// URDF effort limit, safety margins, and wheel/foot ground-contact alignment.
///
/// An empty `poses` array analyzes the zero pose under the name `"default"`.
pub fn analyze_robot(
  component : Component,
  poses : Array[(String, Map[String, Double])],
) -> RobotAnalysis {
  let robot = component.to_robot()
  let (links, _, _) = component.compile_links()
  let requested = if poses.length() == 0 {
    [("default", Map([]))]
  } else {
    poses
  }
  let pose_analyses : Array[PoseAnalysis] = []
  for entry in requested {
    pose_analyses.push(analyze_pose(robot, links, entry.1, entry.0))
  }
  let total_mass = if pose_analyses.length() > 0 {
    pose_analyses[0].total_mass_kg
  } else {
    0.0
  }
  let warnings : Array[String] = []
  for pose in pose_analyses {
    for joint in pose.joints {
      if !joint.ok {
        warnings.push(
          pose.name +
          ": joint '" +
          joint.joint +
          "' safety factor " +
          joint.safety_factor.to_string() +
          " < 1.5 (static " +
          joint.tau_static_nm.to_string() +
          " Nm, rated " +
          joint.tau_rated_nm.to_string() +
          " Nm)",
        )
      }
    }
    if pose.contact_misalignment_m > 1.0e-3 {
      warnings.push(
        pose.name +
        ": wheel/foot ground contacts differ by " +
        (pose.contact_misalignment_m * 1000.0).to_string() +
        " mm",
      )
    }
  }
  { total_mass_kg: total_mass, poses: pose_analyses, warnings, }
}
