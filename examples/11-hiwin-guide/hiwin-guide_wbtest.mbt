///|
test "11-hiwin-guide builds a rail and carriage robot" {
  let robot = build_example().to_robot()
  assert_true(!robot.has_errors())
  assert_eq(robot.links.length(), 2)
  assert_eq(robot.joints.length(), 1)
}
