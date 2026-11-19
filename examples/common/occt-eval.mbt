///|
/// Shared OCCT boolean evaluation and exploded-view helpers for the gearbox
/// examples (`01-motorized-wheel`, `03-hip-joint`, `04-knee-joint`).

///|
/// Unwraps a shared CLI/parser `Result`, aborting with a clean message on error.
pub fn[T] cli_or_abort(result : Result[T, String]) -> T {
  match result {
    Ok(value) => value
    Err(message) => abort("error: " + message)
  }
}

///|
/// Prefixes every body name so a multi-body purchased or printed part stays
/// identifiable and moves as one unit in the exploded view.
pub fn prefix_body_names(
  comp : @cad.Component,
  prefix : String,
) -> @cad.Component {
  let bodies = comp.bodies.map(fn(body) {
    let name = prefix + "_" + body.name
    { ..body, name, node: body.node.with_name(name), }
  })
  { ..comp, bodies, }
}

///|
/// True if a `SceneNode` shape tree contains an unevaluated CSG boolean or
/// edge modifier that should be evaluated by OCCT once up front.
fn shape_has_boolean(shape : @step_cad.Shape) -> Bool {
  match shape {
    @step_cad.Shape::Difference(_)
    | @step_cad.Shape::Union(_)
    | @step_cad.Shape::Fillet(_)
    | @step_cad.Shape::Chamfer(_) => true
    _ => false
  }
}

///|
/// Splits a comma-separated STEP argument list at top-level parentheses and outside strings.
fn split_step_top_args(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut depth = 0
  let mut in_str = false
  let mut start = 0
  let n = s.length()
  let mut i = 0
  while i < n {
    let ch = s.unsafe_get(i)
    if in_str {
      if ch == '\'' {
        if i + 1 < n && s.unsafe_get(i + 1) == '\'' {
          i += 2
          continue
        }
        in_str = false
      }
    } else if ch == '\'' {
      in_str = true
    } else if ch == '(' {
      depth += 1
    } else if ch == ')' {
      if depth > 0 {
        depth -= 1
      }
    } else if ch == ',' && depth == 0 {
      out.push(s.exact_view(start~, end=i).to_owned().trim().to_owned())
      start = i + 1
    }
    i += 1
  }
  out.push(s.exact_view(start~, end=n).to_owned().trim().to_owned())
  out
}

///|
/// Replaces STEP unknown logical `.U.` (outside strings, e.g. from SMLib
/// `B_SPLINE_*` entities) with `.F.` because `gmlewis/step/parse` only accepts
/// `.T.` and `.F.` for spline closed/self-intersect flags.
fn normalize_step_logical_unknown(s : String) -> String {
  if !s.contains(".U.") {
    return s
  }
  s
  .replace_all(old=",.U.,", new=",.F.,")
  .replace_all(old=",.U.,", new=",.F.,")
  .replace_all(old=",.U.)", new=",.F.)")
}

///|
/// Ensures `SHAPE_REPRESENTATION` and `ADVANCED_BREP_SHAPE_REPRESENTATION` use a
/// dedicated identity `AXIS2_PLACEMENT_3D` so `ImportedStep::transformed` never
/// resets a placement shared with `PLANE` or `CIRCLE` geometry.
fn isolate_rep_placements(text : String) -> String {
  let key = "=SHAPE_REPRESENTATION("
  let idx = match text.find(key) {
    Some(i) => i
    None => return text
  }
  let mut line_end = text.length()
  let tail = text.exact_view(start=idx, end=text.length())
  match tail.find(";") {
    Some(rel) => line_end = idx + rel + 1
    None => return text
  }
  let sr_line = text.exact_view(start=idx, end=line_end).to_owned()
  let lp = match sr_line.find(",(#") {
    Some(i) => i + 3
    None => return text
  }
  let mut rp = lp
  while rp < sr_line.length() &&
        sr_line.unsafe_get(rp) >= '0' &&
        sr_line.unsafe_get(rp) <= '9' {
    rp += 1
  }
  if rp == lp || rp >= sr_line.length() || sr_line.unsafe_get(rp) != ')' {
    return text
  }
  let rep_ax = sr_line.exact_view(start=lp, end=rp).to_owned()
  let mut max_id = 0
  let mut pos = 0
  while pos < text.length() {
    match text.exact_view(start=pos, end=text.length()).find("\n#") {
      None => break
      Some(rel) => {
        let mut q = pos + rel + 2
        let mut num = 0
        while q < text.length() &&
              text.unsafe_get(q) >= '0' &&
              text.unsafe_get(q) <= '9' {
          num = num * 10 + (text.unsafe_get(q).to_int() - '0'.to_int())
          q += 1
        }
        if num > max_id {
          max_id = num
        }
        pos = q
      }
    }
  }
  if max_id <= 0 {
    return text
  }
  let p_orig = max_id + 1
  let d_x = max_id + 2
  let d_z = max_id + 3
  let ax_id = max_id + 4
  let extra = "#\{p_orig}=CARTESIAN_POINT('',(0.0,0.0,0.0));\n#\{d_x}=DIRECTION('',(1.0,0.0,0.0));\n#\{d_z}=DIRECTION('',(0.0,0.0,1.0));\n#\{ax_id}=AXIS2_PLACEMENT_3D('',#\{p_orig},#\{d_z},#\{d_x});\n"
  let sb = StringBuilder()
  let mut seen_data = false
  let mut inserted = false
  for line in text.split("\n") {
    let s = line.to_owned()
    if s.trim() == "DATA;" {
      seen_data = true
    }
    if s.has_prefix("#") &&
      (
        s.contains("=SHAPE_REPRESENTATION(") ||
        s.contains("=ADVANCED_BREP_SHAPE_REPRESENTATION(")
      ) {
      let replaced = s
        .replace_all(old="(#\{rep_ax})", new="(#\{ax_id})")
        .replace_all(old=",#\{rep_ax})", new=",#\{ax_id})")
      sb.write_string(replaced)
    } else if seen_data && !inserted && s.trim() == "ENDSEC;" {
      inserted = true
      sb.write_string(extra)
      sb.write_string(s)
    } else {
      sb.write_string(s)
    }
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// Rewrites standalone 13-arg `B_SPLINE_SURFACE_WITH_KNOTS(...)` statements
/// written by OCCT/SMLib into standard ISO 10303-21 AP214 complex entity
/// instances so `ImportedStep::from_string` parses trimmed swept gear solids
/// cleanly.
fn normalize_bspline_surface_entities(raw_text : String) -> String {
  let text = normalize_step_logical_unknown(raw_text)
  if !text.contains("B_SPLINE_SURFACE_WITH_KNOTS(") {
    return text
  }
  let out = StringBuilder()
  let n = text.length()
  let mut pos = 0
  let needle = "B_SPLINE_SURFACE_WITH_KNOTS("
  while pos < n {
    let tail = text.exact_view(start=pos, end=n)
    match tail.find(needle) {
      None => {
        out.write_string(tail.to_owned())
        break
      }
      Some(rel) => {
        let idx = pos + rel
        let mut back = idx - 1
        while back >= pos &&
              (
                text.unsafe_get(back) == ' ' ||
                text.unsafe_get(back) == '\n' ||
                text.unsafe_get(back) == '\r'
              ) {
          back -= 1
        }
        if back < pos || text.unsafe_get(back) != '=' {
          out.write_string(
            text.exact_view(start=pos, end=idx + needle.length()).to_owned(),
          )
          pos = idx + needle.length()
          continue
        }
        let args_start = idx + needle.length()
        let mut depth = 1
        let mut in_str = false
        let mut p = args_start
        while p < n && depth > 0 {
          let ch = text.unsafe_get(p)
          if in_str {
            if ch == '\'' {
              if p + 1 < n && text.unsafe_get(p + 1) == '\'' {
                p += 2
                continue
              }
              in_str = false
            }
          } else if ch == '\'' {
            in_str = true
          } else if ch == '(' {
            depth += 1
          } else if ch == ')' {
            depth -= 1
          }
          p += 1
        }
        let args_end = p - 1
        let args_str = text
          .exact_view(start=args_start, end=args_end)
          .to_owned()
        let parts = split_step_top_args(args_str)
        out.write_string(text.exact_view(start=pos, end=idx).to_owned())
        if parts.length() == 13 {
          let s_args = [
            parts[1],
            parts[2],
            parts[3],
            parts[4],
            parts[5],
            parts[6],
            parts[7],
          ].join(",")
          let k_args = [parts[8], parts[9], parts[10], parts[11], parts[12]].join(
            ",",
          )
          out.write_string(
            "(\nBOUNDED_SURFACE()\nB_SPLINE_SURFACE(\{s_args})\nB_SPLINE_SURFACE_WITH_KNOTS(\{k_args})\nGEOMETRIC_REPRESENTATION_ITEM()\nREPRESENTATION_ITEM(\{parts[0]})\nSURFACE()\n)",
          )
        } else {
          out.write_string(
            text.exact_view(start=idx, end=args_end + 1).to_owned(),
          )
        }
        pos = args_end + 1
      }
    }
  }
  out.to_string()
}

///|
/// Minimal JSON string literal escaping for local file paths.
fn json_quote(s : String) -> String {
  let b = StringBuilder()
  b.write_char('"')
  for ch in s {
    if ch == '\\' {
      b.write_string("\\\\")
    } else if ch == '"' {
      b.write_string("\\\"")
    } else {
      b.write_char(ch)
    }
  }
  b.write_char('"')
  b.to_string()
}

///|
/// Extracts `(base_step, cut_step, cache_key, cutter_names)` when `node.shape`
/// is a `Difference` whose base is an `ImportedStep` or `SweptProfile`.
fn imported_diff_spec(
  node : @step_cad.SceneNode,
) -> (String, String, String, Array[String])? {
  let diff = match node.shape {
    @step_cad.Shape::Difference(d) =>
      match d.base.shape {
        @step_cad.Shape::ImportedStep(_) | @step_cad.Shape::SweptProfile(_) => d
        _ => return None
      }
    _ => return None
  }
  if diff.cutters.is_empty() {
    return None
  }
  let base_design = @step_cad.Design::new(name="base").add(
    diff.base.with_name("base"),
  )
  let mut cut_design = @step_cad.Design::new(name="cut")
  let cutter_names : Array[String] = []
  for idx, cutter in diff.cutters {
    let cname = "cutter_\{idx}"
    cutter_names.push(cname)
    cut_design = cut_design.add(cutter.with_name(cname))
  }
  let base_step = base_design.to_step_file()
  let cut_step = cut_design.to_step_file()
  let cache_key = base_step + "\n---CUTTERS---\n" + cut_step
  Some((base_step, cut_step, cache_key, cutter_names))
}

///|
/// Evaluates one `ImportedStep`/`SweptProfile` difference from its nominal
/// `base_step` and `cut_step` using `solidcraft-cli` (with `DRAWEXE` fallback).
async fn run_imported_difference(
  source_name : String,
  base_step : String,
  cut_step : String,
  cutter_names : Array[String],
) -> @step_cad.ImportedStep? {
  let temp_dir = @fs.tmpdir(prefix="sc-imp-diff-") catch {
    err => {
      @cli.eprintln("eval_imported_difference tmpdir failed: \{err}")
      return None
    }
  }
  let base_path = temp_dir + "/base.step"
  let cut_path = temp_dir + "/cut.step"
  let out_path = temp_dir + "/out.step"
  let script_path = temp_dir + "/script.json"
  let tcl_path = temp_dir + "/script.tcl"
  @step_cad.write_text_file(base_step, Some(base_path))
  @step_cad.write_text_file(cut_step, Some(cut_path))
  let tools_json = cutter_names.map(json_quote).join(",")
  let script =
    $|[{"command":"file.insert_step","params":{"path":\{json_quote(base_path)}}},{"command":"file.insert_step","params":{"path":\{json_quote(cut_path)}}},{"command":"solid.combine","params":{"target":"base","tools":[\{tools_json}],"operation":"cut"}},{"command":"file.export_step","params":{"path":\{json_quote(out_path)},"bodies":["base"]}}]
  @step_cad.write_text_file(script, Some(script_path))
  let sc_res = Some(
    @process.collect_output_merged("solidcraft-cli", [
      "run", script_path, "--validation", "off", "--quiet",
    ]),
  ) catch {
    _ => None
  }
  let (code, proc_out) = match sc_res {
    Some((sc_code, sc_out)) if sc_code == 0 && @fs.exists(out_path) =>
      (sc_code, sc_out)
    _ => {
      let tcl = [
        "pload ALL",
        "testreadstep \"\{base_path}\" b",
        "testreadstep \"\{cut_path}\" c",
        "bcut r b c",
        "testwritestep \"\{out_path}\" r",
        "",
      ].join("\n")
      @step_cad.write_text_file(tcl, Some(tcl_path))
      @process.collect_output_merged("sh", [
        "-c",
        "DRAWEXE -b < \"\{tcl_path}\"",
      ]) catch {
        err => {
          @cli.eprintln("eval_imported_difference DRAWEXE spawn failed: \{err}")
          @fs.rmdir(temp_dir, recursive=true) catch {
            _ => ()
          }
          return None
        }
      }
    }
  }
  let res = if code == 0 && @fs.exists(out_path) {
    let raw_out = @fs.read_file(out_path).text() catch { _ => "" }
    let norm_out = raw_out.replace_all(old="\r\n", new="\n")
    let out_text = match
      (
        base_step.find("HEADER;"),
        base_step.find("ENDSEC;"),
        norm_out.find("HEADER;"),
        norm_out.find("ENDSEC;"),
      ) {
      (Some(bs), Some(be), Some(os), Some(oe)) if be > bs && oe > os => {
        let base_hdr = base_step.exact_view(start=bs, end=be + 7).to_owned()
        let prefix = norm_out.exact_view(start=0, end=os).to_owned()
        let suffix = norm_out
          .exact_view(start=oe + 7, end=norm_out.length())
          .to_owned()
        normalize_bspline_surface_entities(prefix + base_hdr + suffix)
        |> isolate_rep_placements
      }
      _ =>
        normalize_bspline_surface_entities(norm_out) |> isolate_rep_placements
    }
    if out_text != "" {
      match @step_cad.ImportedStep::from_string(out_text, source=source_name) {
        Ok(imported) => Some(imported)
        Err(e) => {
          @cli.eprintln(
            "eval_imported_difference parse failed for \{source_name}: \{e.message}",
          )
          None
        }
      }
    } else {
      @cli.eprintln(
        "eval_imported_difference empty out.step for \{source_name}",
      )
      None
    }
  } else {
    @cli.eprintln(
      "eval_imported_difference failed code=\{code} exists=\{@fs.exists(out_path)} out=\{proc_out.text()}",
    )
    None
  }
  @fs.rmdir(temp_dir, recursive=true) catch {
    _ => ()
  }
  res
}

///|
/// Evaluates a standard CSG boolean/edge node using `to_step_evaluated`.
async fn run_csg_difference(
  body_name : String,
  node : @step_cad.SceneNode,
) -> @step_cad.ImportedStep? {
  let design = @step_cad.Design::new(name=body_name).add(node)
  let evaluated = Some(design.to_step_evaluated()) catch { _ => None }
  match evaluated {
    Some(raw_text) => {
      let step_text = normalize_bspline_surface_entities(
          raw_text.replace_all(old="\r\n", new="\n"),
        )
        |> isolate_rep_placements
      match @step_cad.ImportedStep::from_string(step_text, source=body_name) {
        Ok(imported) => Some(imported)
        Err(e) => {
          @cli.eprintln(
            "run_csg_difference parse failed for \{body_name}: \{e.message}",
          )
          None
        }
      }
    }
    None => None
  }
}

///|
/// Collects all uncached boolean evaluations across `comp` into `tasks` so they
/// can execute concurrently before populating `cache`.
fn collect_boolean_tasks(
  comp : @cad.Component,
  cache : Map[String, @step_cad.ImportedStep],
  queued : Map[String, Bool],
  csg_results : Map[String, @step_cad.ImportedStep?],
  tasks : Array[async () -> (String, Bool, @step_cad.ImportedStep?)],
) -> Unit {
  for body in comp.bodies {
    if shape_has_boolean(body.node.shape) {
      match imported_diff_spec(body.node) {
        Some((base_step, cut_step, cache_key, cutter_names)) =>
          if !cache.contains(cache_key) && !queued.contains(cache_key) {
            queued.set(cache_key, true)
            let name = body.node.name
            tasks.push(async fn() {
              (
                cache_key,
                true,
                run_imported_difference(name, base_step, cut_step, cutter_names),
              )
            })
          }
        None => {
          let csg_key = comp.name + "::" + body.name
          if !csg_results.contains(csg_key) && !queued.contains(csg_key) {
            queued.set(csg_key, true)
            let node = body.node
            let bname = body.name
            tasks.push(async fn() {
              (csg_key, false, run_csg_difference(bname, node))
            })
          }
        }
      }
    }
  }
  for att in comp.attachments {
    collect_boolean_tasks(att.child, cache, queued, csg_results, tasks)
  }
}

///|
/// Rebuilds `comp` synchronously using already-evaluated `ImportedStep` caches.
fn apply_boolean_caches(
  comp : @cad.Component,
  cache : Map[String, @step_cad.ImportedStep],
  csg_results : Map[String, @step_cad.ImportedStep?],
) -> @cad.Component {
  let bodies : Array[@cad.BodyPart] = []
  for body in comp.bodies {
    if shape_has_boolean(body.node.shape) {
      match imported_diff_spec(body.node) {
        Some((_, _, cache_key, _)) =>
          match cache.get(cache_key) {
            Some(imported) => {
              let node = imported
                .as_shape()
                .with_name(body.node.name)
                .with_color(body.node.color)
                .rotate_x(body.node.rx)
                .rotate_y(body.node.ry)
                .rotate_z(body.node.rz)
                .translate(x=body.node.tx, y=body.node.ty, z=body.node.tz)
              bodies.push({ ..body, node, })
              continue
            }
            None => ()
          }
        None => {
          let csg_key = comp.name + "::" + body.name
          match csg_results.get(csg_key) {
            Some(Some(imported)) => {
              let node = imported
                .as_shape()
                .with_name(body.name)
                .with_color(body.node.color)
              bodies.push({ ..body, node, })
              continue
            }
            _ => ()
          }
        }
      }
    }
    bodies.push(body)
  }
  let attachments : Array[@cad.Attachment] = []
  for att in comp.attachments {
    attachments.push({
      ..att,
      child: apply_boolean_caches(att.child, cache, csg_results),
    })
  }
  { ..comp, bodies, attachments, }
}

///|
/// Evaluates all uncached boolean / edge-modified bodies of `comp` concurrently
/// using a shared cache for identical operands.
pub async fn eval_boolean_component_cached(
  comp : @cad.Component,
  cache : Map[String, @step_cad.ImportedStep],
) -> @cad.Component {
  let queued : Map[String, Bool] = Map([])
  let csg_results : Map[String, @step_cad.ImportedStep?] = Map([])
  let tasks : Array[async () -> (String, Bool, @step_cad.ImportedStep?)] = []
  collect_boolean_tasks(comp, cache, queued, csg_results, tasks)
  if !tasks.is_empty() {
    let completed = @async.all(tasks, max_concurrent=8)
    for item in completed {
      let (key, is_imp, res) = item
      if is_imp {
        match res {
          Some(imported) => cache.set(key, imported)
          None => ()
        }
      } else {
        csg_results.set(key, res)
      }
    }
  }
  apply_boolean_caches(comp, cache, csg_results)
}

///|
/// Evaluates only the boolean / edge-modified bodies of `comp` (recursing into
/// attached child components) once, keeping non-boolean swept/STEP bodies
/// untouched so `assembly.step`, `exploded.step`, `--posed-parts`, and
/// `printable/*.step` all share crisp trimmed B-Rep solids quickly.
pub async fn eval_boolean_component(comp : @cad.Component) -> @cad.Component {
  eval_boolean_component_cached(comp, Map([]))
}

///|
/// Radial unit vector of a node's position, for sliding radial-axis parts
/// (set screws) outward along their own insertion axis.
fn radial_offset(
  node : @step_cad.SceneNode,
  distance : Double,
) -> (Double, Double, Double) {
  let (x, y) = (node.tx, node.ty)
  let r = (x * x + y * y).sqrt()
  if r < 1.0e-6 {
    (distance, 0.0, 0.0)
  } else {
    (x / r * distance, y / r * distance, 0.0)
  }
}

///|
/// Display-only offset for the exploded, color-coded view of gearbox assemblies.
fn gearbox_explode_offset(
  node : @step_cad.SceneNode,
) -> (Double, Double, Double) {
  let name = node.name
  let (_, _, _, _, z0, z1) = node.bounding_box()
  let zc = (z0 + z1) / 2.0
  if name.contains("collar") || name.contains("shaft-collar") {
    return (0.0, 0.0, 515.0)
  }
  if name.contains("radial_insert") {
    let (rx, ry, _) = radial_offset(node, 18.0)
    return (rx, ry, 475.0)
  }
  if name.contains("output_hub_set_screw") {
    let (rx, ry, _) = radial_offset(node, 34.0)
    return (rx, ry, 475.0)
  }
  if name.contains("set_screw") || name.contains("set-screw") {
    let (rx, ry, _) = radial_offset(node, 24.0)
    let parent_z = if name.contains("stage2_coupler") {
      148.0
    } else if name.contains("stage2_carrier") {
      305.0
    } else if name.contains("stage1_carrier") {
      95.0
    } else {
      0.0
    }
    return (rx, ry, parent_z)
  }
  if name.contains("tire_bolt") {
    (0.0, 0.0, 655.0)
  } else if name.contains("tire_mount") || name.contains("tire-mount") {
    (0.0, 0.0, 545.0)
  } else if name.contains("tire") {
    (0.0, 0.0, 595.0)
  } else if name.contains("output_hub_insert") {
    (0.0, 0.0, 497.0)
  } else if name.contains("output_hub") {
    (0.0, 0.0, 475.0)
  } else if name.contains("output_cap_screw") || name.contains("ISO4762-M3-16") {
    (0.0, 0.0, 415.0)
  } else if name.contains("output_bearing_inner") {
    (0.0, 0.0, 360.0)
  } else if (
      name.contains("output_bearing") ||
      name.contains("deep-groove-bearing") ||
      name.contains("bearing-FR8")
    ) &&
    !name.contains("planet") {
    (0.0, 0.0, 442.0)
  } else if name.contains("output_cap") {
    (0.0, 0.0, 385.0)
  } else if name.contains("stage2_carrier") {
    (0.0, 0.0, 305.0)
  } else if name.contains("stage2_top_insert") {
    (0.0, 0.0, 227.0)
  } else if name.contains("stage2_joint_screw") {
    (0.0, 0.0, 165.0)
  } else if name.contains("stage2") &&
    (name.contains("bearing") || name.contains("bearing_flange")) {
    (0.0, 0.0, 242.0)
  } else if name.contains("stage2_coupler") {
    (0.0, 0.0, 148.0)
  } else if name.contains("stage2") {
    (0.0, 0.0, 195.0)
  } else if name.contains("stage1_carrier") {
    (0.0, 0.0, 95.0)
  } else if name.contains("stage1_sun_bolt") ||
    (name.contains("stage1_sun") && name.contains("ISO4762")) {
    (0.0, 0.0, 66.0)
  } else if name.contains("motor_cap_screw") {
    (0.0, 0.0, -28.0)
  } else if name.contains("stage1_top_insert") {
    (0.0, 0.0, 32.0)
  } else if name.contains("shroud_screw") {
    (0.0, 0.0, -405.0)
  } else if name.contains("moteus_shroud") {
    (0.0, 0.0, -375.0)
  } else if name.contains("shroud_insert") {
    (0.0, 0.0, -282.0)
  } else if name.contains("ISO4762-M3") {
    if zc < -48.0 {
      (0.0, 0.0, -405.0)
    } else if zc < 0.0 {
      (0.0, 0.0, -350.0)
    } else if zc < 15.0 {
      (0.0, 0.0, -28.0)
    } else {
      (0.0, 0.0, 165.0)
    }
  } else if name.contains("stage1") &&
    (name.contains("bearing") || name.contains("bearing_flange")) {
    (0.0, 0.0, 42.0)
  } else if name.contains("motor_stator_screw") {
    (0.0, 0.0, -295.0)
  } else if name.contains("moteus_screw") {
    (0.0, 0.0, -350.0)
  } else if name.contains("motor_housing_moteus_insert") {
    (0.0, 0.0, -282.0)
  } else if name.contains("motor_housing_top_insert") {
    (0.0, 0.0, -238.0)
  } else if name.contains("moteus") {
    (0.0, 0.0, -320.0)
  } else if name.contains("motor_housing") {
    (0.0, 0.0, -260.0)
  } else if (name.contains("rotor_adapter") && name.contains("screw")) ||
    name.contains("motor_rotor_ISO4762") {
    (0.0, 0.0, -48.0)
  } else if name.contains("rotor_adapter") {
    (0.0, 0.0, -78.0)
  } else if name.contains("_rotor_magnet") {
    (0.0, 0.0, -198.0)
  } else if name.contains("_motor_stator") {
    (0.0, 0.0, -170.0)
  } else if name.contains("_motor_rotor") || name.contains("_rotor") {
    (0.0, 0.0, -125.0)
  } else if name.contains("motor_cap") {
    (0.0, 0.0, -28.0)
  } else if name.contains("_motor") {
    (0.0, 0.0, -140.0)
  } else if name.contains("HEATSET") {
    if zc < -10.0 {
      (0.0, 0.0, -282.0)
    } else if zc < 10.0 {
      (0.0, 0.0, -238.0)
    } else if zc < 35.0 {
      (0.0, 0.0, 32.0)
    } else {
      (0.0, 0.0, 227.0)
    }
  } else {
    (0.0, 0.0, 0.0)
  }
}

///|
/// A distinct display color for each kind of part in the exploded view.
fn gearbox_explode_color(name : String) -> @step_cad.Rgb {
  if name.contains("tire_bolt") ||
    name.contains("screw") ||
    name.contains("sun_bolt") {
    @step_cad.Rgb::new(0.40, 0.75, 0.95)
  } else if name.contains("moteus_shroud") {
    @step_cad.Rgb::new(0.26, 0.30, 0.42)
  } else if name.contains("moteus") {
    @step_cad.Rgb::new(0.10, 0.60, 0.25)
  } else if name.contains("tire_mount") || name.contains("tire-mount") {
    @step_cad.Rgb::new(0.68, 0.42, 0.12)
  } else if name.contains("tire") {
    @step_cad.Rgb::new(0.08, 0.08, 0.08)
  } else if name.contains("motor_housing") {
    @step_cad.Rgb::new(0.20, 0.24, 0.34)
  } else if name.contains("rotor_adapter") || name.contains("coupler") {
    @step_cad.Rgb::new(0.88, 0.45, 0.14)
  } else if name.contains("_rotor_magnet") {
    @step_cad.Rgb::new(0.58, 0.22, 0.78)
  } else if name.contains("casing") || name.contains("_ring") {
    @step_cad.Rgb::new(0.12, 0.12, 0.14)
  } else if name.contains("motor_cap") {
    @step_cad.Rgb::new(0.22, 0.24, 0.30)
  } else if name.contains("output_cap") {
    @step_cad.Rgb::new(0.28, 0.30, 0.36)
  } else if name.contains("output_hub") {
    @step_cad.Rgb::new(0.95, 0.55, 0.15)
  } else if name.contains("collar") {
    @step_cad.Rgb::new(0.60, 0.02, 0.02)
  } else if name.contains("_sun") {
    @step_cad.Rgb::new(1.00, 0.68, 0.10)
  } else if name.contains("bearing") {
    @step_cad.Rgb::new(0.78, 0.78, 0.82)
  } else if name.contains("planet") {
    @step_cad.Rgb::new(0.15, 0.65, 0.95)
  } else if name.contains("carrier") {
    @step_cad.Rgb::new(0.20, 0.80, 0.40)
  } else if name.contains("insert") {
    @step_cad.Rgb::new(0.95, 0.75, 0.10)
  } else if name.contains("_motor_stator") && name.contains("coil") {
    @step_cad.Rgb::new(0.82, 0.42, 0.16)
  } else if name.contains("_motor") {
    @step_cad.Rgb::new(0.55, 0.55, 0.60)
  } else {
    @step_cad.Rgb::new(0.50, 0.50, 0.55)
  }
}

///|
/// A dashed trace from a part's assembled position to its exploded position.
fn trace_sticks(
  node : @step_cad.SceneNode,
  dx : Double,
  dy : Double,
  dz : Double,
) -> Array[@step_cad.SceneNode] {
  let len = (dx * dx + dy * dy + dz * dz).sqrt()
  let out : Array[@step_cad.SceneNode] = []
  if len < 8.0 {
    return out
  }
  let ux = dx / len
  let uy = dy / len
  let uz = dz / len
  let (x0, x1, y0, y1, z0, z1) = node.bounding_box()
  let cx = (x0 + x1) / 2.0
  let cy = (y0 + y1) / 2.0
  let cz = (z0 + z1) / 2.0
  let ry = @math.acos(uz) * 180.0 / @math.PI
  let rz = @math.atan2(uy, ux) * 180.0 / @math.PI
  let dash = 7.0
  let gap = 5.0
  let mut s = 4.0
  let mut i = 0
  while s + dash <= len - 4.0 {
    let sx = cx + ux * s
    let sy = cy + uy * s
    let sz = cz + uz * s
    let stick = @step_cad.Cylinder::new(0.7, dash)
      .with_name("trace_" + node.name + "_" + i.to_string())
      .with_color(@step_cad.Rgb::new(0.32, 0.32, 0.35))
      .rotate_y(ry)
      .rotate_z(rz)
      .translate(x=sx, y=sy, z=sz)
    out.push(stick)
    s = s + dash + gap
    i += 1
  }
  out
}

///|
/// Builds a display-only exploded design for any gearbox assembly.
pub fn gearbox_exploded_design(
  design : @step_cad.Design,
  name~ : String,
) -> @step_cad.Design {
  let mut out = @step_cad.Design::new(
    name~,
    description="Exploded, color-coded view",
  )
  for node in design.nodes() {
    let (dx, dy, dz) = gearbox_explode_offset(node)
    let skip_trace = node.name.contains("ball-") ||
      node.name.contains("inner-ring") ||
      node.name.contains("bearing_flange")
    if !skip_trace {
      for stick in trace_sticks(node, dx, dy, dz) {
        out = out.add(stick)
      }
    }
    out = out.add(
      node
      .with_color(gearbox_explode_color(node.name))
      .translate(x=dx, y=dy, z=dz),
    )
  }
  out
}
