///|
test "parallel gripper compiles with a prismatic jaw" {
  let comp = @catalog.parallel_gripper()
  check_component(comp, ["mount", "jaw_slide"])
  assert_eq(comp.bodies.length(), 2)
  let robot = comp.to_robot()
  let joint = robot.get_joint("parallel_gripper_jaw").unwrap()
  assert_eq(joint.joint_type.to_urdf_str(), "prismatic")
  match joint.limit {
    Some(limit) => {
      assert_true((limit.lower.unwrap() - 0.0).abs() < 1.0e-9)
      assert_true((limit.upper.unwrap() - 0.028).abs() < 1.0e-9)
    }
    None => fail("expected a jaw limit")
  }
  let positions : Map[String, Double] = Map([])
  positions.set("parallel_gripper_jaw", 0.02)
  let poses = robot.forward_kinematics(joint_positions=positions)
  let jaw = poses.get("parallel_gripper_jaw").unwrap()
  assert_true((jaw.trans.0 - 0.02).abs() < 1.0e-9)
  assert_true((jaw.trans.1 - 0.0).abs() < 1.0e-9)
}

///|
test "lead screw gripper is motor driven" {
  let comp = @catalog.lead_screw_gripper()
  check_component(comp, ["mount", "jaw_slide", "motor_mount", "bearing_seat"])
  let robot = comp.to_robot()
  let jaw = robot.get_joint("lead_screw_gripper_jaw").unwrap()
  assert_eq(jaw.joint_type.to_urdf_str(), "prismatic")
  let mimic = jaw.mimic.unwrap()
  assert_eq(mimic.joint, "lead_screw_gripper_motor_shaft_joint")
  let motor = robot.get_joint("lead_screw_gripper_motor_shaft_joint").unwrap()
  assert_eq(motor.joint_type.to_urdf_str(), "continuous")
  let positions : Map[String, Double] = Map([])
  positions.set("lead_screw_gripper_motor_shaft_joint", 10.0)
  let poses = robot.forward_kinematics(joint_positions=positions)
  let jaw_tf = poses.get("lead_screw_gripper_jaw").unwrap()
  let expected = 10.0 * (2.0 / 1000.0) / (2.0 * @math.PI)
  assert_true((jaw_tf.trans.0 - expected).abs() < 1.0e-9)
}
