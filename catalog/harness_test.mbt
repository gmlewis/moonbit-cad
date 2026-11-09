///|
test "cable route builder creates jacket segments and a part" {
  let comp = @catalog.cable_route(
    points=[(0.0, 0.0, 0.0), (50.0, 0.0, 0.0), (50.0, 0.0, 40.0)],
    jacket_diameter_mm=6.0,
    wire_names=["power"],
    material="PVC",
  )
  assert_eq(comp.bodies.length(), 2)
  assert_true(comp.part is Some(_))
  assert_eq(comp.cables.length(), 1)
  assert_true((comp.cables[0].length_mm() - 90.0).abs() < 1.0e-9)
  let robot = comp.to_robot()
  assert_true(!robot.has_errors())
  let bom = comp.bom()
  assert_eq(bom.lines.length(), 1)
}
