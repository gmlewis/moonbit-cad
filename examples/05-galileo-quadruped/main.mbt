///|
/// 05-galileo-quadruped
///
/// The Galileo X wheel-legged quadruped robot: a chamfered silver monocoque
/// chassis with front LiDAR cowling, grab handles, side carry handles, and four
/// 4-DOF legs (shoulder pitch, vented vertical/cantable hip swivel pod, knee
/// pitch, and wheel hub drive with 6-spoke alloy rims). Supports All-Terrain,
/// Cruise, Omni-Directional, and Bicycle pose presets and exports posed STEP,
/// glTF, URDF, ROS 2 bundles, printable parts, and a manufacturing package.

///|
fn silver_hull() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.76, 0.78, 0.80)
}

///|
fn silver_machined() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.65, 0.67, 0.70)
}

///|
fn dark_trim() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.16, 0.17, 0.19)
}

///|
fn matte_black() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.08, 0.08, 0.09)
}

///|
fn accent_red() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.82, 0.16, 0.18)
}

///|
fn accent_blue() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.14, 0.56, 0.96)
}

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
fn cnc_fab(
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
/// Octagonal chamfered rectangle cross-section centered at the origin.
fn chamfered_rect_profile(
  width_mm : Double,
  height_mm : Double,
  chamfer_mm : Double,
) -> Array[(Double, Double)] {
  let hw = width_mm / 2.0
  let hh = height_mm / 2.0
  let c = if chamfer_mm < hw * 0.45 && chamfer_mm < hh * 0.45 {
    chamfer_mm
  } else {
    (if hw < hh { hw } else { hh }) * 0.35
  }
  [
    (-hw + c, -hh),
    (hw - c, -hh),
    (hw, -hh + c),
    (hw, hh - c),
    (hw - c, hh),
    (-hw + c, hh),
    (-hw, hh - c),
    (-hw, -hh + c),
  ]
}

///|
/// Builds a tapered 2D link profile along a canted `(dx, dz)` vector starting
/// at `start_frac` and ending at `end_frac` so it stays clear of adjacent
/// cylindrical actuator housings.
fn canted_tapered_arm_profile(
  dx : Double,
  dz : Double,
  start_frac : Double,
  end_frac : Double,
  prox_width_mm : Double,
  dist_width_mm : Double,
) -> Array[(Double, Double)] {
  let len = (dx * dx + dz * dz).sqrt()
  let ux = dx / len
  let uz = dz / len
  let nx = -uz
  let nz = ux
  let sx = dx * start_frac
  let sz = dz * start_frac
  let ex = dx * end_frac
  let ez = dz * end_frac
  let pw = prox_width_mm / 2.0
  let dw = dist_width_mm / 2.0
  [
    (sx - nx * pw, sz - nz * pw),
    (sx + nx * pw, sz + nz * pw),
    (ex + nx * dw, ez + nz * dw),
    (ex - nx * dw, ez - nz * dw),
  ]
}

///|
/// Builds an open U-shaped arch profile for protective grab/roll bars.
fn u_arch_profile(
  span_mm : Double,
  height_mm : Double,
  bar_mm : Double,
) -> Array[(Double, Double)] {
  let hs = span_mm / 2.0
  let inner_hs = hs - bar_mm
  let inner_h = height_mm - bar_mm
  [
    (-hs, 0.0),
    (-inner_hs, 0.0),
    (-inner_hs, inner_h),
    (inner_hs, inner_h),
    (inner_hs, 0.0),
    (hs, 0.0),
    (hs, height_mm),
    (-hs, height_mm),
  ]
}

///|
/// Builds a Galileo X QDD joint actuator with clean mate orientation (`motor_mount`
/// at `-Z` with `axis=(0,0,-1)` so child `+Z` aligns with parent `+Z`) and an
/// optional vented swivel drum + black end-cap dress package.
fn galileo_qdd_actuator(
  name~ : String,
  joint_name~ : String,
  housing_diam_mm~ : Double,
  housing_length_mm~ : Double,
  output_diam_mm~ : Double,
  output_thickness_mm~ : Double,
  reduction~ : Double = 9.0,
  is_swivel~ : Bool = false,
  continuous~ : Bool = false,
  lower_rad~ : Double = -3.14159,
  upper_rad~ : Double = 3.14159,
  max_effort_nm~ : Double = 90.0,
  max_vel_rad_s~ : Double = 18.0,
) -> @cad.Component {
  let housing_part = cnc_fab(
    "GALILEO-A12-HOUSING-\{housing_diam_mm.to_int()}",
    "A12 8318 QDD planetary housing \{housing_diam_mm.to_int()} mm",
    "6061-T6 aluminum / CF nylon",
    45.0,
  )
  let cap_height = if is_swivel { 22.0 } else { 0.0 }
  let stator_z_min = -housing_length_mm / 2.0
  let mount_z = stator_z_min - cap_height
  let a12_raw = @components.step_a12_motor(
    name=name + "_a12",
    joint_name=name + "_a12_rotor_joint",
  )
  let a12_motor = { ..a12_raw, actuator: None, }
  let mut stator = @cad.Component::new(
      name,
      description="Galileo A12 8318 QDD actuator stator",
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
        density=@urdf.Density::aluminum_6061(),
        color=silver_machined(),
      ).with_part(housing_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_rear_plate",
        housing_diam_mm,
        4.0,
        z_mm=stator_z_min + 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_machined(),
      ).with_part(housing_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_flange",
        housing_diam_mm * 1.06,
        housing_diam_mm * 0.99,
        6.0,
        z_mm=stator_z_min + 3.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(housing_part),
    )
    .add_mate_mm_deg("a12_mount", z=stator_z_min + 4.0, axis=(0.0, 0.0, -1.0))
    .attach(
      name + "_a12_mount_joint",
      parent_mate="a12_mount",
      a12_motor,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
  if is_swivel {
    // Distinctive black octagonal/chamfered top end-cap and vented barrel grilles.
    let cap_profile = chamfered_rect_profile(
      housing_diam_mm * 1.02,
      housing_diam_mm * 1.02,
      housing_diam_mm * 0.24,
    )
    stator = stator.add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_black_cap",
        cap_profile,
        cap_height,
        z_mm=stator_z_min - cap_height / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color=matte_black(),
      ).with_part(housing_part),
    )
    for i in 0..<4 {
      let theta = @math.PI / 4.0 + i.to_double() * @math.PI / 2.0
      let r = housing_diam_mm * 0.5 + 1.5
      stator = stator.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_vent_\{i}",
          3.0,
          housing_diam_mm * 0.32,
          housing_length_mm * 0.48,
          x_mm=r * @math.cos(theta),
          y_mm=r * @math.sin(theta),
          rz_deg=theta * 180.0 / @math.PI,
          density=@urdf.Density::aluminum_6061(),
          color=dark_trim(),
        ).with_part(housing_part),
      )
    }
  }
  stator = stator
    .add_mate_mm_deg("motor_mount", z=mount_z, axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("bearing_seat", z=housing_length_mm / 2.0)
  let rotor_name = name + "_rotor"
  let rotor = @cad.Component::new(
      rotor_name,
      description="Galileo QDD actuator rotor",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        rotor_name + "_horn",
        output_diam_mm,
        output_thickness_mm,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
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
      dynamics=Some(@urdf.JointDynamics::new(damping=0.4, friction=0.08)),
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
      dynamics=Some(@urdf.JointDynamics::new(damping=0.4, friction=0.08)),
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
    bom_external=false,
  )
  .with_part(housing_part)
}

///|
/// Builds Galileo X's 6-spoke silver alloy wheel with a low-profile treaded rubber
/// tire, oriented around `+Z` with `hub_mount` on the inboard (`-Z`) face.
fn galileo_six_spoke_wheel(
  name : String,
  diam_mm~ : Double,
  width_mm~ : Double,
  detail~ : @step_common.DetailLevel,
) -> @cad.Component {
  let rim_od = diam_mm * 0.77
  let rim_id = diam_mm * 0.65
  let hub_od = diam_mm * 0.28
  let rim_part = cnc_fab(
    "GALILEO-RIM-6SPOKE-\{diam_mm.to_int()}",
    "6-spoke CNC alloy wheel rim",
    "6061-T6 aluminum",
    42.0,
  )
  let tire_part = printable_fab(
    "GALILEO-TIRE-\{diam_mm.to_int()}",
    "Low-profile treaded rubber tire",
    "TPU / rubber",
    18.0,
  )
  let mut rim_comp = @cad.Component::new(
      name + "_rim_part",
      description="Galileo X 6-spoke alloy rim",
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_rim_barrel",
        rim_od,
        rim_id,
        width_mm * 0.90,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(rim_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_center_hub",
        hub_od,
        width_mm * 0.65,
        z_mm=-width_mm * 0.08,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(rim_part),
    )
  let spoke_len = (rim_id - hub_od) * 0.48
  let spoke_mid = (rim_id + hub_od) * 0.25
  for i in 0..<6 {
    let theta = i.to_double() * @math.PI / 3.0
    rim_comp = rim_comp.add_body(
      @cad.BodyPart::box_mm(
        "\{name}_spoke_\{i}",
        spoke_len,
        diam_mm * 0.085,
        width_mm * 0.24,
        x_mm=spoke_mid * @math.cos(theta),
        y_mm=spoke_mid * @math.sin(theta),
        z_mm=width_mm * 0.14,
        rz_deg=theta * 180.0 / @math.PI,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(rim_part),
    )
  }
  let mut tire_comp = @cad.Component::new(
    name + "_tire_part",
    description="Galileo X rubber tire",
  ).add_body(
    @cad.BodyPart::tube_mm(
      name + "_tire",
      diam_mm,
      rim_od,
      width_mm,
      density=@urdf.Density::tpu(),
      color=matte_black(),
    ).with_part(tire_part),
  )
  if detail is @step_common.DetailLevel::Detailed ||
    detail is @step_common.DetailLevel::FullyModeled {
    let lug_count = 16
    for i in 0..<lug_count {
      let theta = 2.0 * @math.PI * i.to_double() / lug_count.to_double()
      tire_comp = tire_comp.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_lug_\{i}",
          4.0,
          diam_mm * 0.09,
          width_mm * 0.78,
          x_mm=(diam_mm / 2.0 - 1.0) * @math.cos(theta),
          y_mm=(diam_mm / 2.0 - 1.0) * @math.sin(theta),
          rz_deg=theta * 180.0 / @math.PI,
          density=@urdf.Density::tpu(),
          color=matte_black(),
        ).with_part(tire_part),
      )
    }
  }
  rim_comp = rim_comp.with_part(rim_part)
  tire_comp = tire_comp.with_part(tire_part)
  @cad.Component::new(name, description="Galileo X 6-spoke wheel assembly")
  .add_mate_mm_deg("hub_mount", z=-width_mm / 2.0, axis=(0.0, 0.0, -1.0))
  .attach(
    name + "_rim_merge",
    parent_mate="origin",
    rim_comp,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(),
  )
  .attach(
    name + "_tire_merge",
    parent_mate="origin",
    tire_comp,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(),
  )
}

///|
/// Builds one 4-DOF Galileo X leg (mirrored fore-to-aft via `is_front` so all
/// four wheels stay outboard at equal track width across every mode):
/// 1. `{prefix}_hip_pitch_joint`  (Y-axis shoulder pitch inside torso pod)
/// 2. `{prefix}_hip_swivel_joint` (vented swivel/steering drum, vertical Z at 0 deg)
/// 3. `{prefix}_knee_joint`       (Y_leg knee pitch at distal end of 40-deg canted thigh)
/// 4. `{prefix}_wheel_joint`      (continuous hub drive + outboard 6-spoke wheel)
fn galileo_x_leg(
  prefix : String,
  is_left~ : Bool,
  is_front~ : Bool,
  thigh_len~ : Double,
  calf_len~ : Double,
  wheel_diam~ : Double,
  max_effort_nm~ : Double,
  max_vel_rad_s~ : Double,
  wheeled~ : Bool,
  detail~ : @step_common.DetailLevel,
) -> @cad.Component {
  let sign = if is_left { 1.0 } else { -1.0 }
  let front_sign = if is_front { 1.0 } else { -1.0 }
  let deg = @math.PI / 180.0
  // Front legs cant forward (+40 deg), rear legs cant rearward (-40 deg) at swivel=0.
  let cant_deg = 40.0 * front_sign
  let cant_rad = cant_deg * deg
  let swivel_diam = 122.0
  let swivel_len = 76.0
  let swivel_cap_h = 22.0
  let swivel_center_outboard = 78.0
  let swivel_top_z = -(swivel_len / 2.0 + swivel_cap_h)
  let hip_pitch_drive = galileo_qdd_actuator(
    name=prefix + "_hip_pitch_drive",
    joint_name=prefix + "_hip_pitch_joint",
    housing_diam_mm=118.0,
    housing_length_mm=56.0,
    output_diam_mm=84.0,
    output_thickness_mm=10.0,
    lower_rad=-2.2,
    upper_rad=2.2,
    max_effort_nm~,
    max_vel_rad_s~,
  )
  let yoke_part = cnc_fab(
    "GALILEO-SHOULDER-YOKE", "CNC aluminum shoulder swivel cradle", "6061-T6 aluminum",
    55.0,
  )
  // On left (+Y_yoke = -Z_world), top of swivel drum sits at y_yoke = -60 mm (+Z_world).
  // The top arm clears the black cap from above with zero overlap into the drum.
  let cap_side = -sign
  let top_clear_y = cap_side * (-swivel_top_z + 18.0)
  let yoke = @cad.Component::new(
      prefix + "_shoulder_yoke",
      description="Shoulder pitch-to-swivel yoke",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        prefix + "_yoke_flange",
        84.0,
        14.0,
        z_mm=7.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(yoke_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_yoke_riser",
        82.0,
        -swivel_top_z + 26.0,
        14.0,
        y_mm=cap_side * (-swivel_top_z + 26.0) / 2.0,
        z_mm=7.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(yoke_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_yoke_top_arm",
        82.0,
        16.0,
        swivel_center_outboard + 16.0,
        y_mm=top_clear_y,
        z_mm=(swivel_center_outboard + 16.0) / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(yoke_part),
    )
    .with_part(yoke_part)
    .add_mate_mm_deg("proximal_mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg(
      "swivel_mount",
      y=cap_side * (-swivel_top_z + 9.0),
      z=swivel_center_outboard,
      rx_deg=if is_left { -90.0 } else { 90.0 },
      axis=(0.0, sign, 0.0),
    )
  let hip_swivel_drive = galileo_qdd_actuator(
    name=prefix + "_hip_swivel_drive",
    joint_name=prefix + "_hip_swivel_joint",
    housing_diam_mm=swivel_diam,
    housing_length_mm=swivel_len,
    output_diam_mm=92.0,
    output_thickness_mm=12.0,
    is_swivel=true,
    continuous=true,
    max_effort_nm~,
    max_vel_rad_s~,
  )
  // 40-deg canted sculpted thigh link + elastic bumper & red suspension accent.
  let thigh_part = cnc_fab(
    "GALILEO-THIGH-\{thigh_len.to_int()}",
    "Canted machined thigh arm",
    "6061-T6 aluminum",
    78.0,
  )
  let elastic_part = printable_fab(
    "GALILEO-ELASTIC-UNIT", "Super-structural polyurethane suspension block", "TPU 95A",
    12.0,
  )
  let knee_diam = 108.0
  let thigh_dx = thigh_len * @math.sin(cant_rad)
  let thigh_dz = thigh_len * @math.cos(cant_rad)
  let start_frac = 32.0 / thigh_len
  let end_frac = 1.0
  let mid_frac = (start_frac + end_frac) * 0.5
  let thigh = @cad.Component::new(
      prefix + "_thigh_link",
      description="Galileo X canted thigh link",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        prefix + "_swivel_clevis",
        86.0,
        24.0,
        z_mm=12.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(thigh_part),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        prefix + "_thigh_arm",
        canted_tapered_arm_profile(
          thigh_dx, thigh_dz, start_frac, end_frac, 62.0, 52.0,
        ),
        34.0,
        rx_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(thigh_part),
    )
    .add_body(
      // Cylindrical knee mounting boss at the distal end of the thigh.
      @cad.BodyPart::cylinder_mm(
        prefix + "_thigh_knee_boss",
        82.0,
        34.0,
        x_mm=thigh_dx,
        z_mm=thigh_dz,
        rx_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(thigh_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_thigh_pocket",
        28.0,
        34.0,
        thigh_len * 0.36,
        x_mm=thigh_dx * mid_frac,
        z_mm=thigh_dz * mid_frac,
        ry_deg=cant_deg,
        density=@urdf.Density::aluminum_6061(),
        color=dark_trim(),
      ).with_part(thigh_part),
    )
    .add_body(
      // Black ribbed elastic bump-stop on outer knee crook.
      @cad.BodyPart::box_mm(
        prefix + "_thigh_bumper",
        18.0,
        32.0,
        38.0,
        x_mm=thigh_dx * mid_frac - front_sign * 34.0 * @math.cos(cant_rad),
        z_mm=thigh_dz * mid_frac + front_sign * 34.0 * @math.sin(cant_rad),
        ry_deg=cant_deg,
        density=@urdf.Density::tpu(),
        color=matte_black(),
      ).with_part(elastic_part),
    )
    .add_body(
      // Red super-structural elastic suspension unit inside thigh-knee V.
      @cad.BodyPart::box_mm(
        prefix + "_thigh_elastic_red",
        16.0,
        28.0,
        30.0,
        x_mm=thigh_dx * mid_frac + front_sign * 33.0 * @math.cos(cant_rad),
        z_mm=thigh_dz * mid_frac - front_sign * 33.0 * @math.sin(cant_rad),
        ry_deg=cant_deg,
        density=@urdf.Density::tpu(),
        color=accent_red(),
      ).with_part(elastic_part),
    )
    .with_part(thigh_part)
    .add_mate_mm_deg("proximal_mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg(
      "knee_mount",
      x=thigh_dx,
      y=-sign * 17.0,
      z=thigh_dz,
      rx_deg=if is_left { 90.0 } else { -90.0 },
      axis=(0.0, -sign, 0.0),
    )
  let knee_drive = galileo_qdd_actuator(
    name=prefix + "_knee_drive",
    joint_name=prefix + "_knee_joint",
    housing_diam_mm=knee_diam,
    housing_length_mm=52.0,
    output_diam_mm=80.0,
    output_thickness_mm=10.0,
    lower_rad=-2.6,
    upper_rad=2.6,
    max_effort_nm~,
    max_vel_rad_s~,
  )
  // Sculpted calf link sits outboard of the knee rotor (+Z_knee = outboard),
  // extending down (+Y_knee on left, -Y_knee on right) and stopping just above
  // the wheel hub motor cylinder with zero overlap.
  let calf_dir = sign
  let hub_diam = 98.0
  let calf_arm_start = knee_diam * 0.5 + 2.0
  let calf_arm_end = calf_len - (hub_diam * 0.5 + 4.0)
  let calf_arm_len = calf_arm_end - calf_arm_start
  let calf_arm_mid = (calf_arm_start + calf_arm_end) * 0.5
  let calf_part = cnc_fab(
    "GALILEO-CALF-\{calf_len.to_int()}",
    "Machined calf link with wheel axle housing",
    "6061-T6 aluminum",
    68.0,
  )
  let calf_z_center = 24.0
  let mut calf = @cad.Component::new(
      prefix + "_calf_link",
      description="Galileo X calf link",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        prefix + "_calf_knee_boss",
        74.0,
        11.0,
        z_mm=5.5,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(calf_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_calf_step",
        52.0,
        56.0,
        14.0,
        y_mm=calf_dir * 28.0,
        z_mm=18.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(calf_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_calf_arm",
        46.0,
        calf_arm_len,
        26.0,
        y_mm=calf_dir * calf_arm_mid,
        z_mm=calf_z_center,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(calf_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        prefix + "_calf_pocket",
        24.0,
        calf_arm_len * 0.72,
        28.0,
        y_mm=calf_dir * calf_arm_mid,
        z_mm=calf_z_center,
        density=@urdf.Density::aluminum_6061(),
        color=dark_trim(),
      ).with_part(calf_part),
    )
    .with_part(calf_part)
    .add_mate_mm_deg("proximal_mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("wheel_mount", y=calf_dir * calf_len, z=24.0)
  if wheeled {
    let hub_len = 52.0
    let wheel_drive = galileo_qdd_actuator(
      name=prefix + "_wheel_drive",
      joint_name=prefix + "_wheel_joint",
      housing_diam_mm=hub_diam,
      housing_length_mm=hub_len,
      output_diam_mm=72.0,
      output_thickness_mm=10.0,
      reduction=1.0,
      continuous=true,
      max_effort_nm=36.0,
      max_vel_rad_s=35.0,
    )
    let wheel = galileo_six_spoke_wheel(
      prefix + "_wheel_link",
      diam_mm=wheel_diam,
      width_mm=52.0,
      detail~,
    )
    calf = calf
      .attach(
        prefix + "_wheel_drive_mount",
        parent_mate="wheel_mount",
        wheel_drive,
        child_mate="motor_mount",
        spec=@cad.JointSpec::fixed(offset_mm=-26.0),
      )
      .attach_to(
        prefix + "_wheel_drive_rotor",
        prefix + "_wheel_hub_mount",
        parent_mate="output_flange",
        wheel,
        child_mate="hub_mount",
        spec=@cad.JointSpec::fixed(offset_mm=4.0),
      )
  } else {
    let foot_part = printable_fab(
      "GALILEO-FOOT-\{wheel_diam.to_int()}",
      "Rubber foot pad",
      "TPU",
      8.0,
    )
    let foot = @cad.Component::new(
        prefix + "_foot_link",
        description="Rubber foot link",
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          prefix + "_foot",
          wheel_diam * 0.34,
          44.0,
          y_mm=calf_dir * 22.0,
          rx_deg=90.0,
          density=@urdf.Density::tpu(),
          color=matte_black(),
        ).with_part(foot_part),
      )
      .with_part(foot_part)
      .add_mate_mm_deg("mount", axis=(0.0, 0.0, -1.0))
    calf = calf.attach(
      prefix + "_foot_mount",
      parent_mate="wheel_mount",
      foot,
      child_mate="mount",
      spec=@cad.JointSpec::fixed(),
    )
  }
  hip_pitch_drive
  .attach_to(
    prefix + "_hip_pitch_drive_rotor",
    prefix + "_yoke_mount",
    parent_mate="output_flange",
    yoke,
    child_mate="proximal_mount",
    spec=@cad.JointSpec::fixed(),
  )
  .attach_to(
    prefix + "_shoulder_yoke",
    prefix + "_swivel_drive_mount",
    parent_mate="swivel_mount",
    hip_swivel_drive,
    child_mate="motor_mount",
    spec=@cad.JointSpec::fixed(),
  )
  .attach_to(
    prefix + "_hip_swivel_drive_rotor",
    prefix + "_thigh_mount",
    parent_mate="output_flange",
    thigh,
    child_mate="proximal_mount",
    spec=@cad.JointSpec::fixed(offset_mm=1.0),
  )
  .attach_to(
    prefix + "_thigh_link",
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
    calf,
    child_mate="proximal_mount",
    spec=@cad.JointSpec::fixed(),
  )
}

///|
/// Returns `(hip_pitch_deg, hip_swivel_deg, knee_pitch_deg)` for each named
/// Galileo X mobility mode (`all-terrain`, `cruise`, `omni`, `bicycle`).
fn mode_pose_defaults(mode : String) -> (Double, Double, Double) {
  match mode {
    "cruise" => (8.0, 0.0, 26.0)
    "omni" => (0.0, 90.0, -56.0)
    "bicycle" => (86.0, 0.0, -15.0)
    _ => (56.0, 0.0, -72.0)
  }
}

///|
/// Builds the sculpted Galileo X silver monocoque chassis (`base_link`) with
/// shoulder pods, front LiDAR sensor dome + roll guard, blue LED slits, top
/// battery hump, grab handles, side carry handles, and cooling louvers.
fn build_galileo_chassis(
  body_len : Double,
  body_width : Double,
  body_height : Double,
  detail : @step_common.DetailLevel,
) -> @cad.Component {
  let half_len = body_len / 2.0
  let half_width = body_width / 2.0
  let hull_part = cnc_fab(
    "GALILEO-MONOCOQUE-HULL", "Chamfered silver aluminum monocoque chassis", "6061-T6 aluminum",
    320.0,
  )
  let trim_part = printable_fab(
    "GALILEO-BODY-TRIM", "Front cowling, side panels, and louvers", "carbon fiber nylon",
    45.0,
  )
  let handle_part = cnc_fab(
    "GALILEO-GRAB-HANDLE", "Protective tubular shoulder/sensor guard handle", "6061-T6 aluminum",
    28.0,
  )
  let mut base = @cad.Component::new(
      "base_link",
      description="Galileo X monocoque quadruped chassis",
    )
    .with_robot_name("galileo_quadruped")
    .with_param("body_len_mm", body_len.to_string())
    .with_param("body_width_mm", body_width.to_string())
    .with_param("body_height_mm", body_height.to_string())
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="48 V, 30 A"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  let torso_profile = chamfered_rect_profile(
    body_height,
    body_width,
    body_height * 0.24,
  )
  base = base.add_body(
    @cad.BodyPart::extruded_profile_mm(
      "monocoque_hull",
      torso_profile,
      body_len * 0.88,
      ry_deg=90.0,
      density=@urdf.Density::aluminum_6061(),
      color=silver_hull(),
    ).with_part(hull_part),
  )
  let shoulder_x = body_len * 0.37
  let shoulder_profile = chamfered_rect_profile(
    body_height * 0.88,
    body_width * 1.24,
    body_height * 0.20,
  )
  for
    end_pod in [
      ("front_shoulder_pod", shoulder_x),
      ("rear_shoulder_pod", -shoulder_x),
    ] {
    base = base.add_body(
      @cad.BodyPart::extruded_profile_mm(
        end_pod.0,
        shoulder_profile,
        body_len * 0.24,
        x_mm=end_pod.1,
        ry_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(hull_part),
    )
  }
  let batt_profile = chamfered_rect_profile(30.0, body_width * 0.62, 8.0)
  base = base.add_body(
    @cad.BodyPart::extruded_profile_mm(
      "top_battery_pack",
      batt_profile,
      body_len * 0.34,
      x_mm=-body_len * 0.14,
      z_mm=body_height * 0.50 + 13.0,
      ry_deg=90.0,
      density=@urdf.Density::aluminum_6061(),
      color=silver_machined(),
    ).with_part(hull_part),
  )
  base = base.add_body(
    @cad.BodyPart::box_mm(
      "belly_heatsink",
      body_len * 0.36,
      body_width * 0.56,
      26.0,
      z_mm=-body_height * 0.50 - 8.0,
      density=@urdf.Density::aluminum_6061(),
      color=matte_black(),
    ).with_part(trim_part),
  )
  for
    h_pos in [
      ("front_grab_handle", body_len * 0.30),
      ("rear_grab_handle", -body_len * 0.32),
    ] {
    base = base.add_body(
      @cad.BodyPart::extruded_profile_mm(
        h_pos.0,
        u_arch_profile(body_width * 0.96, 46.0, 10.0),
        12.0,
        x_mm=h_pos.1,
        z_mm=body_height * 0.44,
        rx_deg=90.0,
        rz_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=matte_black(),
      ).with_part(handle_part),
    )
  }
  let nose_x = half_len + 10.0
  base = base
    .add_body(
      @cad.BodyPart::box_mm(
        "front_sensor_cowling",
        64.0,
        94.0,
        66.0,
        x_mm=half_len - 18.0,
        z_mm=body_height * 0.28,
        density=@urdf.Density::aluminum_6061(),
        color=silver_hull(),
      ).with_part(hull_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "front_lidar_dome",
        52.0,
        30.0,
        x_mm=nose_x + 4.0,
        z_mm=body_height * 0.28,
        ry_deg=90.0,
        density=@urdf.Density::petg(),
        color=matte_black(),
      ).with_part(trim_part),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        "front_sensor_guard",
        u_arch_profile(82.0, 44.0, 8.0),
        10.0,
        x_mm=nose_x + 12.0,
        z_mm=body_height * 0.14,
        rx_deg=90.0,
        rz_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=matte_black(),
      ).with_part(handle_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "front_stereo_bar",
        10.0,
        78.0,
        14.0,
        x_mm=half_len - 2.0,
        z_mm=-body_height * 0.10,
        density=@urdf.Density::petg(),
        color=matte_black(),
      ).with_part(trim_part),
    )
  for led_y in [("left_led", 22.0), ("right_led", -22.0)] {
    base = base.add_body(
      @cad.BodyPart::box_mm(
        "front_" + led_y.0,
        6.0,
        14.0,
        10.0,
        x_mm=half_len + 2.0,
        y_mm=led_y.1,
        z_mm=body_height * 0.04,
        density=@urdf.Density::petg(),
        color=accent_blue(),
      ).with_part(trim_part),
    )
  }
  for side_spec in [("right", -1.0, accent_red()), ("left", 1.0, accent_blue())] {
    let (sname, ssign, hcolor) = side_spec
    base = base
      .add_body(
        @cad.BodyPart::box_mm(
          "\{sname}_side_panel",
          body_len * 0.34,
          6.0,
          body_height * 0.56,
          y_mm=ssign * (half_width + 1.0),
          density=@urdf.Density::petg(),
          color=dark_trim(),
        ).with_part(trim_part),
      )
      .add_body(
        @cad.BodyPart::box_mm(
          "\{sname}_carry_handle",
          body_len * 0.18,
          12.0,
          18.0,
          y_mm=ssign * (half_width + 7.0),
          density=@urdf.Density::aluminum_6061(),
          color=hcolor,
        ).with_part(handle_part),
      )
    for louver_x in [body_len * 0.22, -body_len * 0.22] {
      base = base.add_body(
        @cad.BodyPart::box_mm(
          "\{sname}_louver_\{louver_x.to_int()}",
          32.0,
          5.0,
          28.0,
          x_mm=louver_x,
          y_mm=ssign * (half_width + 1.5),
          density=@urdf.Density::petg(),
          color=dark_trim(),
        ).with_part(trim_part),
      )
    }
  }
  let controller = @components.pcb_board(
    name="main_pcb",
    length_mm=90.0,
    width_mm=65.0,
    connectors=["power", "can", "motor1", "motor2", "motor3", "motor4"],
    detail~,
  )
  base = base
    .add_mate_mm_deg("pcb_mount", z=body_height * 0.20)
    .attach(
      "pcb_merge",
      parent_mate="pcb_mount",
      controller,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  for i in 0..<4 {
    let standoff = @components.hex_standoff(
      name="pcb_standoff_\{i}",
      length_mm=8.0,
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
  let imu = @components.imu_module(name="imu")
  base = base
    .add_mate_mm_deg("imu_mount", z=body_height * 0.30)
    .attach(
      "imu_merge",
      parent_mate="imu_mount",
      imu,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  let camera = @components.camera_module(name="front_camera")
  base = base
    .add_mate_mm_deg("camera_mount", x=nose_x, z=body_height * 0.28)
    .attach(
      "camera_merge",
      parent_mate="camera_mount",
      camera,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  base
}

///|
async fn main {
  let base_spec = {
    "bodyLength": @cli.opt_double(600.0, help="Chassis length in mm"),
    "bodyWidth": @cli.opt_double(220.0, help="Central fuselage width in mm"),
    "bodyHeight": @cli.opt_double(140.0, help="Chassis height in mm"),
    "thighLength": @cli.opt_double(225.0, help="Canted thigh link length in mm"),
    "calfLength": @cli.opt_double(225.0, help="Calf link length in mm"),
    "wheelDiam": @cli.opt_double(210.0, help="Wheel outer diameter in mm"),
    "mode": @cli.opt_string(
      help="Pose preset: all-terrain, cruise, omni, or bicycle",
    ),
    "hipPitchDeg": @cli.opt_double(56.0, help="Shoulder pitch angle in deg"),
    "hipSwivelDeg": @cli.opt_double(0.0, help="Hip swivel/steer angle in deg"),
    "kneePitchDeg": @cli.opt_double(-72.0, help="Knee pitch angle in deg"),
    "wheelSpinDeg": @cli.opt_double(0.0, help="Wheel spin angle in deg"),
    "foot": @cli.flag(help="Build rubber feet instead of driven wheels"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="05-galileo-quadruped",
      description="Galileo X adaptive wheel-legged quadruped robot.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let body_len = args.double("bodyLength")
  let body_width = args.double("bodyWidth")
  let body_height = args.double("bodyHeight")
  let thigh_len = args.double("thighLength")
  let calf_len = args.double("calfLength")
  let wheel_diam = args.double("wheelDiam")
  let wheeled = !args.flag("foot")
  let mode = args.string_opt("mode").unwrap_or("all-terrain")
  let (mode_pitch, mode_swivel, mode_knee) = mode_pose_defaults(mode)
  let has_custom_pose = args.string_opt("mode") is Some(_)
  let hip_pitch_deg = if has_custom_pose {
    mode_pitch
  } else {
    args.double("hipPitchDeg")
  }
  let hip_swivel_deg = if has_custom_pose {
    mode_swivel
  } else {
    args.double("hipSwivelDeg")
  }
  let knee_pitch_deg = if has_custom_pose {
    mode_knee
  } else {
    args.double("kneePitchDeg")
  }
  let leg_effort = 90.0
  let leg_velocity = 18.0
  let mut base = build_galileo_chassis(
    body_len, body_width, body_height, detail,
  )
  let shoulder_x = body_len * 0.37
  // Shoulder pod half-width is body_width * 0.62; mount actuator stator flush outboard.
  let shoulder_y = body_width * 0.62 + 0.5
  let corners : Array[(String, Double, Double, Bool, Bool)] = [
    ("fl", shoulder_x, shoulder_y, true, true),
    ("fr", shoulder_x, -shoulder_y, false, true),
    ("rl", -shoulder_x, shoulder_y, true, false),
    ("rr", -shoulder_x, -shoulder_y, false, false),
  ]
  for corner in corners {
    let (prefix, x, y, is_left, is_front) = corner
    let sign = if is_left { 1.0 } else { -1.0 }
    base = base.add_mate_mm_deg(
      "\{prefix}_shoulder_mount",
      x~,
      y~,
      rx_deg=if is_left { -90.0 } else { 90.0 },
      axis=(0.0, sign, 0.0),
    )
    let leg = galileo_x_leg(
      prefix,
      is_left~,
      is_front~,
      thigh_len~,
      calf_len~,
      wheel_diam~,
      max_effort_nm=leg_effort,
      max_vel_rad_s=leg_velocity,
      wheeled~,
      detail~,
    )
    base = base.attach(
      "\{prefix}_leg_mount",
      parent_mate="\{prefix}_shoulder_mount",
      leg,
      child_mate="motor_mount",
      spec=@cad.JointSpec::fixed(),
    )
  }
  let trunk = @cad.CableRoute::new(
    "trunk_harness",
    points=[
      (0.0, 0.0, body_height * 0.25),
      (-body_len * 0.22, 0.0, body_height * 0.25),
      (-shoulder_x, shoulder_y * 0.5, 0.0),
    ],
    jacket_diameter_mm=12.0,
    wire_names=["rl_can"],
    material="PVC",
    from_component="base_link",
    from_port="can",
    to_component="rl_hip_pitch_drive",
    to_port="can",
  )
  base = base.add_cable_route(trunk)
  for prefix in ["fl", "fr", "rl", "rr"] {
    base = base
      .add_wire_run(
        @cad.WireRun::new(
          "\{prefix}_can",
          from_component="base_link",
          from_port="can",
          to_component="\{prefix}_hip_pitch_drive",
          to_port="can",
          gauge_awg=24,
          length_mm=600.0,
        ),
      )
      .add_wire_run(
        @cad.WireRun::new(
          "\{prefix}_power",
          from_component="base_link",
          from_port="power",
          to_component="\{prefix}_hip_pitch_drive",
          to_port="power",
          gauge_awg=16,
          length_mm=500.0,
        ),
      )
  }
  let joint_names : Array[String] = [
    "hip_pitch_joint", "hip_swivel_joint", "knee_joint", "wheel_joint",
  ]
  let actuator_suffixes : Array[String] = [
    "_hip_pitch_drive", "_hip_swivel_drive", "_knee_drive", "_wheel_drive",
  ]
  let mut channel = 1
  let dof = if wheeled { 4 } else { 3 }
  for prefix in ["fl", "fr", "rl", "rr"] {
    let side = if prefix == "fl" || prefix == "rl" { 1.0 } else { -1.0 }
    for i in 0..<dof {
      base = base.add_control_binding(
        @cad.ControlBinding::new(
          "\{prefix}_\{joint_names[i]}",
          actuator="\{prefix}\{actuator_suffixes[i]}",
          channel="can0:" + channel.to_string(),
          direction=if side > 0.0 || i == 1 { "normal" } else { "inverted" },
          gear_ratio=if i == 3 { 1.0 } else { 9.0 },
        ),
      )
      channel = channel + 1
    }
  }
  let deg = @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  for prefix in ["fl", "fr", "rl", "rr"] {
    let is_front = prefix == "fl" || prefix == "fr"
    let side = if prefix == "fl" || prefix == "rl" { 1.0 } else { -1.0 }
    let front_sign = if is_front { 1.0 } else { -1.0 }
    // Front thighs cant +40 deg (swing back when pitch > 0); rear thighs cant -40 deg
    // (swing forward when pitch < 0), and knees bend opposite fore-to-aft so all
    // four wheels sit symmetrically on the ground plane.
    let pitch_val = if mode == "cruise" || mode == "all-terrain" {
      hip_pitch_deg * front_sign
    } else {
      hip_pitch_deg
    }
    let swivel_val = -hip_swivel_deg * side * front_sign
    let knee_val = knee_pitch_deg * front_sign
    positions.set("\{prefix}_hip_pitch_joint", pitch_val * deg * side)
    positions.set("\{prefix}_hip_swivel_joint", swivel_val * deg)
    positions.set("\{prefix}_knee_joint", knee_val * deg * side)
    if wheeled {
      positions.set(
        "\{prefix}_wheel_joint",
        args.double("wheelSpinDeg") * deg * side,
      )
    }
  }
  @common.write_output(base, output, joint_positions=positions)
}
