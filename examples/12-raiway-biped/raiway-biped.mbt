///|
/// 12-raiway-biped — KAIST RAIWAY-inspired Large-Wheeled Bipedal Robot
/// built around six A12 8318 100KV brushless motors with purpose-matched
/// 4-elbow print-in-place herringbone planetary gearboxes and 20-inch wheels.
///
/// Exact dimensions from `raiway-large-wheel-robot.png` (KAIST RAI Lab):
/// - Total standing height: `1,140 mm` (ground plane `z = 0` to torso top)
/// - Vertical electronics torso height: `488 mm` (houses PC, Powerboard,
///   Battery, and 6-DoF IMU)
/// - Wheel radius: `254 mm` (`Ø508 mm` / 20-inch spoked bicycle wheel with
///   knobby tire and internal red foam insert)
/// - Wheel track width (center-to-center): `586 mm` (`y = ±293 mm`)
/// - Upper leg (thigh + four-bar parallel link): `320 mm`
/// - Lower leg (shin / calf): `320 mm`
///
/// Six A12 8318 100KV actuators (3 per leg):
/// - 2x Hip + 2x Knee (coaxial at the hip, knee drives shin via 4-bar link):
///   `6.0:1` high-torque 4-elbow herringbone planetary (`m=2.0`, `12/24/60`,
///   `L=14 mm`) for climbing 150 mm stairs.
/// - 2x Wheel (at bottom of each shin with bolted Wheel Hub adapter):
///   `4.0:1` high-speed, low-inertia 4-elbow herringbone planetary (`m=2.0`,
///   `20/20/60`, `L=12 mm`) for fast rolling and contact-informed blind
///   locomotion.

///|
fn alu_silver() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.78, 0.80, 0.84)
}

///|
fn raiway_blue() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.24, 0.38, 0.68)
}

///|
fn dark_matte() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.11, 0.12, 0.14)
}

///|
fn frame_charcoal() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.20, 0.22, 0.26)
}

///|
fn steel_grey() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.72, 0.75, 0.79)
}

///|
fn foam_red() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.78, 0.16, 0.16)
}

///|
fn battery_slate() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.26, 0.29, 0.34)
}

///|
fn pcb_green() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.10, 0.48, 0.24)
}

///|
fn imu_orange() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.92, 0.42, 0.12)
}

///|
fn raiway_printed(
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
fn raiway_purchased(
  part_number : String,
  description : String,
  material : String,
  cost_usd : Double,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="generic",
    material~,
    process="purchased",
    unit_cost_usd=cost_usd,
  )
}

///|
/// Master parameter bundle for the RAIWAY large-wheeled bipedal robot.
pub(all) struct RaiwayParams {
  total_height_mm : Double
  torso_height_mm : Double
  torso_width_mm : Double
  torso_depth_mm : Double
  thigh_len_mm : Double
  shin_len_mm : Double
  wheel_radius_mm : Double
  wheel_width_mm : Double
  track_width_mm : Double
  hip_gear_module_mm : Double
  hip_gear_length_mm : Double
  wheel_gear_module_mm : Double
  wheel_gear_length_mm : Double
  num_elbows : Int32
  tolerance_mm : Double
  detail : @step_common.DetailLevel
}

///|
/// Builds validated RAIWAY parameters defaulting to the exact dimensions shown
/// in `raiway-large-wheel-robot.png`.
pub fn RaiwayParams::new(
  total_height_mm~ : Double = 1140.0,
  torso_height_mm~ : Double = 488.0,
  torso_width_mm~ : Double = 260.0,
  torso_depth_mm~ : Double = 180.0,
  thigh_len_mm~ : Double = 320.0,
  shin_len_mm~ : Double = 320.0,
  wheel_radius_mm~ : Double = 254.0,
  wheel_width_mm~ : Double = 52.0,
  track_width_mm~ : Double = 586.0,
  hip_gear_module_mm~ : Double = 2.0,
  hip_gear_length_mm~ : Double = 14.0,
  wheel_gear_module_mm~ : Double = 2.0,
  wheel_gear_length_mm~ : Double = 12.0,
  num_elbows~ : Int32 = 4,
  tolerance_mm~ : Double = @step_common.DEFAULT_GEAR_TOLERANCE_MM,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> RaiwayParams {
  {
    total_height_mm,
    torso_height_mm,
    torso_width_mm,
    torso_depth_mm,
    thigh_len_mm,
    shin_len_mm,
    wheel_radius_mm,
    wheel_width_mm,
    track_width_mm,
    hip_gear_module_mm,
    hip_gear_length_mm,
    wheel_gear_module_mm,
    wheel_gear_length_mm,
    num_elbows,
    tolerance_mm,
    detail,
  }
}

///|
/// High-torque 6.0:1 A12 actuator parameters for Hip and Knee joints
/// (`z_sun=12`, `z_planet=24`, `z_ring=60`, 4 planets, `m=2.0`, `L=14 mm`).
pub fn hip_knee_actuator_params(
  params : RaiwayParams,
  name : String,
) -> @components.A12ActuatorParams {
  @components.A12ActuatorParams::new(
    gear_module_mm=params.hip_gear_module_mm,
    gear_length_mm=params.hip_gear_length_mm,
    num_elbows=params.num_elbows,
    tolerance_mm=params.tolerance_mm,
    hub_offset_mm=8.0,
    detail=params.detail,
    sun_teeth=12,
    planet_teeth=24,
    planet_count=4,
    name~,
  )
}

///|
/// High-speed, backdrivable 4.0:1 A12 actuator parameters for the 20-inch
/// Wheel joints (`z_sun=20`, `z_planet=20`, `z_ring=60`, 4 planets, `m=2.0`,
/// `L=12 mm`) with 3-bolt wheel-hub interface. Shares the exact same 60-tooth
/// outer housing envelope and FR8-2RS planet bearings as the 6.0:1 hip/knee
/// gearbox.
pub fn wheel_actuator_params(
  params : RaiwayParams,
  name : String,
) -> @components.A12ActuatorParams {
  @components.A12ActuatorParams::new(
    gear_module_mm=params.wheel_gear_module_mm,
    gear_length_mm=params.wheel_gear_length_mm,
    num_elbows=params.num_elbows,
    tolerance_mm=params.tolerance_mm,
    hub_offset_mm=10.0,
    detail=params.detail,
    sun_teeth=20,
    planet_teeth=20,
    planet_count=4,
    name~,
    tire_mount_bcd_mm=55.85,
    tire_mount_bolt_count=3,
    tire_mount_phase_deg=30.0,
    tire_mount_hole_diam_mm=6.0,
  )
}

///|
/// Solved 2-link leg pitch angles (in radians) for a desired vertical drop `dz`
/// from hip pivot to wheel axle.
pub(all) struct LegIK {
  hip_rad : Double
  knee_rad : Double
  vertical_drop_mm : Double
  knee_offset_x_mm : Double
}

///|
/// Closed-form 2-link IK placing the wheel axle directly beneath the hip pivot
/// (`dx = 0`) at vertical drop `dz_mm` (`thigh_len_mm` + `shin_len_mm`).
pub fn solve_leg_ik(params : RaiwayParams, dz_mm : Double) -> LegIK {
  let l1 = params.thigh_len_mm
  let l2 = params.shin_len_mm
  let min_dz = (l1 - l2).abs() + 20.0
  let max_dz = l1 + l2 - 10.0
  let dz = if dz_mm < min_dz {
    min_dz
  } else if dz_mm > max_dz {
    max_dz
  } else {
    dz_mm
  }
  let cos_a = (l1 * l1 + dz * dz - l2 * l2) / (2.0 * l1 * dz)
  let clamped_a = if cos_a > 1.0 {
    1.0
  } else if cos_a < -1.0 {
    -1.0
  } else {
    cos_a
  }
  let alpha = @math.acos(clamped_a)
  let cos_g = (l1 * l1 + l2 * l2 - dz * dz) / (2.0 * l1 * l2)
  let clamped_g = if cos_g > 1.0 {
    1.0
  } else if cos_g < -1.0 {
    -1.0
  } else {
    cos_g
  }
  let gamma = @math.acos(clamped_g)
  // Hip swings rearward (-X) by `alpha` from straight down (-Z); knee folds
  // forward (+X) by `pi - gamma` so the wheel axle lands directly under the hip.
  let hip_rad = alpha
  let knee_rad = -(@math.PI - gamma)
  let knee_x = -l1 * @math.sin(alpha)
  { hip_rad, knee_rad, vertical_drop_mm: dz, knee_offset_x_mm: knee_x, }
}

///|
/// Vertical clearance in mm from the coaxial hip/knee actuator centerline up to
/// the bottom plate of the 488 mm vertical electronics torso box. The 6:1 A12
/// actuator flange has outer radius ~73.5 mm, so 74 mm places the pods cleanly
/// underneath the torso base plate (just like `raiway-large-wheel-robot.png`)
/// with zero self-intersection.
pub const HIP_POD_DROP_MM : Double = 74.0

///|
/// Hip pivot height in mm so that
/// `z_hip + HIP_POD_DROP_MM + torso_height_mm == total_height_mm`
/// (`1140 - 488 - 74 = 578 mm` at the default dimensions).
pub fn standing_hip_z_mm(params : RaiwayParams) -> Double {
  params.total_height_mm - params.torso_height_mm - HIP_POD_DROP_MM
}

///|
/// Standing vertical drop from hip pivot to wheel axle (`578 - 254 = 324 mm`).
pub fn standing_leg_drop_mm(params : RaiwayParams) -> Double {
  standing_hip_z_mm(params) - params.wheel_radius_mm
}

///|
fn joint_limit_leg() -> @urdf.JointLimit {
  @urdf.JointLimit::new(
    effort=35.0,
    velocity=12.0,
    lower=Some(-2.4),
    upper=Some(2.4),
  )
}

///|
fn build_torso_enclosure(params : RaiwayParams) -> @cad.Component {
  let w = params.torso_width_mm
  let d = params.torso_depth_mm
  let h = params.torso_height_mm
  let z0 = HIP_POD_DROP_MM // Torso box starts above the coaxial hip/knee pods
  let wall = 8.0
  let plate_t = 10.0
  let post_w = 18.0
  let post_h = h - 2.0 * plate_t
  let post_x = d / 2.0 - post_w / 2.0
  let post_y = w / 2.0 - post_w / 2.0
  let post_z = z0 + plate_t + post_h / 2.0
  let saddle_y = 120.0
  let saddle_t = 12.0
  let saddle_h = z0 + 24.0

  let mut torso = @cad.Component::new("torso")
    .add_mate_mm_deg("origin")
    // Left & right structural hip saddle brackets dropping from torso base
    // down to the coaxial hip/knee actuator axis (`z = 0`).
    .add_body(
      @cad.BodyPart::box_mm(
        "hip_saddle_left",
        136.0,
        saddle_t,
        saddle_h,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        y_mm=saddle_y,
        z_mm=z0 - saddle_h / 2.0,
      ).with_part(
        raiway_printed(
          "RAIWAY-HIP-SADDLE", "CNC/printed hip saddle plate mounting coaxial hip & knee A12 pods under torso",
          "Aluminum 6061 / PETG-CF", 18.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "hip_saddle_right",
        136.0,
        saddle_t,
        saddle_h,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        y_mm=-saddle_y,
        z_mm=z0 - saddle_h / 2.0,
      ).with_part(
        raiway_printed(
          "RAIWAY-HIP-SADDLE", "CNC/printed hip saddle plate mounting coaxial hip & knee A12 pods under torso",
          "Aluminum 6061 / PETG-CF", 18.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_base",
        d,
        w,
        plate_t,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        z_mm=z0 + plate_t / 2.0,
      ).with_part(
        raiway_printed(
          "RAIWAY-TORSO-BASE", "Machined/printed torso bottom bulkhead bridging hip/knee coaxial pods",
          "Aluminum 6061 / PETG-CF", 24.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_top",
        d,
        w,
        plate_t,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        z_mm=z0 + h - plate_t / 2.0,
      ).with_part(
        raiway_printed(
          "RAIWAY-TORSO-TOP", "Torso top plate with carrying handle bosses", "Aluminum 6061 / PETG-CF",
          18.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "torso_back",
        wall,
        w - 2.0 * wall,
        post_h,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        x_mm=-d / 2.0 + wall / 2.0,
        z_mm=post_z,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "post_fl",
        post_w,
        post_w,
        post_h,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        x_mm=post_x,
        y_mm=post_y,
        z_mm=post_z,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "post_fr",
        post_w,
        post_w,
        post_h,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        x_mm=post_x,
        y_mm=-post_y,
        z_mm=post_z,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "post_rl",
        post_w,
        post_w,
        post_h,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        x_mm=-post_x,
        y_mm=post_y,
        z_mm=post_z,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "post_rr",
        post_w,
        post_w,
        post_h,
        density=@urdf.Density::aluminum_6061(),
        color=alu_silver(),
        x_mm=-post_x,
        y_mm=-post_y,
        z_mm=post_z,
      ),
    )
    // Internal electronics matching the PNG callouts (Battery, IMU, Powerboard, PC)
    .add_body(
      @cad.BodyPart::box_mm(
        "battery_pack",
        d - 42.0,
        w - 48.0,
        150.0,
        density=@urdf.Density::petg(),
        color=battery_slate(),
        x_mm=-6.0,
        z_mm=z0 + plate_t + 101.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-BATTERY-12S", "12S LiPo / Li-Ion high-discharge robot battery pack",
          "LiPo", 185.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "imu_module",
        40.0,
        40.0,
        18.0,
        density=@urdf.Density::petg(),
        color=imu_orange(),
        x_mm=d / 2.0 - 34.0,
        z_mm=z0 + plate_t + 15.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-IMU-6DOF", "6-DoF high-rate IMU for contact-informed blind locomotion",
          "PCB/Aluminum", 45.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "powerboard",
        22.0,
        w - 70.0,
        120.0,
        density=@urdf.Density::petg(),
        color=pcb_green(),
        x_mm=-d / 2.0 + 28.0,
        z_mm=z0 + plate_t + 250.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-POWERBOARD", "High-current power distribution & CAN-FD bus board",
          "FR4 PCB", 65.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "onboard_pc",
        52.0,
        w - 64.0,
        140.0,
        density=@urdf.Density::aluminum_6061(),
        color=frame_charcoal(),
        x_mm=-d / 2.0 + 44.0,
        z_mm=z0 + plate_t + 392.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-ONBOARD-PC", "Compact x86/ARM real-time RL policy computer", "Aluminum/Electronics",
          320.0,
        ),
      ),
    )

  let rib_h = 12.0
  for i in 0..<4 {
    let rz = plate_t + 90.0 + i.to_double() * 95.0
    if rz + rib_h < h - plate_t {
      torso = torso
        .add_body(
          @cad.BodyPart::box_mm(
            "side_rib_l_\{i}",
            d - 2.0 * post_w,
            wall,
            rib_h,
            density=@urdf.Density::aluminum_6061(),
            color=alu_silver(),
            y_mm=w / 2.0 - wall / 2.0,
            z_mm=z0 + rz,
          ),
        )
        .add_body(
          @cad.BodyPart::box_mm(
            "side_rib_r_\{i}",
            d - 2.0 * post_w,
            wall,
            rib_h,
            density=@urdf.Density::aluminum_6061(),
            color=alu_silver(),
            y_mm=-(w / 2.0 - wall / 2.0),
            z_mm=z0 + rz,
          ),
        )
    }
  }
  torso
}

///|
/// Builds the 320 mm thigh + parallel four-bar link assembly.
/// Local origin is the hip pivot; the link extends along `-Z` to `z = -thigh_len_mm`.
fn build_thigh(params : RaiwayParams, side : String) -> @cad.Component {
  let l = params.thigh_len_mm
  let beam_x = 46.0
  let beam_y = 24.0
  let sign = if side == "left" { 1.0 } else { -1.0 }
  @cad.Component::new("thigh_\{side}")
  .add_mate_mm_deg("origin", axis=(0.0, 1.0, 0.0))
  .add_mate_mm_deg("knee", x=0.0, y=0.0, z=-l, axis=(0.0, 1.0, 0.0))
  .add_body(
    @cad.BodyPart::box_mm(
      "thigh_strut_\{side}",
      beam_x,
      beam_y,
      l,
      density=@urdf.Density::petg(),
      color=raiway_blue(),
      z_mm=-l / 2.0,
    ).with_part(
      raiway_printed(
        "RAIWAY-THIGH-320", "320 mm upper leg thigh link bridging coaxial hip/knee pod to knee pivot",
        "PETG-CF", 18.0,
      ),
    ),
  )
  .add_body(
    @cad.BodyPart::box_mm(
      "four_bar_link_\{side}",
      18.0,
      12.0,
      l - 12.0,
      density=@urdf.Density::aluminum_6061(),
      color=dark_matte(),
      x_mm=34.0,
      y_mm=sign * (beam_y / 2.0 + 10.0),
      z_mm=-l / 2.0,
    ).with_part(
      raiway_printed(
        "RAIWAY-FOUR-BAR-LINK", "Parallel four-bar knee transmission link driven by coaxial knee actuator",
        "Aluminum 6061 / Carbon", 14.0,
      ),
    ),
  )
  .add_body(
    @cad.BodyPart::cylinder_mm(
      "thigh_hip_boss_\{side}",
      68.0,
      beam_y + 8.0,
      density=@urdf.Density::petg(),
      color=raiway_blue(),
      rx_deg=90.0,
    ),
  )
  .add_body(
    @cad.BodyPart::cylinder_mm(
      "thigh_knee_boss_\{side}",
      56.0,
      beam_y + 8.0,
      density=@urdf.Density::petg(),
      color=raiway_blue(),
      z_mm=-l,
      rx_deg=90.0,
    ),
  )
}

///|
/// Builds the 320 mm lower leg (shin) terminating in the Wheel Actuator mount.
/// Local origin is the knee pivot; the shin extends along `-Z` to `z = -shin_len_mm`.
fn build_shin(
  params : RaiwayParams,
  side : String,
  wheel_act : @cad.Component,
) -> @cad.Component {
  let l = params.shin_len_mm
  let beam_x = 42.0
  let beam_y = 22.0
  let sign = if side == "left" { 1.0 } else { -1.0 }
  let act_rx = if side == "left" { -90.0 } else { 90.0 }
  let wheel_y_offset = sign * 68.0

  @cad.Component::new("shin_\{side}")
  .add_mate_mm_deg("origin", axis=(0.0, 1.0, 0.0))
  .add_mate_mm_deg(
    "wheel_act_mount",
    x=0.0,
    y=-sign * 86.0,
    z=-l,
    rx_deg=act_rx,
  )
  .add_mate_mm_deg(
    "wheel_axle",
    x=0.0,
    y=wheel_y_offset,
    z=-l,
    axis=(0.0, 1.0, 0.0),
  )
  .add_body(
    @cad.BodyPart::box_mm(
      "shin_strut_\{side}",
      beam_x,
      beam_y,
      l,
      density=@urdf.Density::petg(),
      color=dark_matte(),
      z_mm=-l / 2.0,
    ).with_part(
      raiway_printed(
        "RAIWAY-SHIN-320", "320 mm lower leg shin strut with integrated A12 wheel actuator clevis",
        "PETG-CF", 18.0,
      ),
    ),
  )
  .add_body(
    @cad.BodyPart::cylinder_mm(
      "shin_knee_clevis_\{side}",
      52.0,
      beam_y + 12.0,
      density=@urdf.Density::petg(),
      color=frame_charcoal(),
      rx_deg=90.0,
    ),
  )
  .add_body(
    @cad.BodyPart::cylinder_mm(
      "wheel_hub_adapter_\{side}",
      72.0,
      62.0,
      density=@urdf.Density::aluminum_6061(),
      color=alu_silver(),
      y_mm=sign * 37.0,
      z_mm=-l,
      rx_deg=90.0,
    ).with_part(
      raiway_printed(
        "RAIWAY-WHEEL-HUB-ADAPTER", "Bolted hub adapter coupling A12 4:1 output flange to 20-inch bicycle hub",
        "Aluminum 6061 / PETG-CF", 16.0,
      ),
    ),
  )
  .attach(
    "wheel_actuator_\{side}",
    parent_mate="wheel_act_mount",
    wheel_act,
    child_mate="origin",
  )
}

///|
/// Builds the 20-inch (`R = 254 mm`, `OD = 508 mm`) spoked wheel assembly
/// with knobby tire, internal red foam insert, rim, 16 steel spokes, and hub.
/// Wheel spin axis is `+Y` (local origin at hub center).
fn build_large_wheel(params : RaiwayParams, side : String) -> @cad.Component {
  let r_outer = params.wheel_radius_mm // 254.0 mm exact from PNG
  let width = params.wheel_width_mm // 52.0 mm tire width
  let r_rim_outer = r_outer - 34.0 // 220.0 mm
  let r_rim_inner = r_rim_outer - 18.0 // 202.0 mm (20" ETRTO 406 rim)
  let r_hub = 32.0

  let mut wheel = @cad.Component::new("wheel_\{side}")
    .add_mate_mm_deg("origin", axis=(0.0, 1.0, 0.0))
    .add_body(
      @cad.BodyPart::tube_mm(
        "tire_20in_\{side}",
        2.0 * r_outer,
        2.0 * (r_rim_outer - 4.0),
        width,
        density=@urdf.Density::rubber(),
        color=dark_matte(),
        rx_deg=90.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-TIRE-20X2.1", "20-inch (OD 508 mm, R=254 mm) knobby bicycle tire",
          "Rubber", 28.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        "foam_insert_\{side}",
        2.0 * (r_outer - 10.0),
        2.0 * (r_rim_outer + 2.0),
        width - 14.0,
        density=@urdf.Density::rubber(),
        color=foam_red(),
        rx_deg=90.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-FOAM-INSERT-20", "20-inch closed-cell run-flat foam tire insert for impact damping",
          "EVA/PE Foam", 22.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        "rim_20in_\{side}",
        2.0 * r_rim_outer,
        2.0 * r_rim_inner,
        width - 12.0,
        density=@urdf.Density::aluminum_6061(),
        color=frame_charcoal(),
        rx_deg=90.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-RIM-20IN", "20-inch (ETRTO 406) double-wall aluminum bicycle rim",
          "Aluminum 6061", 32.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "wheel_hub_\{side}",
        2.0 * r_hub,
        width + 24.0,
        density=@urdf.Density::aluminum_6061(),
        color=dark_matte(),
        rx_deg=90.0,
      ).with_part(
        raiway_purchased(
          "RAIWAY-HUB-20IN", "Bicycle wheel hub mated to A12 4:1 wheel actuator flange",
          "Aluminum/Steel", 24.0,
        ),
      ),
    )

  let spoke_len = r_rim_inner - r_hub + 6.0
  let spoke_mid_r = (r_hub + r_rim_inner) / 2.0
  let num_spokes = 16
  for i in 0..<num_spokes {
    let ang_deg = i.to_double() * (360.0 / num_spokes.to_double())
    let ang_rad = ang_deg * @math.PI / 180.0
    let y_off = if i % 2 == 0 { 10.0 } else { -10.0 }
    wheel = wheel.add_body(
      @cad.BodyPart::cylinder_mm(
        "spoke_\{side}_\{i}",
        3.6,
        spoke_len,
        density=@urdf.Density::steel(),
        color=steel_grey(),
        x_mm=spoke_mid_r * @math.sin(ang_rad),
        y_mm=y_off,
        z_mm=spoke_mid_r * @math.cos(ang_rad),
        ry_deg=ang_deg,
      ),
    )
  }
  wheel
}

///|
/// Builds the complete RAIWAY large-wheeled bipedal robot assembly.
pub fn build_raiway(
  params~ : RaiwayParams = RaiwayParams::new(),
) -> @cad.Component {
  let torso = build_torso_enclosure(params)

  let hip_l_act = @components.a12_planetary_actuator(
    hip_knee_actuator_params(params, "hip_act_left"),
  )
  let knee_l_act = @components.a12_planetary_actuator(
    hip_knee_actuator_params(params, "knee_act_left"),
  )
  let hip_r_act = @components.a12_planetary_actuator(
    hip_knee_actuator_params(params, "hip_act_right"),
  )
  let knee_r_act = @components.a12_planetary_actuator(
    hip_knee_actuator_params(params, "knee_act_right"),
  )
  let wheel_l_act = @components.a12_planetary_actuator(
    wheel_actuator_params(params, "wheel_act_left"),
  )
  let wheel_r_act = @components.a12_planetary_actuator(
    wheel_actuator_params(params, "wheel_act_right"),
  )

  // Place leg centerline at `y = ±225 mm` so wheel centers sit at exact track
  // width `±293 mm` (`track_width_mm = 586 mm`), accounting for shin-to-wheel
  // Y offset (`68 mm`). Coaxial Hip (+Y) and Knee (-Y) actuators bolt
  // back-to-back onto the aluminum hip saddle plates at `y = ±120 mm` directly
  // underneath the torso base plate (`z = +74 mm`), so the hip actuator output
  // hub (`y = ±219 mm`) mates directly into the thigh hip boss (`y = ±225 mm`)
  // with zero self-intersection.
  let shin_to_wheel_y = 68.0
  let leg_plane_y = params.track_width_mm / 2.0 - shin_to_wheel_y

  let thigh_l = build_thigh(params, "left")
  let shin_l = build_shin(params, "left", wheel_l_act)
  let wheel_l = build_large_wheel(params, "left")

  let thigh_r = build_thigh(params, "right")
  let shin_r = build_shin(params, "right", wheel_r_act)
  let wheel_r = build_large_wheel(params, "right")

  let hip_z = standing_hip_z_mm(params)
  let torso_with_pods = torso
    .add_mate_mm_deg(
      "leg_hip_left",
      x=0.0,
      y=leg_plane_y,
      z=0.0,
      axis=(0.0, 1.0, 0.0),
    )
    .add_mate_mm_deg(
      "leg_hip_right",
      x=0.0,
      y=-leg_plane_y,
      z=0.0,
      axis=(0.0, 1.0, 0.0),
    )
    .add_mate_mm_deg("hip_act_l_m", x=0.0, y=126.0, z=0.0, rx_deg=-90.0)
    .add_mate_mm_deg("knee_act_l_m", x=0.0, y=114.0, z=0.0, rx_deg=90.0)
    .add_mate_mm_deg("hip_act_r_m", x=0.0, y=-126.0, z=0.0, rx_deg=90.0)
    .add_mate_mm_deg("knee_act_r_m", x=0.0, y=-114.0, z=0.0, rx_deg=-90.0)
    .attach(
      "hip_act_left",
      parent_mate="hip_act_l_m",
      hip_l_act,
      child_mate="origin",
    )
    .attach(
      "knee_act_left",
      parent_mate="knee_act_l_m",
      knee_l_act,
      child_mate="origin",
    )
    .attach(
      "hip_act_right",
      parent_mate="hip_act_r_m",
      hip_r_act,
      child_mate="origin",
    )
    .attach(
      "knee_act_right",
      parent_mate="knee_act_r_m",
      knee_r_act,
      child_mate="origin",
    )

  let shin_l_full = shin_l.attach(
    "wheel_left",
    parent_mate="wheel_axle",
    wheel_l,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(),
  )
  let leg_l = thigh_l.attach(
    "knee_left",
    parent_mate="knee",
    shin_l_full,
    child_mate="origin",
    spec=@cad.JointSpec::revolute(joint_limit_leg()),
  )
  let shin_r_full = shin_r.attach(
    "wheel_right",
    parent_mate="wheel_axle",
    wheel_r,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(),
  )
  let leg_r = thigh_r.attach(
    "knee_right",
    parent_mate="knee",
    shin_r_full,
    child_mate="origin",
    spec=@cad.JointSpec::revolute(joint_limit_leg()),
  )
  let torso_full = torso_with_pods
    .attach(
      "hip_left",
      parent_mate="leg_hip_left",
      leg_l,
      child_mate="origin",
      spec=@cad.JointSpec::revolute(joint_limit_leg()),
    )
    .attach(
      "hip_right",
      parent_mate="leg_hip_right",
      leg_r,
      child_mate="origin",
      spec=@cad.JointSpec::revolute(joint_limit_leg()),
    )

  @cad.Component::new("raiway_biped")
  .with_param("total_height_mm", params.total_height_mm.to_string())
  .with_param("torso_height_mm", params.torso_height_mm.to_string())
  .with_param("thigh_len_mm", params.thigh_len_mm.to_string())
  .with_param("shin_len_mm", params.shin_len_mm.to_string())
  .with_param("wheel_radius_mm", params.wheel_radius_mm.to_string())
  .with_param("wheel_diam_mm", (params.wheel_radius_mm * 2.0).to_string())
  .with_param("track_width_mm", params.track_width_mm.to_string())
  .with_param("hip_knee_gear_ratio", "6.0:1 (12/24/60, m=2.0, L=14mm)")
  .with_param("wheel_gear_ratio", "4.0:1 (20/20/60, m=2.0, L=12mm)")
  .with_param("num_elbows", params.num_elbows.to_string())
  .with_param("tolerance_mm", params.tolerance_mm.to_string())
  .add_mate_mm_deg("torso_mount", x=0.0, y=0.0, z=hip_z)
  .attach("torso", parent_mate="torso_mount", torso_full)
}

///|
/// Computes joint angles for named poses: `standing` (exact 1,140 mm height),
/// `crouched` (low stance), `tall` (extended legs), or `stair` (asymmetric
/// 150 mm step climb matching the KAIST stair-climbing demo).
pub fn pose_positions(
  params : RaiwayParams,
  pose~ : String = "standing",
  wheel_spin_deg~ : Double = 0.0,
) -> Map[String, Double] {
  let stand_dz = standing_leg_drop_mm(params)
  let (dz_l, dz_r) = match pose {
    "crouched" => (stand_dz - 120.0, stand_dz - 120.0)
    "tall" => (stand_dz + 140.0, stand_dz + 140.0)
    "stair" => (stand_dz - 150.0, stand_dz)
    _ => (stand_dz, stand_dz)
  }
  let ik_l = solve_leg_ik(params, dz_l)
  let ik_r = solve_leg_ik(params, dz_r)
  let spin = wheel_spin_deg * @math.PI / 180.0
  let pos : Map[String, Double] = Map([])
  pos.set("hip_left", ik_l.hip_rad)
  pos.set("knee_left", ik_l.knee_rad)
  pos.set("wheel_left", spin)
  pos.set("hip_right", ik_r.hip_rad)
  pos.set("knee_right", ik_r.knee_rad)
  pos.set("wheel_right", spin)
  pos
}

///|
/// Builds a flat print-in-place 4-elbow herringbone planetary cartridge for
/// either the 6:1 hip/knee actuator or the 4:1 wheel actuator.
fn build_gear_cartridge(
  act : @components.A12ActuatorParams,
) -> @step_common.Component {
  let bearing = @components.flanged_bearing_fr8_2rs()
  let gp = @step_planetary.HerringbonePlanetaryParams::new(
    module_mm=act.gear_module_mm,
    gear_length_mm=act.gear_length_mm,
    helix_angle_deg=30.0,
    pressure_angle_deg=20.0,
    num_elbows=act.num_elbows,
    resolution=7,
    hole_type="Circular",
    sun_hole_type="Hexagonal",
    hole_radius_mm=3.5,
    sun_hole_radius_mm=3.5,
    planet_hole_radius_mm=bearing.outer_mm / 2.0 - 0.03,
    tolerance_mm=act.tolerance_mm,
    outer_thickness_mm=6.0,
    sun_teeth=act.sun_teeth,
    planet_count=act.planet_count,
    planet_teeth=act.planet_teeth,
  ).unwrap()
  @step_planetary.herringbone_planetary_gearbox(gp).unwrap()
}

///|
/// CLI entry point for `examples/12-raiway-biped`.
pub async fn run_cli() -> Unit {
  let base_spec = {
    "totalHeight": @cli.opt_double(
      1140.0,
      help="Total standing height in mm (default 1140.0)",
    ),
    "torsoHeight": @cli.opt_double(
      488.0,
      help="Torso electronics box height in mm (default 488.0)",
    ),
    "thighLength": @cli.opt_double(
      320.0,
      help="Upper leg (thigh / 4-bar) length in mm (default 320.0)",
    ),
    "shinLength": @cli.opt_double(
      320.0,
      help="Lower leg (shin) length in mm (default 320.0)",
    ),
    "wheelRadius": @cli.opt_double(
      254.0,
      help="Large wheel outer radius in mm (default 254.0 = 20-inch OD 508 mm)",
    ),
    "trackWidth": @cli.opt_double(
      586.0,
      help="Center-to-center wheel track width in mm (default 586.0)",
    ),
    "numElbows": @cli.opt_int(
      4,
      help="Herringbone elbow count per planetary gear (default 4)",
    ),
    "tolerance": @cli.opt_double(
      @step_common.DEFAULT_GEAR_TOLERANCE_MM,
      help="3D-printing tooth flank clearance in mm",
    ),
    "pose": @cli.opt_string(
      help="Pose preset: standing (default), crouched, tall, or stair",
    ),
    "wheelSpinDeg": @cli.opt_double(0.0, help="Wheel spin angle in deg"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="12-raiway-biped",
      description="KAIST RAIWAY-inspired 20-inch Large-Wheeled Bipedal Robot with 6x A12 8318 100KV actuators (6:1 hip/knee, 4:1 wheels).",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let params = RaiwayParams::new(
    total_height_mm=args.double("totalHeight"),
    torso_height_mm=args.double("torsoHeight"),
    thigh_len_mm=args.double("thighLength"),
    shin_len_mm=args.double("shinLength"),
    wheel_radius_mm=args.double("wheelRadius"),
    track_width_mm=args.double("trackWidth"),
    num_elbows=args.int("numElbows"),
    tolerance_mm=args.double("tolerance"),
    detail~,
  )
  let links_text = @fs.read_file("examples/12-raiway-biped/supplier-links.txt").text() catch {
    _ => ""
  }
  let robot = build_raiway(params~).with_supplier_links(
    @cad.parse_supplier_links(links_text),
  )
  let pose = args.string_opt("pose").unwrap_or("standing")
  let positions = pose_positions(
    params,
    pose~,
    wheel_spin_deg=args.double("wheelSpinDeg"),
  )
  @common.write_output(
    robot,
    output,
    joint_positions=positions,
    example_dir="examples/12-raiway-biped",
  )
  match output.build_package {
    Some(dir) => {
      let hip_cart = build_gear_cartridge(
        hip_knee_actuator_params(params, "hip_knee_6to1"),
      )
      @step_cad.write_text_file(
        @cad.orient_print_design(hip_cart.to_design()).to_step_file(),
        Some(dir + "/printable/RAIWAY-HIP-KNEE-GEAR-6TO1.step"),
      )
      let wheel_cart = build_gear_cartridge(
        wheel_actuator_params(params, "wheel_4to1"),
      )
      @step_cad.write_text_file(
        @cad.orient_print_design(wheel_cart.to_design()).to_step_file(),
        Some(dir + "/printable/RAIWAY-WHEEL-GEAR-4TO1.step"),
      )
    }
    None => ()
  }
}
