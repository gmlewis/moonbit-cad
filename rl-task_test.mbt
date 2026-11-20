///|
fn rl_fixture() -> @cad.Component {
  let arm_limit = @urdf.JointLimit::new(
    effort=30.0,
    velocity=5.0,
    lower=Some(-1.0),
    upper=Some(1.0),
  )
  let mut comp = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 40.0, 30.0, 20.0))
    .attach(
      "arm_joint",
      parent_mate="origin",
      @cad.Component::new("arm").add_body(
        @cad.BodyPart::box_mm("arm_body", 30.0, 10.0, 10.0),
      ),
      child_mate="origin",
      spec=@cad.JointSpec::revolute(arm_limit),
    )
    .attach(
      "wheel_joint",
      parent_mate="origin",
      @cad.Component::new("wheel").add_body(
        @cad.BodyPart::box_mm("wheel_body", 20.0, 20.0, 20.0),
      ),
      child_mate="origin",
      spec=@cad.JointSpec::continuous_limit(effort=20.0, velocity=30.0),
    )
  comp = comp.add_control_binding(
    @cad.ControlBinding::new(
      "arm_joint",
      actuator="arm_drive",
      channel="can0:1",
    ),
  )
  comp = comp.add_control_binding(
    @cad.ControlBinding::new(
      "wheel_joint",
      actuator="wheel_drive",
      channel="can0:2",
    ),
  )
  comp
}

///|
fn rl_spec() -> @cad.RlTaskSpec {
  let scales : Map[String, Double] = Map([])
  scales.set("arm_joint", 0.5)
  scales.set("wheel_joint", 4.0)
  @cad.RlTaskSpec::new(
    kind=@cad.RlTaskKind::Balance,
    control_dt_s=0.01,
    episode_len_s=10.0,
    target_base_height_m=0.3,
    target_vel_x_mps=0.5,
    termination_tilt_deg=55.0,
    termination_min_z_m=0.15,
    imu_link="base",
    wheel_links=["wheel"],
    hip_joints=["arm_joint"],
    wheel_joints=["wheel_joint"],
    action_scales=scales,
    domain_rand=@cad.DomainRandSpec::new(
      push_impulse_ns=2.0,
      obs_noise_std=0.01,
    ),
  )
}

///|
test "rl task json exposes actuators, obs, action, rewards, and domain rand" {
  let positions : Map[String, Double] = Map([])
  positions.set("arm_joint", 0.25)
  let json = @json.parse(
    rl_fixture().with_rl_task(rl_spec()).rl_task_json(joint_positions=positions),
  )
  assert_eq(jstr(jfield(json, "kind")), "balance")
  assert_eq(jstr(jfield(json, "mjcf_path")), "bundle/mjcf/base.xml")
  assert_true((jnum(jfield(json, "control_dt_s")) - 0.01).abs() < 1.0e-12)
  let actuators = jarr(jfield(json, "actuators"))
  assert_eq(actuators.length(), 2)
  assert_eq(jstr(jfield(actuators[0], "joint")), "arm_joint")
  assert_eq(jstr(jfield(actuators[0], "kind")), "position")
  assert_true((jnum(jfield(actuators[0], "kp")) - 70.0).abs() < 1.0e-9)
  assert_eq(jstr(jfield(actuators[1], "joint")), "wheel_joint")
  assert_eq(jstr(jfield(actuators[1], "kind")), "velocity")
  assert_true((jnum(jfield(actuators[1], "kv")) - 2.0).abs() < 1.0e-9)
  assert_true(
    (jnum(jfield(jfield(json, "home_qpos"), "arm_joint")) - 0.25).abs() <
    1.0e-12,
  )
  let obs = jfield(json, "obs_spec")
  assert_true((jnum(jfield(obs, "dim")) - 16.0).abs() < 1.0e-9)
  let action = jfield(json, "action_spec")
  assert_eq(jarr(jfield(action, "joints")).length(), 2)
  assert_true(
    (jnum(jfield(jfield(json, "rewards"), "forward_vel")) - 1.0).abs() < 1.0e-9,
  )
  assert_eq(
    jarr(jfield(jfield(json, "domain_rand"), "mass_scale_range")).length(),
    2,
  )
}

///|
test "rl task validation accepts a consistent spec" {
  let warnings = rl_fixture().with_rl_task(rl_spec()).assembly_checks()
  let rl_warnings = warnings.filter(fn(warning) { warning.contains("rl task") })
  assert_eq(rl_warnings.length(), 0)
}

///|
test "rl task validation rejects invalid timing, actuators, and names" {
  let scales : Map[String, Double] = Map([])
  scales.set("ghost_scale", 1.0)
  let bad = @cad.RlTaskSpec::new(
    control_dt_s=0.0,
    imu_link="ghost_imu",
    hip_joints=["ghost_joint"],
    action_scales=scales,
  )
  let warnings = rl_fixture().with_rl_task(bad).assembly_checks()
  let has = fn(needle : String) -> Bool {
    warnings.fold(init=false, fn(acc, warning) {
      acc || warning.contains(needle)
    })
  }
  assert_true(has("control_dt_s must be > 0"))
  assert_true(has("hip joint 'ghost_joint' is not a commandable joint"))
  assert_true(has("action scale refers to unknown joint 'ghost_scale'"))
  assert_true(has("imu link 'ghost_imu' is not a robot link"))

  let no_bindings = @cad.Component::new("bare")
    .add_body(@cad.BodyPart::box_mm("body", 10.0, 10.0, 10.0))
    .with_rl_task(@cad.RlTaskSpec::new())
  let warnings = no_bindings.assembly_checks()
  let has_no_actuators = warnings.fold(init=false, fn(acc, warning) {
    acc || warning.contains("no commandable actuators")
  })
  assert_true(has_no_actuators)
}

///|
test "build package emits rl_task.json only when a task is attached" {
  let comp = rl_fixture().with_rl_task(rl_spec())
  let files = comp.build_package_files()
  let mut found = ""
  for file in files {
    if file.path == "rl_task.json" {
      found = file.content
    }
  }
  assert_true(found != "")
  let json = @json.parse(found)
  assert_eq(jstr(jfield(json, "kind")), "balance")

  let plain = rl_fixture().build_package_files()
  let mut named = false
  for file in plain {
    if file.path == "rl_task.json" {
      named = true
    }
  }
  assert_false(named)
}
