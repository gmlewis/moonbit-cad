///|
/// Shared CLI and purchasing-file parsers.
///
/// These helpers are deliberately independent of any one example. The
/// comma-separated list parsers are the standard way to give a per-stage or
/// per-part value to a component: the first item applies to the first stage
/// (or part), the second to the second, and a shorter list repeats its last
/// value. A single value therefore applies to every stage.

///|
/// Extends a parsed list to `count` items by repeating its last value.
fn[T] extend_repeating_last(values : Array[T], count : Int32) -> Array[T] {
  let out : Array[T] = []
  for i in 0..<count {
    let index = if i < values.length() { i } else { values.length() - 1 }
    out.push(values[index])
  }
  out
}

///|
/// Parses a comma-separated double list and extends it to `count` entries by
/// repeating the last value.
///
/// Returns `Err` for an empty list or a malformed number. `label` is the CLI
/// option name without the leading `--` (for example `"module"`).
pub fn parse_double_list(
  text : String,
  count : Int32,
  label : String,
) -> Result[Array[Double], String] {
  let values : Array[Double] = []
  for raw in text.split(",") {
    let item = raw.trim().to_owned()
    if item == "" {
      continue
    }
    let value = @string.parse_double(item) catch {
      _ =>
        return Err(
          "--" + label + " expects comma-separated numbers; got '" + item + "'",
        )
    }
    values.push(value)
  }
  if values.length() == 0 {
    return Err("--" + label + " needs at least one value")
  }
  Ok(extend_repeating_last(values, count))
}

///|
/// Parses a comma-separated integer list and extends it to `count` entries by
/// repeating the last value.
pub fn parse_int_list(
  text : String,
  count : Int32,
  label : String,
) -> Result[Array[Int32], String] {
  let values : Array[Int32] = []
  for raw in text.split(",") {
    let item = raw.trim().to_owned()
    if item == "" {
      continue
    }
    let value = @string.parse_int(item) catch {
      _ =>
        return Err(
          "--" + label + " expects comma-separated integers; got '" + item + "'",
        )
    }
    values.push(value)
  }
  if values.length() == 0 {
    return Err("--" + label + " needs at least one value")
  }
  Ok(extend_repeating_last(values, count))
}

///|
/// Parses a comma-separated string list and extends it to `count` entries by
/// repeating the last value.
pub fn parse_string_list(
  text : String,
  count : Int32,
  label : String,
) -> Result[Array[String], String] {
  let values : Array[String] = []
  for raw in text.split(",") {
    let item = raw.trim().to_owned()
    if item == "" {
      continue
    }
    values.push(item)
  }
  if values.length() == 0 {
    return Err("--" + label + " needs at least one value")
  }
  Ok(extend_repeating_last(values, count))
}

///|
/// Parses a pipe-separated supplier-link file.
///
/// Format: `part_number | supplier | supplier_url | notes | unit_cost_usd`.
/// Blank lines and lines starting with `#` are ignored, as are lines with
/// fewer than three fields. An unparsable cost becomes `None`.
pub fn parse_supplier_links(text : String) -> Array[SupplierLink] {
  let out : Array[SupplierLink] = []
  for raw_line in text.split("\n") {
    let line = raw_line.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    let fields : Array[String] = line
      .split("|")
      .collect()
      .map(fn(field) { field.trim().to_owned() })
    if fields.length() < 3 {
      continue
    }
    let cost : Double? = if fields.length() > 4 && fields[4] != "" {
      Some(@string.parse_double(fields[4])) catch {
        _ => None
      }
    } else {
      None
    }
    out.push(
      SupplierLink::new(
        part_number=fields[0],
        supplier=if fields.length() > 1 { fields[1] } else { "" },
        supplier_url=if fields.length() > 2 { fields[2] } else { "" },
        notes=if fields.length() > 3 { fields[3] } else { "" },
        unit_cost_usd?=cost,
      ),
    )
  }
  out
}

///|
/// Merges shared supplier-link defaults with per-example overrides.
///
/// An override wins for every non-empty field (and for a present cost); an
/// empty field keeps the default. Overrides for part numbers missing from the
/// defaults are appended, so examples can introduce example-specific parts.
pub fn merge_supplier_links(
  defaults : Array[SupplierLink],
  overrides : Array[SupplierLink],
) -> Array[SupplierLink] {
  let out : Array[SupplierLink] = []
  for link in defaults {
    match supplier_link_for(overrides, link.part_number) {
      Some(over) => {
        let supplier = if over.supplier == "" {
          link.supplier
        } else {
          over.supplier
        }
        let supplier_url = if over.supplier_url == "" {
          link.supplier_url
        } else {
          over.supplier_url
        }
        let notes = if over.notes == "" { link.notes } else { over.notes }
        let unit_cost_usd : Double? = match over.unit_cost_usd {
          Some(cost) => Some(cost)
          None => link.unit_cost_usd
        }
        out.push(
          SupplierLink::new(
            part_number=link.part_number,
            supplier~,
            supplier_url~,
            notes~,
            unit_cost_usd?,
          ),
        )
      }
      None => out.push(link)
    }
  }
  for link in overrides {
    if supplier_link_for(defaults, link.part_number) is None {
      out.push(link)
    }
  }
  out
}
