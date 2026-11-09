///|
/// Structural and mobility components: box tubes, robot leg segments, wheels,
/// a wheeled quadruped, and an assistive scooter.

///|
/// Builds a hollow rectangular structural tube extruded along Z.
pub fn box_tube_strut(
  name : String,
  width_mm~ : Double,
  height_mm~ : Double,
  length_mm~ : Double,
  wall_mm~ : Double = 3.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let outer = @step_cad.Profile2D::centered_rect(width_mm, height_mm)
  let inner = @step_cad.Profile2D::centered_rect(
    width_mm - 2.0 * wall_mm,
    height_mm - 2.0 * wall_mm,
  )
  let unit_cost_usd = 8.0
  let part = fabricated_part(
    "TUBE-" +
    width_mm.to_string() +
    "x" +
    height_mm.to_string() +
    "x" +
    length_mm.to_string(),
    "Box tube " +
    width_mm.to_string() +
    " x " +
    height_mm.to_string() +
    " x " +
    length_mm.to_string(),
    "6061-T6",
    "extruded/cut",
    unit_cost_usd,
  )
  @cad.Component::new(name, description="Box tube strut")
  .with_param("width_mm", width_mm.to_string())
  .with_param("height_mm", height_mm.to_string())
  .with_param("length_mm", length_mm.to_string())
  .with_param("wall_mm", wall_mm.to_string())
  .add_body(
    @cad.BodyPart::extruded_profile_mm(
      name + "_body",
      outer,
      length_mm,
      holes=[inner],
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("start", z=-length_mm / 2.0)
  .add_mate_mm_deg("end", z=length_mm / 2.0)
  .with_part(part)
}

///|
/// Builds a robotic thigh or calf link with proximal and distal bosses,
/// extending along -Z from the proximal joint.
pub fn robot_leg_segment(
  name : String,
  length_mm~ : Double,
  width_mm~ : Double = 44.0,
  thickness_mm~ : Double = 28.0,
  density~ : @urdf.Density = @urdf.Density::carbon_fiber(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let leg_cost_usd = 12.0
  @cad.Component::new(name, description="Robot leg segment")
  .with_param("length_mm", length_mm.to_string())
  .with_param("width_mm", width_mm.to_string())
  .with_param("thickness_mm", thickness_mm.to_string())
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_proximal_boss",
      thickness_mm,
      width_mm,
      rx_deg=90.0,
      density~,
      color~,
    ),
  )
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_strut",
      width_mm,
      thickness_mm,
      length_mm,
      z_mm=-length_mm / 2.0,
      density~,
      color~,
    ),
  )
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_distal_boss",
      thickness_mm,
      width_mm,
      z_mm=-length_mm,
      rx_deg=90.0,
      density~,
      color~,
    ),
  )
  .add_mate_mm_deg("proximal_joint", axis=(0.0, 1.0, 0.0))
  .add_mate_mm_deg("distal_joint", z=-length_mm, axis=(0.0, 1.0, 0.0))
  .with_part(
    fabricated_part(
      "LEG-" + length_mm.to_string(),
      "Robot leg segment",
      "carbon fiber",
      "cut/drilled",
      leg_cost_usd,
    ),
  )
}

///|
/// Builds a wheel whose spin axis is +Y, with an aluminum hub and TPU tire.
pub fn treaded_wheel(
  name : String,
  radius_mm~ : Double = 90.0,
  width_mm~ : Double = 45.0,
  hub_radius_mm~ : Double = 35.0,
  density~ : @urdf.Density = @urdf.Density::tpu(),
) -> @cad.Component {
  let wheel_cost_usd = 22.0
  @cad.Component::new(name, description="Treaded wheel")
  .with_param("radius_mm", radius_mm.to_string())
  .with_param("width_mm", width_mm.to_string())
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_hub",
      hub_radius_mm * 2.0,
      width_mm,
      rx_deg=90.0,
      density=@urdf.Density::aluminum_6061(),
      color=@step_cad.Rgb::orange(),
    ),
  )
  .add_body(
    @cad.BodyPart::tube_mm(
      name + "_tire",
      radius_mm * 2.0,
      hub_radius_mm * 2.0,
      width_mm,
      rx_deg=90.0,
      density~,
      color=@step_cad.Rgb::black(),
    ),
  )
  .add_mate_mm_deg("axle", axis=(0.0, 1.0, 0.0))
  .with_part(
    purchased_part(
      "WHEEL-" + radius_mm.to_string(),
      "Treaded wheel",
      "aluminum/TPU",
      wheel_cost_usd,
    ),
  )
}

///|
/// Builds a four-DOF wheeled quadruped leg: hip, thigh, calf, and wheel.
pub fn quadruped_leg_assembly(
  prefix : String,
  is_left~ : Bool,
  hip_offset_y_mm~ : Double = 85.0,
  thigh_len_mm~ : Double = 220.0,
  calf_len_mm~ : Double = 220.0,
  wheel_radius_mm~ : Double = 90.0,
) -> @cad.Component {
  let sign = if is_left { 1.0 } else { -1.0 }
  let hip_cost_usd = 18.0
  let hip_name = prefix + "_hip_link"
  let thigh_name = prefix + "_thigh_link"
  let calf_name = prefix + "_calf_link"
  let wheel_name = prefix + "_wheel_link"
  let hip = @cad.Component::new(hip_name, description="Quadruped hip link")
    .with_param("hip_offset_y_mm", hip_offset_y_mm.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        hip_name + "_tube",
        60.0,
        hip_offset_y_mm,
        y_mm=sign * hip_offset_y_mm / 2.0,
        rx_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        hip_name + "_pod",
        96.0,
        54.0,
        y_mm=sign * hip_offset_y_mm,
        rx_deg=90.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::orange(),
      ),
    )
    .add_mate_mm_deg("hip_mount", axis=(1.0, 0.0, 0.0))
    .add_mate_mm_deg(
      "thigh_mount",
      y=sign * hip_offset_y_mm,
      axis=(0.0, 1.0, 0.0),
    )
    .with_part(
      fabricated_part(
        "HIP-LINK-" + hip_offset_y_mm.to_string(),
        "Quadruped hip link",
        "6061-T6",
        "CNC",
        hip_cost_usd,
      ),
    )
  let thigh = robot_leg_segment(thigh_name, length_mm=thigh_len_mm)
  let calf = robot_leg_segment(calf_name, length_mm=calf_len_mm)
  let wheel = treaded_wheel(wheel_name, radius_mm=wheel_radius_mm)
  let calf_with_wheel = calf.attach(
    "\{prefix}_wheel_joint",
    parent_mate="distal_joint",
    wheel,
    child_mate="axle",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=20.0, velocity=35.0)),
      transmission_reduction=Some(1.0),
    ),
  )
  let thigh_with_calf = thigh.attach(
    "\{prefix}_calf_joint",
    parent_mate="distal_joint",
    calf_with_wheel,
    child_mate="proximal_joint",
    spec=@cad.JointSpec::revolute(
      @urdf.JointLimit::new(
        lower=Some(-2.7),
        upper=Some(-0.5),
        effort=55.0,
        velocity=18.0,
      ),
      transmission_reduction=Some(6.0),
    ),
  )
  hip.attach(
    "\{prefix}_thigh_joint",
    parent_mate="thigh_mount",
    thigh_with_calf,
    child_mate="proximal_joint",
    spec=@cad.JointSpec::revolute(
      @urdf.JointLimit::new(
        lower=Some(-1.57),
        upper=Some(3.14),
        effort=45.0,
        velocity=21.0,
      ),
      transmission_reduction=Some(6.0),
    ),
  )
}

///|
/// Builds a complete Galileo-style wheeled quadruped robot.
pub fn galileo_quadruped_robot(
  name~ : String = "galileo_quadruped",
  body_len_mm~ : Double = 520.0,
  body_width_mm~ : Double = 240.0,
  body_height_mm~ : Double = 110.0,
  thigh_len_mm~ : Double = 220.0,
  calf_len_mm~ : Double = 220.0,
  wheel_radius_mm~ : Double = 90.0,
) -> @cad.Component {
  let half_len = body_len_mm / 2.0
  let half_width = body_width_mm / 2.0
  let chassis_cost_usd = 60.0
  let lidar_cost_usd = 90.0
  let mut base = @cad.Component::new("base_link", description="Galileo chassis")
    .with_robot_name(name)
    .with_param("body_len_mm", body_len_mm.to_string())
    .with_param("body_width_mm", body_width_mm.to_string())
    .with_param("thigh_len_mm", thigh_len_mm.to_string())
    .with_param("calf_len_mm", calf_len_mm.to_string())
    .add_body(
      @cad.BodyPart::box_mm(
        "chassis",
        body_len_mm,
        body_width_mm,
        body_height_mm,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(
        fabricated_part(
          "GALILEO-CHASSIS", "Galileo chassis", "6061-T6", "CNC", chassis_cost_usd,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        "lidar_dome",
        110.0,
        40.0,
        z_mm=body_height_mm / 2.0 + 20.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::black(),
      ).with_part(
        purchased_part("LIDAR-2D", "2D lidar", "mixed", lidar_cost_usd),
      ),
    )
  let corners = [
    ("fl", half_len, half_width, true),
    ("fr", half_len, -half_width, false),
    ("rl", -half_len, half_width, true),
    ("rr", -half_len, -half_width, false),
  ]
  for corner in corners {
    let (prefix, x, y, is_left) = corner
    base = base.add_mate_mm_deg(
      "\{prefix}_hip_mount",
      x~,
      y~,
      axis=(1.0, 0.0, 0.0),
    )
    let leg = quadruped_leg_assembly(
      prefix,
      is_left~,
      thigh_len_mm~,
      calf_len_mm~,
      wheel_radius_mm~,
    )
    base = base.attach(
      "\{prefix}_hip_joint",
      parent_mate="\{prefix}_hip_mount",
      leg,
      child_mate="hip_mount",
      spec=@cad.JointSpec::revolute(
        @urdf.JointLimit::new(
          lower=Some(-0.8),
          upper=Some(0.8),
          effort=45.0,
          velocity=21.0,
        ),
        transmission_reduction=Some(6.0),
      ),
    )
  }
  base
}

///|
/// Builds a rider-parameterized assistive mobility scooter.
pub fn assistive_scooter_robot(
  name~ : String = "assistive_scooter",
  wheelbase_mm~ : Double = 700.0,
  track_width_mm~ : Double = 520.0,
  seat_height_mm~ : Double = 480.0,
  rear_wheel_r_mm~ : Double = 150.0,
  front_wheel_r_mm~ : Double = 100.0,
) -> @cad.Component {
  let chassis_name = "chassis_link"
  let steering_name = "steering_column_link"
  let front_name = "front_wheel_link"
  let rear_left_name = "rear_left_wheel_link"
  let rear_right_name = "rear_right_wheel_link"
  let seat_x = -wheelbase_mm * 0.15
  let deck_top = 90.0
  let deck_cost_usd = 60.0
  let seat_post_cost_usd = 8.0
  let seat_cost_usd = 35.0
  let backrest_cost_usd = 25.0
  let chassis = @cad.Component::new(chassis_name, description="Scooter chassis")
    .with_robot_name(name)
    .with_param("wheelbase_mm", wheelbase_mm.to_string())
    .with_param("track_width_mm", track_width_mm.to_string())
    .with_param("seat_height_mm", seat_height_mm.to_string())
    .add_body(
      @cad.BodyPart::box_mm(
        chassis_name + "_deck",
        wheelbase_mm * 0.75,
        track_width_mm * 0.55,
        deck_top,
        z_mm=deck_top / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(
        fabricated_part(
          "SCOOTER-DECK", "Scooter deck", "6061-T6", "CNC", deck_cost_usd,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        chassis_name + "_seat_post",
        40.0,
        seat_height_mm - deck_top,
        x_mm=seat_x,
        z_mm=deck_top + (seat_height_mm - deck_top) / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::black(),
      ).with_part(
        fabricated_part(
          "SEAT-POST", "Seat post", "mild steel", "cut/weld", seat_post_cost_usd,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        chassis_name + "_seat",
        400.0,
        track_width_mm * 0.8,
        80.0,
        x_mm=seat_x,
        z_mm=seat_height_mm + 40.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::black(),
      ).with_part(
        purchased_part(
          "SCOOTER-SEAT", "Scooter seat", "foam/vinyl", seat_cost_usd,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        chassis_name + "_backrest",
        80.0,
        track_width_mm * 0.8,
        300.0,
        x_mm=seat_x - 200.0,
        z_mm=seat_height_mm + 150.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::black(),
      ).with_part(
        purchased_part(
          "SCOOTER-BACKREST", "Scooter backrest", "foam/vinyl", backrest_cost_usd,
        ),
      ),
    )
    .add_mate_mm_deg("steering_mount", x=wheelbase_mm * 0.4, z=deck_top)
    .add_mate_mm_deg(
      "rear_left_axle",
      x=-wheelbase_mm / 2.0,
      y=track_width_mm / 2.0,
      z=rear_wheel_r_mm,
      axis=(0.0, 1.0, 0.0),
    )
    .add_mate_mm_deg(
      "rear_right_axle",
      x=-wheelbase_mm / 2.0,
      y=-track_width_mm / 2.0,
      z=rear_wheel_r_mm,
      axis=(0.0, 1.0, 0.0),
    )
  let column_cost_usd = 12.0
  let handlebar_cost_usd = 15.0
  let steering = @cad.Component::new(
      steering_name,
      description="Scooter steering column",
    )
    .with_param("seat_height_mm", seat_height_mm.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        steering_name + "_column",
        30.0,
        seat_height_mm,
        z_mm=seat_height_mm / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(
        fabricated_part(
          "SCOOTER-COLUMN", "Steering column", "6061-T6", "cut/weld", column_cost_usd,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        steering_name + "_handlebar",
        60.0,
        500.0,
        30.0,
        z_mm=seat_height_mm,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::black(),
      ).with_part(
        purchased_part(
          "SCOOTER-HANDLEBAR", "Handlebar", "mild steel", handlebar_cost_usd,
        ),
      ),
    )
    .add_mate_mm_deg("mount")
    .add_mate_mm_deg("front_axle", z=-deck_top, axis=(0.0, 1.0, 0.0))
  let front_wheel = treaded_wheel(front_name, radius_mm=front_wheel_r_mm)
  let rear_left = treaded_wheel(rear_left_name, radius_mm=rear_wheel_r_mm)
  let rear_right = treaded_wheel(rear_right_name, radius_mm=rear_wheel_r_mm)
  let steering_with_wheel = steering.attach(
    "front_wheel_joint",
    parent_mate="front_axle",
    front_wheel,
    child_mate="axle",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
    ),
  )
  chassis
  .attach(
    "steering_joint",
    parent_mate="steering_mount",
    steering_with_wheel,
    child_mate="mount",
    spec=@cad.JointSpec::revolute(
      @urdf.JointLimit::new(
        lower=Some(-0.75),
        upper=Some(0.75),
        effort=15.0,
        velocity=3.0,
      ),
      transmission_reduction=Some(5.0),
    ),
  )
  .attach(
    "rear_left_wheel_joint",
    parent_mate="rear_left_axle",
    rear_left,
    child_mate="axle",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=20.0, velocity=30.0)),
      transmission_reduction=Some(1.0),
    ),
  )
  .attach(
    "rear_right_wheel_joint",
    parent_mate="rear_right_axle",
    rear_right,
    child_mate="axle",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=20.0, velocity=30.0)),
      transmission_reduction=Some(1.0),
    ),
  )
}
