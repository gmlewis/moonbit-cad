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
