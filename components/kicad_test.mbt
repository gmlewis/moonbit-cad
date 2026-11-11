///|
test "parse a KiCad position CSV" {
  let csv = "Ref,Val,Package,PosX,PosY,Rot,Side\n" +
    "C1,10u,C_0603,10.0,20.0,90.0,top\n" +
    "J1,Power,Conn_01x02,5.0,5.0,0.0,top\n"
  let footprints = @components.parse_kicad_pos(csv)
  assert_eq(footprints.length(), 2)
  assert_eq(footprints[0].reference, "C1")
}

///|
test "PCB from KiCad placements builds a board with ports" {
  let footprints = @components.parse_kicad_pos(
    "Ref,Val,Package,PosX,PosY,Rot,Side\n" +
    "H1,MountingHole,MountingHole,0.0,0.0,0.0,top\n" +
    "H2,MountingHole,MountingHole,30.0,0.0,0.0,top\n" +
    "H3,MountingHole,MountingHole,30.0,20.0,0.0,top\n" +
    "H4,MountingHole,MountingHole,0.0,20.0,0.0,top\n" +
    "J1,Power,Conn_01x02,10.0,5.0,0.0,top\n",
  )
  let pcb = @components.pcb_from_kicad(name="kicad_board", footprints~)
  assert_true(pcb.pcb is Some(_))
  assert_true(!pcb.to_robot().has_errors())
  assert_true(pcb.ports.length() >= 1)
}
