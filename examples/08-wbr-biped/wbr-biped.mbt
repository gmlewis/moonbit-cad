///|
/// 08-wbr-biped — Ascento / POW-inspired 4-bar Wheeled Bipedal Robot (WBR)
/// built around A12 8318 100KV brushless motors and 4-elbow print-in-place
/// herringbone planetary gearboxes.
///
/// Mechanical architecture (matching the video design, scaled and adapted for
/// DIY 3D printing with A12 + 4-elbow planetary actuators):
/// - Chamfered white printable monocoque chassis (`WBR-SIDE-PLATE`,
///   `WBR-TOP-LID`, `WBR-NOSE-COWL`, `WBR-BELLY-POD`, `WBR-REAR-BULKHEAD`) with
///   angled front 6S LiPo battery cradle, XT60 plug, twin front ToF sensors,
///   and lower belly pod holding the 6-DOF IMU + ESP32-S3 CAN controller for
///   EKF + LQR balance control.
/// - Planar closed-chain 4-bar leg linkage (`A-B-D-C`) on each side so ONE hip
///   actuator raises and lowers each wheel nearly vertically under the chassis
///   CoM across a ~170 mm suspension/jump stroke (`crouched`, `standing`,
///   `tall`, `pitched`).
/// - Four identical A12 8318 100KV + 4-elbow herringbone planetary actuators
///   (2x hip mounted inside the rear chassis walls; 2x wheel mounted inboard
///   of the lower calf struts, matching the reference layout).
/// - Master `--scale` plus direct linkage, wheel, gear-module, and printing
///   `--tolerance` parameters (e.g. `0.042` PETG vs `0.25` PLA with invariant
///   outer housing dimensions).

///|
fn shell_white() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.94, 0.95, 0.96)
}

///|
fn link_white() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.89, 0.91, 0.93)
}

///|
fn housing_slate() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.24, 0.27, 0.32)
}

///|
fn hub_amber() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.92, 0.54, 0.14)
}

///|
fn dark_matte() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.10, 0.11, 0.12)
}

///|
fn steel_grey() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.74, 0.76, 0.79)
}

///|
fn xt60_yellow() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.96, 0.72, 0.08)
}

///|
fn pcb_green() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.12, 0.48, 0.24)
}

///|
fn wbr_printed(
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
fn wbr_purchased(
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
/// Master parameter bundle for sizing and tuning the 4-bar WBR.
pub(all) struct WbrParams {
  scale : Double
  body_len_mm : Double
  body_width_mm : Double
  body_height_mm : Double
  crank_len_mm : Double
  coupler_len_mm : Double
  guide_len_mm : Double
  calf_len_mm : Double
  wheel_diam_mm : Double
  wheel_width_mm : Double
  gear_module_mm : Double
  gear_length_mm : Double
  sun_teeth : Int32
  planet_teeth : Int32
  planet_count : Int32
  num_elbows : Int32
  tolerance_mm : Double
  detail : @step_common.DetailLevel
}

///|
/// Builds validated WBR dimensions from a master `scale` plus optional
/// per-dimension overrides.
pub fn WbrParams::new(
  scale~ : Double = 1.0,
  body_len_mm~ : Double = 0.0,
  body_width_mm~ : Double = 0.0,
  body_height_mm~ : Double = 0.0,
  crank_len_mm~ : Double = 0.0,
  coupler_len_mm~ : Double = 0.0,
  guide_len_mm~ : Double = 0.0,
  calf_len_mm~ : Double = 0.0,
  wheel_diam_mm~ : Double = 0.0,
  wheel_width_mm~ : Double = 0.0,
  gear_module_mm~ : Double = 2.0,
  gear_length_mm~ : Double = 12.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 20,
  planet_count~ : Int32 = 4,
  num_elbows~ : Int32 = 4,
  tolerance_mm~ : Double = 0.20,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> WbrParams {
  let s = if scale < 0.65 { 0.65 } else if scale > 2.0 { 2.0 } else { scale }
  let g_len = if gear_length_mm < 8.0 { 8.0 } else { gear_length_mm }
  let act_depth = 4.0 + 33.0 + 5.0 + g_len + 1.0 + 8.0 + 10.0
  let wall_est = if 8.0 * s < 6.0 { 6.0 } else { 8.0 * s }
  let min_bw = 2.0 * (act_depth + wall_est) + 36.0
  let raw_bw = if body_width_mm > 0.0 { body_width_mm } else { 220.0 * s }
  let bw = if raw_bw < min_bw { min_bw } else { raw_bw }
  {
    scale: s,
    body_len_mm: if body_len_mm > 0.0 {
      body_len_mm
    } else {
      280.0 * s
    },
    body_width_mm: bw,
    body_height_mm: if body_height_mm > 0.0 {
      body_height_mm
    } else {
      175.0 * s
    },
    crank_len_mm: if crank_len_mm > 0.0 {
      crank_len_mm
    } else {
      128.0 * s
    },
    coupler_len_mm: if coupler_len_mm > 0.0 {
      coupler_len_mm
    } else {
      76.0 * s
    },
    guide_len_mm: if guide_len_mm > 0.0 {
      guide_len_mm
    } else {
      165.0 * s
    },
    calf_len_mm: if calf_len_mm > 0.0 {
      calf_len_mm
    } else {
      225.0 * s
    },
    wheel_diam_mm: if wheel_diam_mm > 0.0 {
      wheel_diam_mm
    } else {
      178.0 * s
    },
    wheel_width_mm: if wheel_width_mm > 0.0 {
      wheel_width_mm
    } else {
      38.0 * s
    },
    gear_module_mm: if gear_module_mm < 1.25 {
      1.25
    } else {
      gear_module_mm
    },
    gear_length_mm: g_len,
    sun_teeth,
    planet_teeth,
    planet_count,
    num_elbows,
    tolerance_mm,
    detail,
  }
}

///|
/// Derived 4-bar linkage closure solution in the sagittal X-Z plane.
pub(all) struct FourBarSolution {
  ax : Double
  az : Double
  cx : Double
  cz : Double
  bx : Double
  bz : Double
  dx : Double
  dz : Double
  wx : Double
  wz : Double
  hip_joint_rad : Double
  knee_joint_rad : Double
  guide_joint_rad : Double
  transmission_deg : Double
}

///|
/// Calf angular offset from the `B -> D` coupler ray to the `B -> W` wheel ray.
fn wbr_calf_beta_rad() -> Double {
  -4.0 * @math.PI / 180.0
}

///|
/// Chassis pivot coordinates `(ax, az)` (rear-upper actuated hip) and
/// `(cx, cz)` (forward-lower passive guide) in the chassis frame.
pub fn wbr_chassis_pivots(
  params : WbrParams,
) -> (Double, Double, Double, Double) {
  let sx = params.body_len_mm / 280.0
  let sz = params.body_height_mm / 175.0
  (-88.0 * sx, -18.0 * sz, 12.0 * sx, -70.0 * sz)
}

///|
/// Solves the planar 4-bar closed-chain linkage (`A-B-D-C`) for a requested
/// hip crank depression angle `hip_deg` (measured downward from `-X`).
pub fn solve_four_bar(params : WbrParams, hip_deg : Double) -> FourBarSolution {
  let (ax, az, cx, cz) = wbr_chassis_pivots(params)
  let l1 = params.crank_len_mm
  let l2 = params.coupler_len_mm
  let l3 = params.guide_len_mm
  let l_calf = params.calf_len_mm
  let hip_rad = hip_deg * @math.PI / 180.0
  let bx = ax - l1 * @math.cos(hip_rad)
  let bz = az - l1 * @math.sin(hip_rad)
  let dx_bc = cx - bx
  let dz_bc = cz - bz
  let dist = Double::sqrt(dx_bc * dx_bc + dz_bc * dz_bc)
  if dist >= l2 + l3 - 1.0e-4 || dist <= (l2 - l3).abs() + 1.0e-4 {
    abort(
      "4-bar linkage cannot close at hipDeg=\{hip_deg} (dist=\{dist}, L2=\{l2}, L3=\{l3})",
    )
  }
  let a = (l2 * l2 - l3 * l3 + dist * dist) / (2.0 * dist)
  let h_sq = l2 * l2 - a * a
  let h = if h_sq > 0.0 { Double::sqrt(h_sq) } else { 0.0 }
  let mx = bx + a * dx_bc / dist
  let mz = bz + a * dz_bc / dist
  let c1x = mx + h * (-dz_bc / dist)
  let c1z = mz + h * (dx_bc / dist)
  let c2x = mx - h * (-dz_bc / dist)
  let c2z = mz - h * (dx_bc / dist)
  // Pick the lower-Z branch so D sits below B (Ascento knee posture).
  let (dx, dz) = if c1z < c2z { (c1x, c1z) } else { (c2x, c2z) }
  let phi = @math.atan2(dz - bz, dx - bx)
  let psi = @math.atan2(dz - cz, dx - cx)
  let w_ang = phi + wbr_calf_beta_rad()
  let wx = bx + l_calf * @math.cos(w_ang)
  let wz = bz + l_calf * @math.sin(w_ang)
  let v1x = bx - dx
  let v1z = bz - dz
  let v2x = cx - dx
  let v2z = cz - dz
  let denom = Double::sqrt(v1x * v1x + v1z * v1z) *
    Double::sqrt(v2x * v2x + v2z * v2z)
  let raw_cos = if denom > 1.0e-9 {
    (v1x * v2x + v1z * v2z) / denom
  } else {
    0.0
  }
  let clamped_cos = if raw_cos > 1.0 {
    1.0
  } else if raw_cos < -1.0 {
    -1.0
  } else {
    raw_cos
  }
  let trans_deg = @math.acos(clamped_cos) * 180.0 / @math.PI
  // Revolute axis is +Y: R_y(q) maps (-1,0,0) -> (-cos(q),0,sin(q)) and
  // (+1,0,0) -> (cos(q),0,-sin(q)).
  let hip_joint_rad = -hip_rad
  let knee_joint_rad = hip_rad - phi
  let guide_joint_rad = -psi
  {
    ax,
    az,
    cx,
    cz,
    bx,
    bz,
    dx,
    dz,
    wx,
    wz,
    hip_joint_rad,
    knee_joint_rad,
    guide_joint_rad,
    transmission_deg: trans_deg,
  }
}

///|
/// Named pose presets (`standing`, `crouched`, `tall`, `pitched`) -> hip crank
/// angle in degrees.
pub fn pose_hip_deg(pose : String) -> Double {
  match pose {
    "crouched" => 10.0
    "tall" => 62.0
    "pitched" => 35.0
    _ => 35.0
  }
}

///|
/// Computes the joint position map (radians) closing the 4-bar linkage on both
/// legs for the requested pose or explicit hip angle.
pub fn pose_positions(
  params : WbrParams,
  pose~ : String = "standing",
  hip_deg~ : Double? = None,
  wheel_spin_deg~ : Double = 0.0,
) -> Map[String, Double] {
  let h_deg = hip_deg.unwrap_or(pose_hip_deg(pose))
  let sol = solve_four_bar(params, h_deg)
  let deg = @math.PI / 180.0
  let positions : Map[String, Double] = Map([])
  positions.set("l_hip_joint", sol.hip_joint_rad)
  positions.set("r_hip_joint", sol.hip_joint_rad)
  positions.set("l_knee_joint", sol.knee_joint_rad)
  positions.set("r_knee_joint", sol.knee_joint_rad)
  positions.set("l_guide_joint", sol.guide_joint_rad)
  positions.set("r_guide_joint", sol.guide_joint_rad)
  positions.set("l_wheel_joint", wheel_spin_deg * deg)
  positions.set("r_wheel_joint", wheel_spin_deg * deg)
  positions
}

///|
/// Regular circle polygon in 2D. `ccw = true` for outer profiles, `false` for
/// holes.
fn circle_poly_2d(
  cx : Double,
  cy : Double,
  r : Double,
  segs : Int32,
  ccw : Bool,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  let two_pi = 2.0 * @math.PI
  for i in 0..<segs {
    let idx = if ccw { i } else { segs - 1 - i }
    let theta = two_pi * idx.to_double() / segs.to_double()
    pts.push((cx + r * @math.cos(theta), cy + r * @math.sin(theta)))
  }
  pts
}

///|
/// Ensures a 2D polygon has positive signed area (CCW) or negative (CW).
fn ensure_winding(
  pts : Array[(Double, Double)],
  ccw : Bool,
) -> Array[(Double, Double)] {
  let area = @step_cad.polygon_area_2d(pts)
  if (ccw && area < 0.0) || (!ccw && area > 0.0) {
    pts.rev()
  } else {
    pts
  }
}

///|
/// Rounded-nose faceted chassis side plate profile matching the video WBR
/// silhouette in `(X, Z)` coordinates.
fn side_plate_profile(params : WbrParams) -> Array[(Double, Double)] {
  let sx = params.body_len_mm / 280.0
  let sz = params.body_height_mm / 175.0
  let pts : Array[(Double, Double)] = [
    // Lower rear tail wrapping cleanly around hip A12 actuator + 6x M4 bolts
    (-154.0 * sx, -56.0 * sz),
    (-90.0 * sx, -96.0 * sz),
    // Forward passive pivot C boss bulge
    (12.0 * sx, -98.0 * sz),
    (54.0 * sx, -78.0 * sz),
    (106.0 * sx, -64.0 * sz),
  ]
  // Rounded semi-circular front nose (+X)
  let nose_cx = 106.0 * sx
  let nose_cz = -18.0 * sz
  let nose_rx = 36.0 * sx
  let nose_rz = 46.0 * sz
  let nose_steps = 8
  for i in 1..<nose_steps {
    let a = -0.5 * @math.PI + @math.PI * i.to_double() / nose_steps.to_double()
    pts.push(
      (nose_cx + nose_rx * @math.cos(a), nose_cz + nose_rz * @math.sin(a)),
    )
  }
  // Upper sloped battery hood -> flat top deck -> angled rear bevel
  pts.push((106.0 * sx, 28.0 * sz))
  pts.push((48.0 * sx, 88.0 * sz))
  pts.push((-92.0 * sx, 88.0 * sz))
  pts.push((-154.0 * sx, 38.0 * sz))
  pts.push((-154.0 * sx, -24.0 * sz))
  ensure_winding(pts, true)
}

///|
/// Curved arched boomerang upper hip crank (`A=(0,0)` to `B=(-L1,0)`) in
/// local `(X, Z)` coordinates, matching the video's curved rear hip arm.
fn hip_crank_profile(
  l1 : Double,
  r_a : Double,
  r_b : Double,
  arch_z : Double,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  let steps = 10
  // Upper arch from Pivot A (0, r_a) to Pivot B (-L1, r_b)
  for i in 0..<=steps {
    let t = i.to_double() / steps.to_double()
    let x = -l1 * t
    let r = r_a * (1.0 - t) + r_b * t
    let bulge = arch_z * @math.sin(@math.PI * t)
    pts.push((x, bulge + r))
  }
  // Semicircle around Pivot B (-L1, 0)
  for i in 1..<8 {
    let a = 0.5 * @math.PI + @math.PI * i.to_double() / 8.0
    pts.push((-l1 + r_b * @math.cos(a), r_b * @math.sin(a)))
  }
  // Lower arch from Pivot B back to Pivot A
  for i in 0..<=steps {
    let t = 1.0 - i.to_double() / steps.to_double()
    let x = -l1 * t
    let r = r_a * (1.0 - t) + r_b * t
    let bulge = arch_z * 0.72 * @math.sin(@math.PI * t)
    pts.push((x, bulge - r))
  }
  // Semicircle around Pivot A (0, 0)
  for i in 1..<8 {
    let a = -0.5 * @math.PI + @math.PI * i.to_double() / 8.0
    pts.push((r_a * @math.cos(a), r_a * @math.sin(a)))
  }
  ensure_winding(pts, true)
}

///|
/// Forward dogleg parallel guide link (`C=(0,0)` to `D=(+L3,0)`) in local
/// `(X, Z)` coordinates.
fn guide_link_profile(
  l3 : Double,
  r_end : Double,
  half_w : Double,
  bow_z : Double,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  let steps = 8
  // Lower edge from C (0, -r_end) to D (L3, -r_end)
  for i in 0..<=steps {
    let t = i.to_double() / steps.to_double()
    let x = l3 * t
    let w = if i == 0 || i == steps { r_end } else { half_w }
    let z_mid = bow_z * @math.sin(@math.PI * t)
    pts.push((x, z_mid - w))
  }
  // Semicircle around Pivot D (L3, 0)
  for i in 1..<8 {
    let a = -0.5 * @math.PI + @math.PI * i.to_double() / 8.0
    pts.push((l3 + r_end * @math.cos(a), r_end * @math.sin(a)))
  }
  // Upper edge from D back to C
  for i in 0..<=steps {
    let t = 1.0 - i.to_double() / steps.to_double()
    let x = l3 * t
    let w = if i == 0 || i == steps { r_end } else { half_w }
    let z_mid = bow_z * @math.sin(@math.PI * t)
    pts.push((x, z_mid + w))
  }
  // Semicircle around Pivot C (0, 0)
  for i in 1..<8 {
    let a = 0.5 * @math.PI + @math.PI * i.to_double() / 8.0
    pts.push((r_end * @math.cos(a), r_end * @math.sin(a)))
  }
  ensure_winding(pts, true)
}

///|
/// Sculpted main calf strut (`B=(0,0)`, `D=(L2,0)`, `W=(wx, wz)`) in local
/// `(X, Z)` coordinates, combining the knee clevis head (`B-D`) and tapered
/// lower wheel-actuator hub mount at `W`.
fn calf_strut_profile(
  l2 : Double,
  wx : Double,
  wz : Double,
  r_knee : Double,
  r_wheel_mount : Double,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  let w_ang = @math.atan2(wz, wx)
  let nx = -@math.sin(w_ang)
  let nz = @math.cos(w_ang)
  // Upper contour: B top -> D top -> W top
  pts.push((0.0, r_knee))
  pts.push((l2 * 0.5, r_knee * 0.92))
  pts.push((l2, r_knee * 1.05))
  pts.push((l2 + 18.0, r_knee * 0.78))
  pts.push((wx + nx * r_wheel_mount, wz + nz * r_wheel_mount))
  // Semicircle around wheel mount center W
  for i in 1..<10 {
    let a = w_ang + 0.5 * @math.PI - @math.PI * i.to_double() / 10.0
    pts.push(
      (wx + r_wheel_mount * @math.cos(a), wz + r_wheel_mount * @math.sin(a)),
    )
  }
  // Lower contour: W bottom -> D bottom -> B bottom
  pts.push((wx - nx * r_wheel_mount, wz - nz * r_wheel_mount))
  pts.push((l2 + 10.0, -r_knee * 0.88))
  pts.push((l2, -r_knee * 1.05))
  pts.push((l2 * 0.5, -r_knee * 0.92))
  pts.push((0.0, -r_knee))
  // Semicircle around Pivot B (0, 0)
  for i in 1..<8 {
    let a = -0.5 * @math.PI - @math.PI * i.to_double() / 8.0
    pts.push((r_knee * @math.cos(a), r_knee * @math.sin(a)))
  }
  ensure_winding(pts, true)
}

///|
/// Derived geometry of the A12 + 4-elbow herringbone planetary actuator unit.
priv struct WbrActuatorDims {
  layout : @step_planetary.HerringbonePlanetaryLayout
  step_params : @step_planetary.HerringbonePlanetaryParams
  outer_radius_mm : Double
  flange_radius_mm : Double
  flange_bcd_mm : Double
  motor_z0 : Double
  gear_z0 : Double
  carrier_z0 : Double
  cap_z0 : Double
  total_len_mm : Double
}

///|
fn wbr_actuator_dims(params : WbrParams) -> WbrActuatorDims {
  let bearing = @components.flanged_bearing_fr8_2rs()
  let res : Int32 = match params.detail {
    @step_common.DetailLevel::Simplified => 5
    _ => 7
  }
  // Ensure outer ring diameter exceeds the 91 mm A12 motor + wall cleanly.
  let min_outer_r = 55.0
  let trial = match
    @step_planetary.HerringbonePlanetaryParams::new(
      module_mm=params.gear_module_mm,
      gear_length_mm=params.gear_length_mm,
      helix_angle_deg=30.0,
      pressure_angle_deg=20.0,
      num_elbows=params.num_elbows,
      resolution=res,
      hole_type="Circular",
      hole_radius_mm=6.2,
      sun_hole_radius_mm=6.2,
      planet_hole_radius_mm=bearing.outer_mm / 2.0 - 0.03,
      tolerance_mm=params.tolerance_mm,
      outer_thickness_mm=6.0,
      sun_teeth=params.sun_teeth,
      planet_count=params.planet_count,
      planet_teeth=params.planet_teeth,
    ) {
    Ok(p) => p
    Err(e) => abort("invalid WBR planetary params: " + e.message())
  }
  let trial_layout = @step_planetary.herringbone_planetary_layout(trial)
  let base_r = trial_layout.ring_outer_radius_mm - 6.0
  let outer_r = if base_r + 6.0 > min_outer_r {
    base_r + 6.0
  } else {
    min_outer_r
  }
  let wall = outer_r - base_r
  let step_params = match
    @step_planetary.HerringbonePlanetaryParams::new(
      module_mm=params.gear_module_mm,
      gear_length_mm=params.gear_length_mm,
      helix_angle_deg=30.0,
      pressure_angle_deg=20.0,
      num_elbows=params.num_elbows,
      resolution=res,
      hole_type="Circular",
      hole_radius_mm=6.2,
      sun_hole_radius_mm=6.2,
      planet_hole_radius_mm=bearing.outer_mm / 2.0 - 0.03,
      tolerance_mm=params.tolerance_mm,
      outer_thickness_mm=wall,
      sun_teeth=params.sun_teeth,
      planet_count=params.planet_count,
      planet_teeth=params.planet_teeth,
    ) {
    Ok(p) => p
    Err(e) => abort("invalid WBR planetary params: " + e.message())
  }
  let layout = @step_planetary.herringbone_planetary_layout(step_params)
  let motor_z0 = 4.0
  let gear_z0 = motor_z0 + 33.0 + 5.0
  let carrier_z0 = gear_z0 + params.gear_length_mm + 1.0
  let cap_z0 = carrier_z0 + 8.0
  let total_len = cap_z0 + 10.0
  let flange_r = outer_r + 7.5
  let flange_bcd = 2.0 * (outer_r + 3.8)
  {
    layout,
    step_params,
    outer_radius_mm: outer_r,
    flange_radius_mm: flange_r,
    flange_bcd_mm: flange_bcd,
    motor_z0,
    gear_z0,
    carrier_z0,
    cap_z0,
    total_len_mm: total_len,
  }
}

///|
/// Builds the standalone flat `z = 0` printable 4-elbow herringbone planetary
/// cartridge (`WBR-GEAR-CARTRIDGE`) for `build/08/printable/`.
pub fn build_planetary_cartridge(params : WbrParams) -> @cad.Component {
  let dims = wbr_actuator_dims(params)
  let step_gb = match
    @step_planetary.herringbone_planetary_gearbox(dims.step_params) {
    Ok(c) => c
    Err(e) => abort("planetary cartridge build failed: " + e.message())
  }
  let part = wbr_printed(
    "WBR-GEAR-CARTRIDGE",
    "Print-in-place 4-elbow herringbone planetary gear cartridge (m=\{params.gear_module_mm}, \{params.sun_teeth}/\{params.planet_teeth}/\{dims.layout.ring_teeth}, tol=\{params.tolerance_mm} mm)",
    "PETG / PLA",
    9.50,
  )
  @cad.Component::from_step_component(
    "wbr_gear_cartridge",
    step_gb,
    density=@urdf.Density::petg(),
    part=Some(part),
  )
}

///|
/// Builds one A12 8318 100KV + 4-elbow herringbone planetary actuator assembly.
///
/// Local frame: rear stator backplate at `z = 0`, output cap face at
/// `z = dims.total_len_mm`, output flange hub at `z = dims.total_len_mm + 8`.
fn build_a12_planetary_actuator(
  name : String,
  params : WbrParams,
  dims : WbrActuatorDims,
  gb_step : @step_common.Component,
  board_text : String,
  hub_offset_mm~ : Double = 8.0,
) -> @cad.Component {
  let bearing = @components.flanged_bearing_fr8_2rs()
  let reduction = @components.planetary_reduction(
    params.sun_teeth,
    params.planet_teeth,
    1,
  )
  let outer_d = 2.0 * dims.outer_radius_mm
  let flange_d = 2.0 * dims.flange_radius_mm
  let bolt_r = dims.flange_bcd_mm / 2.0
  let housing_part = wbr_printed(
    "WBR-ACT-HOUSING", "Printed A12 8318 stator cup & 4-elbow planetary housing with rear moteus C1 mount",
    "CF nylon / PETG", 11.0,
  )
  let adapter_part = wbr_printed(
    "WBR-SUN-ADAPTER", "Printed A12 prop-adapter to planetary sun drive coupler (4x M4 on 23 mm BCD)",
    "CF nylon / PETG", 2.50,
  )
  let cartridge_part = wbr_printed(
    "WBR-GEAR-CARTRIDGE",
    "Print-in-place 4-elbow herringbone planetary gear cartridge (m=\{params.gear_module_mm}, \{params.sun_teeth}/\{params.planet_teeth}/\{dims.layout.ring_teeth}, tol=\{params.tolerance_mm} mm)",
    "PETG / PLA",
    9.50,
  )
  let carrier_part = wbr_printed(
    "WBR-CARRIER", "Printed 4-planet carrier plate with 1/2 in dowel pin seats and 12.7 mm output shaft bore",
    "CF nylon / PETG", 5.50,
  )
  let cap_part = wbr_printed(
    "WBR-OUTPUT-CAP", "Printed output bearing cap housing FR8-2RS flanged bearing with 6x M4 flange bolt pattern",
    "CF nylon / PETG", 6.50,
  )
  let hub_part = wbr_printed(
    "WBR-OUTPUT-HUB", "Printed 60 mm output flange hub (4x M4 on 40 mm BCD) coupling 12.7 mm shaft to hip crank or wheel rim",
    "CF nylon / PETG", 4.00,
  )
  let bearing_part = wbr_purchased(
    "BEARING-FR8-2RS", "FR8-2RS flanged sealed ball bearing (12.7 x 28.575 x 7.938 mm)",
    "steel", 1.55,
  )
  let pin_part = wbr_purchased(
    "DOWEL-12.7x24", "Hardened steel dowel pin 12.7 x 24 mm", "steel", 1.50,
  )
  let shaft_part = wbr_purchased(
    "SHAFT-12.7x48", "Stainless rotary output shaft 12.7 x 48 mm", "steel", 6.00,
  )
  // Rear backplate with 4x M4 A12 stator holes (32 mm BCD) + 16 mm sensor window.
  let back_holes : Array[Array[(Double, Double)]] = [
    circle_poly_2d(0.0, 0.0, 8.0, 16, false),
  ]
  for i in 0..<4 {
    let a = (45.0 + 90.0 * i.to_double()) * @math.PI / 180.0
    back_holes.push(
      circle_poly_2d(16.0 * @math.cos(a), 16.0 * @math.sin(a), 2.2, 10, false),
    )
  }
  // Output cap plate with FR8-2RS bearing bore + 6x M4 flange tie-bolt holes.
  let cap_holes : Array[Array[(Double, Double)]] = [
    circle_poly_2d(0.0, 0.0, bearing.outer_mm / 2.0, 20, false),
  ]
  for i in 0..<6 {
    let a = (30.0 + 60.0 * i.to_double()) * @math.PI / 180.0
    cap_holes.push(
      circle_poly_2d(
        bolt_r * @math.cos(a),
        bolt_r * @math.sin(a),
        2.2,
        10,
        false,
      ),
    )
  }
  // Carrier plate with 4 planet pin holes on center_distance + 12.7 mm shaft bore.
  let carrier_r = dims.layout.center_distance_mm + bearing.bore_mm * 0.9
  let carrier_holes : Array[Array[(Double, Double)]] = [
    circle_poly_2d(0.0, 0.0, 6.35, 16, false),
  ]
  for j in 0..<params.planet_count {
    let a = 2.0 * @math.PI * j.to_double() / params.planet_count.to_double()
    carrier_holes.push(
      circle_poly_2d(
        dims.layout.center_distance_mm * @math.cos(a),
        dims.layout.center_distance_mm * @math.sin(a),
        bearing.bore_mm / 2.0,
        12,
        false,
      ),
    )
  }
  // Output flange hub with 12.7 mm shaft bore + 4x M4 on 40 mm BCD.
  let hub_holes : Array[Array[(Double, Double)]] = [
    circle_poly_2d(0.0, 0.0, 6.35, 16, false),
  ]
  for i in 0..<4 {
    let a = (45.0 + 90.0 * i.to_double()) * @math.PI / 180.0
    hub_holes.push(
      circle_poly_2d(20.0 * @math.cos(a), 20.0 * @math.sin(a), 2.2, 10, false),
    )
  }

  let a12_raw = @components.step_a12_motor(
    name=name + "_a12",
    joint_name=name + "_a12_rotor_joint",
  )
  let a12_motor = { ..a12_raw, actuator: None, }

  let mut act = @cad.Component::new(
      name,
      description="A12 8318 100KV + 4-elbow herringbone planetary actuator (\{reduction}:1)",
    )
    .with_param("motor", "A12 8318 100KV")
    .with_param("gear_module_mm", params.gear_module_mm.to_string())
    .with_param("num_elbows", params.num_elbows.to_string())
    .with_param("tolerance_mm", params.tolerance_mm.to_string())
    .with_param("reduction", reduction.to_string())
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V, 40 A"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .with_actuator(
      @cad.ActuatorSpec::new(
        @cad.ActuatorKind::Bldc,
        model="A12 8318 100KV + 4-elbow planetary (\{params.sun_teeth}/\{params.planet_teeth}/\{dims.layout.ring_teeth})",
        voltage_v=24.0,
        current_rated_a=25.0,
        current_stall_a=60.0,
        torque_rated_nm=18.0 * reduction / 5.3333,
        driver="moteus C1 / FOC",
        interface="CAN",
        encoder="AS5047P",
      ),
    )
    // Backplate (z = 0..4)
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_backplate",
        circle_poly_2d(0.0, 0.0, dims.outer_radius_mm, 32, true),
        4.0,
        holes=back_holes,
        z_mm=2.0,
        density=@urdf.Density::petg(),
        color=housing_slate(),
      ).with_part(housing_part),
    )
    // Motor barrel skirt clearing 91 mm A12 rotor (ID 94 mm, z = 4..gear_z0)
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_barrel",
        outer_d,
        94.0,
        dims.gear_z0 - dims.motor_z0,
        z_mm=dims.motor_z0 + (dims.gear_z0 - dims.motor_z0) / 2.0,
        density=@urdf.Density::petg(),
        color=housing_slate(),
      ).with_part(housing_part),
    )
    // Rotor-to-sun adapter coupler
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_sun_adapter",
        34.0,
        12.4,
        5.0,
        z_mm=dims.gear_z0 - 2.5,
        density=@urdf.Density::petg(),
        color=hub_amber(),
      ).with_part(adapter_part),
    )
    // Planet carrier plate
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_carrier",
        circle_poly_2d(0.0, 0.0, carrier_r, 28, true),
        8.0,
        holes=carrier_holes,
        z_mm=dims.carrier_z0 + 4.0,
        density=@urdf.Density::petg(),
        color=hub_amber(),
      ).with_part(carrier_part),
    )
    // Output cap with flange ring and FR8-2RS bearing bore
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_output_cap",
        circle_poly_2d(0.0, 0.0, dims.flange_radius_mm, 32, true),
        10.0,
        holes=cap_holes,
        z_mm=dims.cap_z0 + 5.0,
        density=@urdf.Density::petg(),
        color=housing_slate(),
      ).with_part(cap_part),
    )
    // Output bearing FR8-2RS
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_out_bearing",
        bearing.outer_mm,
        bearing.bore_mm,
        bearing.width_mm,
        z_mm=dims.cap_z0 + 5.0,
        density=@urdf.Density::steel_mild(),
        color=steel_grey(),
      ).with_part(bearing_part),
    )
    // Output steel shaft (carrier -> through structural wall/calf -> output hub)
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        12.7,
        26.0 + hub_offset_mm,
        z_mm=dims.carrier_z0 + (26.0 + hub_offset_mm) / 2.0,
        density=@urdf.Density::steel_mild(),
        color=steel_grey(),
      ).with_part(shaft_part),
    )
    // Output flange hub seated cleanly outboard of wall/calf plate
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_output_hub",
        circle_poly_2d(0.0, 0.0, 30.0, 28, true),
        8.0,
        holes=hub_holes,
        z_mm=dims.total_len_mm + hub_offset_mm + 4.0,
        density=@urdf.Density::petg(),
        color=hub_amber(),
      ).with_part(hub_part),
    )
    // Mount real A12 8318 100KV motor inside the housing cup
    .add_mate_mm_deg("a12_mount", z=dims.motor_z0, axis=(0.0, 0.0, -1.0))
    .attach(
      name + "_a12_mount",
      parent_mate="a12_mount",
      a12_motor,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
    // Mount real 4-elbow herringbone planetary gear cartridge coaxially
    .add_mate_mm_deg("gear_seat", z=dims.gear_z0)
    .attach(
      name + "_gears_mount",
      parent_mate="gear_seat",
      @cad.Component::from_step_component(
        name + "_planetary",
        gb_step,
        density=@urdf.Density::petg(),
        part=Some(cartridge_part),
      ),
      spec=@cad.JointSpec::merge_rigid(),
    )
    .add_mate_mm_deg("rear_face", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("mount_flange", z=dims.total_len_mm)
    .add_mate_mm_deg("output_face", z=dims.total_len_mm + 8.0)

  // Planet bearings + steel carrier dowel pins
  for j in 0..<params.planet_count {
    let a = 2.0 * @math.PI * j.to_double() / params.planet_count.to_double()
    let px = dims.layout.center_distance_mm * @math.cos(a)
    let py = dims.layout.center_distance_mm * @math.sin(a)
    act = act
      .add_body(
        @cad.BodyPart::tube_mm(
          name + "_planet_bearing_" + j.to_string(),
          bearing.outer_mm,
          bearing.bore_mm,
          bearing.width_mm,
          x_mm=px,
          y_mm=py,
          z_mm=dims.gear_z0 + params.gear_length_mm / 2.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(bearing_part),
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          name + "_planet_pin_" + j.to_string(),
          bearing.bore_mm,
          params.gear_length_mm + 9.0,
          x_mm=px,
          y_mm=py,
          z_mm=dims.gear_z0 + (params.gear_length_mm + 9.0) / 2.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(pin_part),
      )
  }

  // Rear moteus C1 controller board (vendored exact STEP when available)
  if board_text != "" {
    act = act
      .add_mate_mm_deg("moteus_mount", z=-2.4, axis=(0.0, 0.0, -1.0))
      .attach(
        name + "_moteus_merge",
        parent_mate="moteus_mount",
        @components.moteus_c1_board(board_text, name=name + "_moteus"),
        child_mate="mount",
        spec=@cad.JointSpec::merge_rigid(),
      )
  }
  // 6x M4 flange tie bolts in Detailed mode
  if params.detail != @step_common.DetailLevel::Simplified {
    let screw_part = wbr_purchased(
      "ISO4762-M4x12", "ISO 4762 socket head cap screw M4 x 12 mm", "steel", 0.09,
    )
    for i in 0..<6 {
      let a = (30.0 + 60.0 * i.to_double()) * @math.PI / 180.0
      act = act.add_body(
        @cad.BodyPart::cylinder_mm(
          name + "_flange_bolt_" + i.to_string(),
          7.0,
          4.0,
          x_mm=bolt_r * @math.cos(a),
          y_mm=bolt_r * @math.sin(a),
          z_mm=dims.total_len_mm + 2.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(screw_part),
      )
    }
  }
  ignore(flange_d)
  act
}

///|
/// Builds the 10-spoke printable wheel rim + rubber tire matching the video WBR.
fn build_wbr_wheel(name : String, params : WbrParams) -> @cad.Component {
  let r_outer = params.wheel_diam_mm / 2.0
  let tire_t = r_outer * 0.34
  let rim_r = r_outer - tire_t
  let w = params.wheel_width_mm
  let rim_w = w * 0.78
  let rim_part = wbr_printed(
    "WBR-WHEEL-RIM",
    "Printed 10-spoke alloy-style wheel rim (\{params.wheel_diam_mm.to_int()} mm wheel, 4x M4 on 40 mm BCD)",
    "PETG / PLA",
    5.50,
  )
  let tire_part = wbr_purchased(
    "WBR-TIRE-RUBBER",
    "Rubber tire tread (\{params.wheel_diam_mm.to_int()} x \{w.to_int()} mm)",
    "rubber",
    9.50,
  )
  let rim_holes : Array[Array[(Double, Double)]] = [
    circle_poly_2d(0.0, 0.0, 6.35, 16, false),
  ]
  for i in 0..<4 {
    let a = (45.0 + 90.0 * i.to_double()) * @math.PI / 180.0
    rim_holes.push(
      circle_poly_2d(20.0 * @math.cos(a), 20.0 * @math.sin(a), 2.2, 8, false),
    )
  }
  // 10 spoke windows cut cleanly through the extruded rim web.
  let spoke_inner = 27.0
  let spoke_outer = rim_r - 7.0
  if spoke_outer > spoke_inner + 6.0 {
    let n_spokes = 10
    for i in 0..<n_spokes {
      let a0 = (2.0 * @math.PI * i.to_double() + 0.24) / n_spokes.to_double()
      let a1 = (2.0 * @math.PI * (i + 1).to_double() - 0.24) /
        n_spokes.to_double()
      let win = ensure_winding(
        [
          (spoke_inner * @math.cos(a0), spoke_inner * @math.sin(a0)),
          (spoke_outer * @math.cos(a0), spoke_outer * @math.sin(a0)),
          (spoke_outer * @math.cos(a1), spoke_outer * @math.sin(a1)),
          (spoke_inner * @math.cos(a1), spoke_inner * @math.sin(a1)),
        ],
        false,
      )
      rim_holes.push(win)
    }
  }
  @cad.Component::new(
    name,
    description="10-spoke printable wheel rim and rubber tire",
  )
  .add_body(
    @cad.BodyPart::extruded_profile_mm(
      name + "_rim",
      circle_poly_2d(0.0, 0.0, rim_r, 36, true),
      rim_w,
      holes=rim_holes,
      rx_deg=90.0,
      density=@urdf.Density::petg(),
      color=shell_white(),
    ).with_part(rim_part),
  )
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_tire",
      params.wheel_diam_mm,
      2.0 * (rim_r - 2.0),
      w,
      rx_deg=90.0,
      density=@urdf.Density::rubber(),
      color=dark_matte(),
    ).with_part(tire_part),
  )
  .add_mate_mm_deg("axle", axis=(0.0, 1.0, 0.0))
}

///|
/// Builds the complete parameterized 4-bar Wheeled Bipedal Robot assembly.
pub fn build_wbr(
  params~ : WbrParams = WbrParams::new(),
  board_text~ : String = "",
) -> @cad.Component {
  let s = params.scale
  let dims = wbr_actuator_dims(params)
  let gb_step = match
    @step_planetary.herringbone_planetary_gearbox(dims.step_params) {
    Ok(c) => c
    Err(e) => abort("WBR planetary build failed: " + e.message())
  }
  let (ax, az, cx, cz) = wbr_chassis_pivots(params)
  let bw = params.body_width_mm
  let half_bw = bw / 2.0
  let wall_t = if 8.0 * s < 6.0 { 6.0 } else { 8.0 * s }
  let link_t = if 18.0 * s < 14.0 { 14.0 } else { 18.0 * s }
  let calf_t = if 22.0 * s < 16.0 { 16.0 } else { 22.0 * s }
  let bearing = @components.flanged_bearing_fr8_2rs()

  // Lateral stations on +Y (left side; right side mirrors to -Y):
  let y_plane1 = half_bw + 8.0 + link_t / 2.0
  let y_plane2 = y_plane1 + link_t / 2.0 + 3.0 + calf_t / 2.0
  let y_calf_in = y_plane2 - calf_t / 2.0
  let y_wheel = y_plane2 + calf_t / 2.0 + 8.0 + params.wheel_width_mm / 2.0

  // Chassis printable parts
  let side_part = wbr_printed(
    "WBR-SIDE-PLATE", "Printed structural chassis side plate with A12 hip mount and FR8-2RS guide pivot bore",
    "PETG / CF nylon", 12.0,
  )
  let lid_part = wbr_printed(
    "WBR-TOP-LID", "Printed top access lid with ventilation slots and M4 corner mounts",
    "PETG / PLA", 6.50,
  )
  let nose_part = wbr_printed(
    "WBR-NOSE-COWL", "Printed front nose bumper cowl with angled 6S LiPo battery cradle and dual ToF bezels",
    "PETG / PLA", 9.00,
  )
  let belly_part = wbr_printed(
    "WBR-BELLY-POD", "Printed lower electronics bay housing the 6-DOF IMU and ESP32-S3 CAN controller",
    "PETG / PLA", 7.00,
  )
  let rear_part = wbr_printed(
    "WBR-REAR-BULKHEAD", "Printed rear cross-bulkhead stiffening plate between hip actuator mounts",
    "PETG / CF nylon", 5.50,
  )
  let crank_part = wbr_printed(
    "WBR-HIP-CRANK",
    "Printed arched boomerang upper hip crank arm (L1=\{params.crank_len_mm.to_int()} mm)",
    "CF nylon / PETG",
    7.50,
  )
  let guide_part = wbr_printed(
    "WBR-GUIDE-LINK",
    "Printed forward parallel guide rocker link (L3=\{params.guide_len_mm.to_int()} mm)",
    "CF nylon / PETG",
    6.00,
  )
  let calf_part = wbr_printed(
    "WBR-CALF-STRUT",
    "Printed main calf strut spanning knee pivots B-D and lower A12 wheel actuator mount (L=\{params.calf_len_mm.to_int()} mm)",
    "CF nylon / PETG",
    11.50,
  )
  let bat_part = wbr_purchased(
    "WBR-BAT-6S", "6S (22.2 V) 5000 mAh LiPo battery pack on angled front nose tray",
    "lithium-ion", 79.00,
  )
  let xt60_part = wbr_purchased(
    "WBR-XT60", "Amass XT60 panel-mount battery power connector", "nylon / brass",
    1.50,
  )
  let imu_part = wbr_purchased(
    "WBR-IMU-6DOF", "6-DOF MEMS IMU sensor module for EKF state estimation", "FR-4",
    18.00,
  )
  let mcu_part = wbr_purchased(
    "WBR-MCU-BOARD", "ESP32-S3 + CAN controller board running EKF + LQR balance loop",
    "FR-4", 22.00,
  )
  let tof_part = wbr_purchased(
    "WBR-TOF-SENSOR", "Front ToF / ultrasonic obstacle sensor module", "mixed", 9.50,
  )
  let bearing_part = wbr_purchased(
    "BEARING-FR8-2RS", "FR8-2RS flanged sealed ball bearing (12.7 x 28.575 x 7.938 mm)",
    "steel", 1.55,
  )
  let pin_part = wbr_purchased(
    "DOWEL-12.7x24", "Hardened steel 1/2 in linkage pivot dowel pin", "steel", 1.50,
  )

  let sx = params.body_len_mm / 280.0
  let sz = params.body_height_mm / 175.0
  let bolt_r = dims.flange_bcd_mm / 2.0
  let side_holes : Array[Array[(Double, Double)]] = [
    circle_poly_2d(ax, az, bearing.outer_mm / 2.0, 18, false),
    circle_poly_2d(cx, cz, bearing.outer_mm / 2.0, 18, false),
  ]
  for i in 0..<6 {
    let a = (30.0 + 60.0 * i.to_double()) * @math.PI / 180.0
    side_holes.push(
      circle_poly_2d(
        ax + bolt_r * @math.cos(a),
        az + bolt_r * @math.sin(a),
        2.2,
        8,
        false,
      ),
    )
  }
  let side_outer = side_plate_profile(params)
  let inner_w = bw - 2.0 * wall_t

  // Top lid vent slots
  let lid_len = 140.0 * sx
  let lid_holes : Array[Array[(Double, Double)]] = []
  for k in 0..<3 {
    let ox = (-36.0 + 36.0 * k.to_double()) * sx
    lid_holes.push(
      ensure_winding(
        [
          (ox - 8.0 * sx, -inner_w * 0.28),
          (ox + 8.0 * sx, -inner_w * 0.28),
          (ox + 8.0 * sx, inner_w * 0.28),
          (ox - 8.0 * sx, inner_w * 0.28),
        ],
        false,
      ),
    )
  }

  let mut base = @cad.Component::new(
      "base_link",
      description="Ascento-inspired 4-bar Wheeled Bipedal Robot (WBR) chassis",
    )
    .with_robot_name("wbr_biped")
    .with_param("scale", s.to_string())
    .with_param("body_len_mm", params.body_len_mm.to_string())
    .with_param("body_width_mm", bw.to_string())
    .with_param("crank_len_mm", params.crank_len_mm.to_string())
    .with_param("coupler_len_mm", params.coupler_len_mm.to_string())
    .with_param("guide_len_mm", params.guide_len_mm.to_string())
    .with_param("calf_len_mm", params.calf_len_mm.to_string())
    .with_param("wheel_diam_mm", params.wheel_diam_mm.to_string())
    .with_param("gear_module_mm", params.gear_module_mm.to_string())
    .with_param("tolerance_mm", params.tolerance_mm.to_string())
    .with_param("exploded_view", "exploded.step")
    .with_param("print_in_place_gearset", "WBR-GEAR-CARTRIDGE")
    .add_port(
      @cad.Port::new("power", @cad.PortKind::Power, spec="22.2 V 6S LiPo"),
    )
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B 1 Mbps"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    // Left & right sculpted structural side plates
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        "chassis_side_l",
        side_outer,
        wall_t,
        holes=side_holes,
        y_mm=half_bw - wall_t / 2.0,
        rx_deg=90.0,
        density=@urdf.Density::petg(),
        color=shell_white(),
      ).with_part(side_part),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        "chassis_side_r",
        side_outer,
        wall_t,
        holes=side_holes,
        y_mm=-(half_bw - wall_t / 2.0),
        rx_deg=90.0,
        density=@urdf.Density::petg(),
        color=shell_white(),
      ).with_part(side_part),
    )
    // Flat top access lid with vent slots
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        "chassis_top_lid",
        ensure_winding(
          [
            (-lid_len / 2.0, -half_bw),
            (lid_len / 2.0, -half_bw),
            (lid_len / 2.0, half_bw),
            (-lid_len / 2.0, half_bw),
          ],
          true,
        ),
        6.0 * s,
        holes=lid_holes,
        x_mm=-22.0 * sx,
        z_mm=88.0 * sz + 3.0 * s,
        density=@urdf.Density::petg(),
        color=shell_white(),
      ).with_part(lid_part),
    )
    // Rounded front nose cowl + sloped upper hood plate
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "chassis_nose_bumper",
        86.0 * sz,
        inner_w,
        x_mm=104.0 * sx,
        z_mm=-18.0 * sz,
        rx_deg=90.0,
        density=@urdf.Density::petg(),
        color=shell_white(),
      ).with_part(nose_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "chassis_front_hood",
        86.0 * sx,
        inner_w,
        8.0 * s,
        x_mm=82.0 * sx,
        z_mm=56.0 * sz,
        ry_deg=44.0,
        density=@urdf.Density::petg(),
        color=shell_white(),
      ).with_part(nose_part),
    )
    // Angled 6S LiPo battery pack strapped on the front hood (signature look!)
    .add_body(
      @cad.BodyPart::box_mm(
        "front_battery_6s",
        72.0 * sx,
        84.0 * s,
        46.0 * sz,
        x_mm=104.0 * sx,
        z_mm=70.0 * sz,
        ry_deg=44.0,
        density=@urdf.Density::lipo_battery(),
        color=dark_matte(),
      ).with_part(bat_part),
    )
    // Yellow/orange XT60 power plug beside the battery pack
    .add_body(
      @cad.BodyPart::box_mm(
        "front_xt60_plug",
        16.0 * s,
        16.0 * s,
        12.0 * s,
        x_mm=98.0 * sx,
        y_mm=-62.0 * s,
        z_mm=60.0 * sz,
        ry_deg=44.0,
        density=@urdf.Density::petg(),
        color=xt60_yellow(),
      ).with_part(xt60_part),
    )
    // Twin recessed front ToF/ultrasonic eyes on nose bumper
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "front_tof_l",
        20.0 * s,
        18.0 * s,
        x_mm=138.0 * sx,
        y_mm=44.0 * s,
        z_mm=-16.0 * sz,
        ry_deg=90.0,
        density=@urdf.Density::abs(),
        color=dark_matte(),
      ).with_part(tof_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "front_tof_r",
        20.0 * s,
        18.0 * s,
        x_mm=138.0 * sx,
        y_mm=-44.0 * s,
        z_mm=-16.0 * sz,
        ry_deg=90.0,
        density=@urdf.Density::abs(),
        color=dark_matte(),
      ).with_part(tof_part),
    )
    // Lower belly electronics pod + internal IMU + ESP32-S3 CAN board
    .add_body(
      @cad.BodyPart::box_mm(
        "chassis_belly_pod",
        92.0 * sx,
        inner_w * 0.72,
        36.0 * sz,
        x_mm=56.0 * sx,
        z_mm=-84.0 * sz,
        density=@urdf.Density::petg(),
        color=shell_white(),
      ).with_part(belly_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "belly_imu_6dof",
        28.0,
        24.0,
        6.0,
        x_mm=48.0 * sx,
        z_mm=-86.0 * sz,
        density=@urdf.Density::fr4_pcb(),
        color=pcb_green(),
      ).with_part(imu_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        "belly_mcu_can",
        58.0,
        42.0,
        8.0,
        x_mm=42.0 * sx,
        z_mm=18.0 * sz,
        density=@urdf.Density::fr4_pcb(),
        color=pcb_green(),
      ).with_part(mcu_part),
    )
    // Rear structural bulkhead stiffening plate tucked cleanly inside rear bevel
    .add_body(
      @cad.BodyPart::box_mm(
        "chassis_rear_bulkhead",
        10.0 * s,
        inner_w,
        62.0 * sz,
        x_mm=-134.0 * sx,
        z_mm=4.0 * sz,
        density=@urdf.Density::petg(),
        color=shell_white(),
      ).with_part(rear_part),
    )

  // Mount Left & Right Hip A12+Planetary Actuators, Upper Cranks, Guide Links,
  // Calf Struts, Inboard Wheel A12+Planetary Actuators, and Wheels.
  for side_entry in [("l", 1.0), ("r", -1.0)] {
    let (prefix, sign) = side_entry
    let act_rx = if sign > 0.0 { -90.0 } else { 90.0 }

    // 1. Hip A12 + 4-elbow planetary actuator bolted flush to inner face of
    //    chassis side wall; shaft passes through side plate to outboard hub.
    let hip_act = build_a12_planetary_actuator(
      prefix + "_hip_drive",
      params,
      dims,
      gb_step,
      board_text,
      hub_offset_mm=wall_t,
    )
    let y_hip_rear = sign * (half_bw - wall_t - dims.total_len_mm)
    base = base
      .add_mate_mm_deg(
        prefix + "_hip_act_mount",
        x=ax,
        y=y_hip_rear,
        z=az,
        rx_deg=act_rx,
      )
      .attach(
        prefix + "_hip_act_fixed",
        parent_mate=prefix + "_hip_act_mount",
        hip_act,
        spec=@cad.JointSpec::fixed(),
        explode=Some(
          @cad.ExplodeSpec::offset_mm(dx=0.0, dy=sign * 50.0, dz=0.0),
        ),
      )

    // Passive Pivot C bearing & pin on chassis side wall.
    base = base
      .add_body(
        @cad.BodyPart::tube_mm(
          prefix + "_pivot_c_bearing",
          bearing.outer_mm,
          bearing.bore_mm,
          bearing.width_mm,
          x_mm=cx,
          y_mm=sign * (half_bw - wall_t / 2.0),
          z_mm=cz,
          rx_deg=90.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(bearing_part),
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          prefix + "_pivot_c_pin",
          bearing.bore_mm,
          wall_t + 8.0 + link_t,
          x_mm=cx,
          y_mm=sign * (half_bw + 4.0 + link_t / 2.0 - wall_t / 2.0),
          z_mm=cz,
          rx_deg=90.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(pin_part),
      )

    // 2. Arched Upper Hip Crank Arm (A -> B) in Plane 1.
    let r_a = 30.0 * s
    let r_b = 24.0 * s
    let crank_holes : Array[Array[(Double, Double)]] = [
      circle_poly_2d(0.0, 0.0, 6.35, 16, false),
      circle_poly_2d(
        -params.crank_len_mm,
        0.0,
        bearing.outer_mm / 2.0,
        18,
        false,
      ),
    ]
    for i in 0..<4 {
      let a = (45.0 + 90.0 * i.to_double()) * @math.PI / 180.0
      crank_holes.push(
        circle_poly_2d(20.0 * @math.cos(a), 20.0 * @math.sin(a), 2.2, 8, false),
      )
    }
    let mut upper_arm = @cad.Component::new(
        prefix + "_upper_arm",
        description="Arched upper hip crank arm (A -> B)",
      )
      .add_body(
        @cad.BodyPart::extruded_profile_mm(
          prefix + "_hip_crank",
          hip_crank_profile(params.crank_len_mm, r_a, r_b, 26.0 * s),
          link_t,
          holes=crank_holes,
          rx_deg=90.0,
          density=@urdf.Density::petg(),
          color=link_white(),
        ).with_part(crank_part),
      )
      .add_body(
        @cad.BodyPart::tube_mm(
          prefix + "_pivot_b_bearing",
          bearing.outer_mm,
          bearing.bore_mm,
          bearing.width_mm,
          x_mm=-params.crank_len_mm,
          rx_deg=90.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(bearing_part),
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          prefix + "_pivot_b_pin",
          bearing.bore_mm,
          link_t + 3.0 + calf_t,
          x_mm=-params.crank_len_mm,
          y_mm=sign * ((calf_t + 3.0) / 2.0),
          rx_deg=90.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(pin_part),
      )
      .add_mate_mm_deg("hip_pivot", axis=(0.0, 1.0, 0.0))
      .add_mate_mm_deg(
        "knee_pivot",
        x=-params.crank_len_mm,
        y=sign * (y_plane2 - y_plane1),
        axis=(0.0, 1.0, 0.0),
      )

    // 3. Main Calf Strut (B - D - W) in Plane 2 + Inboard Wheel A12+Planetary
    //    Actuator + Outboard 10-Spoke Wheel.
    let beta = wbr_calf_beta_rad()
    let wx_loc = params.calf_len_mm * @math.cos(beta)
    let wz_loc = params.calf_len_mm * @math.sin(beta)
    let r_wheel_mount = dims.flange_radius_mm * 0.62
    let calf_holes : Array[Array[(Double, Double)]] = [
      circle_poly_2d(0.0, 0.0, bearing.bore_mm / 2.0, 14, false),
      circle_poly_2d(
        params.coupler_len_mm,
        0.0,
        bearing.bore_mm / 2.0,
        14,
        false,
      ),
      circle_poly_2d(wx_loc, wz_loc, bearing.outer_mm / 2.0, 18, false),
    ]
    let wheel_act = build_a12_planetary_actuator(
      prefix + "_wheel_drive",
      params,
      dims,
      gb_step,
      board_text,
      hub_offset_mm=calf_t,
    )
    let dy_wheel_rear = sign * (y_calf_in - dims.total_len_mm - y_plane2)
    let dy_wheel_ctr = sign * (y_wheel - y_plane2)
    let calf = @cad.Component::new(
        prefix + "_calf_link",
        description="Main 4-bar calf strut carrying lower A12 wheel actuator",
      )
      .add_body(
        @cad.BodyPart::extruded_profile_mm(
          prefix + "_calf_strut",
          calf_strut_profile(
            params.coupler_len_mm,
            wx_loc,
            wz_loc,
            24.0 * s,
            r_wheel_mount,
          ),
          calf_t,
          holes=calf_holes,
          rx_deg=90.0,
          density=@urdf.Density::petg(),
          color=link_white(),
        ).with_part(calf_part),
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          prefix + "_pivot_d_pin",
          bearing.bore_mm,
          link_t + 3.0 + calf_t,
          x_mm=params.coupler_len_mm,
          y_mm=-sign * ((link_t + 3.0) / 2.0),
          rx_deg=90.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(pin_part),
      )
      .add_mate_mm_deg("knee_pivot", axis=(0.0, 1.0, 0.0))
      .add_mate_mm_deg(
        "guide_pin_d",
        x=params.coupler_len_mm,
        axis=(0.0, 1.0, 0.0),
      )
      // Inboard A12 + 4-elbow planetary wheel drive bolted to calf inboard face
      .add_mate_mm_deg(
        "wheel_act_mount",
        x=wx_loc,
        y=dy_wheel_rear,
        z=wz_loc,
        rx_deg=act_rx,
      )
      .attach(
        prefix + "_wheel_act_fixed",
        parent_mate="wheel_act_mount",
        wheel_act,
        spec=@cad.JointSpec::fixed(),
        explode=Some(
          @cad.ExplodeSpec::offset_mm(dx=0.0, dy=sign * 60.0, dz=0.0),
        ),
      )
      // Outboard wheel joint at W
      .add_mate_mm_deg(
        "wheel_axle",
        x=wx_loc,
        y=dy_wheel_ctr,
        z=wz_loc,
        axis=(0.0, 1.0, 0.0),
      )
      .attach(
        prefix + "_wheel_joint",
        parent_mate="wheel_axle",
        build_wbr_wheel(prefix + "_wheel_link", params),
        child_mate="axle",
        spec=@cad.JointSpec::continuous_limit(effort=35.0, velocity=30.0),
        explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=sign * 70.0)),
      )

    upper_arm = upper_arm.attach(
      prefix + "_knee_joint",
      parent_mate="knee_pivot",
      calf,
      child_mate="knee_pivot",
      spec=@cad.JointSpec::revolute(
        @urdf.JointLimit::new(
          lower=Some(-3.06),
          upper=Some(3.06),
          effort=80.0,
          velocity=20.0,
        ),
      ),
      explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=sign * 90.0)),
    )

    // 4. Forward Parallel Guide Rocker Link (C -> D) in Plane 1.
    let guide_holes : Array[Array[(Double, Double)]] = [
      circle_poly_2d(0.0, 0.0, bearing.outer_mm / 2.0, 18, false),
      circle_poly_2d(
        params.guide_len_mm,
        0.0,
        bearing.outer_mm / 2.0,
        18,
        false,
      ),
    ]
    let guide_link = @cad.Component::new(
        prefix + "_guide_link",
        description="Forward parallel guide rocker link (C -> D)",
      )
      .add_body(
        @cad.BodyPart::extruded_profile_mm(
          prefix + "_guide_bar",
          guide_link_profile(params.guide_len_mm, 21.0 * s, 14.0 * s, -14.0 * s),
          link_t,
          holes=guide_holes,
          rx_deg=90.0,
          density=@urdf.Density::petg(),
          color=link_white(),
        ).with_part(guide_part),
      )
      .add_body(
        @cad.BodyPart::tube_mm(
          prefix + "_pivot_d_bearing",
          bearing.outer_mm,
          bearing.bore_mm,
          bearing.width_mm,
          x_mm=params.guide_len_mm,
          rx_deg=90.0,
          density=@urdf.Density::steel_mild(),
          color=steel_grey(),
        ).with_part(bearing_part),
      )
      .add_mate_mm_deg("guide_pivot_c", axis=(0.0, 1.0, 0.0))
      .add_mate_mm_deg(
        "guide_end_d",
        x=params.guide_len_mm,
        axis=(0.0, 1.0, 0.0),
      )

    base = base
      .add_mate_mm_deg(
        prefix + "_hip_pivot",
        x=ax,
        y=sign * y_plane1,
        z=az,
        axis=(0.0, 1.0, 0.0),
      )
      .attach(
        prefix + "_hip_joint",
        parent_mate=prefix + "_hip_pivot",
        upper_arm,
        child_mate="hip_pivot",
        spec=@cad.JointSpec::revolute_deg(
          lower_deg=-85.0,
          upper_deg=15.0,
          effort=90.0,
          velocity=15.0,
        ),
        explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=sign * 120.0)),
      )
      .add_mate_mm_deg(
        prefix + "_guide_pivot",
        x=cx,
        y=sign * y_plane1,
        z=cz,
        axis=(0.0, 1.0, 0.0),
      )
      .attach(
        prefix + "_guide_joint",
        parent_mate=prefix + "_guide_pivot",
        guide_link,
        child_mate="guide_pivot_c",
        spec=@cad.JointSpec::revolute(
          @urdf.JointLimit::new(
            lower=Some(-3.06),
            upper=Some(3.06),
            effort=40.0,
            velocity=20.0,
          ),
        ),
        explode=Some(@cad.ExplodeSpec::along_mate(distance_mm=sign * 100.0)),
      )
  }

  // Cable routing + 4-DOF CAN control bindings (LQR wheel torque + IK height)
  let reduction = @components.planetary_reduction(
    params.sun_teeth,
    params.planet_teeth,
    1,
  )
  base = base
    .add_cable_route(
      @cad.CableRoute::new(
        "can_power_trunk",
        points=[
          (42.0 * sx, 0.0, 18.0 * sz),
          (-40.0 * sx, 0.0, 0.0),
          (ax, 0.0, az),
        ],
        jacket_diameter_mm=9.0,
        wire_names=["l_hip_can", "r_hip_can", "l_wheel_can", "r_wheel_can"],
        material="PVC",
        from_component="base_link",
        from_port="can",
        to_component="l_hip_drive",
        to_port="can",
      ),
    )
    .add_control_binding(
      @cad.ControlBinding::new(
        "l_hip_joint",
        actuator="l_hip_drive",
        channel="can0:1",
        direction="normal",
        gear_ratio=reduction,
      ),
    )
    .add_control_binding(
      @cad.ControlBinding::new(
        "r_hip_joint",
        actuator="r_hip_drive",
        channel="can0:2",
        direction="inverted",
        gear_ratio=reduction,
      ),
    )
    .add_control_binding(
      @cad.ControlBinding::new(
        "l_wheel_joint",
        actuator="l_wheel_drive",
        channel="can0:3",
        direction="normal",
        gear_ratio=reduction,
      ),
    )
    .add_control_binding(
      @cad.ControlBinding::new(
        "r_wheel_joint",
        actuator="r_wheel_drive",
        channel="can0:4",
        direction="inverted",
        gear_ratio=reduction,
      ),
    )
  base
}

///|
/// Runs the `08-wbr-biped` CLI.
pub async fn run_cli() -> Unit {
  let base_spec = {
    "scale": @cli.opt_double(
      1.0,
      help="Master robot size scale factor (0.65..2.0; 1.0 = standard A12 build)",
    ),
    "bodyLength": @cli.opt_double(
      0.0,
      help="Chassis length override in mm (0 = 280 * scale)",
    ),
    "bodyWidth": @cli.opt_double(
      0.0,
      help="Chassis lateral width override in mm (0 = max(220 * scale, 2*act+44))",
    ),
    "bodyHeight": @cli.opt_double(
      0.0,
      help="Chassis height override in mm (0 = 175 * scale)",
    ),
    "crankLength": @cli.opt_double(
      0.0,
      help="Upper hip crank L1 override in mm (0 = 128 * scale)",
    ),
    "couplerLength": @cli.opt_double(
      0.0,
      help="Knee coupler span L2 override in mm (0 = 76 * scale)",
    ),
    "guideLength": @cli.opt_double(
      0.0,
      help="Forward parallel guide L3 override in mm (0 = 165 * scale)",
    ),
    "calfLength": @cli.opt_double(
      0.0,
      help="Main calf strut length override in mm (0 = 225 * scale)",
    ),
    "wheelDiam": @cli.opt_double(
      0.0,
      help="Wheel outer diameter override in mm (0 = 178 * scale)",
    ),
    "gearModule": @cli.opt_double(
      2.0,
      help="4-elbow planetary gear module in mm (default 2.0)",
    ),
    "gearLength": @cli.opt_double(
      12.0,
      help="4-elbow planetary face width in mm (default 12.0)",
    ),
    "numElbows": @cli.opt_int(
      4,
      help="Number of herringbone elbows per planetary gear (default 4)",
    ),
    "tolerance": @cli.opt_double(
      0.20,
      help="3D-printing tooth flank clearance in mm (e.g. 0.042 PETG, 0.25 PLA)",
    ),
    "pose": @cli.opt_string(
      help="Pose preset: standing (default), crouched, tall, or pitched",
    ),
    "hipDeg": @cli.opt_double(
      -999.0,
      help="Explicit hip crank depression angle in deg (5..75; overrides --pose)",
    ),
    "wheelSpinDeg": @cli.opt_double(0.0, help="Wheel spin angle in deg"),
    "explode": @cli.flag(
      help="Write exploded color-coded view to --out (or /tmp/08-wbr-biped-exploded.step)",
    ),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="08-wbr-biped",
      description="Ascento-inspired 4-bar Wheeled Bipedal Robot with A12 motors and 4-elbow planetary gearboxes.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let detail = output.detail_level()
  let params = WbrParams::new(
    scale=args.double("scale"),
    body_len_mm=args.double("bodyLength"),
    body_width_mm=args.double("bodyWidth"),
    body_height_mm=args.double("bodyHeight"),
    crank_len_mm=args.double("crankLength"),
    coupler_len_mm=args.double("couplerLength"),
    guide_len_mm=args.double("guideLength"),
    calf_len_mm=args.double("calfLength"),
    wheel_diam_mm=args.double("wheelDiam"),
    gear_module_mm=args.double("gearModule"),
    gear_length_mm=args.double("gearLength"),
    num_elbows=args.int("numElbows"),
    tolerance_mm=args.double("tolerance"),
    detail~,
  )
  let board_text = @fs.read_file(
    "components/vendor/20240305-moteus-c1-r1_2.step",
  ).text() catch {
    _ => ""
  }
  let links_text = @fs.read_file("examples/08-wbr-biped/supplier-links.txt").text() catch {
    _ => ""
  }
  let robot = build_wbr(params~, board_text~).with_supplier_links(
    @cad.parse_supplier_links(links_text),
  )
  let pose = args.string_opt("pose").unwrap_or("standing")
  let raw_hip = args.double("hipDeg")
  let hip_deg : Double? = if raw_hip > -900.0 { Some(raw_hip) } else { None }
  let positions = pose_positions(
    params,
    pose~,
    hip_deg~,
    wheel_spin_deg=args.double("wheelSpinDeg"),
  )
  @common.write_output(
    robot,
    output,
    joint_positions=positions,
    example_dir="examples/08-wbr-biped",
  )
  // Write the flat print-in-place 4-elbow planetary cartridge. The package's
  // exploded.step is generated automatically from the tree's `ExplodeSpec`s.
  match output.build_package {
    Some(dir) => {
      let cart = build_planetary_cartridge(params)
      @step_cad.write_text_file(
        @cad.orient_print_design(cart.to_design()).to_step_file(),
        Some(dir + "/printable/WBR-GEAR-CARTRIDGE.step"),
      )
    }
    None => ()
  }
  if args.flag("explode") {
    let exploded = robot.to_exploded_design(
      joint_positions=positions,
      trace_lines=true,
    )
    let target = output.step.unwrap_or("/tmp/08-wbr-biped-exploded.step")
    @step_cad.write_text_file(exploded.to_step_file(), Some(target))
  }
}
