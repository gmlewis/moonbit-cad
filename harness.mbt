///|
/// Cable routing: a polyline route with a jacket diameter and the wire runs it
/// carries, plus geometric and wire-length checks.

///|
/// One routed cable bundle.  Points are in the owning component's local frame,
/// in millimetres.
pub(all) struct CableRoute {
  name : String
  points : Array[(Double, Double, Double)]
  jacket_diameter_mm : Double
  /// Wire runs carried by this bundle.
  wire_names : Array[String]
  material : String
  /// Component and port at the source connector (empty when not modeled).
  from_component : String
  from_port : String
  /// Component and port at the destination connector.
  to_component : String
  to_port : String
}

///|
pub fn CableRoute::new(
  name : String,
  points~ : Array[(Double, Double, Double)] = [],
  jacket_diameter_mm~ : Double = 0.0,
  wire_names~ : Array[String] = [],
  material~ : String = "",
  from_component~ : String = "",
  from_port~ : String = "",
  to_component~ : String = "",
  to_port~ : String = "",
) -> CableRoute {
  {
    name,
    points,
    jacket_diameter_mm,
    wire_names,
    material,
    from_component,
    from_port,
    to_component,
    to_port,
  }
}

///|
fn cable_segment_length(
  from : (Double, Double, Double),
  to : (Double, Double, Double),
) -> Double {
  let dx = to.0 - from.0
  let dy = to.1 - from.1
  let dz = to.2 - from.2
  (dx * dx + dy * dy + dz * dz).sqrt()
}

///|
fn route_label(path : String, name : String) -> String {
  let component = leaf_name(path)
  if component == name {
    name
  } else {
    component + "/" + name
  }
}

///|
/// Total routed length, in millimetres.
pub fn CableRoute::length_mm(self : CableRoute) -> Double {
  let mut total = 0.0
  for i in 1..<self.points.length() {
    total = total + cable_segment_length(self.points[i - 1], self.points[i])
  }
  total
}

///|
/// Sets the routed cable bundles for this component.
pub fn Component::with_cable_route(
  self : Component,
  route : CableRoute,
) -> Component {
  { ..self, cables: [route], }
}

///|
/// Adds a routed cable bundle to this component.
pub fn Component::add_cable_route(
  self : Component,
  route : CableRoute,
) -> Component {
  self.cables.push(route)
  self
}

///|
/// All cable routes declared anywhere in this component tree.
pub fn Component::cable_routes(self : Component) -> Array[CableRoute] {
  let routes : Array[CableRoute] = []
  self.collect_cable_routes(routes)
  routes
}

///|
fn Component::collect_cable_routes(
  self : Component,
  routes : Array[CableRoute],
) -> Unit {
  for route in self.cables {
    routes.push(route)
  }
  for att in self.attachments {
    att.child.collect_cable_routes(routes)
  }
}

///|
fn Component::collect_cable_entries(
  self : Component,
  path : String,
  routes : Array[(String, CableRoute)],
) -> Unit {
  for route in self.cables {
    routes.push((path, route))
  }
  for att in self.attachments {
    att.child.collect_cable_entries(path + "/" + att.child.name, routes)
  }
}

///|
fn Component::collect_wire_entries(
  self : Component,
  path : String,
  wires : Array[(String, WireRun)],
) -> Unit {
  for run in self.wiring {
    wires.push((path, run))
  }
  for att in self.attachments {
    att.child.collect_wire_entries(path + "/" + att.child.name, wires)
  }
}

///|
fn wire_named(wires : Array[(String, WireRun)], name : String) -> WireRun? {
  for entry in wires {
    if entry.1.name == name {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Checks cable routes: valid geometry, known wire names, and wire runs that
/// are long enough for the route they follow.
///
/// Returns no warnings when the tree declares no routes.
pub fn Component::harness_checks(self : Component) -> Array[String] {
  let warnings : Array[String] = []
  let routes : Array[(String, CableRoute)] = []
  self.collect_cable_entries(self.name, routes)
  if routes.length() == 0 {
    return warnings
  }
  let wires : Array[(String, WireRun)] = []
  self.collect_wire_entries(self.name, wires)
  let seen : Array[String] = []
  for entry in routes {
    let path = entry.0
    let route = entry.1
    let label = route_label(path, route.name)
    if array_has(seen, route.name) {
      warnings.push("duplicate cable route name '" + route.name + "'")
    } else {
      seen.push(route.name)
    }
    if route.points.length() < 2 {
      warnings.push("cable route '" + label + "' has fewer than two points")
    }
    if route.jacket_diameter_mm <= 0.0 {
      warnings.push("cable route '" + label + "' has no jacket diameter")
    }
    let route_length = route.length_mm()
    if route_length <= 0.0 {
      warnings.push("cable route '" + label + "' has no length")
    }
    if route.wire_names.length() == 0 {
      warnings.push("cable route '" + label + "' carries no wires")
    }
    for name in route.wire_names {
      match wire_named(wires, name) {
        Some(run) =>
          if route_length > 0.0 && run.length_mm < route_length {
            warnings.push(
              "wire '" +
              name +
              "' is shorter (" +
              run.length_mm.to_string() +
              " mm) than cable route '" +
              label +
              "' (" +
              round2(route_length).to_string() +
              " mm)",
            )
          }
        None =>
          warnings.push(
            "cable route '" + label + "' references unknown wire '" + name + "'",
          )
      }
    }
  }
  warnings
}

///|
fn Component::collect_component_ports(
  self : Component,
  entries : Array[(String, Array[String])],
) -> Unit {
  let ports : Array[String] = []
  for port in self.ports {
    ports.push(port.name)
  }
  entries.push((self.name, ports))
  for att in self.attachments {
    att.child.collect_component_ports(entries)
  }
}

///|
fn ports_for(
  entries : Array[(String, Array[String])],
  component : String,
) -> Array[String]? {
  for entry in entries {
    if entry.0 == component {
      return Some(entry.1)
    }
  }
  None
}

///|
fn check_connector(
  warnings : Array[String],
  components : Array[(String, Array[String])],
  owner : String,
  end : String,
  component : String,
  port : String,
) -> Unit {
  if component == "" {
    warnings.push(owner + " has no " + end + " component")
    return
  }
  match ports_for(components, component) {
    Some(ports) =>
      if port != "" && !array_has(ports, port) {
        warnings.push(
          owner +
          " " +
          end +
          " references unknown port '" +
          port +
          "' on component '" +
          component +
          "'",
        )
      }
    None =>
      warnings.push(
        owner + " " + end + " references unknown component '" + component + "'",
      )
  }
}

///|
/// Connector mating checks: every wire and cable-route endpoint must resolve to
/// a component and (when given) a port, and every wire carried by a route must
/// actually connect that route's two components.
pub fn Component::wiring_checks(self : Component) -> Array[String] {
  let warnings : Array[String] = []
  let components : Array[(String, Array[String])] = []
  self.collect_component_ports(components)
  let wires : Array[(String, WireRun)] = []
  self.collect_wire_entries(self.name, wires)
  for entry in wires {
    let run = entry.1
    let owner = "wire '" + run.name + "'"
    check_connector(
      warnings,
      components,
      owner,
      "source",
      run.from_component,
      run.from_port,
    )
    check_connector(
      warnings,
      components,
      owner,
      "destination",
      run.to_component,
      run.to_port,
    )
    if run.from_component != "" && run.from_component == run.to_component {
      warnings.push(owner + " connects a component to itself")
    }
  }
  let routes : Array[(String, CableRoute)] = []
  self.collect_cable_entries(self.name, routes)
  for entry in routes {
    let route = entry.1
    let owner = "cable route '" + route.name + "'"
    if route.from_component != "" || route.from_port != "" {
      check_connector(
        warnings,
        components,
        owner,
        "source",
        route.from_component,
        route.from_port,
      )
    }
    if route.to_component != "" || route.to_port != "" {
      check_connector(
        warnings,
        components,
        owner,
        "destination",
        route.to_component,
        route.to_port,
      )
    }
    if route.from_component != "" && route.to_component != "" {
      for name in route.wire_names {
        match wire_named(wires, name) {
          Some(run) => {
            let forward = run.from_component == route.from_component &&
              run.to_component == route.to_component
            let reverse = run.from_component == route.to_component &&
              run.to_component == route.from_component
            if !forward && !reverse {
              warnings.push(
                owner +
                " carries wire '" +
                name +
                "', which connects '" +
                run.from_component +
                "' to '" +
                run.to_component +
                "'",
              )
            }
          }
          None => ()
        }
      }
    }
  }
  warnings
}
