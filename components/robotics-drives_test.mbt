///|
fn check_drive(comp : @cad.Component) -> @urdf.Robot raise {
  let robot = comp.to_robot()
  if robot.has_errors() {
    let mut msg = "diagnostics for " + comp.name + ":"
    for d in robot.diagnostics() {
      msg = msg + "\n  " + d.message()
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
test "capstan_drive_component builds valid URDF with travel limits and STEP" {
  let comp = @components.capstan_drive_component(
    capstan_radius_mm=8.0,
    driven_radius_mm=48.0,
    cable_diameter_mm=1.0,
    travel_deg=180.0,
    crossed=true,
  )
  let robot = check_drive(comp)
  assert_eq(comp.parameters.get("drive_type").unwrap(), "capstan")
  match robot.get_joint("capstan_drive_output_joint") {
    Some(j) => {
      assert_true(j.joint_type == @urdf.JointType::Revolute)
      match j.mimic {
        Some(m) => assert_true((m.multiplier + 8.5 / 48.5).abs() < 1.0e-9)
        None => fail("expected mimic on capstan output")
      }
    }
    None => fail("missing capstan output joint")
  }
}

///|
test "worm_drive_component builds valid orthogonal URDF, self-locking metadata, and STEP" {
  let comp = @components.worm_drive_component(worm_starts=1, wheel_teeth=30)
  let robot = check_drive(comp)
  assert_eq(comp.parameters.get("drive_type").unwrap(), "worm")
  assert_eq(comp.parameters.get("self_locking").unwrap(), "true")
  match robot.get_joint("worm_drive_wheel_joint") {
    Some(j) =>
      match j.mimic {
        Some(m) => assert_true((m.multiplier - 1.0 / 30.0).abs() < 1.0e-9)
        None => fail("expected mimic on worm wheel")
      }
    None => fail("missing worm wheel joint")
  }
}

///|
test "bevel_differential_component builds valid 2-DOF pitch/roll URDF and STEP" {
  let comp = @components.bevel_differential_component(
    input_teeth=20,
    output_teeth=30,
  )
  let robot = check_drive(comp)
  assert_eq(comp.parameters.get("drive_type").unwrap(), "bevel_differential")
  assert_true(robot.get_joint("bevel_differential_motor_a_joint") is Some(_))
  assert_true(robot.get_joint("bevel_differential_motor_b_joint") is Some(_))
  assert_true(robot.get_joint("bevel_differential_pitch_joint") is Some(_))
  assert_true(robot.get_joint("bevel_differential_roll_joint") is Some(_))
}

///|
test "timing_belt_drive_component builds valid parallel-axis URDF and STEP" {
  let comp = @components.timing_belt_drive_component(
    driver_pitch_diam_mm=16.0,
    driven_pitch_diam_mm=48.0,
  )
  let robot = check_drive(comp)
  assert_eq(comp.parameters.get("drive_type").unwrap(), "timing_belt")
  match robot.get_joint("timing_belt_drive_driven_joint") {
    Some(j) =>
      match j.mimic {
        Some(m) => assert_true((m.multiplier - 1.0 / 3.0).abs() < 1.0e-9)
        None => fail("expected mimic on timing belt driven pulley")
      }
    None => fail("missing timing belt driven joint")
  }
}

///|
test "ball_screw_actuator_component builds valid rotary-to-prismatic URDF and STEP" {
  let comp = @components.ball_screw_actuator_component(
    lead_mm=4.0,
    stroke_mm=100.0,
  )
  let robot = check_drive(comp)
  assert_eq(comp.parameters.get("drive_type").unwrap(), "ball_screw")
  match robot.get_joint("ball_screw_actuator_carriage_joint") {
    Some(j) => {
      assert_true(j.joint_type == @urdf.JointType::Prismatic)
      match j.mimic {
        Some(m) => {
          let expected = 0.004 / (2.0 * @math.PI)
          assert_true((m.multiplier - expected).abs() < 1.0e-9)
        }
        None => fail("expected mimic on ball screw carriage")
      }
    }
    None => fail("missing ball screw carriage joint")
  }
}
