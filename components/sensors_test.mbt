///|
test "limit switch carries a spec, ports, and a part" {
  let comp = @components.limit_switch()
  assert_true(comp.part is Some(_))
  assert_true(comp.sensor is Some(_))
  assert_eq(comp.ports.length(), 3)
  assert_eq(comp.fasteners.length(), 1)
  assert_true(comp.get_mate("mount") is Some(_))
  assert_eq(comp.power_budget().sensors.length(), 1)
  assert_eq(comp.bom().lines.length(), 2)
}

///|
test "magnetic encoder and imu are buildable sensors" {
  let encoder = @components.magnetic_encoder()
  let imu = @components.imu_module()
  for comp in [encoder, imu] {
    assert_true(comp.sensor is Some(_))
    assert_true(comp.part is Some(_))
    assert_eq(comp.power_budget().sensors.length(), 1)
    assert_true(!comp.to_robot().has_errors())
  }
}

///|
test "camera and force sensors declare interfaces" {
  let camera = @components.camera_module()
  assert_eq(camera.ports.length(), 3)
  assert_true(camera.sensor is Some(_))
  let force = @components.force_sensor()
  assert_true(force.sensor is Some(_))
  assert_true(!force.to_robot().has_errors())
}

///|
test "PCB board exposes mounting holes and mates" {
  let pcb = @components.pcb_board(connectors=["power", "can"])
  assert_eq(pcb.ports.length(), 5)
  assert_true(pcb.pcb is Some(_))
  check_component(pcb, ["mount", "bolt_0", "bolt_1", "bolt_2", "bolt_3"])
  assert_true(pcb.part is Some(_))
}

///|
test "detailed PCB adds standoffs" {
  let simple = @components.pcb_board()
  let detailed = @components.pcb_board(
    detail=@step_common.DetailLevel::Detailed,
  )
  assert_true(
    detailed.to_design().nodes.length() > simple.to_design().nodes.length(),
  )
  assert_true(!detailed.to_robot().has_errors())
  let standoffs_forced = @components.pcb_board(include_standoffs=true)
  assert_true(
    standoffs_forced.to_design().nodes.length() >
    simple.to_design().nodes.length(),
  )
}

///|
test "sensor mount bracket is printable" {
  let bracket = @components.sensor_mount_bracket()
  check_component(bracket, ["mount", "sensor_face"])
  let parts = bracket.printable_parts()
  assert_eq(parts.length(), 1)
  assert_true(parts[0].design.nodes.length() > 0)
}
