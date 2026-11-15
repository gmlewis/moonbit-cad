///|
fn check_motorized_gearbox(comp : @cad.Component) -> @urdf.Robot raise {
  let robot = comp.to_robot()
  if robot.has_errors() {
    let mut msg = "diagnostics for " + comp.name + ":"
    for diagnostic in robot.diagnostics() {
      msg = msg + "\n  " + diagnostic.message()
    }
    fail(msg)
  }
  let step = comp.to_step_file()
  if !step.contains("ISO-10303-21;") {
    fail("missing STEP header for " + comp.name)
  }
  robot
}

///|
test "single-stage motorized gearbox compiles with an integrated casing ring" {
  let comp = @components.motorized_gearbox(stages=[
    @components.MotorizedStageSpec::default(),
  ])
  let robot = check_motorized_gearbox(comp)
  // Casing + motor stator + sun + carrier + 4 planets + rotor.
  assert_eq(robot.links.length(), 9)
  let parts : Array[String] = comp
    .printable_parts()
    .map(fn(part) { part.part_number })
  assert_true(parts.contains("MG-CASING-1"))
  assert_true(parts.contains("MG-SUN-1"))
  assert_true(parts.contains("MG-PLANET-1"))
  assert_true(parts.contains("MG-CARRIER-1"))
  assert_true(parts.contains("MG-MOTOR-CAP"))
  assert_true(parts.contains("MG-OUTPUT-CAP"))
  assert_true(parts.contains("MG-OUTPUT-HUB"))
  // The ring is part of the casing, never a separate PGB-RING part.
  assert_false(parts.contains("PGB-RING"))
  // The reduction is 1 + Zring/Zsun = 1 + 52/12.
  let reduction = 1.0 + 52.0 / 12.0
  match comp.parameters.get("reduction") {
    Some(text) => {
      let value = @string.parse_double(text) catch {
        _ => fail("reduction is not a number: " + text)
      }
      assert_true((value - reduction).abs() < 1.0e-9)
    }
    None => fail("missing reduction parameter")
  }
}

///|
test "three-stage gearbox chains each sun to the previous carrier" {
  let stage = @components.MotorizedStageSpec::default()
  let comp = @components.motorized_gearbox(stages=[stage, stage, stage])
  let robot = check_motorized_gearbox(comp)
  let mut chained = 0
  for joint in robot.joints {
    if joint.name.has_prefix("motorized_gearbox_stage2_sun_joint") ||
      joint.name.has_prefix("motorized_gearbox_stage3_sun_joint") {
      match joint.mimic {
        Some(mimic) => {
          chained = chained + 1
          assert_true(mimic.multiplier == 1.0)
          if joint.name.has_prefix("motorized_gearbox_stage2_sun_joint") {
            assert_eq(mimic.joint, "motorized_gearbox_stage1_carrier_joint")
          } else {
            assert_eq(mimic.joint, "motorized_gearbox_stage2_carrier_joint")
          }
        }
        None => fail("stage sun has no mimic: " + joint.name)
      }
    }
  }
  assert_eq(chained, 2)
  let parts = comp.printable_parts()
  let casing_modules = parts.filter(fn(part) {
    part.part_number.has_prefix("MG-CASING-")
  })
  assert_eq(casing_modules.length(), 3)
}

///|
test "flanged bearings are the default planet bearing" {
  let comp = @components.motorized_gearbox(stages=[
    @components.MotorizedStageSpec::default(),
  ])
  let bom = comp.bom()
  let mut bearing = 0
  for line in bom.lines {
    if line.part_number == "BEARING-FR8-2RS" {
      bearing = line.quantity
    }
  }
  // Four planets plus the output bearing.
  assert_eq(bearing, 5)
  let spec = @components.flanged_bearing_fr8_2rs()
  // The flange is wider than the bearing body, so a straight planet bore
  // seats it flush and cannot let it slide through.
  assert_true(spec.flange_outer_mm > spec.outer_mm)
  assert_true(spec.flange_thickness_mm > 0.0)
  assert_true(spec.bore_mm == 12.7)
}

///|
test "each stage keeps its own gear parameters" {
  let first = @components.MotorizedStageSpec::default()
  let second = @components.MotorizedStageSpec::new(
    module_mm=2.0,
    sun_teeth=12,
    planet_teeth=24,
    planet_count=4,
    gear_length_mm=10.0,
  )
  let comp = @components.motorized_gearbox(stages=[first, second])
  // Stage 1 is 1 + 52/12; stage 2 is 1 + 60/12.
  let reduction = (1.0 + 52.0 / 12.0) * (1.0 + 60.0 / 12.0)
  match comp.parameters.get("reduction") {
    Some(text) => {
      let value = @string.parse_double(text) catch {
        _ => fail("reduction is not a number: " + text)
      }
      assert_true((value - reduction).abs() < 1.0e-9)
    }
    None => fail("missing reduction parameter")
  }
  let parts : Array[String] = comp
    .printable_parts()
    .map(fn(part) { part.part_number })
  assert_true(parts.contains("MG-SUN-1"))
  assert_true(parts.contains("MG-SUN-2"))
  assert_true(parts.contains("MG-CASING-1"))
  assert_true(parts.contains("MG-CASING-2"))
}
