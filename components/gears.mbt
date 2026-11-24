///|
/// Gears and planetary gearboxes.
///
/// All primitive geometry is delegated to the Tier-1 STEP primitives:
/// `@step_planetary.herringbone_planetary_gearbox` (one sun, N planets, and an
/// inward-facing ring gear, in straight exact or swept herringbone form) and
/// `@step_gears` (involute spur and internal ring gears). This package adds
/// named mates, kinematic joints (continuous sun, mimic planets and carrier),
/// purchasing/printing metadata, and printable per-part exports.

///|
/// Parameters of a planetary gearbox.
pub(all) struct PlanetaryGearboxParams {
  gear_module : Double
  gear_length_mm : Double
  helix_angle_deg : Double
  sun_teeth : Int32
  planet_teeth : Int32
  num_planets : Int32
  pressure_angle_deg : Double
  num_elbows : Int32
  resolution : Int32
  /// Sun central bore radius (the input shaft bore).
  bore_radius_mm : Double
  /// Planet central bore radius. Set this larger than the sun bore when the
  /// planets carry bearings; the Tier-1 generator now supports per-gear bores.
  planet_bore_radius_mm : Double
  /// Carrier pin diameter. Zero derives a plain pin from the planet bore.
  carrier_pin_diam_mm : Double
  /// Bearing pressed into each planet, e.g. `"688"`; empty means a plain
  /// printed bushing on the pin.
  carrier_bearing_designation : String
  /// Carrier output shaft diameter.
  output_shaft_diam_mm : Double
  /// Carrier plate thickness.
  carrier_thickness_mm : Double
  /// Carrier output shaft length above the plate.
  output_shaft_length_mm : Double
  tolerance_mm : Double
  outer_thickness_mm : Double
  include_carrier : Bool
}

///|
/// Default gearbox parameters: a fast, clean 12/12/36 tooth set with 4 planets.
pub fn PlanetaryGearboxParams::default() -> PlanetaryGearboxParams {
  {
    gear_module: 3.0,
    gear_length_mm: 30.0,
    helix_angle_deg: 30.0,
    sun_teeth: 12,
    planet_teeth: 12,
    num_planets: 4,
    pressure_angle_deg: 20.0,
    num_elbows: 2,
    resolution: 5,
    bore_radius_mm: 6.0,
    planet_bore_radius_mm: 6.0,
    carrier_pin_diam_mm: 0.0,
    carrier_bearing_designation: "",
    output_shaft_diam_mm: 8.0,
    carrier_thickness_mm: 8.0,
    output_shaft_length_mm: 12.0,
    tolerance_mm: 0.1,
    outer_thickness_mm: 10.0,
    include_carrier: true,
  }
}

///|
/// The carrier plate thickness in mm.
let pgb_carrier_thickness_mm : Double = 8.0

///|
/// The axial gap between the rotating carrier plate and the fixed ring and
/// gear faces. The carrier is mounted this far above the stage's output face.
let pgb_carrier_clearance_mm : Double = 0.5

///|
/// The carrier output boss height in mm.
let pgb_output_boss_mm : Double = 12.0

///|
/// The radial wall of the printed ring housing in mm.
let pgb_housing_wall_mm : Double = 4.0

///|
/// The axial overhang of the printed ring housing past each gear face.
let pgb_housing_overhang_mm : Double = 6.0

///|
fn pgb_sun_cost_usd() -> Double {
  5.0
}

///|
fn pgb_planet_cost_usd() -> Double {
  4.0
}

///|
fn pgb_ring_cost_usd() -> Double {
  12.0
}

///|
fn pgb_carrier_cost_usd() -> Double {
  8.0
}

///|
fn pgb_housing_cost_usd() -> Double {
  15.0
}

///|
/// Resolves the sweep elbow count. `smooth` forces exact line/arc extrusions
/// (`num_elbows = 0`), which are also glTF-safe. Otherwise the requested
/// herringbone elbow count is honored at every detail level; detail controls
/// the profile resolution, not the number of elbows.
fn pgb_elbows(
  params : PlanetaryGearboxParams,
  smooth : Bool,
  detail : @step_common.DetailLevel,
) -> Int32 {
  let _ = detail
  if smooth {
    0
  } else {
    params.num_elbows
  }
}

///|
/// Resolves the tooth-outline resolution for a detail level.
fn pgb_resolution(
  params : PlanetaryGearboxParams,
  detail : @step_common.DetailLevel,
) -> Int32 {
  let base = match detail {
    @step_common.DetailLevel::Simplified => 4
    @step_common.DetailLevel::Detailed => 6
    @step_common.DetailLevel::FullyModeled => 9
  }
  if params.resolution > base {
    params.resolution
  } else {
    base
  }
}

///|
/// Converts user parameters into validated Tier-1 gearbox parameters.
///
/// Sun and planet bores are sized independently. Each bore is only requested
/// when it fits inside that gear's root circle; otherwise the gears are
/// exported solid.
fn pgb_step_params(
  params : PlanetaryGearboxParams,
  smooth : Bool,
  detail : @step_common.DetailLevel,
) -> @step_planetary.HerringbonePlanetaryParams {
  let half = 0.5
  let dedendum = 1.25
  let sun_root = params.gear_module * params.sun_teeth.to_double() * half -
    dedendum * params.gear_module
  let planet_root = params.gear_module * params.planet_teeth.to_double() * half -
    dedendum * params.gear_module
  let planet_bore = if params.planet_bore_radius_mm > 0.0 {
    params.planet_bore_radius_mm
  } else {
    params.bore_radius_mm
  }
  let sun_hole_ok = params.bore_radius_mm > 0.0 &&
    params.bore_radius_mm < sun_root - 0.5
  let planet_hole_ok = planet_bore > 0.0 && planet_bore < planet_root - 0.5
  let (hole_type, sun_hole, planet_hole) = if sun_hole_ok && planet_hole_ok {
    ("Circular", params.bore_radius_mm, planet_bore)
  } else {
    ("None", 0.0, 0.0)
  }
  expect_step(
    "planetary gearbox parameters",
    @step_planetary.HerringbonePlanetaryParams::new(
      module_mm=params.gear_module,
      gear_length_mm=params.gear_length_mm,
      helix_angle_deg=params.helix_angle_deg,
      pressure_angle_deg=params.pressure_angle_deg,
      num_elbows=pgb_elbows(params, smooth, detail),
      resolution=pgb_resolution(params, detail),
      hole_type~,
      hole_radius_mm=sun_hole,
      sun_hole_radius_mm=sun_hole,
      planet_hole_radius_mm=planet_hole,
      tolerance_mm=params.tolerance_mm,
      outer_thickness_mm=params.outer_thickness_mm,
      sun_teeth=params.sun_teeth,
      planet_count=params.num_planets,
      planet_teeth=params.planet_teeth,
    ),
  )
}

///|
/// Orients a gear body for the Z-up print frame.
///
/// Smooth (`num_elbows = 0`) gears are already built as Z-axis arc extrusions.
/// Swept herringbone gears are built along the native +Y gear axis and need a
/// +90° rotation about X.
fn pgb_gear_body(comp : @cad.Component, smooth : Bool) -> @cad.Component {
  if smooth {
    return comp
  }
  let xform = @cad.urdf_transform_from_mm_deg(rx_deg=90.0)
  let bodies = comp.bodies.map(fn(body) { body.transform_by(xform) })
  { ..comp, bodies, }
}

///|
/// Builds a printable gearbox part with the standard gear mates.
fn pgb_gear_part(
  name : String,
  step_comp : @step_common.Component,
  layer_name : String,
  description : String,
  part_number : String,
  cost_usd : Double,
  length_mm : Double,
  smooth : Bool,
) -> @cad.Component {
  let part = fabricated_part(
    part_number, description, "PETG / carbon fiber nylon", "3D print", cost_usd,
  )
  let comp = @cad.Component::from_step_layer(
    name,
    step_comp,
    layer_name,
    density=@urdf.Density::petg(),
    include_connectors=false,
    apply_placement=false,
  )
  let bodies = comp.bodies.map(fn(body) { body.with_part(part) })
  let comp = { ..comp, bodies, }
  pgb_gear_body(comp, smooth)
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=length_mm)
  .add_mate_mm_deg("input_shaft")
}

///|
/// Builds the printed carrier plate with planet pins and an output shaft.
///
/// The pins run from the far (input) face of the planets, through the planet
/// bores, and into the carrier plate, so the planets are genuinely carried and
/// the carrier drives the output. A shoulder head at each pin's far end keeps
/// the planet from walking off. When the planets carry bearings the pin
/// diameter is the bearing bore; otherwise it is a plain bushing pin slightly
/// smaller than the planet bore.
fn pgb_carrier_component(
  name : String,
  layout : @step_planetary.HerringbonePlanetaryLayout,
  params : PlanetaryGearboxParams,
  detail : @step_common.DetailLevel,
) -> @cad.Component {
  let thickness = if params.carrier_thickness_mm >= 4.0 {
    params.carrier_thickness_mm
  } else {
    pgb_carrier_thickness_mm
  }
  let plate_radius = layout.center_distance_mm +
    layout.planet.outer_radius_mm +
    4.0
  let planet_bore_diam = params.planet_bore_radius_mm * 2.0
  // The carrier plate sits above the gear faces with a small axial gap, so the
  // rotating plate does not rub the sun, planet, or ring end faces.
  let carrier_clearance = pgb_carrier_clearance_mm
  let pin_diam = if params.carrier_pin_diam_mm > 0.0 {
    params.carrier_pin_diam_mm
  } else if planet_bore_diam > 0.4 {
    planet_bore_diam - 0.2
  } else {
    3.0
  }
  let pin_length = layout.gear_length_mm + carrier_clearance + thickness
  let shaft_diam = if params.output_shaft_diam_mm > 0.0 {
    params.output_shaft_diam_mm
  } else {
    8.0
  }
  let shaft_length = if params.output_shaft_length_mm > 0.0 {
    params.output_shaft_length_mm
  } else {
    pgb_output_boss_mm
  }
  let part = fabricated_part(
    "PGB-CARRIER",
    "Planetary carrier plate and top hub (print); drill/tap the M4 radial set-screw hole, press the 8 mm pins into the 8.1 mm holes, and fit the separate steel pins, washers, and output shaft",
    "PETG / carbon fiber nylon",
    "3D print",
    pgb_carrier_cost_usd(),
  )
  let pin_part = purchased_part(
    "DOWEL-\{pin_diam}x\{pin_length}",
    "Hardened dowel pin \{pin_diam} x \{pin_length} mm",
    "steel",
    0.80,
  )
  let washer_part = purchased_part(
    "WASHER-\{pin_diam + 6.0}x\{pin_diam + 0.2}x1",
    "Retaining washer \{pin_diam + 6.0} x \{pin_diam + 0.2} x 1 mm",
    "steel",
    0.15,
  )
  let shaft_part = purchased_part(
    "SHAFT-\{shaft_diam}x\{shaft_length}",
    "Steel carrier output shaft \{shaft_diam} x \{shaft_length} mm",
    "steel",
    2.50,
  )
  // The plate has a 22 mm central clearance hole so it cannot touch the sun
  // end face, plus real press-fit holes for the three steel pins. A raised
  // top hub bridges the central hole and carries the output shaft; a radial M4
  // set screw locks the shaft into that hub.
  let plate_holes : Array[(Double, Double, Double)] = []
  // The central clearance hole must clear the sun and stay clear of the pin
  // holes. Small modules put the planets close to the axis, so cap it.
  let central_hole = 2.0 *
    (layout.center_distance_mm - (pin_diam + 0.1) / 2.0 - 0.5)
  let central_diameter = if central_hole < 22.0 { central_hole } else { 22.0 }
  let central_diameter = if central_diameter < 12.0 {
    12.0
  } else {
    central_diameter
  }
  plate_holes.push((0.0, 0.0, central_diameter))
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    plate_holes.push((planet.x, -planet.z, pin_diam + 0.1))
  }
  let hub_diam = 32.0
  let hub_height = 4.0
  let hub_x = hub_diam / 2.0 - 6.0
  let set_screw_part = purchased_part(
    "SET-M4x12", "M4 x 12 socket set screw", "steel", 0.25,
  )
  // The printed plate is its own component so the standalone print export
  // contains only the printed body, not the steel pins or output shaft.
  let printed = @cad.Component::new(
      name + "_printed",
      description="Printed planetary carrier plate",
    )
    .with_param("plate_diameter_mm", (plate_radius * 2.0).to_string())
    .with_param("shaft_bore_mm", (shaft_diam + 0.1).to_string())
    .add_body(
      actuator_plate_body(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        0.0,
        plate_holes,
        @urdf.Density::petg(),
        @step_cad.Rgb::purple(),
        detail,
      ).with_part(part),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_plate_hub",
        hub_diam,
        shaft_diam + 0.1,
        hub_height,
        z_mm=thickness - hub_height / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::purple(),
      ).with_part(part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_hub_set_screw",
        4.0,
        12.0,
        x_mm=hub_x,
        z_mm=thickness - hub_height / 2.0,
        ry_deg=90.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(set_screw_part),
    )
    .with_part(part)
    .add_fastener(
      @cad.Fastener::new(
        "carrier_hub_set_screw",
        @cad.FastenerKind::Screw,
        thread="M4",
        length_mm=12.0,
        engagement_mm=4.0,
        quantity=1,
        torque_nm=1.5,
        references=[name + "_plate_hub"],
        part=Some(set_screw_part),
      ),
    )
  let mut comp = @cad.Component::new(
      name,
      description="Planetary carrier plate with steel planet pins and output shaft",
    )
    .with_param("center_distance_mm", layout.center_distance_mm.to_string())
    .with_param("carrier_pin_diam_mm", pin_diam.to_string())
    .with_param("carrier_thickness_mm", thickness.to_string())
    .with_param("output_shaft_diam_mm", shaft_diam.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        shaft_diam,
        thickness + shaft_length,
        z_mm=(thickness + shaft_length) / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::grey(),
      ).with_part(shaft_part),
    )
    .attach(
      "printed_carrier_merge",
      parent_mate="origin",
      printed,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    comp = comp
      .add_body(
        @cad.BodyPart::cylinder_mm(
          "\{name}_pin_\{i}",
          pin_diam,
          pin_length,
          x_mm=planet.x,
          y_mm=-planet.z,
          z_mm=(thickness - layout.gear_length_mm - carrier_clearance) / 2.0,
          density=@urdf.Density::steel_mild(),
          color=@step_cad.Rgb::grey(),
        ).with_part(pin_part),
      )
      .add_body(
        @cad.BodyPart::tube_mm(
          "\{name}_pin_washer_\{i}",
          pin_diam + 6.0,
          pin_diam + 0.2,
          1.0,
          x_mm=planet.x,
          y_mm=-planet.z,
          z_mm=-layout.gear_length_mm - carrier_clearance - 0.5,
          density=@urdf.Density::steel_mild(),
          color=@step_cad.Rgb::grey(),
        ).with_part(washer_part),
      )
      .add_mate_mm_deg(
        "pin_\{i}",
        x=planet.x,
        y=-planet.z,
        z=-layout.gear_length_mm - carrier_clearance,
        rz_deg=-planet.phi_deg,
      )
  }
  comp
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("output_flange", z=thickness)
  .add_mate_mm_deg("output_shaft", z=thickness + shaft_length)
}

///|
/// Builds the complete gearbox tree rooted at the printed ring housing.
fn pgb_build(
  name : String,
  params : PlanetaryGearboxParams,
  smooth : Bool,
  detail : @step_common.DetailLevel,
  include_housing : Bool,
  carrier_transmission_reduction~ : Double? = None,
) -> @cad.Component {
  let step_params = pgb_step_params(params, smooth, detail)
  let layout = @step_planetary.herringbone_planetary_layout(step_params)
  let step_comp = expect_step(
    "planetary gearbox",
    @step_planetary.herringbone_planetary_gearbox(step_params),
  )
  let length = layout.gear_length_mm
  let ring_name = name + "_ring_housing"
  let sun_name = name + "_sun"
  let sun_joint = name + "_sun_joint"
  let sun_root = pgb_gear_part(
    sun_name,
    step_comp,
    "sun",
    "Planetary sun gear",
    "PGB-SUN",
    pgb_sun_cost_usd(),
    length,
    smooth,
  )
  let ring_root = pgb_gear_part(
    ring_name,
    step_comp,
    "ring",
    "Planetary ring gear",
    "PGB-RING",
    pgb_ring_cost_usd(),
    length,
    smooth,
  )
  let mut comp = ring_root
    .add_mate_mm_deg("center")
    .add_mate_mm_deg(
      "input_flange",
      z=-pgb_housing_overhang_mm,
      axis=(0.0, 0.0, -1.0),
    )
    .add_mate_mm_deg("output_face", z=length)
    .add_mate_mm_deg("ring_outer_seat", axis=(1.0, 0.0, 0.0))
  if include_housing {
    let housing_part = fabricated_part(
      "PGB-HOUSING",
      "Planetary ring housing",
      "PETG / carbon fiber nylon",
      "3D print",
      pgb_housing_cost_usd(),
    )
    let inner_radius = layout.ring_outer_radius_mm + 0.5
    let outer_radius = inner_radius + pgb_housing_wall_mm
    comp = comp.add_body(
      @cad.BodyPart::tube_mm(
        ring_name + "_housing",
        outer_radius * 2.0,
        inner_radius * 2.0,
        length + 2.0 * pgb_housing_overhang_mm,
        z_mm=length / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::grey(),
      ).with_part(housing_part),
    )
  }
  comp = comp.attach(
    sun_joint,
    parent_mate="center",
    sun_root,
    child_mate="origin",
    spec=@cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=15.0, velocity=30.0)),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
      transmission_reduction=Some(1.0),
    ),
  )
  let z_sun = params.sun_teeth.to_double()
  let z_planet = params.planet_teeth.to_double()
  let z_ring = layout.ring_teeth.to_double()
  let carrier_name = "\{name}_carrier"
  // With the ring fixed and the sun driven, the carrier turns at
  // Zs / (Zs + Zr) of the sun. A planet's spin *relative to the carrier* is
  // -Zs * Zr / (Zp * (Zs + Zr)) of the sun; that relative angle is what a
  // planet joint whose parent is the carrier must mimic.
  let carrier_multiplier = z_sun / (z_sun + z_ring)
  let planet_multiplier = if params.include_carrier {
    -(z_sun * z_ring) / (z_planet * (z_sun + z_ring))
  } else {
    // Display-only fallback: with no carrier the planets are fixed-axis
    // idlers, so the simple sun/planet mesh ratio is the best available.
    -z_sun / z_planet
  }
  // The carrier must exist before the planets, because the planet pins are on
  // the carrier. Attach the carrier to the ring, then the planets to the
  // carrier, so the planets genuinely orbit with the carrier.
  let mut has_carrier = false
  if params.include_carrier {
    has_carrier = true
    let carrier = pgb_carrier_component(carrier_name, layout, params, detail)
    comp = comp.attach(
      "\{name}_carrier_joint",
      parent_mate="output_face",
      carrier,
      child_mate="bottom",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
        offset_mm=pgb_carrier_clearance_mm,
        mimic=Some(
          @urdf.JointMimic::new(sun_joint, multiplier=carrier_multiplier),
        ),
        transmission_reduction=carrier_transmission_reduction,
      ),
    )
  }
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    let planet_name = "\{name}_planet_\{i}"
    let mut planet_part = pgb_gear_part(
      planet_name,
      step_comp,
      "planet-\{i + 1}",
      "Planetary planet gear",
      "PGB-PLANET-\{planet_name}",
      pgb_planet_cost_usd(),
      length,
      smooth,
    )
    if params.carrier_bearing_designation != "" {
      let bearing = ball_bearing(
        name="\{planet_name}_bearing",
        designation=params.carrier_bearing_designation,
        detail~,
        density=@urdf.Density::steel_mild(),
      )
      let bearing_width = match
        @step_motion.bearing_size(params.carrier_bearing_designation) {
        Ok(size) => size.width_mm
        Err(_) => 5.0
      }
      planet_part = planet_part.attach(
        "\{planet_name}_bearing_merge",
        parent_mate="bottom",
        bearing,
        child_mate="origin",
        spec=@cad.JointSpec::merge_rigid(offset_mm=bearing_width / 2.0),
      )
    }
    let planet_spec = @cad.JointSpec::continuous(
      limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
      dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
      mimic=Some(@urdf.JointMimic::new(sun_joint, multiplier=planet_multiplier)),
    )
    if has_carrier {
      // The planet's bottom sits at the carrier pin's far end; the pin passes
      // through the planet bore and the planet spins about it.
      comp = comp.attach_to(
        carrier_name,
        "\{name}_planet_\{i}_joint",
        parent_mate="pin_\{i}",
        planet_part,
        child_mate="origin",
        spec=planet_spec,
      )
    } else {
      // No carrier: keep the old display-only layout with fixed orbit points.
      comp = comp.add_mate_mm_deg(
        "planet_orbit_\{i}",
        x=planet.x,
        y=-planet.z,
        rz_deg=-planet.phi_deg,
      )
      comp = comp.attach(
        "\{name}_planet_\{i}_joint",
        parent_mate="planet_orbit_\{i}",
        planet_part,
        child_mate="origin",
        spec=planet_spec,
      )
    }
  }
  comp
}

///|
/// Builds a standalone involute gear component with an optional bore.
///
/// The geometry delegates to the Tier-1 involute spur gear; the detail level
/// controls the tooth-outline resolution.
pub fn involute_gear_component(
  name : String,
  gear_module~ : Double,
  num_teeth~ : Int32,
  gear_length_mm~ : Double,
  bore_radius_mm~ : Double = 5.0,
  density~ : @urdf.Density = @urdf.Density::pla(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let gear_cost_usd = 6.0
  let (involute_points, arc_points) = match detail {
    @step_common.DetailLevel::Simplified => (4, 4)
    @step_common.DetailLevel::Detailed => (8, 8)
    @step_common.DetailLevel::FullyModeled => (16, 12)
  }
  let params = expect_step(
    "spur gear parameters",
    @step_gears.SpurGearParams::new(
      module_mm=gear_module,
      teeth=num_teeth,
      pressure_angle_deg=20.0,
      face_width_mm=gear_length_mm,
      bore_diameter_mm=bore_radius_mm * 2.0,
      involute_points~,
      arc_points~,
    ),
  )
  let step_comp = expect_step(
    "involute gear",
    @step_gears.spur_gear(params, detail~, color~, smooth=false),
  )
  let part = fabricated_part(
    "GEAR-" + num_teeth.to_string() + "T",
    "Involute gear",
    "PLA",
    "3D print",
    gear_cost_usd,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density~,
    part=Some(part),
    z_mm=-gear_length_mm / 2.0,
  )
  .add_mate_mm_deg("center")
  .add_mate_mm_deg("bottom", z=-gear_length_mm / 2.0)
  .add_mate_mm_deg("top", z=gear_length_mm / 2.0)
  .with_param("gear_module", gear_module.to_string())
  .with_param("num_teeth", num_teeth.to_string())
  .with_param("gear_length_mm", gear_length_mm.to_string())
}

///|
/// Builds a herringbone planetary gearbox component with a mimic-coupled
/// kinematic tree.
pub fn planetary_gearbox(
  name~ : String = "planetary_gearbox",
  params~ : PlanetaryGearboxParams = PlanetaryGearboxParams::default(),
  smooth~ : Bool = false,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  pgb_build(name, params, smooth, detail, true)
}

///|
/// Builds the sun, planets, and ring as **one print-in-place gear set**.
///
/// The multi-elbow herringbone teeth interlock: the gears cannot be inserted
/// into the ring after printing, so the whole set is exported in its assembled
/// Z-up position as one multi-body STEP. Print it as a single job, then add
/// the separately printed carrier, bearings, housing, and output hardware.
pub fn planetary_print_in_place(
  name~ : String = "planetary_cartridge",
  params~ : PlanetaryGearboxParams = PlanetaryGearboxParams::default(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Detailed,
) -> @cad.Component {
  let step_params = pgb_step_params(params, false, detail)
  let step_comp = expect_step(
    "print-in-place gear set",
    @step_planetary.herringbone_planetary_gearbox(step_params),
  )
  let part = fabricated_part(
    "PGB-CARTRIDGE",
    "Print-in-place herringbone gear set (sun, planets, and ring); print as one job",
    "PETG / carbon fiber nylon",
    "3D print",
    pgb_sun_cost_usd() +
    pgb_ring_cost_usd() +
    pgb_planet_cost_usd() * params.num_planets.to_double(),
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::petg(),
    part=Some(part),
  )
  .with_param("num_elbows", params.num_elbows.to_string())
  .with_param("print_in_place", "true")
}

///|
/// A spur gear built from the Tier-1 involute gear primitive.
///
/// The gear is centered on `z = 0` and marked as a 3D-printed part so
/// `printable_parts()` exports it as a standalone STEP file. `smooth` uses the
/// exact line/arc (`ExtrudedArcProfile`) tooth outline.
pub fn spur_gear_part(
  name~ : String = "spur_gear",
  module_mm~ : Double = 1.0,
  teeth~ : Int32 = 20,
  face_width_mm~ : Double = 8.0,
  bore_diameter_mm~ : Double = 4.0,
  pressure_angle_deg~ : Double = 20.0,
  backlash_mm~ : Double = 0.0,
  smooth~ : Bool = true,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
) -> @cad.Component {
  let params = expect_step(
    "spur gear parameters",
    @step_gears.SpurGearParams::new(
      module_mm~,
      teeth~,
      pressure_angle_deg~,
      face_width_mm~,
      bore_diameter_mm~,
      backlash_mm~,
    ),
  )
  let step_comp = expect_step(
    "spur gear",
    @step_gears.spur_gear(params, detail~, color~, smooth~),
  )
  let part = fabricated_part(
    "SPUR-\{teeth}T-M\{module_mm}-\{name}",
    "Spur gear \{teeth} teeth, module \{module_mm}",
    "PLA",
    "3D print",
    3.0,
  )
  @cad.Component::from_step_component(
    name,
    step_comp,
    density=@urdf.Density::pla(),
    part=Some(part),
    z_mm=-face_width_mm / 2.0,
  )
  .add_mate_mm_deg("origin")
  .add_mate_mm_deg("bottom", z=-face_width_mm / 2.0)
  .add_mate_mm_deg("top", z=face_width_mm / 2.0)
  .with_param("module_mm", module_mm.to_string())
  .with_param("teeth", teeth.to_string())
  .with_param("face_width_mm", face_width_mm.to_string())
}

///|
/// A sun/planet/ring planetary stage with real kinematics.
///
/// The stage is built from the Tier-1 planetary gearbox: the sun is the
/// continuous input, every planet mimics the sun with the matching tooth ratio,
/// and the carrier is the mimic-coupled output. Each gear and the carrier are
/// printable standalone parts.
pub fn planetary_gearset_stage(
  name~ : String = "planetary_stage",
  module_mm~ : Double = 1.0,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 18,
  planet_count~ : Int32 = 4,
  face_width_mm~ : Double = 8.0,
  pressure_angle_deg~ : Double = 20.0,
  sun_bore_mm~ : Double = 0.0,
  planet_bore_mm~ : Double = 0.0,
  carrier_pin_diam_mm~ : Double = 0.0,
  carrier_bearing~ : String = "",
  output_shaft_length_mm~ : Double = 12.0,
  smooth~ : Bool = true,
  housing~ : Bool = true,
  num_elbows~ : Int32 = 2,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let planet_bore = if planet_bore_mm > 0.0 {
    planet_bore_mm
  } else {
    sun_bore_mm
  }
  let params : PlanetaryGearboxParams = {
    gear_module: module_mm,
    gear_length_mm: face_width_mm,
    helix_angle_deg: 30.0,
    sun_teeth,
    planet_teeth,
    num_planets: planet_count,
    pressure_angle_deg,
    num_elbows,
    resolution: 5,
    bore_radius_mm: sun_bore_mm / 2.0,
    planet_bore_radius_mm: planet_bore / 2.0,
    carrier_pin_diam_mm,
    carrier_bearing_designation: carrier_bearing,
    output_shaft_diam_mm: 8.0,
    carrier_thickness_mm: 8.0,
    output_shaft_length_mm,
    tolerance_mm: 0.1,
    outer_thickness_mm: 6.0,
    include_carrier: true,
  }
  pgb_build(
    name,
    params,
    smooth,
    detail,
    housing,
    carrier_transmission_reduction=Some(
      planetary_reduction(sun_teeth, planet_teeth, 1),
    ),
  )
}
