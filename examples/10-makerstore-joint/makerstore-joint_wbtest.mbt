///|
test "10-makerstore-joint assembly builds a valid robot" {
  let robot = build_example().to_robot()
  if robot.has_errors() {
    let mut msg = "makerstore-joint diagnostics:"
    for diagnostic in robot.diagnostics() {
      msg = msg + "\n  " + diagnostic.message()
    }
    fail(msg)
  }
  // The L plate plus the two stacked spacers are three linked parts.
  assert_eq(robot.links.length(), 3)
  assert_true(build_example().total_mass_kg() > 0.0)
}
