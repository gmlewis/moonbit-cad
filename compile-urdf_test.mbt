///|
fn revolute_limit() -> @urdf.JointLimit {
  @urdf.JointLimit::new(
    effort=10.0,
    velocity=5.0,
    lower=Some(-1.57),
    upper=Some(1.57),
  )
}

///|
fn two_link_arm() -> @cad.Component {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 100.0, 100.0, 20.0))
    .add_mate_mm_deg("shoulder", x=50.0)
  let arm = @cad.Component::new("arm")
    .add_body(@cad.BodyPart::box_mm("arm_body", 100.0, 20.0, 20.0, x_mm=50.0))
    .add_mate_mm_deg("tip", x=100.0)
  base.attach(
    "shoulder_joint",
    parent_mate="shoulder",
    arm,
    child_mate="origin",
    spec=@cad.JointSpec::revolute(revolute_limit()),
  )
}

///|
test "two link robot has two links and one joint" {
  let robot = two_link_arm().to_robot()
  assert_eq(robot.links.length(), 2)
  assert_eq(robot.joints.length(), 1)
  assert_false(robot.has_errors())
  assert_eq(robot.joints[0].name, "shoulder_joint")
  assert_eq(robot.joints[0].parent, "base")
  assert_eq(robot.joints[0].child, "arm")
  // The joint sits at the parent mate, 50 mm along +X.
  assert_true((robot.joints[0].origin.xyz.0 - 0.05).abs() < 1.0e-9)
}

///|
test "primitive visuals are emitted per body" {
  let robot = two_link_arm().to_robot()
  let base = robot.get_link("base").unwrap()
  assert_eq(base.visuals.length(), 1)
  assert_true(base.inertial is Some(_))
  assert_eq(base.collisions.length(), 1)
}

///|
test "merge rigid folds bodies into one link" {
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 40.0, 40.0, 10.0))
    .add_mate_mm_deg("top", z=5.0)
  let bracket = @cad.Component::new("bracket").add_body(
    @cad.BodyPart::box_mm("bracket_body", 20.0, 20.0, 5.0),
  )
  let comp = base.attach(
    "merge_joint",
    parent_mate="top",
    bracket,
    spec=@cad.JointSpec::merge_rigid(),
  )
  let (links, joints, _) = comp.compile_links()
  assert_eq(links.length(), 1)
  assert_eq(joints.length(), 0)
  assert_eq(links[0].bodies.length(), 2)
  let robot = comp.to_robot()
  assert_eq(robot.links.length(), 1)
  assert_eq(robot.joints.length(), 0)
  assert_false(robot.has_errors())
  let merged_mass = robot.links[0].inertial.unwrap().mass
  let expected = base.bodies[0].inertial.mass + bracket.bodies[0].inertial.mass
  assert_true((merged_mass - expected).abs() < 1.0e-12)
  // The bracket body was moved up to the parent's top mate.
  let bbox = links[0].bodies[1].node.bounding_box()
  assert_true((bbox.4 - 2.5).abs() < 1.0e-9)
  assert_true((bbox.5 - 7.5).abs() < 1.0e-9)
}

///|
test "urdf bundle contains gltf meshes and step parts" {
  let comp = two_link_arm()
  let bundle = comp.to_urdf_bundle(package_name="testbot")
  assert_eq(bundle.package_name, "testbot")
  let gltf_paths : Array[String] = []
  let step_paths : Array[String] = []
  for asset in bundle.meshes {
    if asset.rel_path.has_suffix(".gltf") {
      gltf_paths.push(asset.rel_path)
      let text = @encoding/utf8.decode(asset.bytes)
      assert_true(text.contains("\"asset\""))
      assert_true(text.contains("\"2.0\""))
    } else if asset.rel_path.has_suffix(".step") {
      step_paths.push(asset.rel_path)
      let text = @encoding/utf8.decode(asset.bytes)
      assert_true(text.contains("ISO-10303-21;"))
    }
  }
  assert_eq(gltf_paths.length(), 2)
  assert_eq(step_paths.length(), 2)
  assert_true(gltf_paths.contains("meshes/base.gltf"))
  assert_true(gltf_paths.contains("meshes/arm.gltf"))
  assert_true(step_paths.contains("parts/base.step"))
  let xml = bundle.robot.to_urdf_xml()
  assert_true(xml.contains("package://testbot/meshes/base.gltf"))
  assert_true(xml.contains("scale=\"0.001 0.001 0.001\""))
}

///|
test "link design returns bodies in local frame" {
  let comp = two_link_arm()
  assert_true(comp.link_design("base") is Some(_))
  assert_true(comp.link_design("missing") is None)
}
