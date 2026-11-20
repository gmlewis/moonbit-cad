///|
test "a12 actuator interface is tolerance invariant" {
  let loose = @components.A12ActuatorParams::new(tolerance_mm=0.042)
  let tight = @components.A12ActuatorParams::new(tolerance_mm=0.25)

  assert_true(
    (loose.outer_radius_mm() - tight.outer_radius_mm()).abs() < 1.0e-9,
  )
  assert_true(
    (loose.center_distance_mm() - tight.center_distance_mm()).abs() < 1.0e-9,
  )
  assert_true((loose.total_len_mm() - tight.total_len_mm()).abs() < 1.0e-9)

  let a = @components.a12_planetary_actuator(loose)
  let b = @components.a12_planetary_actuator(tight)
  for name in ["housing_flange", "motor_rear", "output_hub", "mount_flange"] {
    let ma = a.mates.get(name).unwrap()
    let mb = b.mates.get(name).unwrap()
    assert_true(ma.placement.trans == mb.placement.trans)
    assert_true(ma.axis == mb.axis)
    assert_true(ma.hole_pattern == mb.hole_pattern)
  }
  // The public interfaces carry the expected patterns.
  let housing = a.mates.get("housing_flange").unwrap()
  assert_true(housing.hole_pattern is Some(_))
  let output = a.mates.get("output_hub").unwrap()
  match output.hole_pattern {
    Some(@step_cad.HolePattern::BoltCircle(count, bcd, _hole, pilot, _start)) => {
      assert_eq(count, 4)
      assert_true((bcd - 40.0).abs() < 1.0e-9)
      assert_true((pilot - 12.7).abs() < 1.0e-9)
    }
    _ => fail("expected a 4 x M4 output bolt circle with a pilot bore")
  }
}

///|
test "a12 actuator supports flush tire-mount hub interface" {
  let params = @components.A12ActuatorParams::new(
    tire_mount_bcd_mm=55.85,
    tire_mount_bolt_count=3,
    tire_mount_phase_deg=30.0,
    tire_mount_hole_diam_mm=6.0,
  )
  let act = @components.a12_planetary_actuator(params)
  let tm = act.mates.get("tire_mount").unwrap()
  match tm.hole_pattern {
    Some(@step_cad.HolePattern::BoltCircle(count, bcd, hole, pilot, start)) => {
      assert_eq(count, 3)
      assert_true((bcd - 55.85).abs() < 1.0e-9)
      assert_true((hole - 6.0).abs() < 1.0e-9)
      assert_true((pilot - 12.7).abs() < 1.0e-9)
      assert_true((start - 30.0).abs() < 1.0e-9)
    }
    _ => fail("expected a 3 x M4 tire_mount bolt circle")
  }
  let has_hub_80 = act.bodies.fold(init=false, fn(acc, b) {
    match b.part {
      Some(p) => acc || p.part_number == "A12-OUTPUT-HUB-80"
      None => acc
    }
  })
  assert_true(has_hub_80)
  // Round actuator discs must emit cylindrical (not square box) collisions.
  for suffix in ["_backplate", "_carrier", "_output_cap", "_output_hub"] {
    let found = act.bodies.filter(fn(b) { b.name.has_suffix(suffix) })
    assert_eq(found.length(), 1)
    assert_true(
      found[0].collisions[0].geometry is @urdf.Geometry::Cylinder(_, _),
    )
  }
}
