///|
test "ExplodeStack separates coaxial layers with zero bounding-box overlap" {
  let housing = @step_cad.Cylinder::new(35.0, 30.0)
    .with_name("ACT-HOUSING")
    .translate(z=0.0)
  let gear = @step_cad.Cylinder::new(25.0, 14.0)
    .with_name("gearbox_stage1")
    .translate(z=8.0)
  let cover = @step_cad.Cylinder::new(35.0, 8.0)
    .with_name("output_cover")
    .translate(z=30.0)
  let motor = @step_cad.Cylinder::new(28.0, 20.0)
    .with_name("bldc_motor")
    .translate(z=-20.0)
  let moteus = @step_cad.Cuboid::new(40.0, 40.0, 6.0)
    .with_name("moteus_c1")
    .translate(x=-20.0, y=-20.0, z=-34.0)

  let design = @step_cad.Design::new(name="actuator")
    .add(housing)
    .add(gear)
    .add(cover)
    .add(motor)
    .add(moteus)

  let exploded = @cad.ExplodeStack::z_axis(anchor="ACT-HOUSING", gap_mm=20.0)
    .above_list(["gearbox", "output_cover"])
    .below_list(["bldc_motor", "moteus"])
    .apply(design)

  let (_, _, _, _, h_z0, h_z1) = exploded.nodes[0].bounding_box()
  let (_, _, _, _, g_z0, g_z1) = exploded.nodes[1].bounding_box()
  let (_, _, _, _, c_z0, _c_z1) = exploded.nodes[2].bounding_box()
  let (_, _, _, _, m_z0, m_z1) = exploded.nodes[3].bounding_box()
  let (_, _, _, _, _b_z0, b_z1) = exploded.nodes[4].bounding_box()

  // Anchor stays put at [0, 30]
  assert_true(h_z0.abs() < 1.0e-6)
  assert_true((h_z1 - 30.0).abs() < 1.0e-6)
  // Above layers clear each other by >= 20 mm
  assert_true(g_z0 >= h_z1 + 19.99)
  assert_true(c_z0 >= g_z1 + 19.99)
  // Below layers clear each other by >= 20 mm
  assert_true(m_z1 <= h_z0 - 19.99)
  assert_true(b_z1 <= m_z0 - 19.99)
}

///|
test "ExplodeStack above_where / below_where separates upper and lower inserts" {
  let housing = @step_cad.Cylinder::new(35.0, 30.0).with_name("housing")
  let top_ins = @step_cad.Cylinder::new(2.3, 5.7)
    .with_name("HEATSET_M3_0")
    .translate(z=24.0)
  let bot_ins = @step_cad.Cylinder::new(2.3, 5.7)
    .with_name("HEATSET_M3_1")
    .translate(z=-2.0)

  let design = @step_cad.Design::new(name="inserts")
    .add(housing)
    .add(top_ins)
    .add(bot_ins)

  let stack = @cad.ExplodeStack::z_axis(anchor="housing", gap_mm=15.0)
    .above_where(["HEATSET"], fn(n) { n.tz > 0.0 })
    .below_where(["HEATSET"], fn(n) { n.tz <= 0.0 })

  let offs = stack.offsets(design)
  assert_eq(offs.length(), 3)
  assert_true(offs[0].1.2.abs() < 1.0e-6)
  assert_true(offs[1].1.2 > 10.0)
  assert_true(offs[2].1.2 < -10.0)
}
