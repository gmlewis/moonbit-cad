///|
test "component bodies, mates, and total mass" {
  let base = @cad.Component::new("base", description="test base")
    .add_body(
      @cad.BodyPart::box_mm("plate", 40.0, 40.0, 6.0, x_mm=0.0, y_mm=0.0),
    )
    .add_body(@cad.BodyPart::cylinder_mm("boss", 12.0, 20.0, z_mm=13.0))
    .add_mate_mm_deg("top", z=3.0)
  assert_eq(base.name, "base")
  assert_eq(base.description, "test base")
  assert_eq(base.bodies.length(), 2)
  assert_true(base.get_mate("top") is Some(_))
  assert_true(base.get_mate("origin") is Some(_))
  assert_true(base.get_mate("missing") is None)

  let arm = @cad.Component::new("arm").add_body(
    @cad.BodyPart::cylinder_mm("shaft", 8.0, 40.0),
  )
  let limit = @urdf.JointLimit::new(
    effort=1.5,
    velocity=3.0,
    lower=Some(-1.0),
    upper=Some(1.0),
  )
  let comp = base.attach(
    "elbow",
    parent_mate="top",
    arm,
    child_mate="origin",
    spec=@cad.JointSpec::revolute(limit, transmission_reduction=Some(2.0)),
  )
  assert_eq(comp.attachments.length(), 1)
  let expected = base.bodies[0].inertial.mass +
    base.bodies[1].inertial.mass +
    arm.bodies[0].inertial.mass
  let got = comp.total_mass_kg()
  assert_true((got - expected).abs() < 1.0e-12)
  assert_true(got > 0.0)
}

///|
test "component parameters are recorded" {
  let comp = @cad.Component::new("part")
    .with_param("module", "3.0")
    .with_param("teeth", "12")
  assert_eq(comp.parameters.get("module"), Some("3.0"))
  assert_eq(comp.parameters.get("teeth"), Some("12"))
}

///|
test "joint spec constructors" {
  let merge = @cad.JointSpec::merge_rigid(offset_mm=2.0)
  assert_true(merge.kind is @cad.MergeRigid)
  assert_true(merge.pair.offset_mm == 2.0)
  assert_true(@cad.JointSpec::fixed().kind is @cad.Fixed)
  let limit = @urdf.JointLimit::new(effort=1.0, velocity=1.0)
  let rev = @cad.JointSpec::revolute(limit)
  assert_true(rev.kind is @cad.Revolute(_))
  let cont = @cad.JointSpec::continuous(limit=Some(limit))
  assert_true(cont.kind is @cad.Continuous(Some(_)))
  let pris = @cad.JointSpec::prismatic(limit)
  assert_true(pris.kind is @cad.Prismatic(_))
}

///|
test "body from sketch extrudes on a plane" {
  let body = @cad.BodyPart::extruded_sketch_mm(
    "sketch_body",
    @step_cad.Sketch2D::rect(20.0, 10.0),
    @step_cad.Plane::XY,
    4.0,
    density=@urdf.Density::pla(),
  )
  let (x0, x1, y0, y1, z0, z1) = body.node.bounding_box()
  assert_true((x0 + 10.0).abs() < 1.0e-9)
  assert_true((x1 - 10.0).abs() < 1.0e-9)
  assert_true((y0 + 5.0).abs() < 1.0e-9)
  assert_true((y1 - 5.0).abs() < 1.0e-9)
  assert_true((z0 - 0.0).abs() < 1.0e-9)
  assert_true((z1 - 4.0).abs() < 1.0e-9)
  assert_true(body.inertial.mass > 0.0)
}

///|
test "box body matches its inertial and collision" {
  let body = @cad.BodyPart::box_mm(
    "cube",
    100.0,
    100.0,
    100.0,
    density=@urdf.Density::kg_per_m3(1000.0),
  )
  assert_true((body.inertial.mass - 1.0).abs() < 1.0e-9)
  assert_eq(body.collisions.length(), 1)
  let bbox = body.node.bounding_box()
  assert_true((bbox.0 + 50.0).abs() < 1.0e-9)
  assert_true((bbox.1 - 50.0).abs() < 1.0e-9)
}
