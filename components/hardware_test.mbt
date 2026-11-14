///|
/// Shared assertion: the component compiles and exposes the required mates.
fn check_component(comp : @cad.Component, mates : Array[String]) -> Unit raise {
  let robot = comp.to_robot()
  if robot.has_errors() {
    let mut msg = "diagnostics for " + comp.name + ":"
    for diagnostic in robot.diagnostics() {
      msg = msg + "\n  " + diagnostic.message()
    }
    fail(msg)
  }
  for mate in mates {
    if comp.get_mate(mate) is None {
      fail("missing mate " + mate + " on " + comp.name)
    }
  }
}

///|
test "ISO socket head cap screw has a seat and tip" {
  let screw = @components.iso_shcs_screw(
    size=@step_standards.M3,
    length_mm=12.0,
  )
  check_component(screw, ["head_seat", "tip", "head_top"])
  assert_true(screw.total_mass_kg() > 0.0)
  assert_true(screw.part is Some(_))
  let mut has_shank = false
  let mut has_head = false
  for node in screw.to_design().nodes {
    let (_, _, _, _, z0, z1) = node.bounding_box()
    if z0 < -1.0 {
      has_shank = true
    }
    if z1 > 0.0 {
      has_head = true
    }
  }
  assert_true(has_shank)
  assert_true(has_head)
}

///|
test "ISO hex bolt, nut, washer, and stud build" {
  let bolt = @components.iso_hex_bolt(size=@step_standards.M6, length_mm=25.0)
  check_component(bolt, ["head_seat", "tip", "head_top"])
  let nut = @components.iso_hex_nut(size=@step_standards.M3)
  check_component(nut, ["bottom", "top"])
  let washer = @components.iso_flat_washer(size=@step_standards.M3)
  check_component(washer, ["bottom", "top"])
  let stud = @components.din976_stud(size=@step_standards.M3, length_mm=30.0)
  check_component(stud, ["bottom", "top"])
  assert_true(bolt.total_mass_kg() > 0.0)
  assert_true(nut.total_mass_kg() > 0.0)
  assert_true(washer.total_mass_kg() > 0.0)
  assert_true(stud.total_mass_kg() > 0.0)
}

///|
test "motion parts build with mates" {
  let standoff = @components.hex_standoff(length_mm=20.0)
  check_component(standoff, ["bottom", "top"])
  let spacer = @components.cylindrical_spacer()
  check_component(spacer, ["bottom", "top"])
  let bushing = @components.sleeve_bushing()
  check_component(bushing, ["bottom", "top", "bore"])
  let bearing = @components.ball_bearing(designation="608")
  check_component(bearing, ["center", "bottom", "top"])
  let spring = @components.compression_spring_part()
  check_component(spring, ["bottom", "top"])
}

///|
test "T-slot strut and frame build" {
  let strut = @components.tslot_extrusion_strut(name="rail", length_mm=200.0)
  check_component(strut, ["start", "end", "side_px", "side_nx"])
  let frame = @components.tslot_frame(
    width_mm=300.0,
    depth_mm=200.0,
    height_mm=200.0,
  )
  check_component(frame, [])
  assert_true(frame.bodies.length() > 0)
}

///|
test "structural brackets are printable and build" {
  let flange = @components.flange_plate()
  check_component(flange, ["bottom", "top"])
  let l = @components.l_bracket()
  check_component(l, ["base_mount", "base_top", "wall_mount"])
  let u = @components.u_bracket()
  check_component(u, ["base_mount", "pivot"])
  let coupler = @components.shaft_coupler()
  check_component(coupler, ["input_shaft", "output_shaft"])
  let mut printable_count = 0
  for part in flange.printable_parts() {
    let _ = part
    printable_count = printable_count + 1
  }
  for part in l.printable_parts() {
    let _ = part
    printable_count = printable_count + 1
  }
  for part in u.printable_parts() {
    let _ = part
    printable_count = printable_count + 1
  }
  assert_true(printable_count >= 3)
}

///|
test "detail levels build and rich detail adds geometry" {
  let simplified = @components.nema_stepper(
    detail=@step_common.DetailLevel::Simplified,
  )
  let detailed = @components.nema_stepper(
    detail=@step_common.DetailLevel::Detailed,
  )
  let full = @components.nema_stepper(
    detail=@step_common.DetailLevel::FullyModeled,
  )
  assert_eq(simplified.compile_links().0.length(), 2)
  assert_eq(detailed.compile_links().0.length(), 2)
  assert_true(
    detailed.to_design().nodes.length() > simplified.to_design().nodes.length(),
  )
  assert_true(
    full.to_design().nodes.length() >= detailed.to_design().nodes.length(),
  )
  assert_true(
    detailed.to_step_file().length() > simplified.to_step_file().length(),
  )
}

///|
test "threads override is accepted by threaded hardware" {
  let cosmetic = @components.iso_shcs_screw(
    size=@step_standards.M3,
    length_mm=10.0,
    threads=@step_common.ThreadRepresentation::Cosmetic,
  )
  let helical = @components.iso_shcs_screw(
    size=@step_standards.M3,
    length_mm=10.0,
    detail=@step_common.DetailLevel::FullyModeled,
    threads=@step_common.ThreadRepresentation::Helical,
  )
  assert_true(cosmetic.total_mass_kg() > 0.0)
  assert_true(helical.total_mass_kg() > 0.0)
  assert_true(
    helical.to_step_file().length() > cosmetic.to_step_file().length(),
  )
}

///|
test "Tier-1 stock and motion wrappers build" {
  let vslot = @components.vslot_extrusion_strut(name="rail", length_mm=240.0)
  check_component(vslot, ["start", "end"])
  assert_true(vslot.total_mass_kg() > 0.0)
  let tnut = @components.extrusion_tnut_part(thread="M5")
  check_component(tnut, ["seat", "thread"])
  assert_true(tnut.total_mass_kg() > 0.0)
  let collar = @components.shaft_collar()
  check_component(collar, ["bore"])
  assert_true(collar.total_mass_kg() > 0.0)
  let block = @components.flanged_bearing_block()
  check_component(block, ["mount", "bore"])
  assert_true(block.total_mass_kg() > 0.0)
  let pulley = @components.gt2_pulley_part()
  check_component(pulley, ["bore", "top"])
  assert_true(pulley.total_mass_kg() > 0.0)
  let shaft = @components.stepped_shaft_part()
  check_component(shaft, ["input", "output"])
  assert_true(shaft.total_mass_kg() > 0.0)
  let key = @components.key_part()
  check_component(key, ["center"])
  assert_true(key.total_mass_kg() > 0.0)
}

///|
test "Tier-1 stock plates and brackets build" {
  let plate = @components.stock_plate_part()
  check_component(plate, ["top", "bottom"])
  assert_true(plate.total_mass_kg() > 0.0)
  let bearing_plate = @components.bearing_plate_part()
  check_component(bearing_plate, ["top", "bottom", "bearing_bore"])
  assert_true(bearing_plate.total_mass_kg() > 0.0)
  let angle = @components.angle_bar_part()
  check_component(angle, ["start", "end"])
  assert_true(angle.total_mass_kg() > 0.0)
  let corner = @components.vslot_corner_bracket_part()
  check_component(corner, ["mount_a", "mount_b"])
  assert_true(corner.total_mass_kg() > 0.0)
  let joining = @components.vslot_joining_plate_part()
  check_component(joining, ["top", "bottom"])
  assert_true(joining.total_mass_kg() > 0.0)
  let coupling = @components.rigid_coupling_part()
  check_component(coupling, ["input_shaft", "output_shaft"])
  assert_true(coupling.total_mass_kg() > 0.0)
  let bearing = @components.deep_groove_bearing_part()
  check_component(bearing, ["center", "bottom", "top", "bore"])
  assert_true(bearing.total_mass_kg() > 0.0)
  let nema_plate = @components.nema_mount_plate_part()
  check_component(nema_plate, ["top", "bottom"])
  assert_true(nema_plate.total_mass_kg() > 0.0)
}

///|
test "detailed hardware wrappers are printable and glTF safe" {
  let collar = @components.shaft_collar(
    detail=@step_common.DetailLevel::Detailed,
  )
  assert_true(collar.part is Some(_))
  let bearing = @components.deep_groove_bearing_part(
    detail=@step_common.DetailLevel::Detailed,
  )
  let design = bearing.to_design()
  let gltf = @cad.gltf_safe_design(design).to_gltf()
  assert_true(gltf.contains("\"2.0\""))
  assert_true(bearing.to_step_file().contains("ISO-10303-21;"))
}
