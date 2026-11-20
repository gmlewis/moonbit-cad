///|
/// 09-fox-bot — FOX_BOT Wheeled-Quadruped Active-Suspension Robot
///
/// Parametric wheeled-quadruped built around 8x A12 8318 100KV brushless
/// motors with 4-elbow print-in-place herringbone planetary gearboxes
/// (`@components.a12_planetary_actuator`), 4x `TIRE-MOUNT-86.3` + 4x 7-inch
/// `WHEEL-7IN` budrash tires (`@step_motion.measured_tire_mount` /
/// `@step_motion.measured_tire`), four symmetric closed-chain 4-bar
/// pantograph suspension legs (`@mechanisms.solve_four_bar` upper branch),
/// 20x20 aluminum extrusion chassis frame, bright red fox-head cowl with twin
/// ears and RealSense D455 depth camera, BNO055 IMU, ESP32-S3 + RPi 5 / Jetson
/// Orin Nano compute stack, and dual 6S LiPo battery packs.
///
/// Mirrors the original FOX_BOT CAN ID map (wheels 1-4, hips 5-8 in LF, RF,
/// RR, LR order), kinematic travel (`0.40..1.01 rad`, `theta_mid = 0.705 rad`,
/// calibration `13.15 deg`), and differential heave/roll/pitch/pounce mixer.

///|
pub(all) struct FoxBotParams {
  scale : Double
  chassis_len_mm : Double
  inner_width_mm : Double
  rail_z_mm : Double
  hip_x_mm : Double
  crank_len_mm : Double
  coupler_len_mm : Double
  guide_len_mm : Double
  calf_len_mm : Double
  calf_beta_deg : Double
  gear_module_mm : Double
  gear_length_mm : Double
  num_elbows : Int32
  tolerance_mm : Double
  pose : String
  roll_deg : Double
  pitch_deg : Double
  heave : Double
  wheel_spin_deg : Double
  detail : @step_common.DetailLevel
}

///|
pub fn FoxBotParams::default() -> FoxBotParams {
  {
    scale: 1.0,
    chassis_len_mm: 600.0,
    inner_width_mm: 200.0,
    rail_z_mm: 80.0,
    hip_x_mm: 255.0,
    crank_len_mm: 178.0,
    coupler_len_mm: 48.0,
    guide_len_mm: 175.0,
    calf_len_mm: 215.0,
    calf_beta_deg: 152.0,
    gear_module_mm: 2.0,
    gear_length_mm: 12.0,
    num_elbows: 4,
    tolerance_mm: 0.2,
    pose: "mid",
    roll_deg: 0.0,
    pitch_deg: 0.0,
    heave: 0.0,
    wheel_spin_deg: 0.0,
    detail: @step_common.DetailLevel::Detailed,
  }
}

///|
pub fn FoxBotParams::scaled(scale : Double) -> FoxBotParams {
  let base = FoxBotParams::default()
  let s = if scale < 0.75 { 0.75 } else { scale }
  {
    ..base,
    scale: s,
    chassis_len_mm: base.chassis_len_mm * s,
    inner_width_mm: base.inner_width_mm * s,
    rail_z_mm: base.rail_z_mm * s,
    hip_x_mm: base.hip_x_mm * s,
    crank_len_mm: base.crank_len_mm * s,
    coupler_len_mm: base.coupler_len_mm * s,
    guide_len_mm: base.guide_len_mm * s,
    calf_len_mm: base.calf_len_mm * s,
  }
}

///|
fn fox_clamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
fn fox_hip_actuator_params(
  params : FoxBotParams,
  name : String,
  hub_offset_mm : Double,
) -> @components.A12ActuatorParams {
  @components.A12ActuatorParams::new(
    gear_module_mm=params.gear_module_mm,
    gear_length_mm=params.gear_length_mm,
    num_elbows=params.num_elbows,
    tolerance_mm=params.tolerance_mm,
    hub_offset_mm~,
    // 0 deg puts bolts at 0/60/120/180/240/300 deg so the 120 deg and 180 deg
    // bolts clear the upper guide bearing seat C (-60, +26) by >= 9.8 mm.
    flange_start_deg=0.0,
    detail=params.detail,
    name~,
  )
}

///|
fn fox_wheel_actuator_params(
  params : FoxBotParams,
  name : String,
  hub_offset_mm : Double,
) -> @components.A12ActuatorParams {
  let tm = @step_motion.tire_mount_spec()
  @components.A12ActuatorParams::new(
    gear_module_mm=params.gear_module_mm,
    gear_length_mm=params.gear_length_mm,
    num_elbows=params.num_elbows,
    tolerance_mm=params.tolerance_mm,
    hub_offset_mm~,
    flange_start_deg=30.0,
    detail=params.detail,
    name~,
    tire_mount_bcd_mm=tm.bolt_hole_circle_diameter_mm,
    tire_mount_bolt_count=tm.bolt_hole_count,
    tire_mount_phase_deg=tm.bolt_hole_phase_deg,
    tire_mount_hole_diam_mm=6.0,
  )
}

///|
/// Effective inner bay width guaranteed to clear opposing A12 hip actuators
/// plus their rear moteus C1 controllers with a 24 mm central cable channel.
pub fn FoxBotParams::effective_inner_width_mm(self : FoxBotParams) -> Double {
  let act_len = fox_hip_actuator_params(self, "probe", 10.0).total_len_mm()
  // Each actuator mounts to the outer face of the 20 mm rail (inner_w/2 + 20)
  // and extends inward by `act_len + 14` (moteus C1). Need >= 24 mm center gap.
  let min_inner = 2.0 * (act_len + 14.0 - 20.0) + 24.0
  if self.inner_width_mm < min_inner {
    min_inner
  } else {
    self.inner_width_mm
  }
}

///|
/// Effective vertical half-spacing between upper and lower 20x20 rails,
/// guaranteed to clear the A12 output cap flange (`flange_r + 2 mm`).
pub fn FoxBotParams::effective_rail_z_mm(self : FoxBotParams) -> Double {
  let flange_r = fox_hip_actuator_params(self, "probe", 10.0).outer_radius_mm() +
    7.5
  let min_z = flange_r + 12.0
  if self.rail_z_mm < min_z {
    min_z
  } else {
    self.rail_z_mm
  }
}

///|
/// Planar four-bar linkage parameters in each leg's local XZ frame
/// (front legs: `+X` forward; rear legs: rotated 180 deg around Z).
pub fn FoxBotParams::four_bar_params(
  self : FoxBotParams,
) -> @mechanisms.FourBarParams {
  let s = self.scale
  @mechanisms.FourBarParams::new(
    ax=self.hip_x_mm,
    az=0.0,
    cx=self.hip_x_mm - 60.0 * s,
    cz=26.0 * s,
    crank_len_mm=self.crank_len_mm,
    coupler_len_mm=self.coupler_len_mm,
    guide_len_mm=self.guide_len_mm,
    output_len_mm=self.calf_len_mm,
    output_beta_deg=self.calf_beta_deg,
    upper_branch=true,
  )
}

///|
/// Solves the FOX_BOT differential heave/roll/pitch mixer into four leg angles
/// in degrees: `(lf_deg, rf_deg, rr_deg, lr_deg)`.
///
/// Mirrors Section 3.1 of the FOX_BOT design:
///   theta_LF = theta_MID + o_heave + o_pitch + o_roll
///   theta_RF = theta_MID + o_heave + o_pitch - o_roll
///   theta_RR = theta_MID + o_heave - o_pitch - o_roll
///   theta_LR = theta_MID + o_heave - o_pitch + o_roll
/// Clamped to `[22.9, 57.9]` deg (`[0.40, 1.01]` rad) except for `"ref"`,
/// which sets all four legs to the `13.15 deg` (`0.2295 rad`) calibration pose.
pub fn FoxBotParams::leg_angles_deg(
  self : FoxBotParams,
) -> (Double, Double, Double, Double) {
  if self.pose == "ref" {
    return (13.15, 13.15, 13.15, 13.15)
  }
  let theta_mid = 40.4
  let theta_min = 22.9
  let theta_max = 57.9
  let theta_half = 17.5
  let mut heave = self.heave
  let mut roll_deg = self.roll_deg
  let mut pitch_deg = self.pitch_deg
  if self.pose == "crouched" && heave == 0.0 {
    heave = -1.0
  } else if self.pose == "tall" && heave == 0.0 {
    heave = 1.0
  } else if self.pose == "roll" && roll_deg == 0.0 {
    roll_deg = 22.0
  } else if self.pose == "pitch" && pitch_deg == 0.0 {
    pitch_deg = 18.0
  } else if self.pose == "pounce" && pitch_deg == 0.0 && heave == 0.0 {
    pitch_deg = -16.0
    heave = -0.2
  }
  let o_heave = fox_clamp(heave, -1.0, 1.0) * theta_half
  let o_pitch = fox_clamp(pitch_deg / 25.0, -1.0, 1.0) * theta_half * 0.75
  let o_roll = fox_clamp(roll_deg / 32.0, -1.0, 1.0) * theta_half * 0.75
  let lf = fox_clamp(
    theta_mid + o_heave + o_pitch + o_roll,
    theta_min,
    theta_max,
  )
  let rf = fox_clamp(
    theta_mid + o_heave + o_pitch - o_roll,
    theta_min,
    theta_max,
  )
  let rr = fox_clamp(
    theta_mid + o_heave - o_pitch - o_roll,
    theta_min,
    theta_max,
  )
  let lr = fox_clamp(
    theta_mid + o_heave - o_pitch + o_roll,
    theta_min,
    theta_max,
  )
  (lf, rf, rr, lr)
}

///|
pub fn solve_fox_leg(
  params : FoxBotParams,
  hip_deg : Double,
) -> @mechanisms.FourBarSolution {
  match @mechanisms.solve_four_bar(params.four_bar_params(), hip_deg) {
    Ok(sol) => sol
    Err(e) =>
      abort("FOX_BOT four-bar failed at hipDeg=\{hip_deg}: " + e.message())
  }
}

///|
/// Joint position map for the requested FOX_BOT pose.
pub fn FoxBotParams::pose_positions(self : FoxBotParams) -> Map[String, Double] {
  let (lf_deg, rf_deg, rr_deg, lr_deg) = self.leg_angles_deg()
  let wheel_rad = self.wheel_spin_deg * @math.PI / 180.0
  let legs : Array[(String, Double)] = [
    ("lf", lf_deg),
    ("rf", rf_deg),
    ("rr", rr_deg),
    ("lr", lr_deg),
  ]
  let pos : Map[String, Double] = Map([])
  for entry in legs {
    let (prefix, deg) = entry
    let sol = solve_fox_leg(self, deg)
    pos.set(prefix + "_hip_joint", sol.hip_joint_rad)
    pos.set(prefix + "_knee_joint", sol.knee_joint_rad)
    pos.set(prefix + "_guide_joint", sol.guide_joint_rad)
    pos.set(prefix + "_wheel_joint", wheel_rad)
  }
  pos
}

///|
fn fox_red() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.78, 0.11, 0.10)
}

///|
fn fox_ear_inner() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.88, 0.89, 0.91)
}

///|
fn fox_orange() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.84, 0.45, 0.12)
}

///|
fn fox_carbon() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.14, 0.15, 0.17)
}

///|
fn fox_aluminum() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.74, 0.77, 0.80)
}

///|
fn fox_pcb_red() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.72, 0.12, 0.14)
}

///|
fn fox_pcb_green() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.12, 0.44, 0.22)
}

///|
fn fox_dark() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.18, 0.20, 0.23)
}

///|
fn fox_steel() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.55, 0.58, 0.62)
}

///|
fn fox_printed(
  part_number : String,
  description : String,
  material : String,
  cost : Double,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="in-house",
    material~,
    process="3D print",
    unit_cost_usd=cost,
  )
}

///|
fn fox_purchased(
  part_number : String,
  description : String,
  material : String,
  cost : Double,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="generic",
    material~,
    process="purchased",
    unit_cost_usd=cost,
  )
}

///|
fn fox_prefix_bodies(comp : @cad.Component, prefix : String) -> @cad.Component {
  let bodies = comp.bodies.map(fn(body) {
    { ..body, name: prefix + "_" + body.name, }
  })
  let attachments = comp.attachments.map(fn(att) {
    { ..att, child: fox_prefix_bodies(att.child, prefix), }
  })
  { ..comp, bodies, attachments, }
}

///|
/// Builds the orange corner hip-motor mounting bracket using `Sketch2D`.
///
/// Local sketch origin `(0, 0)` sits at hip pivot `A`; `+X` points toward the
/// outer end of the chassis, `-X` toward the belly center (`C` at `-60*s, +26*s`).
/// Auto-punches the 6x M4 hip actuator `mount_flange` pattern, the 28.575 mm
/// output shaft clearance bore, the `FR8-2RS` bearing seat at `C`, and 4x M5
/// extrusion rail bolts at `z = ±rail_z`.
pub fn fox_hip_bracket_sketch(params : FoxBotParams) -> @step_cad.Sketch2D {
  let s = params.scale
  let rail_z = params.effective_rail_z_mm()
  let act_p = fox_hip_actuator_params(params, "probe", 10.0)
  let flange_bcd = 2.0 * (act_p.outer_radius_mm() + 3.8)
  let bearing = @components.flanged_bearing_fr8_2rs()
  let cx = -60.0 * s
  let cz = 26.0 * s
  let top_z = rail_z + 10.0
  let bot_z = -rail_z - 10.0
  let outer_x = 76.0 * s
  let inner_x = -92.0 * s
  let flange_pattern = @step_cad.HolePattern::bolt_circle(
    count=6,
    bcd_mm=flange_bcd,
    hole_diam_mm=4.4,
    pilot_diam_mm=bearing.outer_mm,
    start_deg=0.0,
  )
  @step_cad.Sketch2D::polygon([
    (inner_x, -56.0 * s),
    (inner_x, top_z),
    (outer_x, top_z),
    (outer_x, bot_z),
    (-52.0 * s, bot_z),
  ])
  .fillet_corners(8.0)
  .punch_mate_holes(0.0, 0.0, flange_pattern)
  .with_hole_circle(cx, cz, diam=bearing.outer_mm, segs=24)
  .with_hole_circle(inner_x + 22.0, rail_z, diam=5.4, segs=16)
  .with_hole_circle(outer_x - 22.0, rail_z, diam=5.4, segs=16)
  .with_hole_circle(-28.0 * s, -rail_z, diam=5.4, segs=16)
  .with_hole_circle(outer_x - 22.0, -rail_z, diam=5.4, segs=16)
}

///|
/// Builds the orange truss hip crank (`A -> B`) using `Sketch2D::stadium_link`
/// with auto-punched `output_hub` holes at `A=(0,0)`, `FR8-2RS` bearing seat
/// at `B=(-L1, 0)`, and FOX_BOT triangular lightening cutouts along the truss.
pub fn fox_hip_crank_sketch(params : FoxBotParams) -> @step_cad.Sketch2D {
  let l1 = params.crank_len_mm
  let bearing = @components.flanged_bearing_fr8_2rs()
  let hub_pattern = @step_cad.HolePattern::bolt_circle(
    count=4,
    bcd_mm=40.0,
    hole_diam_mm=4.4,
    pilot_diam_mm=12.7,
    start_deg=45.0,
  )
  let mut sk = @step_cad.Sketch2D::stadium_link(
      (0.0, 0.0),
      (-l1, 0.0),
      32.0,
      23.0,
      segs=18,
    )
    .punch_mate_holes(0.0, 0.0, hub_pattern)
    .with_hole_circle(-l1, 0.0, diam=bearing.outer_mm, segs=24)
  // Two lightweight truss windows along the mid-span when length permits.
  if l1 > 125.0 {
    let x1 = -52.0
    let x2 = -88.0
    let x3 = -126.0
    sk = sk
      .with_hole_polygon([(x1, -11.0), (x1, 11.0), (x2, 0.0)])
      .with_hole_polygon([(x3, -9.0), (x2 - 6.0, 0.0), (x3, 9.0)])
  }
  sk
}

///|
/// Builds the black curved upper guide link (`C -> D`) along `+X` in local
/// link coordinates `(0, 0) -> (+L3, 0)` so rotating by `sol.guide_joint_rad`
/// places `(+L3, 0)` at Pivot `D` and arches upward (`+Z`) over the hip crank.
pub fn fox_guide_link_sketch(params : FoxBotParams) -> @step_cad.Sketch2D {
  let l3 = params.guide_len_mm
  let bearing = @components.flanged_bearing_fr8_2rs()
  // Since `C -> D` points backward (`psi ~ 210 deg`), rotating `+X` by `-psi`
  // maps local `-Z` to world `+Z` (upward), so negative arch bows upward!
  @step_cad.Sketch2D::link_arc(
    (0.0, 0.0),
    (l3, 0.0),
    23.0,
    23.0,
    -34.0 * params.scale,
    segs=18,
  )
  .with_hole_circle(0.0, 0.0, diam=bearing.outer_mm, segs=24)
  .with_hole_circle(l3, 0.0, diam=bearing.outer_mm, segs=24)
}

///|
/// Builds the black truss calf strut (`B - D - W`) in the calf link's local XZ
/// frame: Pivot `B` at `(0, 0)`, Pivot `D` at `(L2, 0)`, Wheel hub `W` at
/// `(L_calf * cos(beta), L_calf * sin(beta))`. Auto-punches the 6x M4 wheel
/// actuator flange + bearing bore at `W`, `FR8-2RS` bearing seats at `B` & `D`,
/// and truss lightening cutouts.
pub fn fox_calf_strut_sketch(params : FoxBotParams) -> @step_cad.Sketch2D {
  let l2 = params.coupler_len_mm
  let l_calf = params.calf_len_mm
  let beta = params.calf_beta_deg * @math.PI / 180.0
  let wx = l_calf * @math.cos(beta)
  let wz = l_calf * @math.sin(beta)
  let ux = @math.cos(beta)
  let uz = @math.sin(beta)
  let nx = -uz
  let nz = ux
  let bearing = @components.flanged_bearing_fr8_2rs()
  let act_p = fox_wheel_actuator_params(params, "probe", 20.0)
  let flange_r = act_p.outer_radius_mm() + 7.5
  let flange_bcd = 2.0 * (act_p.outer_radius_mm() + 3.8)
  let wheel_boss_r = flange_r + 6.0
  let r_bd = 22.0
  // Build convex outer contour enclosing circles at B(0,0), D(L2,0), and W(wx,wz)
  let pts : Array[(Double, Double)] = []
  let segs = 20
  for i in 0..<segs {
    let a = 2.0 * @math.PI * i.to_double() / segs.to_double()
    pts.push((r_bd * @math.cos(a), r_bd * @math.sin(a)))
    pts.push((l2 + r_bd * @math.cos(a), r_bd * @math.sin(a)))
    pts.push(
      (wx + wheel_boss_r * @math.cos(a), wz + wheel_boss_r * @math.sin(a)),
    )
  }
  // Use stadium-style convex hull via Sketch2D::polygon of sampled convex hull
  let hull = fox_convex_hull(pts)
  let wheel_flange = @step_cad.HolePattern::bolt_circle(
    count=6,
    bcd_mm=flange_bcd,
    hole_diam_mm=4.4,
    pilot_diam_mm=bearing.outer_mm,
    start_deg=30.0,
  )
  let mut sk = @step_cad.Sketch2D::polygon(hull)
    .with_hole_circle(0.0, 0.0, diam=bearing.outer_mm, segs=24)
    .with_hole_circle(l2, 0.0, diam=bearing.outer_mm, segs=24)
    .punch_mate_holes(wx, wz, wheel_flange)
  // Lightweight truss cutout in the middle of the B->W beam (strictly clear
  // of both B bearing and W wheel-actuator boss).
  let mid_t0 = 42.0
  let mid_t1 = l_calf - wheel_boss_r - 16.0
  if mid_t1 > mid_t0 + 28.0 {
    let t_a = mid_t0
    let t_b = (mid_t0 + mid_t1) / 2.0
    let t_c = mid_t1
    let w_truss = 9.0
    sk = sk.with_hole_polygon([
      (t_a * ux + w_truss * nx, t_a * uz + w_truss * nz),
      (t_a * ux - w_truss * nx, t_a * uz - w_truss * nz),
      (t_b * ux, t_b * uz),
    ])
    if t_c - t_b > 16.0 {
      sk = sk.with_hole_polygon([
        (t_c * ux + w_truss * nx, t_c * uz + w_truss * nz),
        (t_b * ux + 4.0 * ux, t_b * uz + 4.0 * uz),
        (t_c * ux - w_truss * nx, t_c * uz - w_truss * nz),
      ])
    }
  }
  sk
}

///|
fn fox_cross(
  o : (Double, Double),
  a : (Double, Double),
  b : (Double, Double),
) -> Double {
  (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
}

///|
fn fox_convex_hull(points : Array[(Double, Double)]) -> Array[(Double, Double)] {
  let pts = points.copy()
  pts.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else if a.1 < b.1 {
      -1
    } else if a.1 > b.1 {
      1
    } else {
      0
    }
  })
  let lower : Array[(Double, Double)] = []
  for p in pts {
    while lower.length() >= 2 &&
          fox_cross(lower[lower.length() - 2], lower[lower.length() - 1], p) <=
          0.0 {
      let _ = lower.pop()
    }
    lower.push(p)
  }
  let upper : Array[(Double, Double)] = []
  let mut i = pts.length() - 1
  while i >= 0 {
    let p = pts[i]
    while upper.length() >= 2 &&
          fox_cross(upper[upper.length() - 2], upper[upper.length() - 1], p) <=
          0.0 {
      let _ = upper.pop()
    }
    upper.push(p)
    i = i - 1
  }
  let _ = lower.pop()
  let _ = upper.pop()
  for p in upper {
    lower.push(p)
  }
  lower
}

///|
/// Builds the bright red fox head front cowl, twin pointed upright ears, and
/// inset Intel RealSense D455 depth camera as a subassembly attached to the
/// front face of the 20x20 extrusion frame.
fn build_fox_head(params : FoxBotParams) -> @cad.Component {
  let inner_w = params.effective_inner_width_mm()
  let rail_z = params.effective_rail_z_mm()
  let cowl_w = inner_w + 42.0
  let cowl_h = 2.0 * rail_z + 20.0
  let cowl_depth = 46.0 * params.scale
  let cowl_part = fox_printed(
    "FOX-HEAD-COWL", "Printed bright-red FOX_BOT front nose cowl with RealSense D455 camera recess",
    "PETG / PLA (Red)", 10.5,
  )
  let ear_part = fox_printed(
    "FOX-EAR", "Printed pointed upright FOX_BOT ear shell", "PETG / PLA (Red)", 2.5,
  ).with_single_body_print(true)
  let ear_inner_part = fox_printed(
    "FOX-EAR-INNER", "Printed inner ear accent insert", "PLA (Charcoal)", 0.4,
  ).with_single_body_print(true)
  let d455_part = fox_purchased(
    "REALSENSE-D455", "Intel RealSense D455 stereo depth camera (95 x 26 x 29 mm)",
    "aluminum / optics", 289.0,
  )
  // Rounded nose side profile in XZ: x in [0, cowl_depth], z in [-cowl_h/2, +cowl_h/2]
  let cowl_sketch = @step_cad.Sketch2D::polygon([
    (0.0, -cowl_h / 2.0),
    (cowl_depth * 0.78, -cowl_h / 2.0),
    (cowl_depth, -cowl_h * 0.24),
    (cowl_depth, cowl_h * 0.28),
    (cowl_depth * 0.72, cowl_h / 2.0),
    (0.0, cowl_h / 2.0),
  ]).fillet_corners(10.0)
  // Pointed upright fox ear profile in YZ (width 44 mm, height 72 mm)
  let ear_h = 72.0 * params.scale
  let ear_w = 42.0 * params.scale
  let ear_sketch = @step_cad.Sketch2D::polygon([
    (-ear_w / 2.0, 0.0),
    (ear_w / 2.0, 0.0),
    (ear_w * 0.34, ear_h * 0.62),
    (0.0, ear_h),
    (-ear_w * 0.34, ear_h * 0.62),
  ]).fillet_corners(5.0)
  let inner_ear_sketch = @step_cad.Sketch2D::polygon([
    (-ear_w * 0.30, 8.0 * params.scale),
    (ear_w * 0.30, 8.0 * params.scale),
    (ear_w * 0.18, ear_h * 0.54),
    (0.0, ear_h * 0.80),
    (-ear_w * 0.18, ear_h * 0.54),
  ]).fillet_corners(3.0)
  let ear_y = inner_w * 0.32
  let ear_x = cowl_depth * 0.38
  let ear_z = cowl_h / 2.0
  let mut head = @cad.Component::new(
      "fox_head",
      description="Red FOX_BOT front head cowl with twin upright ears and Intel RealSense D455",
    )
    .add_body(
      @cad.BodyPart::extruded_sketch_mm(
        "cowl_shell",
        cowl_sketch,
        @step_cad.Plane::XZ,
        cowl_w,
        centered=true,
        density=@urdf.Density::petg(),
        color=fox_red(),
      ).with_part(cowl_part),
    )
    // RealSense D455 silver anodized camera body protruding cleanly on front
    .add_body(
      @cad.BodyPart::box_mm(
        "realsense_d455_body",
        24.0,
        124.0,
        29.0,
        x_mm=cowl_depth - 6.0,
        z_mm=6.0,
        density=@urdf.Density::aluminum_6061(),
        color=fox_aluminum(),
      ).with_part(d455_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "realsense_d455_visor",
        4.0,
        114.0,
        21.0,
        x_mm=cowl_depth + 6.5,
        z_mm=6.0,
        density=@urdf.Density::abs(),
        color=fox_carbon(),
      ).with_part(d455_part),
    )
    .add_mate_mm_deg("mount_rear", x=0.0, axis=(-1.0, 0.0, 0.0))
  for sign in [1.0, -1.0] {
    let tag = if sign > 0.0 { "l" } else { "r" }
    head = head
      .add_body(
        @cad.BodyPart::extruded_sketch_mm(
          "fox_ear_" + tag,
          ear_sketch,
          @step_cad.Plane::XZ,
          14.0 * params.scale,
          centered=true,
          x_mm=ear_x,
          y_mm=sign * ear_y,
          z_mm=ear_z,
          rz_deg=90.0,
          density=@urdf.Density::petg(),
          color=fox_red(),
        ).with_part(ear_part),
      )
      .add_body(
        @cad.BodyPart::extruded_sketch_mm(
          "fox_ear_inner_" + tag,
          inner_ear_sketch,
          @step_cad.Plane::XZ,
          4.0 * params.scale,
          centered=true,
          x_mm=ear_x + 7.5 * params.scale,
          y_mm=sign * ear_y,
          z_mm=ear_z,
          rz_deg=90.0,
          density=@urdf.Density::pla(),
          color=fox_ear_inner(),
        ).with_part(ear_inner_part),
      )
  }
  head.with_print_bed_orient(@cad.PrintBedOrient::AutoFlatLargestFace)
}

///|
/// Builds the bright red arched rear tail bumper with triangular truss cutouts.
fn build_fox_tail(params : FoxBotParams) -> @cad.Component {
  let inner_w = params.effective_inner_width_mm()
  let rail_z = params.effective_rail_z_mm()
  let tail_w = inner_w + 40.0
  let tail_h = 2.0 * rail_z + 20.0
  let tail_depth = 42.0 * params.scale
  let tail_part = fox_printed(
    "FOX-TAIL-BUMPER", "Printed bright-red FOX_BOT arched rear tail truss bumper",
    "PETG / PLA (Red)", 8.0,
  )
  // Top-view arched bumper profile in XY, extruded vertically along Z
  let half_w = tail_w / 2.0
  let tail_sketch = @step_cad.Sketch2D::polygon([
      (0.0, -half_w),
      (0.0, half_w),
      (-tail_depth * 0.55, half_w * 0.88),
      (-tail_depth, half_w * 0.35),
      (-tail_depth, -half_w * 0.35),
      (-tail_depth * 0.55, -half_w * 0.88),
    ])
    .fillet_corners(8.0)
    .with_hole_polygon([
      (-8.0, -half_w * 0.65),
      (-8.0, -14.0),
      (-tail_depth * 0.68, -half_w * 0.32),
    ])
    .with_hole_polygon([
      (-8.0, 14.0),
      (-8.0, half_w * 0.65),
      (-tail_depth * 0.68, half_w * 0.32),
    ])
  @cad.Component::new(
    "fox_tail",
    description="Red FOX_BOT arched rear tail bumper",
  )
  .add_body(
    @cad.BodyPart::extruded_sketch_mm(
      "tail_bumper",
      tail_sketch,
      @step_cad.Plane::XY,
      tail_h,
      centered=true,
      density=@urdf.Density::petg(),
      color=fox_red(),
    ).with_part(tail_part),
  )
  .add_mate_mm_deg("mount_front", x=0.0, axis=(1.0, 0.0, 0.0))
  .with_print_bed_orient(@cad.PrintBedOrient::AutoFlatLargestFace)
}

///|
/// Builds the FOX_BOT open 20x20 aluminum extrusion ladder chassis, corner
/// hip-motor mount brackets, electronics deck, dual 6S LiPo batteries,
/// ESP32-S3 (`AT_ZMOAB_ROS`), RPi 5 / Jetson Orin Nano, Futaba R3008SB,
/// CAN transceiver, and BNO055 IMU link.
fn build_fox_chassis(params : FoxBotParams) -> @cad.Component {
  let s = params.scale
  let inner_w = params.effective_inner_width_mm()
  let rail_z = params.effective_rail_z_mm()
  let half_len = params.chassis_len_mm / 2.0
  let rail_y = inner_w / 2.0 + 10.0
  let bracket_t = 10.0
  let rail_outer_y = inner_w / 2.0 + 20.0

  let rail_part = fox_purchased(
    "EXTRUSION-2020", "20x20 mm aluminum V-slot extrusion rail (cut to length)",
    "6063-T5 aluminum", 6.5,
  )
  let bracket_part = fox_printed(
    "FOX-HIP-BRACKET", "Printed orange FOX_BOT corner hip-motor and upper-guide mount bracket",
    "CF nylon / PETG", 7.5,
  )
  let deck_part = fox_printed(
    "FOX-ELEC-DECK", "Printed central electronics and dual-6S LiPo battery deck",
    "CF nylon / PETG", 9.0,
  )
  let lipo_part = fox_purchased(
    "LIPO-6S-5000", "6S (22.2 V) 5000 mAh high-discharge LiPo battery pack", "LiPo cell pack",
    79.0,
  )
  let dcdc_part = fox_purchased(
    "DCDC-24V-5V", "24 V to 5 V / 12 V 10 A buck DC-DC regulator module", "aluminum / PCB",
    16.0,
  )
  let esp32_part = fox_purchased(
    "ESP32-S3-ZMOAB", "ESP32-S3 AT_ZMOAB_ROS 100 Hz real-time low-level controller board",
    "FR4 PCB", 45.0,
  )
  let can_part = fox_purchased(
    "CAN-TJA1051", "TJA1051T/3 high-speed CAN bus transceiver breakout", "FR4 PCB",
    5.5,
  )
  let sbus_part = fox_purchased(
    "FUTABA-R3008SB", "Futaba R3008SB 2.4 GHz T-FHSS SBUS radio receiver", "ABS / PCB",
    49.0,
  )
  let rpi_part = fox_purchased(
    "RPI5-ORIN-NANO", "Raspberry Pi 5 / Jetson Orin Nano ROS 2 upper computer with heatsink",
    "FR4 PCB / aluminum", 85.0,
  )
  let imu_part = fox_purchased(
    "BNO055-IMU", "Bosch BNO055 9-DOF absolute orientation fused IMU module", "FR4 PCB",
    24.95,
  )

  let mut chassis = @cad.Component::new(
      "chassis",
      description="FOX_BOT 20x20 aluminum ladder-frame chassis with dual 6S LiPo, ESP32-S3, RPi 5 / Orin Nano, and BNO055 IMU",
    )
    .with_param("scale", params.scale.to_string())
    .with_param("chassis_len_mm", params.chassis_len_mm.to_string())
    .with_param("inner_width_mm", inner_w.to_string())
    .with_param("rail_z_mm", rail_z.to_string())
    .with_param("pose", params.pose)
    .add_port(
      @cad.Port::new("power_bus", @cad.PortKind::Power, spec="24 V, 80 A"),
    )
    .add_port(
      @cad.Port::new("can_bus", @cad.PortKind::Bus, spec="CAN 2.0B 1 Mbps"),
    )

  // 4 longitudinal 20x20 rails
  let rail_specs : Array[(String, Double, Double)] = [
    ("rail_top_left", rail_y, rail_z),
    ("rail_top_right", -rail_y, rail_z),
    ("rail_bot_left", rail_y, -rail_z),
    ("rail_bot_right", -rail_y, -rail_z),
  ]
  for entry in rail_specs {
    let (name, ry, rz) = entry
    chassis = chassis.add_body(
      @cad.BodyPart::box_mm(
        name,
        params.chassis_len_mm,
        20.0,
        20.0,
        y_mm=ry,
        z_mm=rz,
        density=@urdf.Density::aluminum_6061(),
        color=fox_aluminum(),
      ).with_part(rail_part),
    )
  }
  // 4 cross-brace 20x20 rails at front and rear ends
  let cross_specs : Array[(String, Double, Double)] = [
    ("cross_front_top", half_len - 10.0, rail_z),
    ("cross_front_bot", half_len - 10.0, -rail_z),
    ("cross_rear_top", -(half_len - 10.0), rail_z),
    ("cross_rear_bot", -(half_len - 10.0), -rail_z),
  ]
  for entry in cross_specs {
    let (name, cx, cz) = entry
    chassis = chassis.add_body(
      @cad.BodyPart::box_mm(
        name,
        20.0,
        inner_w,
        20.0,
        x_mm=cx,
        z_mm=cz,
        density=@urdf.Density::aluminum_6061(),
        color=fox_aluminum(),
      ).with_part(rail_part),
    )
  }

  // Central electronics & dual-battery deck sitting on top of the lower rails,
  // strictly clear of front and rear hip actuators (x in [-142, +142]*s).
  let deck_len = 280.0 * s
  let deck_w = inner_w + 16.0
  let deck_t = 6.0
  let deck_z = -rail_z + 10.0 + deck_t / 2.0
  let deck_top = deck_z + deck_t / 2.0
  let deck_sk = @step_cad.Sketch2D::rounded_rect(deck_len, deck_w, 8.0).with_hole_slot(
    0.0,
    0.0,
    length=42.0,
    width=12.0,
    angle_deg=90.0,
  )
  chassis = chassis
    .add_body(
      @cad.BodyPart::extruded_sketch_mm(
        "electronics_deck",
        deck_sk,
        @step_cad.Plane::XY,
        deck_t,
        centered=true,
        z_mm=deck_z,
        density=@urdf.Density::cf_nylon(),
        color=fox_dark(),
      ).with_part(deck_part),
    )
    // Dual 6S LiPo packs side-by-side in rear half of central bay
    .add_body(
      @cad.BodyPart::box_mm(
        "lipo_6s_left",
        136.0,
        46.0,
        48.0,
        x_mm=-62.0 * s,
        y_mm=28.0,
        z_mm=deck_top + 24.0,
        density=@urdf.Density::lipo_battery(),
        color=fox_carbon(),
      ).with_part(lipo_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "lipo_6s_right",
        136.0,
        46.0,
        48.0,
        x_mm=-62.0 * s,
        y_mm=-28.0,
        z_mm=deck_top + 24.0,
        density=@urdf.Density::lipo_battery(),
        color=fox_carbon(),
      ).with_part(lipo_part),
    )
    // DC-DC regulator beside LiPo packs
    .add_body(
      @cad.BodyPart::box_mm(
        "dcdc_regulator",
        58.0,
        36.0,
        20.0,
        x_mm=-62.0 * s,
        y_mm=76.0,
        z_mm=deck_top + 10.0,
        density=@urdf.Density::aluminum_6061(),
        color=fox_aluminum(),
      ).with_part(dcdc_part),
    )
    // Front electronics: RPi 5 / Jetson Orin Nano + heatsink
    .add_body(
      @cad.BodyPart::box_mm(
        "upper_computer_pcb",
        85.0,
        56.0,
        24.0,
        x_mm=56.0 * s,
        y_mm=34.0,
        z_mm=deck_top + 12.0,
        density=@urdf.Density::fr4_pcb(),
        color=fox_pcb_green(),
      ).with_part(rpi_part),
    )
    // ESP32-S3 AT_ZMOAB_ROS red low-level controller board
    .add_body(
      @cad.BodyPart::box_mm(
        "esp32_zmoab_board",
        72.0,
        52.0,
        14.0,
        x_mm=56.0 * s,
        y_mm=-36.0,
        z_mm=deck_top + 7.0,
        density=@urdf.Density::fr4_pcb(),
        color=fox_pcb_red(),
      ).with_part(esp32_part),
    )
    // TJA1051T/3 CAN transceiver + Futaba R3008SB SBUS receiver
    .add_body(
      @cad.BodyPart::box_mm(
        "can_transceiver",
        24.0,
        20.0,
        8.0,
        x_mm=112.0 * s,
        y_mm=-36.0,
        z_mm=deck_top + 4.0,
        density=@urdf.Density::fr4_pcb(),
        color=fox_dark(),
      ).with_part(can_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "futaba_r3008sb",
        47.0,
        25.0,
        14.0,
        x_mm=112.0 * s,
        y_mm=34.0,
        z_mm=deck_top + 7.0,
        density=@urdf.Density::abs(),
        color=fox_carbon(),
      ).with_part(sbus_part),
    )

  // Attach red fox head cowl (front +X) and arched tail bumper (rear -X)
  // with first-class ExplodeSpecs so exploded.step separates them cleanly!
  let fox_head = build_fox_head(params)
  let fox_tail = build_fox_tail(params)
  let imu_link = @cad.Component::new(
      "bno055_imu",
      description="Bosch BNO055 9-DOF fused IMU (triggers MJCF accelerometer/gyro sensors)",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "bno055_module",
        28.0,
        22.0,
        8.0,
        z_mm=4.0,
        density=@urdf.Density::fr4_pcb(),
        color=fox_dark(),
      ).with_part(imu_part),
    )
    .add_mate_mm_deg("base")

  chassis = chassis
    .add_mate_mm_deg("head_mount", x=half_len, axis=(1.0, 0.0, 0.0))
    .attach(
      "fox_head_joint",
      parent_mate="head_mount",
      fox_head,
      child_mate="mount_rear",
      spec=@cad.JointSpec::fixed(),
      explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=80.0, order=1)),
    )
    .add_mate_mm_deg("tail_mount", x=-half_len, axis=(-1.0, 0.0, 0.0))
    .attach(
      "fox_tail_joint",
      parent_mate="tail_mount",
      fox_tail,
      child_mate="mount_front",
      spec=@cad.JointSpec::fixed(),
      explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=80.0, order=1)),
    )
    .add_mate_mm_deg("imu_mount", x=10.0 * s, z=deck_top)
    .attach(
      "bno055_imu_joint",
      parent_mate="imu_mount",
      imu_link,
      child_mate="base",
      spec=@cad.JointSpec::fixed(),
      explode=Some(
        @cad.ExplodeSpec::offset_mm(dx=0.0, dy=0.0, dz=75.0, order=1),
      ),
    )

  // 4 orange corner hip-motor mounting brackets attached as separate child
  // components so `printable/FOX-HIP-BRACKET.step` exports a single 168x180x10
  // printable plate (qty 4, fits a 220x220 bed!) instead of all 4 fused in place.
  let bracket_sk = fox_hip_bracket_sketch(params)
  let corner_specs : Array[(String, Double, Double, Double)] = [
    ("lf", params.hip_x_mm, rail_outer_y + bracket_t / 2.0, 0.0),
    ("rf", params.hip_x_mm, -(rail_outer_y + bracket_t / 2.0), 0.0),
    ("rr", -params.hip_x_mm, -(rail_outer_y + bracket_t / 2.0), 180.0),
    ("lr", -params.hip_x_mm, rail_outer_y + bracket_t / 2.0, 180.0),
  ]
  for entry in corner_specs {
    let (prefix, bx, by, rz) = entry
    let br_comp = @cad.Component::new(
        prefix + "_hip_bracket",
        description="Orange FOX_BOT corner hip-motor and upper-guide mount bracket",
      )
      .add_body(
        @cad.BodyPart::extruded_sketch_mm(
          prefix + "_hip_bracket_body",
          bracket_sk,
          @step_cad.Plane::XZ,
          bracket_t,
          centered=true,
          density=@urdf.Density::cf_nylon(),
          color=fox_orange(),
        ).with_part(bracket_part),
      )
      .add_mate_mm_deg("mount")
      .with_print_bed_orient(@cad.PrintBedOrient::AutoFlatLargestFace)
    let mate_name = prefix + "_bracket_seat"
    chassis = chassis
      .add_mate_mm_deg(mate_name, x=bx, y=by, rz_deg=rz)
      .attach(
        prefix + "_hip_bracket_joint",
        parent_mate=mate_name,
        br_comp,
        child_mate="mount",
        spec=@cad.JointSpec::fixed(),
      )
  }
  chassis
}

///|
/// Builds the `moteus C1` rear controller component using `@components.moteus_c1_board`
/// (which centers and orients the vendor STEP cleanly onto its `"mount"` mate),
/// or a lightweight exact-envelope PCB block for fast tests.
fn build_moteus_c1(name : String, moteus_step : String?) -> @cad.Component {
  match moteus_step {
    Some(step_text) => @components.moteus_c1_board(step_text, name~)
    None => {
      let part = fox_purchased(
        "MOTEUS-C1-R1.2", "mjbots moteus C1 r1.2 FOC brushless controller with AS5047P encoder",
        "FR4 PCB", 69.0,
      )
      @cad.Component::new(
        name,
        description="moteus C1 r1.2 FOC brushless motor controller",
      )
      .add_body(
        @cad.BodyPart::box_mm(
          name + "_pcb",
          38.0,
          38.0,
          9.5,
          z_mm=-4.75,
          density=@urdf.Density::fr4_pcb(),
          color=fox_dark(),
        ).with_part(part),
      )
      .add_mate_mm_deg("mount", z=0.0, axis=(0.0, 0.0, 1.0))
    }
  }
}

///|
/// Builds the `TIRE-MOUNT-86.3` + `WHEEL-7IN` (`measured_tire_mount` +
/// `measured_tire` + 3x M4x30 SHCS wheel bolts) wheel assembly for one leg.
///
/// Local frame matches `TIRE-MOUNT-86.3` (`front-face` mate at `x = -5.0`
/// with axis `(-1, 0, 0)`), ready to snap straight onto an
/// `a12_planetary_actuator`'s `tire_mount` mate.
fn build_fox_wheel(
  prefix : String,
  detail : @step_common.DetailLevel,
  tire_mount_step : String?,
) -> @cad.Component {
  let tire_spec = @step_motion.tire_spec()
  let mount_spec = @step_motion.tire_mount_spec()
  let tire_part = @cad.PartMeta::new(
    "WHEEL-7IN",
    description="budrash 72-107 7 x 1.5 in wheel and tire with a 1/2 in bore and 6 radial ribs; drill 3 x 4.5 mm holes at 55.85 mm BCD for TIRE-MOUNT-86.3",
    supplier="Amazon",
    supplier_url="https://www.amazon.com/budrash-72-107-Replaces-Universal-Utility/dp/B09XMGXFDN",
    material="rubber tire on hard plastic hub",
    process="purchased",
    unit_cost_usd=9.50,
  )
  let tire_step = match @step_motion.measured_tire() {
    Ok(c) => c
    Err(_) => abort("failed to build @step_motion.measured_tire()")
  }
  let mut tire_comp = fox_prefix_bodies(
    @cad.Component::from_step_component(
      prefix + "_tire",
      tire_step,
      density=@urdf.Density::rubber(),
      part=Some(tire_part),
    ),
    prefix + "_tire",
  ).with_collision_cylinder_mm(
    radius_mm=tire_spec.tire_outer_diameter_mm / 2.0,
    length_mm=tire_spec.tire_width_mm,
    ry_deg=90.0,
  )
  let bolt_r = mount_spec.bolt_hole_circle_diameter_mm / 2.0
  let bolt_plate_x = -(tire_spec.hub_inset_mm + tire_spec.inset_thickness_mm)
  for i in 0..<mount_spec.bolt_hole_count {
    let theta = (
        mount_spec.bolt_hole_phase_deg +
        360.0 * i.to_double() / mount_spec.bolt_hole_count.to_double()
      ) *
      @math.PI /
      180.0
    let bname = prefix + "_tire_bolt_" + i.to_string()
    let screw = fox_prefix_bodies(
      @components.iso_shcs_screw(
        name=bname,
        size=@step_standards.M4,
        length_mm=30.0,
        detail~,
      ),
      bname,
    )
    tire_comp = tire_comp
      .add_mate_mm_deg(
        bname,
        x=bolt_plate_x,
        y=bolt_r * @math.cos(theta),
        z=bolt_r * @math.sin(theta),
        ry_deg=-90.0,
      )
      .attach(
        bname + "_merge",
        parent_mate=bname,
        screw,
        child_mate="head_seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }

  let mount_part = @cad.PartMeta::new(
    "TIRE-MOUNT-86.3",
    description="Printed tire mount for the 7 in budrash wheel; three M4 through-holes at 55.85 mm BCD, six 2 mm radial rib slots, and a 12.7 mm hub post",
    supplier="in-house",
    material="CF nylon / PETG",
    process="3D print",
    unit_cost_usd=2.50,
  )
  let mount_step = match @step_motion.measured_tire_mount() {
    Ok(c) => c
    Err(_) => abort("failed to build @step_motion.measured_tire_mount()")
  }
  let nominal_mount = @cad.Component::from_step_component(
    prefix + "_wheel",
    mount_step,
    density=@urdf.Density::cf_nylon(),
    part=Some(mount_part),
  )
  let mount_base = match tire_mount_step {
    Some(eval_step) => {
      let eval_body = @cad.BodyPart::imported_step(
        prefix + "_tire_mount",
        eval_step,
        source="TIRE-MOUNT-86.3 (SMLib-evaluated)",
        density=@urdf.Density::cf_nylon(),
        color=fox_orange(),
        part=Some(mount_part),
      )
      let kept_inertial = if nominal_mount.bodies.length() > 0 {
        nominal_mount.bodies[0].inertial
      } else {
        eval_body.inertial
      }
      { ..nominal_mount, bodies: [{ ..eval_body, inertial: kept_inertial, }], }
    }
    None => fox_prefix_bodies(nominal_mount, prefix + "_tm")
  }
  mount_base.attach(
    prefix + "_tire_mount_to_tire",
    parent_mate="hub-post",
    tire_comp,
    child_mate="hub-bore",
    spec=@cad.JointSpec::fixed(),
    explode=Some(@cad.ExplodeSpec::offset_mm(dx=-60.0, dy=0.0, dz=0.0, order=5)),
  )
}

///|
/// Attaches one complete symmetric 4-bar leg + hip A12 actuator + wheel A12
/// actuator + `TIRE-MOUNT-86.3` + `WHEEL-7IN` onto the FOX_BOT chassis.
///
/// Rear legs (`is_front = false`) are rotated 180 deg around Z relative to
/// front legs so all four legs share identical printable parts and identical
/// closed-chain joint-angle equations.
fn attach_fox_leg(
  chassis : @cad.Component,
  params : FoxBotParams,
  prefix : String,
  is_front : Bool,
  is_left : Bool,
  hip_can_id : Int32,
  wheel_can_id : Int32,
  moteus_step : String?,
  tire_mount_step : String?,
) -> @cad.Component {
  let s = params.scale
  let inner_w = params.effective_inner_width_mm()
  let rail_outer_y = inner_w / 2.0 + 20.0
  let bracket_t = 10.0
  let hub_t = 8.0
  let crank_t = 16.0
  let gap_t = 4.0
  let calf_t = 20.0
  // Lateral Y stack-up (measured outward from chassis centerline):
  //   rail_outer_y        = 120   (hip actuator mount_flange sits flush here)
  //   bracket_out         = 130   (hip bracket outer face)
  //   hip_hub_out         = 138   (hip A12 output_hub outer face)
  //   plane1_mid          = 146   (crank & guide link center, spans 138..154)
  //   plane2_in           = 158   (calf inner face; wheel actuator mount_flange)
  //   plane2_mid          = 168   (calf center, spans 158..178)
  let bracket_out = rail_outer_y + bracket_t
  let hip_hub_out = bracket_out + hub_t
  let plane1_mid = hip_hub_out + crank_t / 2.0

  // Leg frame: front legs use rz = 0 (outboard = +Y for LF, -Y for RF);
  // rear legs use rz = 180 (outboard in leg-local frame = +Y for RR, -Y for LR).
  let rz = if is_front { 0.0 } else { 180.0 }
  let world_y_sign = if is_left { 1.0 } else { -1.0 }
  let leg_y_sign = if is_front { world_y_sign } else { -world_y_sign }
  let world_x_sign = if is_front { 1.0 } else { -1.0 }

  let bearing = @components.flanged_bearing_fr8_2rs()
  let bearing_part = fox_purchased(
    "BEARING-FR8-2RS", "FR8-2RS flanged sealed bearing (12.7 x 28.575 x 7.938 mm)",
    "steel", 1.55,
  )
  let pin_part = fox_purchased(
    "DOWEL-12.7x42", "12.7 x 42 mm hardened alloy steel leg pivot dowel pin", "steel",
    2.1,
  )
  let standoff_part = fox_printed(
    "FOX-GUIDE-SPACER", "Printed 8 mm guide-pivot bearing spacer sleeve", "CF nylon / PETG",
    1.2,
  )
  let crank_part = fox_printed(
    "FOX-HIP-CRANK", "Printed orange FOX_BOT truss hip crank arm (A -> B)", "CF nylon / PETG",
    6.5,
  )
  let guide_part = fox_printed(
    "FOX-GUIDE-LINK", "Printed black FOX_BOT curved upper parallel guide link (C -> D)",
    "CF nylon / PETG", 5.5,
  )
  let calf_part = fox_printed(
    "FOX-CALF-STRUT", "Printed black FOX_BOT truss calf strut (B - D - W)", "CF nylon / PETG",
    9.0,
  )

  // 1. Hip A12 + 4-elbow planetary actuator + rear moteus C1 (centered & flat)
  let hip_act_params = fox_hip_actuator_params(
    params,
    prefix + "_hip_act",
    bracket_t,
  )
  let hip_moteus = build_moteus_c1(prefix + "_hip_moteus", moteus_step)
  let hip_act = @components.a12_planetary_actuator(hip_act_params)
    .add_mate_mm_deg("moteus_mount", z=-2.4, axis=(0.0, 0.0, -1.0))
    .attach(
      prefix + "_hip_moteus_mount",
      parent_mate="moteus_mount",
      hip_moteus,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )

  // 2. Wheel A12 + 4-elbow planetary actuator (with 80 mm TIRE-MOUNT-86.3 hub!)
  let wheel_act_params = fox_wheel_actuator_params(
    params,
    prefix + "_wheel_act",
    calf_t,
  )
  let wheel_moteus = build_moteus_c1(prefix + "_wheel_moteus", moteus_step)
  let wheel_act = @components.a12_planetary_actuator(wheel_act_params)
    .add_mate_mm_deg("moteus_mount", z=-2.4, axis=(0.0, 0.0, -1.0))
    .attach(
      prefix + "_wheel_moteus_mount",
      parent_mate="moteus_mount",
      wheel_moteus,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )

  // 3. Wheel link (TIRE-MOUNT-86.3 + WHEEL-7IN + 3x M4x30 bolts)
  let wheel_comp = build_fox_wheel(prefix, params.detail, tire_mount_step)
  let mount_spec = @step_motion.tire_mount_spec()

  // 4. Calf strut link (local origin at Pivot B, Pivot D at (L2, 0),
  //    Wheel pivot W at (L_calf*cos(beta), L_calf*sin(beta))).
  let beta = params.calf_beta_deg * @math.PI / 180.0
  let wx = params.calf_len_mm * @math.cos(beta)
  let wz = params.calf_len_mm * @math.sin(beta)
  let calf_sk = fox_calf_strut_sketch(params)
  // Calf local Y = 0 sits at `plane2_mid`; inboard face is at `-leg_y_sign * calf_t/2`
  let calf_inboard_y = -leg_y_sign * calf_t / 2.0
  let calf_outboard_y = leg_y_sign * calf_t / 2.0
  // Wheel actuator `mount_flange` has axis (0,0,+1) -> snap onto calf inboard
  // face with parent mate axis pointing INBOARD (`-leg_y_sign` along Y) so
  // anti-parallel resolve sends actuator +Z OUTBOARD (through calf to hub!).
  let calf = @cad.Component::new(
      prefix + "_calf",
      description="FOX_BOT \{prefix} truss calf strut with inboard A12 wheel actuator and 7 in tire",
    )
    .add_body(
      @cad.BodyPart::extruded_sketch_mm(
        prefix + "_calf_body",
        calf_sk,
        @step_cad.Plane::XZ,
        calf_t,
        centered=true,
        density=@urdf.Density::cf_nylon(),
        color=fox_carbon(),
      )
      .with_collisions([
        // Elbow beam B(0,0) -> D(L2,0)
        @urdf.Collision::new(
          @urdf.Geometry::box_mm(params.coupler_len_mm + 44.0, calf_t, 44.0),
          name=Some(prefix + "_calf_body"),
          origin=@urdf.Origin::from_mm_deg(x=params.coupler_len_mm / 2.0),
        ),
        // Main calf strut beam B(0,0) -> W(wx, wz) rotated along calf_beta_deg
        @urdf.Collision::new(
          @urdf.Geometry::box_mm(params.calf_len_mm + 36.0, calf_t, 52.0),
          name=Some(prefix + "_calf_body"),
          origin=@urdf.Origin::from_mm_deg(
            x=wx / 2.0,
            z=wz / 2.0,
            ry_deg=-params.calf_beta_deg,
          ),
        ),
        // Round wheel-actuator mounting boss at W(wx, wz)
        @urdf.Collision::new(
          @urdf.Geometry::cylinder_mm(
            wheel_act_params.outer_radius_mm() + 10.0,
            calf_t,
          ),
          name=Some(prefix + "_calf_body"),
          origin=@urdf.Origin::from_mm_deg(x=wx, z=wz, rx_deg=90.0),
        ),
      ])
      .with_part(calf_part),
    )
    // Bearings & pivot pins at B (0,0) and D (L2,0) spanning crank/guide -> calf
    .add_body(
      @cad.BodyPart::tube_mm(
        prefix + "_b_bearing",
        bearing.outer_mm,
        bearing.bore_mm,
        bearing.width_mm,
        rx_deg=90.0,
        density=@urdf.Density::steel(),
        color=fox_steel(),
      ).with_part(bearing_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        prefix + "_b_pin",
        bearing.bore_mm,
        crank_t + gap_t + calf_t,
        y_mm=-leg_y_sign * (crank_t + gap_t) / 2.0,
        rx_deg=90.0,
        density=@urdf.Density::steel(),
        color=fox_steel(),
      ).with_part(pin_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        prefix + "_d_bearing",
        bearing.outer_mm,
        bearing.bore_mm,
        bearing.width_mm,
        x_mm=params.coupler_len_mm,
        rx_deg=90.0,
        density=@urdf.Density::steel(),
        color=fox_steel(),
      ).with_part(bearing_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        prefix + "_d_pin",
        bearing.bore_mm,
        crank_t + gap_t + calf_t,
        x_mm=params.coupler_len_mm,
        y_mm=-leg_y_sign * (crank_t + gap_t) / 2.0,
        rx_deg=90.0,
        density=@urdf.Density::steel(),
        color=fox_steel(),
      ).with_part(pin_part),
    )
    .add_mate_mm_deg("pivot_b", y=calf_inboard_y, axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg(
      "wheel_act_mount",
      x=wx,
      y=calf_inboard_y,
      z=wz,
      rx_deg=if leg_y_sign > 0.0 { -90.0 } else { 90.0 },
      axis=(0.0, 0.0, -1.0),
    )
    .attach(
      prefix + "_wheel_act_joint",
      parent_mate="wheel_act_mount",
      wheel_act,
      child_mate="mount_flange",
      spec=@cad.JointSpec::merge_rigid(),
      explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=70.0, order=2)),
    )
    // Wheel spin joint at the outboard face of A12-OUTPUT-HUB-80:
    // `calf_outboard_y + leg_y_sign * hub_t`. Rotate so `TIRE-MOUNT-86.3`'s
    // `-X` (`front-face` -> `rear-face`) points OUTBOARD along `leg_y_sign * Y`.
    .add_mate_mm_deg(
      "wheel_axle",
      x=wx,
      y=calf_outboard_y + leg_y_sign * hub_t,
      z=wz,
      rz_deg=if leg_y_sign > 0.0 { -90.0 } else { 90.0 },
      axis=(-1.0, 0.0, 0.0),
    )
    .attach(
      prefix + "_wheel_joint",
      parent_mate="wheel_axle",
      wheel_comp,
      child_mate="front-face",
      spec=@cad.JointSpec::continuous_limit(effort=50.0, velocity=30.0),
      explode=Some(
        @cad.ExplodeSpec::offset_mm(
          dx=0.0,
          dy=leg_y_sign * 70.0,
          dz=0.0,
          order=4,
        ),
      ),
    )
    .with_print_bed_orient(@cad.PrintBedOrient::AutoFlatLargestFace)

  // 5. Hip crank link (local origin at A=(0,0), Pivot B at (-L1, 0),
  //    local Y = 0 sits at `plane1_mid`).
  let crank_sk = fox_hip_crank_sketch(params)
  let crank_to_calf_y = leg_y_sign * (crank_t / 2.0 + gap_t)
  let crank = @cad.Component::new(
      prefix + "_crank",
      description="FOX_BOT \{prefix} orange truss hip crank arm (A -> B)",
    )
    .add_body(
      @cad.BodyPart::extruded_sketch_mm(
        prefix + "_crank_body",
        crank_sk,
        @step_cad.Plane::XZ,
        crank_t,
        centered=true,
        density=@urdf.Density::cf_nylon(),
        color=fox_orange(),
      ).with_part(crank_part),
    )
    .add_mate_mm_deg("pivot_a", axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg(
      "pivot_b",
      x=-params.crank_len_mm,
      y=crank_to_calf_y,
      axis=(0.0, 1.0, 0.0),
    )
    .attach(
      prefix + "_knee_joint",
      parent_mate="pivot_b",
      calf,
      child_mate="pivot_b",
      spec=@cad.JointSpec::revolute_deg(
        lower_deg=-180.0,
        upper_deg=180.0,
        effort=0.0,
        velocity=20.0,
      ),
      explode=Some(
        @cad.ExplodeSpec::offset_mm(
          dx=0.0,
          dy=leg_y_sign * 55.0,
          dz=0.0,
          order=3,
        ),
      ),
    )
    .with_print_bed_orient(@cad.PrintBedOrient::AutoFlatLargestFace)

  // 6. Upper curved parallel guide link (local origin at C=(0,0), Pivot D at (-L3, 0)).
  let guide_sk = fox_guide_link_sketch(params)
  let guide = @cad.Component::new(
      prefix + "_guide",
      description="FOX_BOT \{prefix} curved upper parallel guide link (C -> D)",
    )
    .add_body(
      @cad.BodyPart::extruded_sketch_mm(
        prefix + "_guide_body",
        guide_sk,
        @step_cad.Plane::XZ,
        crank_t,
        centered=true,
        density=@urdf.Density::cf_nylon(),
        color=fox_carbon(),
      ).with_part(guide_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        prefix + "_c_spacer",
        24.0,
        bearing.bore_mm,
        hub_t,
        y_mm=-leg_y_sign * (crank_t / 2.0 + hub_t / 2.0),
        rx_deg=90.0,
        density=@urdf.Density::cf_nylon(),
        color=fox_dark(),
      ).with_part(standoff_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        prefix + "_c_bearing",
        bearing.outer_mm,
        bearing.bore_mm,
        bearing.width_mm,
        rx_deg=90.0,
        density=@urdf.Density::steel(),
        color=fox_steel(),
      ).with_part(bearing_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        prefix + "_c_pin",
        bearing.bore_mm,
        bracket_t + hub_t + crank_t,
        y_mm=-leg_y_sign * (bracket_t + hub_t) / 2.0,
        rx_deg=90.0,
        density=@urdf.Density::steel(),
        color=fox_steel(),
      ).with_part(pin_part),
    )
    .add_mate_mm_deg("pivot_c", axis=(0.0, 1.0, 0.0))
    .with_print_bed_orient(@cad.PrintBedOrient::AutoFlatLargestFace)

  // 7. Attach hip actuator (inboard of hip bracket), hip crank (Plane 1),
  //    and upper guide link (Plane 1) onto the chassis at this corner!
  let ax_world = world_x_sign * params.hip_x_mm
  let cx_world = world_x_sign * (params.hip_x_mm - 60.0 * s)
  let cz_world = 26.0 * s
  let hip_act_mate = prefix + "_hip_act_mount"
  let hip_pivot_mate = prefix + "_hip_pivot"
  let guide_pivot_mate = prefix + "_guide_pivot"
  // Suppress unused warning on mount_spec (used for wheel bolt phase consistency)
  let _ = mount_spec.bolt_hole_phase_deg

  chassis
  .add_mate_mm_deg(
    hip_act_mate,
    x=ax_world,
    y=world_y_sign * rail_outer_y,
    z=0.0,
    rx_deg=if world_y_sign > 0.0 { -90.0 } else { 90.0 },
    axis=(0.0, 0.0, -1.0),
  )
  .attach(
    prefix + "_hip_act_joint",
    parent_mate=hip_act_mate,
    hip_act,
    child_mate="mount_flange",
    spec=@cad.JointSpec::merge_rigid(),
    explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=65.0, order=1)),
  )
  .add_mate_mm_deg(
    hip_pivot_mate,
    x=ax_world,
    y=world_y_sign * plane1_mid,
    z=0.0,
    rz_deg=rz,
    axis=(0.0, 1.0, 0.0),
  )
  .attach(
    prefix + "_hip_joint",
    parent_mate=hip_pivot_mate,
    crank,
    child_mate="pivot_a",
    spec=@cad.JointSpec::revolute_deg(
      lower_deg=-70.0,
      upper_deg=-10.0,
      effort=80.0,
      velocity=18.0,
    ),
    explode=Some(
      @cad.ExplodeSpec::offset_mm(dx=0.0, dy=leg_y_sign * 45.0, dz=0.0, order=2),
    ),
  )
  .add_mate_mm_deg(
    guide_pivot_mate,
    x=cx_world,
    y=world_y_sign * plane1_mid,
    z=cz_world,
    rz_deg=rz,
    axis=(0.0, 1.0, 0.0),
  )
  .attach(
    prefix + "_guide_joint",
    parent_mate=guide_pivot_mate,
    guide,
    child_mate="pivot_c",
    spec=@cad.JointSpec::revolute_deg(
      lower_deg=-90.0,
      upper_deg=90.0,
      effort=0.0,
      velocity=20.0,
    ),
    explode=Some(
      @cad.ExplodeSpec::offset_mm(
        dx=0.0,
        dy=leg_y_sign * 45.0,
        dz=25.0,
        order=2,
      ),
    ),
  )
  // Closed-chain loop constraint at Pivot D: calf's URDF link origin sits at
  // `pivot_b` (`plane2_in`), which is `leg_y_sign * (crank_t/2 + gap_t)`
  // outboard of `guide`'s link origin (`plane1_mid`).
  .add_loop_constraint(
    name=prefix + "_pivot_d_loop",
    body1=prefix + "_calf",
    anchor1=(params.coupler_len_mm, -leg_y_sign * (crank_t / 2.0 + gap_t), 0.0),
    body2=prefix + "_guide",
    anchor2=(params.guide_len_mm, 0.0, 0.0),
  )
  // Control bindings mirroring FOX_BOT CAN IDs: wheels 1-4, hips 5-8 (LF, RF, RR, LR)
  .add_control_binding(
    @cad.ControlBinding::new(
      prefix + "_hip_joint",
      actuator=prefix + "_hip_act",
      channel="can0:\{hip_can_id}",
      direction=if is_left { "normal" } else { "inverted" },
      gear_ratio=5.333333333333333,
    ),
  )
  .add_control_binding(
    @cad.ControlBinding::new(
      prefix + "_wheel_joint",
      actuator=prefix + "_wheel_act",
      channel="can0:\{wheel_can_id}",
      direction=if is_left { "normal" } else { "inverted" },
      gear_ratio=5.333333333333333,
    ),
  )
}

///|
/// Builds the complete FOX_BOT wheeled-quadruped robot assembly.
///
/// Pass `moteus_step` and `tire_mount_step` from the CLI for vendor moteus C1
/// geometry and SMLib-evaluated `TIRE-MOUNT-86.3` solids; pass `None` in fast
/// unit tests for instant pure-MoonBit evaluation.
pub fn fox_bot(
  params~ : FoxBotParams = FoxBotParams::default(),
  moteus_step~ : String? = None,
  tire_mount_step~ : String? = None,
) -> @cad.Component {
  let mut robot = build_fox_chassis(params)
  // FOX_BOT leg index order & CAN IDs:
  //   LF: wheel 1, hip 5
  //   RF: wheel 2, hip 6
  //   RR: wheel 3, hip 7
  //   LR: wheel 4, hip 8
  let legs : Array[(String, Bool, Bool, Int32, Int32)] = [
    ("lf", true, true, 5, 1),
    ("rf", true, false, 6, 2),
    ("rr", false, false, 7, 3),
    ("lr", false, true, 8, 4),
  ]
  for entry in legs {
    let (prefix, is_front, is_left, hip_id, wheel_id) = entry
    robot = attach_fox_leg(
      robot, params, prefix, is_front, is_left, hip_id, wheel_id, moteus_step, tire_mount_step,
    )
  }
  robot
  .with_robot_name("fox_bot")
  .with_rl_task(
    @cad.RlTaskSpec::new(
      kind=@cad.RlTaskKind::JumpAndLevel,
      control_dt_s=0.01,
      episode_len_s=10.0,
      target_base_height_m=0.42,
      target_vel_x_mps=0.5,
      termination_tilt_deg=55.0,
      termination_min_z_m=0.20,
      imu_link="bno055_imu",
      wheel_links=["lf_tire", "rf_tire", "rr_tire", "lr_tire"],
      hip_joints=[
        "lf_hip_joint", "rf_hip_joint", "rr_hip_joint", "lr_hip_joint",
      ],
      wheel_joints=[
        "lf_wheel_joint", "rf_wheel_joint", "rr_wheel_joint", "lr_wheel_joint",
      ],
      action_scales=fox_rl_scales(),
      domain_rand=@cad.DomainRandSpec::new(
        push_impulse_ns=2.0,
        obs_noise_std=0.01,
      ),
    ),
  )
}

///|
fn fox_rl_scales() -> Map[String, Double] {
  let scales : Map[String, Double] = Map([])
  for leg in ["lf", "rf", "rr", "lr"] {
    scales.set(leg + "_hip_joint", 0.5)
    scales.set(leg + "_wheel_joint", 4.0)
  }
  scales
}

///|
pub async fn run_cli() -> Unit {
  let defaults = FoxBotParams::default()
  let base_spec : Map[String, @cli.Arg] = {
    "scale": @cli.opt_double(
      defaults.scale,
      help="Uniform robot scale factor (keeps A12 motor and 7 in tire envelopes fixed; >= 0.75)",
    ),
    "chassisLength": @cli.opt_double(
      0.0,
      help="Override 20x20 rail chassis length in mm (0 = scaled default)",
    ),
    "innerWidth": @cli.opt_double(
      0.0,
      help="Override inner bay width in mm (0 = scaled default, auto-clamped to clear hip actuators)",
    ),
    "crankLength": @cli.opt_double(
      0.0,
      help="Override hip crank length A->B in mm (0 = scaled default)",
    ),
    "calfLength": @cli.opt_double(
      0.0,
      help="Override calf length B->W in mm (0 = scaled default)",
    ),
    "gearModule": @cli.opt_double(
      defaults.gear_module_mm,
      help="Planetary gear module in mm (default 2.0)",
    ),
    "gearLength": @cli.opt_double(
      defaults.gear_length_mm,
      help="Planetary gear face width in mm (default 12.0)",
    ),
    "numElbows": @cli.opt_int(
      defaults.num_elbows,
      help="Number of herringbone gear elbows (default 4)",
    ),
    "tolerance": @cli.opt_double(
      defaults.tolerance_mm,
      help="Print-in-place gear clearance in mm (0.042 for 1Off PETG, 0.25 for home PLA; outer envelope invariant)",
    ),
    "pose": @cli.opt_string(
      help="Preset stance: mid (default), crouched, tall, roll, pitch, pounce, or ref",
    ),
    "rollDeg": @cli.opt_double(
      0.0,
      help="Differential body roll offset in deg (-32..+32)",
    ),
    "pitchDeg": @cli.opt_double(
      0.0,
      help="Differential body pitch offset in deg (-25..+25)",
    ),
    "heave": @cli.opt_double(
      0.0,
      help="Normalized body height heave (-1 crouched .. +1 tall)",
    ),
    "wheelSpinDeg": @cli.opt_double(0.0, help="Wheel spin angle in deg"),
    "explode": @cli.flag(help="Output color-coded exploded view to -o/--out"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="09-fox-bot",
      description="FOX_BOT wheeled-quadruped active-suspension robot with 8x A12 8318 + 4-elbow herringbone planetary actuators, TIRE-MOUNT-86.3, and 7-inch WHEEL-7IN tires.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let base = FoxBotParams::scaled(args.double("scale"))
  let params : FoxBotParams = {
    ..base,
    chassis_len_mm: if args.double("chassisLength") > 0.0 {
      args.double("chassisLength")
    } else {
      base.chassis_len_mm
    },
    inner_width_mm: if args.double("innerWidth") > 0.0 {
      args.double("innerWidth")
    } else {
      base.inner_width_mm
    },
    crank_len_mm: if args.double("crankLength") > 0.0 {
      args.double("crankLength")
    } else {
      base.crank_len_mm
    },
    calf_len_mm: if args.double("calfLength") > 0.0 {
      args.double("calfLength")
    } else {
      base.calf_len_mm
    },
    gear_module_mm: args.double("gearModule"),
    gear_length_mm: args.double("gearLength"),
    num_elbows: args.int("numElbows"),
    tolerance_mm: args.double("tolerance"),
    pose: args.string_opt("pose").unwrap_or("mid"),
    roll_deg: args.double("rollDeg"),
    pitch_deg: args.double("pitchDeg"),
    heave: args.double("heave"),
    wheel_spin_deg: args.double("wheelSpinDeg"),
    detail: output.detail_level(),
  }

  let moteus_text : String? = Some(
    @fs.read_file("components/vendor/20240305-moteus-c1-r1_2.step").text(),
  ) catch {
    _ => None
  }
  let tire_mount_eval : String? = match @step_motion.measured_tire_mount() {
    Ok(comp) => Some(comp.to_step_evaluated()) catch { _ => None }
    Err(_) => None
  }
  let robot = fox_bot(
    params~,
    moteus_step=moteus_text,
    tire_mount_step=tire_mount_eval,
  )
  let joint_positions = params.pose_positions()
  if args.flag("explode") {
    let exp_design = robot.to_exploded_design(
      joint_positions~,
      trace_lines=true,
    )
    match output.step {
      Some(path) =>
        @step_cad.write_text_file(
          exp_design.to_instanced_step_string(
            assembly_name="FOX_BOT (Exploded)",
          ),
          if path == "-" {
            None
          } else {
            Some(path)
          },
        )
      None => exp_design.write_step_file(None)
    }
    return
  }
  @common.write_output(
    robot,
    output,
    joint_positions~,
    example_dir="examples/09-fox-bot",
  )
}
