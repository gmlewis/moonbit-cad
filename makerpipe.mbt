///|
/// Maker Pipe-compatible components for the CAD/URDF component tree.
///
/// Every wrapper imports the exact STEP component from
/// `gmlewis/step/components/makerpipe`, so bodies, mate connectors, metadata,
/// and feature records come from the single source in this repository. No mate
/// is redefined here.

///|
/// makerpipe_part_meta builds the purchasing record for one Maker Pipe item.
fn makerpipe_part_meta(
  description : String,
  sku : String,
  material : String,
  process : String,
  unit_cost_usd : Double,
) -> PartMeta {
  let finish = if material.contains("steel") { "zinc-plated" } else { "" }
  PartMeta::new(
    sku,
    description~,
    supplier="Maker Pipe",
    supplier_url="https://makerpipe.com",
    material~,
    process~,
    finish~,
    unit_cost_usd~,
    notes="Maker Pipe-compatible nominal component; geometry and mates come from gmlewis/step/components/makerpipe",
  )
}

///|
/// connector_sku returns the SKU and unit price for a structural connector.
fn connector_sku(part : String, size : String) -> (String, Double) {
  let one = size == "1"
  match part {
    "tee" => if one { ("MP0030", 4.95) } else { ("MP0021", 3.74) }
    "elbow-90" => if one { ("MP0059", 8.79) } else { ("MP0023", 5.95) }
    "elbow-45" => if one { ("MP0078", 7.95) } else { ("MP0024", 5.45) }
    "elbow-135" => ("MP0031", 5.79)
    "straight-180" => if one { ("MP0058", 7.95) } else { ("MP0022", 5.45) }
    "four-way" => if one { ("MP0060", 10.95) } else { ("MP0025", 7.49) }
    "five-way" => if one { ("MP0061", 12.45) } else { ("MP0026", 8.49) }
    "coupling" => if one { ("MP0079", 7.95) } else { ("MP0062", 5.45) }
    "flange" => if one { ("MP0080", 5.95) } else { ("MP0052", 5.45) }
    "adj-hinge" => if one { ("MP0075", 9.49) } else { ("MP0027", 7.49) }
    "adj-180" => ("MP0068", 9.95)
    "adj-flange" => if one { ("MP0081", 9.49) } else { ("MP0048", 7.49) }
    "top-rail-tee" => ("MP0072", 5.99)
    other => ("MP-" + other, 0.0)
  }
}

///|
/// makerpipe_connector imports one structural Maker Pipe connector.
pub fn makerpipe_connector(
  part : String,
  size : String,
) -> Result[Component, String] {
  let (sku, cost) = connector_sku(part, size)
  let step_result = match part {
    "tee" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.tee(s)
    }
    "elbow-45" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.elbow_45(s)
    }
    "elbow-90" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.elbow_90(s)
    }
    "elbow-135" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.elbow_135(s)
    }
    "straight-180" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.straight_180(s)
    }
    "four-way" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.four_way(s)
    }
    "five-way" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.five_way(s)
    }
    "coupling" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.coupling(s)
    }
    "flange" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.flange(s)
    }
    "adj-hinge" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.adjustable_hinge(s, 30.0)
    }
    "adj-180" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.adjustable_180(s, 0.0, 45.0)
    }
    "adj-flange" => {
      let s = match @step_makerpipe.makerpipe_size(size) {
        Ok(s) => s
        Err(e) => return Err(e.message())
      }
      @step_makerpipe.adjustable_flange(s, 30.0)
    }
    "top-rail-tee" => @step_makerpipe.top_rail_tee()
    other => return Err("unknown Maker Pipe connector: " + other)
  }
  let step_comp = match step_result {
    Ok(c) => c
    Err(e) => return Err(e.message())
  }
  let meta = makerpipe_part_meta(
    step_comp.metadata().designation,
    sku,
    "zinc-plated steel",
    "purchased",
    cost,
  )
  Ok(
    Component::from_step_component(
      "makerpipe-\{part}-\{size}",
      step_comp,
      density=@urdf.Density::g_per_cm3(7.85),
      part=Some(meta),
    ),
  )
}

///|
/// accessory_info returns SKU, material, process, density, and unit price.
fn accessory_info(part : String) -> (String, String, String, Double, Double) {
  match part {
    "shim" => ("MP-SHIM", "nylon", "purchased", 1.14, 0.15)
    "pipe-shim" => ("MP-SHIM-TUBE", "nylon", "purchased", 1.14, 0.15)
    "end-cap" => ("MP-END-CAP", "plastic", "purchased", 1.05, 0.50)
    "foot" => ("MP-FOOT", "rubber (EPDM)", "purchased", 1.2, 0.99)
    "insert" => ("MP-INSERT", "zinc-plated steel", "purchased", 7.85, 0.99)
    "strap-1" => ("MP-STRAP-1", "zinc-plated steel", "purchased", 7.85, 0.49)
    "strap-2" => ("MP-STRAP-2", "zinc-plated steel", "purchased", 7.85, 0.49)
    "mounting-strap" =>
      ("MP-STRAP-MOUNT", "zinc-plated steel", "purchased", 7.85, 0.49)
    "cross-over" =>
      ("MP-CROSS-OVER", "zinc-plated steel", "purchased", 7.85, 4.95)
    "telescoping" =>
      ("MP-TELESCOPING", "glass-filled nylon", "purchased", 1.35, 10.95)
    "barrel-hinge" =>
      ("MP-BARREL-HINGE", "zinc-plated steel", "purchased", 7.85, 9.95)
    "printed-hinge" => ("MP-PRINTED-HINGE", "PETG", "3D printed", 1.27, 9.98)
    "clip" => ("MP-CLIP", "PETG", "3D printed", 1.27, 1.99)
    "friction-band" => ("MP-FRICTION-BAND", "elastomer", "purchased", 1.2, 0.08)
    other => ("MP-" + other, "unknown", "purchased", 1.0, 0.0)
  }
}

///|
/// makerpipe_accessory imports one Maker Pipe accessory.
pub fn makerpipe_accessory(
  part : String,
  trade : String,
) -> Result[Component, String] {
  let step_result = match part {
    "shim" => @step_makerpipe.adapter_shim("3/4", "1")
    "pipe-shim" => @step_makerpipe.pipe_tube_shim(25.0, 28.0)
    "end-cap" => @step_makerpipe.end_cap(trade)
    "foot" => @step_makerpipe.rubber_foot(trade)
    "insert" => @step_makerpipe.threaded_insert(trade, "1/4-20")
    "strap-1" => @step_makerpipe.one_hole_strap(trade)
    "strap-2" => @step_makerpipe.two_hole_strap(trade)
    "mounting-strap" => @step_makerpipe.mounting_strap(trade)
    "cross-over" => @step_makerpipe.cross_over_clamp(trade)
    "telescoping" => @step_makerpipe.telescoping_clamp()
    "barrel-hinge" => @step_makerpipe.barrel_hinge()
    "printed-hinge" => @step_makerpipe.printed_hinge(trade)
    "clip" => @step_makerpipe.pipe_clip(trade)
    "friction-band" => @step_makerpipe.friction_band(trade)
    other => return Err("unknown Maker Pipe accessory: " + other)
  }
  let step_comp = match step_result {
    Ok(c) => c
    Err(e) => return Err(e.message())
  }
  let (sku, material, process, density_g_cm3, cost) = accessory_info(part)
  let meta = makerpipe_part_meta(
    step_comp.metadata().designation,
    sku,
    material,
    process,
    cost,
  )
  Ok(
    Component::from_step_component(
      "makerpipe-\{part}-\{trade}",
      step_comp,
      density=@urdf.Density::g_per_cm3(density_g_cm3),
      part=Some(meta),
    ),
  )
}
