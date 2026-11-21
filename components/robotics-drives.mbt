///|
/// Non-coaxial, limited-travel, linear, and 2-DOF robotics drive components:
///
/// - `capstan_drive_component`: zero-backlash backdrivable cable drive
/// - `worm_drive_component`: 90-deg right-angle self-locking worm gear drive
/// - `bevel_differential_component`: 2-motor, 2-DOF pitch/roll differential
/// - `timing_belt_drive_component`: parallel-axis backdrivable belt stage
/// - `ball_screw_actuator_component`: rotary-to-linear ball/lead-screw actuator

///|
/// Builds a URDF+STEP capstan / cable drive `@cad.Component` with input and
/// output revolute joints coupled by the exact cable pitch ratio and bounded
/// to `[-travel_deg/2, +travel_deg/2]`.
pub fn capstan_drive_component(
  name~ : String = "capstan_drive",
  capstan_radius_mm~ : Double = 8.0,
  driven_radius_mm~ : Double = 48.0,
  cable_diameter_mm~ : Double = 1.5,
  drum_width_mm~ : Double = 16.0,
  travel_deg~ : Double = 180.0,
  clearance_mm~ : Double = 4.0,
  crossed~ : Bool = false,
) -> @cad.Component {
  let params = match
    @step_capstan.CapstanParams::new(
      capstan_radius_mm~,
      driven_radius_mm~,
      cable_diameter_mm~,
      drum_width_mm~,
      travel_deg~,
      clearance_mm~,
      crossed~,
    ) {
    Ok(p) => p
    Err(e) => abort("capstan_drive_component: \{e.message()}")
  }
  let layout = @step_capstan.capstan_layout(params)
  let step_comp = expect_step(name, @step_capstan.capstan_drive(params))
  let frame_part = fabricated_part(
    "CAP-FRAME", "Capstan cable drive mounting frame", "carbon fiber nylon", "3D print",
    8.0,
  )
  let cap_part = fabricated_part(
    "CAP-INPUT-DRUM",
    "Capstan input drum (r=\{capstan_radius_mm} mm)",
    "carbon fiber nylon",
    "3D print",
    3.0,
  )
  let out_part = fabricated_part(
    "CAP-DRIVEN-DRUM",
    "Capstan driven drum (r=\{driven_radius_mm} mm, travel=\{travel_deg} deg)",
    "carbon fiber nylon",
    "3D print",
    6.0,
  )
  let cable_part = fabricated_part(
    "CAP-CABLE",
    "Tensioned steel / Dyneema drive cable (d=\{cable_diameter_mm} mm)",
    "stainless steel wire rope",
    "purchased",
    2.0,
  )
  let c = layout.center_distance_mm
  let mut frame = @cad.Component::new(
      name + "_frame",
      description="Capstan cable drive base frame",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_base_bar",
        c + 24.0,
        24.0,
        6.0,
        x_mm=c / 2.0,
        z_mm=-4.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::black(),
      ).with_part(frame_part),
    )
    .add_body(
      stage_step_layer_body(
        name + "_capstan_cable_1",
        step_comp,
        "cable-strand-1",
        cable_part,
        @step_cad.Rgb::new(0.75, 0.78, 0.82),
      ),
    )
    .add_body(
      stage_step_layer_body(
        name + "_capstan_cable_2",
        step_comp,
        "cable-strand-2",
        cable_part,
        @step_cad.Rgb::new(0.75, 0.78, 0.82),
      ),
    )
    .add_mate_mm_deg("input_mount")
    .add_mate_mm_deg("output_mount", x=c)
    .with_param("drive_type", "capstan")
    .with_param("reduction", layout.reduction_ratio.to_string())
    .with_param("signed_reduction", layout.signed_reduction.to_string())
    .with_param("travel_deg", travel_deg.to_string())
    .with_param("required_wraps", layout.required_wraps.to_string())
    .with_param("efficiency", layout.efficiency.to_string())
    .with_part(frame_part)
  let capstan_drum = @cad.Component::new(
      name + "_input",
      description="Capstan input drum",
    )
    .add_body(
      stage_step_layer_body(
        name + "_capstan_drum",
        step_comp,
        "capstan-drum",
        cap_part,
        @step_cad.Rgb::orange(),
      ),
    )
    .add_mate_mm_deg("origin")
    .with_part(cap_part)
  let raw_driven = stage_step_layer_body(
    name + "_capstan_driven_drum",
    step_comp,
    "driven-drum",
    out_part,
    @step_cad.Rgb::blue(),
  )
  // Shift driven drum back to its own local joint origin (0, 0, 0).
  let driven_drum = @cad.Component::new(
      name + "_output",
      description="Capstan driven output drum",
    )
    .add_body({ ..raw_driven, node: raw_driven.node.translate(x=-c), })
    .add_mate_mm_deg("origin")
    .with_part(out_part)
  let half_out_rad = travel_deg * @math.PI / 360.0
  let half_in_rad = half_out_rad * layout.reduction_ratio
  let in_joint = name + "_input_joint"
  let out_joint = name + "_output_joint"
  frame = frame
    .attach(
      in_joint,
      parent_mate="input_mount",
      capstan_drum,
      child_mate="origin",
      spec=@cad.JointSpec::revolute(
        @urdf.JointLimit::new(
          lower=Some(-half_in_rad),
          upper=Some(half_in_rad),
          effort=15.0,
          velocity=40.0,
        ),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.01, friction=0.005)),
      ),
    )
    .attach(
      out_joint,
      parent_mate="output_mount",
      driven_drum,
      child_mate="origin",
      spec=@cad.JointSpec::revolute(
        @urdf.JointLimit::new(
          lower=Some(-half_out_rad),
          upper=Some(half_out_rad),
          effort=80.0,
          velocity=10.0,
        ),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
        mimic=Some(
          @urdf.JointMimic::new(
            in_joint,
            multiplier=1.0 / layout.signed_reduction,
          ),
        ),
      ),
    )
    .with_param("command_joint", in_joint)
    .with_param("output_joint", out_joint)
  frame
}

///|
/// Builds a URDF+STEP 90° right-angle worm gear drive `@cad.Component` with
/// orthogonal `+X` worm input and `+Z` wheel output joints coupled by `1 / R`.
pub fn worm_drive_component(
  name~ : String = "worm_drive",
  module_mm~ : Double = 2.0,
  worm_starts~ : Int32 = 1,
  wheel_teeth~ : Int32 = 30,
  worm_pitch_radius_mm~ : Double = 10.0,
  friction_coeff~ : Double = 0.15,
) -> @cad.Component {
  let params = match
    @step_worm.WormGearParams::new(
      module_mm~,
      worm_starts~,
      wheel_teeth~,
      worm_pitch_radius_mm~,
      friction_coeff~,
    ) {
    Ok(p) => p
    Err(e) => abort("worm_drive_component: \{e.message()}")
  }
  let layout = @step_worm.worm_gear_layout(params)
  let step_comp = expect_step(name, @step_worm.worm_gear_drive(params))
  let housing_part = fabricated_part(
    "WORM-HOUSING", "Right-angle worm gear housing", "carbon fiber nylon", "3D print",
    10.0,
  )
  let worm_part = fabricated_part(
    "WORM-SHAFT",
    "Worm input shaft (z1=\{worm_starts}, m=\{module_mm})",
    "steel",
    "machined",
    8.0,
  )
  let wheel_part = fabricated_part(
    "WORM-WHEEL",
    "Worm output wheel (z2=\{wheel_teeth}, m=\{module_mm})",
    "bronze / carbon fiber nylon",
    "3D print",
    8.0,
  )
  let a = layout.center_distance_mm
  let worm_z = params.wheel_width_mm / 2.0
  let mut housing = @cad.Component::new(
      name + "_housing",
      description="90-degree right-angle worm gear housing",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_base_plate",
        40.0,
        a + 30.0,
        6.0,
        y_mm=-a / 2.0,
        z_mm=-4.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::black(),
      ).with_part(housing_part),
    )
    .add_mate_mm_deg("worm_mount", y=-a, z=worm_z, ry_deg=90.0)
    .add_mate_mm_deg("wheel_mount")
    .with_param("drive_type", "worm")
    .with_param("reduction", layout.reduction_ratio.to_string())
    .with_param("lead_angle_deg", layout.lead_angle_deg.to_string())
    .with_param("self_locking", layout.is_self_locking.to_string())
    .with_param("efficiency", layout.efficiency.to_string())
    .with_part(housing_part)
  // Worm input rotates about its local +Z (which is +X in housing via ry_deg=90).
  let worm_core = @cad.BodyPart::cylinder_mm(
    name + "_worm_shaft",
    2.0 * (params.worm_pitch_radius_mm - 1.25 * params.module_mm),
    params.worm_length_mm,
    density=@urdf.Density::steel_mild(),
    color=@step_cad.Rgb::orange(),
  ).with_part(worm_part)
  let worm_comp = @cad.Component::new(
      name + "_worm",
      description="Worm input shaft",
    )
    .add_body(worm_core)
    .add_mate_mm_deg("origin")
    .with_part(worm_part)
  let wheel_body = stage_step_layer_body(
    name + "_worm_wheel",
    step_comp,
    "wheel",
    wheel_part,
    @step_cad.Rgb::blue(),
  )
  let wheel_comp = @cad.Component::new(
      name + "_wheel",
      description="Worm output wheel",
    )
    .add_body(wheel_body)
    .add_mate_mm_deg("origin")
    .with_part(wheel_part)
  let in_joint = name + "_worm_joint"
  let out_joint = name + "_wheel_joint"
  housing = housing
    .attach(
      in_joint,
      parent_mate="worm_mount",
      worm_comp,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=15.0, velocity=50.0)),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.05, friction=0.04)),
      ),
    )
    .attach(
      out_joint,
      parent_mate="wheel_mount",
      wheel_comp,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=100.0, velocity=5.0)),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.1, friction=0.08)),
        mimic=Some(
          @urdf.JointMimic::new(
            in_joint,
            multiplier=1.0 / layout.reduction_ratio,
          ),
        ),
      ),
    )
    .with_param("command_joint", in_joint)
    .with_param("output_joint", out_joint)
  housing
}

///|
/// Builds a URDF+STEP 2-motor, 2-DOF bevel differential wrist/ankle/hip
/// `@cad.Component` with left/right motor input joints (`motor_a_joint`,
/// `motor_b_joint`), a pitch spider joint (`pitch_joint`), and an orthogonal
/// output roll joint (`roll_joint`).
pub fn bevel_differential_component(
  name~ : String = "bevel_differential",
  module_mm~ : Double = 2.0,
  input_teeth~ : Int32 = 20,
  output_teeth~ : Int32 = 20,
  face_width_mm~ : Double = 8.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let params = match
    @step_differential.BevelDifferentialParams::new(
      module_mm~,
      input_teeth~,
      output_teeth~,
      face_width_mm~,
    ) {
    Ok(p) => p
    Err(e) => abort("bevel_differential_component: \{e.message()}")
  }
  let layout = @step_differential.bevel_differential_layout(params)
  let step_comp = expect_step(
    name,
    @step_differential.bevel_differential(params, detail~),
  )
  let yoke_part = fabricated_part(
    "DIFF-YOKE", "2-DOF bevel differential mounting yoke", "carbon fiber nylon",
    "3D print", 10.0,
  )
  let bevel_part = fabricated_part(
    "DIFF-BEVEL",
    "Bevel differential gear (m=\{module_mm}, Zin=\{input_teeth}, Zout=\{output_teeth})",
    "carbon fiber nylon",
    "3D print",
    5.0,
  )
  let spider_part = fabricated_part(
    "DIFF-SPIDER", "2-DOF differential pitch spider carrier", "carbon fiber nylon",
    "3D print", 6.0,
  )
  let off_x = layout.input_apex_offset_mm
  let off_z = layout.output_apex_offset_mm
  let mut yoke = @cad.Component::new(
      name + "_yoke",
      description="2-DOF bevel differential base yoke",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_yoke_base",
        2.0 * off_x + 24.0,
        20.0,
        6.0,
        z_mm=-off_z - 12.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::black(),
      ).with_part(yoke_part),
    )
    .add_mate_mm_deg("motor_a_mount", x=-off_x, ry_deg=90.0)
    .add_mate_mm_deg("motor_b_mount", x=off_x, ry_deg=-90.0)
    .add_mate_mm_deg("pitch_mount", ry_deg=90.0)
    .with_param("drive_type", "bevel_differential")
    .with_param("roll_ratio", layout.roll_ratio.to_string())
    .with_part(yoke_part)
  let input_a = @cad.Component::new(
      name + "_bevel_a",
      description="Left motor input bevel gear",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_bevel_a_body",
        2.0 * layout.input_pitch_radius_mm,
        face_width_mm,
        z_mm=face_width_mm / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::orange(),
      ).with_part(bevel_part),
    )
    .add_mate_mm_deg("origin")
    .with_part(bevel_part)
  let input_b = @cad.Component::new(
      name + "_bevel_b",
      description="Right motor input bevel gear",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_bevel_b_body",
        2.0 * layout.input_pitch_radius_mm,
        face_width_mm,
        z_mm=face_width_mm / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::new(0.90, 0.40, 0.10),
      ).with_part(bevel_part),
    )
    .add_mate_mm_deg("origin")
    .with_part(bevel_part)
  let output_comp = @cad.Component::new(
      name + "_output_bevel",
      description="2-DOF differential output bevel gear and shaft",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_bevel_output_body",
        2.0 * layout.output_pitch_radius_mm,
        face_width_mm,
        z_mm=-face_width_mm / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::blue(),
      ).with_part(bevel_part),
    )
    .add_mate_mm_deg("origin")
    .with_part(bevel_part)
  let spider_body = stage_step_layer_body(
    name + "_differential_spider",
    step_comp,
    "pitch-spider",
    spider_part,
    @step_cad.Rgb::grey(),
  )
  let mut spider = @cad.Component::new(
      name + "_spider",
      description="2-DOF differential pitch spider",
    )
    .add_body(spider_body)
    .add_mate_mm_deg("origin")
    .add_mate_mm_deg("roll_mount", x=-off_z, ry_deg=-90.0)
    .with_part(spider_part)
  let roll_joint = name + "_roll_joint"
  spider = spider.attach(
    roll_joint,
    parent_mate="roll_mount",
    output_comp,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=30.0, velocity=20.0)),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
    ),
  )
  let pitch_joint = name + "_pitch_joint"
  yoke = yoke
    .attach(
      name + "_motor_a_joint",
      parent_mate="motor_a_mount",
      input_a,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=20.0, velocity=30.0)),
      ),
    )
    .attach(
      name + "_motor_b_joint",
      parent_mate="motor_b_mount",
      input_b,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=20.0, velocity=30.0)),
      ),
    )
    .attach(
      pitch_joint,
      parent_mate="pitch_mount",
      spider,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=40.0, velocity=20.0)),
      ),
    )
    .with_param("pitch_joint", pitch_joint)
    .with_param("roll_joint", roll_joint)
  yoke
}

///|
/// Builds a parallel-axis backdrivable timing-belt drive `@cad.Component`
/// wrapping `gmlewis/step/components/mechanisms::belt_loop_unequal`.
pub fn timing_belt_drive_component(
  name~ : String = "timing_belt_drive",
  driver_pitch_diam_mm~ : Double = 16.0,
  driven_pitch_diam_mm~ : Double = 48.0,
  center_distance_mm~ : Double = 70.0,
  belt_width_mm~ : Double = 9.0,
) -> @cad.Component {
  let ratio = driven_pitch_diam_mm / driver_pitch_diam_mm
  let belt_step = expect_step(
    name + "_belt",
    @step_mechanisms.belt_loop_unequal(
      driver_pitch_diam_mm, driven_pitch_diam_mm, center_distance_mm, belt_width_mm,
      1.5,
    ),
  )
  let frame_part = fabricated_part(
    "BELT-FRAME", "Timing belt parallel-axis frame", "carbon fiber nylon", "3D print",
    6.0,
  )
  let belt_part = fabricated_part(
    "BELT-GT2",
    "Closed-loop GT2 timing belt (width \{belt_width_mm} mm)",
    "neoprene / fiberglass",
    "purchased",
    4.0,
  )
  let pulley_part = fabricated_part(
    "PULLEY-GT2", "GT2 timing pulley", "aluminum / 3D print", "purchased", 3.0,
  )
  let belt_comp = @cad.Component::from_step_component(
    name + "_belt",
    belt_step,
    density=@urdf.Density::petg(),
    include_connectors=false,
  ).with_part(belt_part)
  let mut frame = @cad.Component::new(
      name + "_frame",
      description="Parallel-axis timing belt stage",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_bridge",
        center_distance_mm + 20.0,
        20.0,
        5.0,
        x_mm=center_distance_mm / 2.0,
        z_mm=-4.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::black(),
      ).with_part(frame_part),
    )
    .attach(
      name + "_belt_merge",
      parent_mate="origin",
      belt_comp,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
    .add_mate_mm_deg("driver_mount")
    .add_mate_mm_deg("driven_mount", x=center_distance_mm)
    .with_param("drive_type", "timing_belt")
    .with_param("reduction", ratio.to_string())
    .with_param("efficiency", "0.95")
    .with_part(frame_part)
  let driver = @cad.Component::new(
      name + "_driver_pulley",
      description="Driver timing pulley",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_driver_pulley_body",
        driver_pitch_diam_mm,
        belt_width_mm + 2.0,
        z_mm=(belt_width_mm + 2.0) / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::orange(),
      ).with_part(pulley_part),
    )
    .add_mate_mm_deg("origin")
    .with_part(pulley_part)
  let driven = @cad.Component::new(
      name + "_driven_pulley",
      description="Driven timing pulley",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_driven_pulley_body",
        driven_pitch_diam_mm,
        belt_width_mm + 2.0,
        z_mm=(belt_width_mm + 2.0) / 2.0,
        density=@urdf.Density::aluminum_6061(),
        color=@step_cad.Rgb::blue(),
      ).with_part(pulley_part),
    )
    .add_mate_mm_deg("origin")
    .with_part(pulley_part)
  let in_joint = name + "_driver_joint"
  let out_joint = name + "_driven_joint"
  frame = frame
    .attach(
      in_joint,
      parent_mate="driver_mount",
      driver,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=15.0, velocity=60.0)),
      ),
    )
    .attach(
      out_joint,
      parent_mate="driven_mount",
      driven,
      child_mate="origin",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=45.0, velocity=20.0)),
        mimic=Some(@urdf.JointMimic::new(in_joint, multiplier=1.0 / ratio)),
      ),
    )
    .with_param("command_joint", in_joint)
    .with_param("output_joint", out_joint)
  frame
}

///|
/// Builds a rotary-to-linear ball/lead-screw actuator `@cad.Component`
/// wrapping `gmlewis/step/components/mechanisms::lead_screw` and
/// `lead_screw_nut`, coupling the rotary screw joint to a prismatic carriage
/// joint via exact mimic `multiplier = lead_m / (2 * pi)`.
pub fn ball_screw_actuator_component(
  name~ : String = "ball_screw_actuator",
  screw_diameter_mm~ : Double = 8.0,
  screw_length_mm~ : Double = 150.0,
  lead_mm~ : Double = 4.0,
  stroke_mm~ : Double = 100.0,
) -> @cad.Component {
  let screw_step = expect_step(
    name + "_screw",
    @step_mechanisms.lead_screw(screw_diameter_mm, screw_length_mm, lead_mm~),
  )
  let nut_step = expect_step(
    name + "_nut",
    @step_mechanisms.lead_screw_nut(
      screw_diameter_mm + 6.0,
      14.0,
      screw_diameter_mm + 16.0,
      3.5,
      screw_diameter_mm,
      lead_mm,
    ),
  )
  let housing_part = fabricated_part(
    "BALLSCREW-HOUSING", "Ball/lead-screw linear actuator end block", "aluminum / 3D print",
    "3D print", 8.0,
  )
  let screw_part = fabricated_part(
    "BALLSCREW-SHAFT",
    "Ball/lead screw (d=\{screw_diameter_mm} mm, lead=\{lead_mm} mm, L=\{screw_length_mm} mm)",
    "hardened steel",
    "purchased",
    14.0,
  )
  let nut_part = fabricated_part(
    "BALLSCREW-NUT", "Ball/lead screw flanged carriage nut", "steel / brass", "purchased",
    10.0,
  )
  let screw_comp = @cad.Component::from_step_component(
      name + "_screw",
      screw_step,
      density=@urdf.Density::steel_mild(),
      include_connectors=false,
    )
    .add_mate_mm_deg("origin")
    .with_part(screw_part)
  let nut_comp = @cad.Component::from_step_component(
      name + "_nut",
      nut_step,
      density=@urdf.Density::steel_mild(),
      include_connectors=false,
    )
    .add_mate_mm_deg("origin")
    .with_part(nut_part)
  let in_joint = name + "_screw_joint"
  let out_joint = name + "_carriage_joint"
  // Exact rotary-to-linear coupling: meters of travel per radian of screw turn.
  let linear_per_rad = lead_mm / 1000.0 / (2.0 * @math.PI)
  let stroke_m = stroke_mm / 1000.0
  @cad.Component::new(
    name + "_housing",
    description="Rotary-to-linear ball/lead-screw actuator",
  )
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_end_block",
      32.0,
      32.0,
      12.0,
      z_mm=-6.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(housing_part),
  )
  .add_mate_mm_deg("screw_mount")
  .add_mate_mm_deg("carriage_mount", z=15.0)
  .attach(
    in_joint,
    parent_mate="screw_mount",
    screw_comp,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=80.0)),
    ),
  )
  .attach(
    out_joint,
    parent_mate="carriage_mount",
    nut_comp,
    child_mate="origin",
    spec=@cad.JointSpec::prismatic(
      @urdf.JointLimit::new(
        lower=Some(0.0),
        upper=Some(stroke_m),
        effort=1500.0,
        velocity=0.25,
      ),
      mimic=Some(@urdf.JointMimic::new(in_joint, multiplier=linear_per_rad)),
    ),
  )
  .with_param("drive_type", "ball_screw")
  .with_param("lead_mm", lead_mm.to_string())
  .with_param("stroke_mm", stroke_mm.to_string())
  .with_param("command_joint", in_joint)
  .with_param("output_joint", out_joint)
  .with_part(housing_part)
}
