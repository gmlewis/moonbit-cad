///|
/// Declarative coaxial `ExplodeStack` builder for collision-free exploded views.
///
/// Replaces hand-written 60-line `if name.contains(...)` chains with a readable
/// stack spec that automatically computes non-overlapping offsets along `X`,
/// `Y`, or `Z` from each layer's real assembled bounding box:
///
/// ```moonbit
/// let exploded = ExplodeStack::z_axis(anchor="ACT-HOUSING", gap_mm=18.0)
///   .above_list(["gearbox", "bearing-688", "pin_washer", "carrier", "output_cover", "bearing-608", "output_flange"])
///   .below_list(["rotor_adapter", "motor", "motor_plate", "standoff", "moteus"])
///   .apply(assembled_design)
/// ```

///|
/// Axis along which an `ExplodeStack` separates layers.
pub(all) enum ExplodeAxis {
  AxisX
  AxisY
  AxisZ
}

///|
/// One layer in an `ExplodeStack`: matches any `SceneNode` whose name contains
/// at least one of `patterns` (and satisfies `predicate` when provided).
pub(all) struct ExplodeLayer {
  patterns : Array[String]
  gap_override_mm : Double?
  predicate : ((@step_cad.SceneNode) -> Bool)?
}

///|
/// Declarative coaxial explode layout anchored at one or more stationary parts,
/// with ordered layers exploding in the `+axis` (`above`) and `-axis` (`below`)
/// directions.
pub struct ExplodeStack {
  axis : ExplodeAxis
  anchor_patterns : Array[String]
  above_layers : Array[ExplodeLayer]
  below_layers : Array[ExplodeLayer]
  default_gap_mm : Double
}

///|
/// Starts a Z-axis coaxial `ExplodeStack` anchored on parts whose name contains
/// `anchor`, with default inter-layer clearance `gap_mm`.
pub fn ExplodeStack::z_axis(
  anchor~ : String,
  gap_mm~ : Double = 20.0,
) -> ExplodeStack {
  {
    axis: AxisZ,
    anchor_patterns: [anchor],
    above_layers: [],
    below_layers: [],
    default_gap_mm: gap_mm,
  }
}

///|
/// Starts an X-axis coaxial `ExplodeStack`.
pub fn ExplodeStack::x_axis(
  anchor~ : String,
  gap_mm~ : Double = 20.0,
) -> ExplodeStack {
  {
    axis: AxisX,
    anchor_patterns: [anchor],
    above_layers: [],
    below_layers: [],
    default_gap_mm: gap_mm,
  }
}

///|
/// Starts a Y-axis coaxial `ExplodeStack`.
pub fn ExplodeStack::y_axis(
  anchor~ : String,
  gap_mm~ : Double = 20.0,
) -> ExplodeStack {
  {
    axis: AxisY,
    anchor_patterns: [anchor],
    above_layers: [],
    below_layers: [],
    default_gap_mm: gap_mm,
  }
}

///|
/// Adds an additional stationary anchor substring to this stack.
pub fn ExplodeStack::with_anchor(
  self : ExplodeStack,
  pattern : String,
) -> ExplodeStack {
  let anchors = self.anchor_patterns.copy()
  anchors.push(pattern)
  { ..self, anchor_patterns: anchors, }
}

///|
/// Appends one layer in the `+axis` direction matching any node whose name
/// contains any substring in `patterns`.
pub fn ExplodeStack::above(
  self : ExplodeStack,
  patterns : Array[String],
  gap_mm? : Double,
) -> ExplodeStack {
  let layers = self.above_layers.copy()
  layers.push({ patterns, gap_override_mm: gap_mm, predicate: None, })
  { ..self, above_layers: layers, }
}

///|
/// Appends a single-substring layer in the `+axis` direction.
pub fn ExplodeStack::above_one(
  self : ExplodeStack,
  pattern : String,
  gap_mm? : Double,
) -> ExplodeStack {
  self.above([pattern], gap_mm?)
}

///|
/// Appends a filtered layer in the `+axis` direction (e.g. upper vs. lower
/// heat-set inserts distinguished by `node.tz > 0.0`).
pub fn ExplodeStack::above_where(
  self : ExplodeStack,
  patterns : Array[String],
  predicate : (@step_cad.SceneNode) -> Bool,
  gap_mm? : Double,
) -> ExplodeStack {
  let layers = self.above_layers.copy()
  layers.push({ patterns, gap_override_mm: gap_mm, predicate: Some(predicate), })
  { ..self, above_layers: layers, }
}

///|
/// Appends each substring in `patterns` as its own sequential `+axis` layer.
pub fn ExplodeStack::above_list(
  self : ExplodeStack,
  patterns : Array[String],
) -> ExplodeStack {
  let mut out = self
  for pat in patterns {
    out = out.above_one(pat)
  }
  out
}

///|
/// Appends one layer in the `-axis` direction matching any node whose name
/// contains any substring in `patterns`.
pub fn ExplodeStack::below(
  self : ExplodeStack,
  patterns : Array[String],
  gap_mm? : Double,
) -> ExplodeStack {
  let layers = self.below_layers.copy()
  layers.push({ patterns, gap_override_mm: gap_mm, predicate: None, })
  { ..self, below_layers: layers, }
}

///|
/// Appends a single-substring layer in the `-axis` direction.
pub fn ExplodeStack::below_one(
  self : ExplodeStack,
  pattern : String,
  gap_mm? : Double,
) -> ExplodeStack {
  self.below([pattern], gap_mm?)
}

///|
/// Appends a filtered layer in the `-axis` direction.
pub fn ExplodeStack::below_where(
  self : ExplodeStack,
  patterns : Array[String],
  predicate : (@step_cad.SceneNode) -> Bool,
  gap_mm? : Double,
) -> ExplodeStack {
  let layers = self.below_layers.copy()
  layers.push({ patterns, gap_override_mm: gap_mm, predicate: Some(predicate), })
  { ..self, below_layers: layers, }
}

///|
/// Appends each substring in `patterns` as its own sequential `-axis` layer.
pub fn ExplodeStack::below_list(
  self : ExplodeStack,
  patterns : Array[String],
) -> ExplodeStack {
  let mut out = self
  for pat in patterns {
    out = out.below_one(pat)
  }
  out
}

///|
fn node_axis_span(
  node : @step_cad.SceneNode,
  axis : ExplodeAxis,
) -> (Double, Double) {
  let (x0, x1, y0, y1, z0, z1) = node.bounding_box()
  match axis {
    AxisX => (x0, x1)
    AxisY => (y0, y1)
    AxisZ => (z0, z1)
  }
}

///|
fn layer_matches(layer : ExplodeLayer, node : @step_cad.SceneNode) -> Bool {
  let mut name_ok = false
  for pat in layer.patterns {
    if node.name.contains(pat) {
      name_ok = true
      break
    }
  }
  if !name_ok {
    return false
  }
  match layer.predicate {
    Some(pred) => pred(node)
    None => true
  }
}

///|
fn axis_vector(axis : ExplodeAxis, offset : Double) -> (Double, Double, Double) {
  match axis {
    AxisX => (offset, 0.0, 0.0)
    AxisY => (0.0, offset, 0.0)
    AxisZ => (0.0, 0.0, offset)
  }
}

///|
/// Computes collision-free `(dx, dy, dz)` explode offsets (mm) for every node
/// in `design` (in the same order as `design.nodes`).
pub fn ExplodeStack::offsets(
  self : ExplodeStack,
  design : @step_cad.Design,
) -> Array[(String, (Double, Double, Double))] {
  let n_above = self.above_layers.length()
  let n_below = self.below_layers.length()
  // Classify each node: 0 = anchor/unmatched, +1..+n_above = above[k-1], -1..-n_below = below[-k-1]
  let node_bucket : Array[Int32] = []
  let mut anchor_has = false
  let mut anchor_min = 0.0
  let mut anchor_max = 0.0
  let above_has : Array[Bool] = Array::make(n_above, false)
  let above_min : Array[Double] = Array::make(n_above, 0.0)
  let above_max : Array[Double] = Array::make(n_above, 0.0)
  let below_has : Array[Bool] = Array::make(n_below, false)
  let below_min : Array[Double] = Array::make(n_below, 0.0)
  let below_max : Array[Double] = Array::make(n_below, 0.0)

  for node in design.nodes {
    let (lo, hi) = node_axis_span(node, self.axis)
    let mut is_anchor = false
    for pat in self.anchor_patterns {
      if node.name.contains(pat) {
        is_anchor = true
        break
      }
    }
    if is_anchor {
      node_bucket.push(0)
      if !anchor_has {
        anchor_has = true
        anchor_min = lo
        anchor_max = hi
      } else {
        if lo < anchor_min {
          anchor_min = lo
        }
        if hi > anchor_max {
          anchor_max = hi
        }
      }
      continue
    }
    let mut matched : Int32 = 0
    for k in 0..<n_above {
      if layer_matches(self.above_layers[k], node) {
        matched = k + 1
        if !above_has[k] {
          above_has[k] = true
          above_min[k] = lo
          above_max[k] = hi
        } else {
          if lo < above_min[k] {
            above_min[k] = lo
          }
          if hi > above_max[k] {
            above_max[k] = hi
          }
        }
        break
      }
    }
    if matched == 0 {
      for k in 0..<n_below {
        if layer_matches(self.below_layers[k], node) {
          matched = -(k + 1)
          if !below_has[k] {
            below_has[k] = true
            below_min[k] = lo
            below_max[k] = hi
          } else {
            if lo < below_min[k] {
              below_min[k] = lo
            }
            if hi > below_max[k] {
              below_max[k] = hi
            }
          }
          break
        }
      }
    }
    node_bucket.push(matched)
  }

  // Compute collision-free scalar offsets walking outward from the anchor.
  let above_off : Array[Double] = Array::make(n_above, 0.0)
  let mut cursor_up = if anchor_has { anchor_max } else { 0.0 }
  for k in 0..<n_above {
    if !above_has[k] {
      continue
    }
    let gap = self.above_layers[k].gap_override_mm.unwrap_or(
      self.default_gap_mm,
    )
    let target_lo = cursor_up + gap
    let delta = target_lo - above_min[k]
    let off = if delta > 0.0 { delta } else { 0.0 }
    above_off[k] = off
    cursor_up = above_max[k] + off
  }

  let below_off : Array[Double] = Array::make(n_below, 0.0)
  let mut cursor_dn = if anchor_has { anchor_min } else { 0.0 }
  for k in 0..<n_below {
    if !below_has[k] {
      continue
    }
    let gap = self.below_layers[k].gap_override_mm.unwrap_or(
      self.default_gap_mm,
    )
    let target_hi = cursor_dn - gap
    let delta = target_hi - below_max[k]
    let off = if delta < 0.0 { delta } else { 0.0 }
    below_off[k] = off
    cursor_dn = below_min[k] + off
  }

  let out : Array[(String, (Double, Double, Double))] = []
  for i in 0..<design.nodes.length() {
    let bucket = node_bucket[i]
    let scalar = if bucket > 0 {
      above_off[bucket - 1]
    } else if bucket < 0 {
      below_off[-bucket - 1]
    } else {
      0.0
    }
    out.push((design.nodes[i].name, axis_vector(self.axis, scalar)))
  }
  out
}

///|
/// Returns a new `@step_cad.Design` with every matched node translated by its
/// collision-free coaxial explode offset.
pub fn ExplodeStack::apply(
  self : ExplodeStack,
  design : @step_cad.Design,
) -> @step_cad.Design {
  let offs = self.offsets(design)
  let mut out = @step_cad.Design::new(
    name=design.name,
    description=design.description,
    documentation=design.documentation,
  )
  for i in 0..<design.nodes.length() {
    let (dx, dy, dz) = offs[i].1
    out = out.add(design.nodes[i].translate(x=dx, y=dy, z=dz))
  }
  out
}
