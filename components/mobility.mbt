///|
/// Reusable mobility sub-assemblies: structural tubes, robot leg segments,
/// wheels, quadruped legs, and a steerable suspension fork.
///
/// Whole-robot models live under `examples/`; this package contains only
/// parameterized building blocks shared by those models.

///|
/// Axial length of the printed motor cup at a leg's distal joint. It must be
/// at least the outrunner's rear overhang so the motor nests inside it.
let leg_motor_cup_length_mm : Double = 34.0

///|
/// Outer diameter of the printed leg motor cup.
let leg_motor_cup_outer_mm : Double = 64.0

///|
/// Inner bore of the printed leg motor cup (clears the 50 mm outrunner).
let leg_motor_cup_bore_mm : Double = 51.0

///|
/// Bolt-circle radius of the rear cover screws that the cup must clear.
let leg_motor_cup_screw_radius_mm : Double = 28.8

///|
/// Clearance hole for a rear cover screw head in the motor cup.
let leg_motor_cup_screw_hole_mm : Double = 6.2

///|
/// Builds a printed motor cup: a ring with a screw-head clearance hole at each
/// corner of the actuator's rear bolt circle. The cup axis is +Y.
fn leg_motor_cup_body(
  name : String,
  x_mm : Double,
  y_mm : Double,
  z_mm : Double,
  density : @urdf.Density,
  color : @step_cad.Rgb,
  detail : @step_common.DetailLevel,
) -> @cad.BodyPart {
  let holes : Array[(Double, Double, Double)] = [
    (0.0, 0.0, leg_motor_cup_bore_mm),
  ]
  for i in 0..<4 {
    let theta = 2.0 * @math.PI * i.to_double() / 4.0
    holes.push(
      (
        leg_motor_cup_screw_radius_mm * @math.cos(theta),
        leg_motor_cup_screw_radius_mm * @math.sin(theta),
        leg_motor_cup_screw_hole_mm,
      ),
    )
  }
  actuator_plate_body(
    name,
    leg_motor_cup_outer_mm,
    leg_motor_cup_length_mm,
    -leg_motor_cup_length_mm / 2.0,
    holes,
    density,
    color,
    detail,
  ).transform_by(
    @cad.urdf_transform_from_mm_deg(x_mm~, y_mm~, z_mm~, rx_deg=90.0),
  )
}

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
  hub_bore_mm~ : Double = 8.2,
  distal_cup_offset_mm~ : Double = 0.0,
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
  // The motor cup sits inboard of the distal joint, so the strut, spars, ribs,
  // and cable clips are offset in the same direction. This leaves an
  // unobstructed bay for the next actuator's rear screw heads.
  let strut_y_mm = distal_cup_offset_mm * 0.6
  let mut leg = @cad.Component::new(name, description="Robot leg segment")
    .with_param("length_mm", length_mm.to_string())
    .with_param("width_mm", width_mm.to_string())
    .with_param("thickness_mm", thickness_mm.to_string())
    .with_param("bore_diam_mm", bore_diam_mm.to_string())
    .with_param("hub_bore_mm", hub_bore_mm.to_string())
    .add_body(
      // The proximal boss is a real hub, bored for the actuator's output
      // shaft, so the link mounts on the shaft instead of embedding it.
      @cad.BodyPart::tube_mm(
        name + "_proximal_boss",
        width_mm,
        hub_bore_mm,
        thickness_mm,
        rx_deg=90.0,
        density~,
        color~,
      ).with_part(part),
    )
    .add_body(
      // The strut starts below the proximal hub so the actuator's output
      // shaft passes through the hub bore, not through solid link material.
      @cad.BodyPart::box_mm(
        name + "_strut",
        width_mm,
        thickness_mm,
        length_mm - width_mm / 2.0,
        z_mm=-(length_mm + width_mm / 2.0) / 2.0,
        y_mm=strut_y_mm,
        density~,
        color~,
      ).with_part(part),
    )
    .add_body(
      // A motor cup at the distal joint: the next actuator's outrunner nests
      // in this bore, so the motor plate seats on the cup face instead of
      // intersecting the link.
      leg_motor_cup_body(
        name + "_distal_motor_cup",
        0.0,
        distal_cup_offset_mm,
        -length_mm,
        density,
        color,
        detail,
      ).with_part(part),
    )
    .add_mate_mm_deg("proximal_joint", axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg("distal_joint", z=-length_mm, axis=(0.0, 1.0, 0.0))
    // Bearing seats are rotated so the bearing axis matches the joint axis
    // (+Y) instead of the bearing primitive's default +Z.
    .add_mate_mm_deg("proximal_bearing_seat", rx_deg=90.0, axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg(
      "distal_bearing_seat",
      z=-length_mm,
      rx_deg=90.0,
      axis=(0.0, 1.0, 0.0),
    )
    .add_mate_mm_deg(
      "insert_seat_0",
      x=width_mm * 0.35,
      z=-8.0,
      axis=(0.0, 0.0, 1.0),
    )
    .add_mate_mm_deg(
      "insert_seat_1",
      x=-width_mm * 0.35,
      z=-8.0,
      axis=(0.0, 0.0, 1.0),
    )
    // Frames for a direct bolt-on to a planetary actuator's output shaft. The
    // actuator's local z points along world +Y on the left side and -Y on the
    // mirrored right side, so the two frames differ by a half turn.
    .add_mate_mm_deg("proximal_mount", rx_deg=-90.0, axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg(
      "proximal_mount_mirror",
      rx_deg=90.0,
      axis=(0.0, -1.0, 0.0),
    )
    // Parent-side mounting frames for a knee or wheel actuator at the distal
    // joint. The rotation lives here, not on the actuator, so the actuator
    // root only translates when it is compiled.
    .add_mate_mm_deg(
      "distal_mount_left",
      y=leg_motor_cup_length_mm / 2.0,
      z=-length_mm,
      rx_deg=-90.0,
      axis=(0.0, 1.0, 0.0),
    )
    .add_mate_mm_deg(
      "distal_mount_right",
      y=-leg_motor_cup_length_mm / 2.0,
      z=-length_mm,
      rx_deg=90.0,
      axis=(0.0, -1.0, 0.0),
    )
    .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  if detail_is_rich(detail) {
    // Dual-spar, ribbed link: two side spars, transverse lightening ribs, and
    // cable-routing clips down one face. These are separate nominal bodies, so
    // the printed part keeps its analytic box and cylinder surfaces.
    for i in 0..<2 {
      let x = if i == 0 { width_mm * 0.30 } else { -width_mm * 0.30 }
      leg = leg.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_spar_\{i}",
          width_mm * 0.16,
          thickness_mm * 1.04,
          length_mm * 0.92,
          x_mm=x,
          y_mm=strut_y_mm,
          z_mm=-length_mm / 2.0,
          density~,
          color~,
        ).with_part(part),
      )
    }
    for i in 0..<3 {
      let z = -length_mm * (0.25 + 0.25 * i.to_double())
      leg = leg.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_rib_\{i}",
          width_mm * 0.9,
          thickness_mm * 1.04,
          length_mm * 0.06,
          y_mm=strut_y_mm,
          z_mm=z,
          density~,
          color~,
        ).with_part(part),
      )
    }
    for i in 0..<3 {
      let z = -length_mm * (0.2 + 0.25 * i.to_double())
      leg = leg.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_clip_\{i}",
          5.0,
          12.0,
          8.0,
          x_mm=width_mm * 0.5 + 2.0,
          y_mm=strut_y_mm,
          z_mm=z,
          density=@urdf.Density::petg(),
          color=@step_cad.Rgb::black(),
        ).with_part(part),
      )
    }
  }
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
      parent_mate="proximal_bearing_seat",
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
      parent_mate="distal_bearing_seat",
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
        parent_mate="insert_seat_" + i.to_string(),
        insert,
        child_mate="seat",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
  }
  // One printed link part: all body-level metadata rolls up to a single BOM
  // line per link instead of one per body.
  leg.with_part(part)
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
  // The hub/rim and the TPU tread are separate printable assemblies, so each
  // rolls up as exactly one BOM line per wheel.
  let mut hub_comp = @cad.Component::new(
      name + "_hub_part",
      description="Wheel hub and rim",
    )
    .with_param("hub_bore_mm", hub_bore_mm.to_string())
    .add_body(
      // The hub is always bored to the actuator output shaft, at every
      // detail level, so the shaft never embeds in solid hub material.
      @cad.BodyPart::tube_mm(
        name + "_hub",
        hub_radius_mm * 2.0,
        hub_bore_mm,
        width_mm,
        rx_deg=90.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::orange(),
      ).with_part(hub_part),
    )
  let mut tread_comp = @cad.Component::new(
    name + "_tread_part",
    description="Wheel TPU tread",
  ).add_body(
    @cad.BodyPart::tube_mm(
      name + "_tire",
      radius_mm * 2.0,
      hub_radius_mm * 2.0,
      width_mm,
      rx_deg=90.0,
      density~,
      color=@step_cad.Rgb::black(),
    ).with_part(tread_part),
  )
  if detail_is_rich(detail) {
    // A separate printed rim ties the hub and TPU tread together.
    hub_comp = hub_comp.add_body(
      @cad.BodyPart::tube_mm(
        name + "_rim",
        hub_radius_mm * 2.0 + 6.0,
        hub_radius_mm * 2.0 - 6.0,
        width_mm * 0.92,
        rx_deg=90.0,
        density=@urdf.Density::petg(),
        color=@step_cad.Rgb::orange(),
      ).with_part(hub_part),
    )
    // Radial chevron/lug tread around the TPU tire.
    let lug_count = 12
    for i in 0..<lug_count {
      let theta = 2.0 * @math.PI * i.to_double() / lug_count.to_double()
      tread_comp = tread_comp.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_lug_\{i}",
          5.0,
          width_mm * 0.72,
          radius_mm * 0.22,
          x_mm=(radius_mm - 1.5) * @math.cos(theta),
          z_mm=(radius_mm - 1.5) * @math.sin(theta),
          ry_deg=-theta * 180.0 / @math.PI,
          density~,
          color=@step_cad.Rgb::black(),
        ).with_part(tread_part),
      )
    }
    // Lightening spokes run radially from just outside the shaft bore to the
    // hub rim, so they never block the output shaft.
    for i in 0..<4 {
      let theta = @math.PI * i.to_double() / 2.0
      let spoke_len = hub_radius_mm * 0.70
      let spoke_center = hub_radius_mm * 0.60
      hub_comp = hub_comp.add_body(
        @cad.BodyPart::box_mm(
          "\{name}_spoke_\{i}",
          spoke_len,
          width_mm * 0.18,
          width_mm * 0.35,
          x_mm=spoke_center * @math.cos(theta),
          z_mm=spoke_center * @math.sin(theta),
          ry_deg=-theta * 180.0 / @math.PI,
          density=@urdf.Density::petg(),
          color=@step_cad.Rgb::orange(),
        ).with_part(hub_part),
      )
    }
  }
  hub_comp = hub_comp.with_part(hub_part)
  tread_comp = tread_comp.with_part(tread_part)
  let mut wheel = @cad.Component::new(name, description="Treaded wheel")
    .with_param("radius_mm", radius_mm.to_string())
    .with_param("width_mm", width_mm.to_string())
    .with_param("hub_bore_mm", hub_bore_mm.to_string())
    .add_mate_mm_deg("axle", axis=(0.0, 1.0, 0.0))
    // Bearing and collar seats are rotated so their bores run along the wheel
    // spin axis (+Y) instead of the primitives' default +Z.
    .add_mate_mm_deg("axle_bearing_seat", rx_deg=90.0, axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg("axle_collar_seat", rx_deg=90.0, axis=(0.0, 1.0, 0.0))
    .add_mate_mm_deg("outer_face", x=width_mm / 2.0, axis=(1.0, 0.0, 0.0))
    // Frame for bolting the wheel directly to a planetary actuator output
    // shaft: the wheel's spin axis (+Y) maps to the actuator's +Z.
    .add_mate_mm_deg("drive_mount", rx_deg=-90.0, axis=(0.0, 1.0, 0.0))
    .attach(
      name + "_hub_merge",
      parent_mate="origin",
      hub_comp,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
    .attach(
      name + "_tread_merge",
      parent_mate="origin",
      tread_comp,
      child_mate="origin",
      spec=@cad.JointSpec::merge_rigid(),
    )
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
      parent_mate="axle_bearing_seat",
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
    )
    wheel = wheel.attach(
      "hub_collar_merge",
      parent_mate="axle_collar_seat",
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
/// Every joint is driven by a real `planetary_bldc_actuator`. The actuator's
/// motor rotor is the commanded input; its printed planetary carrier is the
/// moving output, and the next link bolts directly to that carrier's output
/// shaft. The hip link is a printed clevis bracket, the thigh and calf are
/// printed leg segments with bearing seats, and the wheel is a printable hub
/// and TPU tread.
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
) -> @cad.Component {
  // Joint effort and velocity limits come from the actuator's own rating.
  let _ = (max_effort_nm, max_vel_rad_s)
  let sign = if is_left { 1.0 } else { -1.0 }
  let leg_thickness_mm = 28.0
  let wheel_width_mm = 45.0
  // The actuator output shaft is extended past its printed cover so each
  // link's proximal boss sits fully on the shaft with clearance to the cover.
  let link_extension_mm = 36.0
  let leg_offset_mm = -(leg_thickness_mm / 2.0)
  let wheel_extension_mm = wheel_width_mm + 10.0
  let preset = "5010_360kv"
  let module_mm = 1.0
  let sun_teeth = 12
  let planet_teeth = 12
  let planet_count = 3
  let gear_length_mm = 10.0
  let thigh_name = prefix + "_thigh_link"
  let calf_name = prefix + "_calf_link"
  let wheel_name = prefix + "_wheel_link"
  let mount_mate = if is_left {
    "proximal_mount"
  } else {
    "proximal_mount_mirror"
  }
  let distal_mount_mate = if is_left {
    "distal_mount_left"
  } else {
    "distal_mount_right"
  }
  // Every actuator mounts through its own `motor_mount` face, a pure
  // translation. The joint-axis rotation is carried by the parent-side mate so
  // the actuator's internal links stay correctly placed when it is rebased.
  let new_drive = fn(
    drive_name : String,
    joint : String,
    extension : Double,
  ) -> @cad.Component {
    planetary_bldc_actuator(
      name=drive_name,
      preset~,
      stages=1,
      module_mm~,
      sun_teeth~,
      planet_teeth~,
      planet_count~,
      gear_length_mm~,
      gear_type="spur",
      detail~,
      joint_name=joint,
      add_binding=false,
      output_encoder=false,
      output_shaft_extension_mm=extension,
      // The printed leg housing is tapped directly; the compact motor bay has
      // no room for separate insert flanges.
      heat_set_inserts=false,
    )
  }
  // Hip abduction. The chassis bolts to the stator; the printed clevis
  // bracket is bolted to the rotating carrier's output shaft.
  let hip_drive = new_drive(
    prefix + "_hip_drive",
    prefix + "_hip_joint",
    link_extension_mm,
  )
  let bracket_name = prefix + "_hip_bracket"
  let bracket_part = fabricated_part(
    "HIP-BRACKET-\{hip_offset_y_mm}",
    "Quadruped hip clevis bracket",
    "carbon fiber nylon",
    "3D print",
    14.0,
  )
  let bracket_arm_len = if hip_offset_y_mm > 17.0 {
    hip_offset_y_mm - 17.0
  } else {
    0.0
  }
  let bracket = @cad.Component::new(
      bracket_name,
      description="Quadruped hip clevis bracket",
    )
    .with_param("hip_offset_y_mm", hip_offset_y_mm.to_string())
    .add_body(
      @cad.BodyPart::tube_mm(
        bracket_name + "_hub",
        34.0,
        8.2,
        20.0,
        ry_deg=90.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::orange(),
      ).with_part(bracket_part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        bracket_name + "_arm",
        22.0,
        bracket_arm_len,
        20.0,
        y_mm=sign * (hip_offset_y_mm + 17.0) / 2.0,
        density=@urdf.Density::carbon_fiber(),
        color=@step_cad.Rgb::orange(),
      ).with_part(bracket_part),
    )
    .add_body(
      // The thigh actuator's outrunner nests in this cup.
      leg_motor_cup_body(
        bracket_name + "_motor_cup",
        0.0,
        sign * (hip_offset_y_mm + leg_motor_cup_length_mm / 2.0 - 8.0),
        0.0,
        @urdf.Density::carbon_fiber(),
        @step_cad.Rgb::orange(),
        detail,
      ).with_part(bracket_part),
    )
    .with_part(bracket_part)
    // The hub frame is rotated so the bracket itself ends up world-aligned
    // after snapping onto the hip actuator's rotated carrier.
    .add_mate_mm_deg("hub", ry_deg=90.0, axis=(1.0, 0.0, 0.0))
    .add_mate_mm_deg(
      "distal_mount",
      y=sign * (hip_offset_y_mm + leg_motor_cup_length_mm),
      rx_deg=if is_left { -90.0 } else { 90.0 },
      axis=(0.0, 1.0, 0.0),
    )
  let hip_drive = hip_drive.attach_to(
    prefix + "_hip_drive_stage1_carrier",
    prefix + "_hip_bracket_joint",
    parent_mate="output_shaft",
    bracket,
    child_mate="hub",
    spec=@cad.JointSpec::fixed(offset_mm=-12.0),
  )
  // Hip pitch.
  let thigh_drive = new_drive(
    prefix + "_thigh_drive",
    prefix + "_thigh_joint",
    link_extension_mm,
  )
  let hip_drive = hip_drive.attach_to(
    bracket_name,
    prefix + "_thigh_drive_mount",
    parent_mate="distal_mount",
    thigh_drive,
    child_mate="motor_mount",
    spec=@cad.JointSpec::fixed(),
  )
  // Knee pitch.
  let knee_drive = new_drive(
    prefix + "_knee_drive",
    prefix + "_calf_joint",
    link_extension_mm,
  )
  let mut thigh = robot_leg_segment(
    thigh_name,
    length_mm=thigh_length_mm,
    distal_cup_offset_mm=-sign * 10.0,
    detail~,
  )
  thigh = thigh.attach(
    prefix + "_knee_drive_mount",
    parent_mate=distal_mount_mate,
    knee_drive,
    child_mate="motor_mount",
    spec=@cad.JointSpec::fixed(),
  )
  let hip_drive = hip_drive.attach_to(
    prefix + "_thigh_drive_stage1_carrier",
    prefix + "_thigh_link_joint",
    parent_mate="output_shaft",
    thigh,
    child_mate=mount_mate,
    spec=@cad.JointSpec::fixed(offset_mm=leg_offset_mm),
  )
  let mut calf = robot_leg_segment(
    calf_name,
    length_mm=calf_length_mm,
    distal_cup_offset_mm=-sign * 10.0,
    detail~,
  )
  if detail_is_rich(detail) && !wheeled {
    let force = force_sensor(name=calf_name + "_foot_sensor")
    calf = calf.attach(
      prefix + "_foot_sensor_merge",
      parent_mate="distal_joint",
      force,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  if detail_is_rich(detail) {
    let wire = @cad.WireRun::new(
      "\{prefix}_motor_power",
      from_component=prefix + "_hip_drive",
      from_port="power",
      to_component=calf_name,
      to_port="power",
      gauge_awg=18,
      length_mm=calf_length_mm * 2.0,
    )
    calf = calf.add_wire_run(wire)
    let harness = cable_route(
      name=calf_name + "_harness",
      // Start the jacket on the side of the link, clear of the proximal
      // actuator shaft.
      points=[
        (16.0, 0.0, -16.0),
        (16.0, 18.0, -calf_length_mm * 0.35),
        (16.0, 8.0, -calf_length_mm * 0.8),
      ],
      jacket_diameter_mm=5.0,
      wire_names=["\{prefix}_motor_power"],
      material="PVC",
      from_component=prefix + "_hip_drive",
      from_port="power",
      to_component=calf_name,
      to_port="power",
    )
    calf = calf.attach(
      prefix + "_leg_harness_merge",
      parent_mate="proximal_joint",
      harness,
      child_mate="mount",
      spec=@cad.JointSpec::merge_rigid(),
    )
  }
  if wheeled {
    let wheel_drive = new_drive(
      prefix + "_wheel_drive",
      prefix + "_wheel_joint",
      wheel_extension_mm,
    )
    let calf_with_drive = calf.attach(
      prefix + "_wheel_drive_mount",
      parent_mate=distal_mount_mate,
      wheel_drive,
      child_mate="motor_mount",
      spec=@cad.JointSpec::fixed(),
    )
    let wheel = treaded_wheel(
      wheel_name,
      radius_mm=wheel_diam_mm / 2.0,
      width_mm=wheel_width_mm,
      hub_bore_mm=8.0,
      hub_bolt_circle_mm=20.0,
      detail~,
    )
    let wheel_offset = 2.0 + wheel_width_mm / 2.0 - wheel_extension_mm
    let calf_with_wheel = calf_with_drive.attach_to(
      prefix + "_wheel_drive_stage1_carrier",
      prefix + "_wheel_joint_mount",
      parent_mate="output_shaft",
      wheel,
      child_mate="drive_mount",
      spec=@cad.JointSpec::fixed(offset_mm=wheel_offset),
    )
    let calf_with_wheel = calf_with_wheel.attach_to(
      prefix + "_wheel_drive_stage1_carrier",
      prefix + "_wheel_collar_merge",
      parent_mate="output_shaft",
      shaft_collar(
        name=wheel_name + "_collar",
        bore_diam_mm=8.0,
        outer_diam_mm=16.0,
        width_mm=4.0,
        style="set_screw",
        thread_size=@step_standards.M3,
      ),
      child_mate="origin",
      spec=@cad.JointSpec::fixed(offset_mm=-5.0),
    )
    hip_drive.attach_to(
      prefix + "_knee_drive_stage1_carrier",
      prefix + "_calf_link_joint",
      parent_mate="output_shaft",
      calf_with_wheel,
      child_mate=mount_mate,
      spec=@cad.JointSpec::fixed(offset_mm=leg_offset_mm),
    )
  } else {
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
          z_mm=-calf_length_mm - leg_motor_cup_length_mm - 20.0,
          density=@urdf.Density::tpu(),
          color=@step_cad.Rgb::black(),
        ).with_part(foot_part),
      )
      .add_mate_mm_deg("mount")
    hip_drive.attach_to(
      prefix + "_knee_drive_stage1_carrier",
      prefix + "_calf_link_joint",
      parent_mate="output_shaft",
      calf.attach(
        "\{prefix}_ankle_joint",
        parent_mate="distal_joint",
        foot,
        child_mate="mount",
        spec=@cad.JointSpec::fixed(),
      ),
      child_mate=mount_mate,
      spec=@cad.JointSpec::fixed(offset_mm=leg_offset_mm),
    )
  }
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
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
) -> @cad.Component {
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
/// A compact printable + purchased actuator pod envelope.
///
/// This is the simplified geometry that a low-KV BLDC outrunner plus planetary
/// reduction presents at a joint: a motor can, a printed planetary housing, and
/// a printed output flange. It is kept for compatibility with earlier models;
/// `quadruped_leg_assembly` and `planetary_wheel_drive_unit` now use real
/// `planetary_bldc_actuator` modules instead.
pub fn actuator_pod_geometry(
  name : String,
  preset~ : String = "5010_360kv",
  ring_outer_mm~ : Double = 56.0,
  gear_length_mm~ : Double = 8.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let p = resolve_bldc_preset(preset)
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
) -> @cad.Component {
  // The output shaft is extended past the printed cover so the wheel can sit
  // outboard of it while remaining on the rotating carrier's real output
  // shaft. The wheel then needs no synthetic axle frame.
  let wheel_extension = wheel_width_mm + 10.0
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
    joint_name=name + "_wheel_joint",
    add_binding=false,
    output_encoder=false,
    output_shaft_extension_mm=wheel_extension,
    heat_set_inserts=false,
  )
  let final_stage = if stages >= 2 { "stage2" } else { "stage1" }
  let carrier = name + "_drive_" + final_stage + "_carrier"
  let wheel = treaded_wheel(
    name + "_wheel",
    radius_mm=wheel_diam_mm / 2.0,
    width_mm=wheel_width_mm,
    hub_radius_mm=wheel_diam_mm * 0.18,
    // The actuator output is an 8 mm steel shaft through two 608 bearings.
    hub_bore_mm=8.0,
    detail~,
  )
  // Put the wheel's inboard face 2.5 mm outboard of the cover face.
  let wheel_offset = 2.0 + wheel_width_mm / 2.0 - wheel_extension
  let mut out = actuator.attach_to(
    carrier,
    "\{name}_wheel_joint_mount",
    parent_mate="output_shaft",
    wheel,
    child_mate="drive_mount",
    spec=@cad.JointSpec::fixed(offset_mm=wheel_offset),
  )
  // A set-screw clamp collar outboard of the wheel retains it on the shaft.
  out = out.attach_to(
    carrier,
    "\{name}_wheel_collar_merge",
    parent_mate="output_shaft",
    shaft_collar(
      name=name + "_wheel_collar",
      bore_diam_mm=8.0,
      outer_diam_mm=16.0,
      width_mm=4.0,
      style="set_screw",
      thread_size=@step_standards.M3,
    ),
    child_mate="origin",
    spec=@cad.JointSpec::fixed(offset_mm=-5.0),
  )
  out
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
) -> @cad.Component {
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
