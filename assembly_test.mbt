///|
test "bom aggregates parts, fasteners, and internal children" {
  let body_part = @cad.PartMeta::new(
    "BODY-1",
    description="body",
    material="6061-T6",
    process="CNC",
    unit_cost_usd=2.0,
  )
  let child_part = @cad.PartMeta::new(
    "CHILD-1",
    description="child",
    unit_cost_usd=5.0,
  )
  let fastener_part = @cad.PartMeta::new(
    "SCREW-M3x10",
    description="screw",
    unit_cost_usd=0.5,
  )
  let motor_part = @cad.PartMeta::new(
    "MOTOR-1",
    description="motor",
    unit_cost_usd=10.0,
  )
  let rotor = @cad.Component::new("rotor").add_body(
    @cad.BodyPart::box_mm("rotor_body", 5.0, 5.0, 5.0),
  )
  let motor = @cad.Component::new("motor")
    .add_body(@cad.BodyPart::box_mm("motor_body", 20.0, 20.0, 20.0))
    .with_part(motor_part)
    .attach(
      "rotor_joint",
      parent_mate="origin",
      rotor,
      child_mate="origin",
      bom_external=false,
    )
  let external = @cad.Component::new("external").add_body(
    @cad.BodyPart::box_mm("external_body", 5.0, 5.0, 5.0).with_part(child_part),
  )
  let root = @cad.Component::new("root")
    .add_body(
      @cad.BodyPart::box_mm("root_body", 10.0, 10.0, 10.0).with_part(body_part),
    )
    .add_body(@cad.BodyPart::box_mm("plain_body", 5.0, 5.0, 5.0))
    .add_fastener(
      @cad.Fastener::new(
        "bolts",
        @cad.FastenerKind::Screw,
        thread="M3",
        length_mm=10.0,
        quantity=2,
        part=Some(fastener_part),
      ),
    )
    .attach("motor_mount", parent_mate="origin", motor, child_mate="origin")
    .attach(
      "external_mount",
      parent_mate="origin",
      external,
      child_mate="origin",
    )
  let bom = root.bom()
  assert_eq(bom.unassigned, 1)
  let mut body_qty = 0
  let mut child_qty = 0
  let mut screw_qty = 0
  let mut motor_qty = 0
  for line in bom.lines {
    match line.part_number {
      "BODY-1" => body_qty = line.quantity
      "CHILD-1" => child_qty = line.quantity
      "SCREW-M3x10" => screw_qty = line.quantity
      "MOTOR-1" => motor_qty = line.quantity
      _ => ()
    }
  }
  assert_eq(body_qty, 1)
  assert_eq(child_qty, 1)
  assert_eq(screw_qty, 2)
  assert_eq(motor_qty, 1)
  let csv = root.to_bom_csv()
  assert_true(csv.contains("part_number"))
  assert_true(csv.contains("BODY-1"))
  assert_true(csv.contains("UNASSIGNED"))
}

///|
test "assembly plan builds subassemblies before attach steps" {
  let bolt_part = @cad.PartMeta::new(
    "SCREW-M3x10",
    description="screw",
    unit_cost_usd=0.5,
  )
  let child = @cad.Component::new("child")
    .add_body(@cad.BodyPart::box_mm("child_body", 10.0, 10.0, 10.0))
    .add_fastener(
      @cad.Fastener::new(
        "child_bolts",
        @cad.FastenerKind::Screw,
        thread="M3",
        length_mm=10.0,
        engagement_mm=5.0,
        torque_nm=1.0,
        references=["child_body"],
        part=Some(bolt_part),
      ),
    )
    .add_fastener(
      @cad.Fastener::new(
        "mount_bolts",
        @cad.FastenerKind::Screw,
        thread="M4",
        length_mm=12.0,
        engagement_mm=6.0,
        torque_nm=2.0,
        references=["base", "child_mount"],
        part=Some(bolt_part),
      ),
    )
  let base = @cad.Component::new("base")
    .add_body(@cad.BodyPart::box_mm("base_body", 20.0, 20.0, 20.0))
    .add_fastener(
      @cad.Fastener::new(
        "base_bolts",
        @cad.FastenerKind::Screw,
        thread="M3",
        length_mm=8.0,
        engagement_mm=4.0,
        torque_nm=1.0,
        references=["base_body"],
        part=Some(bolt_part),
      ),
    )
    .attach("child_mount", parent_mate="origin", child, child_mate="origin")
  let steps = base.assembly_plan()
  assert_eq(steps.length(), 3)
  assert_eq(steps[0].title, "Install base_bolts")
  assert_eq(steps[1].title, "Install child_bolts")
  assert_eq(steps[1].component, "base/child")
  assert_eq(steps[2].title, "Attach child to base")
  let joint = match steps[2].joint {
    Some(name) => name
    None => ""
  }
  assert_eq(joint, "child_mount")
  assert_true(steps[2].fasteners.contains("mount_bolts"))
  let text = base.assembly_plan_text()
  assert_true(text.contains("Attach child to base"))
  assert_true(text.contains("2.5 mm hex key"))
}

///|
test "assembly checks flag hardware problems" {
  let comp = @cad.Component::new("bad")
    .add_body(@cad.BodyPart::box_mm("plain_body", 10.0, 10.0, 10.0))
    .add_fastener(
      @cad.Fastener::new(
        "short_bolt",
        @cad.FastenerKind::Screw,
        thread="M3",
        length_mm=8.0,
        engagement_mm=10.0,
        quantity=1,
        torque_nm=1.0,
        references=["plain_body"],
      ),
    )
    .add_port(@cad.Port::new("power", @cad.PortKind::Power))
    .add_port(@cad.Port::new("power", @cad.PortKind::Signal))
    .add_fit(
      @cad.Fit::new(
        "loose",
        @cad.FitClass::Clearance,
        nominal_mm=10.0,
        min_mm=4.0,
        max_mm=6.0,
      ),
    )
  let warnings = comp.assembly_checks()
  let has = fn(needle : String) -> Bool {
    warnings.fold(init=false, fn(acc, warning) {
      acc || warning.contains(needle)
    })
  }
  assert_true(has("engages"))
  assert_true(has("has no PartMeta"))
  assert_true(has("duplicate port name"))
  assert_true(has("is outside"))
}
