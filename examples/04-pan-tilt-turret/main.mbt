///|
/// 04-pan-tilt-turret
///
/// A two-axis pan/tilt camera or lidar turret: a flange base, a NEMA pan
/// motor merged into the base link, a U-bracket clevis, a QDD tilt joint, and
/// a sensor payload housing with an IMU.  A controller PCB, a pan-home limit
/// switch, wiring, and a two-joint control map make the package buildable and
/// controllable.

///|
async fn main {
  let base_spec = {
    "panDeg": @cli.opt_double(30.0, help="Pan angle in degrees"),
    "tiltDeg": @cli.opt_double(-15.0, help="Tilt angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="04-pan-tilt-turret",
      description="Two-axis gimbal pan-tilt camera/lidar turret.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let threads = output.thread_rep()
  let base = @components.flange_plate(
      name="turret_base",
      outer_diam_mm=140.0,
      center_bore_mm=30.0,
      bolt_count=6,
      detail~,
    )
    .add_mate_mm_deg("pcb_mount", x=48.0, z=3.0)
    .add_mate_mm_deg("pan_limit_mount", x=-45.0, z=3.0)
  let pan_limit = @components.limit_switch(name="pan_limit", detail~)
  let controller = @components.pcb_board(
      name="turret_controller",
      length_mm=30.0,
      width_mm=24.0,
      detail~,
      connectors=[
        "power", "motor", "can", "limit_home", "bus48", "i2c", "power3v3", "power5v",
      ],
    )
    .add_port(@cad.Port::new("bus48", @cad.PortKind::Power, spec="48 V, 8 A"))
    .add_port(
      @cad.Port::new("power3v3", @cad.PortKind::Power, spec="3.3 V, 0.1 A"),
    )
    .add_port(
      @cad.Port::new("power5v", @cad.PortKind::Power, spec="5 V, 0.5 A"),
    )
    .add_port(@cad.Port::new("i2c", @cad.PortKind::Bus, spec="I2C, 400 kHz"))
  let imu = @components.imu_module(name="imu", detail~)
  let pan_motor = @components.nema_stepper(
    name="pan_motor",
    frame_size_mm=57.0,
    body_length_mm=56.0,
    shaft_diam_mm=8.0,
    shaft_length_mm=30.0,
    max_effort_nm=2.0,
    detail~,
    threads?,
  )
  let pan_bracket = @components.u_bracket(
    name="pan_bracket",
    inner_span_mm=120.0,
    arm_length_mm=50.0,
    width_mm=45.0,
    detail~,
  )
  let tilt = @components.bldc_actuator_pod(
    name="tilt",
    housing_diam_mm=70.0,
    housing_length_mm=40.0,
    output_diam_mm=42.0,
    output_thickness_mm=6.0,
    reduction=4.0,
    lower_rad=-1.2,
    upper_rad=1.2,
    max_effort_nm=30.0,
    max_vel_rad_s=10.0,
    detail~,
    threads?,
  )
  let payload = @cad.Component::new(
      "sensor_payload",
      description="Camera and lidar payload housing",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "camera_housing",
        90.0,
        90.0,
        70.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "lens",
        50.0,
        20.0,
        z_mm=45.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::blue(),
      ),
    )
    .add_mate_mm_deg("imu_mount", x=35.0, z=35.0)
    .add_mate_mm_deg("mount", z=-35.0)
    .with_part(
      @cad.PartMeta::new(
        "SENSOR-PAYLOAD",
        description="Camera and lidar payload",
        supplier="in-house",
        material="PLA/glass",
        process="3D print",
        unit_cost_usd=90.0,
      ),
    )
  let payload = payload.attach(
    "imu_mount",
    parent_mate="imu_mount",
    imu,
    child_mate="mount",
    spec=@cad.JointSpec::fixed(),
  )
  let comp = base
    .attach(
      "pan_motor_mount",
      parent_mate="top",
      pan_motor,
      child_mate="rear_mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
    .attach_to(
      "pan_motor_rotor",
      "pan_bracket_mount",
      parent_mate="shaft_tip",
      pan_bracket,
      child_mate="base_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "pan_bracket",
      "tilt_axis_joint",
      parent_mate="pivot",
      tilt,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "tilt_rotor",
      "payload_mount",
      parent_mate="output_flange",
      payload,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(offset_mm=100.0),
    )
    .attach(
      "pan_limit_mount",
      parent_mate="pan_limit_mount",
      pan_limit,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach(
      "pcb_mount",
      parent_mate="pcb_mount",
      controller,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
    .with_robot_name("pan_tilt_turret")
  // Instrumentation wiring and control map.
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "pan_power",
      from_component="turret_controller",
      from_port="power",
      to_component="pan_motor_stator",
      to_port="power",
      gauge_awg=20,
      length_mm=400.0,
    ),
  )
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "pan_step_dir",
      from_component="turret_controller",
      from_port="motor",
      to_component="pan_motor_stator",
      to_port="step_dir",
      gauge_awg=26,
      length_mm=400.0,
    ),
  )
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "tilt_power",
      from_component="turret_controller",
      from_port="bus48",
      to_component="tilt",
      to_port="power",
      gauge_awg=18,
      length_mm=600.0,
    ),
  )
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "tilt_can",
      from_component="turret_controller",
      from_port="can",
      to_component="tilt",
      to_port="can",
      gauge_awg=24,
      length_mm=600.0,
    ),
  )
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "imu_power",
      from_component="turret_controller",
      from_port="power3v3",
      to_component="imu",
      to_port="power",
      gauge_awg=26,
      length_mm=250.0,
    ),
  )
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "imu_i2c",
      from_component="turret_controller",
      from_port="i2c",
      to_component="imu",
      to_port="i2c",
      gauge_awg=26,
      length_mm=250.0,
    ),
  )
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "limit_power",
      from_component="turret_controller",
      from_port="power5v",
      to_component="pan_limit",
      to_port="power",
      gauge_awg=26,
      length_mm=200.0,
    ),
  )
  let _ = comp.add_wire_run(
    @cad.WireRun::new(
      "limit_signal",
      from_component="pan_limit",
      from_port="signal",
      to_component="turret_controller",
      to_port="limit_home",
      gauge_awg=26,
      length_mm=200.0,
    ),
  )
  let _ = comp.add_control_binding(
    @cad.ControlBinding::new(
      "pan_motor_shaft_joint",
      actuator="pan_motor_stator",
      channel="step_dir:0",
      mcu_pins="STEP=PB0; DIR=PB1; EN=PB2",
      gear_ratio=1.0,
      soft_lower=Some(-@math.PI),
      soft_upper=Some(@math.PI),
      homing_input=Some("limit_home"),
    ),
  )
  let _ = comp.add_control_binding(
    @cad.ControlBinding::new(
      "tilt_joint",
      actuator="tilt",
      channel="can0:7",
      gear_ratio=4.0,
      soft_lower=Some(-1.2),
      soft_upper=Some(1.2),
    ),
  )
  let positions : Map[String, Double] = Map([])
  positions.set(
    "pan_motor_shaft_joint",
    args.double("panDeg") * @math.PI / 180.0,
  )
  positions.set("tilt_joint", args.double("tiltDeg") * @math.PI / 180.0)
  @common.write_output(comp, output, joint_positions=positions)
}
