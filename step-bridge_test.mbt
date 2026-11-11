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
