///|
/// 06-assistive-scooter
///
/// A rider-parameterized assistive mobility scooter: chassis with seat, a
/// steerable front column and wheel, and two driven rear wheels.

///|
async fn main {
  let base_spec = {
    "wheelbase": @cli.opt_double(700.0, help="Wheelbase in mm"),
    "trackWidth": @cli.opt_double(520.0, help="Track width in mm"),
    "seatHeight": @cli.opt_double(480.0, help="Seat height in mm"),
    "steerDeg": @cli.opt_double(0.0, help="Steering angle in degrees"),
  }
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="06-assistive-scooter",
      description="Lightweight rider-parameterized assistive mobility scooter.",
    )
    is Some(args) else {
    return
  }
  let comp = @cad.assistive_scooter_robot(
    wheelbase_mm=args.double("wheelbase"),
    track_width_mm=args.double("trackWidth"),
    seat_height_mm=args.double("seatHeight"),
  )
  let positions : Map[String, Double] = Map([])
  positions.set("steering_joint", args.double("steerDeg") * @math.PI / 180.0)
  @common.write_output(
    comp,
    @common.output_paths(args),
    joint_positions=positions,
  )
}
