///|
fn elbow_limit() -> @urdf.JointLimit {
  @urdf.JointLimit::new(
    effort=10.0,
    velocity=5.0,
    lower=Some(-3.14),
    upper=Some(3.14),
  )
}

///|
/// A base plus one 100 mm link whose local frame starts at the revolute joint
/// at 50 mm along +X.
fn arm_assembly() -> @cad.Component {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0))
    .add_mate_mm_deg("shoulder", x=50.0)
  let link = @cad.Component::new("link1")
    .add_body(@cad.BodyPart::box_mm("link1_body", 100.0, 20.0, 20.0, x_mm=50.0))
    .add_mate_mm_deg("tip", x=100.0)
  base.attach(
    "elbow",
    parent_mate="shoulder",
    link,
    child_mate="origin",
    spec=@cad.JointSpec::revolute(elbow_limit()),
  )
}

///|
fn find_node_box(
  design : @step_cad.Design,
  name : String,
) -> (Double, Double, Double, Double, Double, Double)? {
  for node in design.nodes {
    if node.name == name {
      return Some(node.bounding_box())
    }
  }
  None
}

///|
test "posed design at zero joint angle extends along x" {
  let design = arm_assembly().to_design()
  let box = find_node_box(design, "link1_link1_body").unwrap()
  assert_true((box.0 - 50.0).abs() < 1.0e-6)
  assert_true((box.1 - 150.0).abs() < 1.0e-6)
  assert_true((box.2 + 10.0).abs() < 1.0e-6)
  assert_true((box.3 - 10.0).abs() < 1.0e-6)
}

///|
test "posed design rotates the link by ninety degrees" {
  let positions : Map[String, Double] = Map([])
  positions.set("elbow", @math.PI / 2.0)
  let design = arm_assembly().to_design(joint_positions=positions)
  let box = find_node_box(design, "link1_link1_body").unwrap()
  // The link rotates about the joint at x = 50 mm: it now spans +Y.
  assert_true((box.0 - 40.0).abs() < 1.0e-6)
  assert_true((box.1 - 60.0).abs() < 1.0e-6)
  assert_true((box.2 - 0.0).abs() < 1.0e-6)
  assert_true((box.3 - 100.0).abs() < 1.0e-6)
}

///|
test "step exports contain iso markers" {
  let comp = arm_assembly()
  let flat = comp.to_step_file()
  assert_true(flat.contains("ISO-10303-21;"))
  assert_true(flat.contains("END-ISO-10303-21;"))
  let assembly = comp.to_assembly_step()
  assert_true(assembly.contains("ISO-10303-21;"))
  assert_true(assembly.contains("END-ISO-10303-21;"))
}

///|
test "gltf export is a 2.0 asset" {
  let gltf = arm_assembly().to_gltf()
  assert_true(gltf.contains("\"asset\""))
  assert_true(gltf.contains("\"2.0\""))
}

///|
test "documentation lists sorted parameters" {
  let comp = @cad.Component::new("part", description="a part")
    .with_param("zeta", "1")
    .with_param("alpha", "2")
  let doc = comp.format_documentation()
  assert_true(doc.contains("part"))
  assert_true(doc.contains("a part"))
  assert_true(doc.contains("alpha=2"))
  let alpha_pos = doc.find("alpha=2").unwrap()
  let zeta_pos = doc.find("zeta=1").unwrap()
  assert_true(alpha_pos < zeta_pos)
}

///|
fn explode_near(a : Double, b : Double) -> Bool {
  (a - b).abs() <= 1.0e-6
}

///|
fn explode_box_matches(
  a : (Double, Double, Double, Double, Double, Double),
  b : (Double, Double, Double, Double, Double, Double),
) -> Bool {
  explode_near(a.0, b.0) &&
  explode_near(a.1, b.1) &&
  explode_near(a.2, b.2) &&
  explode_near(a.3, b.3) &&
  explode_near(a.4, b.4) &&
  explode_near(a.5, b.5)
}

///|
/// A three-level tree whose bracket explodes 10 mm along the base mate's +Z
/// axis and whose wheel uses the supplied spec.
fn explodable_assembly(wheel_spec : @cad.ExplodeSpec) -> @cad.Component {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 10.0, 10.0, 10.0))
    .add_mate_mm_deg("top", z=10.0, axis=(0.0, 0.0, 1.0))
  let bracket = @cad.Component::new("bracket")
    .add_body(@cad.BodyPart::box_mm("bracket_body", 10.0, 10.0, 10.0))
    .add_mate_mm_deg("hub", z=10.0, axis=(0.0, 0.0, 1.0))
  let wheel = @cad.Component::new("wheel").add_body(
    @cad.BodyPart::box_mm("wheel_body", 6.0, 6.0, 6.0),
  )
  base
  .attach(
    "bracket_joint",
    parent_mate="top",
    bracket,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(),
    explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=10.0)),
  )
  .attach_to(
    "bracket",
    "wheel_joint",
    parent_mate="hub",
    wheel,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(),
    explode=Some(wheel_spec),
  )
}

///|
fn rotated_explode_assembly(spec : @cad.ExplodeSpec) -> @cad.Component {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 10.0, 10.0, 10.0))
    .add_mate_mm_deg("pivot", x=50.0, rz_deg=-90.0, axis=(1.0, 0.0, 0.0))
  let child = @cad.Component::new("child").add_body(
    @cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0),
  )
  base.attach(
    "child_joint",
    parent_mate="pivot",
    child,
    child_mate="origin",
    spec=@cad.JointSpec::fixed(),
    explode=Some(spec),
  )
}

///|
test "along_mate uses the parent-frame axis on a rotated mate" {
  let comp = rotated_explode_assembly(
    @cad.ExplodeSpec::along_mate(distance_mm=10.0),
  )
  let a0 = find_node_box(comp.to_design(), "child_child_body").unwrap()
  let a1 = find_node_box(comp.to_exploded_design(), "child_child_body").unwrap()
  assert_true(explode_near(a1.0 - a0.0, 10.0))
  assert_true(explode_near(a1.2 - a0.2, 0.0))
  assert_true(explode_near(a1.4 - a0.4, 0.0))
}

///|
test "along_mate_local rotates the axis by the mate placement" {
  let comp = rotated_explode_assembly(
    @cad.ExplodeSpec::along_mate_local(distance_mm=10.0),
  )
  let a0 = find_node_box(comp.to_design(), "child_child_body").unwrap()
  let a1 = find_node_box(comp.to_exploded_design(), "child_child_body").unwrap()
  // rz = -90 maps the mate-local +X axis to world -Y.
  assert_true(explode_near(a1.2 - a0.2, -10.0))
  assert_true(explode_near(a1.0 - a0.0, 0.0))
  assert_true(explode_near(a1.4 - a0.4, 0.0))
}

///|
test "exploded design at scale zero matches assembled bounding boxes" {
  let comp = explodable_assembly(@cad.ExplodeSpec::along_mate(distance_mm=20.0))
  let assembled = comp.to_design()
  let exploded = comp.to_exploded_design(scale=0.0)
  for name in ["base_base_body", "bracket_bracket_body", "wheel_wheel_body"] {
    let a = find_node_box(assembled, name).unwrap()
    let b = find_node_box(exploded, name).unwrap()
    assert_true(explode_box_matches(a, b))
  }
}

///|
test "exploded children inherit parent displacements" {
  let comp = explodable_assembly(@cad.ExplodeSpec::along_mate(distance_mm=20.0))
  let assembled = comp.to_design()
  let exploded = comp.to_exploded_design()
  let base0 = find_node_box(assembled, "base_base_body").unwrap()
  let bracket0 = find_node_box(assembled, "bracket_bracket_body").unwrap()
  let wheel0 = find_node_box(assembled, "wheel_wheel_body").unwrap()
  let base1 = find_node_box(exploded, "base_base_body").unwrap()
  let bracket1 = find_node_box(exploded, "bracket_bracket_body").unwrap()
  let wheel1 = find_node_box(exploded, "wheel_wheel_body").unwrap()
  // The root does not move.
  assert_true(explode_box_matches(base0, base1))
  // The bracket moves 10 mm along +Z.
  assert_true(explode_near(bracket1.4 - bracket0.4, 10.0))
  assert_true(explode_near(bracket1.5 - bracket0.5, 10.0))
  assert_true(explode_near(bracket1.0, bracket0.0))
  assert_true(explode_near(bracket1.2, bracket0.2))
  // The wheel inherits the bracket's 10 mm and adds its own 20 mm.
  assert_true(explode_near(wheel1.4 - wheel0.4, 30.0))
  assert_true(explode_near(wheel1.5 - wheel0.5, 30.0))
  assert_true(explode_near(wheel1.0, wheel0.0))
  assert_true(explode_near(wheel1.2, wheel0.2))
}

///|
test "exploded scale doubles every displacement" {
  let comp = explodable_assembly(@cad.ExplodeSpec::along_mate(distance_mm=20.0))
  let assembled = comp.to_design()
  let exploded = comp.to_exploded_design(scale=2.0)
  let bracket0 = find_node_box(assembled, "bracket_bracket_body").unwrap()
  let wheel0 = find_node_box(assembled, "wheel_wheel_body").unwrap()
  let bracket1 = find_node_box(exploded, "bracket_bracket_body").unwrap()
  let wheel1 = find_node_box(exploded, "wheel_wheel_body").unwrap()
  assert_true(explode_near(bracket1.5 - bracket0.5, 20.0))
  assert_true(explode_near(wheel1.5 - wheel0.5, 60.0))
}

///|
test "explicit explode offsets are expressed in the parent frame" {
  let comp = explodable_assembly(
    @cad.ExplodeSpec::offset_mm(dx=5.0, dy=0.0, dz=20.0),
  )
  let assembled = comp.to_design()
  let exploded = comp.to_exploded_design()
  let bracket0 = find_node_box(assembled, "bracket_bracket_body").unwrap()
  let wheel0 = find_node_box(assembled, "wheel_wheel_body").unwrap()
  let bracket1 = find_node_box(exploded, "bracket_bracket_body").unwrap()
  let wheel1 = find_node_box(exploded, "wheel_wheel_body").unwrap()
  assert_true(explode_near(bracket1.5 - bracket0.5, 10.0))
  // The wheel inherits +10 Z and adds its own (+5 X, +20 Z).
  assert_true(explode_near(wheel1.0 - wheel0.0, 5.0))
  assert_true(explode_near(wheel1.5 - wheel0.5, 30.0))
}

///|
test "explode order scales the separation distance" {
  let comp = explodable_assembly(
    @cad.ExplodeSpec::along_mate(distance_mm=10.0, order=3),
  )
  let assembled = comp.to_design()
  let exploded = comp.to_exploded_design()
  let wheel0 = find_node_box(assembled, "wheel_wheel_body").unwrap()
  let wheel1 = find_node_box(exploded, "wheel_wheel_body").unwrap()
  // bracket 10 mm + wheel 10 mm * order 3 = 40 mm.
  assert_true(explode_near(wheel1.5 - wheel0.5, 40.0))
}

///|
test "exploded view applies role colors but keeps explicit colors" {
  let comp = @cad.Component::new("color_test")
    .add_body(@cad.BodyPart::box_mm("plain_body", 5.0, 5.0, 5.0))
    .add_body(
      @cad.BodyPart::box_mm(
        "red_body",
        5.0,
        5.0,
        5.0,
        x_mm=10.0,
        color=@step_cad.Rgb::red(),
      ),
    )
  let design = comp.to_exploded_design()
  let mut plain : (Double, Double, Double) = (0.0, 0.0, 0.0)
  let mut red : (Double, Double, Double) = (0.0, 0.0, 0.0)
  for node in design.nodes {
    if node.name == "color_test_plain_body" {
      plain = (node.color.r, node.color.g, node.color.b)
    }
    if node.name == "color_test_red_body" {
      red = (node.color.r, node.color.g, node.color.b)
    }
  }
  // The default grey is replaced by a role color.
  assert_false(
    explode_near(plain.0, 0.2) &&
    explode_near(plain.1, 0.2) &&
    explode_near(plain.2, 0.2),
  )
  // The explicit red color is preserved.
  assert_true(explode_near(red.0, 0.8))
  assert_true(explode_near(red.1, 0.0))
  assert_true(explode_near(red.2, 0.0))
}

///|
test "trace lines are opt-in and add assembly guides" {
  let comp = explodable_assembly(@cad.ExplodeSpec::along_mate(distance_mm=20.0))
  let plain = comp.to_exploded_design()
  let traced = comp.to_exploded_design(trace_lines=true)
  assert_eq(plain.nodes.length(), 3)
  assert_true(traced.nodes.length() > plain.nodes.length())
  let mut trace_count = 0
  for node in traced.nodes {
    if node.name.has_prefix("explode_trace") {
      trace_count = trace_count + 1
    }
  }
  assert_true(trace_count > 0)
  // With no displacement there is nothing to trace.
  let still = comp.to_exploded_design(scale=0.0, trace_lines=true)
  assert_eq(still.nodes.length(), 3)
}

///|
test "has_explode_spec detects first-class explosion metadata" {
  let comp = explodable_assembly(@cad.ExplodeSpec::along_mate(distance_mm=20.0))
  assert_true(comp.has_explode_spec())
  assert_false(@cad.Component::new("plain").has_explode_spec())
}
