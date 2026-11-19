///|
test "wbr four-bar closes across the stroke" {
  let params = WbrParams::new()
  let fbp = wbr_four_bar_params(params)
  for hip in [10.0, 20.0, 35.0, 50.0, 62.0] {
    let sol = solve_four_bar(params, hip)
    assert_true(@mechanisms.loop_closure_residual(fbp, sol) < 1.0e-9)
  }
}

///|
fn four_bar_limit() -> @urdf.JointLimit {
  @urdf.JointLimit::new(
    effort=100.0,
    velocity=100.0,
    lower=Some(-10.0),
    upper=Some(10.0),
  )
}

///|
/// A four-link URDF fixture: base (A, C) -> crank (A-B) -> calf (B-D), and a
/// guide (C-D) attached to the base. The two D mates must coincide in world
/// after forward kinematics at the solved joint angles.
test "urdf forward kinematics closes the four-bar loop" {
  let params = WbrParams::new()
  let fbp = wbr_four_bar_params(params)
  let sol = solve_four_bar(params, 35.0)
  let base = @cad.Component::new("base")
    .add_mate_mm_deg("A", x=fbp.ax, z=fbp.az, axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg("C", x=fbp.cx, z=fbp.cz, axis=(0.0, 1.0, 0.0))
  let crank = @cad.Component::new("crank").add_mate_mm_deg(
    "B",
    x=-fbp.crank_len_mm,
    axis=(0.0, 1.0, 0.0),
  )
  let calf = @cad.Component::new("calf").add_mate_mm_deg(
    "D",
    x=fbp.coupler_len_mm,
    axis=(0.0, 1.0, 0.0),
  )
  let guide = @cad.Component::new("guide").add_mate_mm_deg(
    "D",
    x=fbp.guide_len_mm,
    axis=(0.0, 1.0, 0.0),
  )
  let root = base
    .attach(
      "hip",
      parent_mate="A",
      crank,
      child_mate="origin",
      spec=@cad.JointSpec::revolute(four_bar_limit()),
    )
    .attach(
      "guide",
      parent_mate="C",
      guide,
      child_mate="origin",
      spec=@cad.JointSpec::revolute(four_bar_limit()),
    )
    .attach_to(
      "crank",
      "knee",
      parent_mate="B",
      calf,
      child_mate="origin",
      spec=@cad.JointSpec::revolute(four_bar_limit()),
    )
  let positions : Map[String, Double] = Map([])
  positions.set("hip", sol.hip_joint_rad)
  positions.set("guide", sol.guide_joint_rad)
  positions.set("knee", sol.knee_joint_rad)
  let robot = root.to_robot()
  let fk = robot.forward_kinematics(joint_positions=positions)
  let guide_world = fk.get("guide").unwrap()
  let calf_world = fk.get("calf").unwrap()
  // D on the guide is at +guide_len; D on the calf is at +coupler_len, both in
  // millimetres, so convert to metres for the URDF transform.
  let d_guide = guide_world.apply_point((fbp.guide_len_mm / 1000.0, 0.0, 0.0))
  let d_calf = calf_world.apply_point((fbp.coupler_len_mm / 1000.0, 0.0, 0.0))
  let dx = d_guide.0 - d_calf.0
  let dy = d_guide.1 - d_calf.1
  let dz = d_guide.2 - d_calf.2
  assert_true((dx * dx + dy * dy + dz * dz).sqrt() < 1.0e-6)
}
