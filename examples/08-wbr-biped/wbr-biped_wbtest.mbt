///|
test "4-bar closed-chain kinematics closes D pivot across all poses and scales" {
  for s in [0.8, 1.0, 1.3] {
    let params = WbrParams::new(scale=s)
    let robot = build_wbr(params~)
    let bundle = robot.to_urdf_bundle(package_name="wbr_biped")
    let diag = bundle.robot.diagnostics()
    let err_count = diag.filter(fn(d) { d.severity().is_error() }).length()
    assert_eq(err_count, 0)
    assert_eq(robot.control.length(), 4)
    for pose in ["crouched", "standing", "tall"] {
      let positions = pose_positions(params, pose~)
      let fk = bundle.robot.forward_kinematics(joint_positions=positions)
      // Verify Pivot D on left calf matches Pivot D on left guide link in world meters.
      let t_calf = match fk.get("l_calf_link") {
        Some(t) => t
        None => fail("missing l_calf_link in FK")
      }
      let t_guide = match fk.get("l_guide_link") {
        Some(t) => t
        None => fail("missing l_guide_link in FK")
      }
      let d_on_calf = t_calf.apply_point(
        (params.coupler_len_mm / 1000.0, 0.0, 0.0),
      )
      let d_on_guide = t_guide.apply_point(
        (params.guide_len_mm / 1000.0, 0.0, 0.0),
      )
      let dx = d_on_calf.0 - d_on_guide.0
      let dy = d_on_calf.1 - d_on_guide.1
      let dz = d_on_calf.2 - d_on_guide.2
      // X and Z must close to sub-micrometer accuracy; Y differs by the lateral plane step.
      assert_true(dx.abs() < 1.0e-6)
      assert_true(dz.abs() < 1.0e-6)
      assert_true(dy.abs() > 0.01)
    }
  }
}

///|
test "WBR tolerance_mm preserves planetary outer dimensions" {
  let p_petg = WbrParams::new(tolerance_mm=0.042)
  let p_pla = WbrParams::new(tolerance_mm=0.25)
  let d_petg = wbr_actuator_dims(p_petg)
  let d_pla = wbr_actuator_dims(p_pla)
  assert_true((d_petg.outer_radius_mm - d_pla.outer_radius_mm).abs() < 1.0e-9)
  assert_true((d_petg.total_len_mm - d_pla.total_len_mm).abs() < 1.0e-9)
  assert_true(
    (d_petg.layout.center_distance_mm - d_pla.layout.center_distance_mm).abs() <
    1.0e-9,
  )
}
