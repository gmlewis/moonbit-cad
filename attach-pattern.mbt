///|
/// Zero-`for`-loop hardware pattern attachment helpers on `Component`.
///
/// Define a mounting pattern once (as a ring, rectangle, grid, line, or
/// explicit `(x, y)` coordinates — including `@step_cad.PointPattern2D.points`),
/// then attach physical screws, brass heat-set inserts, standoffs, or dowel
/// pins in a single call with automatic mate creation, BOM tracking, and
/// optional coaxial `ExplodeSpec`.

///|
/// Generates `count` evenly spaced `(x, y)` points on a circle of diameter
/// `diam_mm` centered at `(center_x, center_y)` starting at `phase_deg`.
pub fn pattern_ring_mm(
  count : Int32,
  diam_mm~ : Double,
  phase_deg~ : Double = 0.0,
  center_x~ : Double = 0.0,
  center_y~ : Double = 0.0,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  if count <= 0 || diam_mm <= 0.0 {
    return pts
  }
  let r = diam_mm / 2.0
  for i in 0..<count {
    let ang = (phase_deg + 360.0 * i.to_double() / count.to_double()) *
      @math.PI /
      180.0
    pts.push((center_x + r * @math.cos(ang), center_y + r * @math.sin(ang)))
  }
  pts
}

///|
/// Generates a 4-corner rectangular pattern (`width_mm` × `height_mm`)
/// centered at `(center_x, center_y)`.
pub fn pattern_rect_mm(
  width_mm : Double,
  height_mm : Double,
  center_x~ : Double = 0.0,
  center_y~ : Double = 0.0,
) -> Array[(Double, Double)] {
  let hx = width_mm / 2.0
  let hy = height_mm / 2.0
  [
    (center_x + hx, center_y - hy),
    (center_x - hx, center_y - hy),
    (center_x + hx, center_y + hy),
    (center_x - hx, center_y + hy),
  ]
}

///|
/// Generates a `cols` × `rows` rectangular grid spaced by `pitch_x_mm` and
/// `pitch_y_mm`, centered at `(center_x, center_y)`.
pub fn pattern_grid_mm(
  cols : Int32,
  rows : Int32,
  pitch_x_mm : Double,
  pitch_y_mm : Double,
  center_x~ : Double = 0.0,
  center_y~ : Double = 0.0,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  if cols <= 0 || rows <= 0 {
    return pts
  }
  let x0 = center_x - (cols - 1).to_double() * pitch_x_mm / 2.0
  let y0 = center_y - (rows - 1).to_double() * pitch_y_mm / 2.0
  for r in 0..<rows {
    for c in 0..<cols {
      pts.push(
        (x0 + c.to_double() * pitch_x_mm, y0 + r.to_double() * pitch_y_mm),
      )
    }
  }
  pts
}

///|
/// Generates `count` evenly spaced `(x, y)` points along a line at `angle_deg`,
/// spaced by `pitch_mm` and centered at `(center_x, center_y)`.
pub fn pattern_line_mm(
  count : Int32,
  pitch_mm : Double,
  angle_deg~ : Double = 0.0,
  center_x~ : Double = 0.0,
  center_y~ : Double = 0.0,
) -> Array[(Double, Double)] {
  let pts : Array[(Double, Double)] = []
  if count <= 0 {
    return pts
  }
  let rad = angle_deg * @math.PI / 180.0
  let ux = @math.cos(rad)
  let uy = @math.sin(rad)
  let half = (count - 1).to_double() * pitch_mm / 2.0
  for i in 0..<count {
    let s = i.to_double() * pitch_mm - half
    pts.push((center_x + s * ux, center_y + s * uy))
  }
  pts
}

///|
/// Attaches one child component (produced by `make_child(index)`) at every
/// `(x, y, z_mm)` point in `points`, automatically registering a mate
/// connector `"\{prefix}_mate_\{i}"` on `self` and attaching the child via
/// joint `"\{prefix}_\{i}"`.
///
/// Eliminates the 20–30 lines of manual `for` loop + trig + mate boilerplate
/// normally needed for bolt circles, heat-set insert rings, standoffs, or
/// dowel pin sets.
pub fn Component::attach_pattern(
  self : Component,
  prefix : String,
  points : Array[(Double, Double)],
  make_child : (Int32) -> Component,
  z_mm~ : Double = 0.0,
  axis~ : (Double, Double, Double) = (0.0, 0.0, 1.0),
  child_mate~ : String = "mount",
  spec~ : JointSpec = JointSpec::merge_rigid(),
  bom_external~ : Bool = false,
  explode? : ExplodeSpec,
) -> Component {
  let mut out = self
  for i in 0..<points.length() {
    let (x, y) = points[i]
    let mate_name = "\{prefix}_mate_\{i}"
    let joint_name = "\{prefix}_\{i}"
    out = out
      .add_mate_mm_deg(mate_name, x~, y~, z=z_mm, axis~)
      .attach(
        joint_name,
        parent_mate=mate_name,
        make_child(i),
        child_mate~,
        spec~,
        bom_external~,
        explode~,
      )
  }
  out
}

///|
/// Convenience wrapper over `Component::attach_pattern` for a circular ring
/// of `count` identical hardware items on diameter `diam_mm`.
pub fn Component::attach_ring(
  self : Component,
  prefix : String,
  count~ : Int32,
  diam_mm~ : Double,
  make_child : (Int32) -> Component,
  phase_deg~ : Double = 0.0,
  center_x~ : Double = 0.0,
  center_y~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  axis~ : (Double, Double, Double) = (0.0, 0.0, 1.0),
  child_mate~ : String = "mount",
  spec~ : JointSpec = JointSpec::merge_rigid(),
  bom_external~ : Bool = false,
  explode? : ExplodeSpec,
) -> Component {
  let pts = pattern_ring_mm(count, diam_mm~, phase_deg~, center_x~, center_y~)
  self.attach_pattern(
    prefix,
    pts,
    make_child,
    z_mm~,
    axis~,
    child_mate~,
    spec~,
    bom_external~,
    explode?,
  )
}

///|
/// Convenience wrapper over `Component::attach_pattern` for a 4-corner
/// rectangular pattern (`width_mm` × `height_mm`, e.g. PCB standoffs).
pub fn Component::attach_rect(
  self : Component,
  prefix : String,
  width_mm~ : Double,
  height_mm~ : Double,
  make_child : (Int32) -> Component,
  center_x~ : Double = 0.0,
  center_y~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  axis~ : (Double, Double, Double) = (0.0, 0.0, 1.0),
  child_mate~ : String = "mount",
  spec~ : JointSpec = JointSpec::merge_rigid(),
  bom_external~ : Bool = false,
  explode? : ExplodeSpec,
) -> Component {
  let pts = pattern_rect_mm(width_mm, height_mm, center_x~, center_y~)
  self.attach_pattern(
    prefix,
    pts,
    make_child,
    z_mm~,
    axis~,
    child_mate~,
    spec~,
    bom_external~,
    explode?,
  )
}
