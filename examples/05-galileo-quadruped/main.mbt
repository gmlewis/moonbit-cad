///|
/// 05-galileo-quadruped
///
/// The Galileo X wheeled quadruped: a 2020 T-slot chassis with printable
/// bulkheads, four 4-DOF legs, electronics on standoffs, and a complete
/// control map. Exports posed STEP, glTF, URDF, ROS 2 bundles, printable
/// parts, and a manufacturing package.

///|
fn printable_fab(
  part_number : String,
  description : String,
  material : String,
  cost_usd : Double,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="in-house",
    material~,
    process="3D print",
    unit_cost_usd=cost_usd,
  )
}

///|
/// The four V-slot corner bracket poses for a rectangular torso.
fn corners_for_brackets(
  half_len : Double,
  half_width : Double,
  body_height : Double,
) -> Array[(String, Double, Double, Double, Double, Double, Double)] {
  [
    ("corner_fl", half_len * 0.8, half_width, body_height / 2.0, 0.0, 0.0, 0.0),
    (
      "corner_fr",
      half_len * 0.8,
      -half_width,
      body_height / 2.0,
      0.0,
      0.0,
      90.0,
    ),
    (
      "corner_rl",
      -half_len * 0.8,
      half_width,
      body_height / 2.0,
      0.0,
      0.0,
      180.0,
    ),
    (
      "corner_rr",
      -half_len * 0.8,
      -half_width,
      body_height / 2.0,
      0.0,
      0.0,
      270.0,
    ),
  ]
}

///|
/// Soft lower limit matching the leg's URDF joint limit.
fn joint_soft_lower(index : Int32) -> Double {
  match index {
    0 => -0.8
    1 => -1.57
    2 => -2.7
    _ => -1000.0
  }
}

///|
/// Soft upper limit matching the leg's URDF joint limit.
fn joint_soft_upper(index : Int32) -> Double {
  match index {
    0 => 0.8
    1 => 3.14
    2 => -0.5
    _ => 1000.0
  }
}

///|
async fn main {
  let base_spec = {
    "bodyLength": @cli.opt_double(460.0, help="Chassis length in mm"),
    "bodyWidth": @cli.opt_double(220.0, help="Chassis width in mm"),
    "bodyHeight": @cli.opt_double(110.0, help="Chassis height in mm"),
    "thighLength": @cli.opt_double(210.0, help="Thigh link length in mm"),
    "calfLength": @cli.opt_double(210.0, help="Calf link length in mm"),
    "wheelDiam": @cli.opt_double(140.0, help="Wheel diameter in mm"),
    "hipAbductionDeg": @cli.opt_double(0.0, help="Hip abduction angle"),
    "hipPitchDeg": @cli.opt_double(25.0, help="Hip pitch angle"),
    "kneePitchDeg": @cli.opt_double(-50.0, help="Knee pitch angle"),
    "wheelSpinDeg": @cli.opt_double(0.0, help="Wheel spin angle"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="05-galileo-quadruped",
      description="Galileo X wheeled quadruped robot.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let threads = output.thread_rep()
  let body_len = args.double("bodyLength")
  let body_width = args.double("bodyWidth")
  let body_height = args.double("bodyHeight")
  let thigh_len = args.double("thighLength")
  let calf_len = args.double("calfLength")
  let wheel_diam = args.double("wheelDiam")
  let half_len = body_len / 2.0
  let half_width = body_width / 2.0
  let mut base = @cad.Component::new("base_link", description="Galileo chassis")
    .with_robot_name("galileo_quadruped")
    .with_param("body_len_mm", body_len.to_string())
    .with_param("body_width_mm", body_width.to_string())
    .with_param("body_height_mm", body_height.to_string())
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V, 15 A"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  // Printable front/rear bulkheads and top/bottom torso shells.
  base = base.add_body(
    @cad.BodyPart::box_mm(
      "front_bulkhead",
      body_width * 0.9,
      body_height * 0.85,
      8.0,
      x_mm=half_len,
      density=@urdf.Density::carbon_fiber(),
      color=@step_cad.Rgb::grey(),
    ).with_part(
      printable_fab(
        "TPLATE-FRONT-BULKHEAD", "Front chassis bulkhead", "carbon fiber nylon",
        6.0,
      ),
    ),
  )
  base = base.add_body(
    @cad.BodyPart::box_mm(
      "rear_bulkhead",
      body_width * 0.9,
      body_height * 0.85,
      8.0,
      x_mm=-half_len,
      density=@urdf.Density::carbon_fiber(),
      color=@step_cad.Rgb::grey(),
    ).with_part(
      printable_fab(
        "TPLATE-REAR-BULKHEAD", "Rear chassis bulkhead", "carbon fiber nylon", 6.0,
      ),
    ),
  )
  base = base.add_body(
    @cad.BodyPart::box_mm(
      "top_shell",
      body_len * 0.8,
      body_width * 0.8,
      4.0,
      z_mm=body_height / 2.0,
      density=@urdf.Density::carbon_fiber(),
      color=@step_cad.Rgb::black(),
    ).with_part(
      printable_fab(
        "TPLATE-TOP-SHELL", "Top torso shell", "carbon fiber nylon", 12.0,
      ),
    ),
  )
  base = base.add_body(
    @cad.BodyPart::box_mm(
      "battery_bay",
      body_len * 0.28,
      body_width * 0.42,
      body_height * 0.55,
      x_mm=-body_len * 0.12,
      z_mm=-body_height / 2.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(
      printable_fab("TPLATE-BATTERY-BAY", "Battery bay enclosure", "PETG", 8.0),
    ),
  )
  // 2020 V-slot chassis rails.
  let rail_specs : Array[
    (String, Double, Double, Double, Double, Double, Double),
  ] = [
    ("left_rail", 0.0, half_width, body_len, 1.0, 0.0, 0.0),
    ("right_rail", 0.0, -half_width, body_len, 1.0, 0.0, 0.0),
    ("front_rail", half_len * 0.8, 0.0, body_width, 0.0, 1.0, 0.0),
    ("rear_rail", -half_len * 0.8, 0.0, body_width, 0.0, 1.0, 0.0),
  ]
  for rail in rail_specs {
    let (rail_name, x, y, rail_length, ax, _, _) = rail
    let is_x_rail = ax != 0.0
    base = base.add_mate_mm_deg(
      "\{rail_name}_mount",
      x~,
      y~,
      z=body_height / 2.0,
      ry_deg=if is_x_rail { 90.0 } else { 0.0 },
      rx_deg=if is_x_rail { 0.0 } else { -90.0 },
    )
    let strut = @components.vslot_extrusion_strut(
      name=rail_name,
      profile=@step_profiles.VSlotProfile::vslot_2020(),
      length_mm=rail_length,
      detail~,
    )
    base = base.attach(
      "\{rail_name}_merge",
      parent_mate="\{rail_name}_mount",
      strut,
      child_mate="start",
      spec=@cad.JointSpec::merge_rigid(offset_mm=-rail_length / 2.0),
    )
  }
  // V-slot corner brackets tie the rails together.
  for corner in corners_for_brackets(half_len, half_width, body_height) {
    let (bracket_name, bx, by, bz, brx, bry, brz) = corner
    base = base.add_mate_mm_deg(
      "\{bracket_name}_mount",
      x=bx,
      y=by,
      z=bz,
      rx_deg=brx,
      ry_deg=bry,
      rz_deg=brz,
    )
    base = base.attach(
      "\{bracket_name}_merge",
      parent_mate="\{bracket_name}_mount",
      @components.vslot_corner_bracket_part(
        name=bracket_name,
        leg_mm=20.0,
        detail~,
      ),
      child_mate="mount_a",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  // Electronics: controller on standoffs, IMU, and depth camera.
  let controller = @components.pcb_board(
    name="main_pcb",
    length_mm=80.0,
    width_mm=55.0,
    connectors=["power", "can", "motor1", "motor2", "motor3", "motor4"],
    detail~,
  )
  base = base.add_mate_mm_deg("pcb_mount", z=body_height / 2.0 - 4.0)
  base = base.attach(
    "pcb_merge",
    parent_mate="pcb_mount",
    controller,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  for i in 0..<4 {
    let standoff = @components.hex_standoff(
      name="pcb_standoff_\{i}",
      length_mm=6.0,
      across_flats_mm=5.0,
      bore_diam_mm=2.7,
      detail~,
    )
    base = base.attach(
      "pcb_standoff_merge_\{i}",
      parent_mate="pcb_mount",
      standoff,
      child_mate="bottom",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let imu = @components.imu_module(name="imu", detail~)
  base = base.add_mate_mm_deg("imu_mount", z=body_height / 2.0 + 4.0)
  base = base.attach(
    "imu_merge",
    parent_mate="imu_mount",
    imu,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let camera = @components.camera_module(name="front_camera", detail~)
  base = base.add_mate_mm_deg("camera_mount", x=half_len, z=body_height * 0.35)
  base = base.attach(
    "camera_merge",
    parent_mate="camera_mount",
    camera,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let sensor_bracket = @components.sensor_mount_bracket(
    name="sensor_mount",
    detail~,
  )
  base = base.attach(
    "sensor_bracket_merge",
    parent_mate="camera_mount",
    sensor_bracket,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  // Four legs.
  let corners : Array[(String, Double, Double, Bool)] = [
    ("fl", half_len, half_width, true),
    ("fr", half_len, -half_width, false),
    ("rl", -half_len, half_width, true),
    ("rr", -half_len, -half_width, false),
  ]
  for corner in corners {
    let (prefix, x, y, is_left) = corner
    base = base.add_mate_mm_deg(
      "\{prefix}_hip_mount",
      x~,
      y~,
      axis=(1.0, 0.0, 0.0),
    )
    let leg = @components.quadruped_leg_assembly(
      prefix,
      is_left~,
      thigh_length_mm=thigh_len,
      calf_length_mm=calf_len,
      wheel_diam_mm=wheel_diam,
      detail~,
      threads?,
    )
    base = base.attach(
      "\{prefix}_hip_joint",
      parent_mate="\{prefix}_hip_mount",
      leg,
      child_mate="hip_mount",
      spec=@cad.JointSpec::revolute(
        @urdf.JointLimit::new(
          lower=Some(-0.8),
          upper=Some(0.8),
          effort=45.0,
          velocity=21.0,
        ),
        transmission_reduction=Some(6.0),
      ),
    )
  }
  // Harness: trunk routes and point-to-point CAN/power runs.
  let trunk = @cad.CableRoute::new(
    "trunk_harness",
    points=[
      (0.0, 0.0, body_height / 2.0),
      (-half_len * 0.5, 0.0, body_height / 2.0),
      (-half_len, half_width * 0.5, 0.0),
    ],
    jacket_diameter_mm=12.0,
    wire_names=["rl_can"],
    material="PVC",
    from_component="base_link",
    from_port="can",
    to_component="rl_hip_link",
    to_port="",
  )
  let _ = base.add_cable_route(trunk)
  let can_runs : Array[String] = ["fl", "fr", "rl", "rr"]
  for i in 0..<can_runs.length() {
    let prefix = can_runs[i]
    let _ = base.add_wire_run(
      @cad.WireRun::new(
        "\{prefix}_can",
        from_component="base_link",
        from_port="can",
        to_component="\{prefix}_hip_link",
        to_port="can",
        gauge_awg=24,
        length_mm=600.0,
      ),
    )
    let _ = base.add_wire_run(
      @cad.WireRun::new(
        "\{prefix}_power",
        from_component="base_link",
        from_port="power",
        to_component="\{prefix}_hip_link",
        to_port="power",
        gauge_awg=18,
        length_mm=500.0,
      ),
    )
  }
  // Control map: 16 joints, four per leg.
  let joint_names : Array[String] = [
    "hip_joint", "thigh_joint", "calf_joint", "wheel_joint",
  ]
  let actuator_suffixes : Array[String] = [
    "_hip_link", "_thigh_link", "_calf_link", "_wheel_link",
  ]
  let mut channel = 1
  for prefix in ["fl", "fr", "rl", "rr"] {
    for i in 0..<4 {
      let _ = base.add_control_binding(
        @cad.ControlBinding::new(
          "\{prefix}_\{joint_names[i]}",
          actuator="\{prefix}\{actuator_suffixes[i]}",
          channel="can0:" + channel.to_string(),
          gear_ratio=@components.planetary_reduction(12, 12, 1),
          soft_lower=Some(joint_soft_lower(i)),
          soft_upper=Some(joint_soft_upper(i)),
        ),
      )
      channel = channel + 1
    }
  }
  let deg = @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  for prefix in ["fl", "fr", "rl", "rr"] {
    positions.set("\{prefix}_hip_joint", args.double("hipAbductionDeg") * deg)
    positions.set("\{prefix}_thigh_joint", args.double("hipPitchDeg") * deg)
    positions.set("\{prefix}_calf_joint", args.double("kneePitchDeg") * deg)
    positions.set("\{prefix}_wheel_joint", args.double("wheelSpinDeg") * deg)
  }
  @common.write_output(base, output, joint_positions=positions)
}
