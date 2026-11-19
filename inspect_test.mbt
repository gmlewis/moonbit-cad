///|
fn jfield(json : @json.Json, key : String) -> @json.Json {
  match json {
    @json.Json::Object(map) =>
      match map.get(key) {
        Some(value) => value
        None => abort("missing JSON field '" + key + "'")
      }
    _ => abort("expected a JSON object")
  }
}

///|
fn jnum(json : @json.Json) -> Double {
  match json {
    @json.Json::Number(value, ..) => value
    _ => abort("expected a JSON number")
  }
}

///|
fn jstr(json : @json.Json) -> String {
  match json {
    @json.Json::String(value) => value
    _ => abort("expected a JSON string")
  }
}

///|
fn jbool(json : @json.Json) -> Bool {
  match json {
    @json.Json::True => true
    @json.Json::False => false
    _ => abort("expected a JSON boolean")
  }
}

///|
fn jarr(json : @json.Json) -> Array[@json.Json] {
  match json {
    @json.Json::Array(values) => values
    _ => abort("expected a JSON array")
  }
}

///|
test "inspect json exposes the statics summary" {
  let json = @json.parse(analysis_arm(10.0).inspect_json())
  assert_eq(jstr(jfield(json, "name")), "base")
  assert_true((jnum(jfield(json, "total_mass_kg")) - 2.0).abs() < 1.0e-9)
  let com = jarr(jfield(json, "com_m"))
  assert_eq(com.length(), 3)
  assert_true((jnum(com[0]) - 0.5).abs() < 1.0e-9)
  assert_eq(jarr(jfield(json, "world_bbox_mm")).length(), 6)
  assert_true(jarr(jfield(json, "links")).length() > 0)
  let joints = jarr(jfield(json, "joints"))
  assert_eq(joints.length(), 1)
  assert_eq(jstr(jfield(joints[0], "name")), "arm_joint")
  assert_eq(jstr(jfield(joints[0], "type")), "revolute")
  let margins = jarr(jfield(json, "torque_margins"))
  assert_eq(margins.length(), 1)
  let tau = jnum(jfield(margins[0], "tau_static_nm"))
  assert_true((tau - 9.80665).abs() < 1.0e-4)
  assert_false(jbool(jfield(margins[0], "ok")))
  let interference = jfield(json, "interference_summary")
  assert_eq(jnum(jfield(interference, "collisions")), 0.0)
  let views = jarr(jfield(json, "views"))
  let has_iso = views.fold(init=false, fn(acc, view) {
    acc || view is @json.Json::String("iso")
  })
  assert_true(has_iso)
}

///|
test "inspect json lists printable parts with bed fit and mass" {
  let json = @json.parse(build_test_component().inspect_json())
  let parts = jarr(jfield(json, "printable_parts"))
  assert_eq(parts.length(), 1)
  let plate = parts[0]
  assert_eq(jstr(jfield(plate, "part_number")), "PLATE-1")
  assert_eq(jarr(jfield(plate, "bbox_mm")).length(), 3)
  assert_true(jbool(jfield(plate, "fits_bed")))
  assert_true(jnum(jfield(plate, "est_mass_g")) > 0.0)
  assert_true(jnum(jfield(jfield(json, "bom"), "lines")) > 0.0)
}
