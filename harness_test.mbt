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

///|
test "wiring checks resolve components, ports, and route endpoints" {
  let controller = @cad.Component::new("controller")
    .add_port(@cad.Port::new("power", @cad.PortKind::Power))
    .add_port(@cad.Port::new("motor", @cad.PortKind::Signal))
  let motor = @cad.Component::new("motor")
    .add_port(@cad.Port::new("power", @cad.PortKind::Power))
    .add_port(@cad.Port::new("step_dir", @cad.PortKind::Signal))
  let root = @cad.Component::new("root")
    .attach("controller_mount", parent_mate="origin", controller)
    .attach("motor_mount", parent_mate="origin", motor)
    .add_wire_run(
      @cad.WireRun::new(
        "power_wire",
        from_component="controller",
        from_port="power",
        to_component="motor",
        to_port="power",
        gauge_awg=20,
        length_mm=100.0,
      ),
    )
    .add_wire_run(
      @cad.WireRun::new(
        "step_wire",
        from_component="controller",
        from_port="motor",
        to_component="motor",
        to_port="step_dir",
        gauge_awg=26,
        length_mm=100.0,
      ),
    )
    .add_cable_route(
      @cad.CableRoute::new(
        "bundle",
        points=[(0.0, 0.0, 0.0), (40.0, 0.0, 0.0)],
        jacket_diameter_mm=5.0,
        wire_names=["power_wire"],
        material="PVC",
        from_component="controller",
        to_component="motor",
      ),
    )
  assert_eq(root.wiring_checks().length(), 0)
}

///|
test "wiring checks flag bad endpoints and route mismatches" {
  let controller = @cad.Component::new("controller").add_port(
    @cad.Port::new("power", @cad.PortKind::Power),
  )
  let motor = @cad.Component::new("motor").add_port(
    @cad.Port::new("power", @cad.PortKind::Power),
  )
  let other = @cad.Component::new("other").add_port(
    @cad.Port::new("signal", @cad.PortKind::Signal),
  )
  let root = @cad.Component::new("root")
    .attach("controller_mount", parent_mate="origin", controller)
    .attach("motor_mount", parent_mate="origin", motor)
    .attach("other_mount", parent_mate="origin", other)
    .add_wire_run(
      @cad.WireRun::new(
        "bad_component",
        from_component="controller",
        from_port="power",
        to_component="ghost",
        to_port="power",
        gauge_awg=20,
        length_mm=100.0,
      ),
    )
    .add_wire_run(
      @cad.WireRun::new(
        "bad_port",
        from_component="controller",
        from_port="power",
        to_component="motor",
        to_port="missing_port",
        gauge_awg=20,
        length_mm=100.0,
      ),
    )
    .add_wire_run(
      @cad.WireRun::new(
        "self_wire",
        from_component="controller",
        from_port="power",
        to_component="controller",
        to_port="power",
        gauge_awg=20,
        length_mm=100.0,
      ),
    )
    .add_wire_run(
      @cad.WireRun::new(
        "wrong_route",
        from_component="controller",
        from_port="power",
        to_component="other",
        to_port="signal",
        gauge_awg=26,
        length_mm=100.0,
      ),
    )
    .add_cable_route(
      @cad.CableRoute::new(
        "route",
        points=[(0.0, 0.0, 0.0), (40.0, 0.0, 0.0)],
        jacket_diameter_mm=5.0,
        wire_names=["wrong_route"],
        material="PVC",
        from_component="controller",
        to_component="motor",
        to_port="missing_port",
      ),
    )
  let warnings = root.wiring_checks()
  let has = fn(needle : String) -> Bool {
    warnings.fold(init=false, fn(acc, warning) {
      acc || warning.contains(needle)
    })
  }
  assert_true(has("unknown component 'ghost'"))
  assert_true(has("unknown port 'missing_port' on component 'motor'"))
  assert_true(has("connects a component to itself"))
  assert_true(has("carries wire 'wrong_route'"))
  assert_true(has("to 'other'"))
}
