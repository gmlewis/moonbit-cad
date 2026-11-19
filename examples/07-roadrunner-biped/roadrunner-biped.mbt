///|
/// 07-roadrunner-biped — RAI Institute "Roadrunner" symmetric bipedal-wheeled
/// robot prototype for multi-modal locomotion.
///
/// Key observed design features:
/// - Cylindrical lateral-axis torso drum (~230 x 210 mm, ~15 kg total robot)
///   with a curved purple wrap shell, exposed gold/brass structural end rings,
///   white half-dome lateral cheek shrouds above the hip mounts, dual top
///   roll/tether hoops, internal 48 V battery + compute stack, and IMU.
/// - Fully symmetric 4-DOF legs (`hip_roll_joint`, `hip_pitch_joint`,
///   `knee_joint`, `wheel_joint`) allowing knees to flex equally forward or
///   backward and legs to swing seamlessly between `side-by-side`, `in-line`,
///   `one-wheel`, and `wide` (ground-recovery) configurations.
/// - Brushed silver cylindrical thighs with side-mounted driver pods, teal/purple
///   QDD planetary actuators, slender dark-anodized twin-bar calves, and 180 mm
///   (7-inch) multi-spoke white wheels driven by compact hub motors.

///|
fn purple_shell() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.47, 0.24, 0.56)
}

///|
fn gold_ring() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.84, 0.72, 0.34)
}

///|
fn white_trim() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.95, 0.96, 0.97)
}

///|
fn teal_anodized() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.10, 0.55, 0.62)
}

///|
fn silver_aluminum() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.76, 0.79, 0.82)
}

///|
fn dark_frame() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.14, 0.15, 0.17)
}

///|
fn rubber_black() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.08, 0.08, 0.09)
}

///|
fn printed_part(
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
fn cnc_part(
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
    process="CNC",
    unit_cost_usd=cost_usd,
  )
}

///|
fn purchased_part(
  part_number : String,
  description : String,
  supplier : String,
  supplier_url : String,
  material : String,
  cost_usd : Double,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier~,
    supplier_url~,
    material~,
    process="purchased",
    unit_cost_usd=cost_usd,
  )
}

///|
/// Builds an annular arc polygon around the origin in 2D `(x, z)` from
/// `start_deg` to `end_deg` (measured from `+Z` toward `+X`).
fn annular_arc_profile(
  inner_r : Double,
  outer_r : Double,
  start_deg : Double,
  end_deg : Double,
  steps : Int32,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  let deg = @math.PI / 180.0
  for i in 0..<=steps {
    let frac = i.to_double() / steps.to_double()
    let a = (start_deg + (end_deg - start_deg) * frac) * deg
    pts.push((outer_r * @math.sin(a), outer_r * @math.cos(a)))
  }
  for i in 0..<=steps {
    let frac = (steps - i).to_double() / steps.to_double()
    let a = (start_deg + (end_deg - start_deg) * frac) * deg
    pts.push((inner_r * @math.sin(a), inner_r * @math.cos(a)))
  }
  pts
}

///|
/// Builds a semicircular cap profile spanning `z >= 0` (`-90..+90 deg` from `+Z`).
fn half_disc_profile(
  inner_r : Double,
  outer_r : Double,
  steps : Int32,
) -> Array[(Double, Double)] {
  annular_arc_profile(inner_r, outer_r, -90.0, 90.0, steps)
}

///|
/// Open U-shaped profile for top roll/tether arches.
fn u_arch_profile(
  span_mm : Double,
  height_mm : Double,
  bar_mm : Double,
) -> Array[(Double, Double)] {
  let hs = span_mm / 2.0
  let ihs = hs - bar_mm
  let ih = height_mm - bar_mm
  [
    (-hs, 0.0),
    (-ihs, 0.0),
    (-ihs, ih),
    (ihs, ih),
    (ihs, 0.0),
    (hs, 0.0),
    (hs, height_mm),
    (-hs, height_mm),
  ]
}

///|
/// Compact Roadrunner QDD planetary actuator (`motor_mount` at `-Z`,
/// `output_flange` on the rotating horn at `+Z`).
fn roadrunner_qdd_actuator(
  name~ : String,
  joint_name~ : String,
  housing_diam_mm~ : Double,
  housing_length_mm~ : Double,
  output_diam_mm~ : Double,
  output_thickness_mm~ : Double,
  housing_color~ : @step_cad.Rgb,
  reduction~ : Double = 9.0,
  continuous~ : Bool = false,
  lower_rad~ : Double = -3.14159,
  upper_rad~ : Double = 3.14159,
  max_effort_nm~ : Double = 90.0,
  max_vel_rad_s~ : Double = 20.0,
) -> @cad.Component {
  let housing_part = printed_part(
    "RR-QDD-\{housing_diam_mm.to_int()}",
    "A12 8318 QDD planetary housing \{housing_diam_mm.to_int()} mm",
    "CF nylon / 6061-T6 aluminum",
    42.0,
  )
  let a12_raw = @components.step_a12_motor(
    name=name + "_a12",
    joint_name=name + "_a12_rotor_joint",
  )
  let a12_motor = { ..a12_raw, actuator: None, }
  let stator = @cad.Component::new(
      name,
      description="Roadrunner A12 8318 QDD planetary actuator stator",
    )
    .with_param("motor", "A12 8318 100KV")
    .with_param("housing_diam_mm", housing_diam_mm.to_string())
    .with_param("housing_length_mm", housing_length_mm.to_string())
    .with_param("reduction", reduction.to_string())
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_housing",
        housing_diam_mm,
        92.0,
        housing_length_mm,
        density=@urdf.Density::kg_per_m3(1650.0),
        color=housing_color,
      ).with_part(housing_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_rear_plate",
        housing_diam_mm,
        4.0,
        z_mm=-housing_length_mm / 2.0 + 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_aluminum(),
      ).with_part(housing_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_bezel",
        housing_diam_mm * 1.05,
        housing_diam_mm * 0.94,
        6.0,
        z_mm=housing_length_mm / 2.0 - 3.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_aluminum(),
      ).with_part(housing_part),
    )
    .add_mate_mm_deg(
      "a12_mount",
      z=-housing_length_mm / 2.0 + 4.0,
      axis=(0.0, 0.0, -1.0),
    )
    .attach(
      name + "_a12_mount_joint",
      parent_mate="a12_mount",
      a12_motor,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
    .add_mate_mm_deg(
      "motor_mount",
      z=-housing_length_mm / 2.0,
      axis=(0.0, 0.0, -1.0),
    )
    .add_mate_mm_deg("bearing_seat", z=housing_length_mm / 2.0)
  let rotor_name = name + "_rotor"
  let rotor = @cad.Component::new(
      rotor_name,
      description="Roadrunner QDD actuator rotor flange",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        rotor_name + "_horn",
        output_diam_mm,
        output_thickness_mm,
        density=@urdf.Density::aluminum_6061(),
        color=silver_aluminum(),
      ).with_part(housing_part),
    )
    .add_mate_mm_deg("base", z=-output_thickness_mm / 2.0)
    .add_mate_mm_deg("output_flange", z=output_thickness_mm / 2.0)
  let spec = @cad.ActuatorSpec::new(
    @cad.ActuatorKind::Bldc,
    model="A12 8318 100KV QDD " + housing_diam_mm.to_int().to_string(),
    voltage_v=48.0,
    current_rated_a=60.0,
    current_stall_a=120.0,
    torque_rated_nm=max_effort_nm,
    driver="moteus C1 / FOC",
    interface="CAN",
    encoder="AS5047P",
  )
  let joint_spec = if continuous {
    @cad.JointSpec::continuous(
      offset_mm=output_thickness_mm / 2.0,
      limit=Some(
        @urdf.JointLimit::new(effort=max_effort_nm, velocity=max_vel_rad_s),
      ),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.35, friction=0.06)),
      transmission_reduction=Some(reduction),
    )
  } else {
    @cad.JointSpec::revolute(
      @urdf.JointLimit::new(
        lower=Some(lower_rad),
        upper=Some(upper_rad),
        effort=max_effort_nm,
        velocity=max_vel_rad_s,
      ),
      offset_mm=output_thickness_mm / 2.0,
      dynamics=Some(@urdf.JointDynamics::new(damping=0.35, friction=0.06)),
      transmission_reduction=Some(reduction),
    )
  }
  stator
  .with_actuator(spec)
  .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="48 V, 60 A"))
  .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B, 1 Mbps"))
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  .attach(
    joint_name,
    parent_mate="bearing_seat",
    rotor,
    child_mate="base",
    spec=joint_spec,
  )
}

///|
/// Builds Roadrunner's multi-spoke white alloy wheel (`180 mm` OD) + black rubber tire.
fn roadrunner_wheel(
  name : String,
  diam_mm~ : Double,
  width_mm~ : Double,
) -> @cad.Component {
  let wheel_part = purchased_part(
    "RR-WHEEL-\{diam_mm.to_int()}",
    "Roadrunner \{diam_mm.to_int()} mm multi-spoke wheeled foot with pneumatic tire",
    "Amazon",
    "https://www.amazon.com/budrash-72-107-Replaces-Universal-Utility/dp/B09XMGXFDN",
    "6061-T6 rim / rubber tire",
    22.0,
  )
  let rim_outer = diam_mm * 0.72
  let rim_inner = rim_outer * 0.80
  let tire_inner = rim_outer - 2.0
  let mut wheel = @cad.Component::new(
      name,
      description="Multi-spoke wheeled foot",
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_tire",
        diam_mm,
        tire_inner,
        width_mm,
        density=@urdf.Density::tpu(),
        color=rubber_black(),
      ).with_part(wheel_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_rim_barrel",
        rim_outer,
        rim_inner,
        width_mm * 0.72,
        density=@urdf.Density::aluminum_6061(),
        color=white_trim(),
      ).with_part(wheel_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_center_hub",
        rim_inner * 0.44,
        width_mm * 0.56,
        density=@urdf.Density::aluminum_6061(),
        color=silver_aluminum(),
      ).with_part(wheel_part),
    )
    .with_part(wheel_part)
  let spoke_len = rim_inner * 0.88 - rim_inner * 0.16
  let spoke_mid = (rim_inner * 0.88 + rim_inner * 0.16) * 0.5
  for i in 0..<6 {
    let angle = i.to_double() * @math.PI / 3.0
    wheel = wheel.add_body(
      @cad.BodyPart::box_mm(
        "\{name}_spoke_\{i}",
        spoke_len,
        10.0,
        width_mm * 0.36,
        x_mm=spoke_mid * @math.cos(angle),
        y_mm=spoke_mid * @math.sin(angle),
        rz_deg=angle * 180.0 / @math.PI,
        density=@urdf.Density::aluminum_6061(),
        color=white_trim(),
      ).with_part(wheel_part),
    )
  }
  wheel.add_mate_mm_deg("hub_mount", z=-width_mm * 0.5, axis=(0.0, 0.0, -1.0))
}

///|
/// Builds Roadrunner's cylindrical lateral-axis torso drum (`drum_diam_mm` x
/// `drum_width_mm`) with purple outer shell, gold structural end rings, white
/// half-dome side shrouds, top tether arches, 48 V battery, compute box, and IMU.
fn build_roadrunner_torso(
  drum_diam_mm : Double,
  drum_width_mm : Double,
) -> @cad.Component {
  let drum_part = printed_part(
    "RR-DRUM-SHELL", "Curved purple Roadrunner cylindrical torso wrap with white half-dome cheek shrouds",
    "carbon fiber PETG", 36.0,
  )
  let ring_part = cnc_part(
    "RR-END-RINGS", "Gold-anodized circular structural torso end rings & inner saddle frame",
    "6061-T6 aluminum", 42.0,
  )
  let battery_part = purchased_part(
    "RR-BAT-48V", "48 V 8 Ah high-discharge Li-ion battery pack", "Amazon", "https://www.amazon.com/s?k=48V+Li-ion+battery+pack+XT60",
    "Li-ion cells / FR-4", 165.0,
  )
  let r_out = drum_diam_mm / 2.0
  let shell_profile = annular_arc_profile(r_out - 5.0, r_out, -138.0, 138.0, 48)
  let cheek_profile = half_disc_profile(r_out * 0.54, r_out * 1.02, 36)
  let arch_prof = u_arch_profile(46.0, 26.0, 7.0)
  let half_w = drum_width_mm / 2.0
  let mut torso = @cad.Component::new(
      "base_link",
      description="Roadrunner cylindrical barrel torso with dual hip roll mounts",
    )
    // Curved purple barrel shell extruded along Y (rx=90 maps +Z extrusion to -Y).
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        "torso_purple_shell",
        shell_profile,
        drum_width_mm,
        rx_deg=90.0,
        density=@urdf.Density::carbon_fiber(),
        color=purple_shell(),
      ).with_part(drum_part),
    )
    // Internal dark battery/compute core inside the barrel.
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_compute_pack",
        drum_diam_mm * 0.56,
        drum_width_mm * 0.76,
        drum_diam_mm * 0.38,
        z_mm=-8.0,
        density=@urdf.Density::kg_per_m3(1200.0),
        color=dark_frame(),
      ).with_part(battery_part),
    )
    // Exposed bottom electronics tray saddle.
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_bottom_saddle",
        drum_diam_mm * 0.56,
        drum_width_mm * 0.88,
        14.0,
        z_mm=-r_out * 0.78,
        density=@urdf.Density::aluminum_6061(),
        color=silver_aluminum(),
      ).with_part(ring_part),
    )
    // Geometric white "rai" badge accent bars on front (+X) and rear (-X).
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_front_emblem",
        4.0,
        48.0,
        14.0,
        x_mm=r_out - 0.5,
        z_mm=-34.0,
        density=@urdf.Density::pla(),
        color=white_trim(),
      ).with_part(drum_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_rear_emblem",
        4.0,
        48.0,
        14.0,
        x_mm=-(r_out - 0.5),
        z_mm=-34.0,
        density=@urdf.Density::pla(),
        color=white_trim(),
      ).with_part(drum_part),
    )
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="48 V, 60 A"))
    .add_port(
      @cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B, 1 Mbps"),
    )
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  // Left & right gold end rings + white upper cheek domes + top tether arches.
  for side_idx, sign in [1.0, -1.0] {
    let side_tag = if side_idx == 0 { "left" } else { "right" }
    torso = torso
      .add_body(
        @cad.BodyPart::tube_mm(
          "torso_gold_ring_\{side_tag}",
          drum_diam_mm + 4.0,
          drum_diam_mm - 26.0,
          8.0,
          y_mm=sign * (half_w + 3.0),
          rx_deg=90.0,
          density=@urdf.Density::aluminum_6061(),
          color=gold_ring(),
        ).with_part(ring_part),
      )
      .add_body(
        @cad.BodyPart::extruded_profile_mm(
          "torso_cheek_dome_\{side_tag}",
          cheek_profile,
          28.0,
          y_mm=sign * (half_w + 20.0),
          rx_deg=90.0,
          density=@urdf.Density::carbon_fiber(),
          color=white_trim(),
        ).with_part(drum_part),
      )
      .add_body(
        @cad.BodyPart::extruded_profile_mm(
          "torso_dome_cap_\{side_tag}",
          half_disc_profile(10.0, r_out * 0.94, 24),
          8.0,
          y_mm=sign * (half_w + 35.0),
          rx_deg=90.0,
          density=@urdf.Density::carbon_fiber(),
          color=white_trim(),
        ).with_part(drum_part),
      )
      .add_body(
        @cad.BodyPart::extruded_profile_mm(
          "torso_top_arch_\{side_tag}",
          arch_prof,
          10.0,
          y_mm=sign * (half_w - 30.0),
          z_mm=r_out - 6.0,
          rx_deg=90.0,
          density=@urdf.Density::aluminum_6061(),
          color=dark_frame(),
        ).with_part(ring_part),
      )
  }
  let imu_part = purchased_part(
    "RR-IMU-6DOF", "BMI088 6-DOF IMU sensor module", "Amazon", "https://www.amazon.com/s?k=BMI088+6-DOF+IMU+module",
    "FR-4 / MEMS", 18.0,
  )
  let imu = @cad.Component::new("torso_imu", description="Six-axis IMU")
    .with_param("voltage_v", "5.0")
    .with_param("current_ma", "25.0")
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_imu_board",
        30.0,
        30.0,
        1.6,
        density=@urdf.Density::kg_per_m3(1850.0),
        color=teal_anodized(),
      ).with_part(imu_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_imu_ic",
        6.0,
        6.0,
        1.2,
        z_mm=1.4,
        density=@urdf.Density::pla(),
        color=dark_frame(),
      ).with_part(imu_part),
    )
    .with_part(imu_part)
    .with_sensor(
      @cad.SensorSpec::new(
        @cad.SensorKind::Imu,
        model="BMI088 6-axis IMU",
        interface="I2C",
        voltage_v=5.0,
        current_ma=25.0,
        range="+/-16 g, +/-2000 deg/s",
        resolution="16-bit",
      ),
    )
    .add_mate_mm_deg("mount", z=-0.8, axis=(0.0, 0.0, -1.0))
  torso
  .add_mate_mm_deg("imu_mount", z=26.0)
  .attach(
    "imu_merge",
    parent_mate="imu_mount",
    imu,
    child_mate="mount",
    spec=@cad.JointSpec::merge_rigid(),
  )
}

///|
/// Builds one symmetric 4-DOF Roadrunner leg (`hip_roll -> hip_pitch -> thigh ->
/// knee -> twin-bar calf -> hub_wheel`).
fn build_roadrunner_leg(
  prefix : String,
  is_left~ : Bool,
  thigh_len_mm~ : Double,
  calf_len_mm~ : Double,
  wheel_diam_mm~ : Double,
) -> @cad.Component {
  let side = if is_left { 1.0 } else { -1.0 }
  let bracket_part = cnc_part(
    "RR-HIP-YOKE", "Machined purple aluminum hip abduction clevis yoke", "6061-T6 aluminum",
    48.0,
  )
  let thigh_part = cnc_part(
    "RR-THIGH-\{thigh_len_mm.to_int()}",
    "Brushed silver cylindrical thigh tube with side motor-driver enclosure",
    "6061-T6 aluminum",
    55.0,
  )
  let calf_part = cnc_part(
    "RR-CALF-\{calf_len_mm.to_int()}",
    "Slender twin-bar symmetric dark-anodized calf fork",
    "7075-T6 aluminum",
    46.0,
  )
  let esc_part = printed_part(
    "RR-THIGH-POD", "White side-mounted thigh ESC / capacitor pod cover", "PETG",
    6.0,
  )
  let hip_roll_drive = roadrunner_qdd_actuator(
    name=prefix + "_hip_roll_drive",
    joint_name=prefix + "_hip_roll_joint",
    housing_diam_mm=98.0,
    housing_length_mm=46.0,
    output_diam_mm=64.0,
    output_thickness_mm=10.0,
    housing_color=purple_shell(),
    lower_rad=-1.05,
    upper_rad=1.05,
    max_effort_nm=80.0,
    max_vel_rad_s=18.0,
  )
  // Hip clevis offsets outward in Y by 56 mm so the cylindrical thigh and hip
  // pitch actuator swing full ±180 deg clear of the drum and white cheek domes.
  let clevis_span_y = 56.0
  let thigh_outboard_z = 26.0
  // Hip pitch actuator (teal QDD): continuous / symmetric ±180 deg rotation.
  let hip_pitch_drive = roadrunner_qdd_actuator(
    name=prefix + "_hip_pitch_drive",
    joint_name=prefix + "_hip_pitch_joint",
    housing_diam_mm=100.0,
    housing_length_mm=48.0,
    output_diam_mm=68.0,
    output_thickness_mm=10.0,
    housing_color=teal_anodized(),
    continuous=true,
    max_effort_nm=90.0,
    max_vel_rad_s=20.0,
  )
  // Knee actuator (teal QDD): points inboard (`-Z_thigh` = `-side * Y_world`)
  // so `knee_rotor`'s `output_flange` lands right inline beneath the hip roll plane.
  let knee_drive = roadrunner_qdd_actuator(
    name=prefix + "_knee_drive",
    joint_name=prefix + "_knee_joint",
    housing_diam_mm=98.0,
    housing_length_mm=46.0,
    output_diam_mm=64.0,
    output_thickness_mm=10.0,
    housing_color=teal_anodized(),
    lower_rad=-2.45,
    upper_rad=2.45,
    max_effort_nm=75.0,
    max_vel_rad_s=22.0,
  )
  let wheel_drive = roadrunner_qdd_actuator(
    name=prefix + "_wheel_drive",
    joint_name=prefix + "_wheel_joint",
    housing_diam_mm=98.0,
    housing_length_mm=42.0,
    output_diam_mm=64.0,
    output_thickness_mm=8.0,
    housing_color=teal_anodized(),
    reduction=1.0,
    continuous=true,
    max_effort_nm=32.0,
    max_vel_rad_s=36.0,
  )
  let wheel = roadrunner_wheel(
    prefix + "_wheel_link",
    diam_mm=wheel_diam_mm,
    width_mm=44.0,
  )
  // Hip clevis offsets outward in Y by 56 mm so the cylindrical thigh and hip
  // pitch actuator swing full ±180 deg clear of the drum and white cheek domes.
  // Because `hip_roll_drive` has `ry_deg = 90` on torso (`X_roll = -Z_world`),
  // rotating `pitch_mount` by `rx_deg = ±90` keeps `+X_thigh` pointing straight DOWN!
  let clevis_clean = @cad.Component::new(
      prefix + "_hip_clevis",
      description="Symmetric hip roll-to-pitch clevis yoke",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_clevis_arm",
        44.0,
        clevis_span_y + 24.0,
        42.0,
        x_mm=12.0,
        y_mm=side * clevis_span_y * 0.5,
        z_mm=-20.0,
        density=@urdf.Density::aluminum_6061(),
        color=purple_shell(),
      ).with_part(bracket_part),
    )
    .with_part(bracket_part)
    .add_mate_mm_deg("roll_mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg(
      "pitch_mount",
      x=20.0,
      y=side * clevis_span_y,
      z=-37.0,
      rx_deg=if is_left { -90.0 } else { 90.0 },
      axis=(0.0, side, 0.0),
    )
  // Rebuild `thigh` and `calf` using exact `+X` = DOWN (`-Z_world`)!
  let mut thigh_x = @cad.Component::new(
      prefix + "_thigh_link",
      description="Symmetric cylindrical Roadrunner thigh",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_thigh_shoulder_tab",
        30.0,
        34.0,
        thigh_outboard_z + 4.0,
        x_mm=8.0,
        z_mm=thigh_outboard_z * 0.5,
        density=@urdf.Density::aluminum_6061(),
        color=silver_aluminum(),
      ).with_part(thigh_part),
    )
    // Signature thick brushed silver aluminum hollow thigh tube (68 mm OD x 60 mm ID).
    .add_body(
      @cad.BodyPart::tube_mm(
        prefix + "_thigh_cylinder",
        68.0,
        60.0,
        thigh_len_mm - 56.0,
        x_mm=thigh_len_mm * 0.5,
        z_mm=thigh_outboard_z,
        ry_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_aluminum(),
      ).with_part(thigh_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_thigh_driver_pod",
        52.0,
        38.0,
        24.0,
        x_mm=thigh_len_mm * 0.45,
        z_mm=thigh_outboard_z + 34.0,
        density=@urdf.Density::pla(),
        color=white_trim(),
      ).with_part(esc_part),
    )
    .with_part(thigh_part)
    .add_mate_mm_deg("proximal_mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg(
      "knee_mount",
      x=thigh_len_mm,
      z=thigh_outboard_z - 16.0,
      rx_deg=180.0,
      axis=(0.0, 0.0, -1.0),
    )
  let mut calf_x = @cad.Component::new(
      prefix + "_calf_link",
      description="Slender symmetric twin-bar dark-anodized calf",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_calf_knee_yoke",
        36.0,
        38.0,
        14.0,
        x_mm=10.0,
        z_mm=7.0,
        density=@urdf.Density::aluminum_6061(),
        color=dark_frame(),
      ).with_part(calf_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_calf_spar_front",
        calf_len_mm - 20.0,
        10.0,
        14.0,
        x_mm=calf_len_mm * 0.5,
        y_mm=11.0,
        z_mm=12.0,
        density=@urdf.Density::aluminum_6061(),
        color=dark_frame(),
      ).with_part(calf_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_calf_spar_rear",
        calf_len_mm - 20.0,
        10.0,
        14.0,
        x_mm=calf_len_mm * 0.5,
        y_mm=-11.0,
        z_mm=12.0,
        density=@urdf.Density::aluminum_6061(),
        color=dark_frame(),
      ).with_part(calf_part),
    )
    .with_part(calf_part)
    .add_mate_mm_deg("proximal_mount", axis=(0.0, 0.0, -1.0))
    // Wheel motor points outboard (`-Z_calf`, so rx_deg=180).
    .add_mate_mm_deg(
      "wheel_mount",
      x=calf_len_mm,
      z=6.0,
      rx_deg=180.0,
      axis=(0.0, 0.0, -1.0),
    )
  calf_x = calf_x
    .attach(
      prefix + "_wheel_drive_mount",
      parent_mate="wheel_mount",
      wheel_drive,
      child_mate="motor_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      prefix + "_wheel_drive_rotor",
      prefix + "_wheel_hub_mount",
      parent_mate="output_flange",
      wheel,
      child_mate="hub_mount",
      spec=@cad.JointSpec::fixed(offset_mm=24.0),
    )
  thigh_x = thigh_x
    .attach(
      prefix + "_knee_drive_mount",
      parent_mate="knee_mount",
      knee_drive,
      child_mate="motor_mount",
      spec=@cad.JointSpec::fixed(),
    )
    .attach_to(
      prefix + "_knee_drive_rotor",
      prefix + "_calf_mount",
      parent_mate="output_flange",
      calf_x,
      child_mate="proximal_mount",
      spec=@cad.JointSpec::fixed(),
    )
  hip_roll_drive
  .attach_to(
    prefix + "_hip_roll_drive_rotor",
    prefix + "_clevis_mount",
    parent_mate="output_flange",
    clevis_clean,
    child_mate="roll_mount",
    spec=@cad.JointSpec::fixed(),
  )
  .attach_to(
    prefix + "_hip_clevis",
    prefix + "_pitch_drive_mount",
    parent_mate="pitch_mount",
    hip_pitch_drive,
    child_mate="motor_mount",
    spec=@cad.JointSpec::fixed(),
  )
  .attach_to(
    prefix + "_hip_pitch_drive_rotor",
    prefix + "_thigh_mount",
    parent_mate="output_flange",
    thigh_x,
    child_mate="proximal_mount",
    spec=@cad.JointSpec::fixed(),
  )
}

///|
/// Roadrunner pose defaults (`left` and `right` (roll, hip_pitch, knee) in deg)
/// matching the four behaviors shown in the RAI Institute video:
/// `side-by-side`, `in-line`, `one-wheel`, and `wide`.
fn mode_pose(
  mode : String,
) -> ((Double, Double, Double), (Double, Double, Double)) {
  match mode {
    // Symmetric tandem inline wheel stance: left forward, right backward, equal Z drop.
    "in-line" | "inline" => ((-8.0, -26.0, 14.0), (-8.0, 26.0, -14.0))
    // Balancing dynamically on left wheel while right leg splays outboard & tucks high.
    "one-wheel" | "onewheel" => ((-8.0, 14.0, 28.0), (16.0, -40.0, -115.0))
    // Wide low stance recovering from ground with opposite forward/backward knees.
    "wide" | "stand-up" => ((26.0, 36.0, 72.0), (26.0, -36.0, -72.0))
    // Default side-by-side wheeled bipedal stance centered vertically under drum.
    _ => ((0.0, 18.0, 36.0), (0.0, 18.0, 36.0))
  }
}

///|
/// Builds the complete 8-DOF Roadrunner bipedal wheeled robot assembly.
pub fn build_roadrunner(
  drum_diam_mm~ : Double = 230.0,
  drum_width_mm~ : Double = 210.0,
  thigh_len_mm~ : Double = 220.0,
  calf_len_mm~ : Double = 220.0,
  wheel_diam_mm~ : Double = 180.0,
) -> @cad.Component {
  let mut base = build_roadrunner_torso(drum_diam_mm, drum_width_mm)
  let hip_y = drum_width_mm * 0.5 - 16.0
  let hip_z = -drum_diam_mm * 0.36
  for pair in [("l", true), ("r", false)] {
    let (prefix, is_left) = pair
    let sign = if is_left { 1.0 } else { -1.0 }
    base = base.add_mate_mm_deg(
      "\{prefix}_hip_mount",
      x=-22.0,
      y=sign * hip_y,
      z=hip_z,
      ry_deg=90.0,
      axis=(1.0, 0.0, 0.0),
    )
    let leg = build_roadrunner_leg(
      prefix,
      is_left~,
      thigh_len_mm~,
      calf_len_mm~,
      wheel_diam_mm~,
    )
    base = base.attach(
      "\{prefix}_leg_mount",
      parent_mate="\{prefix}_hip_mount",
      leg,
      child_mate="motor_mount",
      spec=@cad.JointSpec::fixed(),
    )
  }
  base = base.add_cable_route(
    @cad.CableRoute::new(
      "hip_trunk_harness",
      points=[
        (0.0, 0.0, 0.0),
        (0.0, hip_y * 0.6, hip_z * 0.5),
        (0.0, hip_y, hip_z),
      ],
      jacket_diameter_mm=10.0,
      wire_names=["l_can", "l_power"],
      material="PVC",
      from_component="base_link",
      from_port="can",
      to_component="l_hip_roll_drive",
      to_port="can",
    ),
  )
  for prefix in ["l", "r"] {
    base = base
      .add_wire_run(
        @cad.WireRun::new(
          "\{prefix}_can",
          from_component="base_link",
          from_port="can",
          to_component="\{prefix}_hip_roll_drive",
          to_port="can",
          gauge_awg=24,
          length_mm=380.0,
        ),
      )
      .add_wire_run(
        @cad.WireRun::new(
          "\{prefix}_power",
          from_component="base_link",
          from_port="power",
          to_component="\{prefix}_hip_roll_drive",
          to_port="power",
          gauge_awg=16,
          length_mm=340.0,
        ),
      )
  }
  let joint_names : Array[String] = [
    "hip_roll_joint", "hip_pitch_joint", "knee_joint", "wheel_joint",
  ]
  let actuator_suffixes : Array[String] = [
    "_hip_roll_drive", "_hip_pitch_drive", "_knee_drive", "_wheel_drive",
  ]
  let mut channel = 1
  for pair in [("l", 1.0), ("r", -1.0)] {
    let (prefix, side) = pair
    for i in 0..<4 {
      base = base.add_control_binding(
        @cad.ControlBinding::new(
          "\{prefix}_\{joint_names[i]}",
          actuator="\{prefix}\{actuator_suffixes[i]}",
          channel="can0:" + channel.to_string(),
          direction=if side > 0.0 || i == 0 { "normal" } else { "inverted" },
          gear_ratio=if i == 3 { 1.0 } else { 9.0 },
        ),
      )
      channel = channel + 1
    }
  }
  base
}

///|
/// Computes joint positions map (radians) for a named pose or explicit angles.
pub fn pose_positions(
  mode~ : String = "side-by-side",
  hip_roll_deg~ : Double? = None,
  hip_pitch_deg~ : Double? = None,
  knee_deg~ : Double? = None,
  wheel_spin_deg~ : Double = 0.0,
) -> Map[String, Double] {
  let ((l_roll, l_pitch, l_knee), (r_roll, r_pitch, r_knee)) = mode_pose(mode)
  let deg = @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  positions.set("l_hip_roll_joint", hip_roll_deg.unwrap_or(l_roll) * deg)
  positions.set("r_hip_roll_joint", -hip_roll_deg.unwrap_or(r_roll) * deg)
  // Remember `rx_deg = ±90` mirrors pitch sign between left and right legs.
  positions.set("l_hip_pitch_joint", hip_pitch_deg.unwrap_or(l_pitch) * deg)
  positions.set("r_hip_pitch_joint", -hip_pitch_deg.unwrap_or(r_pitch) * deg)
  positions.set("l_knee_joint", knee_deg.unwrap_or(l_knee) * deg)
  positions.set("r_knee_joint", -knee_deg.unwrap_or(r_knee) * deg)
  positions.set("l_wheel_joint", wheel_spin_deg * deg)
  positions.set("r_wheel_joint", -wheel_spin_deg * deg)
  positions
}

///|
/// Runs the `07-roadrunner-biped` CLI.
pub async fn run_cli() -> Unit {
  let base_spec = {
    "drumDiam": @cli.opt_double(230.0, help="Torso drum diameter in mm"),
    "drumWidth": @cli.opt_double(210.0, help="Torso drum lateral width in mm"),
    "thighLength": @cli.opt_double(220.0, help="Symmetric thigh length in mm"),
    "calfLength": @cli.opt_double(220.0, help="Slender calf length in mm"),
    "wheelDiam": @cli.opt_double(180.0, help="Wheel outer diameter in mm"),
    "mode": @cli.opt_string(
      help="Pose preset: side-by-side (default), in-line, one-wheel, or wide",
    ),
    "hipRollDeg": @cli.opt_double(0.0, help="Symmetric hip roll/splay in deg"),
    "hipPitchDeg": @cli.opt_double(18.0, help="Symmetric hip pitch in deg"),
    "kneeDeg": @cli.opt_double(36.0, help="Symmetric knee pitch in deg"),
    "wheelSpinDeg": @cli.opt_double(0.0, help="Wheel spin angle in deg"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="07-roadrunner-biped",
      description="Roadrunner symmetric 8-DOF bipedal wheeled robot (side-by-side, in-line, one-wheel, wide).",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let base = build_roadrunner(
    drum_diam_mm=args.double("drumDiam"),
    drum_width_mm=args.double("drumWidth"),
    thigh_len_mm=args.double("thighLength"),
    calf_len_mm=args.double("calfLength"),
    wheel_diam_mm=args.double("wheelDiam"),
  )
  let mode = args.string_opt("mode").unwrap_or("side-by-side")
  let has_custom_mode = args.string_opt("mode") is Some(_)
  let positions = if has_custom_mode {
    pose_positions(mode~, wheel_spin_deg=args.double("wheelSpinDeg"))
  } else {
    pose_positions(
      mode~,
      hip_roll_deg=Some(args.double("hipRollDeg")),
      hip_pitch_deg=Some(args.double("hipPitchDeg")),
      knee_deg=Some(args.double("kneeDeg")),
      wheel_spin_deg=args.double("wheelSpinDeg"),
    )
  }
  @common.write_output(
    base,
    output,
    joint_positions=positions,
    example_dir="examples/07-roadrunner-biped",
  )
}
