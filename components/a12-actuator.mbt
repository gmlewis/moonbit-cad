///|
/// Parameters for the reusable A12 8318 + single-stage herringbone planetary
/// actuator.
///
/// The outer envelope, center distance, and mate frames depend only on the
/// module, tooth counts, and lengths. `tolerance_mm` changes only the printed
/// tooth clearance, so a PETG (`0.042`) and a PLA (`0.25`) build share one
/// mechanical interface.
pub(all) struct A12ActuatorParams {
  gear_module_mm : Double
  gear_length_mm : Double
  num_elbows : Int32
  tolerance_mm : Double
  hub_offset_mm : Double
  flange_start_deg : Double
  detail : @step_common.DetailLevel
  sun_teeth : Int32
  planet_teeth : Int32
  planet_count : Int32
  name : String
  /// Optional three-hole tire-mount interface on the output hub face.
  /// Set to `55.85` to match `TIRE-MOUNT-86.3`; `0.0` disables it.
  tire_mount_bcd_mm : Double
  tire_mount_bolt_count : Int32
  tire_mount_phase_deg : Double
  tire_mount_hole_diam_mm : Double
}

///|
pub fn A12ActuatorParams::new(
  gear_module_mm~ : Double = 2.0,
  gear_length_mm~ : Double = 12.0,
  num_elbows~ : Int32 = 4,
  tolerance_mm~ : Double = @step_common.DEFAULT_GEAR_TOLERANCE_MM,
  hub_offset_mm~ : Double = 8.0,
  flange_start_deg~ : Double = 30.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Detailed,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 20,
  planet_count~ : Int32 = 4,
  name~ : String = "a12_actuator",
  tire_mount_bcd_mm~ : Double = 0.0,
  tire_mount_bolt_count~ : Int32 = 3,
  tire_mount_phase_deg~ : Double = 30.0,
  tire_mount_hole_diam_mm~ : Double = 6.0,
) -> A12ActuatorParams {
  {
    gear_module_mm,
    gear_length_mm,
    num_elbows,
    tolerance_mm,
    hub_offset_mm,
    flange_start_deg,
    detail,
    sun_teeth,
    planet_teeth,
    planet_count,
    name,
    tire_mount_bcd_mm,
    tire_mount_bolt_count,
    tire_mount_phase_deg,
    tire_mount_hole_diam_mm,
  }
}

///|
fn a12_resolution(detail : @step_common.DetailLevel) -> Int32 {
  match detail {
    @step_common.DetailLevel::Simplified => 5
    _ => 7
  }
}

///|
fn a12_layout_params(
  params : A12ActuatorParams,
  outer_thickness_mm : Double,
) -> @step_planetary.HerringbonePlanetaryParams {
  let bearing = flanged_bearing_fr8_2rs()
  match
    @step_planetary.HerringbonePlanetaryParams::new(
      module_mm=params.gear_module_mm,
      gear_length_mm=params.gear_length_mm,
      helix_angle_deg=30.0,
      pressure_angle_deg=20.0,
      num_elbows=params.num_elbows,
      resolution=a12_resolution(params.detail),
      hole_type="Circular",
      sun_hole_type="Hexagonal",
      hole_radius_mm=3.5,
      sun_hole_radius_mm=3.5,
      planet_hole_radius_mm=bearing.outer_mm / 2.0 - 0.03,
      tolerance_mm=params.tolerance_mm,
      outer_thickness_mm~,
      sun_teeth=params.sun_teeth,
      planet_count=params.planet_count,
      planet_teeth=params.planet_teeth,
    ) {
    Ok(p) => p
    Err(e) =>
      abort("invalid A12 actuator params for '\{params.name}': \{e.message()}")
  }
}

///|
/// Trial layout with the default 6 mm ring wall.
fn a12_trial_layout(
  params : A12ActuatorParams,
) -> @step_planetary.HerringbonePlanetaryLayout {
  @step_planetary.herringbone_planetary_layout(a12_layout_params(params, 6.0))
}

///|
/// Outer housing radius in millimetres. Independent of `tolerance_mm`.
pub fn A12ActuatorParams::outer_radius_mm(self : A12ActuatorParams) -> Double {
  let layout = a12_trial_layout(self)
  let min_outer_r = 55.0
  if layout.ring_outer_radius_mm > min_outer_r {
    layout.ring_outer_radius_mm
  } else {
    min_outer_r
  }
}

///|
/// Ring wall thickness required to reach the outer radius.
fn A12ActuatorParams::ring_wall_mm(self : A12ActuatorParams) -> Double {
  let layout = a12_trial_layout(self)
  let wall = self.outer_radius_mm() - layout.ring_outer_radius_mm + 6.0
  if wall < 6.0 {
    6.0
  } else {
    wall
  }
}

///|
/// Final planetary layout used for the cartridge geometry.
pub fn A12ActuatorParams::layout(
  self : A12ActuatorParams,
) -> @step_planetary.HerringbonePlanetaryLayout {
  @step_planetary.herringbone_planetary_layout(
    a12_layout_params(self, self.ring_wall_mm()),
  )
}

///|
pub fn A12ActuatorParams::center_distance_mm(
  self : A12ActuatorParams,
) -> Double {
  self.layout().center_distance_mm
}

///|
/// Output cap face to rear backplate span, in millimetres.
pub fn A12ActuatorParams::total_len_mm(self : A12ActuatorParams) -> Double {
  self.gear_length_mm + 61.0
}

///|
fn a12_circle(
  cx : Double,
  cy : Double,
  r : Double,
  segs : Int32,
) -> Array[(Double, Double)] {
  let n = if segs < 3 { 3 } else { segs }
  let out : Array[(Double, Double)] = []
  for i in 0..<n {
    let a = 2.0 * @math.PI * i.to_double() / n.to_double()
    out.push((cx + r * @math.cos(a), cy + r * @math.sin(a)))
  }
  out
}

///|
fn a12_printed(
  part_number : String,
  description : String,
  material : String,
  cost : Double,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="in-house",
    material~,
    process="3D print",
    unit_cost_usd=cost,
  )
}

///|
fn a12_purchased(
  part_number : String,
  description : String,
  material : String,
  cost : Double,
) -> @cad.PartMeta {
  @cad.PartMeta::new(
    part_number,
    description~,
    supplier="generic",
    material~,
    process="purchased",
    unit_cost_usd=cost,
  )
}

///|
fn a12_shell_color() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.76, 0.78, 0.80)
}

///|
fn a12_hub_color() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.92, 0.54, 0.14)
}

///|
fn a12_steel_color() -> @step_cad.Rgb {
  @step_cad.Rgb::new(0.55, 0.58, 0.62)
}

///|
/// Builds a reusable A12 8318 + single-stage 4-elbow planetary actuator.
///
/// Local frame: rear backplate face at `z = 0`, output cap face at
/// `total_len_mm()`, output hub outboard at
/// `total_len_mm() + hub_offset_mm + 8`.
pub fn a12_planetary_actuator(params : A12ActuatorParams) -> @cad.Component {
  let bearing = flanged_bearing_fr8_2rs()
  let layout = params.layout()
  let outer_r = params.outer_radius_mm()
  let wall = params.ring_wall_mm()
  let flange_r = outer_r + 7.5
  let flange_bcd = 2.0 * (outer_r + 3.8)
  let bolt_r = flange_bcd / 2.0
  let center_distance = layout.center_distance_mm
  let total_len = params.total_len_mm()
  let motor_z0 = 4.0
  let gear_z0 = 42.0
  let carrier_z0 = gear_z0 + params.gear_length_mm + 1.0
  let cap_z0 = carrier_z0 + 8.0
  let hub_z = total_len + params.hub_offset_mm
  let reduction = planetary_reduction(params.sun_teeth, params.planet_teeth, 1)

  let housing_part = a12_printed(
    "A12-ACT-HOUSING", "Printed A12 8318 stator cup and planetary housing", "CF nylon / PETG",
    11.0,
  )
  let adapter_part = a12_printed(
    "A12-SUN-ADAPTER", "Printed A12 prop-adapter to planetary sun coupler", "CF nylon / PETG",
    2.5,
  )
  let cartridge_part = a12_printed(
    "A12-GEAR-CARTRIDGE", "Print-in-place herringbone planetary cartridge", "PETG / PLA",
    9.5,
  )
  let carrier_part = a12_printed(
    "A12-CARRIER", "Printed planet carrier plate", "CF nylon / PETG", 5.5,
  )
  let cap_part = a12_printed(
    "A12-OUTPUT-CAP", "Printed output bearing cap", "CF nylon / PETG", 6.5,
  )
  let has_tire_mount = params.tire_mount_bcd_mm > 0.0 &&
    params.tire_mount_bolt_count > 0
  let hub_r = if has_tire_mount { 40.0 } else { 30.0 }
  let hub_part = if has_tire_mount {
    a12_printed(
      "A12-OUTPUT-HUB-80", "Printed 80 mm wheel output hub (4x M4 on 40 mm BCD + 3x M4 heat-set inserts on 55.85 mm BCD for TIRE-MOUNT-86.3)",
      "CF nylon / PETG", 4.5,
    )
  } else {
    a12_printed(
      "A12-OUTPUT-HUB", "Printed 60 mm output hub (4x M4 on 40 mm BCD)", "CF nylon / PETG",
      4.0,
    )
  }
  let bearing_part = a12_purchased(
    "BEARING-FR8-2RS", "FR8-2RS flanged sealed bearing", "steel", 1.55,
  )
  let pin_part = a12_purchased(
    "DOWEL-12.7x24", "12.7 x 24 mm hardened dowel pin", "steel", 1.5,
  )
  let shaft_part = a12_purchased(
    "SHAFT-12.7x48", "12.7 x 48 mm stainless output shaft", "steel", 6.0,
  )

  let back_holes : Array[Array[(Double, Double)]] = [
    a12_circle(0.0, 0.0, 8.0, 16),
  ]
  for i in 0..<4 {
    let a = (45.0 + 90.0 * i.to_double()) * @math.PI / 180.0
    back_holes.push(
      a12_circle(16.0 * @math.cos(a), 16.0 * @math.sin(a), 2.2, 10),
    )
  }
  let cap_holes : Array[Array[(Double, Double)]] = [
    a12_circle(0.0, 0.0, bearing.outer_mm / 2.0, 20),
  ]
  for i in 0..<6 {
    let a = (params.flange_start_deg + 60.0 * i.to_double()) * @math.PI / 180.0
    cap_holes.push(
      a12_circle(bolt_r * @math.cos(a), bolt_r * @math.sin(a), 2.2, 10),
    )
  }
  let carrier_r = center_distance + bearing.bore_mm * 0.9
  // 0.10 mm radial slip clearance on the 12.7 mm steel shaft and 0.05 mm on
  // planet dowel pins so printed PETG/CF-nylon parts assemble cleanly.
  let carrier_holes : Array[Array[(Double, Double)]] = [
    a12_circle(0.0, 0.0, 6.45, 16),
  ]
  for j in 0..<params.planet_count {
    let a = 2.0 * @math.PI * j.to_double() / params.planet_count.to_double()
    carrier_holes.push(
      a12_circle(
        center_distance * @math.cos(a),
        center_distance * @math.sin(a),
        bearing.bore_mm / 2.0 + 0.05,
        12,
      ),
    )
  }
  let hub_holes : Array[Array[(Double, Double)]] = [
    a12_circle(0.0, 0.0, 6.45, 16),
  ]
  for i in 0..<4 {
    let a = (45.0 + 90.0 * i.to_double()) * @math.PI / 180.0
    hub_holes.push(
      a12_circle(20.0 * @math.cos(a), 20.0 * @math.sin(a), 2.2, 10),
    )
  }
  if has_tire_mount {
    let tm_r = params.tire_mount_bcd_mm / 2.0
    let tm_hole_r = params.tire_mount_hole_diam_mm / 2.0
    for i in 0..<params.tire_mount_bolt_count {
      let a = (
          params.tire_mount_phase_deg +
          360.0 * i.to_double() / params.tire_mount_bolt_count.to_double()
        ) *
        @math.PI /
        180.0
      hub_holes.push(
        a12_circle(tm_r * @math.cos(a), tm_r * @math.sin(a), tm_hole_r, 12),
      )
    }
  }

  let gear_comp = match params.detail {
    @step_common.DetailLevel::Simplified => {
      // Smooth pitch-diameter planetary cartridge for fast multi-actuator
      // `--view` rendering (keeps STEP well under SolidCraft's 20M parameter
      // cap while preserving exact outer envelope, mass, and BOM). Detailed /
      // FullyModeled and standalone printable cartridges emit full 4-elbow
      // herringbone involute teeth.
      let ring_inner_d = params.gear_module_mm *
        (params.sun_teeth + 2 * params.planet_teeth).to_double()
      let sun_d = params.gear_module_mm * params.sun_teeth.to_double()
      let planet_d = params.gear_module_mm * params.planet_teeth.to_double()
      let z_mid = params.gear_length_mm / 2.0
      let mut sc = @cad.Component::new(params.name + "_planetary")
        .add_body(
          @cad.BodyPart::tube_mm(
            params.name + "_ring_simple",
            2.0 * outer_r,
            ring_inner_d,
            params.gear_length_mm,
            z_mm=z_mid,
            density=@urdf.Density::petg(),
            color=a12_shell_color(),
          ).with_part(cartridge_part),
        )
        .add_body(
          @cad.BodyPart::tube_mm(
            params.name + "_sun_simple",
            sun_d,
            7.0,
            params.gear_length_mm,
            z_mm=z_mid,
            density=@urdf.Density::petg(),
            color=a12_hub_color(),
          ),
        )
      for j in 0..<params.planet_count {
        let a = 2.0 * @math.PI * j.to_double() / params.planet_count.to_double()
        sc = sc.add_body(
          @cad.BodyPart::tube_mm(
            params.name + "_planet_simple_\{j}",
            planet_d,
            bearing.outer_mm,
            params.gear_length_mm,
            x_mm=center_distance * @math.cos(a),
            y_mm=center_distance * @math.sin(a),
            z_mm=z_mid,
            density=@urdf.Density::petg(),
            color=a12_hub_color(),
          ),
        )
      }
      sc.with_collision_cylinder_mm(
        radius_mm=outer_r,
        length_mm=params.gear_length_mm,
        z_mm=z_mid,
      )
    }
    _ => {
      let step_gb = match
        @step_planetary.herringbone_planetary_gearbox(
          a12_layout_params(params, wall),
        ) {
        Ok(c) => c
        Err(e) => abort("A12 planetary cartridge failed: " + e.message())
      }
      @cad.Component::from_step_component(
        params.name + "_planetary",
        step_gb,
        density=@urdf.Density::petg(),
        part=Some(cartridge_part),
      ).with_collision_cylinder_mm(
        radius_mm=outer_r,
        length_mm=params.gear_length_mm,
        z_mm=params.gear_length_mm / 2.0,
      )
    }
  }
  let a12_motor = step_a12_motor(
    name=params.name + "_a12",
    joint_name=params.name + "_a12_rotor_joint",
  )

  let mut act = @cad.Component::new(
      params.name,
      description="A12 8318 100KV + 4-elbow herringbone planetary actuator (\{reduction}:1)",
    )
    .with_param("motor", "A12 8318 100KV")
    .with_param("gear_module_mm", params.gear_module_mm.to_string())
    .with_param("num_elbows", params.num_elbows.to_string())
    .with_param("tolerance_mm", params.tolerance_mm.to_string())
    .with_param("reduction", reduction.to_string())
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V, 40 A"))
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .with_actuator(
      @cad.ActuatorSpec::new(
        @cad.ActuatorKind::Bldc,
        model="A12 8318 100KV + herringbone planetary",
        voltage_v=24.0,
        current_rated_a=25.0,
        current_stall_a=60.0,
        torque_rated_nm=18.0 * reduction / 5.3333,
        driver="moteus C1 / FOC",
        interface="CAN",
        encoder="AS5047P",
      ),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        params.name + "_backplate",
        a12_circle(0.0, 0.0, outer_r, 32),
        4.0,
        holes=back_holes,
        z_mm=2.0,
        density=@urdf.Density::petg(),
        color=a12_shell_color(),
      )
      .with_collisions([
        @urdf.Collision::new(
          @urdf.Geometry::cylinder_mm(outer_r, 4.0),
          name=Some(params.name + "_backplate"),
          origin=@urdf.Origin::from_mm_deg(z=2.0),
        ),
      ])
      .with_part(housing_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        params.name + "_barrel",
        2.0 * outer_r,
        94.0,
        gear_z0 - motor_z0,
        z_mm=motor_z0 + (gear_z0 - motor_z0) / 2.0,
        density=@urdf.Density::petg(),
        color=a12_shell_color(),
      ).with_part(housing_part),
    )
    .add_body(
      // Bolted 4xM4 (23 mm BCD) rotor-to-sun flange + integral 6.7 mm
      // across-flats hexagonal drive post engaging the sun gear's 7.0 mm hex
      // bore (zero slip under full A12 torque).
      {
        let prop_r = 11.5
        let flange_holes : Array[(Double, Double, Double)] = []
        for i in 0..<4 {
          let theta = 2.0 * @math.PI * i.to_double() / 4.0
          flange_holes.push(
            (prop_r * @math.cos(theta), prop_r * @math.sin(theta), 4.3),
          )
        }
        let flange = actuator_plate_body(
          params.name + "_sun_adapter",
          34.0,
          5.0,
          gear_z0 - 5.0,
          flange_holes,
          @urdf.Density::petg(),
          a12_hub_color(),
          params.detail,
        )
        let hex_post = hex_prism_body_mm(
          params.name + "_sun_adapter_hex_post",
          3.35,
          params.gear_length_mm - 0.5,
          gear_z0,
          @urdf.Density::petg(),
          a12_hub_color(),
        )
        {
          ..flange,
          node: @step_cad.union_all(
            [flange.node, hex_post.node],
            name=params.name + "_sun_adapter",
          ).with_color(a12_hub_color()),
        }.with_part(adapter_part)
      },
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        params.name + "_carrier",
        a12_circle(0.0, 0.0, carrier_r, 28),
        8.0,
        holes=carrier_holes,
        z_mm=carrier_z0 + 4.0,
        density=@urdf.Density::petg(),
        color=a12_hub_color(),
      )
      .with_collisions([
        @urdf.Collision::new(
          @urdf.Geometry::cylinder_mm(carrier_r, 8.0),
          name=Some(params.name + "_carrier"),
          origin=@urdf.Origin::from_mm_deg(z=carrier_z0 + 4.0),
        ),
      ])
      .with_part(carrier_part),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        params.name + "_output_cap",
        a12_circle(0.0, 0.0, flange_r, 32),
        10.0,
        holes=cap_holes,
        z_mm=cap_z0 + 5.0,
        density=@urdf.Density::petg(),
        color=a12_shell_color(),
      )
      .with_collisions([
        @urdf.Collision::new(
          @urdf.Geometry::cylinder_mm(flange_r, 10.0),
          name=Some(params.name + "_output_cap"),
          origin=@urdf.Origin::from_mm_deg(z=cap_z0 + 5.0),
        ),
      ])
      .with_part(cap_part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        params.name + "_out_bearing",
        bearing.outer_mm,
        bearing.bore_mm,
        bearing.width_mm,
        z_mm=cap_z0 + 5.0,
        density=@urdf.Density::steel_mild(),
        color=a12_steel_color(),
      ).with_part(bearing_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        params.name + "_output_shaft",
        12.7,
        26.0 + params.hub_offset_mm,
        z_mm=carrier_z0 + (26.0 + params.hub_offset_mm) / 2.0,
        density=@urdf.Density::steel_mild(),
        color=a12_steel_color(),
      ).with_part(shaft_part),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        params.name + "_output_hub",
        a12_circle(0.0, 0.0, hub_r, 32),
        8.0,
        holes=hub_holes,
        z_mm=hub_z + 4.0,
        density=@urdf.Density::petg(),
        color=a12_hub_color(),
      )
      .with_collisions([
        @urdf.Collision::new(
          @urdf.Geometry::cylinder_mm(hub_r, 8.0),
          name=Some(params.name + "_output_hub"),
          origin=@urdf.Origin::from_mm_deg(z=hub_z + 4.0),
        ),
      ])
      .with_part(hub_part),
    )
    .add_mate_mm_deg("a12_mount", z=motor_z0, axis=(0.0, 0.0, -1.0))
    .attach(
      params.name + "_a12_mount",
      parent_mate="a12_mount",
      a12_motor,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
    .add_mate_mm_deg("gear_seat", z=gear_z0)
    .attach(
      params.name + "_gears_mount",
      parent_mate="gear_seat",
      gear_comp,
      spec=@cad.JointSpec::merge_rigid(),
    )

  for j in 0..<params.planet_count {
    let a = 2.0 * @math.PI * j.to_double() / params.planet_count.to_double()
    let px = center_distance * @math.cos(a)
    let py = center_distance * @math.sin(a)
    act = act
      .add_body(
        @cad.BodyPart::tube_mm(
          params.name + "_planet_bearing_" + j.to_string(),
          bearing.outer_mm,
          bearing.bore_mm,
          bearing.width_mm,
          x_mm=px,
          y_mm=py,
          z_mm=gear_z0 + params.gear_length_mm / 2.0,
          density=@urdf.Density::steel_mild(),
          color=a12_steel_color(),
        ).with_part(bearing_part),
      )
      .add_body(
        @cad.BodyPart::cylinder_mm(
          params.name + "_planet_pin_" + j.to_string(),
          bearing.bore_mm,
          params.gear_length_mm + 9.0,
          x_mm=px,
          y_mm=py,
          z_mm=gear_z0 + (params.gear_length_mm + 9.0) / 2.0,
          density=@urdf.Density::steel_mild(),
          color=a12_steel_color(),
        ).with_part(pin_part),
      )
  }

  let stator_holes = @step_cad.HolePattern::bolt_circle(
    count=4,
    bcd_mm=32.0,
    hole_diam_mm=4.4,
    start_deg=45.0,
  )
  let output_holes = @step_cad.HolePattern::bolt_circle(
    count=4,
    bcd_mm=40.0,
    hole_diam_mm=4.4,
    pilot_diam_mm=12.7,
    start_deg=45.0,
  )
  let flange_holes = @step_cad.HolePattern::bolt_circle(
    count=6,
    bcd_mm=flange_bcd,
    hole_diam_mm=4.4,
    start_deg=params.flange_start_deg,
  )
  let mut result = act
    .add_mate(
      @step_common.MateConnector::from_mm_deg(
        "housing_flange",
        z=0.0,
        axis=(0.0, 0.0, -1.0),
        kind=@step_common.MateKind::PlaneFace,
        hole_pattern=stator_holes,
        description="A12 stator mounting face",
      ),
    )
    .add_mate(
      @step_common.MateConnector::from_mm_deg(
        "motor_rear",
        z=0.0,
        axis=(0.0, 0.0, -1.0),
        kind=@step_common.MateKind::PlaneFace,
        hole_pattern=stator_holes,
        description="Rear motor/controller mounting face",
      ),
    )
    .add_mate(
      @step_common.MateConnector::from_mm_deg(
        "output_hub",
        z=hub_z + 8.0,
        axis=(0.0, 0.0, 1.0),
        kind=@step_common.MateKind::CylindricalShaft,
        diameter_mm=12.7,
        hole_pattern=output_holes,
        description="Outboard 4x M4 output flange",
      ),
    )
    .add_mate(
      @step_common.MateConnector::from_mm_deg(
        "mount_flange",
        z=total_len,
        axis=(0.0, 0.0, 1.0),
        kind=@step_common.MateKind::PlaneFace,
        hole_pattern=flange_holes,
        description="Output cap flange face",
      ),
    )
  if has_tire_mount {
    let tm_holes = @step_cad.HolePattern::bolt_circle(
      count=params.tire_mount_bolt_count,
      bcd_mm=params.tire_mount_bcd_mm,
      hole_diam_mm=params.tire_mount_hole_diam_mm,
      pilot_diam_mm=12.7,
      start_deg=params.tire_mount_phase_deg,
    )
    result = result.add_mate(
      @step_common.MateConnector::from_mm_deg(
        "tire_mount",
        z=hub_z + 8.0,
        ry_deg=90.0,
        axis=(1.0, 0.0, 0.0),
        kind=@step_common.MateKind::PlaneFace,
        diameter_mm=2.0 * hub_r,
        hole_pattern=tm_holes,
        description="Flush tire-mount face matching TIRE-MOUNT-86.3 front-face",
      ),
    )
  }
  result
}
