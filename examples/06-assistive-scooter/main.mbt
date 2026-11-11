///|
/// 06-assistive-scooter
///
/// A rider-parameterized assistive mobility scooter: a T-slot chassis with a
/// printable deck, battery bay, and seat mounts; a steerable suspension front
/// fork; and two driven rear hub motors.

///|
fn scooter_fab(
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
async fn main {
  let base_spec = {
    "wheelbase": @cli.opt_double(680.0, help="Wheelbase in mm"),
    "trackWidth": @cli.opt_double(480.0, help="Track width in mm"),
    "seatHeight": @cli.opt_double(420.0, help="Seat height in mm"),
    "rearWheelDiam": @cli.opt_double(250.0, help="Rear wheel diameter in mm"),
    "frontWheelDiam": @cli.opt_double(180.0, help="Front wheel diameter in mm"),
    "steerDeg": @cli.opt_double(0.0, help="Steering angle in degrees"),
    "leftWheelDeg": @cli.opt_double(0.0, help="Left wheel angle in degrees"),
    "rightWheelDeg": @cli.opt_double(0.0, help="Right wheel angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="06-assistive-scooter",
      description="Lightweight rider-parameterized assistive mobility scooter.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let threads = output.thread_rep()
  let wheelbase = args.double("wheelbase")
  let track_width = args.double("trackWidth")
  let seat_height = args.double("seatHeight")
  let rear_wheel_diam = args.double("rearWheelDiam")
  let front_wheel_diam = args.double("frontWheelDiam")
  let rear_wheel_r = rear_wheel_diam / 2.0
  let deck_top = 90.0
  let half_track = track_width / 2.0
  let mut chassis = @cad.Component::new(
      "chassis_link",
      description="Assistive scooter chassis",
    )
    .with_robot_name("assistive_scooter")
    .with_param("wheelbase_mm", wheelbase.to_string())
    .with_param("track_width_mm", track_width.to_string())
    .with_param("seat_height_mm", seat_height.to_string())
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="36 V, 25 A"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  // Printable deck, battery bay, fenders, and seat/armrest mounts.
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "deck",
      wheelbase * 0.6,
      track_width * 0.55,
      deck_top,
      z_mm=deck_top / 2.0,
      density=@urdf.Density::aluminum_6061(),
      color=@step_cad.Rgb::grey(),
    ).with_part(scooter_fab("SCOOTER-DECK", "Scooter foot deck", "PETG", 20.0)),
  )
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "battery_bay",
      wheelbase * 0.35,
      track_width * 0.45,
      120.0,
      x_mm=-wheelbase * 0.1,
      z_mm=deck_top + 60.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(
      scooter_fab("SCOOTER-BATTERY-BAY", "Battery bay enclosure", "PETG", 18.0),
    ),
  )
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "left_fender",
      rear_wheel_diam * 1.1,
      track_width * 0.12,
      6.0,
      x_mm=-wheelbase / 2.0,
      y_mm=half_track,
      z_mm=rear_wheel_r * 2.0 + 5.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(
      scooter_fab("SCOOTER-LEFT-FENDER", "Left rear fender", "PETG", 4.0),
    ),
  )
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "right_fender",
      rear_wheel_diam * 1.1,
      track_width * 0.12,
      6.0,
      x_mm=-wheelbase / 2.0,
      y_mm=-half_track,
      z_mm=rear_wheel_r * 2.0 + 5.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(
      scooter_fab("SCOOTER-RIGHT-FENDER", "Right rear fender", "PETG", 4.0),
    ),
  )
  let drop_mounts : Array[(String, Double, String)] = [
    ("left_drop_mount", half_track + 30.0, "SCOOTER-LEFT-DROP-MOUNT"),
    ("right_drop_mount", -(half_track + 30.0), "SCOOTER-RIGHT-DROP-MOUNT"),
  ]
  for drop in drop_mounts {
    let (drop_name, y, drop_part) = drop
    chassis = chassis.add_body(
      @cad.BodyPart::box_mm(
        drop_name,
        70.0,
        14.0,
        rear_wheel_r * 0.75,
        x_mm=-wheelbase / 2.0,
        y_mm=y,
        z_mm=rear_wheel_r * 0.5,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(
        scooter_fab(drop_part, "Rear axle drop plate", "6061-T6", 5.0),
      ),
    )
  }
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "seat_mount",
      track_width * 0.5,
      track_width * 0.5,
      10.0,
      x_mm=-wheelbase * 0.15,
      z_mm=seat_height - 5.0,
      density=@urdf.Density::aluminum_6061(),
      color=@step_cad.Rgb::grey(),
    ).with_part(
      scooter_fab("SCOOTER-SEAT-MOUNT", "Seat mount plate", "PETG", 8.0),
    ),
  )
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "joystick_pod",
      70.0,
      60.0,
      40.0,
      x_mm=wheelbase * 0.28,
      z_mm=seat_height * 0.8,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(
      scooter_fab(
        "SCOOTER-JOYSTICK-POD", "Joystick controller pod", "PETG", 6.0,
      ),
    ),
  )
  // 2040 side rails and 2020 cross rails.
  chassis = chassis.add_mate_mm_deg(
    "left_rail_mount",
    y=half_track,
    z=deck_top * 0.5,
    ry_deg=90.0,
  )
  chassis = chassis.add_mate_mm_deg(
    "right_rail_mount",
    y=-half_track,
    z=deck_top * 0.5,
    ry_deg=90.0,
  )
  for
    rail in [
      ("left_rail", "left_rail_mount"),
      ("right_rail", "right_rail_mount"),
    ] {
    let strut = @components.tslot_extrusion_strut(
      name=rail.0,
      profile=@step_profiles.TSlotProfile::generic_2040(),
      length_mm=wheelbase,
      detail~,
    )
    chassis = chassis.attach(
      "\{rail.0}_merge",
      parent_mate=rail.1,
      strut,
      child_mate="start",
      spec=@cad.JointSpec::merge_rigid(offset_mm=-wheelbase / 2.0),
    )
  }
  // Front suspension fork and its steering column. The fork's local frame
  // puts the axle at z = 0 and the mount at fork_length + 18, so the mount
  // sits high enough that the axle lands at the front-wheel radius.
  let fork_length = front_wheel_diam * 1.2
  let fork_mount_z = front_wheel_diam / 2.0 + fork_length + 18.0
  chassis = chassis.add_body(
    @cad.BodyPart::cylinder_mm(
      "steering_column",
      30.0,
      fork_mount_z - 30.0 - deck_top,
      x_mm=wheelbase * 0.55,
      y_mm=45.0,
      z_mm=(deck_top + fork_mount_z - 30.0) / 2.0,
      density=@urdf.Density::aluminum_6061(),
      color=@step_cad.Rgb::grey(),
    ).with_part(
      scooter_fab("SCOOTER-STEERING-COLUMN", "Steering column", "6061-T6", 8.0),
    ),
  )
  chassis = chassis.add_mate_mm_deg(
    "steering_mount",
    x=wheelbase * 0.55,
    z=fork_mount_z,
    axis=(0.0, 0.0, 1.0),
  )
  let fork = @components.suspension_fork_module(
    name="front_fork",
    fork_span_mm=track_width * 0.28,
    fork_length_mm=fork_length,
    wheel_diam_mm=front_wheel_diam,
    detail~,
    threads?,
  )
  chassis = chassis.attach(
    "steering_joint",
    parent_mate="steering_mount",
    fork,
    child_mate="mount",
    spec=@cad.JointSpec::revolute(
      @urdf.JointLimit::new(
        lower=Some(-0.75),
        upper=Some(0.75),
        effort=15.0,
        velocity=3.0,
      ),
      transmission_reduction=Some(5.0),
    ),
  )
  // Rear hub drives.
  let hub_members : Array[(String, Double)] = [
    ("rear_left_hub", half_track),
    ("rear_right_hub", -half_track),
  ]
  for hub_spec in hub_members {
    let (hub_name, y) = hub_spec
    chassis = chassis.add_mate_mm_deg(
      "\{hub_name}_axle",
      x=-wheelbase / 2.0,
      y~,
      z=rear_wheel_r,
      rx_deg=-90.0,
      axis=(0.0, 1.0, 0.0),
    )
    let hub = @components.hub_motor_assembly(
      name=hub_name,
      tire_diam_mm=rear_wheel_diam,
      tire_width_mm=track_width * 0.12,
      detail~,
    )
    chassis = chassis.attach(
      "\{hub_name}_mount_joint",
      parent_mate="\{hub_name}_axle",
      hub,
      child_mate="axle",
      spec=@cad.JointSpec::fixed(),
    )
  }
  // Electronics, sensors, and harness.
  let controller = @components.pcb_board(
    name="drive_controller",
    length_mm=70.0,
    width_mm=50.0,
    connectors=["power", "can", "left_motor", "right_motor", "steer"],
    detail~,
  )
  chassis = chassis.add_mate_mm_deg("pcb_mount", z=deck_top + 4.0)
  chassis = chassis.attach(
    "pcb_merge",
    parent_mate="pcb_mount",
    controller,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let imu = @components.imu_module(name="imu", detail~)
  chassis = chassis.add_mate_mm_deg(
    "imu_mount",
    x=-wheelbase * 0.15,
    z=deck_top + 4.0,
  )
  chassis = chassis.attach(
    "imu_merge",
    parent_mate="imu_mount",
    imu,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let steering_home = @components.limit_switch(name="steering_home", detail~)
  chassis = chassis.add_mate_mm_deg(
    "steering_home_mount",
    x=wheelbase * 0.55,
    y=45.0,
    z=deck_top + 110.0,
  )
  chassis = chassis.attach(
    "steering_home_merge",
    parent_mate="steering_home_mount",
    steering_home,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let camera = @components.camera_module(name="front_camera", detail~)
  chassis = chassis.add_mate_mm_deg(
    "camera_mount",
    x=wheelbase * 0.55,
    z=front_wheel_diam + 20.0,
  )
  chassis = chassis.attach(
    "camera_merge",
    parent_mate="camera_mount",
    camera,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let _ = chassis.add_cable_route(
    @cad.CableRoute::new(
      "deck_harness",
      points=[(0.0, 0.0, deck_top), (wheelbase * 0.3, 0.0, deck_top)],
      jacket_diameter_mm=10.0,
      wire_names=["drive_can"],
      material="PVC",
      from_component="chassis_link",
      from_port="can",
      to_component="front_fork",
      to_port="can",
    ),
  )
  let _ = chassis.add_wire_run(
    @cad.WireRun::new(
      "drive_can",
      from_component="chassis_link",
      from_port="can",
      to_component="front_fork",
      to_port="can",
      gauge_awg=24,
      length_mm=900.0,
    ),
  )
  let _ = chassis.add_control_binding(
    @cad.ControlBinding::new(
      "steering_joint",
      actuator="front_fork",
      channel="can0:1",
      gear_ratio=5.0,
      soft_lower=Some(-0.75),
      soft_upper=Some(0.75),
      homing_input=Some("signal"),
    ),
  )
  let _ = chassis.add_control_binding(
    @cad.ControlBinding::new(
      "rear_left_hub_spin_joint",
      actuator="rear_left_hub_wheel",
      channel="can0:2",
      gear_ratio=1.0,
      soft_lower=Some(-100.0),
      soft_upper=Some(100.0),
    ),
  )
  let _ = chassis.add_control_binding(
    @cad.ControlBinding::new(
      "rear_right_hub_spin_joint",
      actuator="rear_right_hub_wheel",
      channel="can0:3",
      gear_ratio=1.0,
      soft_lower=Some(-100.0),
      soft_upper=Some(100.0),
    ),
  )
  let _ = chassis.add_control_binding(
    @cad.ControlBinding::new(
      "front_fork_wheel_joint",
      actuator="front_fork_wheel",
      channel="can0:4",
      gear_ratio=1.0,
      soft_lower=Some(-100.0),
      soft_upper=Some(100.0),
    ),
  )
  let deg = @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  positions.set("steering_joint", args.double("steerDeg") * deg)
  positions.set("rear_left_hub_spin_joint", args.double("leftWheelDeg") * deg)
  positions.set("rear_right_hub_spin_joint", args.double("rightWheelDeg") * deg)
  @common.write_output(chassis, output, joint_positions=positions)
}
