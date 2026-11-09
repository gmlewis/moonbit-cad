///|
fn check_component(comp : @cad.Component, mates : Array[String]) -> Unit raise {
  let mass = comp.total_mass_kg()
  if mass <= 0.0 {
    fail("expected positive mass for " + comp.name)
  }
  let robot = comp.to_robot()
  if robot.has_errors() {
    let mut msg = "diagnostics for " + comp.name + ":"
    for d in robot.diagnostics() {
      msg = msg + "\n  " + d.message()
    }
    fail(msg)
  }
  let step = comp.to_step_file()
  if !step.contains("ISO-10303-21;") {
    fail("missing STEP header for " + comp.name)
  }
  for mate in mates {
    if comp.get_mate(mate) is None {
      fail("missing mate " + mate + " on " + comp.name)
    }
  }
}

///|
test "hex standoff" {
  let comp = @catalog.hex_standoff()
  check_component(comp, ["bottom", "top", "origin"])
  assert_true(comp.total_mass_kg() > 0.0)
}

///|
test "cylindrical spacer" {
  let comp = @catalog.cylindrical_spacer()
  check_component(comp, ["bottom", "top"])
}

///|
test "ball bearing" {
  let comp = @catalog.ball_bearing()
  check_component(comp, ["center", "bottom", "top"])
  assert_eq(comp.bodies.length(), 3)
}

///|
test "shaft coupler" {
  let comp = @catalog.shaft_coupler()
  check_component(comp, ["input_shaft", "output_shaft"])
  assert_eq(comp.bodies.length(), 2)
}

///|
test "flange plate" {
  let comp = @catalog.flange_plate()
  check_component(comp, [
    "bottom", "top", "bolt_0", "bolt_1", "bolt_2", "bolt_3",
  ])
  let bolt = comp.get_mate("bolt_0").unwrap()
  assert_true((bolt.origin.xyz.0 - 0.022).abs() < 1.0e-9)
}

///|
test "l bracket" {
  let comp = @catalog.l_bracket()
  check_component(comp, ["base_mount", "wall_mount"])
  assert_eq(comp.bodies.length(), 2)
}

///|
test "u bracket" {
  let comp = @catalog.u_bracket()
  check_component(comp, ["base_mount", "pivot"])
  assert_eq(comp.bodies.length(), 3)
  let pivot = comp.get_mate("pivot").unwrap()
  assert_true((pivot.axis.0 - 1.0).abs() < 1.0e-12)
}

///|
test "fastener catalog parts are buildable and priced" {
  let screw = @catalog.socket_head_screw()
  check_component(screw, ["seat", "head"])
  let nut = @catalog.hex_nut()
  check_component(nut, ["seat", "top"])
  let washer = @catalog.washer()
  check_component(washer, ["seat", "top"])
  let insert = @catalog.heat_set_insert()
  check_component(insert, ["seat", "top"])
  assert_true(
    match screw.part {
      Some(_) => true
      None => false
    },
  )
}
