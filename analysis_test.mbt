///|
test "separated bodies report clearance and no collision" {
  let base = @cad.Component::new("base").add_body(
    @cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0),
  )
  let child = @cad.Component::new("child").add_body(
    @cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0),
  )
  let comp = base.attach(
    "child_joint",
    parent_mate="origin",
    child,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(offset_mm=50.0),
  )
  assert_eq(comp.collision_checks().length(), 0)
  let reports = comp.collision_reports()
  assert_true(reports.length() > 0)
  let text = comp.collision_report_text()
  assert_true(text.contains("0 collision(s)"))
}

///|
test "overlapping bodies report a collision" {
  let base = @cad.Component::new("base").add_body(
    @cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0),
  )
  let child = @cad.Component::new("child").add_body(
    @cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0),
  )
  let comp = base.attach(
    "child_joint",
    parent_mate="origin",
    child,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(),
  )
  let warnings = comp.collision_checks()
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0].contains("COLLISION") || warnings[0].contains("collision"),
  )
  let text = comp.collision_report_text()
  assert_true(text.contains("1 collision(s)"))
}

///|
test "bodies in one link are not cross-reported" {
  let comp = @cad.Component::new("part")
    .add_body(@cad.BodyPart::box_mm("body_a", 20.0, 20.0, 20.0))
    .add_body(@cad.BodyPart::box_mm("body_b", 10.0, 10.0, 10.0))
  assert_eq(comp.collision_checks().length(), 0)
}

///|
test "placed shapes carry world poses" {
  let base = @cad.Component::new("base").add_body(
    @cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0),
  )
  let child = @cad.Component::new("child").add_body(
    @cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0),
  )
  let comp = base.attach(
    "child_joint",
    parent_mate="origin",
    child,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(offset_mm=50.0),
  )
  let shapes = comp.placed_shapes()
  assert_eq(shapes.length(), 2)
  let child_shape = shapes[1]
  assert_true(child_shape.obb.center.2 > 40.0)
}
