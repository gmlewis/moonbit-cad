///|
test "power budget aggregates actuators, sensors, ports, and wiring" {
  let motor = @cad.Component::new("motor")
    .with_actuator(
      @cad.ActuatorSpec::new(
        @cad.ActuatorKind::Bldc,
        model="QDD-96",
        voltage_v=48.0,
        current_rated_a=8.0,
        current_stall_a=20.0,
        torque_rated_nm=45.0,
        driver="ODrive",
        interface="CAN",
        encoder="magnetic 14-bit",
      ),
    )
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="48 V, 8 A"))
  let sensor = @cad.Component::new("sensor").with_sensor(
    @cad.SensorSpec::new(
      @cad.SensorKind::LimitSwitch,
      model="microswitch",
      interface="GPIO",
      voltage_v=5.0,
      current_ma=10.0,
      range="5 mm",
      resolution="binary",
    ),
  )
  let board = @cad.Component::new("board")
    .with_pcb(
      @cad.PcbSpec::new(
        model="CTRL-40x30",
        length_mm=40.0,
        width_mm=30.0,
        thickness_mm=1.6,
        mounting_holes=4,
        mounting_hole_diam_mm=2.7,
        max_component_height_mm=12.0,
        connectors=["power"],
      ),
    )
    .add_wire_run(
      @cad.WireRun::new(
        "home_signal",
        from_component="sensor",
        from_port="signal",
        to_component="board",
        to_port="limit_home",
        gauge_awg=26,
        length_mm=100.0,
      ),
    )
  let root = @cad.Component::new("root")
    .attach("motor_mount", parent_mate="origin", motor)
    .attach("sensor_mount", parent_mate="origin", sensor)
    .attach("board_mount", parent_mate="origin", board)
  let budget = root.power_budget()
  assert_eq(budget.actuators.length(), 1)
  assert_eq(budget.sensors.length(), 1)
  assert_eq(budget.ports.length(), 1)
  assert_eq(budget.wires.length(), 1)
  let text = root.report_text()
  assert_true(text.contains("Power and IO budget"))
  assert_true(text.contains("48 V"))
  assert_true(text.contains("QDD-96"))
  assert_true(text.contains("5 V"))
  assert_true(text.contains("AWG 26"))
}

///|
test "assembly checks flag invalid electronics metadata" {
  let bad = @cad.Component::new("bad")
    .with_actuator(
      @cad.ActuatorSpec::new(
        @cad.ActuatorKind::Bldc,
        voltage_v=0.0,
        current_rated_a=10.0,
        current_stall_a=5.0,
      ),
    )
    .with_sensor(@cad.SensorSpec::new(@cad.SensorKind::Imu, current_ma=-1.0))
    .with_pcb(
      @cad.PcbSpec::new(
        length_mm=0.0,
        width_mm=0.0,
        thickness_mm=0.0,
        mounting_holes=0,
        max_component_height_mm=0.0,
      ),
    )
    .add_wire_run(
      @cad.WireRun::new(
        "bad_wire",
        from_component="",
        from_port="",
        to_component="",
        to_port="",
        gauge_awg=40,
        length_mm=0.0,
      ),
    )
  let warnings = bad.assembly_checks()
  let has = fn(needle : String) -> Bool {
    warnings.fold(init=false, fn(acc, warning) {
      acc || warning.contains(needle)
    })
  }
  assert_true(has("no supply voltage"))
  assert_true(has("stall current is below rated current"))
  assert_true(has("no rated torque"))
  assert_true(has("no control interface"))
  assert_true(has("negative current draw"))
  assert_true(has("no outline"))
  assert_true(has("no source"))
  assert_true(has("invalid gauge"))
  assert_true(has("no length"))
}
