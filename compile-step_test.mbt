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
