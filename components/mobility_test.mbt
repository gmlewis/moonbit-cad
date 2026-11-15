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
test "quadruped leg joints are real planetary actuators" {
  let leg = @components.quadruped_leg_assembly("fl", is_left=true)
  let robot = leg.to_robot()
  if robot.has_errors() {
    let mut msg = "leg diagnostics:"
    for diagnostic in robot.diagnostics() {
      msg = msg + "\n  " + diagnostic.message()
    }
    fail(msg)
  }
  // Four commandable joints: hip abduction, hip pitch, knee, and wheel.
  for
    joint in [
      "fl_hip_joint", "fl_thigh_joint", "fl_calf_joint", "fl_wheel_joint",
    ] {
    let found = robot.get_joint(joint)
    assert_true(found is Some(_))
    match found {
      Some(j) => {
        assert_true(j.joint_type == @urdf.JointType::Continuous)
        assert_true(j.mimic is None)
      }
      None => fail("missing joint " + joint)
    }
  }
  // The four primary leg links and the printed hip clevis bracket exist.
  let link_names : Array[String] = []
  for link in robot.links {
    link_names.push(link.name)
  }
  for
    link in ["fl_hip_bracket", "fl_thigh_link", "fl_calf_link", "fl_wheel_link"] {
    assert_true(link_names.contains(link))
  }
  // Every joint is driven by a real actuator, so the leg carries four suns,
  // four rings, four carriers, and the planet gears.
  let parts = leg.printable_parts()
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  let mut suns = 0
  let mut rings = 0
  let mut carriers = 0
  let mut planets = 0
  for name in names {
    if name == "PGB-SUN" {
      suns = suns + 1
    }
    if name == "PGB-RING" {
      rings = rings + 1
    }
    if name == "PGB-CARRIER" {
      carriers = carriers + 1
    }
    if name.has_prefix("PGB-PLANET-") {
      planets = planets + 1
    }
  }
  // PGB-SUN/RING/CARRIER are aggregated by part number, so the BOM reports
  // four of each even though printable_parts de-duplicates.
  let bom = leg.bom()
  let mut actuator_parts = 0
  for line in bom.lines {
    if line.part_number == "PGB-SUN" {
      actuator_parts = line.quantity
    }
  }
  assert_eq(actuator_parts, 4)
  assert_true(suns >= 1)
  assert_true(rings >= 1)
  assert_true(carriers >= 1)
  assert_true(planets >= 3)
  assert_eq(bom.unassigned, 0)
  // The old placeholder envelope bodies are gone.
  for body in leg.bodies {
    assert_false(body.name.contains("actuator_geometry"))
  }
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
  let robot = detailed.to_robot()
  assert_true(!robot.has_errors())
  assert_true(robot.get_joint("fl_calf_joint") is Some(_))
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

///|
test "wheelchair wheel is bolted to the actuator carrier output" {
  let unit = @components.planetary_wheel_drive_unit()
  let robot = unit.to_robot()
  assert_true(!robot.has_errors())
  // The command joint is the actuator rotor, and the wheel is a fixed child
  // of the final stage's rotating carrier.
  assert_true(robot.get_joint("wheel_drive_wheel_joint") is Some(_))
  let mount = robot.get_joint("wheel_drive_wheel_joint_mount")
  assert_true(mount is Some(_))
  match mount {
    Some(joint) => {
      assert_eq(joint.parent, "wheel_drive_drive_stage2_carrier")
      assert_eq(joint.child, "wheel_drive_wheel")
    }
    None => fail("missing wheel mount joint")
  }
  assert_true(unit.get_mate("output_shaft") is Some(_))
  let parts = unit.printable_parts()
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  assert_true(names.contains("WHEEL-HUB-125"))
  assert_true(names.contains("WHEEL-TREAD-125"))
  assert_eq(unit.bom().unassigned, 0)
}

///|
test "detailed treaded wheel has lug tread and a separate rim" {
  let wheel = @components.treaded_wheel(
    "wheel",
    detail=@step_common.DetailLevel::Detailed,
  )
  let parts = wheel.printable_parts()
  assert_eq(parts.length(), 2)
  let mut lugs = 0
  let mut rim = false
  for node in wheel.to_design().nodes {
    if node.name.contains("_lug_") {
      lugs = lugs + 1
    }
    if node.name.contains("_rim") {
      rim = true
    }
  }
  assert_true(lugs >= 8)
  assert_true(rim)
}

///|
test "joystick pod has stick, E-stop, power button, and ports" {
  let pod = @components.joystick_pod()
  let robot = pod.to_robot()
  assert_true(!robot.has_errors())
  assert_eq(robot.joints.length(), 0)
  assert_true(pod.get_mate("stick") is Some(_))
  assert_true(pod.get_mate("estop") is Some(_))
  assert_true(pod.get_mate("power_button") is Some(_))
  let ports : Array[String] = []
  for port in pod.ports {
    ports.push(port.name)
  }
  assert_true(ports.contains("signal"))
  assert_true(ports.contains("estop"))
  let parts = pod.printable_parts()
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  assert_true(names.contains("JOYSTICK-HOUSING-90x70"))
  assert_eq(pod.bom().unassigned, 0)
}
