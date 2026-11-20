///|
test "separated bodies report clearance and no collision" {
  let base = @cad.Component::new("base").add_body(
    @cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0),
  )
  let child = @cad.Component::new("child").add_body(
    @cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0),
  )
  let comp = base.attach(
    "child_joint",
    parent_mate="origin",
    child,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(offset_mm=50.0),
  )
  assert_eq(comp.collision_checks().length(), 0)
  let reports = comp.collision_reports()
  assert_true(reports.length() > 0)
  let text = comp.collision_report_text()
  assert_true(text.contains("0 collision(s)"))
}

///|
test "overlapping bodies report a collision" {
  let base = @cad.Component::new("base").add_body(
    @cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0),
  )
  let child = @cad.Component::new("child").add_body(
    @cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0),
  )
  let comp = base.attach(
    "child_joint",
    parent_mate="origin",
    child,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(),
  )
  let warnings = comp.collision_checks()
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0].contains("COLLISION") || warnings[0].contains("collision"),
  )
  let text = comp.collision_report_text()
  assert_true(text.contains("1 collision(s)"))
}

///|
test "bodies in one link are not cross-reported" {
  let comp = @cad.Component::new("part")
    .add_body(@cad.BodyPart::box_mm("body_a", 20.0, 20.0, 20.0))
    .add_body(@cad.BodyPart::box_mm("body_b", 10.0, 10.0, 10.0))
  assert_eq(comp.collision_checks().length(), 0)
}

///|
test "placed shapes carry world poses" {
  let base = @cad.Component::new("base").add_body(
    @cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0),
  )
  let child = @cad.Component::new("child").add_body(
    @cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0),
  )
  let comp = base.attach(
    "child_joint",
    parent_mate="origin",
    child,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(offset_mm=50.0),
  )
  let shapes = comp.placed_shapes()
  assert_eq(shapes.length(), 2)
  let child_shape = shapes[1]
  assert_true(child_shape.obb.center.2 > 40.0)
}

///|
fn analysis_arm(effort : Double) -> @cad.Component {
  let arm_body = @cad.BodyPart::custom(
    "arm_body",
    @step_cad.Cuboid::new(1.0, 0.1, 0.1).with_name("arm_body"),
    @urdf.Inertial::from_box(
      1.0,
      0.1,
      0.1,
      mass=2.0,
      origin=@urdf.Origin::new(xyz=(0.5, 0.0, 0.0)),
    ),
  )
  let base = @cad.Component::new("base").add_mate_mm_deg(
    "joint",
    axis=(0.0, 1.0, 0.0),
  )
  let arm = @cad.Component::new("arm").add_body(arm_body)
  base.attach(
    "arm_joint",
    parent_mate="joint",
    arm,
    child_mate="origin",
    spec=@cad.JointSpec::revolute(
      @urdf.JointLimit::new(
        effort~,
        velocity=1.0,
        lower=Some(-3.0),
        upper=Some(3.0),
      ),
    ),
  )
}

///|
test "static gravity torque matches a known horizontal arm" {
  let analysis = @cad.analyze_robot(analysis_arm(10.0), [
    ("horizontal", Map([])),
  ])
  assert_true((analysis.total_mass_kg - 2.0).abs() < 1.0e-9)
  let pose = analysis.poses[0]
  assert_true((pose.com_m.0 - 0.5).abs() < 1.0e-9)
  assert_true(pose.com_m.1.abs() < 1.0e-9)
  assert_true(pose.com_m.2.abs() < 1.0e-9)
  assert_eq(pose.joints.length(), 1)
  let joint = pose.joints[0]
  assert_eq(joint.joint, "arm_joint")
  let expected = 2.0 * 9.80665 * 0.5
  assert_true((joint.tau_static_nm - expected).abs() < 1.0e-4)
  assert_true((joint.tau_rated_nm - 10.0).abs() < 1.0e-9)
  assert_true(joint.safety_factor < 1.5)
  assert_false(joint.ok)
  assert_true(analysis.warnings.length() > 0)
}

///|
test "safety factor passes with a stronger actuator" {
  let analysis = @cad.analyze_robot(analysis_arm(30.0), [
    ("horizontal", Map([])),
  ])
  let joint = analysis.poses[0].joints[0]
  assert_true(joint.safety_factor > 3.0)
  assert_true(joint.ok)
  assert_eq(analysis.warnings.length(), 0)
}

///|
test "wheel contact links report ground misalignment" {
  let base = @cad.Component::new("base")
    .add_mate_mm_deg("l_mount", z=0.0)
    .add_mate_mm_deg("r_mount", z=12.0)
  let left = @cad.Component::new("l_wheel_link").add_body(
    @cad.BodyPart::box_mm("wheel_body", 10.0, 10.0, 10.0),
  )
  let right = @cad.Component::new("r_wheel_link").add_body(
    @cad.BodyPart::box_mm("wheel_body", 10.0, 10.0, 10.0),
  )
  let comp = base
    .attach(
      "l_wheel_fixed",
      parent_mate="l_mount",
      left,
      spec=@cad.JointSpec::fixed(),
    )
    .attach(
      "r_wheel_fixed",
      parent_mate="r_mount",
      right,
      spec=@cad.JointSpec::fixed(),
    )
  let analysis = @cad.analyze_robot(comp, [("default", Map([]))])
  let pose = analysis.poses[0]
  assert_eq(pose.contacts.length(), 2)
  assert_true((pose.contact_misalignment_m - 0.012).abs() < 1.0e-6)
  assert_true(analysis.warnings.length() > 0)
  let constants = comp.control_constants()
  assert_true((constants.ground_z_m - -0.005).abs() < 1.0e-6)
}

///|
test "passive joints carry gravity without motor sizing warnings" {
  let analysis = @cad.analyze_robot(analysis_arm(0.0), [("horizontal", Map([]))])
  let joint = analysis.poses[0].joints[0]
  assert_true(joint.passive)
  assert_true(joint.ok)
  assert_true(joint.tau_static_nm > 1.0)
  assert_eq(analysis.warnings.length(), 0)
}

///|
test "analyze ignores rotor links and uses tires for ground contact" {
  let base = @cad.Component::new("base")
    .add_mate_mm_deg("rotor_mount", z=0.0)
    .add_mate_mm_deg("tire_mount", z=-50.0)
  let rotor = @cad.Component::new("lf_wheel_act_a12_rotor").add_body(
    @cad.BodyPart::box_mm("rotor_body", 10.0, 10.0, 10.0),
  )
  let tire = @cad.Component::new("lf_tire").add_body(
    @cad.BodyPart::box_mm("tire_body", 20.0, 20.0, 20.0),
  )
  let comp = base
    .attach(
      "rotor_fixed",
      parent_mate="rotor_mount",
      rotor,
      spec=@cad.JointSpec::fixed(),
    )
    .attach(
      "tire_fixed",
      parent_mate="tire_mount",
      tire,
      spec=@cad.JointSpec::fixed(),
    )
  let analysis = @cad.analyze_robot(comp, [("default", Map([]))])
  let pose = analysis.poses[0]
  assert_eq(pose.contacts.length(), 1)
  assert_eq(pose.contacts[0].name, "lf_tire")
  assert_true((pose.contacts[0].min_z_m - -0.060).abs() < 1.0e-6)
  let constants = comp.control_constants()
  assert_true((constants.ground_z_m - -0.060).abs() < 1.0e-6)
}
