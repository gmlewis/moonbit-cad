///|
/// Electrical metadata: actuator and sensor specifications, PCB envelopes, wire
/// runs, and the power/IO budget derived from a component tree.
///
/// These records are additive; geometry and kinematics stay in `Component` and
/// `BodyPart`.

///|
/// The kind of actuator a component represents.
pub(all) enum ActuatorKind {
  Stepper
  Bldc
  Servo
  Hub
}

///|
/// Electrical and mechanical ratings for one actuator.
pub(all) struct ActuatorSpec {
  kind : ActuatorKind
  model : String
  voltage_v : Double
  current_rated_a : Double
  current_stall_a : Double
  torque_rated_nm : Double
  driver : String
  /// Control interface, e.g. `"STEP/DIR"`, `"CAN"`, `"PWM"`.
  interface : String
  /// Feedback, e.g. `"none"` or `"magnetic 14-bit"`.
  encoder : String
}

///|
pub fn ActuatorSpec::new(
  kind : ActuatorKind,
  model~ : String = "",
  voltage_v~ : Double = 0.0,
  current_rated_a~ : Double = 0.0,
  current_stall_a~ : Double = 0.0,
  torque_rated_nm~ : Double = 0.0,
  driver~ : String = "",
  interface~ : String = "",
  encoder~ : String = "",
) -> ActuatorSpec {
  {
    kind,
    model,
    voltage_v,
    current_rated_a,
    current_stall_a,
    torque_rated_nm,
    driver,
    interface,
    encoder,
  }
}

///|
/// The kind of sensor a component represents.
pub(all) enum SensorKind {
  LimitSwitch
  Encoder
  Imu
  Camera
  Force
}

///|
/// Electrical and measuring characteristics for one sensor.
pub(all) struct SensorSpec {
  kind : SensorKind
  model : String
  /// Electrical interface, e.g. `"GPIO"`, `"I2C"`, `"SPI"`, `"USB"`.
  interface : String
  voltage_v : Double
  current_ma : Double
  range : String
  resolution : String
}

///|
pub fn SensorSpec::new(
  kind : SensorKind,
  model~ : String = "",
  interface~ : String = "",
  voltage_v~ : Double = 0.0,
  current_ma~ : Double = 0.0,
  range~ : String = "",
  resolution~ : String = "",
) -> SensorSpec {
  { kind, model, interface, voltage_v, current_ma, range, resolution, }
}

///|
/// A PCB envelope: outline, thickness, mounting holes, height limit, and the
/// connectors that must be reachable.
pub(all) struct PcbSpec {
  model : String
  length_mm : Double
  width_mm : Double
  thickness_mm : Double
  mounting_holes : Int32
  mounting_hole_diam_mm : Double
  max_component_height_mm : Double
  connectors : Array[String]
}

///|
pub fn PcbSpec::new(
  model~ : String = "",
  length_mm~ : Double = 0.0,
  width_mm~ : Double = 0.0,
  thickness_mm~ : Double = 1.6,
  mounting_holes~ : Int32 = 4,
  mounting_hole_diam_mm~ : Double = 2.7,
  max_component_height_mm~ : Double = 0.0,
  connectors~ : Array[String] = [],
) -> PcbSpec {
  {
    model,
    length_mm,
    width_mm,
    thickness_mm,
    mounting_holes,
    mounting_hole_diam_mm,
    max_component_height_mm,
    connectors,
  }
}

///|
/// One point-to-point cable run.
pub(all) struct WireRun {
  name : String
  from_component : String
  from_port : String
  to_component : String
  to_port : String
  gauge_awg : Int32
  length_mm : Double
  notes : String
}

///|
pub fn WireRun::new(
  name : String,
  from_component~ : String,
  from_port~ : String,
  to_component~ : String,
  to_port~ : String,
  gauge_awg~ : Int32 = 24,
  length_mm~ : Double = 0.0,
  notes~ : String = "",
) -> WireRun {
  {
    name,
    from_component,
    from_port,
    to_component,
    to_port,
    gauge_awg,
    length_mm,
    notes,
  }
}

///|
/// One actuator line in the power budget.
pub(all) struct ActuatorLine {
  path : String
  spec : ActuatorSpec
}

///|
/// One sensor line in the power budget.
pub(all) struct SensorLine {
  path : String
  spec : SensorSpec
}

///|
/// One port line in the IO map.
pub(all) struct PortLine {
  path : String
  name : String
  kind : String
  spec : String
}

///|
/// One wire line in the harness report.
pub(all) struct WireLine {
  path : String
  run : WireRun
}

///|
/// One routed cable bundle in the harness report.
pub(all) struct RouteLine {
  path : String
  route : CableRoute
}

///|
/// The electrical budget for a component tree.
pub(all) struct PowerBudget {
  actuators : Array[ActuatorLine]
  sensors : Array[SensorLine]
  ports : Array[PortLine]
  wires : Array[WireLine]
  routes : Array[RouteLine]
}

///|
pub fn PowerBudget::new() -> PowerBudget {
  { actuators: [], sensors: [], ports: [], wires: [], routes: [], }
}

///|
/// Renders the power, IO, and wiring report.
pub fn PowerBudget::to_text(self : PowerBudget) -> String {
  let mut out = "Power and IO budget\n===================\n\nActuators\n---------\n"
  if self.actuators.length() == 0 {
    out = out + "(none)\n"
  }
  for line in self.actuators {
    let spec = line.spec
    out = out +
      leaf_name(line.path) +
      " | " +
      spec.model +
      " | " +
      actuator_kind_name(spec.kind) +
      " | " +
      spec.voltage_v.to_string() +
      " V | " +
      spec.current_rated_a.to_string() +
      " A rated / " +
      spec.current_stall_a.to_string() +
      " A stall | " +
      spec.torque_rated_nm.to_string() +
      " N·m | " +
      spec.driver +
      " | " +
      spec.interface +
      " | " +
      spec.encoder +
      "\n"
  }
  out = out + "\nPower summary\n-------------\n"
  let voltages : Array[Double] = []
  for line in self.actuators {
    push_unique_voltage(voltages, line.spec.voltage_v)
  }
  for line in self.sensors {
    push_unique_voltage(voltages, line.spec.voltage_v)
  }
  if voltages.length() == 0 {
    out = out + "(none)\n"
  }
  for voltage in voltages {
    let mut actuator_count = 0
    let mut sensor_count = 0
    let mut rated_a = 0.0
    let mut stall_a = 0.0
    let mut sensor_ma = 0.0
    for line in self.actuators {
      if line.spec.voltage_v == voltage {
        actuator_count = actuator_count + 1
        rated_a = rated_a + line.spec.current_rated_a
        stall_a = stall_a + line.spec.current_stall_a
      }
    }
    for line in self.sensors {
      if line.spec.voltage_v == voltage {
        sensor_count = sensor_count + 1
        sensor_ma = sensor_ma + line.spec.current_ma
      }
    }
    out = out +
      voltage.to_string() +
      " V: " +
      actuator_count.to_string() +
      " actuator(s), " +
      sensor_count.to_string() +
      " sensor(s) | " +
      rated_a.to_string() +
      " A rated (" +
      round2(voltage * rated_a).to_string() +
      " W), " +
      stall_a.to_string() +
      " A stall (" +
      round2(voltage * stall_a).to_string() +
      " W), sensors " +
      sensor_ma.to_string() +
      " mA\n"
  }
  out = out + "\nSensors\n-------\n"
  if self.sensors.length() == 0 {
    out = out + "(none)\n"
  }
  for line in self.sensors {
    let spec = line.spec
    out = out +
      leaf_name(line.path) +
      " | " +
      spec.model +
      " | " +
      sensor_kind_name(spec.kind) +
      " | " +
      spec.interface +
      " | " +
      spec.voltage_v.to_string() +
      " V | " +
      spec.current_ma.to_string() +
      " mA | " +
      spec.range +
      " | " +
      spec.resolution +
      "\n"
  }
  out = out + "\nPorts\n-----\n"
  if self.ports.length() == 0 {
    out = out + "(none)\n"
  }
  for port in self.ports {
    out = out +
      leaf_name(port.path) +
      " | " +
      port.name +
      " | " +
      port.kind +
      " | " +
      port.spec +
      "\n"
  }
  out = out + "\nWiring\n------\n"
  if self.wires.length() == 0 {
    out = out + "(none)\n"
  }
  for wire in self.wires {
    let run = wire.run
    out = out +
      run.name +
      " | " +
      run.from_component +
      "." +
      run.from_port +
      " -> " +
      run.to_component +
      "." +
      run.to_port +
      " | AWG " +
      run.gauge_awg.to_string() +
      " | " +
      run.length_mm.to_string() +
      " mm | " +
      run.notes +
      "\n"
  }
  out = out + "\nCable routes\n------------\n"
  if self.routes.length() == 0 {
    out = out + "(none)\n"
  }
  for entry in self.routes {
    let route = entry.route
    out = out +
      route_label(entry.path, route.name) +
      " | jacket " +
      route.jacket_diameter_mm.to_string() +
      " mm | " +
      round2(route.length_mm()).to_string() +
      " mm | " +
      route.material +
      " | wires: " +
      array_join(route.wire_names, ", ") +
      "\n"
  }
  out
}

///|
fn actuator_kind_name(kind : ActuatorKind) -> String {
  match kind {
    Stepper => "stepper"
    Bldc => "bldc"
    Servo => "servo"
    Hub => "hub"
  }
}

///|
fn sensor_kind_name(kind : SensorKind) -> String {
  match kind {
    LimitSwitch => "limit switch"
    Encoder => "encoder"
    Imu => "imu"
    Camera => "camera"
    Force => "force"
  }
}

///|
fn port_kind_name(kind : PortKind) -> String {
  match kind {
    Mechanical => "mechanical"
    Power => "power"
    Signal => "signal"
    Bus => "bus"
    Fluid => "fluid"
    Sensor => "sensor"
    Ground => "ground"
  }
}

///|
fn round2(value : Double) -> Double {
  let scale = 100.0
  let scaled = value * scale
  (scaled + 0.5).to_int().to_double() / scale
}

///|
fn push_unique_voltage(voltages : Array[Double], voltage : Double) -> Unit {
  let seen = voltages.fold(init=false, fn(acc, value) {
    acc || value == voltage
  })
  if !seen {
    voltages.push(voltage)
  }
}

///|
/// Walks the tree and collects actuator, sensor, port, and wire data.
pub fn Component::power_budget(self : Component) -> PowerBudget {
  let budget = PowerBudget::new()
  self.collect_power_budget(self.name, budget)
  budget
}

///|
/// The full power/IO/wiring report for this component tree.
pub fn Component::report_text(self : Component) -> String {
  self.power_budget().to_text()
}

///|
fn Component::collect_power_budget(
  self : Component,
  path : String,
  budget : PowerBudget,
) -> Unit {
  match self.actuator {
    Some(spec) => budget.actuators.push({ path, spec, })
    None => ()
  }
  match self.sensor {
    Some(spec) => budget.sensors.push({ path, spec, })
    None => ()
  }
  for port in self.ports {
    budget.ports.push({
      path,
      name: port.name,
      kind: port_kind_name(port.kind),
      spec: port.spec,
    })
  }
  for run in self.wiring {
    budget.wires.push({ path, run, })
  }
  for route in self.cables {
    budget.routes.push({ path, route, })
  }
  for att in self.attachments {
    att.child.collect_power_budget(path + "/" + att.child.name, budget)
  }
}

///|
/// Sets the actuator ratings for this component.
pub fn Component::with_actuator(
  self : Component,
  actuator : ActuatorSpec,
) -> Component {
  { ..self, actuator: Some(actuator), }
}

///|
/// Sets the sensor characteristics for this component.
pub fn Component::with_sensor(
  self : Component,
  sensor : SensorSpec,
) -> Component {
  { ..self, sensor: Some(sensor), }
}

///|
/// Sets the PCB envelope metadata for this component.
pub fn Component::with_pcb(self : Component, pcb : PcbSpec) -> Component {
  { ..self, pcb: Some(pcb), }
}

///|
/// Adds a point-to-point cable run to this component's harness.
pub fn Component::add_wire_run(self : Component, run : WireRun) -> Component {
  self.wiring.push(run)
  self
}

///|
/// Checks electrical metadata for problems: invalid ratings, missing
/// interfaces, bad PCB dimensions, and incomplete wire runs.
fn Component::collect_electronics_checks(
  self : Component,
  path : String,
  warnings : Array[String],
) -> Unit {
  match self.actuator {
    Some(spec) => {
      if spec.voltage_v <= 0.0 {
        warnings.push(path + ": actuator has no supply voltage")
      }
      if spec.current_rated_a <= 0.0 {
        warnings.push(path + ": actuator has no rated current")
      }
      if spec.current_stall_a < spec.current_rated_a {
        warnings.push(path + ": actuator stall current is below rated current")
      }
      if spec.torque_rated_nm <= 0.0 {
        warnings.push(path + ": actuator has no rated torque")
      }
      if spec.interface == "" {
        warnings.push(path + ": actuator has no control interface")
      }
    }
    None => ()
  }
  match self.sensor {
    Some(spec) => {
      if spec.voltage_v <= 0.0 {
        warnings.push(path + ": sensor has no supply voltage")
      }
      if spec.current_ma < 0.0 {
        warnings.push(path + ": sensor has negative current draw")
      }
      if spec.interface == "" {
        warnings.push(path + ": sensor has no interface")
      }
    }
    None => ()
  }
  match self.pcb {
    Some(spec) => {
      if spec.length_mm <= 0.0 || spec.width_mm <= 0.0 {
        warnings.push(path + ": PCB has no outline")
      }
      if spec.thickness_mm <= 0.0 {
        warnings.push(path + ": PCB has no thickness")
      }
      if spec.mounting_holes < 0 {
        warnings.push(path + ": PCB has a negative mounting-hole count")
      }
      if spec.max_component_height_mm <= 0.0 {
        warnings.push(path + ": PCB has no component height limit")
      }
    }
    None => ()
  }
  for run in self.wiring {
    if run.from_component == "" || run.from_port == "" {
      warnings.push(path + ": wire '" + run.name + "' has no source")
    }
    if run.to_component == "" || run.to_port == "" {
      warnings.push(path + ": wire '" + run.name + "' has no destination")
    }
    if run.gauge_awg < 10 || run.gauge_awg > 30 {
      warnings.push(path + ": wire '" + run.name + "' has an invalid gauge")
    }
    if run.length_mm <= 0.0 {
      warnings.push(path + ": wire '" + run.name + "' has no length")
    }
  }
}
