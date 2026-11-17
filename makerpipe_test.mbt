///|
test "Maker Pipe connector wrapper keeps STEP bodies and mates" {
  let comp = match @cad.makerpipe_connector("tee", "3/4") {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(comp.bodies.length(), 2)
  assert_true(comp.mates.contains("branch-1"))
  assert_true(comp.mates.contains("mouth-1"))
  assert_true(comp.mates.contains("run-a"))
  let part = match comp.part {
    Some(p) => p
    None => abort("missing Maker Pipe part metadata")
  }
  assert_eq(part.supplier, "Maker Pipe")
  assert_eq(part.part_number, "MP0021")
  assert_eq(part.material, "zinc-plated steel")
  assert_true(part.finish == "zinc-plated")
}

///|
test "Maker Pipe accessory wrapper carries material and process metadata" {
  let foot = match @cad.makerpipe_accessory("foot", "3/4") {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(foot.bodies.length(), 2)
  assert_true(foot.mates.contains("pipe-seat"))
  let foot_part = match foot.part {
    Some(p) => p
    None => abort("missing foot part metadata")
  }
  assert_eq(foot_part.material, "rubber (EPDM)")
  let hinge = match @cad.makerpipe_accessory("printed-hinge", "3/4") {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(hinge.bodies.length(), 5)
  assert_true(hinge.mates.contains("hinge-axis"))
  let hinge_part = match hinge.part {
    Some(p) => p
    None => abort("missing printed-hinge part metadata")
  }
  assert_eq(hinge_part.process, "3D printed")
}

///|
test "Maker Pipe wrapper rejects unknown parts" {
  assert_true(@cad.makerpipe_connector("nope", "3/4") is Err(_))
  assert_true(@cad.makerpipe_accessory("nope", "3/4") is Err(_))
}
