///|
test "default planetary gearbox compiles to a mimic-coupled robot" {
  let gearbox = @components.planetary_gearbox()
  let robot = gearbox.to_robot()
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
          // 12/12/36 with a fixed ring: the planet's spin relative to the
          // carrier is -Zs*Zr / (Zp*(Zs+Zr)) = -0.75 of the sun.
          assert_true((mimic.multiplier + 0.75).abs() < 1.0e-9)
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
    for diagnostic in robot.diagnostics() {
      msg = msg + "\n  " + diagnostic.message()
    }
    fail(msg)
  }
}

///|
test "gearbox exports every gear as a printable part" {
  let gearbox = @components.planetary_gearbox()
  let parts = gearbox.printable_parts()
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
    assert_true(part.design.nodes.length() > 0)
  }
  assert_true(names.contains("PGB-RING"))
  assert_true(names.contains("PGB-SUN"))
  let mut has_planet = false
  for name in names {
    if name.has_prefix("PGB-PLANET-") {
      has_planet = true
    }
  }
  assert_true(has_planet)
  assert_true(names.contains("PGB-CARRIER"))
}

///|
test "herringbone gear accepts detail levels" {
  let simple = @components.involute_gear_component(
    "gear",
    gear_module=2.0,
    num_teeth=20,
    gear_length_mm=12.0,
    detail=@step_common.DetailLevel::Simplified,
  )
  let full = @components.involute_gear_component(
    "gear",
    gear_module=2.0,
    num_teeth=20,
    gear_length_mm=12.0,
    detail=@step_common.DetailLevel::FullyModeled,
  )
  assert_true(simple.total_mass_kg() > 0.0)
  assert_true(full.total_mass_kg() > 0.0)
  assert_true(full.to_step_file().length() > simple.to_step_file().length())
}

///|
test "Tier-1 spur gear wrapper is printable" {
  let gear = @components.spur_gear_part(
    module_mm=1.5,
    teeth=24,
    face_width_mm=8.0,
    bore_diameter_mm=5.0,
  )
  assert_true(gear.total_mass_kg() > 0.0)
  let parts = gear.printable_parts()
  assert_eq(parts.length(), 1)
  assert_true(parts[0].design.nodes.length() > 0)
  let robot = gear.to_robot()
  assert_true(!robot.has_errors())
}

///|
test "planetary stage wraps the Tier-1 planetary assembly" {
  let stage = @components.planetary_gearset_stage(
    module_mm=1.5,
    sun_teeth=12,
    planet_teeth=18,
    planet_count=3,
    face_width_mm=8.0,
    sun_bore_mm=6.0,
  )
  let robot = stage.to_robot()
  assert_true(!robot.has_errors())
  // The Tier-1 assembly is a posed gear set, so the stage keeps its gears as
  // fixed links and exports each one as a printable part.
  let parts = stage.printable_parts()
  assert_true(parts.length() >= 4)
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  let mut has_planet = false
  for name in names {
    if name.contains("planet") {
      has_planet = true
    }
  }
  assert_true(has_planet)
  assert_true(stage.total_mass_kg() > 0.0)
}

///|
test "Tier-1 planetary layers split with connectors and export glTF" {
  for num_elbows in [0, 4] {
    let params = @step_planetary.HerringbonePlanetaryParams::new(
      module_mm=1.5,
      gear_length_mm=8.0,
      num_elbows~,
      hole_type="Circular",
      hole_radius_mm=3.0,
      sun_teeth=12,
      planet_teeth=12,
      planet_count=3,
    ).unwrap()
    let gearbox = @step_planetary.herringbone_planetary_gearbox(params).unwrap()
    for layer in ["sun", "planet-1", "planet-2", "planet-3", "ring"] {
      let link = @cad.Component::from_step_layer(layer, gearbox, layer)
      assert_eq(link.bodies.length(), 1)
      assert_true(link.get_mate("origin") is Some(_))
      assert_true(link.to_step_file().contains("ISO-10303-21;"))
    }
    let sun = @cad.Component::from_step_layer("sun", gearbox, "sun")
    assert_true(sun.get_mate("sun-bore") is Some(_))
    assert_true(sun.get_mate("sun-pitch") is Some(_))
    let gltf = @cad.gltf_safe_design(sun.to_design()).to_gltf()
    assert_true(gltf.contains("\"2.0\""))
    // The exact STEP keeps the swept or arc extrusion geometry.
    assert_true(sun.to_step_file().contains("ADVANCED_FACE"))
  }
}

///|
test "planetary gearbox and smooth spur gear export glTF" {
  let gearbox = @components.planetary_gearbox(
    detail=@step_common.DetailLevel::FullyModeled,
  )
  let design = gearbox.to_design()
  let gltf = @cad.gltf_safe_design(design).to_gltf()
  assert_true(gltf.contains("\"2.0\""))
  let spur = @components.spur_gear_part(
    module_mm=1.5,
    teeth=24,
    smooth=true,
    detail=@step_common.DetailLevel::Detailed,
  )
  let spur_gltf = @cad.gltf_safe_design(spur.to_design()).to_gltf()
  assert_true(spur_gltf.contains("\"2.0\""))
}
