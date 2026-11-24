///|
test "pattern_ring_mm and pattern_rect_mm produce exact coordinates" {
  let ring = @cad.pattern_ring_mm(4, diam_mm=40.0)
  assert_eq(ring.length(), 4)
  assert_true((ring[0].0 - 20.0).abs() < 1.0e-9)
  assert_true(ring[0].1.abs() < 1.0e-9)
  assert_true(ring[1].0.abs() < 1.0e-9)
  assert_true((ring[1].1 - 20.0).abs() < 1.0e-9)

  let rect = @cad.pattern_rect_mm(32.0, 32.0)
  assert_eq(rect.length(), 4)
  assert_true((rect[0].0 - 16.0).abs() < 1.0e-9)
  assert_true((rect[0].1 + 16.0).abs() < 1.0e-9)

  let grid = @cad.pattern_grid_mm(2, 3, 10.0, 20.0)
  assert_eq(grid.length(), 6)

  let line = @cad.pattern_line_mm(3, 15.0)
  assert_eq(line.length(), 3)
  assert_true((line[0].0 + 15.0).abs() < 1.0e-9)
  assert_true(line[1].0.abs() < 1.0e-9)
  assert_true((line[2].0 - 15.0).abs() < 1.0e-9)
}

///|
test "Component::attach_ring attaches N fasteners with mates and BOM" {
  let meta = @cad.PartMeta::new(
    "M3-INS",
    description="M3 heat-set insert",
    supplier="McMaster",
    unit_cost_usd=0.15,
  )
  let plate = @cad.Component::new("plate").add_body(
    @cad.BodyPart::cylinder_mm("plate_body", 50.0, 6.0),
  )
  let assembled = plate.attach_ring(
    "insert",
    count=4,
    diam_mm=38.0,
    fn(i) {
      @cad.Component::new("insert_\{i}")
      .add_body(@cad.BodyPart::cylinder_mm("brass_\{i}", 4.6, 5.7))
      .with_part(meta)
      .add_mate_mm_deg("mount", axis=(0.0, 0.0, -1.0))
    },
    z_mm=3.0,
    explode=@cad.ExplodeSpec::along_mate(distance_mm=15.0),
  )
  assert_eq(assembled.attachments.length(), 4)
  assert_true(assembled.get_mate("insert_mate_0") is Some(_))
  assert_true(assembled.get_mate("insert_mate_3") is Some(_))
  let bom = assembled.bom()
  let mut ins_qty : Int32 = 0
  for line in bom.lines {
    if line.part_number == "M3-INS" {
      ins_qty = line.quantity
    }
  }
  assert_eq(ins_qty, 4)
}

///|
test "Component::attach_rect mounts 4 standoffs cleanly" {
  let board = @cad.Component::new("motor_plate").add_body(
    @cad.BodyPart::box_mm("plate", 46.0, 46.0, 5.0),
  )
  let with_standoffs = board.attach_rect(
    "standoff",
    width_mm=32.0,
    height_mm=32.0,
    fn(i) {
      @cad.Component::new("standoff_\{i}")
      .add_body(@cad.BodyPart::cylinder_mm("hex_\{i}", 5.0, 10.0))
      .add_mate_mm_deg("mount", axis=(0.0, 0.0, -1.0))
    },
    z_mm=-2.5,
  )
  assert_eq(with_standoffs.attachments.length(), 4)
  let design = with_standoffs.to_design()
  assert_eq(design.nodes.length(), 5)
}
