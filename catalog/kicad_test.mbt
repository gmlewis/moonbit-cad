///|
fn kicad_test_csv() -> String {
  "Ref,Val,Package,PosX,PosY,Rot,Side\n" +
  "H1,MountingHole,MountingHole_2.7mm_M2.5,4.000,4.000,0,top\n" +
  "H2,MountingHole,MountingHole_2.7mm_M2.5,40.000,4.000,0,top\n" +
  "H3,MountingHole,MountingHole_2.7mm_M2.5,40.000,28.000,0,top\n" +
  "H4,MountingHole,MountingHole_2.7mm_M2.5,4.000,28.000,0,top\n" +
  "J1,power,Conn_01x02,10.000,20.000,0,top\n" +
  "J2,motor,Conn_01x04,34.000,20.000,0,top\n"
}

///|
test "parse kicad pos csv" {
  let footprints = @catalog.parse_kicad_pos(kicad_test_csv())
  assert_eq(footprints.length(), 6)
  assert_eq(footprints[0].reference, "H1")
  assert_true((footprints[0].x_mm - 4.0).abs() < 1.0e-9)
  assert_true(footprints[4].rotation_deg.abs() < 1.0e-9)
  assert_eq(footprints[4].side, "top")
}

///|
test "kicad pcb builder imports mounting holes and connectors" {
  let footprints = @catalog.parse_kicad_pos(kicad_test_csv())
  let comp = @catalog.pcb_from_kicad(
    name="ctrl",
    footprints~,
    board_len_mm=44.0,
    board_w_mm=32.0,
    origin_x_mm=22.0,
    origin_y_mm=16.0,
    mounting_hole_diam_mm=2.7,
  )
  assert_eq(comp.bodies.length(), 1)
  assert_true(comp.pcb is Some(_))
  let spec = comp.pcb.unwrap()
  assert_eq(spec.placements.length(), 2)
  assert_eq(spec.mounting_holes, 4)
  assert_eq(comp.ports.length(), 2)
  for i in 0..<4 {
    assert_true(comp.get_mate("bolt_" + i.to_string()) is Some(_))
  }
  assert_eq(comp.fasteners.length(), 1)
  let robot = comp.to_robot()
  assert_true(!robot.has_errors())
  let bom = comp.bom()
  assert_eq(bom.lines.length(), 2)
  let placements = comp.pcb_placements_csv()
  assert_true(placements.contains("\"power\""))
  assert_true(placements.contains("Conn_01x02"))
}

///|
test "kicad pcb auto-sizes from placements" {
  let footprints = @catalog.parse_kicad_pos(kicad_test_csv())
  let comp = @catalog.pcb_from_kicad(
    name="auto",
    footprints~,
    mounting_hole_match="MountingHole",
    board_margin_mm=5.0,
  )
  let spec = comp.pcb.unwrap()
  assert_true(spec.length_mm > 36.0)
  assert_true(spec.width_mm > 24.0)
  assert_eq(spec.mounting_holes, 4)
}
