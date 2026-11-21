///|
test "parse detail level options" {
  assert_true(
    @cad.parse_detail_level("simplified")
    is Some(@step_common.DetailLevel::Simplified),
  )
  assert_true(
    @cad.parse_detail_level("detailed")
    is Some(@step_common.DetailLevel::Detailed),
  )
  assert_true(
    @cad.parse_detail_level("fully-modeled")
    is Some(@step_common.DetailLevel::FullyModeled),
  )
  assert_true(
    @cad.parse_detail_level("fully_modeled")
    is Some(@step_common.DetailLevel::FullyModeled),
  )
  assert_true(@cad.parse_detail_level("nonsense") is None)
}

///|
test "parse thread representation options" {
  assert_true(
    @cad.parse_thread_rep("none")
    is Some(@step_common.ThreadRepresentation::None),
  )
  assert_true(
    @cad.parse_thread_rep("cosmetic")
    is Some(@step_common.ThreadRepresentation::Cosmetic),
  )
  assert_true(
    @cad.parse_thread_rep("helical")
    is Some(@step_common.ThreadRepresentation::Helical),
  )
  assert_true(@cad.parse_thread_rep("square") is None)
}

///|
test "detail and thread names round-trip" {
  assert_eq(
    @cad.detail_level_name(@step_common.DetailLevel::Simplified),
    "simplified",
  )
  assert_eq(
    @cad.detail_level_name(@step_common.DetailLevel::Detailed),
    "detailed",
  )
  assert_eq(
    @cad.detail_level_name(@step_common.DetailLevel::FullyModeled),
    "fully-modeled",
  )
  assert_eq(
    @cad.thread_rep_name(@step_common.ThreadRepresentation::None),
    "none",
  )
  assert_eq(
    @cad.thread_rep_name(@step_common.ThreadRepresentation::Cosmetic),
    "cosmetic",
  )
  assert_eq(
    @cad.thread_rep_name(@step_common.ThreadRepresentation::Helical),
    "helical",
  )
  for name in ["simplified", "detailed", "fully-modeled"] {
    assert_true(@cad.parse_detail_level(name) is Some(_))
  }
  for name in ["none", "cosmetic", "helical"] {
    assert_true(@cad.parse_thread_rep(name) is Some(_))
  }
}

///|
test "bearing primitive converts every layer to a body" {
  let bearing = match
    @step_motion.bearing_by_designation("608", detail=@step_common.Detailed) {
    Ok(comp) => comp
    Err(_) => abort("bearing should build")
  }
  let bodies = @cad.BodyPart::from_step_component(bearing)
  // Outer ring, inner ring, and balls are separate layers.
  assert_true(bodies.length() >= 3)
  let mut mass = 0.0
  for body in bodies {
    mass = mass + body.inertial.mass
  }
  assert_true(mass > 0.0)
}

///|
test "step component converts to bodies with one part" {
  let screw = match
    @step_fasteners.iso4762_screw(
      @step_standards.M3,
      12.0,
      detail=@step_common.Detailed,
    ) {
    Ok(comp) => comp
    Err(_) => abort("screw should build")
  }
  let part = @cad.PartMeta::new(
    "ISO4762-M3x12",
    description="socket head cap screw",
    process="purchased",
  )
  let bodies = @cad.BodyPart::from_step_component(screw, part=Some(part))
  assert_true(bodies.length() > 0)
  let mut mass = 0.0
  let mut parts = 0
  for body in bodies {
    mass = mass + body.inertial.mass
    match body.part {
      Some(_) => parts = parts + 1
      None => ()
    }
  }
  assert_true(mass > 0.0)
  assert_eq(parts, 1)
}

///|
test "step component converts to a cad component with metadata" {
  let screw = match @step_fasteners.iso4762_screw(@step_standards.M4, 16.0) {
    Ok(comp) => comp
    Err(_) => abort("screw should build")
  }
  let comp = @cad.Component::from_step_component("screw", screw)
  assert_true(comp.bodies.length() > 0)
  assert_eq(comp.parameters.get("standard"), Some("ISO 4762:2004"))
  assert_true(comp.parameters.get("designation").unwrap() != "")
}

///|
test "revolved profile is safe for gltf" {
  let sphere = @step_cad.RevolvedProfile::sphere(20.0).as_shape()
  let node = sphere.with_name("ball")
  let safe = @cad.gltf_safe_node(node)
  let (x0, x1, y0, y1, z0, z1) = safe.bounding_box()
  assert_true(x1 - x0 > 15.0)
  assert_true(y1 - y0 > 15.0)
  assert_true(z1 - z0 > 15.0)
}

///|
test "design with a revolved profile exports gltf" {
  let sphere = @step_cad.RevolvedProfile::sphere(8.0)
    .as_shape()
    .with_name("ball")
  let design = @step_cad.Design::new(name="sphere_test").add(sphere)
  let gltf = @cad.gltf_safe_design(design).to_gltf()
  assert_true(gltf.contains("\"2.0\""))
  // The exact STEP export keeps the spherical surface.
  assert_true(design.to_step_file().contains("SPHERICAL_SURFACE"))
}

///|
test "imported STEP body keeps the vendor geometry and a placed bbox" {
  let source = @step_cad.Design::new(name="vendor")
    .add(@step_cad.Cuboid::new(10.0, 20.0, 30.0).with_name("vendor-board"))
    .to_step_file()
  let part = @cad.PartMeta::new(
    "VENDOR-BOARD",
    description="Vendor controller board",
    material="FR-4",
    process="purchased",
    unit_cost_usd=100.0,
  )
  let body = @cad.BodyPart::imported_step(
    "board",
    source,
    source="test",
    density=@urdf.Density::g_per_cm3(1.85),
    part=Some(part),
    x_mm=5.0,
  )
  let (x0, x1, y0, y1, z0, z1) = body.node.bounding_box()
  assert_true((x0 - 5.0).abs() < 1.0e-9)
  assert_true((x1 - 15.0).abs() < 1.0e-9)
  assert_true(y1 - y0 > 19.0)
  assert_true(z1 - z0 > 29.0)
  assert_true(body.inertial.mass > 0.0)
  let comp = @cad.Component::new("import-test").add_body(body)
  let step = comp.to_step_file()
  assert_true(step.contains("vendor-board"))
  assert_true(step.contains("MANIFOLD_SOLID_BREP"))
  assert_eq(comp.bom().unassigned, 0)
}

///|
test "from_scene_node uses true shape volume for hollow tubes and curved arcs" {
  let tube = @step_cad.RevolvedProfile::tube(100.0, 90.0, 20.0)
    .as_shape()
    .with_name("thin-ring")
  let body = @cad.BodyPart::from_scene_node(
    tube,
    density=@urdf.Density::kg_per_m3(1000.0),
  )
  // Exact annulus volume: pi * (50^2 - 45^2) * 20 = 29845.13 mm^3 -> ~0.02985 kg
  // (bounding box would have been 100 * 100 * 20 = 200000 mm^3 -> 0.20 kg).
  assert_true(body.inertial.mass > 0.027 && body.inertial.mass < 0.033)
  let r0 = 40.0
  let r1 = 44.0
  let da = 0.2
  let a0 = (@math.cos(0.0) * r1, @math.sin(0.0) * r1)
  let b0 = (@math.cos(da) * r1, @math.sin(da) * r1)
  let b1 = (@math.cos(da) * r0, @math.sin(da) * r0)
  let a1 = (@math.cos(0.0) * r0, @math.sin(0.0) * r0)
  let magnet = @step_cad.ExtrudedArcProfile::new(
      [
        @step_cad.SegmentArc(a0, b0, (0.0, 0.0)),
        @step_cad.SegmentLine(b0, b1),
        @step_cad.SegmentArc(b1, a1, (0.0, 0.0)),
        @step_cad.SegmentLine(a1, a0),
      ],
      10.0,
    )
    .as_shape()
    .with_name("arc-magnet")
  let mag_body = @cad.BodyPart::from_scene_node(
    magnet,
    density=@urdf.Density::kg_per_m3(7500.0),
  )
  // Sector volume: 0.5 * (44^2 - 40^2) * 0.2 * 10 = 336 mm^3 -> ~0.00252 kg.
  assert_true(
    mag_body.inertial.mass > 0.0020 && mag_body.inertial.mass < 0.0032,
  )
}

///|
test "gltf_safe_node keeps centered bounding boxes and uses coaxial proxies for round solids" {
  // 1. Hollow revolved tube becomes a hollow tube (ExtrudedProfile with a hole)
  // centered on [-50..50, -50..50, 0..20].
  let tube = @step_cad.RevolvedProfile::tube(100.0, 90.0, 20.0)
    .as_shape()
    .with_name("hollow-ring")
  let safe_tube = @cad.gltf_safe_node(tube)
  let (tx0, tx1, ty0, ty1, tz0, tz1) = safe_tube.bounding_box()
  assert_true((tx0 + 50.0).abs() < 0.5 && (tx1 - 50.0).abs() < 0.5)
  assert_true((ty0 + 50.0).abs() < 0.5 && (ty1 - 50.0).abs() < 0.5)
  assert_true(tz0.abs() < 1.0e-6 && (tz1 - 20.0).abs() < 1.0e-6)
  match safe_tube.shape {
    @step_cad.Shape::ExtrudedProfile(ext) =>
      assert_eq(ext.profile.holes.length(), 1)
    _ => fail("expected hollow tube ExtrudedProfile for RevolvedProfile::tube")
  }

  // 2. Centered imported STEP disk along Y (38 x 9.5 x 38, like moteus-c1)
  // stays centered on [-19..19, -4.75..4.75, -19..19] instead of shifting to [0..38].
  let disk_step = @step_cad.Design::new(name="disk")
    .add(
      @step_cad.ExtrudedProfile::new(
        @step_cad.Profile2D::circle(38.0, segments=32),
        9.5,
      )
      .with_name("pcb-disk")
      .rotate_x(-90.0)
      .translate(y=-4.75),
    )
    .to_step_file()
  let disk_body = @cad.BodyPart::imported_step("pcb-disk", disk_step)
  let safe_disk = @cad.gltf_safe_node(disk_body.node)
  let (dx0, dx1, dy0, dy1, dz0, dz1) = safe_disk.bounding_box()
  assert_true((dx0 + 19.0).abs() < 0.5 && (dx1 - 19.0).abs() < 0.5)
  assert_true((dy0 + 4.75).abs() < 0.5 && (dy1 - 4.75).abs() < 0.5)
  assert_true((dz0 + 19.0).abs() < 0.5 && (dz1 - 19.0).abs() < 0.5)
  assert_true(safe_disk.shape is @step_cad.Shape::Cylinder(_))

  // 3. Non-circular imported STEP box centered at origin keeps its exact
  // [-5..5, -10..10, -15..15] bounds without shifting by half-extents.
  let box_step = @step_cad.Design::new(name="centered-box")
    .add(
      @step_cad.Cuboid::new(10.0, 20.0, 30.0)
      .with_name("box")
      .translate(x=-5.0, y=-10.0, z=-15.0),
    )
    .to_step_file()
  let box_body = @cad.BodyPart::imported_step("box", box_step)
  let safe_box = @cad.gltf_safe_node(box_body.node)
  let (bx0, bx1, by0, by1, bz0, bz1) = safe_box.bounding_box()
  assert_true((bx0 + 5.0).abs() < 1.0e-6 && (bx1 - 5.0).abs() < 1.0e-6)
  assert_true((by0 + 10.0).abs() < 1.0e-6 && (by1 - 10.0).abs() < 1.0e-6)
  assert_true((bz0 + 15.0).abs() < 1.0e-6 && (bz1 - 15.0).abs() < 1.0e-6)
}
