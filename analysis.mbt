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
