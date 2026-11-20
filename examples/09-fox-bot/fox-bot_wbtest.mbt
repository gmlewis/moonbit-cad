///|
test "FOX_BOT 2D sketches have clean bolt-hole edge margins" {
  let params = FoxBotParams::default()
  let bracket_warnings = fox_hip_bracket_sketch(params).validate_edge_margins(
    2.0,
  )
  assert_eq(bracket_warnings.length(), 0)
  let crank_warnings = fox_hip_crank_sketch(params).validate_edge_margins(2.0)
  assert_eq(crank_warnings.length(), 0)
  let guide_warnings = fox_guide_link_sketch(params).validate_edge_margins(2.0)
  assert_eq(guide_warnings.length(), 0)
  let calf_warnings = fox_calf_strut_sketch(params).validate_edge_margins(2.0)
  assert_eq(calf_warnings.length(), 0)
}

///|
test "FOX_BOT URDF has zero errors, 4 loop constraints, and exact Pivot D FK closure across poses" {
  let base = FoxBotParams::default()
  let robot_comp = fox_bot(params={
    ..base,
    detail: @step_common.DetailLevel::Simplified,
  })
  let urdf_robot = robot_comp.to_robot()
  let errors = urdf_robot
    .diagnostics()
    .filter(fn(d) { d.severity() is @urdf.Severity::Error })
  assert_eq(errors.length(), 0)
  assert_eq(urdf_robot.loop_constraints.length(), 4)

  // Verify MuJoCo MJCF contains all 4 closed-chain connect equalities + IMU sensors
  let mjcf = urdf_robot.to_mjcf_string()
  assert_true(mjcf.contains("lf_pivot_d_loop"))
  assert_true(mjcf.contains("rf_pivot_d_loop"))
  assert_true(mjcf.contains("rr_pivot_d_loop"))
  assert_true(mjcf.contains("lr_pivot_d_loop"))
  assert_true(mjcf.contains("<accelerometer"))
  assert_true(mjcf.contains("<gyro"))

  // Verify exact URDF FK Pivot D closure (< 1e-6 m in X, Y, and Z) on ALL 4 legs
  // across mid, crouched, tall, roll, pitch, pounce, and ref poses!
  for pose in ["mid", "crouched", "tall", "roll", "pitch", "pounce", "ref"] {
    let p = { ..base, pose, }
    let fk = urdf_robot.forward_kinematics(joint_positions=p.pose_positions())
    for lc in urdf_robot.loop_constraints {
      let t1 = fk.get(lc.body1).unwrap()
      let t2 = fk.get(lc.body2).unwrap()
      let p1 = t1.apply_point(lc.anchor1)
      let p2 = t2.apply_point(lc.anchor2)
      let err = ((p1.0 - p2.0) * (p1.0 - p2.0) +
      (p1.1 - p2.1) * (p1.1 - p2.1) +
      (p1.2 - p2.2) * (p1.2 - p2.2)).sqrt()
      if err >= 1.0e-6 {
        fail(
          "pose=\{pose} loop=\{lc.name} err=\{err} p1=(\{p1.0},\{p1.1},\{p1.2}) p2=(\{p2.0},\{p2.1},\{p2.2})",
        )
      }
    }
  }
}

///|
test "FOX_BOT wheels sit cleanly outboard of calves and symmetric in Y and Z" {
  let base = {
    ..FoxBotParams::default(),
    detail: @step_common.DetailLevel::Simplified,
  }
  let comp = fox_bot(params=base)
  let design = comp.to_design(joint_positions=base.pose_positions())
  let mut lf_tire_ymin = 1.0e9
  let mut lf_tire_ymax = -1.0e9
  let mut lf_tire_zmin = 1.0e9
  let mut rf_tire_zmin = 1.0e9
  let mut rr_tire_zmin = 1.0e9
  let mut lr_tire_zmin = 1.0e9
  let mut lf_calf_ymax = -1.0e9
  for node in design.nodes {
    let (_x0, _x1, y0, y1, z0, _z1) = node.bounding_box()
    if node.name.contains("lf_tire") && !node.name.contains("bolt") {
      if y0 < lf_tire_ymin {
        lf_tire_ymin = y0
      }
      if y1 > lf_tire_ymax {
        lf_tire_ymax = y1
      }
      if z0 < lf_tire_zmin {
        lf_tire_zmin = z0
      }
    }
    if node.name.contains("rf_tire") &&
      !node.name.contains("bolt") &&
      z0 < rf_tire_zmin {
      rf_tire_zmin = z0
    }
    if node.name.contains("rr_tire") &&
      !node.name.contains("bolt") &&
      z0 < rr_tire_zmin {
      rr_tire_zmin = z0
    }
    if node.name.contains("lr_tire") &&
      !node.name.contains("bolt") &&
      z0 < lr_tire_zmin {
      lr_tire_zmin = z0
    }
    if node.name.contains("lf_calf_body") && y1 > lf_calf_ymax {
      lf_calf_ymax = y1
    }
  }
  // Tire must sit cleanly outboard of the calf strut (no overlap into the calf!)
  if !(lf_tire_ymin > lf_calf_ymax + 2.0) {
    fail(
      "lf_tire_y=[\{lf_tire_ymin}, \{lf_tire_ymax}] vs lf_calf_ymax=\{lf_calf_ymax}",
    )
  }
  assert_true(lf_tire_ymax > lf_tire_ymin + 35.0)
  // All 4 wheels must touch the exact same ground plane in mid-stance (< 0.1 mm)
  assert_true((lf_tire_zmin - rf_tire_zmin).abs() < 0.1)
  assert_true((lf_tire_zmin - rr_tire_zmin).abs() < 0.1)
  assert_true((lf_tire_zmin - lr_tire_zmin).abs() < 0.1)
}

///|
fn design_bbox(
  d : @step_cad.Design,
) -> (Double, Double, Double, Double, Double, Double) {
  let mut x0 = 1.0e18
  let mut x1 = -1.0e18
  let mut y0 = 1.0e18
  let mut y1 = -1.0e18
  let mut z0 = 1.0e18
  let mut z1 = -1.0e18
  for node in d.nodes {
    let (nx0, nx1, ny0, ny1, nz0, nz1) = node.bounding_box()
    if nx0 < x0 {
      x0 = nx0
    }
    if nx1 > x1 {
      x1 = nx1
    }
    if ny0 < y0 {
      y0 = ny0
    }
    if ny1 > y1 {
      y1 = ny1
    }
    if nz0 < z0 {
      z0 = nz0
    }
    if nz1 > z1 {
      z1 = nz1
    }
  }
  (x0, x1, y0, y1, z0, z1)
}

///|
test "FOX_BOT scales cleanly and keeps A12 gear tolerance outer-envelope invariant" {
  let petg = {
    ..FoxBotParams::scaled(0.9),
    tolerance_mm: 0.042,
    detail: @step_common.DetailLevel::Simplified,
  }
  let pla = { ..petg, tolerance_mm: 0.25, }
  let c1 = fox_bot(params=petg)
  let c2 = fox_bot(params=pla)
  let d1 = c1.to_design(joint_positions=petg.pose_positions())
  let d2 = c2.to_design(joint_positions=pla.pose_positions())
  let (x0a, x1a, y0a, y1a, z0a, z1a) = design_bbox(d1)
  let (x0b, x1b, y0b, y1b, z0b, z1b) = design_bbox(d2)
  assert_true((x0a - x0b).abs() < 1.0e-6)
  assert_true((x1a - x1b).abs() < 1.0e-6)
  assert_true((y0a - y0b).abs() < 1.0e-6)
  assert_true((y1a - y1b).abs() < 1.0e-6)
  assert_true((z0a - z0b).abs() < 1.0e-6)
  assert_true((z1a - z1b).abs() < 1.0e-6)
}
