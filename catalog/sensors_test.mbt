///|
test "limit switch carries a spec, ports, and a part" {
  let comp = @catalog.limit_switch()
  assert_true(comp.part is Some(_))
  assert_true(comp.sensor is Some(_))
  assert_eq(comp.ports.length(), 3)
  assert_eq(comp.fasteners.length(), 1)
  assert_true(comp.get_mate("mount") is Some(_))
  let budget = comp.power_budget()
  assert_eq(budget.sensors.length(), 1)
  let bom = comp.bom()
  assert_eq(bom.lines.length(), 2)
}

///|
test "magnetic encoder and imu are buildable sensors" {
  let encoder = @catalog.magnetic_encoder()
  let imu = @catalog.imu_module()
  for comp in [encoder, imu] {
    assert_true(comp.sensor is Some(_))
    assert_true(comp.part is Some(_))
    assert_eq(comp.power_budget().sensors.length(), 1)
    let robot = comp.to_robot()
    assert_true(!robot.has_errors())
  }
}

///|
test "camera and force sensors declare interfaces" {
  let camera = @catalog.camera_module()
  let force = @catalog.force_sensor()
  for comp in [camera, force] {
    assert_true(comp.sensor is Some(_))
    assert_true(comp.part is Some(_))
    let budget = comp.power_budget()
    assert_eq(budget.sensors.length(), 1)
    assert_eq(budget.ports.length(), 3)
  }
}

///|
test "pcb board has four mounting holes and mates" {
  let pcb = @catalog.pcb_board(length_mm=44.0, width_mm=32.0, connectors=[
    "power", "motor", "can",
  ])
  assert_true(pcb.pcb is Some(_))
  assert_true(pcb.part is Some(_))
  assert_eq(pcb.bodies.length(), 1)
  for i in 0..<4 {
    assert_true(pcb.get_mate("bolt_" + i.to_string()) is Some(_))
  }
  assert_eq(pcb.ports.length(), 5)
  let budget = pcb.power_budget()
  assert_eq(budget.ports.length(), 5)
  let bom = pcb.bom()
  assert_eq(bom.lines.length(), 2)
}

///|
test "pcb board builds a valid STEP body" {
  let pcb = @catalog.pcb_board(length_mm=44.0, width_mm=32.0)
  let robot = pcb.to_robot()
  assert_true(!robot.has_errors())
  let step = pcb.to_step_file()
  assert_true(step.contains("ISO-10303-21;"))
}
