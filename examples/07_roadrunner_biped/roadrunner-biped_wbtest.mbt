///|
test "roadrunner biped mass, URDF diagnostics, and 8-DOF bindings" {
  let robot = build_roadrunner()
  assert_eq(robot.control.length(), 8)
  assert_eq(robot.cables.length(), 1)
  let total_mass = robot.total_mass_kg()
  assert_true(total_mass > 13.0 && total_mass < 18.0)
  let bundle = robot.to_urdf_bundle(package_name="roadrunner")
  let diag = bundle.robot.diagnostics()
  let error_count = diag.filter(fn(d) { d.severity().is_error() }).length()
  assert_eq(error_count, 0)
  assert_true(bundle.robot.links.length() >= 20)
  assert_true(bundle.robot.joints.length() >= 19)
}

///|
test "roadrunner pose presets return symmetric 8-joint maps" {
  for mode in ["side-by-side", "in-line", "one-wheel", "wide"] {
    let pos = pose_positions(mode~)
    assert_eq(pos.length(), 8)
    for
      joint in [
        "l_hip_roll_joint", "r_hip_roll_joint", "l_hip_pitch_joint", "r_hip_pitch_joint",
        "l_knee_joint", "r_knee_joint", "l_wheel_joint", "r_wheel_joint",
      ] {
      assert_true(pos.get(joint) is Some(_))
    }
  }
  let side = pose_positions(mode="side-by-side")
  assert_true(side.get("l_hip_pitch_joint") == Some(18.0 * @math.PI / 180.0))
  assert_true(side.get("l_knee_joint") == Some(36.0 * @math.PI / 180.0))
  assert_true(side.get("r_hip_pitch_joint") == Some(-18.0 * @math.PI / 180.0))
  assert_true(side.get("r_knee_joint") == Some(-36.0 * @math.PI / 180.0))
}
