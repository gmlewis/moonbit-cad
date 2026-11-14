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
  bore_radius_mm : Double
  tolerance_mm : Double
  outer_thickness_mm : Double
  include_carrier : Bool
}

///|
/// Default gearbox parameters: a fast, clean 12/12/36 tooth set with 3 planets.
pub fn PlanetaryGearboxParams::default() -> PlanetaryGearboxParams {
  {
    gear_module: 3.0,
    gear_length_mm: 30.0,
    helix_angle_deg: 30.0,
    sun_teeth: 12,
    planet_teeth: 12,
    num_planets: 3,
    pressure_angle_deg: 20.0,
    num_elbows: 2,
    resolution: 5,
    bore_radius_mm: 6.0,
    tolerance_mm: 0.35,
    outer_thickness_mm: 10.0,
    include_carrier: true,
  }
}

///|
/// The carrier plate thickness in mm.
let pgb_carrier_thickness_mm : Double = 8.0

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
/// Resolves the sweep elbow count for a detail level. `smooth` forces exact
/// line/arc extrusions (`num_elbows = 0`), which are also glTF-safe.
fn pgb_elbows(
  params : PlanetaryGearboxParams,
  smooth : Bool,
  detail : @step_common.DetailLevel,
) -> Int32 {
  if smooth {
    return 0
  }
  match detail {
    @step_common.DetailLevel::Simplified =>
      if params.num_elbows < 2 {
        params.num_elbows
      } else {
        2
      }
    @step_common.DetailLevel::Detailed =>
      if params.num_elbows < 2 {
        2
      } else {
        params.num_elbows
      }
    @step_common.DetailLevel::FullyModeled =>
      if params.num_elbows < 4 {
        4
      } else {
        params.num_elbows
      }
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
/// A central bore is only requested when it fits inside both the sun and the
/// planet root circles; otherwise the gears are exported solid.
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
  let smallest_root = if sun_root < planet_root {
    sun_root
  } else {
    planet_root
  }
  let (hole_type, hole_radius) = if params.bore_radius_mm > 0.0 &&
    params.bore_radius_mm < smallest_root - 0.5 {
    ("Circular", params.bore_radius_mm)
  } else {
    ("None", 0.0)
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
      hole_radius_mm=hole_radius,
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
/// Builds the printed carrier plate with planet pins and an output boss.
fn pgb_carrier_component(
  name : String,
  layout : @step_planetary.HerringbonePlanetaryLayout,
) -> @cad.Component {
  let thickness = pgb_carrier_thickness_mm
  let plate_radius = layout.center_distance_mm +
    layout.planet.outer_radius_mm +
    4.0
  let part = fabricated_part(
    "PGB-CARRIER",
    "Planetary carrier plate with output boss",
    "PETG / carbon fiber nylon",
    "3D print",
    pgb_carrier_cost_usd(),
  )
  let mut comp = @cad.Component::new(
      name,
      description="Planetary carrier plate",
    )
    .with_param("center_distance_mm", layout.center_distance_mm.to_string())
    .add_body(
      @cad.BodyPart::tube_mm(
        name + "_plate",
        plate_radius * 2.0,
        36.0,
        thickness,
        z_mm=thickness / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::purple(),
      ),
    )
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    comp = comp.add_body(
      @cad.BodyPart::cylinder_mm(
        "\{name}_pin_\{i}",
        8.0,
        thickness,
        x_mm=planet.x,
        y_mm=-planet.z,
        z_mm=thickness / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::purple(),
      ),
    )
  }
  comp = comp.add_body(
    @cad.BodyPart::tube_mm(
      name + "_output_boss",
      plate_radius * 0.55 * 2.0,
      36.0,
      pgb_output_boss_mm,
      z_mm=thickness + pgb_output_boss_mm / 2.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::purple(),
    ),
  )
  comp
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("output_flange", z=thickness + pgb_output_boss_mm)
  .add_mate_mm_deg("output_shaft", z=thickness + pgb_output_boss_mm)
  .with_part(part)
}

///|
/// Builds the complete gearbox tree rooted at the printed ring housing.
fn pgb_build(
  name : String,
  params : PlanetaryGearboxParams,
  smooth : Bool,
  detail : @step_common.DetailLevel,
  include_housing : Bool,
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
  let planet_multiplier = -(params.sun_teeth.to_double() /
    params.planet_teeth.to_double())
  for i in 0..<layout.planets.length() {
    let planet = layout.planets[i]
    let planet_name = "\{name}_planet_\{i}"
    let planet_part = pgb_gear_part(
      planet_name,
      step_comp,
      "planet-\{i + 1}",
      "Planetary planet gear",
      "PGB-PLANET-\{planet_name}",
      pgb_planet_cost_usd(),
      length,
      smooth,
    )
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
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
        dynamics=Some(@urdf.JointDynamics::new(damping=0.02, friction=0.01)),
        mimic=Some(
          @urdf.JointMimic::new(sun_joint, multiplier=planet_multiplier),
        ),
      ),
    )
  }
  if params.include_carrier {
    let carrier = pgb_carrier_component("\{name}_carrier", layout)
    let carrier_multiplier = params.sun_teeth.to_double() /
      (params.sun_teeth.to_double() + layout.ring_teeth.to_double())
    comp = comp.attach(
      "\{name}_carrier_joint",
      parent_mate="output_face",
      carrier,
      child_mate="bottom",
      spec=@cad.JointSpec::continuous(
        limit=Some(@urdf.JointLimit::new(effort=10.0, velocity=30.0)),
        mimic=Some(
          @urdf.JointMimic::new(sun_joint, multiplier=carrier_multiplier),
        ),
      ),
    )
  }
  comp
}

///|
/// Builds a standalone involute gear component with an optional bore.
///
/// The public API is unchanged; the geometry delegates to the Tier-1 involute
/// spur gear and the detail level controls the tooth-outline resolution.
pub fn herringbone_gear_component(
  name : String,
  gear_module~ : Double,
  num_teeth~ : Int32,
  gear_length_mm~ : Double,
  helix_angle_deg~ : Double = 30.0,
  bore_radius_mm~ : Double = 5.0,
  num_elbows~ : Int32 = 2,
  resolution~ : Int32 = 5,
  direction~ : Double = 1.0,
  density~ : @urdf.Density = @urdf.Density::pla(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::orange(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let _ = helix_angle_deg
  let _ = num_elbows
  let _ = resolution
  let _ = direction
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
  planet_count~ : Int32 = 3,
  face_width_mm~ : Double = 8.0,
  pressure_angle_deg~ : Double = 20.0,
  sun_bore_mm~ : Double = 0.0,
  planet_bore_mm~ : Double = 0.0,
  smooth~ : Bool = true,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let _ = planet_bore_mm
  let params : PlanetaryGearboxParams = {
    gear_module: module_mm,
    gear_length_mm: face_width_mm,
    helix_angle_deg: 30.0,
    sun_teeth,
    planet_teeth,
    num_planets: planet_count,
    pressure_angle_deg,
    num_elbows: 2,
    resolution: 5,
    bore_radius_mm: sun_bore_mm / 2.0,
    tolerance_mm: 0.1,
    outer_thickness_mm: 6.0,
    include_carrier: true,
  }
  pgb_build(name, params, smooth, detail, false)
}
