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
  let mut root = @cad.Component::new("base")
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
  root = root.add_control_binding(
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
  assert_eq(files.length(), 15)
  let names : Array[String] = files.map(fn(file) { file.path })
  for
    name in [
      "START-HERE.md", "NAME-KEY.md", "README.md", "bom.csv", "sourcing.csv", "print-list.csv",
      "fasteners.csv", "assembly.txt", "report.txt", "control.yaml", "pins.csv",
    ] {
    assert_true(names.contains(name))
  }
}

///|
test "name key maps assembly names to parts" {
  let root = build_test_component()
  let key = root.name_key_text(name="demo")
  assert_true(key.contains("# Name key — demo"))
  assert_true(key.contains("SCREW-M3x12"))
  assert_true(key.contains("SENSOR-1"))
}

///|
test "start-here guide covers print, buy, and assemble" {
  let root = build_test_component()
  let guide = root.start_here_text(name="demo")
  assert_true(guide.contains("# Start here — demo"))
  assert_true(guide.contains("## 1. 3D-print these files"))
  assert_true(guide.contains("printable/PLATE-1.step"))
  assert_true(guide.contains("## 2. Buy these parts"))
  assert_true(guide.contains("SCREW-M3x12"))
  assert_true(guide.contains("## 3. Assemble it"))
  assert_true(guide.contains("Assembly and test procedure"))
  assert_true(guide.contains("Fastener torque table"))
}

///|
test "start-here guide embeds a visual overview gallery" {
  let root = build_test_component()
  let guide = root.start_here_text(name="demo")
  assert_true(guide.contains("## Visual overview"))
  for
    view in [
      "views/iso.png", "views/front.png", "views/left.png", "views/top.png", "views/exploded.png",
    ] {
    assert_true(guide.contains(view))
  }
  // Missing renders are hidden rather than shown as broken images.
  assert_true(guide.contains("onerror"))
}

///|
test "printable parts exclude purchased and include fabricated" {
  let root = build_test_component()
  let parts = root.printable_parts()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].part_number, "PLATE-1")
  // The standalone design carries the plate body in its own local frame.
  assert_eq(parts[0].design.nodes.length(), 1)
  assert_eq(parts[0].design.nodes[0].name, "plate_body")
}

///|
test "printable parts export standalone step files in the package" {
  let root = build_test_component()
  let files = root.build_package_files(name="demo")
  let names : Array[String] = []
  for file in files {
    names.push(file.path)
    if file.path == "printable/PLATE-1.step" {
      assert_true(file.content.contains("ISO-10303-21;"))
      assert_true(file.content.contains("CARTESIAN_POINT"))
    }
  }
  assert_true(names.contains("printable/PLATE-1.step"))
  assert_true(!names.contains("printable/MOTOR-1.step"))
  assert_true(!names.contains("printable/SENSOR-1.step"))
}

///|
test "fabrication predicate matches process names" {
  assert_true(
    @cad.is_fabricated_part(@cad.PartMeta::new("P", process="3D print")),
  )
  assert_true(@cad.is_fabricated_part(@cad.PartMeta::new("P", process="CNC")))
  assert_true(@cad.is_fabricated_part(@cad.PartMeta::new("P", process="cut")))
  assert_true(
    !@cad.is_fabricated_part(@cad.PartMeta::new("P", process="purchased")),
  )
  assert_true(!@cad.is_fabricated_part(@cad.PartMeta::new("P")))
}

///|
test "part numbers are sanitized for file names" {
  assert_eq(@cad.sanitize_part_number("PLATE 1/left"), "PLATE-1-left")
}

///|
test "build manifest handles an empty component" {
  let empty = @cad.Component::new("empty")
  let manifest = empty.build_manifest(name="empty")
  assert_true(manifest.contains("BOM lines | 0"))
  assert_true(manifest.contains("Hardware warnings | 0"))
}

///|
test "supplier links override BOM metadata through the tree" {
  let root = build_test_component()
  let links : Array[@cad.SupplierLink] = [
    @cad.SupplierLink::new(
      part_number="SCREW-M3x12",
      supplier="Amazon",
      supplier_url="https://example.com/screws",
      notes="screw kit",
      unit_cost_usd=0.1,
    ),
    @cad.SupplierLink::new(
      part_number="MOTOR-1",
      supplier="mjbots",
      supplier_url="https://example.com/motor",
    ),
  ]
  let linked = root.with_supplier_links(links)
  let bom = linked.bom()
  let mut saw_screw = false
  let mut saw_motor = false
  for line in bom.lines {
    if line.part_number == "SCREW-M3x12" {
      saw_screw = true
      assert_eq(line.supplier, "Amazon")
      assert_eq(line.supplier_url, "https://example.com/screws")
      assert_eq(line.notes, "screw kit")
      assert_true((line.unit_cost_usd - 0.1).abs() < 1.0e-9)
    }
    if line.part_number == "MOTOR-1" {
      saw_motor = true
      assert_eq(line.supplier, "mjbots")
      assert_eq(line.supplier_url, "https://example.com/motor")
    }
  }
  assert_true(saw_screw)
  assert_true(saw_motor)
}
