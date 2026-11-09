///|
/// Cable-route builders: a polyline of jacket segments with part metadata and
/// the wire runs it carries.

///|
fn route_rad_to_deg(radians : Double) -> Double {
  radians * 180.0 / @math.PI
}

///|
/// Builds a routed cable bundle from a polyline of points (millimetres, local
/// frame).  Each segment becomes a cylinder of `jacket_diameter_mm`; the bundle
/// carries the named wire runs and a purchased part number with its length.
pub fn cable_route(
  name~ : String = "harness",
  points~ : Array[(Double, Double, Double)] = [],
  jacket_diameter_mm~ : Double = 5.0,
  wire_names~ : Array[String] = [],
  material~ : String = "PVC",
  density~ : @urdf.Density = @urdf.Density::kg_per_m3(1400.0),
  color~ : @step_cad.Rgb = @step_cad.Rgb::black(),
) -> @cad.Component {
  let route = @cad.CableRoute::new(
    name,
    points~,
    jacket_diameter_mm~,
    wire_names~,
    material~,
  )
  let mut comp = @cad.Component::new(name, description="Cable route")
    .with_param("jacket_diameter_mm", jacket_diameter_mm.to_string())
    .add_mate_mm_deg("mount")
  if points.length() >= 2 {
    for i in 0..<(points.length() - 1) {
      let from = points[i]
      let to = points[i + 1]
      let dx = to.0 - from.0
      let dy = to.1 - from.1
      let dz = to.2 - from.2
      let length = (dx * dx + dy * dy + dz * dz).sqrt()
      if length > 0.0 {
        let theta_deg = route_rad_to_deg(@math.acos(dz / length))
        let phi_deg = route_rad_to_deg(@math.atan2(dy, dx))
        comp = comp.add_body(
          @cad.BodyPart::cylinder_mm(
            name + "_seg_" + i.to_string(),
            jacket_diameter_mm,
            length,
            x_mm=(from.0 + to.0) / 2.0,
            y_mm=(from.1 + to.1) / 2.0,
            z_mm=(from.2 + to.2) / 2.0,
            ry_deg=theta_deg,
            rz_deg=phi_deg,
            density~,
            color~,
          ),
        )
      }
    }
  }
  let mm_per_m = 1000.0
  let jacket_base_usd = 1.0
  let cost_per_m_usd = 2.0
  let length_mm = route.length_mm().to_int()
  let unit_cost_usd = jacket_base_usd +
    cost_per_m_usd * route.length_mm() / mm_per_m
  let part = purchased_part(
    "CABLE-" + jacket_diameter_mm.to_string() + "-" + length_mm.to_string(),
    "Cable bundle " +
    jacket_diameter_mm.to_string() +
    " mm x " +
    length_mm.to_string() +
    " mm",
    material,
    unit_cost_usd,
    supplier_url="https://www.mcmaster.com/cable/",
  )
  comp.with_cable_route(route).with_part(part)
}
