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
test "nema stepper at detailed adds a keyed shaft and mount-screw schedule" {
  let simplified = @components.nema_stepper()
  let detailed = @components.nema_stepper(
    detail=@step_common.DetailLevel::Detailed,
  )
  assert_true(
    detailed.to_design().nodes.length() >= simplified.to_design().nodes.length(),
  )
  // The mounting hardware is a schedule, not solids through the purchased
  // motor envelope.
  assert_eq(detailed.fasteners.length(), 1)
  assert_eq(detailed.fasteners[0].quantity, 4)
}

///|
test "bldc actuator pod compiles to an actuated robot" {
  let comp = @components.qdd_actuator_pod()
  check_actuator(comp)
  let robot = comp.to_robot()
  assert_eq(robot.joints[0].name, "actuator_pod_joint")
  assert_true(comp.total_mass_kg() > 0.0)
}

///|
test "detailed bldc pod carries bearing and flange screws" {
  let comp = @components.qdd_actuator_pod(
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
test "Tier-1 brushless motor adapts to the two-link motor interface" {
  for preset in @components.bldc_preset_names() {
    let motor = @components.step_brushless_motor(preset~)
    let robot = motor.to_robot()
    if robot.has_errors() {
      let mut msg = "brushless motor diagnostics for " + preset + ":"
      for diagnostic in robot.diagnostics() {
        msg = msg + "\n  " + diagnostic.message()
      }
      fail(msg)
    }
    assert_eq(robot.links.length(), 2)
    assert_eq(robot.joints.length(), 1)
    assert_eq(robot.transmissions.length(), 1)
    let joint = robot.get_joint("bldc_motor_rotor_joint")
    assert_true(joint is Some(_))
    match joint {
      Some(j) => {
        assert_true(j.joint_type == @urdf.JointType::Continuous)
        assert_eq(j.parent, "bldc_motor_stator")
        assert_eq(j.child, "bldc_motor_rotor")
      }
      None => fail("missing rotor joint")
    }
    assert_eq(motor.bom().unassigned, 0)
    assert_true(motor.to_step_file().contains("ISO-10303-21;"))
  }
  // The measured layers survive the split: a fixed stator hub and a rotor bell
  // plus shaft.
  let design = @components.step_brushless_motor().to_design()
  let names : Array[String] = design.nodes.map(fn(node) { node.name })
  assert_true(names.contains("bldc_motor_stator_stator-hub"))
  assert_true(names.contains("bldc_motor_rotor_bell"))
  assert_true(names.contains("bldc_motor_rotor_shaft"))
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
  // The motor rotor is the single commanded joint. The output carrier is a
  // mimic joint, so it is not commandable; its AS5047P sensor is feedback.
  let bindings = act.control_bindings()
  assert_eq(bindings.length(), 1)
  assert_eq(bindings[0].joint, "bldc_actuator_motor_rotor_joint")
  assert_eq(
    act.parameters.get("output_joint"),
    Some("bldc_actuator_stage1_carrier_joint"),
  )
  // The output is supported by a pair of 608 bearings in a printed cover and
  // read by an AS5047P absolute encoder.
  let bom = act.bom()
  let mut has_608 = false
  let mut has_sensor = false
  for line in bom.lines {
    if line.part_number == "BEARING-608" {
      has_608 = true
    }
    if line.part_number == "ENC-AS5047P" {
      has_sensor = true
    }
  }
  assert_true(has_608)
  assert_true(has_sensor)
  assert_true(act.get_mate("output_shaft") is Some(_))
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
  // Module 1.5 / 18T planets leave room for a 688 bearing in each planet.
  let bom = act.bom()
  let mut has_688 = false
  for line in bom.lines {
    if line.part_number == "BEARING-688" {
      has_688 = true
    }
  }
  assert_true(has_688)
  assert_true(bom.total_cost_usd() > 20.0)
  assert_true(bom.total_cost_usd() < 500.0)
}

///|
test "bldc actuator pod factory builds a real planetary actuator" {
  let pod = @components.bldc_actuator_pod(preset="5208_180kv")
  let robot = pod.to_robot()
  assert_true(!robot.has_errors())
  assert_true(robot.get_joint("bldc_actuator_pod_motor_rotor_joint") is Some(_))
  let parts = pod.printable_parts()
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  assert_true(names.contains("PGB-SUN"))
  assert_true(names.contains("PGB-RING"))
  assert_true(names.contains("PGB-CARRIER"))
  assert_eq(pod.bom().unassigned, 0)
}

///|
test "detailed low-KV motor adds vents, leads, flux ring, keyed shaft, rotor magnet" {
  for preset in @components.bldc_preset_names() {
    let simple = @components.low_kv_bldc_motor(preset~)
    let rich = @components.low_kv_bldc_motor(
      preset~,
      detail=@step_common.DetailLevel::FullyModeled,
    )
    assert_true(
      rich.to_design().nodes.length() > simple.to_design().nodes.length(),
    )
    let mut vents = 0
    let mut leads = 0
    let mut flux = 0
    let mut keyed = 0
    for node in rich.to_design().nodes {
      if node.name.contains("_vent_") {
        vents = vents + 1
      }
      if node.name.contains("_phase_lead_") {
        leads = leads + 1
      }
      if node.name.contains("_flux_ring") {
        flux = flux + 1
      }
      if node.name.contains("keyed-shaft") {
        keyed = keyed + 1
      }
    }
    assert_true(vents >= 6)
    assert_true(leads >= 3)
    assert_true(flux >= 1)
    assert_true(keyed >= 1)
    let bom = rich.bom()
    assert_eq(bom.unassigned, 0)
    // No built-in encoder board: the rotor magnet ships with the motor and
    // the caller attaches a sensor (e.g. a moteus C1) to `encoder_mount`.
    let mut magnets = 0
    for node in rich.to_design().nodes {
      if node.name.contains("_sensor_magnet") {
        magnets = magnets + 1
      }
    }
    assert_eq(magnets, 1)
    assert_true(rich.get_mate("encoder_mount") is Some(_))
    assert_true(rich.parameters.get("rotor_encoder") is Some(_))
  }
}

///|
test "planetary stage has a printed ring housing and carrier transmission" {
  let stage = @components.planetary_gearset_stage(
    module_mm=1.0,
    sun_teeth=12,
    planet_teeth=18,
    planet_count=3,
    face_width_mm=8.0,
    sun_bore_mm=6.0,
  )
  let robot = stage.to_robot()
  assert_true(!robot.has_errors())
  let parts = stage.printable_parts()
  let names : Array[String] = []
  for part in parts {
    names.push(part.part_number)
  }
  assert_true(names.contains("PGB-HOUSING"))
  let mut has_carrier_transmission = false
  for transmission in robot.transmissions {
    if transmission.joints.length() > 0 &&
      transmission.joints[0].name == "planetary_stage_carrier_joint" {
      has_carrier_transmission = true
      if transmission.actuators.length() > 0 {
        match transmission.actuators[0].mechanical_reduction {
          Some(reduction) => assert_true(reduction > 3.0)
          None => fail("carrier transmission has no reduction")
        }
      }
    }
  }
  assert_true(has_carrier_transmission)
}

///|
test "output magnet is parameterized and the printed sensor can be omitted" {
  let act = @components.planetary_bldc_actuator(
    output_sensor="none",
    magnet_diameter_mm=8.0,
    magnet_height_mm=3.0,
  )
  let robot = act.to_robot()
  assert_true(!robot.has_errors())
  assert_true(act.get_mate("sensor_base") is Some(_))
  assert_true(act.get_mate("sensor_mount") is Some(_))
  let bom = act.bom()
  let mut has_magnet = false
  let mut has_fake_sensor = false
  for line in bom.lines {
    if line.part_number == "MAG-8x3-DIA" {
      has_magnet = true
    }
    if line.part_number.contains("ENC-AS5047P") {
      has_fake_sensor = true
    }
  }
  assert_true(has_magnet)
  assert_false(has_fake_sensor)
}
