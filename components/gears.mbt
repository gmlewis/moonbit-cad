///|
/// A parameterized print-in-place herringbone planetary gearbox, ported from
/// `moonbit-17-step/examples/38-planetary-gearbox`.
///
/// Every gear is a true involute herringbone B-Rep solid swept through
/// `num_elbows + 1` linearly twisted extrusions. The gearbox is also a complete
/// URDF mechanism with mimic-coupled planets and carrier.

///|
let gear_deg : Double = @math.PI / 180.0

///|
let gear_two_pi : Double = 2.0 * @math.PI

///|
let gear_points_in_involute : Int32 = 20

///|
let gear_max_sweep_step_deg : Double = 24.0

///|
/// Parameters of a planetary gearbox.
pub(all) struct PlanetaryGearboxParams {
  gear_module : Double
  gear_length_mm : Double
  helix_angle_deg : Double
  sun_teeth : Int32
  planet_teeth : Int32
  num_planets : Int32
  pressure_angle_deg : Double
  num_elbows : Int32
  resolution : Int32
  bore_radius_mm : Double
  tolerance_mm : Double
  outer_thickness_mm : Double
  include_carrier : Bool
}

///|
/// Default gearbox parameters: a fast, clean 12/12/36 tooth set with 3 planets.
pub fn PlanetaryGearboxParams::default() -> PlanetaryGearboxParams {
  {
    gear_module: 3.0,
    gear_length_mm: 30.0,
    helix_angle_deg: 30.0,
    sun_teeth: 12,
    planet_teeth: 12,
    num_planets: 3,
    pressure_angle_deg: 20.0,
    num_elbows: 2,
    resolution: 5,
    bore_radius_mm: 6.0,
    tolerance_mm: 0.25,
    outer_thickness_mm: 10.0,
    include_carrier: true,
  }
}

///|
priv struct GearDims {
  num_teeth : Int32
  pitch_radius : Double
  outer_radius : Double
}

///|
priv struct PlanetPlacement {
  phi_deg : Double
}

///|
priv struct GearboxConfig {
  gear_module : Double
  gear_length : Double
  helix_angle_deg : Double
  helix_angle_sun : Double
  pressure_angle : Double
  num_elbows : Int32
  resolution : Int32
  tolerance : Double
  outer_thickness : Double
  sun : GearDims
  planet : GearDims
  ring : GearDims
  ring_teeth : Int32
  center_distance : Double
  sun_direction : Double
  planet_direction : Double
  planets : Array[PlanetPlacement]
}

///|
priv struct GearRingGeometry {
  inner : Array[(Double, Double)]
  outer_radius : Double
  phase : Double
  ring_scale : Double
  max_helix_mate : Double
}

///|
fn gear_clamp(value : Double, lo : Double, hi : Double) -> Double {
  if value < lo {
    lo
  } else if value > hi {
    hi
  } else {
    value
  }
}

///|
fn gear_deg2rad(degrees : Double) -> Double {
  degrees * gear_deg
}

///|
fn gear_frac(x : Double) -> Double {
  x - x.floor()
}

///|
fn gear_dmod(a : Double, b : Double) -> Double {
  a - b * (a / b).floor()
}

///|
fn gear_norm_angle(a : Double) -> Double {
  let mut angle = gear_dmod(a, gear_two_pi)
  if angle < 0.0 {
    angle = angle + gear_two_pi
  }
  angle
}

///|
fn gear_radius_of(pt : (Double, Double)) -> Double {
  (pt.0 * pt.0 + pt.1 * pt.1).sqrt()
}

///|
fn gear_sq_dist(a : (Double, Double), b : (Double, Double)) -> Double {
  let dx = a.0 - b.0
  let dz = a.1 - b.1
  dx * dx + dz * dz
}

///|
fn gear_rotate_xz(pt : (Double, Double), theta : Double) -> (Double, Double) {
  let c = @math.cos(theta)
  let s = @math.sin(theta)
  (c * pt.0 - s * pt.1, s * pt.0 + c * pt.1)
}

///|
fn gear_involute_xz(radius : Double, theta : Double) -> (Double, Double) {
  let c = @math.cos(theta)
  let s = @math.sin(theta)
  (radius * (c + theta * s), radius * (s - theta * c))
}

///|
fn gear_involute_theta(radius : Double, distance : Double) -> Double {
  let x = distance / radius
  (x * x - 1.0).sqrt()
}

///|
fn gear_clean_polygon(
  pts : Array[(Double, Double)],
  eps2 : Double,
) -> Array[(Double, Double)] {
  let out : Array[(Double, Double)] = []
  for pt in pts {
    let keep = out.length() == 0 ||
      gear_sq_dist(out[out.length() - 1], pt) > eps2
    if keep {
      out.push(pt)
    }
  }
  while out.length() > 1 && gear_sq_dist(out[0], out[out.length() - 1]) <= eps2 {
    let _ = out.pop()
  }
  out
}

///|
fn gear_dimensions(
  gear_module : Double,
  pressure_angle : Double,
  num_teeth : Int32,
) -> GearDims {
  let pitch = gear_module * num_teeth.to_double() / 2.0
  let _ = pressure_angle
  { num_teeth, pitch_radius: pitch, outer_radius: pitch + gear_module, }
}

///|
fn gear_circle_outline(
  radius : Double,
  segments : Int32,
  clockwise : Bool,
) -> Array[(Double, Double)] {
  let n = if segments < 3 { 3 } else { segments }
  let pts : Array[(Double, Double)] = []
  for i in 0..<n {
    let a = gear_two_pi * i.to_double() / n.to_double()
    let angle = if clockwise { -a } else { a }
    pts.push((radius * @math.cos(angle), radius * @math.sin(angle)))
  }
  pts
}

///|
/// Returns the complete external-gear boundary in the XZ plane, clockwise.
fn gear_outline(
  gear_module : Double,
  pressure_angle_deg : Double,
  num_teeth : Int32,
  resolution : Int32,
) -> Array[(Double, Double)] {
  let pa = gear_deg2rad(pressure_angle_deg)
  let n = num_teeth.to_double()
  let pitch_radius = gear_module * n / 2.0
  let base_radius = pitch_radius * @math.cos(pa)
  let root_radius = pitch_radius - 1.25 * gear_module
  let outer_radius = pitch_radius + gear_module
  let backlash = 0.25 * @math.PI * @math.cos(pa) / (n * gear_module)
  let pitch_point = gear_involute_xz(
    base_radius,
    gear_involute_theta(base_radius, pitch_radius),
  )
  let face_angle = @math.atan2(pitch_point.1, pitch_point.0)
  let backlash_angle = backlash / (2.0 * pitch_radius)
  let center_angle = @math.PI / (2.0 * n) + face_angle - backlash_angle
  let start_angle = gear_involute_theta(
    base_radius,
    if root_radius > base_radius {
      root_radius
    } else {
      base_radius
    },
  )
  let stop_angle = gear_involute_theta(base_radius, outer_radius)
  let d_theta = (stop_angle - start_angle) / gear_points_in_involute.to_double()
  let inv : Array[(Double, Double)] = []
  if root_radius < base_radius {
    inv.push(gear_rotate_xz((root_radius, 0.0), -center_angle))
  }
  let mut angle = start_angle
  for _i in 0..<(gear_points_in_involute + 1) {
    inv.push(
      gear_rotate_xz(gear_involute_xz(base_radius, angle), -center_angle),
    )
    angle = angle + d_theta
  }
  let num_facets = inv.length()
  let arc_tip = inv[num_facets - 1]
  let arc_tip_angle = Double::abs(@math.atan2(arc_tip.1, arc_tip.0))
  for i in 1..<resolution {
    let phi = -arc_tip_angle +
      2.0 * arc_tip_angle * i.to_double() / resolution.to_double()
    inv.push(gear_rotate_xz((outer_radius, 0.0), phi))
  }
  for i in 1..<=num_facets {
    let pt = inv[num_facets - i]
    inv.push((pt.0, -pt.1))
  }
  let first_angle = @math.atan2(inv[0].1, inv[0].0)
  let last_angle = @math.atan2(inv[inv.length() - 1].1, inv[inv.length() - 1].0)
  let involute_arc_angle = Double::abs(last_angle - first_angle)
  let gap_arc_angle = gear_two_pi / n - involute_arc_angle
  let gap_delta = gap_arc_angle / resolution.to_double()
  let outline : Array[(Double, Double)] = []
  let num_inv = inv.length()
  for i in 0..<num_teeth {
    let theta = -i.to_double() * gear_two_pi / n
    for k in 0..<num_inv {
      outline.push(gear_rotate_xz(inv[num_inv - 1 - k], theta))
    }
    let lower_root = gear_rotate_xz(inv[0], theta)
    for j in 1..<resolution {
      outline.push(gear_rotate_xz(lower_root, -j.to_double() * gap_delta))
    }
  }
  gear_clean_polygon(outline, 1.0e-4)
}

///|
/// Returns the clockwise outer boundary of an external involute gear without
/// the tip arc, used for the internal ring envelope.
fn external_gear_boundary(
  gear_module : Double,
  pressure_angle_deg : Double,
  num_teeth : Int32,
  root_radius : Double,
  outer_radius : Double,
  resolution : Int32,
) -> Array[(Double, Double)] {
  let pa = gear_deg2rad(pressure_angle_deg)
  let n = num_teeth.to_double()
  let pitch_radius = gear_module * n / 2.0
  let base_radius = pitch_radius * @math.cos(pa)
  let face_angle = @math.tan(pa) - pa
  let backlash = 0.25 * @math.PI * @math.cos(pa) / (n * gear_module)
  let backlash_angle = backlash / (2.0 * pitch_radius)
  let center_angle = @math.PI / (2.0 * n) + face_angle - backlash_angle
  let start_angle = gear_involute_theta(
    base_radius,
    if root_radius > base_radius {
      root_radius
    } else {
      base_radius
    },
  )
  let stop_angle = gear_involute_theta(base_radius, outer_radius)
  let d_theta = (stop_angle - start_angle) / gear_points_in_involute.to_double()
  let inv : Array[(Double, Double)] = []
  if root_radius < base_radius {
    inv.push(gear_rotate_xz((root_radius, 0.0), -center_angle))
  }
  let mut angle = start_angle
  for _i in 0..<(gear_points_in_involute + 1) {
    inv.push(
      gear_rotate_xz(gear_involute_xz(base_radius, angle), -center_angle),
    )
    angle = angle + d_theta
  }
  let num_facets = inv.length()
  let arc_tip = inv[num_facets - 1]
  let arc_tip_angle = Double::abs(@math.atan2(arc_tip.1, arc_tip.0))
  for i in 1..<resolution {
    let phi = -arc_tip_angle +
      2.0 * arc_tip_angle * i.to_double() / resolution.to_double()
    inv.push(gear_rotate_xz((outer_radius, 0.0), phi))
  }
  for i in 1..<=num_facets {
    let pt = inv[num_facets - i]
    inv.push((pt.0, -pt.1))
  }
  let first_angle = @math.atan2(inv[0].1, inv[0].0)
  let last_angle = @math.atan2(inv[inv.length() - 1].1, inv[inv.length() - 1].0)
  let involute_arc_angle = Double::abs(last_angle - first_angle)
  let gap_arc_angle = gear_two_pi / n - involute_arc_angle
  let gap_delta = gap_arc_angle / resolution.to_double()
  let profile : Array[(Double, Double)] = []
  let num_inv = inv.length()
  for tooth in 0..<num_teeth {
    let tooth_angle = -gear_two_pi * tooth.to_double() / n
    for k in 1..<=num_inv {
      profile.push(gear_rotate_xz(inv[num_inv - k], tooth_angle))
    }
    let lower_root = gear_rotate_xz(inv[0], tooth_angle)
    for j in 1..<resolution {
      profile.push(gear_rotate_xz(lower_root, -j.to_double() * gap_delta))
    }
  }
  profile
}

///|
/// Builds the ring's inner boundary from a phantom external gear.
fn gear_ring_geometry(cfg : GearboxConfig) -> GearRingGeometry {
  let gear_module = cfg.gear_module
  let n = cfg.ring_teeth.to_double()
  let ring_pitch = gear_module * n / 2.0
  let mate_pitch = gear_module * cfg.planet.num_teeth.to_double() / 2.0
  let mate_outer = mate_pitch + gear_module
  let nominal_center = ring_pitch - mate_pitch
  let center = if cfg.center_distance <= 0.0 {
    nominal_center
  } else {
    cfg.center_distance
  }
  let center_delta = if center > nominal_center {
    center - nominal_center
  } else {
    0.0
  }
  let phantom_root = ring_pitch - gear_module
  let phantom_tip = ring_pitch + gear_module
  let profile = external_gear_boundary(
    gear_module,
    cfg.pressure_angle,
    cfg.ring_teeth,
    phantom_root,
    phantom_tip,
    cfg.resolution,
  )
  let profile = gear_clean_polygon(profile, 1.0e-4)
  let mut max_r = 0.0
  for pt in profile {
    let r = gear_radius_of(pt)
    if r > max_r {
      max_r = r
    }
  }
  let radial_offset = center_delta +
    cfg.tolerance / @math.sin(gear_deg2rad(cfg.pressure_angle))
  let offset_profile = profile.map(fn(pt) {
    let r = gear_radius_of(pt)
    if r > 0.0 {
      let s = (r + radial_offset) / r
      (pt.0 * s, pt.1 * s)
    } else {
      pt
    }
  })
  let inner = gear_clean_polygon(offset_profile, 1.0e-4)
  let outer_radius = max_r + radial_offset + cfg.outer_thickness
  let mate_pitch_angle = gear_two_pi / cfg.planet.num_teeth.to_double()
  let ring_pitch_angle = gear_two_pi / n
  let mate_rotation = gear_deg2rad(cfg.planets[0].phi_deg)
  let mut phase = ring_pitch_angle *
    gear_dmod(mate_rotation / mate_pitch_angle, 1.0)
  if phase < 0.0 {
    phase = phase + ring_pitch_angle
  }
  let max_helix_mate = @math.tan(gear_deg2rad(cfg.helix_angle_deg)) *
    (cfg.gear_length / 2.0) /
    mate_outer
  {
    inner,
    outer_radius,
    phase,
    ring_scale: mate_pitch / ring_pitch,
    max_helix_mate,
  }
}

///|
/// Builds a gear as a swept herringbone solid with its axis along +Y.
fn make_gear_shape(
  outline : Array[(Double, Double)],
  holes : Array[Array[(Double, Double)]],
  gear_length : Double,
  num_elbows : Int32,
  max_rotation : Double,
  direction : Double,
  straight_holes~ : Bool = false,
  straight_outline~ : Bool = true,
) -> @step_cad.Shape {
  let path = gear_sweep_path(gear_length, num_elbows, max_rotation, direction)
  let profile = @step_cad.SweepProfile::new(
    gear_profile_points(outline),
    holes=holes.map(fn(hole) { gear_profile_points(hole) }),
    normal_dir=(0.0, 0.0, 1.0),
    right_dir=(1.0, 0.0, 0.0),
  )
  @step_cad.SweptProfile::new(
    path~,
    profile~,
    straight_holes~,
    straight_outline~,
  )
}

///|
fn gear_sweep_path(
  gear_length : Double,
  num_elbows : Int32,
  max_rotation : Double,
  direction : Double,
) -> @step_cad.SweepPath {
  let chunks = num_elbows + 1
  let max_step = gear_max_sweep_step_deg * gear_deg
  let steps = if max_rotation <= max_step {
    1
  } else {
    let n = @math.ceil(max_rotation / max_step).to_int()
    if n < 1 {
      1
    } else {
      n
    }
  }
  let total = chunks * steps
  let points : Array[@step_cad.Vec3] = []
  let normals : Array[@step_cad.Vec3] = []
  let tangents : Array[@step_cad.Vec3] = []
  for i in 0..<(total + 1) {
    let y = gear_length * i.to_double() / total.to_double()
    let chunk = if i == total { chunks - 1 } else { i / steps }
    let within = if i == total {
      1.0
    } else {
      (i % steps).to_double() / steps.to_double()
    }
    let start_rotation = if chunk % 2 == 0 { 0.0 } else { max_rotation }
    let end_rotation = if chunk % 2 == 0 { max_rotation } else { 0.0 }
    let helix_rotation = start_rotation +
      (end_rotation - start_rotation) * within
    let angle = -direction * helix_rotation
    points.push((0.0, y, 0.0))
    normals.push((@math.cos(angle), 0.0, @math.sin(angle)))
    tangents.push((0.0, 1.0, 0.0))
  }
  { points, normals, tangents, }
}

///|
fn gear_profile_points(pts : Array[(Double, Double)]) -> Array[@step_cad.Vec3] {
  pts.map(fn(pt) { (-pt.1, pt.0, 0.0) })
}

///|
/// Computes the gearbox configuration from user parameters.
fn gearbox_config(p : PlanetaryGearboxParams) -> GearboxConfig {
  let pa = p.pressure_angle_deg * gear_deg
  let ha = gear_clamp(p.helix_angle_deg, 0.0, 45.0) * gear_deg
  let sun = gear_dimensions(p.gear_module, pa, p.sun_teeth)
  let planet = gear_dimensions(p.gear_module, pa, p.planet_teeth)
  let ring_teeth = p.sun_teeth + 2 * p.planet_teeth
  let ring_nominal = gear_dimensions(p.gear_module, pa, ring_teeth)
  let ring : GearDims = {
    ..ring_nominal,
    outer_radius: ring_nominal.pitch_radius - 1.25 * p.gear_module,
  }
  let center_delta = if p.tolerance_mm > 0.0 {
    p.tolerance_mm * 2.0
  } else {
    0.0
  }
  let center_distance = sun.pitch_radius + planet.pitch_radius + center_delta
  let tan_beta_pitch = @math.tan(ha) *
    p.planet_teeth.to_double() /
    (p.planet_teeth + 2).to_double()
  let helix_angle_sun = gear_clamp(
    @math.atan(
      tan_beta_pitch * (p.sun_teeth + 2).to_double() / p.sun_teeth.to_double(),
    ) /
    gear_deg,
    0.0,
    45.0,
  )
  let sun_direction = 1.0
  let planet_direction = -1.0
  let planets : Array[PlanetPlacement] = []
  for j in 0..<p.num_planets {
    let theta = gear_two_pi * j.to_double() / p.num_planets.to_double()
    let s = gear_frac(p.sun_teeth.to_double() * theta / gear_two_pi)
    let phi = theta +
      @math.PI -
      gear_two_pi / p.planet_teeth.to_double() * (0.5 - s)
    planets.push({ phi_deg: gear_norm_angle(phi) / gear_deg, })
  }
  {
    gear_module: p.gear_module,
    gear_length: p.gear_length_mm,
    helix_angle_deg: ha / gear_deg,
    helix_angle_sun,
    pressure_angle: p.pressure_angle_deg,
    num_elbows: p.num_elbows,
    resolution: p.resolution,
    tolerance: p.tolerance_mm,
    outer_thickness: p.outer_thickness_mm,
    sun,
    planet,
    ring,
    ring_teeth,
    center_distance,
    sun_direction,
    planet_direction,
    planets,
  }
}

///|
/// Builds one centered herringbone gear scene node with its axis along +Z.
fn gear_node(
  name : String,
  outline : Array[(Double, Double)],
  holes : Array[Array[(Double, Double)]],
  gear_length : Double,
  num_elbows : Int32,
  max_rotation : Double,
  direction : Double,
  color : @step_cad.Rgb,
  straight_holes~ : Bool = true,
) -> @step_cad.SceneNode {
  make_gear_shape(
    outline,
    holes,
    gear_length,
    num_elbows,
    max_rotation,
    direction,
    straight_holes~,
    straight_outline=false,
  )
  .with_name(name)
  .with_color(color)
  .rotate_x(90.0)
  .translate(z=-gear_length / 2.0)
}

///|
/// Builds a standalone herringbone gear component with optional bore.
pub fn herringbone_gear_component(
  name : String,
  gear_module~ : Double,
  num_teeth~ : Int32,
  gear_length_mm~ : Double,
  helix_angle_deg~ : Double = 30.0,
  bore_radius_mm~ : Double = 5.0,
  num_elbows~ : Int32 = 2,
  resolution~ : Int32 = 5,
  direction~ : Double = 1.0,
  density~ : @urdf.Density = @urdf.Density::pla(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let gear_cost_usd = 6.0
  let policy = @step_common.DetailPolicy::for_level(detail)
  let effective_resolution = if !detail_is_rich(detail) {
    if resolution < 3 {
      3
    } else {
      resolution
    }
  } else if detail is @step_common.DetailLevel::FullyModeled {
    if resolution > 8 {
      resolution
    } else {
      8
    }
  } else {
    resolution
  }
  let effective_elbows = if !detail_is_rich(detail) {
    1
  } else if detail is @step_common.DetailLevel::FullyModeled {
    if num_elbows > 3 {
      num_elbows
    } else {
      3
    }
  } else {
    num_elbows
  }
  let dims = gear_dimensions(gear_module, gear_deg2rad(20.0), num_teeth)
  let outline = gear_outline(gear_module, 20.0, num_teeth, effective_resolution)
  let holes = if bore_radius_mm > 0.0 {
    [gear_circle_outline(bore_radius_mm, policy.circle_segments, false)]
  } else {
    []
  }
  let max_rotation = @math.tan(gear_deg2rad(helix_angle_deg)) *
    (gear_length_mm / 2.0) /
    dims.outer_radius
  let node = gear_node(
    name + "_gear",
    outline,
    holes,
    gear_length_mm,
    effective_elbows,
    max_rotation,
    direction,
    color,
  )
  let inertial = @urdf.Inertial::from_cylinder_density(
    dims.outer_radius / 1000.0,
    gear_length_mm / 1000.0,
    density~,
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::cylinder_mm(dims.outer_radius, gear_length_mm),
    name=Some(name + "_gear"),
  )
  @cad.Component::new(name, description="Herringbone gear")
  .with_param("gear_module", gear_module.to_string())
  .with_param("num_teeth", num_teeth.to_string())
  .with_param("gear_length_mm", gear_length_mm.to_string())
  .with_param("helix_angle_deg", helix_angle_deg.to_string())
  .add_body(
    @cad.BodyPart::custom(
      name + "_body",
      node,
      inertial,
      collisions=[collision],
      density~,
    ),
  )
  .add_mate_mm_deg("center")
  .add_mate_mm_deg("bottom", z=-gear_length_mm / 2.0)
  .add_mate_mm_deg("top", z=gear_length_mm / 2.0)
  .with_part(
    fabricated_part(
      "GEAR-" + num_teeth.to_string() + "T",
      "Herringbone gear",
      "PLA",
      "3D print",
      gear_cost_usd,
    ),
  )
}

///|
/// Builds the ring housing component with its inward-toothed ring gear.
fn ring_housing_component(
  name : String,
  cfg : GearboxConfig,
  p : PlanetaryGearboxParams,
) -> @cad.Component {
  let ring_cost_usd = 12.0
  let ring = gear_ring_geometry(cfg)
  let outer_circle = gear_circle_outline(
    ring.outer_radius,
    cfg.resolution * 8,
    true,
  )
  let inner_ccw = ring.inner
    .map(fn(pt) { gear_rotate_xz(pt, ring.phase) })
    .rev()
  let node = gear_node(
    name + "_gear",
    outer_circle,
    [inner_ccw],
    cfg.gear_length,
    cfg.num_elbows,
    ring.ring_scale * ring.max_helix_mate,
    cfg.planet_direction,
    @step_cad.Rgb::grey(),
    straight_holes=false,
  )
  let inner_radius = cfg.ring.pitch_radius - cfg.gear_module
  let inertial = @urdf.Inertial::from_tube_density(
    inner_radius / 1000.0,
    ring.outer_radius / 1000.0,
    cfg.gear_length / 1000.0,
    density=@urdf.Density::pla(),
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::cylinder_mm(ring.outer_radius, cfg.gear_length),
    name=Some(name + "_gear"),
  )
  let mut comp = @cad.Component::new(name, description="Planetary ring housing")
    .with_param("sun_teeth", p.sun_teeth.to_string())
    .with_param("planet_teeth", p.planet_teeth.to_string())
    .with_param("ring_teeth", cfg.ring_teeth.to_string())
    .add_body(
      @cad.BodyPart::custom(
        name + "_body",
        node,
        inertial,
        collisions=[collision],
        density=@urdf.Density::pla(),
      ),
    )
    .add_mate_mm_deg("input_flange", z=-cfg.gear_length / 2.0)
    .add_mate_mm_deg("center")
    .add_mate_mm_deg("output_face", z=cfg.gear_length / 2.0)
  for i in 0..<p.num_planets {
    let theta = gear_two_pi * i.to_double() / p.num_planets.to_double()
    comp = comp.add_mate_mm_deg(
      "planet_orbit_\{i}",
      x=cfg.center_distance * @math.cos(theta),
      y=-cfg.center_distance * @math.sin(theta),
    )
  }
  comp.with_part(
    fabricated_part(
      "PGB-RING", "Planetary ring housing", "PLA", "3D print", ring_cost_usd,
    ),
  )
}

///|
/// Builds the sun gear component.
fn sun_component(
  name : String,
  cfg : GearboxConfig,
  p : PlanetaryGearboxParams,
) -> @cad.Component {
  let sun_cost_usd = 5.0
  let outline = gear_outline(
    cfg.gear_module,
    cfg.pressure_angle,
    cfg.sun.num_teeth,
    cfg.resolution,
  )
  let holes = if p.bore_radius_mm > 0.0 {
    [gear_circle_outline(p.bore_radius_mm, 36, false)]
  } else {
    []
  }
  let max_rotation = @math.tan(gear_deg2rad(cfg.helix_angle_sun)) *
    (cfg.gear_length / 2.0) /
    cfg.sun.outer_radius
  let node = gear_node(
    name + "_gear",
    outline,
    holes,
    cfg.gear_length,
    cfg.num_elbows,
    max_rotation,
    cfg.sun_direction,
    @step_cad.Rgb::orange(),
  )
  let inertial = @urdf.Inertial::from_cylinder_density(
    cfg.sun.outer_radius / 1000.0,
    cfg.gear_length / 1000.0,
    density=@urdf.Density::pla(),
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::cylinder_mm(cfg.sun.outer_radius, cfg.gear_length),
    name=Some(name + "_gear"),
  )
  @cad.Component::new(name, description="Planetary sun gear")
  .with_param("sun_teeth", cfg.sun.num_teeth.to_string())
  .add_body(
    @cad.BodyPart::custom(
      name + "_body",
      node,
      inertial,
      collisions=[collision],
      density=@urdf.Density::pla(),
    ),
  )
  .add_mate_mm_deg("center")
  .add_mate_mm_deg("bottom", z=-cfg.gear_length / 2.0)
  .add_mate_mm_deg("top", z=cfg.gear_length / 2.0)
  .with_part(
    fabricated_part(
      "PGB-SUN", "Planetary sun gear", "PLA", "3D print", sun_cost_usd,
    ),
  )
}

///|
/// Builds one planet gear component, phased to mesh with the sun.
fn planet_component(
  name : String,
  cfg : GearboxConfig,
  p : PlanetaryGearboxParams,
  phi_deg : Double,
) -> @cad.Component {
  let planet_cost_usd = 4.0
  let outline = gear_outline(
    cfg.gear_module,
    cfg.pressure_angle,
    cfg.planet.num_teeth,
    cfg.resolution,
  )
  let holes = if p.bore_radius_mm > 0.0 {
    [gear_circle_outline(p.bore_radius_mm, 36, false)]
  } else {
    []
  }
  let max_rotation = @math.tan(gear_deg2rad(cfg.helix_angle_deg)) *
    (cfg.gear_length / 2.0) /
    cfg.planet.outer_radius
  let node = make_gear_shape(
      outline,
      holes,
      cfg.gear_length,
      cfg.num_elbows,
      max_rotation,
      cfg.planet_direction,
      straight_holes=true,
      straight_outline=false,
    )
    .with_name(name + "_gear")
    .with_color(@step_cad.Rgb::blue())
    .rotate_x(90.0)
    .rotate_z(-phi_deg)
    .translate(z=-cfg.gear_length / 2.0)
  let inertial = @urdf.Inertial::from_cylinder_density(
    cfg.planet.outer_radius / 1000.0,
    cfg.gear_length / 1000.0,
    density=@urdf.Density::pla(),
  )
  let collision = @urdf.Collision::new(
    @urdf.Geometry::cylinder_mm(cfg.planet.outer_radius, cfg.gear_length),
    name=Some(name + "_gear"),
  )
  @cad.Component::new(name, description="Planetary planet gear")
  .with_param("planet_teeth", cfg.planet.num_teeth.to_string())
  .with_param("phase_deg", phi_deg.to_string())
  .add_body(
    @cad.BodyPart::custom(
      name + "_body",
      node,
      inertial,
      collisions=[collision],
      density=@urdf.Density::pla(),
    ),
  )
  .add_mate_mm_deg("center")
  .add_mate_mm_deg("bottom", z=-cfg.gear_length / 2.0)
  .add_mate_mm_deg("top", z=cfg.gear_length / 2.0)
  .with_part(
    fabricated_part(
      "PGB-PLANET-" + name,
      "Planetary planet gear",
      "PLA",
      "3D print",
      planet_cost_usd,
    ),
  )
}

///|
/// Builds the optional planet carrier plate with pin bosses.
fn carrier_component(
  name : String,
  cfg : GearboxConfig,
  p : PlanetaryGearboxParams,
) -> @cad.Component {
  let carrier_cost_usd = 8.0
  let thickness = 8.0
  let plate_radius = cfg.center_distance + cfg.planet.outer_radius + 4.0
  let mut comp = @cad.Component::new(
      name,
      description="Planetary carrier plate",
    )
    .with_param("center_distance_mm", cfg.center_distance.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        z_mm=thickness / 2.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::purple(),
      ),
    )
  for i in 0..<p.num_planets {
    let theta = gear_two_pi * i.to_double() / p.num_planets.to_double()
    comp = comp.add_body(
      @cad.BodyPart::cylinder_mm(
        "\{name}_pin_\{i}",
        8.0,
        thickness,
        x_mm=cfg.center_distance * @math.cos(theta),
        y_mm=-cfg.center_distance * @math.sin(theta),
        z_mm=thickness / 2.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::purple(),
      ),
    )
  }
  comp
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("output_shaft", z=thickness)
  .with_part(
    fabricated_part(
      "PGB-CARRIER", "Planetary carrier", "PLA", "3D print", carrier_cost_usd,
    ),
  )
}

///|
/// Builds a herringbone planetary gearbox component with a mimic-coupled
/// kinematic tree.
pub fn planetary_gearbox(
  name~ : String = "planetary_gearbox",
  params~ : PlanetaryGearboxParams = PlanetaryGearboxParams::default(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let effective_params : PlanetaryGearboxParams = if !detail_is_rich(detail) {
    {
      ..params,
      num_elbows: if params.num_elbows < 2 {
        params.num_elbows
      } else {
        2
      },
      resolution: if params.resolution < 4 {
        params.resolution
      } else {
        4
      },
    }
  } else if detail is @step_common.DetailLevel::FullyModeled {
    {
      ..params,
      num_elbows: if params.num_elbows > 3 {
        params.num_elbows
      } else {
        3
      },
      resolution: if params.resolution > 8 {
        params.resolution
      } else {
        8
      },
    }
  } else {
    params
  }
  let cfg = gearbox_config(effective_params)
  let ring_name = name + "_ring_housing"
  let sun_name = name + "_sun"
  let sun_joint = name + "_sun_joint"
  let mut comp = ring_housing_component(ring_name, cfg, params)
  let sun = sun_component(sun_name, cfg, effective_params)
  comp = comp.attach(
    sun_joint,
    parent_mate="center",
    sun,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=15.0, velocity=30.0)),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
      transmission_reduction=Some(1.0),
    ),
  )
  let planet_multiplier = -(effective_params.sun_teeth.to_double() /
    effective_params.planet_teeth.to_double())
  for i in 0..<effective_params.num_planets {
    let planet = planet_component(
      "\{name}_planet_\{i}",
      cfg,
      effective_params,
      cfg.planets[i].phi_deg,
    )
    comp = comp.attach(
      "\{name}_planet_\{i}_joint",
      parent_mate="planet_orbit_\{i}",
      planet,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
        mimic=Some(
          @urdf.JointMimic::new(sun_joint, multiplier=planet_multiplier),
        ),
      ),
    )
  }
  if effective_params.include_carrier {
    let carrier = carrier_component("\{name}_carrier", cfg, effective_params)
    let carrier_multiplier = effective_params.sun_teeth.to_double() /
      (effective_params.sun_teeth + cfg.ring_teeth).to_double()
    comp = comp.attach(
      "\{name}_carrier_joint",
      parent_mate="output_face",
      carrier,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
        mimic=Some(
          @urdf.JointMimic::new(sun_joint, multiplier=carrier_multiplier),
        ),
      ),
    )
  }
  comp
}

///|
/// A spur gear built from the Tier-1 involute gear primitive.
///
/// The gear is centered on `z = 0` and marked as a 3D-printed part so
/// `printable_parts()` exports it as a standalone STEP file.
pub fn spur_gear_part(
  name~ : String = "spur_gear",
  module_mm~ : Double = 1.0,
  teeth~ : Int32 = 20,
  face_width_mm~ : Double = 8.0,
  bore_diameter_mm~ : Double = 4.0,
  pressure_angle_deg~ : Double = 20.0,
  backlash_mm~ : Double = 0.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
) -> @cad.Component {
  let params = expect_step(
    "spur gear parameters",
    @step_gears.SpurGearParams::new(
      module_mm~,
      teeth~,
      pressure_angle_deg~,
      face_width_mm~,
      bore_diameter_mm~,
      backlash_mm~,
    ),
  )
  let step_comp = expect_step(
    "spur gear",
    @step_gears.spur_gear(params, detail~, color~),
  )
  let part = fabricated_part(
    "SPUR-\{teeth}T-M\{module_mm}-\{name}",
    "Spur gear \{teeth} teeth, module \{module_mm}",
    "PLA",
    "3D print",
    3.0,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::pla(),
    part=Some(part),
    z_mm=-face_width_mm / 2.0,
  )
  .add_mate_mm_deg("origin")
  .add_mate_mm_deg("bottom", z=-face_width_mm / 2.0)
  .add_mate_mm_deg("top", z=face_width_mm / 2.0)
  .with_param("module_mm", module_mm.to_string())
  .with_param("teeth", teeth.to_string())
  .with_param("face_width_mm", face_width_mm.to_string())
}

///|
/// A sun/planet/ring planetary stage built from Tier-1 gear primitives.
///
/// The ring is the root. The sun and each planet are continuous joints with
/// mimic coupling, and a printed carrier disk is driven at the sun/ring ratio.
/// Every gear and the carrier are exported individually by
/// `printable_parts()`.
pub fn planetary_gearset_stage(
  name~ : String = "planetary_stage",
  module_mm~ : Double = 1.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 18,
  planet_count~ : Int32 = 3,
  face_width_mm~ : Double = 8.0,
  pressure_angle_deg~ : Double = 20.0,
  ring_wall_mm~ : Double = 4.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let ring_teeth = sun_teeth + 2 * planet_teeth
  let center_distance = module_mm *
    (sun_teeth.to_double() + planet_teeth.to_double()) /
    2.0
  let ring_step = expect_step(
    "internal ring gear",
    @step_gears.internal_ring_gear_exact(
      module_mm,
      ring_teeth,
      face_width_mm,
      pressure_angle_deg~,
      outer_wall_mm=ring_wall_mm,
    ),
  )
  let ring_part = fabricated_part(
    "RING-\{ring_teeth}T-M\{module_mm}",
    "Internal ring gear \{ring_teeth} teeth",
    "PLA",
    "3D print",
    6.0,
  )
  let sun_joint = name + "_sun_joint"
  let mut stage = @cad.Component::from_step_component(
      name + "_ring",
      ring_step,
      density=@urdf.Density::pla(),
      part=Some(ring_part),
      z_mm=-face_width_mm / 2.0,
    )
    .add_mate_mm_deg("sun_axis")
    .add_mate_mm_deg("carrier_mount", z=face_width_mm / 2.0)
  let sun = spur_gear_part(
    name=name + "_sun",
    module_mm~,
    teeth=sun_teeth,
    face_width_mm~,
    bore_diameter_mm=module_mm * 3.0,
    pressure_angle_deg~,
    detail~,
  )
  stage = stage.attach(
    sun_joint,
    parent_mate="sun_axis",
    sun,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=20.0)),
      transmission_reduction=Some(1.0),
    ),
  )
  let planet_multiplier = -(sun_teeth.to_double() / planet_teeth.to_double())
  for i in 0..<planet_count {
    let theta = 2.0 * @math.PI * i.to_double() / planet_count.to_double()
    let x = center_distance * @math.cos(theta)
    let y = center_distance * @math.sin(theta)
    stage = stage.add_mate_mm_deg("planet_axis_\{i}", x~, y~)
    let planet = spur_gear_part(
      name="\{name}_planet_\{i}",
      module_mm~,
      teeth=planet_teeth,
      face_width_mm~,
      bore_diameter_mm=module_mm * 3.0,
      pressure_angle_deg~,
      detail~,
    )
    stage = stage.attach(
      "\{name}_planet_\{i}_joint",
      parent_mate="planet_axis_\{i}",
      planet,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=5.0, velocity=20.0)),
        mimic=Some(
          @urdf.JointMimic::new(sun_joint, multiplier=planet_multiplier),
        ),
      ),
    )
  }
  let carrier_thickness = module_mm * 4.0
  let carrier_part = fabricated_part(
    "PGS-CARRIER", "Planetary carrier", "PLA", "3D print", 4.0,
  )
  let carrier = @cad.Component::new(
      name + "_carrier",
      description="Planetary carrier",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_carrier_disk",
        (center_distance + module_mm * planet_teeth.to_double() / 2.0) * 2.0,
        carrier_thickness,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_mate_mm_deg("origin")
    .with_part(carrier_part)
  let carrier_multiplier = sun_teeth.to_double() /
    (sun_teeth + ring_teeth).to_double()
  stage.attach(
    "\{name}_carrier_joint",
    parent_mate="carrier_mount",
    carrier,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=5.0, velocity=20.0)),
      mimic=Some(
        @urdf.JointMimic::new(sun_joint, multiplier=carrier_multiplier),
      ),
    ),
  )
}
