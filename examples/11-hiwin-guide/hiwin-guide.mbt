///|
/// 11-hiwin-guide — a Hiwin HGR15 rail with an HGH15CA carriage assembled at a
/// named seat, exercising the Hiwin wrappers, their mate connectors, and the
/// BOM/sourcing/URDF bundle path.

///|
/// Builds the example component.
///
/// Keep this function free of CLI concerns so other assemblies can import the
/// package and reuse the same builder.
pub fn build_example(
  length_mm~ : Double = 400.0,
  travel_mm~ : Double = 180.0,
) -> @cad.Component {
  let rail = @components.hiwin_hgr_rail(name="rail", size="HGR15", length_mm~).add_mate_mm_deg(
    "carriage_seat",
    x=travel_mm,
    z=15.0,
    axis=(1.0, 0.0, 0.0),
  )
  let carriage = @components.hiwin_hgh_block(name="carriage", size="HGH15CA").add_mate_mm_deg(
    "carriage_base",
    z=0.0,
  )
  let lower_m = -travel_mm / 1000.0
  let upper_m = (length_mm - travel_mm) / 1000.0
  rail.attach(
    "rail_to_carriage",
    parent_mate="carriage_seat",
    carriage,
    child_mate="carriage_base",
    spec=@cad.JointSpec::prismatic(
      @urdf.JointLimit::new(
        effort=200.0,
        velocity=1.0,
        lower=Some(lower_m),
        upper=Some(upper_m),
      ),
    ),
    explode=Some(@cad.ExplodeSpec::offset_mm(dx=0.0, dy=0.0, dz=35.0)),
  )
}

///|
/// Runs the `11-hiwin-guide` CLI.
pub async fn run_cli() -> Unit {
  let base_spec = {
    "length": @cli.opt_double(
      400.0,
      help="Rail length in mm (default 400)",
      min=0.0,
      min_exclusive=true,
    ),
    "travel": @cli.opt_double(
      180.0,
      help="Carriage seat position along the rail in mm (default 180)",
      min=0.0,
    ),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="11-hiwin-guide",
      description="Hiwin HGR15 rail with an HGH15CA carriage.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let comp = build_example(
    length_mm=args.double("length"),
    travel_mm=args.double("travel"),
  )
  @common.write_output(comp, output, example_dir="examples/11-hiwin-guide")
}
