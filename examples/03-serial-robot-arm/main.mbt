///|
/// 03-serial-robot-arm
///
/// A six-revolute-joint modular serial arm assembled from flange plates, QDD
/// actuator pods, reinforced box-tube links, right-angle joint flanges, and a
/// 1-DOF motorized, threaded lead-screw parallel-jaw gripper.  The gripper
/// carries two limit switches on welded brackets and a controller PCB on the
/// bottom beam, with declared power, STEP/DIR, and limit-switch wiring.
///
/// Every link is a box tube with **solid end plates** welded into both ends
/// (the plate overlaps the tube by 4 mm and extends past it), and every
/// side-mounted actuator or transverse joint sits on a **solid boss pad**
/// welded into the tube wall (again with a 4 mm overlap).  This gives each
/// joint a full solid face to bolt to instead of a thin end-ring or a bare
/// 3 mm tube wall.
///
/// The chain is intentionally non-collinear: the waist yaws about Z, the
/// shoulder/elbow/wrist-pitch/tool-pitch axes are horizontal (Y), and the
/// wrist roll is about X, giving a pitch-roll-pitch wrist.

///|
/// A box-tube link with solid end plates welded into its ends.
///
/// The plate is wider and taller than the tube (by `margin` on each side) and
/// overlaps the tube end by `overlap`; its outer face is a solid mating
/// surface.  `start_plate`/`end_plate` can be disabled for open-ended
/// adapters.
fn plated_strut(
  name : String,
  width : Double,
  height : Double,
  length : Double,
  wall : Double,
  plate_t : Double,
  margin : Double,
  overlap : Double,
  start_plate~ : Bool = true,
  end_plate~ : Bool = true,
) -> @cad.Component {
  let plate_w = width + 2.0 * margin
  let plate_h = height + 2.0 * margin
  let start_face = if start_plate {
    -length / 2.0 - (plate_t - overlap)
  } else {
    -length / 2.0
  }
  let end_face = if end_plate {
    length / 2.0 + (plate_t - overlap)
  } else {
    length / 2.0
  }
  let mut comp = @catalog.box_tube_strut(
    name,
    width_mm=width,
    height_mm=height,
    length_mm=length,
    wall_mm=wall,
  )
  if start_plate {
    comp = comp.add_body(
      @cad.BodyPart::box_mm(
        name + "_start_plate",
        plate_w,
        plate_h,
        plate_t,
        z_mm=-length / 2.0 + overlap - plate_t / 2.0,
      ),
    )
  }
  if end_plate {
    comp = comp.add_body(
      @cad.BodyPart::box_mm(
        name + "_end_plate",
        plate_w,
        plate_h,
        plate_t,
        z_mm=length / 2.0 - overlap + plate_t / 2.0,
      ),
    )
  }
  comp
  .add_mate_mm_deg("start_flange", z=start_face)
  .add_mate_mm_deg("end_flange", z=end_face)
}

///|
/// Welds a solid boss pad into one side of a box-tube link and registers a
/// port mate on the pad's outer face.  The pad overlaps the tube wall by
/// `overlap`, so it is solidly connected rather than sitting on the skin.
fn with_side_pad(
  comp : @cad.Component,
  name : String,
  side : String,
  tube_w : Double,
  tube_h : Double,
  pad_size : Double,
  pad_t : Double,
  overlap : Double,
  along : Double,
) -> @cad.Component {
  match side {
    "+y" =>
      comp
      .add_body(
        @cad.BodyPart::box_mm(
          name + "_pad",
          pad_size,
          pad_t,
          pad_size,
          y_mm=tube_h / 2.0 + pad_t / 2.0 - overlap,
          z_mm=along,
        ),
      )
      .add_mate_mm_deg(
        name,
        y=tube_h / 2.0 + pad_t - overlap,
        z=along,
        rx_deg=-90.0,
      )
    "-y" =>
      comp
      .add_body(
        @cad.BodyPart::box_mm(
          name + "_pad",
          pad_size,
          pad_t,
          pad_size,
          y_mm=-tube_h / 2.0 - pad_t / 2.0 + overlap,
          z_mm=along,
        ),
      )
      .add_mate_mm_deg(
        name,
        y=-tube_h / 2.0 - (pad_t - overlap),
        z=along,
        rx_deg=90.0,
      )
    "+x" =>
      comp
      .add_body(
        @cad.BodyPart::box_mm(
          name + "_pad",
          pad_t,
          pad_size,
          pad_size,
          x_mm=tube_w / 2.0 + pad_t / 2.0 - overlap,
          z_mm=along,
        ),
      )
      .add_mate_mm_deg(
        name,
        x=tube_w / 2.0 + pad_t - overlap,
        z=along,
        ry_deg=90.0,
      )
    "-x" =>
      comp
      .add_body(
        @cad.BodyPart::box_mm(
          name + "_pad",
          pad_t,
          pad_size,
          pad_size,
          x_mm=-tube_w / 2.0 - pad_t / 2.0 + overlap,
          z_mm=along,
        ),
      )
      .add_mate_mm_deg(
        name,
        x=-tube_w / 2.0 - (pad_t - overlap),
        z=along,
        ry_deg=-90.0,
      )
    _ => comp
  }
}

///|
async fn main {
  let base_spec = {
    "link1Len": @cli.opt_double(250.0, help="Upper arm length in mm"),
    "link2Len": @cli.opt_double(220.0, help="Forearm length in mm"),
    "waistDeg": @cli.opt_double(25.0, help="Waist yaw angle in degrees"),
    "shoulderDeg": @cli.opt_double(35.0, help="Shoulder pitch angle in degrees"),
    "elbowDeg": @cli.opt_double(-55.0, help="Elbow pitch angle in degrees"),
    "wristPitchDeg": @cli.opt_double(30.0, help="Wrist pitch angle in degrees"),
    "wristRollDeg": @cli.opt_double(60.0, help="Wrist roll angle in degrees"),
    "toolPitchDeg": @cli.opt_double(25.0, help="Tool pitch angle in degrees"),
    "gripMm": @cli.opt_double(12.0, help="Gripper jaw travel in mm (0-28)"),
    "kicadPos": @cli.opt_string(
      help="KiCad .pos CSV for the gripper controller board",
    ),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="03-serial-robot-arm",
      description="Six-axis modular serial robot arm with a motorized lead-screw jaw.",
    )
    is Some(args) else {
    return
  }
  let link1_len = args.double("link1Len")
  let link2_len = args.double("link2Len")
  // Link cross-sections and structural member sizes.
  let link1_w = 90.0
  let link1_h = 70.0
  let link2_w = 70.0
  let link2_h = 60.0
  let link_wall = 5.0
  let plate_t = 10.0
  let plate_margin = 6.0
  let plate_overlap = 4.0
  let adapter_w = 50.0
  let adapter_h = 40.0
  let adapter_len = 60.0
  let adapter_wall = 4.0
  let adapter_plate_t = 8.0
  let adapter_margin = 6.0
  let pad_t = 12.0
  let pad_overlap = 3.0
  let shoulder_diam = 96.0
  let elbow_diam = 80.0
  let wrist_pitch_diam = 64.0
  let wrist_roll_diam = 52.0
  let tool_pitch_diam = 40.0
  let wrist_link_len = 80.0
  let wrist_link_w = 50.0
  let wrist_link_h = 40.0
  let small_adapter_len = 60.0
  let small_adapter_w = 36.0
  let small_adapter_h = 30.0
  let tool_link_len = 60.0
  let tool_link_w = 40.0
  let tool_link_h = 34.0
  let tool_out_len = 55.0
  let tool_out_w = 30.0
  let tool_out_h = 24.0
  let base = @catalog.flange_plate(
    name="base_flange",
    outer_diam_mm=160.0,
    center_bore_mm=40.0,
    bolt_count=6,
    bolt_circle_mm=120.0,
  )
  let waist = @catalog.bldc_actuator_pod(
    name="waist",
    housing_diam_mm=120.0,
    housing_length_mm=70.0,
    output_diam_mm=80.0,
    output_thickness_mm=12.0,
  )
  // Vertical upper arm with solid end plates and a shoulder boss on its +Y
  // side.  The boss keeps the pod's rear disc off the 5 mm tube wall.
  let upper_arm = plated_strut(
    "upper_arm", link1_w, link1_h, link1_len, link_wall, plate_t, plate_margin, plate_overlap,
  )
  let upper_arm = with_side_pad(
    upper_arm,
    "shoulder_port",
    "+y",
    link1_w,
    link1_h,
    shoulder_diam,
    pad_t,
    pad_overlap,
    link1_len / 2.0 - shoulder_diam / 2.0 - 6.0,
  )
  let shoulder = @catalog.bldc_actuator_pod(
    name="shoulder",
    housing_diam_mm=shoulder_diam,
    housing_length_mm=54.0,
    output_diam_mm=56.0,
    output_thickness_mm=8.0,
  )
  // Right-angle flange: the actuator output runs along +Y, the forearm
  // leaves along +X.  The adapter's start plate takes the full rotor face,
  // and its side boss gives the forearm a solid 45 x 45 land.
  let shoulder_adapter = plated_strut(
    "shoulder_adapter",
    adapter_w,
    adapter_h,
    adapter_len,
    adapter_wall,
    adapter_plate_t,
    adapter_margin,
    plate_overlap,
    end_plate=false,
  )
  let shoulder_adapter = with_side_pad(
    shoulder_adapter,
    "forearm_port",
    "+x",
    adapter_w,
    adapter_h,
    45.0,
    pad_t,
    pad_overlap,
    adapter_len / 2.0 - 30.0,
  )
  let forearm = plated_strut(
    "forearm", link2_w, link2_h, link2_len, link_wall, plate_t, plate_margin, plate_overlap,
  )
  let forearm = with_side_pad(
    forearm,
    "elbow_port",
    "-x",
    link2_w,
    link2_h,
    elbow_diam,
    pad_t,
    pad_overlap,
    link2_len / 2.0 - elbow_diam / 2.0 - 6.0,
  )
  let elbow = @catalog.bldc_actuator_pod(
    name="elbow",
    housing_diam_mm=elbow_diam,
    housing_length_mm=48.0,
    output_diam_mm=48.0,
    output_thickness_mm=8.0,
  )
  let elbow_adapter = plated_strut(
    "elbow_adapter",
    adapter_w,
    adapter_h,
    adapter_len,
    adapter_wall,
    adapter_plate_t,
    adapter_margin,
    plate_overlap,
    end_plate=false,
  )
  let elbow_adapter = with_side_pad(
    elbow_adapter,
    "wrist_link_port",
    "+x",
    adapter_w,
    adapter_h,
    45.0,
    pad_t,
    pad_overlap,
    adapter_len / 2.0 - 30.0,
  )
  let wrist_link = plated_strut(
    "wrist_link", wrist_link_w, wrist_link_h, wrist_link_len, adapter_wall, adapter_plate_t,
    adapter_margin, plate_overlap,
  )
  let wrist_link = with_side_pad(
    wrist_link, "wrist_pitch_port", "-x", wrist_link_w, wrist_link_h, wrist_pitch_diam,
    pad_t, pad_overlap, 0.0,
  )
  let wrist_pitch = @catalog.bldc_actuator_pod(
    name="wrist_pitch",
    housing_diam_mm=wrist_pitch_diam,
    housing_length_mm=40.0,
    output_diam_mm=38.0,
    output_thickness_mm=6.0,
  )
  let wrist_adapter = plated_strut(
    "wrist_adapter",
    small_adapter_w,
    small_adapter_h,
    small_adapter_len,
    adapter_wall,
    adapter_plate_t,
    adapter_margin,
    plate_overlap,
    end_plate=false,
  )
  let wrist_adapter = with_side_pad(
    wrist_adapter,
    "wrist_roll_port",
    "+x",
    small_adapter_w,
    small_adapter_h,
    45.0,
    pad_t,
    pad_overlap,
    small_adapter_len / 2.0 - 20.0,
  )
  let wrist_roll = @catalog.bldc_actuator_pod(
    name="wrist_roll",
    housing_diam_mm=wrist_roll_diam,
    housing_length_mm=34.0,
    output_diam_mm=32.0,
    output_thickness_mm=6.0,
  )
  // Sixth axis: a small pitch pod at the tool flange.  The tool link carries
  // the pod on its -X side boss, and the gripper leaves the pod's +X boss, so
  // the tool pitch is perpendicular to the wrist roll.
  let tool_link = plated_strut(
    "tool_link", tool_link_w, tool_link_h, tool_link_len, adapter_wall, adapter_plate_t,
    adapter_margin, plate_overlap,
  )
  let tool_link = with_side_pad(
    tool_link, "tool_pitch_port", "-x", tool_link_w, tool_link_h, tool_pitch_diam,
    pad_t, pad_overlap, -4.0,
  )
  let tool_pitch = @catalog.bldc_actuator_pod(
    name="tool_pitch",
    housing_diam_mm=tool_pitch_diam,
    housing_length_mm=28.0,
    output_diam_mm=26.0,
    output_thickness_mm=5.0,
  )
  let tool_out = plated_strut(
    "tool_out",
    tool_out_w,
    tool_out_h,
    tool_out_len,
    adapter_wall,
    adapter_plate_t,
    adapter_margin,
    plate_overlap,
    end_plate=false,
  )
  let tool_out = with_side_pad(
    tool_out,
    "gripper_port",
    "+x",
    tool_out_w,
    tool_out_h,
    45.0,
    pad_t,
    pad_overlap,
    tool_out_len / 2.0 - 22.0,
  )
  let kicad_pos_csv = match args.string_opt("kicadPos") {
    Some(path) => @fs.read_file(path).text()
    None => ""
  }
  let grip_lead_mm = 2.0
  let grip_travel_mm = 28.0
  let joint_gear_ratio = 6.0
  let can_node_base = 1
  let joint_limit_rad = @math.PI
  let gripper = @catalog.lead_screw_gripper(
    name="gripper",
    opening_mm=30.0,
    travel_mm=28.0,
    lead_mm=grip_lead_mm,
    finger_len_mm=45.0,
    finger_width_mm=45.0,
    finger_thick_mm=8.0,
    controller_pos_csv=kicad_pos_csv,
  )
  let comp = base
    .attach(
      "waist_mount",
      parent_mate="top",
      waist,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "waist_rotor",
      "upper_arm_mount",
      parent_mate="output_flange",
      upper_arm,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "upper_arm",
      "shoulder_mount",
      parent_mate="shoulder_port",
      shoulder,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "shoulder_rotor",
      "shoulder_adapter_mount",
      parent_mate="output_flange",
      shoulder_adapter,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "shoulder_adapter",
      "forearm_mount",
      parent_mate="forearm_port",
      forearm,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "forearm",
      "elbow_mount",
      parent_mate="elbow_port",
      elbow,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "elbow_rotor",
      "elbow_adapter_mount",
      parent_mate="output_flange",
      elbow_adapter,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "elbow_adapter",
      "wrist_link_mount",
      parent_mate="wrist_link_port",
      wrist_link,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "wrist_link",
      "wrist_pitch_mount",
      parent_mate="wrist_pitch_port",
      wrist_pitch,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "wrist_pitch_rotor",
      "wrist_adapter_mount",
      parent_mate="output_flange",
      wrist_adapter,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "wrist_adapter",
      "wrist_roll_mount",
      parent_mate="wrist_roll_port",
      wrist_roll,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "wrist_roll_rotor",
      "tool_link_mount",
      parent_mate="output_flange",
      tool_link,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "tool_link",
      "tool_pitch_mount",
      parent_mate="tool_pitch_port",
      tool_pitch,
      child_mate="rear_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "tool_pitch_rotor",
      "tool_out_mount",
      parent_mate="output_flange",
      tool_out,
      child_mate="start_flange",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      "tool_out",
      "gripper_mount",
      parent_mate="gripper_port",
      gripper,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
    .with_robot_name("serial_robot_arm")
  // Control map: six CAN joint modules plus the gripper's STEP/DIR channel.
  let arm_bindings : Array[(String, String)] = [
    ("waist_joint", "waist"),
    ("shoulder_joint", "shoulder"),
    ("elbow_joint", "elbow"),
    ("wrist_pitch_joint", "wrist_pitch"),
    ("wrist_roll_joint", "wrist_roll"),
    ("tool_pitch_joint", "tool_pitch"),
  ]
  for i in 0..<arm_bindings.length() {
    let binding = arm_bindings[i]
    let _ = comp.add_control_binding(
      @cad.ControlBinding::new(
        binding.0,
        actuator=binding.1,
        channel="can0:" + (can_node_base + i).to_string(),
        gear_ratio=joint_gear_ratio,
        soft_lower=Some(-joint_limit_rad),
        soft_upper=Some(joint_limit_rad),
      ),
    )
  }
  let gripper_pins = "STEP=PA0; DIR=PA1; EN=PA2"
  let _ = comp.add_control_binding(
    @cad.ControlBinding::new(
      "gripper_motor_shaft_joint",
      actuator="gripper_motor_stator",
      channel="step_dir:0",
      mcu_pins=gripper_pins,
      gear_ratio=1.0,
      soft_lower=Some(0.0),
      soft_upper=Some(grip_travel_mm / grip_lead_mm * 2.0 * @math.PI),
      homing_input=Some("limit_home"),
      limit_input=Some("limit_closed"),
    ),
  )
  let deg = @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  positions.set("waist_joint", args.double("waistDeg") * deg)
  positions.set("shoulder_joint", args.double("shoulderDeg") * deg)
  positions.set("elbow_joint", args.double("elbowDeg") * deg)
  positions.set("wrist_pitch_joint", args.double("wristPitchDeg") * deg)
  positions.set("wrist_roll_joint", args.double("wristRollDeg") * deg)
  positions.set("tool_pitch_joint", args.double("toolPitchDeg") * deg)
  let grip_mm = args.double("gripMm")
  let grip_mm = if grip_mm < 0.0 {
    0.0
  } else if grip_mm > grip_travel_mm {
    grip_travel_mm
  } else {
    grip_mm
  }
  positions.set(
    "gripper_motor_shaft_joint",
    grip_mm / grip_lead_mm * 2.0 * @math.PI,
  )
  @common.write_output(
    comp,
    @common.output_paths(args),
    joint_positions=positions,
  )
}
