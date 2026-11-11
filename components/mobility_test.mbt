///|
test "box tube strut and leg segment and wheel" {
  let strut = @components.box_tube_strut(
    "strut",
    width_mm=40.0,
    height_mm=40.0,
    length_mm=300.0,
  )
  assert_true(strut.total_mass_kg() > 0.0)
  assert_true(strut.get_mate("start") is Some(_))
  assert_true(strut.get_mate("end") is Some(_))
  let leg = @components.robot_leg_segment("thigh", length_mm=200.0)
  assert_true(leg.total_mass_kg() > 0.0)
  assert_true(leg.get_mate("proximal_joint") is Some(_))
  assert_true(leg.get_mate("distal_joint") is Some(_))
  let wheel = @components.treaded_wheel("wheel")
  assert_true(wheel.total_mass_kg() > 0.0)
  assert_true(wheel.get_mate("axle") is Some(_))
  assert_false(wheel.to_robot().has_errors())
}

///|
test "wheel hub and tread are individually printable" {
  let wheel = @components.treaded_wheel("wheel")
  let parts = wheel.printable_parts()
  assert_eq(parts.length(), 2)
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  assert_true(names.contains("WHEEL-HUB-70"))
  assert_true(names.contains("WHEEL-TREAD-70"))
}

///|
test "quadruped leg assembly has four links and printable segments" {
  let leg = @components.quadruped_leg_assembly("fl", is_left=true)
  let robot = leg.to_robot()
  assert_true(!robot.has_errors())
  assert_eq(robot.links.length(), 4)
  assert_eq(robot.joints.length(), 3)
  let parts = leg.printable_parts()
  assert_true(parts.length() >= 4)
}

///|
test "detailed quadruped leg adds bearings, sensor, and harness" {
  let simple = @components.quadruped_leg_assembly("fl", is_left=true)
  let detailed = @components.quadruped_leg_assembly(
    "fl",
    is_left=true,
    detail=@step_common.DetailLevel::Detailed,
  )
  assert_true(
    detailed.to_design().nodes.length() > simple.to_design().nodes.length(),
  )
  assert_eq(detailed.to_robot().links.length(), 4)
}

///|
test "suspension fork module has a driven wheel" {
  let fork = @components.suspension_fork_module()
  let robot = fork.to_robot()
  assert_true(!robot.has_errors())
  assert_true(robot.get_joint("front_fork_wheel_joint") is Some(_))
  assert_true(fork.total_mass_kg() > 0.0)
  let parts = fork.printable_parts()
  assert_true(parts.length() >= 2)
}
