///|
/// Typed RL task metadata: the observation/action/reward contract a policy
/// trainer needs, exported as `rl_task.json` next to the MJCF model.

///|
/// The training objective a task targets.
#derive(Debug, Eq)
pub(all) enum RlTaskKind {
  Balance
  WheeledLocomotion
  QuadrupedWalk
  JumpAndLevel
  Custom(String)
}

///|
pub fn RlTaskKind::to_string(self : RlTaskKind) -> String {
  match self {
    Balance => "balance"
    WheeledLocomotion => "wheeled_locomotion"
    QuadrupedWalk => "quadruped_walk"
    JumpAndLevel => "jump_and_level"
    Custom(name) => name
  }
}

///|
/// Domain randomization ranges and disturbances applied on reset.
#derive(Debug, Eq)
pub(all) struct DomainRandSpec {
  mass_scale_range : (Double, Double)
  friction_range : (Double, Double)
  kp_scale_range : (Double, Double)
  push_impulse_ns : Double
  obs_noise_std : Double
}

///|
pub fn DomainRandSpec::new(
  mass_scale_range~ : (Double, Double) = (0.9, 1.1),
  friction_range~ : (Double, Double) = (0.7, 1.3),
  kp_scale_range~ : (Double, Double) = (0.9, 1.1),
  push_impulse_ns~ : Double = 0.0,
  obs_noise_std~ : Double = 0.0,
) -> DomainRandSpec {
  {
    mass_scale_range,
    friction_range,
    kp_scale_range,
    push_impulse_ns,
    obs_noise_std,
  }
}

///|
/// Weighted reward terms. Negative weights penalize their quantity.
#derive(Debug, Eq)
pub(all) struct RewardWeights {
  forward_vel : Double
  target_height : Double
  upright : Double
  energy : Double
  smoothness : Double
  alive : Double
}

///|
pub fn RewardWeights::new(
  forward_vel~ : Double = 1.0,
  target_height~ : Double = 1.0,
  upright~ : Double = 1.0,
  energy~ : Double = -0.01,
  smoothness~ : Double = -0.01,
  alive~ : Double = 0.5,
) -> RewardWeights {
  { forward_vel, target_height, upright, energy, smoothness, alive, }
}

///|
/// One robot's RL contract.
#derive(Debug, Eq)
pub(all) struct RlTaskSpec {
  kind : RlTaskKind
  control_dt_s : Double
  episode_len_s : Double
  target_base_height_m : Double
  target_vel_x_mps : Double
  termination_tilt_deg : Double
  termination_min_z_m : Double
  imu_link : String
  wheel_links : Array[String]
  hip_joints : Array[String]
  wheel_joints : Array[String]
  action_scales : Map[String, Double]
  rewards : RewardWeights
  domain_rand : DomainRandSpec
}

///|
pub fn RlTaskSpec::new(
  kind~ : RlTaskKind = WheeledLocomotion,
  control_dt_s~ : Double = 0.01,
  episode_len_s~ : Double = 10.0,
  target_base_height_m~ : Double = 0.30,
  target_vel_x_mps~ : Double = 0.5,
  termination_tilt_deg~ : Double = 55.0,
  termination_min_z_m~ : Double = 0.15,
  imu_link~ : String = "",
  wheel_links~ : Array[String] = [],
  hip_joints~ : Array[String] = [],
  wheel_joints~ : Array[String] = [],
  action_scales~ : Map[String, Double] = Map([]),
  rewards~ : RewardWeights = RewardWeights::new(),
  domain_rand~ : DomainRandSpec = DomainRandSpec::new(),
) -> RlTaskSpec {
  {
    kind,
    control_dt_s,
    episode_len_s,
    target_base_height_m,
    target_vel_x_mps,
    termination_tilt_deg,
    termination_min_z_m,
    imu_link,
    wheel_links,
    hip_joints,
    wheel_joints,
    action_scales,
    rewards,
    domain_rand,
  }
}

///|
pub fn Component::with_rl_task(
  self : Component,
  spec : RlTaskSpec,
) -> Component {
  { ..self, rl_task: Some(spec), }
}

///|
fn rl_reward_json(weights : RewardWeights) -> @json.Json {
  inspect_object([
    ("forward_vel", @json.Json::number(weights.forward_vel)),
    ("target_height", @json.Json::number(weights.target_height)),
    ("upright", @json.Json::number(weights.upright)),
    ("energy", @json.Json::number(weights.energy)),
    ("smoothness", @json.Json::number(weights.smoothness)),
    ("alive", @json.Json::number(weights.alive)),
  ])
}

///|
fn rl_domain_rand_json(spec : DomainRandSpec) -> @json.Json {
  inspect_object([
    (
      "mass_scale_range",
      @json.Json::array([
        @json.Json::number(spec.mass_scale_range.0),
        @json.Json::number(spec.mass_scale_range.1),
      ]),
    ),
    (
      "friction_range",
      @json.Json::array([
        @json.Json::number(spec.friction_range.0),
        @json.Json::number(spec.friction_range.1),
      ]),
    ),
    (
      "kp_scale_range",
      @json.Json::array([
        @json.Json::number(spec.kp_scale_range.0),
        @json.Json::number(spec.kp_scale_range.1),
      ]),
    ),
    ("push_impulse_ns", @json.Json::number(spec.push_impulse_ns)),
    ("obs_noise_std", @json.Json::number(spec.obs_noise_std)),
  ])
}

///|
/// One actuator record: the joint, the MJCF actuator kind, gains, and the
/// control range. Mirrors the options written into `bundle/mjcf/*.xml`.
fn rl_actuator_json(
  robot : @urdf.Robot,
  binding : ControlBinding,
  spec : RlTaskSpec,
) -> @json.Json? {
  match robot.get_joint(binding.joint) {
    None => None
    Some(joint) => {
      let (effort, velocity, lower, upper) = match joint.limit {
        Some(limit) => (limit.effort, limit.velocity, limit.lower, limit.upper)
        None => (0.0, 0.0, None, None)
      }
      let (kind, kp, kv, ctrl_min, ctrl_max) = match joint.joint_type {
        Continuous => {
          let vmax = if velocity > 0.0 { velocity } else { 10.0 }
          ("velocity", 0.0, 2.0, -vmax, vmax)
        }
        Revolute | Prismatic => {
          let lo = match lower {
            Some(value) => value
            None => -3.141592653589793
          }
          let hi = match upper {
            Some(value) => value
            None => 3.141592653589793
          }
          ("position", 70.0, 3.0, lo, hi)
        }
        _ => ("motor", 0.0, 0.0, -effort, effort)
      }
      let entries : Array[(String, @json.Json)] = [
        ("joint", @json.Json::string(joint.name)),
        (
          "name",
          @json.Json::string(
            if binding.actuator == "" {
              joint.name + "_" + kind
            } else {
              binding.actuator
            },
          ),
        ),
        ("kind", @json.Json::string(kind)),
        ("ctrl_min", @json.Json::number(ctrl_min)),
        ("ctrl_max", @json.Json::number(ctrl_max)),
        (
          "scale",
          @json.Json::number(spec.action_scales.get(joint.name).unwrap_or(1.0)),
        ),
      ]
      if kp > 0.0 {
        entries.push(("kp", @json.Json::number(kp)))
      }
      if kv > 0.0 {
        entries.push(("kv", @json.Json::number(kv)))
      }
      if effort > 0.0 {
        entries.push(("forcerange", @json.Json::number(effort)))
      }
      Some(inspect_object(entries))
    }
  }
}

///|
fn rl_range_valid(range : (Double, Double)) -> Bool {
  range.0 >= 0.0 && range.0 <= range.1
}

///|
/// Validation for an attached RL spec. Empty means consistent.
pub fn Component::rl_task_checks(self : Component) -> Array[String] {
  let warnings : Array[String] = []
  let spec = match self.rl_task {
    Some(spec) => spec
    None => return warnings
  }
  let robot = self.to_robot()
  let bindings = self.control_bindings()
  let bound : Array[String] = bindings.map(fn(binding) { binding.joint })
  if spec.control_dt_s <= 0.0 {
    warnings.push(self.name + ": rl task control_dt_s must be > 0")
  }
  if spec.episode_len_s <= 0.0 {
    warnings.push(self.name + ": rl task episode_len_s must be > 0")
  }
  if spec.termination_tilt_deg <= 0.0 {
    warnings.push(self.name + ": rl task termination tilt must be > 0")
  }
  if spec.termination_min_z_m < 0.0 {
    warnings.push(self.name + ": rl task termination min z must be >= 0")
  }
  if bindings.length() == 0 {
    warnings.push(
      self.name +
      ": rl task has no commandable actuators (add control bindings)",
    )
  }
  for name in spec.hip_joints {
    if !bound.contains(name) {
      warnings.push(
        self.name +
        ": rl task hip joint '" +
        name +
        "' is not a commandable joint",
      )
    }
  }
  for name in spec.wheel_joints {
    if !bound.contains(name) {
      warnings.push(
        self.name +
        ": rl task wheel joint '" +
        name +
        "' is not a commandable joint",
      )
    }
  }
  for name, _scale in spec.action_scales {
    if !bound.contains(name) {
      warnings.push(
        self.name +
        ": rl task action scale refers to unknown joint '" +
        name +
        "'",
      )
    }
  }
  if spec.imu_link != "" && robot.get_link(spec.imu_link) is None {
    warnings.push(
      self.name +
      ": rl task imu link '" +
      spec.imu_link +
      "' is not a robot link",
    )
  }
  if !rl_range_valid(spec.domain_rand.mass_scale_range) ||
    spec.domain_rand.mass_scale_range.0 <= 0.0 {
    warnings.push(self.name + ": rl task mass scale range is invalid")
  }
  if !rl_range_valid(spec.domain_rand.friction_range) {
    warnings.push(self.name + ": rl task friction range is invalid")
  }
  if !rl_range_valid(spec.domain_rand.kp_scale_range) ||
    spec.domain_rand.kp_scale_range.0 <= 0.0 {
    warnings.push(self.name + ": rl task kp scale range is invalid")
  }
  if spec.domain_rand.push_impulse_ns < 0.0 {
    warnings.push(self.name + ": rl task push impulse must be >= 0")
  }
  if spec.domain_rand.obs_noise_std < 0.0 {
    warnings.push(self.name + ": rl task observation noise must be >= 0")
  }
  warnings
}

///|
/// The RL task contract as a JSON document. `"null"` when no task is attached.
pub fn Component::rl_task_json(
  self : Component,
  joint_positions~ : Map[String, Double] = Map([]),
) -> String {
  let spec = match self.rl_task {
    Some(spec) => spec
    None => return "null"
  }
  let robot = self.to_robot()
  let bindings = self.control_bindings()
  let actuators : Array[@json.Json] = []
  let action_joints : Array[@json.Json] = []
  for binding in bindings {
    match rl_actuator_json(robot, binding, spec) {
      Some(entry) => {
        actuators.push(entry)
        action_joints.push(entry)
      }
      None => ()
    }
  }
  let count = actuators.length()
  let obs_dim = 10 + 3 * count
  let home : Map[String, @json.Json] = Map([])
  for name, value in joint_positions {
    home.set(name, @json.Json::number(value))
  }
  inspect_object([
    ("name", @json.Json::string(self.display_name())),
    ("kind", @json.Json::string(spec.kind.to_string())),
    (
      "mjcf_path",
      @json.Json::string("bundle/mjcf/" + self.display_name() + ".xml"),
    ),
    ("control_dt_s", @json.Json::number(spec.control_dt_s)),
    ("episode_len_s", @json.Json::number(spec.episode_len_s)),
    ("target_base_height_m", @json.Json::number(spec.target_base_height_m)),
    ("target_vel_x_mps", @json.Json::number(spec.target_vel_x_mps)),
    (
      "termination",
      inspect_object([
        ("tilt_deg", @json.Json::number(spec.termination_tilt_deg)),
        ("min_z_m", @json.Json::number(spec.termination_min_z_m)),
      ]),
    ),
    ("imu_link", @json.Json::string(spec.imu_link)),
    (
      "wheel_links",
      @json.Json::array(
        spec.wheel_links.map(fn(name) { @json.Json::string(name) }),
      ),
    ),
    (
      "hip_joints",
      @json.Json::array(
        spec.hip_joints.map(fn(name) { @json.Json::string(name) }),
      ),
    ),
    (
      "wheel_joints",
      @json.Json::array(
        spec.wheel_joints.map(fn(name) { @json.Json::string(name) }),
      ),
    ),
    ("home_qpos", @json.Json::object(home)),
    ("actuators", @json.Json::array(actuators)),
    (
      "obs_spec",
      inspect_object([
        ("base_height", @json.Json::number(1.0)),
        ("projected_gravity", @json.Json::number(3.0)),
        ("base_ang_vel", @json.Json::number(3.0)),
        ("base_lin_vel", @json.Json::number(3.0)),
        ("joint_pos", @json.Json::number(count.to_double())),
        ("joint_vel", @json.Json::number(count.to_double())),
        ("prev_action", @json.Json::number(count.to_double())),
        ("dim", @json.Json::number(obs_dim.to_double())),
      ]),
    ),
    (
      "action_spec",
      inspect_object([
        ("dim", @json.Json::number(count.to_double())),
        ("joints", @json.Json::array(action_joints)),
      ]),
    ),
    ("rewards", rl_reward_json(spec.rewards)),
    ("domain_rand", rl_domain_rand_json(spec.domain_rand)),
  ]).stringify()
}
