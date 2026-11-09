///|
test "cable route length and wire-length checks" {
  let comp = @cad.Component::new("root").add_wire_run(
    @cad.WireRun::new(
      "motor_power",
      from_component="controller",
      from_port="power",
      to_component="motor",
      to_port="power",
      gauge_awg=20,
      length_mm=100.0,
    ),
  )
  let _ = comp.add_cable_route(
    @cad.CableRoute::new(
      "harness",
      points=[(0.0, 0.0, 0.0), (30.0, 0.0, 0.0), (30.0, 40.0, 0.0)],
      jacket_diameter_mm=6.0,
      wire_names=["motor_power"],
      material="PVC",
    ),
  )
  let routes = comp.cable_routes()
  assert_eq(routes.length(), 1)
  assert_true((routes[0].length_mm() - 70.0).abs() < 1.0e-9)
  assert_eq(comp.harness_checks().length(), 0)
}

///|
test "harness checks flag short wires, unknown wires, and bad routes" {
  let comp = @cad.Component::new("root")
    .add_wire_run(
      @cad.WireRun::new(
        "short_wire",
        from_component="a",
        from_port="p",
        to_component="b",
        to_port="q",
        gauge_awg=26,
        length_mm=50.0,
      ),
    )
    .add_cable_route(
      @cad.CableRoute::new(
        "long_route",
        points=[(0.0, 0.0, 0.0), (70.0, 0.0, 0.0)],
        jacket_diameter_mm=4.0,
        wire_names=["short_wire", "ghost_wire"],
        material="PVC",
      ),
    )
    .add_cable_route(
      @cad.CableRoute::new("one_point", points=[(0.0, 0.0, 0.0)]),
    )
    .add_cable_route(
      @cad.CableRoute::new(
        "long_route",
        points=[(0.0, 0.0, 0.0), (10.0, 0.0, 0.0)],
        jacket_diameter_mm=4.0,
        wire_names=["short_wire"],
      ),
    )
  let warnings = comp.harness_checks()
  let has = fn(needle : String) -> Bool {
    warnings.fold(init=false, fn(acc, warning) {
      acc || warning.contains(needle)
    })
  }
  assert_true(has("is shorter"))
  assert_true(has("unknown wire 'ghost_wire'"))
  assert_true(has("fewer than two points"))
  assert_true(has("duplicate cable route name 'long_route'"))
  assert_true(has("has no jacket diameter"))
}

///|
test "no routes means no harness warnings" {
  let comp = @cad.Component::new("root")
  assert_eq(comp.harness_checks().length(), 0)
}
