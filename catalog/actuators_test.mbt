///|
fn check_actuator(comp : @cad.Component) -> Unit raise {
  let robot = comp.to_robot()
  if robot.has_errors() {
    let mut msg = "diagnostics for " + comp.name + ":"
    for d in robot.diagnostics() {
      msg = msg + "\n  " + d.message()
    }
    fail(msg)
  }
  assert_eq(robot.links.length(), 2)
  assert_eq(robot.joints.length(), 1)
  assert_eq(robot.transmissions.length(), 1)
  let step = comp.to_step_file()
  if !step.contains("ISO-10303-21;") {
    fail("missing STEP header for " + comp.name)
  }
  let design = comp.to_design()
  assert_true(design.nodes.length() >= 2)
}

///|
test "nema stepper compiles to an actuated robot" {
  let comp = @catalog.nema_stepper()
  check_actuator(comp)
  let robot = comp.to_robot()
  assert_eq(robot.joints[0].name, "nema17_shaft_joint")
  assert_eq(robot.transmissions[0].name, "nema17_shaft_joint_trans")
  assert_true(comp.total_mass_kg() > 0.0)
}

///|
test "bldc actuator pod compiles to an actuated robot" {
  let comp = @catalog.bldc_actuator_pod()
  check_actuator(comp)
  let robot = comp.to_robot()
  assert_eq(robot.joints[0].name, "actuator_pod_joint")
  assert_true(comp.total_mass_kg() > 0.0)
}

///|
test "hub motor compiles to an actuated robot" {
  let comp = @catalog.hub_motor_assembly()
  check_actuator(comp)
  let robot = comp.to_robot()
  assert_eq(robot.joints[0].name, "hub_motor_spin_joint")
  assert_true(comp.total_mass_kg() > 0.0)
}
