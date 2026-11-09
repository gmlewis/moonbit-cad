///|
fn near(a : Double, b : Double, tol~ : Double = 1.0e-9) -> Bool {
  (a - b).abs() <= tol
}

///|
test "centered cuboid bounding box" {
  let (x0, x1, y0, y1, z0, z1) = @cad.centered_cuboid_node(20.0, 40.0, 60.0).bounding_box()
  assert_true(near(x0, -10.0))
  assert_true(near(x1, 10.0))
  assert_true(near(y0, -20.0))
  assert_true(near(y1, 20.0))
  assert_true(near(z0, -30.0))
  assert_true(near(z1, 30.0))
}

///|
test "centered cylinder spans z symmetric" {
  let (_, _, _, _, z0, z1) = @cad.centered_cylinder_node(20.0, 50.0).bounding_box()
  assert_true(near(z0, -25.0))
  assert_true(near(z1, 25.0))
}

///|
test "centered tube and extrusion are centered" {
  let (_, _, _, _, tz0, tz1) = @cad.centered_tube_node(20.0, 10.0, 12.0).bounding_box()
  assert_true(near(tz0, -6.0))
  assert_true(near(tz1, 6.0))
  let outer = @step_cad.Profile2D::centered_rect(10.0, 20.0)
  let (_, _, _, _, ez0, ez1) = @cad.centered_extruded_profile_node(outer, 8.0).bounding_box()
  assert_true(near(ez0, -4.0))
  assert_true(near(ez1, 4.0))
}

///|
test "color round trip" {
  let rgb = @step_cad.Rgb::new(0.25, 0.5, 0.75)
  let rgba = @cad.rgb_to_rgba(rgb, a=0.5)
  assert_true(near(rgba.r, 0.25))
  assert_true(near(rgba.a, 0.5))
  let back = @cad.rgba_to_rgb(rgba)
  assert_true(near(back.r, 0.25))
  assert_true(near(back.g, 0.5))
  assert_true(near(back.b, 0.75))
}

///|
test "transform converts meters to millimeters and rotates" {
  let t : @urdf.Transform = {
    rot: @urdf.rotation_matrix_rpy(0.0, 0.0, @math.PI / 2.0),
    trans: (0.1, -0.2, 0.3),
  }
  let p = @cad.urdf_to_step_transform(t).apply((10.0, 0.0, 0.0))
  assert_true(near(p.0, 100.0))
  assert_true(near(p.1, -190.0))
  assert_true(near(p.2, 300.0))
}

///|
test "step to urdf transform scales back" {
  let step_t : @step_cad.Transform = {
    rot: @step_cad.Transform::identity().rot,
    trans: (1000.0, -2000.0, 500.0),
  }
  let u = @cad.step_to_urdf_transform(step_t)
  assert_true(near(u.trans.0, 1.0))
  assert_true(near(u.trans.1, -2.0))
  assert_true(near(u.trans.2, 0.5))
}

///|
test "matrix round trip preserves entries" {
  let m = @urdf.rotation_matrix_rpy(0.3, -0.4, 0.5)
  let back = @cad.step_to_urdf_matrix(@cad.urdf_to_step_matrix(m))
  assert_true(near(back.m00, m.m00))
  assert_true(near(back.m12, m.m12))
  assert_true(near(back.m22, m.m22))
}

///|
test "transform scene node applies urdf pose" {
  let node = @cad.centered_cuboid_node(2.0, 4.0, 6.0)
  let t : @urdf.Transform = {
    rot: @urdf.rotation_matrix_rpy(0.0, 0.0, @math.PI / 2.0),
    trans: (0.1, -0.2, 0.3),
  }
  let moved = @cad.transform_scene_node_urdf(node, t)
  let (x0, x1, y0, y1, _, _) = moved.bounding_box()
  // A 2x4 box rotated 90 degrees about Z then translated.
  assert_true(near(x0, 98.0, tol=1.0e-6))
  assert_true(near(x1, 102.0, tol=1.0e-6))
  assert_true(near(y0, -201.0, tol=1.0e-6))
  assert_true(near(y1, -199.0, tol=1.0e-6))
}
