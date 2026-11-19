///|
/// A planar four-bar linkage in the X-Z plane.
///
/// Ground pivots are `A` (the actuated crank pivot) and `C` (the passive guide
/// pivot). `B` is the crank end, `D` the coupler/guide joint, and `W` an output
/// point on a ray from `B` offset from the coupler by `output_beta_deg`.
pub(all) struct FourBarParams {
  ax : Double
  az : Double
  cx : Double
  cz : Double
  crank_len_mm : Double
  coupler_len_mm : Double
  guide_len_mm : Double
  output_len_mm : Double
  output_beta_deg : Double
}

///|
pub fn FourBarParams::new(
  ax~ : Double,
  az~ : Double,
  cx~ : Double,
  cz~ : Double,
  crank_len_mm~ : Double,
  coupler_len_mm~ : Double,
  guide_len_mm~ : Double,
  output_len_mm~ : Double,
  output_beta_deg~ : Double = 0.0,
) -> FourBarParams {
  {
    ax,
    az,
    cx,
    cz,
    crank_len_mm,
    coupler_len_mm,
    guide_len_mm,
    output_len_mm,
    output_beta_deg,
  }
}

///|
pub(all) enum FourBarError {
  /// The coupler and guide cannot reach each other at this crank angle.
  DeadPoint(String)
  /// A link length or the ground span is not usable.
  OutOfReach(String)
}

///|
pub fn FourBarError::message(self : FourBarError) -> String {
  match self {
    DeadPoint(message) => message
    OutOfReach(message) => message
  }
}

///|
/// One closed pose of the linkage.
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
  hip_deg : Double
  hip_joint_rad : Double
  knee_joint_rad : Double
  guide_joint_rad : Double
  transmission_deg : Double
}

///|
fn fb_dist(x0 : Double, z0 : Double, x1 : Double, z1 : Double) -> Double {
  let dx = x1 - x0
  let dz = z1 - z0
  (dx * dx + dz * dz).sqrt()
}

///|
/// Solves the planar four-bar for a crank angle `hip_deg` measured downward
/// from -X. The lower-Z branch is chosen so the knee sits below the crank.
pub fn solve_four_bar(
  params : FourBarParams,
  hip_deg : Double,
) -> Result[FourBarSolution, FourBarError] {
  if params.crank_len_mm <= 0.0 ||
    params.coupler_len_mm <= 0.0 ||
    params.guide_len_mm <= 0.0 {
    return Err(OutOfReach("four-bar link lengths must be positive"))
  }
  let ground = fb_dist(params.ax, params.az, params.cx, params.cz)
  if ground < 1.0e-9 {
    return Err(OutOfReach("four-bar ground pivots A and C coincide"))
  }
  let l1 = params.crank_len_mm
  let l2 = params.coupler_len_mm
  let l3 = params.guide_len_mm
  let hip_rad = hip_deg * @math.PI / 180.0
  let bx = params.ax - l1 * @math.cos(hip_rad)
  let bz = params.az - l1 * @math.sin(hip_rad)
  let dx_bc = params.cx - bx
  let dz_bc = params.cz - bz
  let dist = (dx_bc * dx_bc + dz_bc * dz_bc).sqrt()
  if dist >= l2 + l3 - 1.0e-4 || dist <= (l2 - l3).abs() + 1.0e-4 {
    return Err(
      DeadPoint(
        "four-bar cannot close at hipDeg=\{hip_deg} (dist=\{dist}, L2=\{l2}, L3=\{l3})",
      ),
    )
  }
  let a = (l2 * l2 - l3 * l3 + dist * dist) / (2.0 * dist)
  let h_sq = l2 * l2 - a * a
  let h = if h_sq > 0.0 { h_sq.sqrt() } else { 0.0 }
  let mx = bx + a * dx_bc / dist
  let mz = bz + a * dz_bc / dist
  let c1x = mx + h * (-dz_bc / dist)
  let c1z = mz + h * (dx_bc / dist)
  let c2x = mx - h * (-dz_bc / dist)
  let c2z = mz - h * (dx_bc / dist)
  let (dx, dz) = if c1z < c2z { (c1x, c1z) } else { (c2x, c2z) }
  let phi = @math.atan2(dz - bz, dx - bx)
  let psi = @math.atan2(dz - params.cz, dx - params.cx)
  let w_ang = phi + params.output_beta_deg * @math.PI / 180.0
  let wx = bx + params.output_len_mm * @math.cos(w_ang)
  let wz = bz + params.output_len_mm * @math.sin(w_ang)
  let v1x = bx - dx
  let v1z = bz - dz
  let v2x = params.cx - dx
  let v2z = params.cz - dz
  let denom = (v1x * v1x + v1z * v1z).sqrt() * (v2x * v2x + v2z * v2z).sqrt()
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
  Ok({
    ax: params.ax,
    az: params.az,
    cx: params.cx,
    cz: params.cz,
    bx,
    bz,
    dx,
    dz,
    wx,
    wz,
    hip_deg,
    hip_joint_rad: -hip_rad,
    knee_joint_rad: hip_rad - phi,
    guide_joint_rad: -psi,
    transmission_deg: trans_deg,
  })
}

///|
/// Maximum loop-closure error in millimetres for one solution.
pub fn loop_closure_residual(
  params : FourBarParams,
  solution : FourBarSolution,
) -> Double {
  let coupler_err = (fb_dist(solution.bx, solution.bz, solution.dx, solution.dz) -
  params.coupler_len_mm).abs()
  let guide_err = (fb_dist(solution.dx, solution.dz, params.cx, params.cz) -
  params.guide_len_mm).abs()
  if coupler_err > guide_err {
    coupler_err
  } else {
    guide_err
  }
}

///|
/// Grashof condition: `shortest + longest <= sum of the other two`.
pub fn FourBarParams::grashof(self : FourBarParams) -> Bool {
  let ground = fb_dist(self.ax, self.az, self.cx, self.cz)
  let links : Array[Double] = [
    ground,
    self.crank_len_mm,
    self.coupler_len_mm,
    self.guide_len_mm,
  ]
  let mut shortest = links[0]
  let mut longest = links[0]
  let mut total = 0.0
  for link in links {
    total = total + link
    if link < shortest {
      shortest = link
    }
    if link > longest {
      longest = link
    }
  }
  shortest + longest <= total - shortest - longest + 1.0e-9
}

///|
/// A crank-angle sweep with transmission-angle diagnostics.
pub(all) struct FourBarSweep {
  solutions : Array[FourBarSolution]
  errors : Array[String]
  min_transmission_deg : Double
  max_transmission_deg : Double
  grashof : Bool
  warnings : Array[String]
}

///|
pub fn FourBarSweep::has_warnings(self : FourBarSweep) -> Bool {
  self.warnings.length() > 0 || self.errors.length() > 0
}

///|
/// Sweeps the crank from `start_deg` to `end_deg` and reports transmission-angle
/// and Grashof diagnostics.
pub fn sweep_four_bar(
  params : FourBarParams,
  start_deg~ : Double,
  end_deg~ : Double,
  steps~ : Int32 = 24,
) -> FourBarSweep {
  let n = if steps < 1 { 1 } else { steps }
  let solutions : Array[FourBarSolution] = []
  let errors : Array[String] = []
  let mut min_t = 1.0e18
  let mut max_t = -1.0e18
  for i in 0..<=n {
    let t = i.to_double() / n.to_double()
    let hip_deg = start_deg + (end_deg - start_deg) * t
    match solve_four_bar(params, hip_deg) {
      Ok(solution) => {
        solutions.push(solution)
        if solution.transmission_deg < min_t {
          min_t = solution.transmission_deg
        }
        if solution.transmission_deg > max_t {
          max_t = solution.transmission_deg
        }
      }
      Err(error) => errors.push(error.message())
    }
  }
  if solutions.length() == 0 {
    min_t = 0.0
    max_t = 0.0
  }
  let warnings : Array[String] = []
  if solutions.length() > 0 && min_t < 30.0 {
    warnings.push(
      "minimum transmission angle " + min_t.to_string() + " deg is below 30 deg",
    )
  }
  if solutions.length() > 0 && max_t > 150.0 {
    warnings.push(
      "maximum transmission angle " +
      max_t.to_string() +
      " deg is above 150 deg",
    )
  }
  if !params.grashof() {
    warnings.push(
      "non-Grashof linkage: the output link cannot make a full rotation",
    )
  }
  if errors.length() > 0 {
    warnings.push(
      errors.length().to_string() + " crank angle(s) hit a dead point",
    )
  }
  {
    solutions,
    errors,
    min_transmission_deg: min_t,
    max_transmission_deg: max_t,
    grashof: params.grashof(),
    warnings,
  }
}
