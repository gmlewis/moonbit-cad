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

///|
test "lead screw gripper exposes sensors, PCB, and wiring" {
  let comp = @catalog.lead_screw_gripper()
  let budget = comp.power_budget()
  assert_eq(budget.sensors.length(), 2)
  assert_eq(budget.wires.length(), 4)
  let mut pcb_found = false
  for att in comp.attachments {
    if att.child.pcb is Some(_) {
      pcb_found = true
    }
  }
  assert_true(pcb_found)
  // One motor revolution moves the jaw by the 2 mm screw lead; the full
  // 28 mm travel is 14 revolutions.
  let screw_lead_mm = 2.0
  let travel_mm = 28.0
  let robot = comp.to_robot()
  let at_zero : Map[String, Double] = Map([])
  let jaw_zero = robot
    .forward_kinematics(joint_positions=at_zero)
    .get("lead_screw_gripper_jaw")
    .unwrap()
  let one_rev : Map[String, Double] = Map([])
  one_rev.set("lead_screw_gripper_motor_shaft_joint", 2.0 * @math.PI)
  let jaw_rev = robot
    .forward_kinematics(joint_positions=one_rev)
    .get("lead_screw_gripper_jaw")
    .unwrap()
  let dx = jaw_rev.trans.0 - jaw_zero.trans.0
  let dy = jaw_rev.trans.1 - jaw_zero.trans.1
  let dz = jaw_rev.trans.2 - jaw_zero.trans.2
  let distance = (dx * dx + dy * dy + dz * dz).sqrt()
  assert_true((distance - screw_lead_mm / 1000.0).abs() < 1.0e-9)
  let closed : Map[String, Double] = Map([])
  closed.set(
    "lead_screw_gripper_motor_shaft_joint",
    travel_mm / screw_lead_mm * 2.0 * @math.PI,
  )
  let jaw_closed = robot
    .forward_kinematics(joint_positions=closed)
    .get("lead_screw_gripper_jaw")
    .unwrap()
  let cx = jaw_closed.trans.0 - jaw_zero.trans.0
  let cy = jaw_closed.trans.1 - jaw_zero.trans.1
  let cz = jaw_closed.trans.2 - jaw_zero.trans.2
  let closed_distance = (cx * cx + cy * cy + cz * cz).sqrt()
  assert_true((closed_distance - travel_mm / 1000.0).abs() < 1.0e-9)
}
