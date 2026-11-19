///|
test "comma lists repeat the last value" {
  let doubles = match @cad.parse_double_list("1.0, 2.0", 4, "module") {
    Ok(values) => values
    Err(message) => fail(message)
  }
  assert_eq(doubles.length(), 4)
  assert_true(doubles[0] == 1.0)
  assert_true(doubles[1] == 2.0)
  assert_true(doubles[2] == 2.0)
  assert_true(doubles[3] == 2.0)
  let ints = match @cad.parse_int_list(" 12 , 20 ", 3, "sunTeeth") {
    Ok(values) => values
    Err(message) => fail(message)
  }
  assert_eq(ints.length(), 3)
  assert_eq(ints[0], 12)
  assert_eq(ints[1], 20)
  assert_eq(ints[2], 20)
  let strings = match
    @cad.parse_string_list("FR8-2RS, 608", 3, "planetBearing") {
    Ok(values) => values
    Err(message) => fail(message)
  }
  assert_eq(strings.length(), 3)
  assert_eq(strings[0], "FR8-2RS")
  assert_eq(strings[1], "608")
  assert_eq(strings[2], "608")
}

///|
test "comma lists reject empty and malformed values" {
  match @cad.parse_double_list("", 2, "module") {
    Ok(_) => fail("an empty double list should be rejected")
    Err(_) => ()
  }
  match @cad.parse_double_list("1.0, nope", 2, "module") {
    Ok(_) => fail("a malformed double should be rejected")
    Err(_) => ()
  }
  match @cad.parse_int_list("1, 2.5", 2, "sunTeeth") {
    Ok(_) => fail("a malformed integer should be rejected")
    Err(_) => ()
  }
  match @cad.parse_string_list(" , ", 2, "planetBearing") {
    Ok(_) => fail("an empty string list should be rejected")
    Err(_) => ()
  }
}

///|
test "supplier links parse comments, fields, and costs" {
  let text = "# a comment\n" +
    "BEARING-X | Amazon | https://example.com/bearing | exact bearing | 3.50\n" +
    "\n" +
    "SHORT | only-two-fields\n" +
    "NO-COST | McMaster-Carr | https://example.com/shaft | cut to length\n"
  let links = @cad.parse_supplier_links(text)
  assert_eq(links.length(), 2)
  assert_eq(links[0].part_number, "BEARING-X")
  assert_eq(links[0].supplier, "Amazon")
  assert_eq(links[0].supplier_url, "https://example.com/bearing")
  assert_eq(links[0].notes, "exact bearing")
  match links[0].unit_cost_usd {
    Some(cost) => assert_true((cost - 3.5).abs() < 1.0e-9)
    None => fail("expected a parsed cost")
  }
  assert_eq(links[1].part_number, "NO-COST")
  match links[1].unit_cost_usd {
    Some(_) => fail("expected no cost")
    None => ()
  }
}

///|
test "merge_supplier_links overlays example values over catalog defaults" {
  let defaults = @cad.parse_supplier_links(
    "M4 | CatalogCo | https://catalog.example/4 | catalog default | 1.0\n" +
    "M3 | CatalogCo | https://catalog.example/3 | catalog default | 0.5\n",
  )
  let overrides = @cad.parse_supplier_links(
    "M4 | ExampleCo |  | example note | 2.0\n" +
    "M5 | ExampleCo | https://example.example/5 | only here | 3.0\n",
  )
  let merged = @cad.merge_supplier_links(defaults, overrides)
  assert_eq(merged.length(), 3)
  let lookup = fn(part_number : String) -> @cad.SupplierLink? {
    let mut found : @cad.SupplierLink? = None
    for link in merged {
      if link.part_number == part_number {
        found = Some(link)
      }
    }
    found
  }
  match lookup("M4") {
    Some(link) => {
      assert_eq(link.supplier, "ExampleCo")
      assert_eq(link.supplier_url, "https://catalog.example/4")
      assert_eq(link.notes, "example note")
      match link.unit_cost_usd {
        Some(cost) => assert_true((cost - 2.0).abs() < 1.0e-9)
        None => fail("expected the example cost")
      }
    }
    None => fail("expected a merged M4 link")
  }
  match lookup("M3") {
    Some(link) => assert_eq(link.supplier, "CatalogCo")
    None => fail("expected the catalog M3 link")
  }
  match lookup("M5") {
    Some(link) => assert_eq(link.supplier_url, "https://example.example/5")
    None => fail("expected the added M5 link")
  }
}
