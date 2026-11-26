///|
test "raiway default params match raiway-large-wheel-robot.png specs" {
  let p = RaiwayParams::new()
  assert_eq(p.total_height_mm, 1140.0)
  assert_eq(p.torso_height_mm, 488.0)
  assert_eq(p.thigh_len_mm, 320.0)
  assert_eq(p.shin_len_mm, 320.0)
  assert_eq(p.wheel_radius_mm, 254.0)
  assert_eq(p.track_width_mm, 586.0)
  assert_eq(standing_hip_z_mm(p), 578.0)
  assert_eq(standing_leg_drop_mm(p), 324.0)
}

///|
test "raiway standing IK places both 20-inch wheels on z=0 at track width 586mm" {
  let p = RaiwayParams::new()
  let robot = build_raiway(params=p)
  let pos = pose_positions(p, pose="standing")
  let fk = robot.to_robot().forward_kinematics(joint_positions=pos)
  let wl = fk.get("wheel_left").unwrap()
  let wr = fk.get("wheel_right").unwrap()
  let pl = wl.apply_point((0.0, 0.0, 0.0))
  let pr = wr.apply_point((0.0, 0.0, 0.0))
  // Wheel centers must sit at z = 254 mm (so R=254 mm tire bottom touches z = 0)
  // and y = +/-293 mm (exact 586 mm track width) with x = 0 under the hip.
  assert_true((pl.0 * 1000.0).abs() < 1.0e-3)
  assert_true((pr.0 * 1000.0).abs() < 1.0e-3)
  assert_true(((pl.1 - pr.1) * 1000.0 - 586.0).abs() < 1.0e-3)
  assert_true((pl.2 * 1000.0 - 254.0).abs() < 1.0e-3)
  assert_true((pr.2 * 1000.0 - 254.0).abs() < 1.0e-3)
}

///|
test "raiway stair pose lifts left wheel 150mm above right wheel" {
  let p = RaiwayParams::new()
  let robot = build_raiway(params=p)
  let pos = pose_positions(p, pose="stair")
  let fk = robot.to_robot().forward_kinematics(joint_positions=pos)
  let pl = fk.get("wheel_left").unwrap().apply_point((0.0, 0.0, 0.0))
  let pr = fk.get("wheel_right").unwrap().apply_point((0.0, 0.0, 0.0))
  let step_mm = (pl.2 - pr.2) * 1000.0
  assert_true((step_mm - 150.0).abs() < 1.0e-3)
}

///|
test "raiway hip/knee (6:1) and wheel (4:1) A12 gearboxes are valid" {
  let p = RaiwayParams::new()
  let hk = hip_knee_actuator_params(p, "hk")
  let wh = wheel_actuator_params(p, "wh")
  assert_eq(hk.sun_teeth, 12)
  assert_eq(hk.planet_teeth, 24)
  assert_eq(wh.sun_teeth, 20)
  assert_eq(wh.planet_teeth, 20)
  assert_eq(hk.tolerance_mm, @step_common.DEFAULT_GEAR_TOLERANCE_MM)
  assert_eq(wh.tolerance_mm, @step_common.DEFAULT_GEAR_TOLERANCE_MM)
  // Full URDF diagnostics must have zero errors (no duplicate joints/links).
  let diags = build_raiway(params=p).to_robot().diagnostics()
  for d in diags {
    if d.severity().is_error() {
      fail("URDF diagnostic error: \{d.message()}")
    }
  }
}
