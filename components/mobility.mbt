///|
/// Reusable mobility sub-assemblies: structural tubes, robot leg segments,
/// wheels, quadruped legs, and a steerable suspension fork.
///
/// Whole-robot models live under `examples/`; this package contains only
/// parameterized building blocks shared by those models.

///|
/// Builds a hollow rectangular structural tube extruded along Z.
pub fn box_tube_strut(
  name : String,
  width_mm~ : Double,
  height_mm~ : Double,
  length_mm~ : Double,
  wall_mm~ : Double = 3.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let _ = detail
  let outer = @step_cad.Profile2D::centered_rect(width_mm, height_mm)
  let inner = @step_cad.Profile2D::centered_rect(
    width_mm - 2.0 * wall_mm,
    height_mm - 2.0 * wall_mm,
  )
  let part = fabricated_part(
    "TUBE-\{width_mm}x\{height_mm}x\{length_mm}",
    "Box tube \{width_mm} x \{height_mm} x \{length_mm}",
    "6061-T6",
    "3D print / CNC",
    8.0,
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
/// Builds a printable robotic thigh or calf link with proximal and distal
/// bosses and pressed bearing seats, extending along `-Z` from the proximal
/// joint.
pub fn robot_leg_segment(
  name : String,
  length_mm~ : Double,
  width_mm~ : Double = 44.0,
  thickness_mm~ : Double = 28.0,
  bore_diam_mm~ : Double = 22.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::carbon_fiber(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let part = fabricated_part(
    "LEG-\{length_mm}",
    "Robot leg segment",
    "carbon fiber nylon",
    "3D print",
    12.0,
  )
  let mut leg = @cad.Component::new(name, description="Robot leg segment")
    .with_param("length_mm", length_mm.to_string())
    .with_param("width_mm", width_mm.to_string())
    .with_param("thickness_mm", thickness_mm.to_string())
    .with_param("bore_diam_mm", bore_diam_mm.to_string())
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
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .with_part(part)
  if detail_is_rich(detail) {
    let bearing = ball_bearing(
      name=name + "_proximal_bearing",
      designation="",
      inner_diam_mm=bore_diam_mm * 0.42,
      outer_diam_mm=bore_diam_mm,
      width_mm=thickness_mm * 0.32,
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    leg = leg.attach(
      "proximal_bearing_merge",
      parent_mate="proximal_joint",
      bearing,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
    let distal_bearing = ball_bearing(
      name=name + "_distal_bearing",
      designation="",
      inner_diam_mm=bore_diam_mm * 0.42,
      outer_diam_mm=bore_diam_mm,
      width_mm=thickness_mm * 0.32,
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    leg = leg.attach(
      "distal_bearing_merge",
      parent_mate="distal_joint",
      distal_bearing,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  leg
}

///|
/// Builds a wheel whose spin axis is +Y: a 3D-printable PETG hub, a
/// 3D-printable TPU tread, and hub bearings.
pub fn treaded_wheel(
  name : String,
  radius_mm~ : Double = 70.0,
  width_mm~ : Double = 45.0,
  hub_radius_mm~ : Double = 35.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::tpu(),
) -> @cad.Component {
  let policy = @step_common.DetailPolicy::for_level(detail)
  let hub_part = fabricated_part(
    "WHEEL-HUB-\{radius_mm}",
    "Wheel hub",
    "PETG",
    "3D print",
    9.0,
  )
  let tread_part = fabricated_part(
    "WHEEL-TREAD-\{radius_mm}",
    "Flexible wheel tread",
    "TPU",
    "3D print",
    6.0,
  )
  let mut wheel = @cad.Component::new(name, description="Treaded wheel")
    .with_param("radius_mm", radius_mm.to_string())
    .with_param("width_mm", width_mm.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_hub",
        hub_radius_mm * 2.0,
        width_mm,
        rx_deg=90.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::orange(),
      ).with_part(hub_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_tire",
        radius_mm * 2.0,
        hub_radius_mm * 2.0,
        width_mm,
        segments=policy.circle_segments,
        rx_deg=90.0,
        density~,
        color=@step_cad.Rgb::black(),
      ).with_part(tread_part),
    )
    .add_mate_mm_deg("axle", axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg("outer_face", x=width_mm / 2.0, axis=(1.0, 0.0, 0.0))
  if detail_is_rich(detail) {
    let bearing_width = width_mm * 0.22
    let bearing = ball_bearing(
      name=name + "_hub_bearing",
      designation="608",
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    wheel = wheel.attach(
      "hub_bearing_merge",
      parent_mate="axle",
      bearing,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
    let _ = bearing_width
  }
  wheel
}

///|
/// Builds a four-DOF wheeled quadruped leg module: hip abduction, hip pitch,
/// knee pitch, and the driven wheel.
///
/// The hip link carries the QDD pod body; the thigh and calf are printable leg
/// segments with bearing seats; the wheel is a printable hub and TPU tread.
pub fn quadruped_leg_assembly(
  prefix : String,
  is_left~ : Bool,
  hip_offset_y_mm~ : Double = 58.0,
  thigh_length_mm~ : Double = 210.0,
  calf_length_mm~ : Double = 210.0,
  wheel_diam_mm~ : Double = 140.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let sign = if is_left { 1.0 } else { -1.0 }
  // Clevis stack: each link's bosses sit beside its parent's boss rather than
  // sharing the same axial span, so the exported solids do not interpenetrate.
  let hip_pod_length_mm = 54.0
  let leg_width_mm = 44.0
  let leg_thickness_mm = 28.0
  let wheel_width_mm = 45.0
  let hip_to_thigh_mm = sign * (hip_pod_length_mm / 2.0 + leg_width_mm / 2.0)
  let thigh_to_calf_mm = -sign * (leg_width_mm / 2.0 + leg_thickness_mm / 2.0)
  let calf_to_wheel_mm = sign * (leg_width_mm / 2.0 + wheel_width_mm / 2.0)
  let hip_name = prefix + "_hip_link"
  let thigh_name = prefix + "_thigh_link"
  let calf_name = prefix + "_calf_link"
  let wheel_name = prefix + "_wheel_link"
  let hip_part = fabricated_part(
    "HIP-LINK-\{hip_offset_y_mm}",
    "Quadruped hip link",
    "6061-T6",
    "3D print / CNC",
    18.0,
  )
  let mut hip = @cad.Component::new(hip_name, description="Quadruped hip link")
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
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .with_part(hip_part)
  if detail_is_rich(detail) {
    // A printed hip-to-thigh bracket ties the pod to the leg.
    let bracket = sensor_mount_bracket(
      name=hip_name + "_bracket",
      width_mm=hip_offset_y_mm * 0.7,
      height_mm=hip_offset_y_mm * 0.5,
      thickness_mm=5.0,
      detail~,
    )
    hip = hip.attach(
      "hip_bracket_merge",
      parent_mate="thigh_mount",
      bracket,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let mut calf = robot_leg_segment(calf_name, length_mm=calf_length_mm, detail~)
  if detail_is_rich(detail) {
    let force = force_sensor(name=calf_name + "_foot_sensor", detail~)
    calf = calf.attach(
      "foot_sensor_merge",
      parent_mate="distal_joint",
      force,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
    let wire = @cad.WireRun::new(
      "\{prefix}_motor_power",
      from_component=hip_name,
      from_port="power",
      to_component=calf_name,
      to_port="power",
      gauge_awg=18,
      length_mm=calf_length_mm * 2.0,
    )
    calf = calf.add_wire_run(wire)
    let harness = cable_route(
      name=calf_name + "_harness",
      points=[
        (0.0, 0.0, 0.0),
        (0.0, 20.0, -calf_length_mm * 0.35),
        (0.0, 10.0, -calf_length_mm * 0.8),
      ],
      jacket_diameter_mm=5.0,
      wire_names=["\{prefix}_motor_power"],
      material="PVC",
      from_component=hip_name,
      from_port="power",
      to_component=calf_name,
      to_port="power",
      detail~,
    )
    calf = calf.attach(
      "leg_harness_merge",
      parent_mate="proximal_joint",
      harness,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let thigh = robot_leg_segment(thigh_name, length_mm=thigh_length_mm, detail~)
  let wheel = treaded_wheel(wheel_name, radius_mm=wheel_diam_mm / 2.0, detail~)
  let calf_with_wheel = calf.attach(
    "\{prefix}_wheel_joint",
    parent_mate="distal_joint",
    wheel,
    child_mate="axle",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=20.0, velocity=35.0)),
      offset_mm=calf_to_wheel_mm,
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
      offset_mm=thigh_to_calf_mm,
      transmission_reduction=Some(6.0),
    ),
  )
  let _ = threads
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
      offset_mm=hip_to_thigh_mm,
      transmission_reduction=Some(6.0),
    ),
  )
}

///|
/// Builds a steerable front suspension fork with headset bearings, a coil-over
/// spring, a printed crown and dropouts, and a driven front wheel.
pub fn suspension_fork_module(
  name~ : String = "front_fork",
  fork_span_mm~ : Double = 100.0,
  fork_length_mm~ : Double = 220.0,
  wheel_diam_mm~ : Double = 200.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
  let _ = threads
  let crown_part = fabricated_part(
    "FORK-CROWN", "Suspension fork crown", "6061-T6", "3D print / CNC", 16.0,
  )
  let dropout_part = fabricated_part(
    "FORK-DROPOUT", "Suspension fork dropout", "6061-T6", "3D print / CNC", 8.0,
  )
  let half_span = fork_span_mm / 2.0
  let mut fork = @cad.Component::new(name, description="Suspension fork")
    .with_param("fork_span_mm", fork_span_mm.to_string())
    .with_param("fork_length_mm", fork_length_mm.to_string())
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_crown",
        30.0,
        fork_span_mm + 20.0,
        18.0,
        z_mm=fork_length_mm,
        density~,
        color=@step_cad.Rgb::grey(),
      ).with_part(crown_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_leg_left",
        18.0,
        fork_length_mm,
        y_mm=-half_span,
        z_mm=fork_length_mm / 2.0,
        density~,
        color=@step_cad.Rgb::grey(),
      ).with_part(
        @cad.PartMeta::new(
          "FORK-LEG",
          description="Suspension fork leg",
          supplier="in-house",
          material="6061-T6",
          process="3D print / CNC",
          unit_cost_usd=5.0,
        ),
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_leg_right",
        18.0,
        fork_length_mm,
        y_mm=half_span,
        z_mm=fork_length_mm / 2.0,
        density~,
        color=@step_cad.Rgb::grey(),
      ).with_part(
        @cad.PartMeta::new(
          "FORK-LEG",
          description="Suspension fork leg",
          supplier="in-house",
          material="6061-T6",
          process="3D print / CNC",
          unit_cost_usd=5.0,
        ),
      ),
    )
    .add_mate_mm_deg("mount", z=fork_length_mm + 18.0)
    .add_mate_mm_deg("steering_axis", z=fork_length_mm)
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="36 V"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .add_mate_mm_deg("spring_seat", z=fork_length_mm * 0.55)
    .add_mate_mm_deg("front_axle", z=0.0, axis=(0.0, 1.0, 0.0))
  let headset = ball_bearing(
    name=name + "_headset_bearing",
    designation="608",
    detail~,
    density=@urdf.Density::steel_mild(),
  )
  fork = fork.attach(
    "headset_merge",
    parent_mate="steering_axis",
    headset,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let spring = compression_spring_part(
    name=name + "_spring",
    wire_diam_mm=4.0,
    mean_diam_mm=fork_span_mm * 0.35,
    free_length_mm=fork_length_mm * 0.7,
    detail~,
  )
  fork = fork.attach(
    "spring_merge",
    parent_mate="spring_seat",
    spring,
    child_mate="bottom",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let dropout = @cad.Component::new(
      name + "_dropouts",
      description="Suspension fork dropouts",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_dropout_left",
        26.0,
        18.0,
        30.0,
        y_mm=-half_span,
        z_mm=12.0,
        density~,
        color=@step_cad.Rgb::grey(),
      ).with_part(dropout_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_dropout_right",
        26.0,
        18.0,
        30.0,
        y_mm=half_span,
        z_mm=12.0,
        density~,
        color=@step_cad.Rgb::grey(),
      ).with_part(dropout_part),
    )
  fork = fork.attach(
    "dropout_merge",
    parent_mate="front_axle",
    dropout,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let wheel = treaded_wheel(
    name + "_wheel",
    radius_mm=wheel_diam_mm / 2.0,
    detail~,
  )
  fork.attach(
    "\{name}_wheel_joint",
    parent_mate="front_axle",
    wheel,
    child_mate="axle",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=20.0, velocity=30.0)),
      transmission_reduction=Some(1.0),
    ),
  )
}
