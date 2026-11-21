///|
/// Stage-type dispatch and geometry builders for heterogeneous multi-stage
/// motorized gearboxes (`Planetary`, `Cycloidal`, `Harmonic`).

///|
/// Mechanical topology of one stage inside a `motorized_gearbox`.
#derive(Eq)
pub(all) enum GearboxStageKind {
  Planetary
  Cycloidal
  Harmonic
  SteppedPlanetary
  Wolfrom
  FlatHarmonic
}

///|
/// Parameters for a stepped (compound) planetary stage inside `motorized_gearbox`.
///
/// Defaults to a 10.2:1 backdrivable stepped planetary stage (`12/24/10/46` teeth).
pub(all) struct SteppedStageSpec {
  module_mm : Double
  sun_teeth : Int32
  planet_sun_teeth : Int32
  planet_ring_teeth : Int32
  planet_count : Int32
  tier1_length_mm : Double
  tier2_length_mm : Double
  tier_gap_mm : Double
}

///|
/// Parameters for a Wolfrom (3K) planetary stage inside `motorized_gearbox`.
///
/// Defaults to an 85:1 100%-rigid 3K planetary stage (`12/18/48/51` teeth).
pub(all) struct WolfromStageSpec {
  module_mm : Double
  sun_teeth : Int32
  planet_teeth : Int32
  ring_tooth_diff : Int32
  planet_count : Int32
  fixed_ring_length_mm : Double
  output_ring_length_mm : Double
  ring_gap_mm : Double
}

///|
/// Parameters for a flat / pancake (split-ring) harmonic stage inside
/// `motorized_gearbox`.
pub(all) struct FlatHarmonicStageSpec {
  module_mm : Double
  flexspline_teeth : Int32
  tooth_diff : Int32
  ring_length_mm : Double
  ring_gap_mm : Double
  flex_wall_mm : Double
  deformed : Bool
}

///|
/// Parameters for a cycloidal stage inside `motorized_gearbox`.
///
/// Defaults to an 11:1 dual-disk (180° phase-opposed) cycloidal stage whose
/// two opposing eccentric disks cancel radial vibration.
pub(all) struct CycloidalStageSpec {
  num_lobes : Int32
  pin_circle_radius_mm : Double
  ring_pin_radius_mm : Double
  eccentricity_mm : Double
  num_disks : Int32
  disk_thickness_mm : Double
  disk_gap_mm : Double
  output_pin_count : Int32
  output_pin_circle_radius_mm : Double
  output_pin_radius_mm : Double
  eccentric_bearing_outer_radius_mm : Double
}

///|
/// Parameters for a harmonic (strain-wave) stage inside `motorized_gearbox`.
///
/// Defaults to a 30:1 (`60`/`62`-tooth) cup-style harmonic drive whose
/// symmetric 2-lobe elliptical wave generator is inherently radially balanced.
pub(all) struct HarmonicStageSpec {
  module_mm : Double
  flexspline_teeth : Int32
  tooth_diff : Int32
  gear_length_mm : Double
  cup_length_mm : Double
  flex_wall_mm : Double
  deformed : Bool
}

///|
/// Builds a cycloidal stage specification (default 11:1, dual 180°-opposed disks).
pub fn MotorizedStageSpec::cycloidal(
  num_lobes~ : Int32 = 11,
  pin_circle_radius_mm~ : Double = 42.0,
  ring_pin_radius_mm~ : Double = 3.0,
  eccentricity_mm~ : Double = 1.5,
  num_disks~ : Int32 = 2,
  disk_thickness_mm~ : Double = 8.0,
  disk_gap_mm~ : Double = 1.0,
  output_pin_count~ : Int32 = 6,
  output_pin_circle_radius_mm~ : Double = 24.0,
  output_pin_radius_mm~ : Double = 3.0,
  eccentric_bearing_outer_radius_mm~ : Double = 11.0,
) -> MotorizedStageSpec {
  let stack_len = num_disks.to_double() * disk_thickness_mm +
    (num_disks - 1).to_double() * disk_gap_mm
  {
    ..MotorizedStageSpec::default(),
    kind: GearboxStageKind::Cycloidal,
    gear_length_mm: stack_len,
    num_elbows: 0,
    cycloidal: Some({
      num_lobes,
      pin_circle_radius_mm,
      ring_pin_radius_mm,
      eccentricity_mm,
      num_disks,
      disk_thickness_mm,
      disk_gap_mm,
      output_pin_count,
      output_pin_circle_radius_mm,
      output_pin_radius_mm,
      eccentric_bearing_outer_radius_mm,
    }),
    harmonic: None,
    stepped: None,
    wolfrom: None,
    flat_harmonic: None,
  }
}

///|
/// Builds a harmonic (strain-wave) stage specification (default 30:1, 60/62 teeth).
pub fn MotorizedStageSpec::harmonic(
  module_mm~ : Double = 1.0,
  flexspline_teeth~ : Int32 = 60,
  tooth_diff~ : Int32 = 2,
  gear_length_mm~ : Double = 12.0,
  cup_length_mm~ : Double = 24.0,
  flex_wall_mm~ : Double = 1.2,
  deformed~ : Bool = true,
) -> MotorizedStageSpec {
  {
    ..MotorizedStageSpec::default(),
    kind: GearboxStageKind::Harmonic,
    module_mm,
    gear_length_mm: cup_length_mm,
    num_elbows: 0,
    cycloidal: None,
    harmonic: Some({
      module_mm,
      flexspline_teeth,
      tooth_diff,
      gear_length_mm,
      cup_length_mm,
      flex_wall_mm,
      deformed,
    }),
    stepped: None,
    wolfrom: None,
    flat_harmonic: None,
  }
}

///|
/// Builds a stepped (compound) planetary stage specification (default 10.2:1).
pub fn MotorizedStageSpec::stepped_planetary(
  module_mm~ : Double = 1.5,
  sun_teeth~ : Int32 = 12,
  planet_sun_teeth~ : Int32 = 24,
  planet_ring_teeth~ : Int32 = 10,
  planet_count~ : Int32 = 3,
  tier1_length_mm~ : Double = 8.0,
  tier2_length_mm~ : Double = 8.0,
  tier_gap_mm~ : Double = 1.0,
) -> MotorizedStageSpec {
  {
    ..MotorizedStageSpec::default(),
    kind: GearboxStageKind::SteppedPlanetary,
    module_mm,
    sun_teeth,
    planet_teeth: planet_sun_teeth,
    planet_count,
    gear_length_mm: tier1_length_mm + tier_gap_mm + tier2_length_mm,
    num_elbows: 0,
    cycloidal: None,
    harmonic: None,
    stepped: Some({
      module_mm,
      sun_teeth,
      planet_sun_teeth,
      planet_ring_teeth,
      planet_count,
      tier1_length_mm,
      tier2_length_mm,
      tier_gap_mm,
    }),
    wolfrom: None,
    flat_harmonic: None,
  }
}

///|
/// Builds a Wolfrom (3K) rigid high-ratio planetary stage specification (default 85:1).
pub fn MotorizedStageSpec::wolfrom(
  module_mm~ : Double = 1.5,
  sun_teeth~ : Int32 = 12,
  planet_teeth~ : Int32 = 18,
  ring_tooth_diff~ : Int32 = 3,
  planet_count~ : Int32 = 3,
  fixed_ring_length_mm~ : Double = 8.0,
  output_ring_length_mm~ : Double = 8.0,
  ring_gap_mm~ : Double = 1.0,
) -> MotorizedStageSpec {
  {
    ..MotorizedStageSpec::default(),
    kind: GearboxStageKind::Wolfrom,
    module_mm,
    sun_teeth,
    planet_teeth,
    planet_count,
    gear_length_mm: fixed_ring_length_mm + ring_gap_mm + output_ring_length_mm,
    num_elbows: 0,
    cycloidal: None,
    harmonic: None,
    stepped: None,
    wolfrom: Some({
      module_mm,
      sun_teeth,
      planet_teeth,
      ring_tooth_diff,
      planet_count,
      fixed_ring_length_mm,
      output_ring_length_mm,
      ring_gap_mm,
    }),
    flat_harmonic: None,
  }
}

///|
/// Builds a flat / pancake (split-ring) harmonic stage specification (default -30:1).
pub fn MotorizedStageSpec::flat_harmonic(
  module_mm~ : Double = 1.0,
  flexspline_teeth~ : Int32 = 60,
  tooth_diff~ : Int32 = 2,
  ring_length_mm~ : Double = 7.0,
  ring_gap_mm~ : Double = 1.0,
  flex_wall_mm~ : Double = 1.2,
  deformed~ : Bool = true,
) -> MotorizedStageSpec {
  {
    ..MotorizedStageSpec::default(),
    kind: GearboxStageKind::FlatHarmonic,
    module_mm,
    gear_length_mm: 2.0 * ring_length_mm + ring_gap_mm,
    num_elbows: 0,
    cycloidal: None,
    harmonic: None,
    stepped: None,
    wolfrom: None,
    flat_harmonic: Some({
      module_mm,
      flexspline_teeth,
      tooth_diff,
      ring_length_mm,
      ring_gap_mm,
      flex_wall_mm,
      deformed,
    }),
  }
}

///|
/// Returns the mechanical topology of this stage.
pub fn MotorizedStageSpec::stage_kind(
  self : MotorizedStageSpec,
) -> GearboxStageKind {
  self.kind
}

///|
/// Returns the signed gear reduction ratio of this stage (`> 0` same direction
/// as input, `< 0` reversed direction relative to input).
pub fn MotorizedStageSpec::signed_reduction(
  self : MotorizedStageSpec,
) -> Double {
  match self.kind {
    Planetary => {
      let z_sun = self.sun_teeth.to_double()
      let z_ring = (self.sun_teeth + 2 * self.planet_teeth).to_double()
      1.0 + z_ring / z_sun
    }
    Cycloidal =>
      match self.cycloidal {
        Some(c) => -c.num_lobes.to_double()
        None => -11.0
      }
    Harmonic =>
      match self.harmonic {
        Some(h) => -h.flexspline_teeth.to_double() / h.tooth_diff.to_double()
        None => -30.0
      }
    SteppedPlanetary =>
      match self.stepped {
        Some(s) => {
          let zr = (s.sun_teeth + s.planet_sun_teeth + s.planet_ring_teeth).to_double()
          1.0 +
          zr *
          s.planet_sun_teeth.to_double() /
          (s.sun_teeth.to_double() * s.planet_ring_teeth.to_double())
        }
        None => 10.2
      }
    Wolfrom =>
      match self.wolfrom {
        Some(w) => {
          let zs = w.sun_teeth.to_double()
          let zr1 = (w.sun_teeth + 2 * w.planet_teeth).to_double()
          let zr2 = zr1 + w.ring_tooth_diff.to_double()
          (zs + zr1) * zr2 / (zs * (zr2 - zr1))
        }
        None => 85.0
      }
    FlatHarmonic =>
      match self.flat_harmonic {
        Some(fh) => -fh.flexspline_teeth.to_double() / fh.tooth_diff.to_double()
        None => -30.0
      }
  }
}

///|
/// Typical per-stage mechanical efficiency for torque rating estimates.
pub fn MotorizedStageSpec::efficiency(self : MotorizedStageSpec) -> Double {
  match self.kind {
    Planetary => 0.90
    Cycloidal => 0.85
    Harmonic => 0.80
    SteppedPlanetary => 0.85
    Wolfrom => 0.65
    FlatHarmonic => 0.80
  }
}

///|
/// Returns `true` when this stage is a print-in-place herringbone planetary
/// cartridge (`num_elbows >= 4`).
pub fn MotorizedStageSpec::is_print_in_place_cartridge(
  self : MotorizedStageSpec,
) -> Bool {
  self.kind == GearboxStageKind::Planetary && self.num_elbows >= 4
}

///|
/// Extracts a single named layer from a native `+Z` `@step_common.Component`
/// into a `@cad.BodyPart`.
fn stage_step_layer_body(
  body_name : String,
  step_comp : @step_common.Component,
  layer_name : String,
  part : @cad.PartMeta,
  color : @step_cad.Rgb,
) -> @cad.BodyPart {
  let comp = @cad.Component::from_step_layer(
    body_name,
    step_comp,
    layer_name,
    density=@urdf.Density::petg(),
    include_connectors=false,
    apply_placement=true,
  )
  if comp.bodies.length() != 1 {
    abort("expected one body for layer \{layer_name} in \{body_name}")
  }
  let raw = comp.bodies[0]
  {
    ..raw,
    name: body_name,
    node: raw.node.with_name(body_name).with_color(color),
    part: Some(part),
  }
}

///|
/// Builds the cycloidal stage's rotating eccentric input hub (merging all
/// phased eccentric cams onto a single rigid input shaft hub).
fn build_cycloidal_input_hub(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_cycloidal.CycloidalLayout,
) -> @cad.Component {
  let part = fabricated_part(
    part_number,
    "Printed phased eccentric input shaft (\{layout.params.num_disks} opposing cam lobes for vibration balance)",
    "carbon fiber nylon",
    "3D print",
    4.0,
  )
  let mut comp = @cad.Component::new(
      name,
      description="Cycloidal phased eccentric input hub",
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("top", z=layout.stack_length_mm)
    .with_part(part)
  for d in 0..<layout.params.num_disks {
    let body = stage_step_layer_body(
      "\{name}_cam_\{d + 1}",
      stage_step,
      "eccentric-cam-\{d + 1}",
      part,
      @step_cad.Rgb::orange(),
    )
    comp = comp.add_body(body)
  }
  comp
}

///|
/// Builds the cycloidal stage's output carrier plate, output drive pins,
/// output shaft, and phased cycloidal disks (which all share the `-1/N`
/// output rotation rate).
fn build_cycloidal_output_carrier(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_cycloidal.CycloidalLayout,
  plate_radius : Double,
  clearance : Double,
  thickness : Double,
  shaft_diam : Double,
  shaft_length : Double,
  hub_seat_z : Double?,
) -> @cad.Component {
  let carrier_part = fabricated_part(
    part_number,
    "Printed cycloidal output carrier plate with \{layout.params.output_pin_count} drive pins and \{shaft_diam} mm output shaft",
    "carbon fiber nylon",
    "3D print",
    6.0,
  )
  let disk_part = fabricated_part(
    part_number + "-DISK",
    "Printed cycloidal disk (\{layout.params.num_lobes} lobes, \{layout.params.num_disks}-disk balanced set)",
    "carbon fiber nylon",
    "3D print",
    5.0,
  )
  let pin_part = fabricated_part(
    part_number + "-PIN",
    "Steel cycloidal output drive pin",
    "steel",
    "purchased",
    1.0,
  )
  let mut comp = @cad.Component::new(
      name,
      description="Cycloidal stage output carrier with drive pins and phased disks",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        z_mm=thickness / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::new(0.20, 0.72, 0.42),
      ).with_part(carrier_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        shaft_diam,
        shaft_length,
        z_mm=thickness + shaft_length / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::new(0.75, 0.78, 0.82),
      ).with_part(carrier_part),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("output_flange", z=thickness)
    .add_mate_mm_deg("output_shaft_end", z=thickness + shaft_length)
    .with_part(carrier_part)
  match hub_seat_z {
    Some(z) => comp = comp.add_mate_mm_deg("output_hub_seat", z~)
    None => ()
  }
  // Output drive pins extend downward from the carrier plate through all disks.
  let pin_len = layout.stack_length_mm + clearance + thickness * 0.6
  let pin_z0 = -(layout.stack_length_mm + clearance)
  for j in 0..<layout.output_pins.length() {
    let (ox, oy) = layout.output_pins[j]
    comp = comp.add_body(
      @cad.BodyPart::cylinder_mm(
        "\{name}_out_pin_\{j + 1}",
        2.0 * layout.params.output_pin_radius_mm,
        pin_len,
        x_mm=ox,
        y_mm=oy,
        z_mm=pin_z0 + pin_len / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::new(0.82, 0.84, 0.88),
      ).with_part(pin_part),
    )
  }
  // Attach the phased cycloidal disks below the carrier plate (shifted down by
  // -(stack_length + clearance) so they sit inside the outer pin ring).
  let disk_colors = [
    @step_cad.Rgb::blue(),
    @step_cad.Rgb::new(0.15, 0.72, 0.45),
    @step_cad.Rgb::new(0.75, 0.35, 0.85),
  ]
  for d in 0..<layout.params.num_disks {
    let raw_disk = stage_step_layer_body(
      "\{name}_cycloid_disk_\{d + 1}",
      stage_step,
      "disk-\{d + 1}",
      disk_part,
      disk_colors[d % disk_colors.length()],
    )
    let shifted = { ..raw_disk, node: raw_disk.node.translate(z=pin_z0), }
    comp = comp.add_body(shifted)
  }
  comp
}

///|
/// Builds the harmonic stage's rotating elliptical wave generator input hub.
fn build_harmonic_wave_generator(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_harmonic.HarmonicLayout,
) -> @cad.Component {
  let part = fabricated_part(
    part_number, "Printed symmetric 2-lobe elliptical wave generator cam", "carbon fiber nylon",
    "3D print", 4.0,
  )
  let body = stage_step_layer_body(
    name + "_wave_gen",
    stage_step,
    "wave-generator",
    part,
    @step_cad.Rgb::orange(),
  )
  @cad.Component::new(
    name,
    description="Harmonic drive elliptical wave generator",
  )
  .add_body(body)
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=layout.params.gear_length_mm)
  .with_part(part)
}

///|
/// Builds the harmonic stage's flexspline cup + output flange + output shaft.
fn build_harmonic_output_carrier(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_harmonic.HarmonicLayout,
  plate_radius : Double,
  clearance : Double,
  thickness : Double,
  shaft_diam : Double,
  shaft_length : Double,
  hub_seat_z : Double?,
) -> @cad.Component {
  let flex_part = fabricated_part(
    part_number,
    "Printed flexspline cup (\{layout.params.flexspline_teeth} teeth) with output flange and \{shaft_diam} mm shaft",
    "carbon fiber nylon",
    "3D print",
    8.0,
  )
  let mut comp = @cad.Component::new(
      name,
      description="Harmonic stage flexspline output carrier",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        z_mm=thickness / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::new(0.20, 0.72, 0.42),
      ).with_part(flex_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        shaft_diam,
        shaft_length,
        z_mm=thickness + shaft_length / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::new(0.75, 0.78, 0.82),
      ).with_part(flex_part),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("output_flange", z=thickness)
    .add_mate_mm_deg("output_shaft_end", z=thickness + shaft_length)
    .with_part(flex_part)
  match hub_seat_z {
    Some(z) => comp = comp.add_mate_mm_deg("output_hub_seat", z~)
    None => ()
  }
  let z_shift = -(layout.total_length_mm + clearance)
  let flex_teeth = stage_step_layer_body(
    name + "_flexspline_teeth",
    stage_step,
    "flexspline-teeth",
    flex_part,
    @step_cad.Rgb::blue(),
  )
  let flex_cup = stage_step_layer_body(
    name + "_flexspline_cup",
    stage_step,
    "flexspline-cup",
    flex_part,
    @step_cad.Rgb::new(0.20, 0.55, 0.90),
  )
  let flex_diaphragm = stage_step_layer_body(
    name + "_flexspline_diaphragm",
    stage_step,
    "flexspline-diaphragm",
    flex_part,
    @step_cad.Rgb::new(0.15, 0.45, 0.80),
  )
  comp
  .add_body({ ..flex_teeth, node: flex_teeth.node.translate(z=z_shift), })
  .add_body({ ..flex_cup, node: flex_cup.node.translate(z=z_shift), })
  .add_body({
    ..flex_diaphragm,
    node: flex_diaphragm.node.translate(z=z_shift),
  })
}

///|
/// Builds the stepped planetary stage's rotating sun input hub.
fn build_stepped_input_sun(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_stepped.SteppedPlanetaryLayout,
) -> @cad.Component {
  let part = fabricated_part(
    part_number,
    "Printed stepped planetary sun gear (\{layout.params.sun_teeth} teeth)",
    "carbon fiber nylon",
    "3D print",
    3.0,
  )
  let body = stage_step_layer_body(
    name + "_stepped_sun",
    stage_step,
    "sun",
    part,
    @step_cad.Rgb::orange(),
  )
  @cad.Component::new(name, description="Stepped planetary sun input gear")
  .add_body(body)
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=layout.params.tier1_length_mm)
  .with_part(part)
}

///|
/// Builds the stepped planetary stage's carrier plate, pins, stepped planets,
/// and output shaft.
fn build_stepped_output_carrier(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_stepped.SteppedPlanetaryLayout,
  plate_radius : Double,
  clearance : Double,
  thickness : Double,
  shaft_diam : Double,
  shaft_length : Double,
  hub_seat_z : Double?,
) -> @cad.Component {
  let carrier_part = fabricated_part(
    part_number,
    "Printed stepped planetary carrier plate with \{layout.params.planet_count} stepped planets and \{shaft_diam} mm output shaft",
    "carbon fiber nylon",
    "3D print",
    7.0,
  )
  let planet_part = fabricated_part(
    part_number + "-PLANET",
    "Printed two-tier stepped planet gear (\{layout.params.planet_sun_teeth}/\{layout.params.planet_ring_teeth} teeth)",
    "carbon fiber nylon",
    "3D print",
    3.5,
  )
  let mut comp = @cad.Component::new(
      name,
      description="Stepped planetary output carrier with two-tier planets",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        z_mm=thickness / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::new(0.20, 0.72, 0.42),
      ).with_part(carrier_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        shaft_diam,
        shaft_length,
        z_mm=thickness + shaft_length / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::new(0.75, 0.78, 0.82),
      ).with_part(carrier_part),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("output_flange", z=thickness)
    .add_mate_mm_deg("output_shaft_end", z=thickness + shaft_length)
    .with_part(carrier_part)
  match hub_seat_z {
    Some(z) => comp = comp.add_mate_mm_deg("output_hub_seat", z~)
    None => ()
  }
  let z_shift = -(layout.total_length_mm + clearance)
  let pin_len = layout.total_length_mm + clearance + thickness * 0.6
  for i in 0..<layout.planets.length() {
    let (px, py) = layout.planets[i]
    comp = comp.add_body(
      @cad.BodyPart::cylinder_mm(
        "\{name}_stepped_pin_\{i + 1}",
        2.0 * layout.params.planet_bore_radius_mm,
        pin_len,
        x_mm=px,
        y_mm=py,
        z_mm=z_shift + pin_len / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::new(0.82, 0.84, 0.88),
      ).with_part(carrier_part),
    )
    let t1 = stage_step_layer_body(
      "\{name}_stepped_planet_\{i + 1}_t1",
      stage_step,
      "planet-\{i + 1}-tier1",
      planet_part,
      @step_cad.Rgb::blue(),
    )
    let t2 = stage_step_layer_body(
      "\{name}_stepped_planet_\{i + 1}_t2",
      stage_step,
      "planet-\{i + 1}-tier2",
      planet_part,
      @step_cad.Rgb::new(0.25, 0.55, 0.95),
    )
    comp = comp
      .add_body({ ..t1, node: t1.node.translate(z=z_shift), })
      .add_body({ ..t2, node: t2.node.translate(z=z_shift), })
  }
  comp
}

///|
/// Builds the Wolfrom (3K) stage's rotating sun input hub.
fn build_wolfrom_input_sun(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_wolfrom.WolfromLayout,
) -> @cad.Component {
  let part = fabricated_part(
    part_number,
    "Printed Wolfrom 3K sun gear (\{layout.params.sun_teeth} teeth)",
    "carbon fiber nylon",
    "3D print",
    3.0,
  )
  let body = stage_step_layer_body(
    name + "_wolfrom_sun",
    stage_step,
    "sun",
    part,
    @step_cad.Rgb::orange(),
  )
  @cad.Component::new(name, description="Wolfrom 3K planetary sun input gear")
  .add_body(body)
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=layout.params.fixed_ring_length_mm)
  .with_part(part)
}

///|
/// Builds the Wolfrom (3K) stage's rotating output ring + output flange + shaft
/// (plus the full-width planets riding inside the stage).
fn build_wolfrom_output_carrier(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_wolfrom.WolfromLayout,
  plate_radius : Double,
  clearance : Double,
  thickness : Double,
  shaft_diam : Double,
  shaft_length : Double,
  hub_seat_z : Double?,
) -> @cad.Component {
  let out_part = fabricated_part(
    part_number,
    "Printed Wolfrom 3K rotating output ring (\{layout.output_ring_teeth} teeth) with output flange and \{shaft_diam} mm shaft",
    "carbon fiber nylon",
    "3D print",
    8.0,
  )
  let planet_part = fabricated_part(
    part_number + "-PLANET",
    "Printed Wolfrom 3K full-width planet gear (\{layout.params.planet_teeth} teeth)",
    "carbon fiber nylon",
    "3D print",
    3.0,
  )
  let mut comp = @cad.Component::new(
      name,
      description="Wolfrom 3K rotating output ring and shaft",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        z_mm=thickness / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::new(0.20, 0.72, 0.42),
      ).with_part(out_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        shaft_diam,
        shaft_length,
        z_mm=thickness + shaft_length / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::new(0.75, 0.78, 0.82),
      ).with_part(out_part),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("output_flange", z=thickness)
    .add_mate_mm_deg("output_shaft_end", z=thickness + shaft_length)
    .with_part(out_part)
  match hub_seat_z {
    Some(z) => comp = comp.add_mate_mm_deg("output_hub_seat", z~)
    None => ()
  }
  let z_shift = -(layout.total_length_mm + clearance)
  let out_ring = stage_step_layer_body(
    name + "_wolfrom_ring_output",
    stage_step,
    "ring-output",
    out_part,
    @step_cad.Rgb::new(0.18, 0.72, 0.45),
  )
  comp = comp.add_body({ ..out_ring, node: out_ring.node.translate(z=z_shift), })
  for i in 0..<layout.planets.length() {
    let p_body = stage_step_layer_body(
      "\{name}_wolfrom_planet_\{i + 1}",
      stage_step,
      "planet-\{i + 1}",
      planet_part,
      @step_cad.Rgb::blue(),
    )
    comp = comp.add_body({ ..p_body, node: p_body.node.translate(z=z_shift), })
  }
  comp
}

///|
/// Builds the flat/pancake harmonic stage's elliptical wave generator input hub.
fn build_flat_harmonic_wave_generator(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_harmonic.FlatHarmonicLayout,
) -> @cad.Component {
  let part = fabricated_part(
    part_number, "Printed pancake harmonic elliptical wave generator cam", "carbon fiber nylon",
    "3D print", 4.0,
  )
  let body = stage_step_layer_body(
    name + "_wave_gen",
    stage_step,
    "wave-generator",
    part,
    @step_cad.Rgb::orange(),
  )
  @cad.Component::new(
    name,
    description="Pancake harmonic elliptical wave generator",
  )
  .add_body(body)
  .add_mate_mm_deg("bottom")
  .add_mate_mm_deg("top", z=layout.total_length_mm)
  .with_part(part)
}

///|
/// Builds the flat/pancake harmonic stage's rotating output dynamic spline +
/// floating flex-ring + output flange + shaft.
fn build_flat_harmonic_output_carrier(
  name : String,
  part_number : String,
  stage_step : @step_common.Component,
  layout : @step_harmonic.FlatHarmonicLayout,
  plate_radius : Double,
  clearance : Double,
  thickness : Double,
  shaft_diam : Double,
  shaft_length : Double,
  hub_seat_z : Double?,
) -> @cad.Component {
  let out_part = fabricated_part(
    part_number,
    "Printed pancake harmonic output dynamic spline (\{layout.params.flexspline_teeth} teeth) and floating flex-ring",
    "carbon fiber nylon",
    "3D print",
    8.0,
  )
  let mut comp = @cad.Component::new(
      name,
      description="Pancake harmonic output dynamic spline and flex-ring",
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_plate",
        plate_radius * 2.0,
        thickness,
        z_mm=thickness / 2.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::new(0.20, 0.72, 0.42),
      ).with_part(out_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_output_shaft",
        shaft_diam,
        shaft_length,
        z_mm=thickness + shaft_length / 2.0,
        density=@urdf.Density::steel_mild(),
        color=@step_cad.Rgb::new(0.75, 0.78, 0.82),
      ).with_part(out_part),
    )
    .add_mate_mm_deg("bottom")
    .add_mate_mm_deg("output_flange", z=thickness)
    .add_mate_mm_deg("output_shaft_end", z=thickness + shaft_length)
    .with_part(out_part)
  match hub_seat_z {
    Some(z) => comp = comp.add_mate_mm_deg("output_hub_seat", z~)
    None => ()
  }
  let z_shift = -(layout.total_length_mm + clearance)
  let out_ring = stage_step_layer_body(
    name + "_harmonic_ring_output",
    stage_step,
    "ring-output",
    out_part,
    @step_cad.Rgb::new(0.18, 0.72, 0.45),
  )
  let flex_ring = stage_step_layer_body(
    name + "_flexspline_ring",
    stage_step,
    "flexspline-ring",
    out_part,
    @step_cad.Rgb::blue(),
  )
  comp
  .add_body({ ..out_ring, node: out_ring.node.translate(z=z_shift), })
  .add_body({ ..flex_ring, node: flex_ring.node.translate(z=z_shift), })
}
