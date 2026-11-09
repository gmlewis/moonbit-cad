///|
fn make_revolute_arm(name : String) -> @cad.Component {
  @cad.Component::new(name).add_body(
    @cad.BodyPart::box_mm(name + "_body", 20.0, 10.0, 10.0),
  )
}

///|
fn make_joint_limit() -> @urdf.JointLimit {
  @urdf.JointLimit::new(
    lower=Some(-1.0),
    upper=Some(1.0),
    effort=10.0,
    velocity=2.0,
  )
}

///|
test "ros2 control yaml and pin map map every binding" {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 20.0, 20.0, 10.0))
    .attach(
      "arm_joint",
      parent_mate="origin",
      make_revolute_arm("arm"),
      spec=@cad.JointSpec::revolute(make_joint_limit()),
    )
  let _ = base.add_control_binding(
    @cad.ControlBinding::new(
      "arm_joint",
      actuator="arm",
      channel="can0:1",
      gear_ratio=6.0,
      soft_lower=Some(-1.0),
      soft_upper=Some(1.0),
    ),
  )
  let yaml = base.to_ros2_control_yaml()
  assert_true(yaml.contains("joint_trajectory_controller"))
  assert_true(yaml.contains("\"arm_joint\""))
  assert_true(yaml.contains("channel: \"can0:1\""))
  assert_true(yaml.contains("gear_ratio: 6"))
  assert_true(yaml.contains("sensors:"))
  let csv = base.to_pin_map_csv()
  assert_true(csv.contains("\"joint\",\"actuator\""))
  assert_true(csv.contains("\"arm_joint\",\"arm\",\"can0:1\""))
  assert_eq(base.control_checks().length(), 0)
}

///|
test "control checks require a binding for every commandable joint" {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 20.0, 20.0, 10.0))
    .attach(
      "arm_a_joint",
      parent_mate="origin",
      make_revolute_arm("arm_a"),
      spec=@cad.JointSpec::revolute(make_joint_limit()),
    )
    .attach(
      "arm_b_joint",
      parent_mate="origin",
      make_revolute_arm("arm_b"),
      spec=@cad.JointSpec::revolute(make_joint_limit()),
    )
  let _ = base.add_control_binding(
    @cad.ControlBinding::new("arm_a_joint", actuator="arm_a", channel="can0:1"),
  )
  let warnings = base.control_checks()
  let has = fn(needle : String) -> Bool {
    warnings.fold(init=false, fn(acc, warning) {
      acc || warning.contains(needle)
    })
  }
  assert_true(has("arm_b_joint' has no control binding"))
}

///|
test "control checks flag invalid bindings" {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 20.0, 20.0, 10.0))
    .attach(
      "arm_joint",
      parent_mate="origin",
      make_revolute_arm("arm"),
      spec=@cad.JointSpec::revolute(make_joint_limit()),
    )
  let _ = base.add_control_binding(
    @cad.ControlBinding::new(
      "ghost_joint",
      actuator="missing_actuator",
      channel="can9:99",
      direction="sideways",
      gear_ratio=0.0,
      soft_lower=Some(2.0),
      soft_upper=Some(1.0),
      homing_input=Some("missing_port"),
    ),
  )
  let warnings = base.control_checks()
  let has = fn(needle : String) -> Bool {
    warnings.fold(init=false, fn(acc, warning) {
      acc || warning.contains(needle)
    })
  }
  assert_true(has("unknown joint 'ghost_joint'"))
  assert_true(has("unknown actuator 'missing_actuator'"))
  assert_true(has("has direction 'sideways'"))
  assert_true(has("has gear ratio 0"))
  assert_true(has("soft lower > upper"))
  assert_true(has("unknown homing input 'missing_port'"))
  assert_true(has("arm_joint' has no control binding"))
}

///|
test "forward kinematics rotates a commanded joint" {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 20.0, 20.0, 10.0))
    .attach(
      "arm_joint",
      parent_mate="origin",
      make_revolute_arm("arm"),
      spec=@cad.JointSpec::revolute(make_joint_limit()),
    )
  let robot = base.to_robot()
  let at_zero : Map[String, Double] = Map([])
  let at_one : Map[String, Double] = Map([])
  at_one.set("arm_joint", 1.0)
  let t0 = robot.forward_kinematics(joint_positions=at_zero).get("arm").unwrap()
  let t1 = robot.forward_kinematics(joint_positions=at_one).get("arm").unwrap()
  let delta = (t1.rot.m00 - t0.rot.m00).abs() + (t1.rot.m01 - t0.rot.m01).abs()
  assert_true(delta > 0.1)
}
