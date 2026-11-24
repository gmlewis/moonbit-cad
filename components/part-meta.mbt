///|
/// Part-metadata helpers shared by the component builders.

///|
/// A purchased, off-the-shelf item.
fn purchased_part(
  part_number : String,
  description : String,
  material : String,
  unit_cost_usd : Double,
  supplier_url~ : String = "",
  supplier~ : String = "generic",
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier~,
    supplier_url~,
    material~,
    process="purchased",
    unit_cost_usd~,
  )
}

///|
/// An in-house fabricated item.
fn fabricated_part(
  part_number : String,
  description : String,
  material : String,
  process : String,
  unit_cost_usd : Double,
  supplier_url~ : String = "",
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="in-house",
    supplier_url~,
    material~,
    process~,
    unit_cost_usd~,
  )
}
