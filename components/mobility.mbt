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
      ).with_part(part),
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
      ).with_part(part),
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
      ).with_part(part),
    )
    .add_mate_mm_deg("proximal_joint", axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg("distal_joint", z=-length_mm, axis=(0.0, 1.0, 0.0))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
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
  if detail is @step_common.DetailLevel::FullyModeled {
    for i in 0..<2 {
      let insert = heat_set_insert(
        name="\{name}_insert_\{i}",
        outer_diam_mm=4.5,
        inner_diam_mm=3.0,
        length_mm=6.0,
      )
      leg = leg.attach(
        "insert_merge_\{i}",
        parent_mate="proximal_joint",
        insert,
        child_mate="seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
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
  hub_bore_mm~ : Double = 8.0,
  hub_bolt_circle_mm~ : Double = 0.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  density~ : @urdf.Density = @urdf.Density::tpu(),
) -> @cad.Component {
  let policy = @step_common.DetailPolicy::for_level(detail)
  let hub_part = fabricated_part(
    "WHEEL-HUB-\{radius_mm}",
    "Wheel hub",
    "PETG / carbon fiber nylon",
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
    .with_param("hub_bore_mm", hub_bore_mm.to_string())
    .add_body(
      (if detail_is_rich(detail) {
        @cad.BodyPart::tube_mm(
          name + "_hub",
          hub_radius_mm * 2.0,
          hub_bore_mm,
          width_mm,
          segments=policy.circle_segments,
          rx_deg=90.0,
          density=@urdf.Density::petg(),
          color=@step_cad.Rgb::orange(),
        )
      } else {
        @cad.BodyPart::cylinder_mm(
          name + "_hub",
          hub_radius_mm * 2.0,
          width_mm,
          rx_deg=90.0,
          density=@urdf.Density::petg(),
          color=@step_cad.Rgb::orange(),
        )
      }).with_part(hub_part),
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
    // Lightening spokes keep the hub a single printable part.
    for i in 0..<4 {
      let theta = @math.PI * i.to_double() / 4.0
      wheel = wheel.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_spoke_\{i}",
          hub_radius_mm * 1.6,
          width_mm * 0.18,
          width_mm * 0.35,
          z_mm=0.0,
          rx_deg=90.0,
          ry_deg=0.0,
          density=@urdf.Density::petg(),
          color=@step_cad.Rgb::orange(),
        ).with_part(hub_part),
      )
      let _ = theta
    }
    // Bolt pattern matching the actuator output flange.
    if hub_bolt_circle_mm > 0.0 {
      for i in 0..<6 {
        let theta = 2.0 * @math.PI * i.to_double() / 6.0
        wheel = wheel.add_mate_mm_deg(
          "hub_bolt_\{i}",
          y=-(hub_bolt_circle_mm / 2.0) * @math.cos(theta),
          z=hub_bolt_circle_mm / 2.0 * @math.sin(theta),
          axis=(0.0, 1.0, 0.0),
        )
      }
    }
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
    let collar = shaft_collar(
      name=name + "_hub_collar",
      bore_diam_mm=hub_bore_mm,
      outer_diam_mm=hub_bore_mm * 2.0,
      width_mm=bearing_width,
      style="set_screw",
      detail~,
    )
    wheel = wheel.attach(
      "hub_collar_merge",
      parent_mate="axle",
      collar,
      child_mate="bore",
      spec=@cad.JointSpec::merge_rigid(),
    )
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
  max_effort_nm~ : Double = 45.0,
  max_vel_rad_s~ : Double = 21.0,
  wheeled~ : Bool = true,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let sign = if is_left { 1.0 } else { -1.0 }
  // Clevis stack: each link's bosses sit beside its parent's boss rather than
  // sharing the same axial span, so the exported solids do not interpenetrate.
  let hip_pod_length_mm = 54.0
  let leg_width_mm = 44.0
  let wheel_width_mm = 45.0
  let hip_to_thigh_mm = sign *
    (hip_pod_length_mm / 2.0 + leg_width_mm / 2.0 + 6.0)
  let thigh_to_calf_mm = -sign * (leg_width_mm / 2.0 + leg_width_mm / 2.0 + 8.0)
  let calf_to_wheel_mm = sign *
    (leg_width_mm / 2.0 + wheel_width_mm / 2.0 + 34.0)
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
      ).with_part(hip_part),
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
      ).with_part(hip_part),
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
  // A compact low-KV BLDC + planetary actuator drives the hip abduction.
  hip = add_pod_geometry(
    hip,
    hip_name + "_actuator_geometry",
    actuator_pod_geometry(
      prefix + "_hip_actuator",
      preset="5010_360kv",
      ring_outer_mm=26.0,
      gear_length_mm=8.0,
      detail~,
    ),
    axis="x",
    y_mm=sign * hip_offset_y_mm,
  )
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
  let mut thigh = robot_leg_segment(
    thigh_name,
    length_mm=thigh_length_mm,
    detail~,
  )
  // Hip-pitch actuator at the thigh's proximal joint.
  thigh = add_pod_geometry(
    thigh,
    thigh_name + "_actuator_geometry",
    actuator_pod_geometry(
      prefix + "_thigh_actuator",
      preset="5010_360kv",
      ring_outer_mm=26.0,
      gear_length_mm=8.0,
      detail~,
    ),
    axis="y",
    y_mm=sign * (leg_width_mm / 2.0),
  )
  // Knee actuator at the calf's proximal joint.
  calf = add_pod_geometry(
    calf,
    calf_name + "_knee_actuator_geometry",
    actuator_pod_geometry(
      prefix + "_knee_actuator",
      preset="5010_360kv",
      ring_outer_mm=26.0,
      gear_length_mm=8.0,
      detail~,
    ),
    axis="y",
    y_mm=-sign * (leg_width_mm / 2.0 + 18.0),
  )
  // Wheel-drive actuator at the calf's distal end.
  calf = add_pod_geometry(
    calf,
    calf_name + "_wheel_actuator_geometry",
    actuator_pod_geometry(
      prefix + "_wheel_actuator",
      preset="5010_360kv",
      ring_outer_mm=26.0,
      gear_length_mm=8.0,
      detail~,
    ),
    axis="y",
    y_mm=calf_to_wheel_mm - sign * 64.0,
    z_mm=-calf_length_mm,
  )
  let wheel = treaded_wheel(
    wheel_name,
    radius_mm=wheel_diam_mm / 2.0,
    hub_bore_mm=8.0,
    hub_bolt_circle_mm=20.0,
    detail~,
  )
  let foot_part = fabricated_part(
    "FOOT-\{wheel_diam_mm}",
    "Rubber foot pad",
    "TPU",
    "3D print",
    4.0,
  )
  let foot = @cad.Component::new(
      prefix + "_foot_link",
      description="Rubber foot link",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        prefix + "_foot",
        wheel_diam_mm * 0.42,
        40.0,
        z_mm=-calf_length_mm - 20.0,
        density=@urdf.Density::tpu(),
        color=@step_cad.Rgb::black(),
      ).with_part(foot_part),
    )
    .add_mate_mm_deg("mount")
  let (distal, distal_joint_name, distal_child, distal_spec, distal_offset) = if wheeled {
    (
      wheel,
      "\{prefix}_wheel_joint",
      "axle",
      @cad.JointSpec::continuous(
        limit=Some(
          @urdf.JointLimit::new(
            effort=max_effort_nm * 0.45,
            velocity=max_vel_rad_s * 1.6,
          ),
        ),
        offset_mm=calf_to_wheel_mm,
        transmission_reduction=Some(1.0),
      ),
      calf_to_wheel_mm,
    )
  } else {
    (foot, "\{prefix}_ankle_joint", "mount", @cad.JointSpec::fixed(), 0.0)
  }
  let _ = distal_offset
  let calf_with_wheel = calf.attach(
    distal_joint_name,
    parent_mate="distal_joint",
    distal,
    child_mate=distal_child,
    spec=distal_spec,
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
        effort=max_effort_nm * 1.2,
        velocity=max_vel_rad_s * 0.85,
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
        effort=max_effort_nm,
        velocity=max_vel_rad_s,
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
    .add_mate_mm_deg("spring_seat", y=half_span * 0.6, z=fork_length_mm * 0.55)
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

///|
/// Recursively collects a component tree's bodies into one frame.
///
/// Each attachment is resolved with its mate pair (the same snap used by the
/// URDF compiler), so the flattened bodies keep their exact assembled
/// positions while dropping the kinematic links. A component-level part is
/// applied to every body that has no part of its own.
fn flatten_bodies_into(
  comp : @cad.Component,
  xform : @urdf.Transform,
  out : Array[@cad.BodyPart],
) -> Unit {
  for body in comp.bodies {
    let placed = body.transform_by(xform)
    let with_part = match comp.part {
      Some(part) =>
        match placed.part {
          Some(_) => placed
          None => placed.with_part(part)
        }
      None => placed
    }
    out.push(with_part)
  }
  for att in comp.attachments {
    let pair = att.spec.pair
    let p_mate = comp.mates
      .get(pair.parent)
      .unwrap_or(@step_common.MateConnector::new(pair.parent))
    let c_mate = att.child.mates
      .get(pair.child)
      .unwrap_or(@step_common.MateConnector::new(pair.child))
    let (snap, _) = @step_common.snap_connectors(
      p_mate,
      c_mate,
      offset_mm=pair.offset_mm,
      twist_rad=pair.twist_deg * @math.PI / 180.0,
      flip_axis=pair.flip_axis,
    )
    let (xyz, rpy) = @step_common.MateConnector::new("snap", placement=snap).to_m_rad()
    let snap_xform = @urdf.Transform::from_origin(@urdf.Origin::new(xyz~, rpy~))
    flatten_bodies_into(att.child, xform.compose(snap_xform), out)
  }
}

///|
/// Flattens a component tree into a geometry-only component with no joints.
///
/// This is how a multi-link actuator contributes realistic bodies and parts to
/// a link that must keep its own fixed kinematic structure (for example a
/// quadruped hip link). The root mate frames are preserved.
pub fn flattened_geometry(
  name : String,
  comp : @cad.Component,
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
  rx_deg~ : Double = 0.0,
  ry_deg~ : Double = 0.0,
  rz_deg~ : Double = 0.0,
) -> @cad.Component {
  let xform = @cad.urdf_transform_from_mm_deg(
    x_mm~,
    y_mm~,
    z_mm~,
    rx_deg~,
    ry_deg~,
    rz_deg~,
  )
  let bodies : Array[@cad.BodyPart] = []
  flatten_bodies_into(comp, xform, bodies)
  let mates : Map[String, @step_common.MateConnector] = Map([])
  mates.set("origin", @step_common.MateConnector::new("origin"))
  {
    ..comp,
    name,
    description: comp.description,
    bodies,
    attachments: [],
    mates,
    part: None,
    control: [],
    cables: [],
    wiring: [],
  }
}

///|
/// A compact printable + purchased actuator pod for a leg link.
///
/// This is the geometry that a low-KV BLDC outrunner plus planetary reduction
/// presents at a joint: a motor can, a printed planetary housing, and a printed
/// output flange. Each body carries one part number, so a quadruped's bill of
/// materials counts one motor and one housing per actuator.
pub fn actuator_pod_geometry(
  name : String,
  preset~ : String = "5010_360kv",
  ring_outer_mm~ : Double = 56.0,
  gear_length_mm~ : Double = 8.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let p = resolve_bldc_preset(preset)
  let policy = @step_common.DetailPolicy::for_level(detail)
  let motor_part = purchased_part(
    "BLDC-\{p.name}",
    "Low-KV brushless outrunner \{p.name} (\{p.kv} KV)",
    "mixed",
    p.cost_usd,
    supplier_url="https://www.hobbyking.com/",
  )
  let housing_part = fabricated_part(
    "ACT-HOUSING", "Printed planetary actuator housing", "carbon fiber nylon", "3D print",
    18.0,
  )
  let flange_part = fabricated_part(
    "ACT-OUTPUT-FLANGE", "Printed actuator output flange", "carbon fiber nylon",
    "3D print", 8.0,
  )
  let mut pod = @cad.Component::new(
      name,
      description="Planetary BLDC actuator pod",
    )
    .with_param("preset", p.name)
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_motor_can",
        p.diameter_mm,
        p.body_length_mm,
        z_mm=-p.body_length_mm / 2.0 - 6.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::black(),
      ).with_part(motor_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_housing",
        (ring_outer_mm + 4.0) * 2.0,
        (ring_outer_mm + 0.5) * 2.0,
        gear_length_mm + 12.0,
        segments=policy.circle_segments,
        z_mm=gear_length_mm / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::grey(),
      ).with_part(housing_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_flange",
        ring_outer_mm * 0.9,
        8.0,
        z_mm=gear_length_mm + 12.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::black(),
      ).with_part(flange_part),
    )
  if detail is @step_common.DetailLevel::FullyModeled {
    for i in 0..<4 {
      let theta = 2.0 * @math.PI * i.to_double() / 4.0
      // Keep the fastener B-Rep at detailed resolution so a fully modeled
      // 16-actuator quadruped stays a practical file size.
      let screw = iso_shcs_screw(
        name="\{name}_flange_screw_\{i}",
        size=@step_standards.M3,
        length_mm=8.0,
        detail=@step_common.DetailLevel::Detailed,
      )
      pod = pod.add_bodies(
        flattened_geometry(
          name + "_flange_screw_" + i.to_string(),
          screw,
          x_mm=ring_outer_mm * 0.4 * @math.cos(theta),
          y_mm=ring_outer_mm * 0.4 * @math.sin(theta),
          z_mm=gear_length_mm + 16.0,
        ).bodies,
      )
    }
  }
  pod
  .add_mate_mm_deg("mount")
  .add_mate_mm_deg("output", z=gear_length_mm + 16.0)
}

///|
/// Adds an actuator pod's bodies to a link in the given axis frame.
fn add_pod_geometry(
  comp : @cad.Component,
  name : String,
  actor : @cad.Component,
  axis~ : String = "z",
  x_mm~ : Double = 0.0,
  y_mm~ : Double = 0.0,
  z_mm~ : Double = 0.0,
) -> @cad.Component {
  let rx = if axis == "y" { 90.0 } else { 0.0 }
  let ry = if axis == "x" { 90.0 } else { 0.0 }
  let flat = flattened_geometry(
    name,
    actor,
    x_mm~,
    y_mm~,
    z_mm~,
    rx_deg=rx,
    ry_deg=ry,
  )
  comp.add_bodies(flat.bodies)
}

///|
/// A motorized wheelchair planetary wheel-drive unit.
///
/// An inexpensive heavy low-KV BLDC outrunner (`6354_190kv` by default) drives
/// a two-stage printed planetary gearbox; the output carrier turns a stepped
/// output shaft in a pair of bearings and a heavy treaded drive wheel.
pub fn planetary_wheel_drive_unit(
  name~ : String = "wheel_drive",
  preset~ : String = "6354_190kv",
  stages~ : Int32 = 2,
  module_mm~ : Double = 2.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 18,
  planet_count~ : Int32 = 3,
  gear_length_mm~ : Double = 14.0,
  gear_type~ : String = "spur",
  wheel_diam_mm~ : Double = 250.0,
  wheel_width_mm~ : Double = 50.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let actuator = planetary_bldc_actuator(
    name=name + "_drive",
    preset~,
    stages~,
    module_mm~,
    sun_teeth~,
    planet_teeth~,
    planet_count~,
    gear_length_mm~,
    gear_type~,
    detail~,
    threads?,
  )
  let wheel = treaded_wheel(
    name + "_wheel",
    radius_mm=wheel_diam_mm / 2.0,
    width_mm=wheel_width_mm,
    hub_radius_mm=wheel_diam_mm * 0.18,
    hub_bore_mm=16.0,
    detail~,
  )
  let wheel_center_z = gear_length_mm * stages.to_double() +
    (if stages >= 2 { 92.0 } else { 68.0 })
  let output = actuator
    .add_mate_mm_deg(
      "axle_output",
      z=wheel_center_z,
      rx_deg=90.0,
      axis=(0.0, 0.0, 1.0),
    )
    .attach(
      "\{name}_wheel_joint",
      parent_mate="axle_output",
      wheel,
      child_mate="axle",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=60.0, velocity=8.0)),
        transmission_reduction=Some(1.0),
      ),
    )
  output
}

///|
/// A heavy-duty wheelchair caster / steerable front fork.
///
/// Twin side plates carry a front caster wheel on a pressed bearing; the
/// steering column runs in two headset bearings with a compression spring.
pub fn caster_fork_assembly(
  name~ : String = "caster_fork",
  wheel_diam_mm~ : Double = 150.0,
  wheel_width_mm~ : Double = 32.0,
  fork_span_mm~ : Double = 90.0,
  fork_length_mm~ : Double = 150.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  threads? : @step_common.ThreadRepresentation,
) -> @cad.Component {
  let _ = threads
  let half_span = fork_span_mm / 2.0
  let plate_part = fabricated_part(
    "CASTER-PLATE", "Caster fork side plate", "6061-T6", "3D print / CNC", 7.0,
  )
  let mut fork = @cad.Component::new(name, description="Wheelchair caster fork")
    .with_param("wheel_diam_mm", wheel_diam_mm.to_string())
    .with_param("fork_length_mm", fork_length_mm.to_string())
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_plate_left",
        14.0,
        12.0,
        fork_length_mm,
        y_mm=-half_span,
        z_mm=fork_length_mm / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(plate_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_plate_right",
        14.0,
        12.0,
        fork_length_mm,
        y_mm=half_span,
        z_mm=fork_length_mm / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(plate_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_crown",
        30.0,
        fork_span_mm + 30.0,
        16.0,
        z_mm=fork_length_mm + 24.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::grey(),
      ).with_part(plate_part),
    )
    .add_mate_mm_deg("steering_axis", z=fork_length_mm + 16.0)
    .add_mate_mm_deg("front_axle", z=0.0, axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg("spring_seat", y=half_span * 0.6, z=fork_length_mm * 0.55)
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="36 V"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  // Twin headset bearings.
  for i in 0..<2 {
    let headset = ball_bearing(
      name="\{name}_headset_\{i}",
      designation="608",
      detail~,
      density=@urdf.Density::steel_mild(),
    )
    fork = fork.attach(
      "headset_merge_\{i}",
      parent_mate="steering_axis",
      headset,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  let spring = compression_spring_part(
    name=name + "_spring",
    wire_diam_mm=3.5,
    mean_diam_mm=fork_span_mm * 0.2,
    free_length_mm=fork_length_mm * 0.6,
    detail~,
  )
  fork = fork.attach(
    "spring_merge",
    parent_mate="spring_seat",
    spring,
    child_mate="bottom",
    spec=@cad.JointSpec::merge_rigid(),
  )
  let wheel = treaded_wheel(
    name + "_wheel",
    radius_mm=wheel_diam_mm / 2.0,
    width_mm=wheel_width_mm,
    hub_radius_mm=wheel_diam_mm * 0.20,
    hub_bore_mm=10.0,
    detail~,
  )
  fork.attach(
    "\{name}_wheel_joint",
    parent_mate="front_axle",
    wheel,
    child_mate="axle",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=15.0, velocity=20.0)),
      transmission_reduction=Some(1.0),
    ),
  )
}
