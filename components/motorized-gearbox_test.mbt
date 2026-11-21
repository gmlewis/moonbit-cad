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

///|
test "A12 motorized gearbox attaches rotor to stage1 sun with ventilated housing" {
  let stage = @components.MotorizedStageSpec::new(
    module_mm=2.0,
    sun_teeth=12,
    planet_teeth=20,
    planet_count=4,
    gear_length_mm=10.0,
    num_elbows=4,
  )
  let comp = @components.motorized_gearbox(
    stages=[stage, stage],
    motor_source="a12",
  )
  let robot = check_motorized_gearbox(comp)
  let parts : Array[String] = comp
    .printable_parts()
    .map(fn(part) { part.part_number })
  assert_true(parts.contains("MG-MOTOR-HOUSING"))
  assert_true(parts.contains("MG-ROTOR-ADAPTER"))
  assert_true(parts.contains("MG-STAGE2-COUPLER"))
  assert_false(parts.contains("MG-MOTOR-CAP"))
  match robot.get_joint("motorized_gearbox_stage1_sun_joint") {
    Some(j) => {
      assert_true(j.joint_type == @urdf.JointType::Fixed)
      assert_eq(j.parent, "motorized_gearbox_motor_rotor")
      assert_eq(j.child, "motorized_gearbox_stage1_sun")
    }
    None => fail("missing stage1 sun attachment joint")
  }
  let cart = @components.motorized_stage_cartridge(
    stages=[stage, stage],
    stage_index=1,
    motor_source="a12",
  )
  let cart_parts : Array[String] = cart
    .printable_parts()
    .map(fn(part) { part.part_number })
  assert_true(cart_parts.contains("MG-STAGE1-CARTRIDGE"))
}

///|
test "wheel-mode A12 gearbox supports dual bearings, flush tire mount, moteus shroud, and single actuator budget" {
  let stage = @components.MotorizedStageSpec::new(
    module_mm=2.0,
    sun_teeth=12,
    planet_teeth=20,
    planet_count=4,
    gear_length_mm=10.0,
    num_elbows=4,
  )
  let comp = @components.motorized_gearbox(
    stages=[stage],
    motor_source="a12",
    output_hub_diam_mm=80.0,
    output_hub_thickness_mm=10.0,
    output_free_length_mm=0.0,
    tire_mount_bolt_circle_mm=55.85,
    dual_output_bearing=true,
    tire_mount_flush=true,
    moteus_shroud=true,
  )
  let _ = check_motorized_gearbox(comp)
  let parts : Array[String] = comp
    .printable_parts()
    .map(fn(part) { part.part_number })
  assert_true(parts.contains("MG-MOTEUS-SHROUD"))
  let mut bearings = 0
  let mut collars = 0
  for line in comp.bom().lines {
    if line.part_number == "BEARING-FR8-2RS" {
      bearings = line.quantity
    } else if line.part_number == "COLLAR-12.7-25.4" {
      collars = line.quantity
    }
  }
  // 4 planet bearings + 2 spaced output bearings.
  assert_eq(bearings, 6)
  // Flush mount omits the spacer shaft collar between hub and tire mount.
  assert_eq(collars, 0)
  // Power budget must count the combined geared A12 once, not twice.
  assert_eq(comp.power_budget().actuators.length(), 1)
}

///|
test "single-stage cycloidal motorized gearbox builds valid URDF and STEP" {
  let stage = @components.MotorizedStageSpec::cycloidal(
    num_lobes=11,
    num_disks=2,
  )
  let comp = @components.motorized_gearbox(stages=[stage], motor_source="a12")
  let robot = check_motorized_gearbox(comp)
  assert_eq(comp.parameters.get("stage_types").unwrap(), "cycloidal")
  assert_eq(comp.parameters.get("signed_reduction").unwrap(), "-11")
  assert_eq(comp.parameters.get("reduction").unwrap(), "11")
  match robot.get_joint("motorized_gearbox_stage1_carrier_joint") {
    Some(j) =>
      match j.mimic {
        Some(m) => assert_true((m.multiplier + 1.0 / 11.0).abs() < 1.0e-9)
        None => fail("expected mimic on cycloidal carrier joint")
      }
    None => fail("missing cycloidal stage1 carrier joint")
  }
}

///|
test "single-stage harmonic motorized gearbox builds valid URDF and STEP" {
  let stage = @components.MotorizedStageSpec::harmonic(
    module_mm=1.0,
    flexspline_teeth=60,
    tooth_diff=2,
  )
  let comp = @components.motorized_gearbox(stages=[stage], motor_source="a12")
  let robot = check_motorized_gearbox(comp)
  assert_eq(comp.parameters.get("stage_types").unwrap(), "harmonic")
  assert_eq(comp.parameters.get("signed_reduction").unwrap(), "-30")
  assert_eq(comp.parameters.get("reduction").unwrap(), "30")
  match robot.get_joint("motorized_gearbox_stage1_carrier_joint") {
    Some(j) =>
      match j.mimic {
        Some(m) => assert_true((m.multiplier + 1.0 / 30.0).abs() < 1.0e-9)
        None => fail("expected mimic on harmonic carrier joint")
      }
    None => fail("missing harmonic stage1 carrier joint")
  }
}

///|
test "heterogeneous 3-stage gearbox stacks planetary, cycloidal, and harmonic stages" {
  let s1 = @components.MotorizedStageSpec::default()
  let s2 = @components.MotorizedStageSpec::cycloidal(num_lobes=11, num_disks=2)
  let s3 = @components.MotorizedStageSpec::harmonic(
    module_mm=1.0,
    flexspline_teeth=60,
    tooth_diff=2,
  )
  let comp = @components.motorized_gearbox(
    stages=[s1, s2, s3],
    motor_source="a12",
  )
  let robot = check_motorized_gearbox(comp)
  assert_eq(
    comp.parameters.get("stage_types").unwrap(),
    "planetary,cycloidal,harmonic",
  )
  // Net signed reduction: (1 + 52/12) * (-11) * (-30) = (16/3) * 330 = +1760.0.
  let signed = @string.parse_double(
    comp.parameters.get("signed_reduction").unwrap(),
  ) catch {
    _ => abort("invalid signed_reduction")
  }
  assert_true((signed - 1760.0).abs() < 1.0e-6)
  // Verify mimic chain from stage 1 -> stage 2 -> stage 3.
  match robot.get_joint("motorized_gearbox_stage2_sun_joint") {
    Some(j) =>
      match j.mimic {
        Some(m) => {
          assert_eq(m.joint, "motorized_gearbox_stage1_carrier_joint")
          assert_true((m.multiplier - 1.0).abs() < 1.0e-9)
        }
        None => fail("missing stage2 input mimic")
      }
    None => fail("missing stage2 input joint")
  }
  match robot.get_joint("motorized_gearbox_stage3_sun_joint") {
    Some(j) =>
      match j.mimic {
        Some(m) => {
          assert_eq(m.joint, "motorized_gearbox_stage2_carrier_joint")
          assert_true((m.multiplier - 1.0).abs() < 1.0e-9)
        }
        None => fail("missing stage3 input mimic")
      }
    None => fail("missing stage3 input joint")
  }
  match robot.get_joint("motorized_gearbox_stage3_carrier_joint") {
    Some(j) =>
      match j.mimic {
        Some(m) => {
          assert_eq(m.joint, "motorized_gearbox_stage3_sun_joint")
          assert_true((m.multiplier + 1.0 / 30.0).abs() < 1.0e-9)
        }
        None => fail("missing stage3 output mimic")
      }
    None => fail("missing stage3 output joint")
  }
}

///|
test "stepped-planetary, wolfrom 3K, and flat-harmonic stages stack cleanly in motorized_gearbox" {
  let s1 = @components.MotorizedStageSpec::stepped_planetary()
  let s2 = @components.MotorizedStageSpec::wolfrom()
  let s3 = @components.MotorizedStageSpec::flat_harmonic()
  let comp = @components.motorized_gearbox(
    stages=[s1, s2, s3],
    motor_source="a12",
  )
  let _ = check_motorized_gearbox(comp)
  assert_eq(
    comp.parameters.get("stage_types").unwrap(),
    "stepped-planetary,wolfrom,flat-harmonic",
  )
  // Net signed reduction: 10.2 * 85.0 * (-30.0) = -26010.0.
  let signed = @string.parse_double(
    comp.parameters.get("signed_reduction").unwrap(),
  ) catch {
    _ => abort("invalid signed_reduction")
  }
  assert_true((signed + 26010.0).abs() < 1.0e-4)
}
