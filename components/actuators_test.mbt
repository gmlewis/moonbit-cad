///|
fn check_actuator(comp : @cad.Component) -> Unit raise {
  let robot = comp.to_robot()
  if robot.has_errors() {
    let mut msg = "diagnostics for " + comp.name + ":"
    for diagnostic in robot.diagnostics() {
      msg = msg + "\n  " + diagnostic.message()
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
  assert_true(comp.to_design().nodes.length() >= 2)
}

///|
test "nema stepper compiles to an actuated robot" {
  let comp = @components.nema_stepper()
  check_actuator(comp)
  let robot = comp.to_robot()
  assert_eq(robot.joints[0].name, "nema17_shaft_joint")
  assert_eq(robot.transmissions[0].name, "nema17_shaft_joint_trans")
  assert_true(comp.total_mass_kg() > 0.0)
}

///|
test "nema stepper at detailed adds keyed shaft and mounting screws" {
  let simplified = @components.nema_stepper()
  let detailed = @components.nema_stepper(
    detail=@step_common.DetailLevel::Detailed,
  )
  assert_true(
    detailed.to_design().nodes.length() > simplified.to_design().nodes.length(),
  )
  assert_true(detailed.bom().lines.length() > simplified.bom().lines.length())
}

///|
test "bldc actuator pod compiles to an actuated robot" {
  let comp = @components.bldc_actuator_pod()
  check_actuator(comp)
  let robot = comp.to_robot()
  assert_eq(robot.joints[0].name, "actuator_pod_joint")
  assert_true(comp.total_mass_kg() > 0.0)
}

///|
test "detailed bldc pod carries bearing and flange screws" {
  let comp = @components.bldc_actuator_pod(
    detail=@step_common.DetailLevel::Detailed,
  )
  check_actuator(comp)
  let bom = comp.bom()
  let mut has_bearing = false
  let mut has_screw = false
  for line in bom.lines {
    if line.part_number.has_prefix("BEARING-") {
      has_bearing = true
    }
    if line.part_number.has_prefix("ISO4762-") {
      has_screw = true
    }
  }
  assert_true(has_bearing)
  assert_true(has_screw)
}

///|
test "hub motor compiles to an actuated robot" {
  let comp = @components.hub_motor_assembly()
  check_actuator(comp)
  let robot = comp.to_robot()
  assert_eq(robot.joints[0].name, "hub_motor_spin_joint")
  assert_true(comp.total_mass_kg() > 0.0)
}

///|
test "detailed hub motor adds axle and bearing bodies" {
  let simplified = @components.hub_motor_assembly()
  let detailed = @components.hub_motor_assembly(
    detail=@step_common.DetailLevel::FullyModeled,
  )
  check_actuator(detailed)
  assert_true(
    detailed.to_design().nodes.length() > simplified.to_design().nodes.length(),
  )
}
