///|
test "box tube strut and leg segment and wheel" {
  let strut = @cad.box_tube_strut(
    "strut",
    width_mm=40.0,
    height_mm=40.0,
    length_mm=300.0,
  )
  assert_true(strut.total_mass_kg() > 0.0)
  assert_true(strut.get_mate("start") is Some(_))
  assert_true(strut.get_mate("end") is Some(_))
  let leg = @cad.robot_leg_segment("thigh", length_mm=200.0)
  assert_true(leg.total_mass_kg() > 0.0)
  assert_true(leg.get_mate("proximal_joint") is Some(_))
  assert_true(leg.get_mate("distal_joint") is Some(_))
  let wheel = @cad.treaded_wheel("wheel")
  assert_true(wheel.total_mass_kg() > 0.0)
  assert_true(wheel.get_mate("axle") is Some(_))
  let robot = wheel.to_robot()
  assert_false(robot.has_errors())
}

///|
test "galileo quadruped has seventeen links" {
  let galileo = @cad.galileo_quadruped_robot()
  let robot = galileo.to_robot()
  assert_eq(robot.name, "galileo_quadruped")
  assert_eq(robot.links.length(), 17)
  assert_eq(robot.joints.length(), 16)
  assert_eq(robot.transmissions.length(), 16)
  let mut revolute = 0
  let mut continuous = 0
  for joint in robot.joints {
    if joint.joint_type == @urdf.JointType::Revolute {
      revolute = revolute + 1
    } else if joint.joint_type == @urdf.JointType::Continuous {
      continuous = continuous + 1
    }
  }
  assert_eq(revolute, 12)
  assert_eq(continuous, 4)
  if robot.has_errors() {
    let mut msg = "quadruped diagnostics:"
    for d in robot.diagnostics() {
      msg = msg + "\n  " + d.message()
    }
    fail(msg)
  }
  assert_true(galileo.total_mass_kg() > 0.0)
}

///|
test "galileo posed design moves the legs" {
  let galileo = @cad.galileo_quadruped_robot()
  let rest = galileo.to_design()
  assert_true(rest.nodes.length() > 17)
  let moved_positions : Map[String, Double] = Map([])
  moved_positions.set("fl_thigh_joint", 0.5)
  moved_positions.set("fr_thigh_joint", -0.5)
  let moved = galileo.to_design(joint_positions=moved_positions)
  assert_eq(moved.nodes.length(), rest.nodes.length())
  let step = galileo.to_step_file(joint_positions=moved_positions)
  assert_true(step.contains("ISO-10303-21;"))
}

///|
test "galileo bundle names the robot and base link correctly" {
  let galileo = @cad.galileo_quadruped_robot()
  let bundle = galileo.to_urdf_bundle()
  assert_eq(bundle.robot.name, "galileo_quadruped")
  assert_eq(bundle.package_name, "galileo_quadruped")
  let mut has_base_mesh = false
  let mut has_base_part = false
  for asset in bundle.meshes {
    if asset.rel_path == "meshes/base_link.gltf" {
      has_base_mesh = true
    }
    if asset.rel_path == "parts/base_link.step" {
      has_base_part = true
    }
  }
  assert_true(has_base_mesh)
  assert_true(has_base_part)
}

///|
test "assistive scooter compiles to five links" {
  let scooter = @cad.assistive_scooter_robot()
  let robot = scooter.to_robot()
  assert_eq(robot.name, "assistive_scooter")
  assert_eq(robot.links.length(), 5)
  assert_eq(robot.joints.length(), 4)
  assert_eq(robot.transmissions.length(), 3)
  if robot.has_errors() {
    let mut msg = "scooter diagnostics:"
    for d in robot.diagnostics() {
      msg = msg + "\n  " + d.message()
    }
    fail(msg)
  }
  assert_true(scooter.total_mass_kg() > 0.0)
  assert_true(scooter.to_step_file().contains("ISO-10303-21;"))
}
