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
  let printable_count = flange.printable_parts().length() +
    l.printable_parts().length() +
    u.printable_parts().length()
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
    detailed.to_design().nodes.length() >= simplified.to_design().nodes.length(),
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
  let collar = @components.shaft_collar()
  assert_true(collar.part is Some(_))
  let bearing = @components.deep_groove_bearing_part(
    detail=@step_common.DetailLevel::Detailed,
  )
  let design = bearing.to_design()
  let gltf = @cad.gltf_safe_design(design).to_gltf()
  assert_true(gltf.contains("\"2.0\""))
  assert_true(bearing.to_step_file().contains("ISO-10303-21;"))
}

///|
/// Converts a Tier-1 STEP component and checks STEP + glTF validity.
fn check_step_and_gltf(
  name : String,
  step_comp : @step_common.Component,
) -> Unit raise {
  let comp = @cad.Component::from_step_component(name, step_comp)
  assert_true(comp.to_step_file().contains("ISO-10303-21;"))
  let gltf = @cad.gltf_safe_design(comp.to_design()).to_gltf()
  assert_true(gltf.contains("\"2.0\""))
}

///|
test "Tier-1 primitives export STEP and glTF at every detail level" {
  let size = @step_motion.bearing_size("608").unwrap()
  let frame = @step_motors.nema_frame("NEMA17").unwrap()
  let levels : Array[@step_common.DetailLevel] = [
    @step_common.DetailLevel::Simplified,
    @step_common.DetailLevel::Detailed,
    @step_common.DetailLevel::FullyModeled,
  ]
  for level in levels {
    check_step_and_gltf(
      "deep-groove",
      @step_motion.deep_groove_bearing(size, detail=level).unwrap(),
    )
    check_step_and_gltf(
      "shielded",
      @step_motion.shielded_bearing(size, detail=level).unwrap(),
    )
    check_step_and_gltf(
      "nema",
      @step_motors.nema_stepper_motor(frame, 40.0, detail=level).unwrap(),
    )
    check_step_and_gltf(
      "vslot",
      @step_profiles.vslot_extrusion(
        @step_profiles.VSlotProfile::vslot_2020(),
        200.0,
        detail=level,
      ).unwrap(),
    )
    check_step_and_gltf(
      "tnut",
      @step_fasteners.extrusion_tnut(
        @step_fasteners.extrusion_tnut_spec("M5").unwrap(),
        detail=level,
      ).unwrap(),
    )
    check_step_and_gltf(
      "counterbores",
      @step_stock.plate_with_counterbores(60.0, 40.0, 6.0, holes=[
        {
          x_mm: 15.0,
          y_mm: 10.0,
          through_diameter_mm: 4.2,
          counterbore_diameter_mm: 8.0,
          counterbore_depth_mm: 3.0,
        },
        {
          x_mm: -15.0,
          y_mm: 10.0,
          through_diameter_mm: 4.2,
          counterbore_diameter_mm: 8.0,
          counterbore_depth_mm: 3.0,
        },
      ]).unwrap(),
    )
    check_step_and_gltf(
      "insert",
      @step_fasteners.heat_set_insert_m3("short").unwrap(),
    )
  }
}

///|
test "swept gear STEP keeps B-spline surfaces while glTF proxies them" {
  let params = @step_planetary.HerringbonePlanetaryParams::new(
    module_mm=1.5,
    gear_length_mm=8.0,
    num_elbows=4,
    sun_teeth=12,
    planet_teeth=12,
    planet_count=3,
  ).unwrap()
  let gearbox = @step_planetary.herringbone_planetary_gearbox(params).unwrap()
  let sun = @cad.Component::from_step_layer("sun", gearbox, "sun")
  let step = sun.to_step_file()
  assert_true(step.contains("B_SPLINE"))
  let mut saw_swept = false
  for node in sun.to_design().nodes {
    if node.shape is @step_cad.Shape::SweptProfile(_) {
      saw_swept = true
      let safe_shape = @cad.gltf_safe_node(node).shape
      assert_true(
        safe_shape
        is (@step_cad.Shape::Cylinder(_) | @step_cad.Shape::ExtrudedProfile(_)),
      )
    }
  }
  assert_true(saw_swept)
}

///|
test "planetary gearbox is a valid robot in both smooth and swept modes" {
  for smooth in [true, false] {
    let gearbox = @components.planetary_gearbox(
      smooth~,
      detail=@step_common.DetailLevel::Detailed,
    )
    let robot = gearbox.to_robot()
    if robot.has_errors() {
      let mut msg = "gearbox diagnostics:"
      for diagnostic in robot.diagnostics() {
        msg = msg + "\n  " + diagnostic.message()
      }
      fail(msg)
    }
    assert_true(gearbox.total_mass_kg() > 0.0)
  }
}
