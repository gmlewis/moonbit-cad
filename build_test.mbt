///|
fn build_test_component() -> @cad.Component {
  let motor_part = @cad.PartMeta::new(
    "MOTOR-1",
    description="motor",
    supplier="generic",
    supplier_url="https://example.com/motor",
    material="mixed",
    process="purchased",
    unit_cost_usd=10.0,
  )
  let plate_part = @cad.PartMeta::new(
    "PLATE-1",
    description="printed plate",
    supplier="in-house",
    material="PLA",
    process="print",
    unit_cost_usd=2.0,
  )
  let screw_part = @cad.PartMeta::new(
    "SCREW-M3x12",
    description="screw",
    supplier="generic",
    supplier_url="https://example.com/screw",
    material="steel",
    process="purchased",
    unit_cost_usd=0.3,
  )
  let sensor = @cad.Component::new("sensor")
    .add_body(@cad.BodyPart::box_mm("sensor_body", 10.0, 10.0, 6.0))
    .with_part(
      @cad.PartMeta::new(
        "SENSOR-1",
        description="sensor",
        supplier="generic",
        supplier_url="https://example.com/sensor",
        material="mixed",
        process="purchased",
        unit_cost_usd=5.0,
      ),
    )
    .with_sensor(
      @cad.SensorSpec::new(
        @cad.SensorKind::LimitSwitch,
        model="microswitch",
        interface="GPIO",
        voltage_v=5.0,
        current_ma=10.0,
      ),
    )
  let arm = @cad.Component::new("arm").add_body(
    @cad.BodyPart::box_mm("arm_body", 10.0, 10.0, 10.0),
  )
  let root = @cad.Component::new("base")
    .add_body(
      @cad.BodyPart::box_mm("motor_body", 20.0, 20.0, 10.0).with_part(
        motor_part,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm("plate_body", 20.0, 20.0, 5.0, z_mm=10.0).with_part(
        plate_part,
      ),
    )
    .add_fastener(
      @cad.Fastener::new(
        "bolts",
        @cad.FastenerKind::Screw,
        thread="M3",
        length_mm=12.0,
        engagement_mm=6.0,
        quantity=4,
        torque_nm=1.2,
        references=["motor_body"],
        part=Some(screw_part),
      ),
    )
    .attach("sensor_mount", parent_mate="origin", sensor)
    .attach(
      "arm_joint",
      parent_mate="origin",
      arm,
      spec=@cad.JointSpec::revolute(
        @urdf.JointLimit::new(
          lower=Some(-1.0),
          upper=Some(1.0),
          effort=1.0,
          velocity=1.0,
        ),
      ),
    )
  let _ = root.add_control_binding(
    @cad.ControlBinding::new("arm_joint", actuator="arm", channel="can0:1"),
  )
  root
}

///|
test "build package files cover sourcing, print list, torque, and procedure" {
  let root = build_test_component()
  let sourcing = root.sourcing_csv()
  assert_true(sourcing.contains("https://example.com/motor"))
  assert_true(sourcing.contains("PLATE-1"))
  let print_list = root.print_list_csv()
  assert_true(print_list.contains("PLATE-1"))
  assert_true(print_list.contains("largest flat face down"))
  assert_true(print_list.contains("0.20"))
  assert_true(!print_list.contains("MOTOR-1"))
  let fasteners = root.fastener_table_csv()
  assert_true(fasteners.contains("\"bolts\""))
  assert_true(fasteners.contains("SCREW-M3x12"))
  assert_true(fasteners.contains("1.2"))
  let procedure = root.build_procedure_text()
  assert_true(procedure.contains("Fastener torque table"))
  assert_true(procedure.contains("Electrical checkout"))
  assert_true(procedure.contains("arm_joint"))
  assert_true(procedure.contains("sensor"))
  let manifest = root.build_manifest(name="demo")
  assert_true(manifest.contains("# Build package: demo"))
  assert_true(manifest.contains("`sourcing.csv`"))
  assert_true(manifest.contains("bundle/parts"))
  let files = root.build_package_files(name="demo")
  assert_eq(files.length(), 11)
  let names : Array[String] = files.map(fn(file) { file.path })
  for
    name in [
      "README.md", "bom.csv", "sourcing.csv", "print-list.csv", "fasteners.csv",
      "assembly.txt", "report.txt", "control.yaml", "pins.csv",
    ] {
    assert_true(names.contains(name))
  }
}

///|
test "build manifest handles an empty component" {
  let empty = @cad.Component::new("empty")
  let manifest = empty.build_manifest(name="empty")
  assert_true(manifest.contains("BOM lines | 0"))
  assert_true(manifest.contains("Hardware warnings | 0"))
}
