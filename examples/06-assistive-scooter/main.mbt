///|
/// 06-assistive-scooter
///
/// A motorized wheelchair / assistive mobility vehicle. Two inexpensive heavy
/// low-KV BLDC outrunners drive two-stage printed planetary gearboxes; the
/// printed frame, seat, backrest, and armrests are built from V-slot extrusion
/// and printable plates. `--layout scooter` builds the lighter single-front-fork
/// variant on the same drivetrain.

///|
fn mobility_fab(
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
    "layout": @cli.opt_string(help="Layout: wheelchair (default) or scooter"),
    "wheelbase": @cli.opt_double(680.0, help="Wheelbase in mm"),
    "trackWidth": @cli.opt_double(480.0, help="Track width in mm"),
    "seatHeight": @cli.opt_double(420.0, help="Seat height in mm"),
    "rearWheelDiam": @cli.opt_double(250.0, help="Rear wheel diameter in mm"),
    "frontWheelDiam": @cli.opt_double(150.0, help="Front wheel diameter in mm"),
    "gearRatio": @cli.opt_double(
      25.0,
      help="Requested total reduction (informational)",
    ),
    "stage1Module": @cli.opt_double(2.0, help="Planetary gear module in mm"),
    "steerDeg": @cli.opt_double(0.0, help="Steering angle in degrees"),
    "leftWheelDeg": @cli.opt_double(0.0, help="Left wheel angle in degrees"),
    "rightWheelDeg": @cli.opt_double(0.0, help="Right wheel angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="06-assistive-scooter",
      description="Motorized wheelchair / assistive mobility vehicle.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let layout = args.string_opt("layout").unwrap_or("wheelchair")
  let wheelbase = args.double("wheelbase")
  let track_width = args.double("trackWidth")
  let seat_height = args.double("seatHeight")
  let rear_wheel_diam = args.double("rearWheelDiam")
  let front_wheel_diam = args.double("frontWheelDiam")
  let module_mm = args.double("stage1Module")
  let rear_wheel_r = rear_wheel_diam / 2.0
  let front_wheel_r = front_wheel_diam / 2.0
  let half_track = track_width / 2.0
  let frame_z = rear_wheel_r + 60.0
  let deg = @math.PI / 180.0
  // Two-stage 12/18/48 planetary drive: 25:1, driven by an A12 8318 100KV motor.
  let reduction = @components.planetary_reduction(12, 18, 2)
  let stage_length = 14.0
  let drive_length = stage_length * 2.0 + 124.0
  let mut chassis = @cad.Component::new(
      "chassis_link",
      description="Motorized wheelchair chassis",
    )
    .with_robot_name("assistive_wheelchair")
    .with_param("layout", layout)
    .with_param("wheelbase_mm", wheelbase.to_string())
    .with_param("track_width_mm", track_width.to_string())
    .with_param("seat_height_mm", seat_height.to_string())
    .with_param("reduction", reduction.to_string())
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="36 V, 30 A"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  // Structural lower frame: two 2040 V-slot side rails and 2020 cross rails.
  for
    rail in [
      ("left_rail", track_width * 0.20),
      ("right_rail", -track_width * 0.20),
    ] {
    chassis = chassis
      .add_mate_mm_deg("\{rail.0}_mount", y=rail.1, z=frame_z, ry_deg=90.0)
      .attach(
        "\{rail.0}_merge",
        parent_mate="\{rail.0}_mount",
        @components.vslot_extrusion_strut(
          name=rail.0,
          profile=@step_profiles.VSlotProfile::vslot_2040(),
          length_mm=wheelbase,
          detail~,
        ),
        child_mate="start",
        spec=@cad.JointSpec::merge_rigid(offset_mm=-wheelbase / 2.0),
      )
    chassis = chassis.attach(
      "\{rail.0}_tnut_merge",
      parent_mate="\{rail.0}_mount",
      @components.extrusion_tnut_part(
        name=rail.0 + "_tnut",
        thread="M5",
        slot_width_mm=6.0,
        detail~,
      ),
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  for
    cross in [
      ("front_cross", wheelbase * 0.35),
      ("rear_cross", -wheelbase * 0.35),
    ] {
    chassis = chassis
      .add_mate_mm_deg(
        "\{cross.0}_mount",
        x=cross.1,
        z=frame_z - 20.0,
        rx_deg=-90.0,
      )
      .attach(
        "\{cross.0}_merge",
        parent_mate="\{cross.0}_mount",
        @components.vslot_extrusion_strut(
          name=cross.0,
          profile=@step_profiles.VSlotProfile::vslot_2020(),
          length_mm=track_width * 0.42,
          detail~,
        ),
        child_mate="start",
        spec=@cad.JointSpec::merge_rigid(offset_mm=-track_width * 0.21),
      )
  }
  // Corner brackets and joining plates tie the frame together.
  for
    corner in [
      ("frame_fl", wheelbase * 0.45, track_width * 0.20),
      ("frame_fr", wheelbase * 0.45, -track_width * 0.20),
      ("frame_rl", -wheelbase * 0.45, track_width * 0.20),
      ("frame_rr", -wheelbase * 0.45, -track_width * 0.20),
    ] {
    let (corner_name, cx, cy) = corner
    chassis = chassis
      .add_mate_mm_deg("\{corner_name}_mount", x=cx, y=cy, z=frame_z)
      .attach(
        "\{corner_name}_merge",
        parent_mate="\{corner_name}_mount",
        @components.vslot_corner_bracket_part(name=corner_name, leg_mm=20.0),
        child_mate="mount_a",
        spec=@cad.JointSpec::merge_rigid(),
      )
    chassis = chassis.attach(
      "\{corner_name}_joining_merge",
      parent_mate="\{corner_name}_mount",
      @components.vslot_joining_plate_part(
        name=corner_name + "_joining",
        length_mm=40.0,
        width_mm=20.0,
        thickness_mm=4.0,
      ),
      child_mate="bottom",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  // Printable deck, battery bay, seat pan, backrest, and armrests.
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "deck",
      wheelbase * 0.55,
      track_width * 0.62,
      10.0,
      z_mm=frame_z + 25.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::grey(),
    ).with_part(mobility_fab("WC-DECK", "Foot deck", "PETG", 18.0)),
  )
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "battery_bay",
      wheelbase * 0.32,
      track_width * 0.4,
      120.0,
      x_mm=-wheelbase * 0.12,
      z_mm=frame_z - 20.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(mobility_fab("WC-BATTERY-BAY", "Battery bay", "PETG", 20.0)),
  )
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "seat_pan",
      track_width * 0.78,
      track_width * 0.66,
      14.0,
      x_mm=-wheelbase * 0.10,
      z_mm=seat_height - 7.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(mobility_fab("WC-SEAT-PAN", "Seat pan", "PETG", 26.0)),
  )
  chassis = chassis.add_body(
    @cad.BodyPart::box_mm(
      "backrest",
      16.0,
      track_width * 0.72,
      460.0,
      x_mm=-wheelbase * 0.10 - 210.0,
      z_mm=seat_height + 220.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(mobility_fab("WC-BACKREST", "Backrest", "PETG", 24.0)),
  )
  for armrest in [("left_armrest", 150.0), ("right_armrest", -150.0)] {
    chassis = chassis.add_body(
      @cad.BodyPart::box_mm(
        armrest.0,
        380.0,
        50.0,
        40.0,
        x_mm=-wheelbase * 0.05,
        y_mm=armrest.1,
        z_mm=seat_height + 120.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::black(),
      ).with_part(mobility_fab("WC-ARMREST", "Folding armrest", "PETG", 14.0)),
    )
  }
  // Reusable joystick pod on the left armrest.
  chassis = chassis
    .add_mate_mm_deg(
      "joystick_mount",
      x=wheelbase * 0.20,
      y=-150.0,
      // The left armrest top is 20 mm above its centreline.
      z=seat_height + 140.0,
    )
    .attach(
      "joystick_joint",
      parent_mate="joystick_mount",
      @components.joystick_pod(name="joystick", detail~),
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
  // Differential rear planetary drives.
  for drive in [("left", 1.0), ("right", -1.0)] {
    let (drive_name, side) = drive
    let mount_y = if side > 0.0 {
      half_track - drive_length
    } else {
      -half_track + drive_length
    }
    let drive_rx = if side > 0.0 { -90.0 } else { 90.0 }
    chassis = chassis
      .add_mate_mm_deg(
        "\{drive_name}_mount",
        x=-wheelbase / 2.0,
        y=mount_y,
        z=rear_wheel_r,
        rx_deg=drive_rx,
      )
      .attach(
        "\{drive_name}_mount_joint",
        parent_mate="\{drive_name}_mount",
        @components.planetary_wheel_drive_unit(
          name=drive_name,
          preset="a12_8318_100kv",
          stages=2,
          module_mm~,
          sun_teeth=12,
          planet_teeth=18,
          planet_count=3,
          gear_length_mm=stage_length,
          wheel_diam_mm=rear_wheel_diam,
          wheel_width_mm=52.0,
          detail~,
        ),
        child_mate="motor_mount",
        spec=@cad.JointSpec::fixed(),
      )
  }
  // Front casters (wheelchair) or one steerable suspension fork (scooter).
  let caster_mount_z = frame_z - 30.0
  // The suspension fork's `mount` is 18 mm above its front axle; the caster's
  // `steering_axis` is 16 mm above its axle. Each length subtracts its own
  // offset so the front wheel bottom lands on the same ground plane.
  let scooter_fork_length = if caster_mount_z > front_wheel_r + 30.0 {
    caster_mount_z - front_wheel_r - 18.0
  } else {
    60.0
  }
  let caster_fork_length = if caster_mount_z > front_wheel_r + 30.0 {
    caster_mount_z - front_wheel_r - 16.0
  } else {
    60.0
  }
  if layout == "scooter" {
    let mount_z = caster_mount_z
    chassis = chassis
      .add_mate_mm_deg(
        "steering_mount",
        x=wheelbase * 0.48,
        z=mount_z,
        axis=(0.0, 0.0, 1.0),
      )
      .attach(
        "steering_joint",
        parent_mate="steering_mount",
        @components.suspension_fork_module(
          name="front_fork",
          fork_span_mm=track_width * 0.25,
          fork_length_mm=scooter_fork_length,
          wheel_diam_mm=front_wheel_diam,
          detail~,
        ),
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
  } else {
    for caster in [("caster_left", 1.0), ("caster_right", -1.0)] {
      let (caster_name, side) = caster
      chassis = chassis
        .add_mate_mm_deg(
          "\{caster_name}_mount",
          x=wheelbase * 0.45,
          y=side * track_width * 0.36,
          z=caster_mount_z,
          axis=(0.0, 0.0, 1.0),
        )
        .attach(
          "\{caster_name}_swivel_joint",
          parent_mate="\{caster_name}_mount",
          @components.caster_fork_assembly(
            name=caster_name,
            wheel_diam_mm=front_wheel_diam,
            wheel_width_mm=32.0,
            fork_span_mm=90.0,
            fork_length_mm=caster_fork_length,
            detail~,
          ),
          child_mate="steering_axis",
          spec=@cad.JointSpec::revolute(
            @urdf.JointLimit::new(
              lower=Some(-1.4),
              upper=Some(1.4),
              effort=4.0,
              velocity=4.0,
            ),
            dynamics=Some(@urdf.JointDynamics::new(damping=0.2, friction=0.1)),
          ),
        )
    }
  }
  // Electronics and sensors.
  let controller = @components.pcb_board(
      name="drive_controller",
      length_mm=90.0,
      width_mm=60.0,
      connectors=["power", "can", "left_motor", "right_motor", "joystick"],
      detail~,
    )
    .add_port(
      @cad.Port::new("joystick", @cad.PortKind::Signal, spec="2-axis Hall"),
    )
    .add_port(
      @cad.Port::new("estop", @cad.PortKind::Signal, spec="NC to ground"),
    )
  chassis = chassis
    .add_mate_mm_deg("pcb_mount", x=-wheelbase * 0.10, z=seat_height - 20.0)
    .attach(
      "pcb_merge",
      parent_mate="pcb_mount",
      controller,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  let imu = @components.imu_module(name="imu")
  chassis = chassis
    .add_mate_mm_deg("imu_mount", x=-wheelbase * 0.10, z=frame_z + 30.0)
    .attach(
      "imu_merge",
      parent_mate="imu_mount",
      imu,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  let camera = @components.camera_module(name="front_camera")
  chassis = chassis
    .add_mate_mm_deg("camera_mount", x=wheelbase * 0.45, z=frame_z + 200.0)
    .attach(
      "camera_merge",
      parent_mate="camera_mount",
      camera,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  // Wiring and control.
  chassis = chassis.add_wire_run(
    @cad.WireRun::new(
      "left_drive_can",
      from_component="chassis_link",
      from_port="can",
      to_component="left_drive",
      to_port="can",
      gauge_awg=24,
      length_mm=900.0,
    ),
  )
  chassis = chassis.add_wire_run(
    @cad.WireRun::new(
      "right_drive_can",
      from_component="chassis_link",
      from_port="can",
      to_component="right_drive",
      to_port="can",
      gauge_awg=24,
      length_mm=900.0,
    ),
  )
  chassis = chassis.add_wire_run(
    @cad.WireRun::new(
      "joystick_signal",
      from_component="joystick",
      from_port="signal",
      to_component="drive_controller",
      to_port="joystick",
      gauge_awg=26,
      length_mm=300.0,
    ),
  )
  chassis = chassis.add_wire_run(
    @cad.WireRun::new(
      "estop_loop",
      from_component="joystick",
      from_port="estop",
      to_component="drive_controller",
      to_port="estop",
      gauge_awg=22,
      length_mm=300.0,
    ),
  )
  chassis = chassis.add_cable_route(
    @cad.CableRoute::new(
      "drive_harness",
      points=[
        (-wheelbase * 0.1, 0.0, seat_height - 20.0),
        (-wheelbase * 0.3, 0.0, frame_z),
        (-wheelbase / 2.0, half_track * 0.5, rear_wheel_r),
      ],
      jacket_diameter_mm=10.0,
      wire_names=["left_drive_can"],
      material="PVC",
      from_component="chassis_link",
      from_port="can",
      to_component="left_drive",
      to_port="can",
    ),
  )
  if layout == "scooter" {
    chassis = chassis.add_control_binding(
      @cad.ControlBinding::new(
        "steering_joint",
        actuator="front_fork",
        channel="can0:3",
        gear_ratio=5.0,
        soft_lower=Some(-0.75),
        soft_upper=Some(0.75),
      ),
    )
    chassis = chassis.add_control_binding(
      @cad.ControlBinding::new(
        "front_fork_wheel_joint",
        actuator="front_fork",
        channel="can0:4",
        gear_ratio=1.0,
        soft_lower=Some(-1000.0),
        soft_upper=Some(1000.0),
      ),
    )
  } else {
    for
      caster in [
        ("caster_left", "can0:3", "can0:4"),
        ("caster_right", "can0:5", "can0:6"),
      ] {
      chassis = chassis.add_control_binding(
        @cad.ControlBinding::new(
          "\{caster.0}_swivel_joint",
          actuator=caster.0,
          channel=caster.1,
          gear_ratio=1.0,
          soft_lower=Some(-1.4),
          soft_upper=Some(1.4),
        ),
      )
      chassis = chassis.add_control_binding(
        @cad.ControlBinding::new(
          "\{caster.0}_wheel_joint",
          actuator=caster.0,
          channel=caster.2,
          gear_ratio=1.0,
          soft_lower=Some(-1000.0),
          soft_upper=Some(1000.0),
        ),
      )
    }
  }
  chassis = chassis.add_control_binding(
    @cad.ControlBinding::new(
      "left_wheel_joint",
      actuator="left_drive",
      channel="can0:1",
      gear_ratio=reduction,
      soft_lower=Some(-1000.0),
      soft_upper=Some(1000.0),
    ),
  )
  chassis = chassis.add_control_binding(
    @cad.ControlBinding::new(
      "right_wheel_joint",
      actuator="right_drive",
      channel="can0:2",
      gear_ratio=reduction,
      soft_lower=Some(-1000.0),
      soft_upper=Some(1000.0),
    ),
  )
  let positions : Map[String, Double] = Map([])
  positions.set("left_wheel_joint", args.double("leftWheelDeg") * deg)
  positions.set("right_wheel_joint", args.double("rightWheelDeg") * deg)
  if layout == "scooter" {
    positions.set("steering_joint", args.double("steerDeg") * deg)
  } else {
    positions.set("caster_left_swivel_joint", args.double("steerDeg") * deg)
  }
  // Ground-plane check: every drive and caster tire's lowest point must sit on
  // z = 0 so the vehicle stands on one plane. This uses the posed design's
  // exact body bounds, not a hand-computed estimate.
  let design = chassis.to_design(joint_positions=positions)
  let mut ground_min = 1.0e9
  let mut ground_max = -1.0e9
  let mut tires = 0
  for node in design.nodes {
    if node.name.contains("_tire") {
      let (_, _, _, _, z0, _) = node.bounding_box()
      tires = tires + 1
      if z0 < ground_min {
        ground_min = z0
      }
      if z0 > ground_max {
        ground_max = z0
      }
    }
  }
  if tires == 0 ||
    ground_min.abs() > 0.1 ||
    (ground_max - ground_min).abs() > 0.1 {
    @cli.eprintln(
      "error: wheel ground plane is not at z = 0 (tires " +
      tires.to_string() +
      ", min z " +
      ground_min.to_string() +
      ", max z " +
      ground_max.to_string() +
      ")",
    )
    abort("")
  }
  @common.write_output(
    chassis,
    output,
    joint_positions=positions,
    example_dir="examples/06-assistive-scooter",
  )
}
