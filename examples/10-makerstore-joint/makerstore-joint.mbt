///|
/// 10-makerstore-joint — a Maker Store 40 x 40 L plate with a stacked aluminum
/// spacer post, assembled through named `Datum` mates.
///
/// The L plate is the calibrated `PLATE-40X40L` (3 x 3 Ø5 holes on 10 mm
/// centres). Two `SHIM-SPAC` spacers stack on the plate's top face over its
/// centre hole, so the assembly exercises the new Maker Store parts, their
/// mate connectors, and the BOM/sourcing/URDF bundle path.

///|
/// Builds the assembled example component.
///
/// Keep this function free of CLI concerns so other assemblies can import the
/// package and reuse the same builder.
pub fn build_example(
  plate_leg_mm~ : Double = 40.0,
  spacer_length_mm~ : Double = 10.0,
) -> @cad.Component {
  let plate = @components.makerstore_l_plate(
    name="l_plate",
    leg_a_mm=plate_leg_mm,
    leg_b_mm=plate_leg_mm,
  ).add_mate_mm_deg("spacer_stack", x=plate_leg_mm / 2.0, z=3.0)
  let spacer_a = @components.makerstore_aluminum_spacer(
    name="spacer_a",
    length_mm=spacer_length_mm,
  ).add_mate_mm_deg("spacer_stack", z=0.0)
  let spacer_b = @components.makerstore_aluminum_spacer(
    name="spacer_b",
    length_mm=6.0,
  )
  let post = spacer_a.attach(
    "spacer_a_to_b",
    parent_mate="face-positive",
    spacer_b,
    child_mate="face-negative",
    spec=@cad.JointSpec::fixed(),
  )
  plate.attach(
    "plate_to_post",
    parent_mate="spacer_stack",
    post,
    child_mate="spacer_stack",
    spec=@cad.JointSpec::fixed(),
  )
}

///|
/// Runs the `10-makerstore-joint` CLI.
pub async fn run_cli() -> Unit {
  let base_spec = {
    "plateLeg": @cli.opt_double(
      40.0,
      help="L plate leg length in mm (default 40)",
      min=0.0,
      min_exclusive=true,
    ),
    "spacerLength": @cli.opt_double(
      10.0,
      help="First spacer length in mm (default 10)",
      min=0.0,
      min_exclusive=true,
    ),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="10-makerstore-joint",
      description="Maker Store L plate with a stacked aluminum spacer post.",
    )
    is Some(args) else {
    return
  }
  let output = @common.output_paths(args)
  let comp = build_example(
    plate_leg_mm=args.double("plateLeg"),
    spacer_length_mm=args.double("spacerLength"),
  )
  @common.write_output(comp, output, example_dir="examples/10-makerstore-joint")
}
