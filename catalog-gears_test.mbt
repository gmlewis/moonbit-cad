///|
test "default planetary gearbox compiles to a mimic-coupled robot" {
  let gb = @cad.planetary_gearbox()
  let robot = gb.to_robot()
  assert_eq(robot.links.length(), 6)
  assert_eq(robot.joints.length(), 5)
  let mut continuous = 0
  let mut mimics = 0
  for joint in robot.joints {
    if joint.joint_type == @urdf.JointType::Continuous {
      continuous = continuous + 1
    }
    match joint.mimic {
      Some(mimic) => {
        mimics = mimics + 1
        if joint.name.has_prefix("planetary_gearbox_planet_") {
          assert_true((mimic.multiplier + 1.0).abs() < 1.0e-9)
        } else if joint.name == "planetary_gearbox_carrier_joint" {
          assert_true((mimic.multiplier - 0.25).abs() < 1.0e-9)
        }
      }
      None => ()
    }
  }
  assert_eq(continuous, 5)
  assert_eq(mimics, 4)
  if robot.has_errors() {
    let mut msg = "gearbox diagnostics:"
    for d in robot.diagnostics() {
      msg = msg + "\n  " + d.message()
    }
    fail(msg)
  }
  assert_true(gb.total_mass_kg() > 0.0)
}

///|
test "gearbox posed design evaluates mimic joints" {
  let gb = @cad.planetary_gearbox()
  let positions : Map[String, Double] = Map([])
  positions.set("planetary_gearbox_sun_joint", 1.0)
  let design = gb.to_design(joint_positions=positions)
  assert_true(design.nodes.length() >= 6)
  let step = gb.to_step_file(joint_positions=positions)
  assert_true(step.contains("ISO-10303-21;"))
  assert_true(step.contains("END-ISO-10303-21;"))
}

///|
test "standalone herringbone gear component" {
  let gear = @cad.herringbone_gear_component(
    "gear12",
    gear_module=3.0,
    num_teeth=12,
    gear_length_mm=20.0,
  )
  assert_true(gear.total_mass_kg() > 0.0)
  assert_true(gear.get_mate("bottom") is Some(_))
  assert_true(gear.get_mate("top") is Some(_))
  let robot = gear.to_robot()
  assert_false(robot.has_errors())
  assert_true(gear.to_step_file().contains("ISO-10303-21;"))
}
