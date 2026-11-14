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

///|
test "BLDC presets expose realistic torque constants" {
  for name in @components.bldc_preset_names() {
    let p = @components.bldc_preset(name).unwrap()
    assert_true(p.kv > 100.0)
    let kt = @components.bldc_torque_constant(p)
    assert_true((kt - 8.27 / p.kv).abs() < 1.0e-9)
    assert_true(@components.bldc_rated_torque(p) > 0.0)
    let motor = @components.low_kv_bldc_motor(preset=name)
    let robot = motor.to_robot()
    if robot.has_errors() {
      let mut msg = "diagnostics for " + name + ":"
      for diagnostic in robot.diagnostics() {
        msg = msg + "\n  " + diagnostic.message()
      }
      fail(msg)
    }
    assert_eq(robot.links.length(), 2)
    assert_eq(robot.joints.length(), 1)
    assert_eq(robot.transmissions.length(), 1)
    assert_true(robot.get_joint("bldc_motor_rotor_joint") is Some(_))
    assert_true(motor.total_mass_kg() > 0.0)
  }
}

///|
test "low-KV BLDC motor exports step and glTF" {
  let motor = @components.low_kv_bldc_motor(
    preset="5208_180kv",
    detail=@step_common.DetailLevel::Detailed,
  )
  assert_true(motor.to_step_file().contains("ISO-10303-21;"))
  let gltf = @cad.gltf_safe_design(motor.to_design()).to_gltf()
  assert_true(gltf.contains("\"2.0\""))
  let bom = motor.bom()
  assert_true(bom.lines.length() > 0)
  assert_eq(bom.unassigned, 0)
}

///|
test "single-stage planetary BLDC actuator is built and printable" {
  let act = @components.planetary_bldc_actuator(
    preset="5010_360kv",
    stages=1,
    module_mm=1.0,
    sun_teeth=12,
    planet_teeth=12,
    planet_count=3,
  )
  let robot = act.to_robot()
  if robot.has_errors() {
    let mut msg = "actuator diagnostics:"
    for diagnostic in robot.diagnostics() {
      msg = msg + "\n  " + diagnostic.message()
    }
    fail(msg)
  }
  assert_true(robot.get_joint("bldc_actuator_motor_rotor_joint") is Some(_))
  assert_true(robot.get_joint("bldc_actuator_stage1_carrier_joint") is Some(_))
  let parts = act.printable_parts()
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  assert_true(names.contains("PGB-SUN"))
  assert_true(names.contains("PGB-RING"))
  assert_true(names.contains("PGB-CARRIER"))
  assert_eq(act.bom().unassigned, 0)
  assert_true(act.total_mass_kg() > 0.0)
  assert_true(act.to_step_file().contains("ISO-10303-21;"))
  let gltf = @cad.gltf_safe_design(act.to_design()).to_gltf()
  assert_true(gltf.contains("\"2.0\""))
  // 12 sun / 12 planet / 36 ring: one stage is 1 + 36/12 = 4:1.
  let reduction = act.parameters.get("reduction").unwrap()
  assert_true(reduction.contains("4"))
  assert_true(act.control_bindings().length() == 1)
}

///|
test "two-stage planetary BLDC actuator compounds the reduction" {
  let act = @components.planetary_bldc_actuator(
    preset="6354_190kv",
    stages=2,
    module_mm=1.5,
    sun_teeth=12,
    planet_teeth=18,
    planet_count=3,
  )
  let robot = act.to_robot()
  assert_true(!robot.has_errors())
  assert_eq(act.bom().unassigned, 0)
  let per_stage = 1.0 + (12.0 + 2.0 * 18.0) / 12.0
  let expected = @components.planetary_reduction(12, 18, 2)
  assert_true((expected - per_stage * per_stage).abs() < 1.0e-9)
  assert_eq(act.parameters.get("reduction"), Some(expected.to_string()))
  assert_true(act.bom().total_cost_usd() > 20.0)
  assert_true(act.bom().total_cost_usd() < 500.0)
}
