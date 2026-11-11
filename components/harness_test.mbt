///|
test "cable route builds jacket segments with a length-based part" {
  let route = @components.cable_route(
    points=[(0.0, 0.0, 0.0), (100.0, 0.0, 0.0), (100.0, 50.0, 0.0)],
    jacket_diameter_mm=6.0,
    wire_names=["power"],
  )
  assert_true(route.total_mass_kg() > 0.0)
  assert_eq(route.cables.length(), 1)
  assert_true(route.part is Some(_))
  assert_true(!route.to_robot().has_errors())
}
