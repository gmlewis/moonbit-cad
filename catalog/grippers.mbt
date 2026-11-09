///|
/// Reusable end-effectors: a compact 1-DOF parallel-jaw gripper with a solid
/// base, an integral fixed finger, and a moving finger on a prismatic joint.

///|
/// Builds a parallel-jaw gripper.
///
/// The base is a solid block with a fixed finger on one side and a sliding
/// finger on the other.  The moving finger is a child link on a prismatic
/// joint; drive it with the `"<name>_jaw"` joint position (metres).
///
/// Layout (local frame):
/// - `mount` is on the rear face at `Z = 0`, normal `+Z`.
/// - The fingers extend along `+Z`; the jaws open/close along `X`.
/// - At joint position `0` the opening is `opening_mm`; travel closes it to
///   `opening_mm - travel_mm`.
///
/// Mates: `"mount"` (rear, `+Z`), `"jaw_slide"` (base front, axis `+X`).
pub fn parallel_gripper(
  name~ : String = "parallel_gripper",
  opening_mm~ : Double = 30.0,
  travel_mm~ : Double = 28.0,
  finger_len_mm~ : Double = 45.0,
  finger_width_mm~ : Double = 45.0,
  finger_thick_mm~ : Double = 8.0,
  base_thick_mm~ : Double = 12.0,
  finger_overlap_mm~ : Double = 4.0,
  effort_n~ : Double = 20.0,
  velocity_mps~ : Double = 0.05,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let half_open = opening_mm / 2.0
  let mm_per_m = 1000.0
  let base_w = opening_mm + 2.0 * finger_thick_mm
  let jaw_name = name + "_jaw"
  let base = @cad.Component::new(name, description="Parallel-jaw gripper")
    .with_param("opening_mm", opening_mm.to_string())
    .with_param("travel_mm", travel_mm.to_string())
    .with_param("finger_len_mm", finger_len_mm.to_string())
    .with_param("finger_width_mm", finger_width_mm.to_string())
    .with_param("finger_thick_mm", finger_thick_mm.to_string())
    .with_param("base_thick_mm", base_thick_mm.to_string())
    .with_param("finger_overlap_mm", finger_overlap_mm.to_string())
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_base",
        base_w,
        finger_width_mm,
        base_thick_mm,
        z_mm=base_thick_mm / 2.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_fixed_finger",
        finger_thick_mm,
        finger_width_mm,
        finger_len_mm + finger_overlap_mm,
        x_mm=half_open + finger_thick_mm / 2.0,
        z_mm=base_thick_mm + finger_len_mm / 2.0 - finger_overlap_mm / 2.0,
        density~,
        color~,
      ),
    )
    .add_mate_mm_deg("mount")
    .add_mate_mm_deg("jaw_slide", z=base_thick_mm, axis=(1.0, 0.0, 0.0))
  let jaw = @cad.Component::new(jaw_name, description="Moving gripper jaw")
    .add_body(
      @cad.BodyPart::box_mm(
        jaw_name + "_finger",
        finger_thick_mm,
        finger_width_mm,
        finger_len_mm,
        x_mm=-(half_open + finger_thick_mm / 2.0),
        z_mm=finger_len_mm / 2.0,
        density~,
        color~,
      ),
    )
    .add_mate_mm_deg("mount")
  base.attach(
    jaw_name,
    parent_mate="jaw_slide",
    jaw,
    child_mate="mount",
    spec=@cad.JointSpec::prismatic(
      @urdf.JointLimit::new(
        effort=effort_n,
        velocity=velocity_mps,
        lower=Some(0.0),
        upper=Some(travel_mm / mm_per_m),
      ),
    ),
  )
}

///|
/// Builds a motorized, threaded lead-screw parallel-jaw gripper.
///
/// The frame is deliberately skeletal: two end plates, a bottom beam, a rear
/// wrist flange, and two guide rails.  The screw, nut, bushings, and drive
/// train are visible from the sides and top.  A NEMA 8 stepper turns a
/// threaded lead screw through a coupler; the screw drives a nut on the moving
/// carriage; two guide rails take the moment; the screw's far end runs in a
/// ball bearing.  The jaw is a prismatic joint **mimicking the motor rotor**:
/// command the motor and the jaw follows through the screw lead.  Two limit
/// switches sit on brackets above the carriage, and a controller PCB mounts on
/// the outside of the bottom beam; `--report` prints their power/IO budget.
///
/// Layout (local frame):
/// - `mount` is on the rear flange at `Z = 0`, normal `+Z`.
/// - The jaws extend along `+Z`; the carriage slides along `X`.
/// - The motor is on the `-X` end plate; the screw runs along `X`.
///
/// Mates: `"mount"`, `"jaw_slide"` (axis `+X`), `"motor_mount"`, and
/// `"bearing_seat"`.  Joints: `"<name>_motor_shaft_joint"` (continuous) and
/// `"<name>_jaw"` (prismatic, mimic of the motor).
pub fn lead_screw_gripper(
  name~ : String = "lead_screw_gripper",
  opening_mm~ : Double = 30.0,
  travel_mm~ : Double = 28.0,
  lead_mm~ : Double = 2.0,
  finger_len_mm~ : Double = 45.0,
  finger_width_mm~ : Double = 45.0,
  finger_thick_mm~ : Double = 8.0,
  grip_pad_mm~ : Double = 3.0,
  base_depth_mm~ : Double = 70.0,
  base_h_mm~ : Double = 58.0,
  base_w_mm~ : Double = 84.0,
  wall_mm~ : Double = 6.0,
  screw_diam_mm~ : Double = 6.0,
  thread_od_mm~ : Double = 7.2,
  rail_diam_mm~ : Double = 6.0,
  rail_y_mm~ : Double = 16.0,
  motor_frame_mm~ : Double = 20.3,
  motor_body_mm~ : Double = 20.0,
  motor_shaft_mm~ : Double = 12.0,
  motor_shaft_diam_mm~ : Double = 4.0,
  motor_boss_diam_mm~ : Double = 15.0,
  motor_boss_height_mm~ : Double = 1.5,
  motor_effort_nm~ : Double = 0.05,
  motor_vel_rad_s~ : Double = 20.0,
  coupler_len_mm~ : Double = 8.0,
  coupler_outer_mm~ : Double = 10.0,
  motor_shaft_fit_mm~ : Double = 0.2,
  screw_fit_mm~ : Double = 0.2,
  nut_outer_mm~ : Double = 16.0,
  nut_len_mm~ : Double = 12.0,
  nut_fit_mm~ : Double = 0.4,
  bushing_outer_mm~ : Double = 12.0,
  bushing_len_mm~ : Double = 14.0,
  bushing_fit_mm~ : Double = 0.2,
  bearing_outer_mm~ : Double = 16.0,
  bearing_width_mm~ : Double = 5.0,
  bearing_fit_mm~ : Double = 0.2,
  thread_crest_width_mm~ : Double = 1.0,
  thread_crest_fit_mm~ : Double = 0.05,
  thread_journal_mm~ : Double = 12.5,
  bearing_journal_mm~ : Double = 4.0,
  grip_finger_overlap_mm~ : Double = 1.0,
  flange_bolt_diam_mm~ : Double = 4.5,
  flange_bolt_pitch_x_mm~ : Double = 60.0,
  flange_bolt_pitch_y_mm~ : Double = 36.0,
  motor_hole_diam_mm~ : Double = 17.0,
  motor_bolt_diam_mm~ : Double = 3.0,
  motor_bolt_pitch_mm~ : Double = 20.0,
  bearing_hole_diam_mm~ : Double = 16.4,
  bearing_bolt_diam_mm~ : Double = 3.0,
  bearing_bolt_pitch_mm~ : Double = 24.0,
  jaw_effort_n~ : Double = 200.0,
  jaw_velocity_mps~ : Double = 0.05,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  // Units and layout constants.
  let mm_per_m = 1000.0
  let right_angle_deg = 90.0
  let rad_per_rev = 2.0 * @math.PI
  let jaw_lower_mm = 0.0
  let rail_engagement_mm = 4.0
  let carriage_plate_z_mm = 8.0
  let carriage_plate_thick_mm = 8.0
  let post_start_z_mm = 8.0
  let carriage_width_inset_mm = 4.0
  let bracket_thick_mm = 8.0
  let bracket_setback_mm = 2.0
  let slide_axis = (1.0, 0.0, 0.0)
  // Limit-switch brackets sit above the moving carriage, welded to the bottom
  // beam; the switches ride on the brackets.  The PCB sits on the beam's
  // outside face.
  let switch_body_len_mm = 10.0
  let switch_bracket_w_mm = 10.0
  let switch_bracket_depth_mm = 11.0
  let switch_bracket_t_mm = 2.0
  let switch_bracket_y_mm = -base_h_mm / 2.0 +
    wall_mm +
    switch_bracket_depth_mm / 2.0
  let switch_bracket_z_mm = carriage_plate_z_mm +
    carriage_plate_thick_mm / 2.0 +
    switch_bracket_t_mm / 2.0
  let switch_mount_z_mm = switch_bracket_z_mm + switch_bracket_t_mm / 2.0
  let home_switch_x_mm = -base_w_mm / 2.0 + wall_mm + switch_body_len_mm / 2.0
  let closed_switch_x_mm = travel_mm + bracket_setback_mm
  let pcb_len_mm = 44.0
  let pcb_w_mm = 32.0
  // Derived geometry.
  let half_open = opening_mm / 2.0
  let half_base = base_w_mm / 2.0
  let plate_z = wall_mm / 2.0
  let screw_z = base_depth_mm / 2.0
  let wall_inner = half_base - wall_mm
  let jaw_name = name + "_jaw"
  let motor_name = name + "_motor"
  let coupler_name = name + "_coupler"
  let screw_name = name + "_screw"
  let motor_joint = motor_name + "_shaft_joint"
  // The motor face sits on the -X end plate; the shaft and coupler occupy the
  // first part of the frame, then the threaded screw runs to the far bearing.
  let motor_face_x = -half_base
  let shaft_tip_x = motor_face_x + motor_boss_height_mm + motor_shaft_mm
  let coupler_out_x = shaft_tip_x + coupler_len_mm
  let bearing_x = wall_inner
  let screw_len = bearing_x - coupler_out_x
  let screw_center_x = (coupler_out_x + bearing_x) / 2.0
  let rail_len = base_w_mm - 2.0 * wall_mm + 2.0 * rail_engagement_mm
  let finger_z = base_depth_mm + finger_len_mm / 2.0 - screw_z
  let finger_center_x = half_open + grip_pad_mm + finger_thick_mm / 2.0
  let arm_x = finger_center_x - grip_finger_overlap_mm
  let fixed_inner_x = arm_x - finger_thick_mm / 2.0
  let bracket_x0 = fixed_inner_x
  let bracket_w = half_base - bracket_x0
  let bracket_xc = (half_base + bracket_x0) / 2.0
  let thread_start_x = coupler_out_x + thread_journal_mm
  let thread_end_x = bearing_x - bearing_journal_mm
  let thread_count = ((thread_end_x - thread_start_x) / lead_mm).to_int()
  let half_lead_mm = lead_mm / 2.0
  let flange_bolt_dx = flange_bolt_pitch_x_mm / 2.0
  let flange_bolt_dy = flange_bolt_pitch_y_mm / 2.0
  let flange_pts : Array[(Double, Double)] = [
    (-flange_bolt_dx, -flange_bolt_dy),
    (flange_bolt_dx, -flange_bolt_dy),
    (flange_bolt_dx, flange_bolt_dy),
    (-flange_bolt_dx, flange_bolt_dy),
  ]
  let flange_holes = flange_pts.map(fn(p) {
    @step_cad.translate_pts(
      @step_cad.Profile2D::circle(flange_bolt_diam_mm),
      p.0,
      p.1,
    ).rev()
  })
  let motor_bolt_d = motor_bolt_pitch_mm / 2.0
  let motor_holes : Array[Array[(Double, Double)]] = [
    @step_cad.Profile2D::circle(motor_hole_diam_mm).rev(),
  ]
  for
    p in [
      (-motor_bolt_d, -motor_bolt_d),
      (motor_bolt_d, -motor_bolt_d),
      (motor_bolt_d, motor_bolt_d),
      (-motor_bolt_d, motor_bolt_d),
    ] {
    motor_holes.push(
      @step_cad.translate_pts(
        @step_cad.Profile2D::circle(motor_bolt_diam_mm),
        p.0,
        p.1,
      ).rev(),
    )
  }
  let bearing_bolt_d = bearing_bolt_pitch_mm / 2.0
  let bearing_holes : Array[Array[(Double, Double)]] = [
    @step_cad.Profile2D::circle(bearing_hole_diam_mm).rev(),
  ]
  for
    p in [
      (-bearing_bolt_d, -bearing_bolt_d),
      (bearing_bolt_d, -bearing_bolt_d),
      (bearing_bolt_d, bearing_bolt_d),
      (-bearing_bolt_d, bearing_bolt_d),
    ] {
    bearing_holes.push(
      @step_cad.translate_pts(
        @step_cad.Profile2D::circle(bearing_bolt_diam_mm),
        p.0,
        p.1,
      ).rev(),
    )
  }
  let base = @cad.Component::new(name, description="Lead-screw gripper")
    .with_param("opening_mm", opening_mm.to_string())
    .with_param("travel_mm", travel_mm.to_string())
    .with_param("lead_mm", lead_mm.to_string())
    .with_param("finger_len_mm", finger_len_mm.to_string())
    .with_param("finger_width_mm", finger_width_mm.to_string())
    .with_param("grip_pad_mm", grip_pad_mm.to_string())
    .with_param("screw_diam_mm", screw_diam_mm.to_string())
    .with_param("thread_od_mm", thread_od_mm.to_string())
    .with_param("rail_diam_mm", rail_diam_mm.to_string())
    .with_param("nut_len_mm", nut_len_mm.to_string())
    .with_param("bushing_len_mm", bushing_len_mm.to_string())
    .with_param("bearing_outer_mm", bearing_outer_mm.to_string())
    // Bolt-ready wrist flange.
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_wrist_flange",
        @step_cad.Profile2D::centered_rect(base_w_mm, base_h_mm),
        wall_mm,
        holes=flange_holes,
        z_mm=plate_z,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_bottom_beam",
        base_w_mm,
        wall_mm,
        base_depth_mm,
        y_mm=-base_h_mm / 2.0 + plate_z,
        z_mm=base_depth_mm / 2.0,
        density~,
        color~,
      ),
    )
    // End plates carry the motor and the screw bearing; both have clearance
    // holes and bolt patterns, and the guide rails weld into their inner faces.
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_motor_plate",
        @step_cad.Profile2D::centered_rect(base_depth_mm, base_h_mm),
        wall_mm,
        holes=motor_holes,
        x_mm=-half_base + plate_z,
        z_mm=screw_z,
        ry_deg=right_angle_deg,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_bearing_plate",
        @step_cad.Profile2D::centered_rect(base_depth_mm, base_h_mm),
        wall_mm,
        holes=bearing_holes,
        x_mm=half_base - plate_z,
        z_mm=screw_z,
        ry_deg=right_angle_deg,
        density~,
        color~,
      ),
    )
    // Fixed jaw: a bracket from the +X end plate to an identical finger, with
    // a bolt-ready grip pad.  The bracket stays outside the moving jaw's path.
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_fixed_bracket",
        bracket_w,
        finger_width_mm,
        bracket_thick_mm,
        x_mm=bracket_xc,
        z_mm=base_depth_mm - bracket_setback_mm,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_fixed_finger",
        finger_thick_mm,
        finger_width_mm,
        finger_len_mm,
        x_mm=arm_x,
        z_mm=base_depth_mm + finger_len_mm / 2.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_fixed_pad",
        grip_pad_mm,
        finger_width_mm,
        finger_len_mm,
        x_mm=half_open + grip_pad_mm / 2.0,
        z_mm=base_depth_mm + finger_len_mm / 2.0,
        density~,
        color=@step_cad.Rgb::black(),
      ),
    )
    // Two guide rails, welded into the end plates and visible between them.
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_rail_left",
        rail_diam_mm,
        rail_len,
        y_mm=rail_y_mm,
        z_mm=screw_z,
        ry_deg=right_angle_deg,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_rail_right",
        rail_diam_mm,
        rail_len,
        y_mm=-rail_y_mm,
        z_mm=screw_z,
        ry_deg=right_angle_deg,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_home_switch_bracket",
        switch_bracket_w_mm,
        switch_bracket_depth_mm,
        switch_bracket_t_mm,
        x_mm=home_switch_x_mm,
        y_mm=switch_bracket_y_mm,
        z_mm=switch_bracket_z_mm,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_closed_switch_bracket",
        switch_bracket_w_mm,
        switch_bracket_depth_mm,
        switch_bracket_t_mm,
        x_mm=closed_switch_x_mm,
        y_mm=switch_bracket_y_mm,
        z_mm=switch_bracket_z_mm,
        density~,
        color~,
      ),
    )
    .add_mate_mm_deg("mount")
    .add_mate_mm_deg("jaw_slide", z=screw_z, axis=slide_axis)
    .add_mate_mm_deg(
      "motor_mount",
      x=-half_base,
      z=screw_z,
      ry_deg=right_angle_deg,
    )
    .add_mate_mm_deg(
      "bearing_seat",
      x=bearing_x,
      z=screw_z,
      ry_deg=right_angle_deg,
    )
    .add_mate_mm_deg(
      "home_switch_mount",
      x=home_switch_x_mm,
      y=switch_bracket_y_mm,
      z=switch_mount_z_mm,
    )
    .add_mate_mm_deg(
      "closed_switch_mount",
      x=closed_switch_x_mm,
      y=switch_bracket_y_mm,
      z=switch_mount_z_mm,
    )
    .add_mate_mm_deg(
      "pcb_mount",
      y=-base_h_mm / 2.0,
      z=base_depth_mm / 2.0,
      rx_deg=right_angle_deg,
    )
  // Moving jaw: nut, bushings, compact carriage plate, post, identical finger,
  // and grip pad.  It is an L so the post travels behind the fixed jaw.
  let jaw = @cad.Component::new(jaw_name, description="Lead-screw jaw carriage")
    .with_param("opening_mm", opening_mm.to_string())
    .with_param("travel_mm", travel_mm.to_string())
    .add_body(
      @cad.BodyPart::tube_mm(
        jaw_name + "_nut",
        nut_outer_mm,
        thread_od_mm + nut_fit_mm,
        nut_len_mm,
        ry_deg=right_angle_deg,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        jaw_name + "_bushing_left",
        bushing_outer_mm,
        rail_diam_mm + bushing_fit_mm,
        bushing_len_mm,
        y_mm=rail_y_mm,
        ry_deg=right_angle_deg,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        jaw_name + "_bushing_right",
        bushing_outer_mm,
        rail_diam_mm + bushing_fit_mm,
        bushing_len_mm,
        y_mm=-rail_y_mm,
        ry_deg=right_angle_deg,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        jaw_name + "_carriage",
        arm_x,
        finger_width_mm - carriage_width_inset_mm,
        carriage_plate_thick_mm,
        x_mm=-arm_x / 2.0,
        z_mm=carriage_plate_z_mm,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        jaw_name + "_post",
        finger_thick_mm,
        finger_width_mm,
        finger_z - post_start_z_mm,
        x_mm=-arm_x,
        z_mm=post_start_z_mm + (finger_z - post_start_z_mm) / 2.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        jaw_name + "_finger",
        finger_thick_mm,
        finger_width_mm,
        finger_len_mm,
        x_mm=-arm_x,
        z_mm=finger_z,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        jaw_name + "_pad",
        grip_pad_mm,
        finger_width_mm,
        finger_len_mm,
        x_mm=-(half_open + grip_pad_mm / 2.0),
        z_mm=finger_z,
        density~,
        color=@step_cad.Rgb::black(),
      ),
    )
    .add_mate_mm_deg("mount")
  // Part metadata and fastener schedule for the BOM.
  let flange_cost_usd = 18.0
  let beam_cost_usd = 12.0
  let plate_cost_usd = 14.0
  let bracket_cost_usd = 10.0
  let finger_cost_usd = 8.0
  let pad_cost_usd = 4.0
  let carriage_cost_usd = 12.0
  let post_cost_usd = 8.0
  let rail_cost_usd = 3.0
  let nut_cost_usd = 6.0
  let bushing_cost_usd = 4.0
  let bolt_m3_cost_usd = 0.35
  let bolt_m4_cost_usd = 0.45
  let flange_part = fabricated_part(
    "GRIP-WRIST-FLANGE", "Gripper wrist flange", "6061-T6", "CNC", flange_cost_usd,
  )
  let beam_part = fabricated_part(
    "GRIP-BOTTOM-BEAM", "Gripper bottom beam", "6061-T6", "CNC", beam_cost_usd,
  )
  let motor_plate_part = fabricated_part(
    "GRIP-MOTOR-PLATE", "Gripper motor plate", "6061-T6", "CNC", plate_cost_usd,
  )
  let bearing_plate_part = fabricated_part(
    "GRIP-BEARING-PLATE", "Gripper bearing plate", "6061-T6", "CNC", plate_cost_usd,
  )
  let bracket_part = fabricated_part(
    "GRIP-FIXED-BRACKET", "Fixed jaw bracket", "6061-T6", "CNC", bracket_cost_usd,
  )
  let finger_part = fabricated_part(
    "GRIP-FINGER", "Gripper finger", "6061-T6", "CNC", finger_cost_usd,
  )
  let pad_part = fabricated_part(
    "GRIP-PAD", "Gripper grip pad", "POM", "CNC", pad_cost_usd,
  )
  let rail_part = purchased_part(
    "GRIP-RAIL-6", "Guide rail 6 mm", "hardened steel", rail_cost_usd,
  )
  let nut_part = purchased_part(
    "GRIP-NUT-M6x2", "Lead-screw nut M6 x 2", "bronze", nut_cost_usd,
  )
  let bushing_part = purchased_part(
    "GRIP-BUSHING-6", "Guide bushing 6 mm", "bronze", bushing_cost_usd,
  )
  let carriage_part = fabricated_part(
    "GRIP-CARRIAGE", "Moving jaw carriage", "6061-T6", "CNC", carriage_cost_usd,
  )
  let post_part = fabricated_part(
    "GRIP-POST", "Moving jaw post", "6061-T6", "CNC", post_cost_usd,
  )
  tag_body(base, name + "_wrist_flange", flange_part)
  tag_body(base, name + "_bottom_beam", beam_part)
  tag_body(base, name + "_motor_plate", motor_plate_part)
  tag_body(base, name + "_bearing_plate", bearing_plate_part)
  tag_body(base, name + "_fixed_bracket", bracket_part)
  tag_body(base, name + "_fixed_finger", finger_part)
  tag_body(base, name + "_fixed_pad", pad_part)
  tag_body(base, name + "_rail_left", rail_part)
  tag_body(base, name + "_rail_right", rail_part)
  tag_body(jaw, jaw_name + "_nut", nut_part)
  tag_body(jaw, jaw_name + "_bushing_left", bushing_part)
  tag_body(jaw, jaw_name + "_bushing_right", bushing_part)
  tag_body(jaw, jaw_name + "_carriage", carriage_part)
  tag_body(jaw, jaw_name + "_post", post_part)
  tag_body(jaw, jaw_name + "_finger", finger_part)
  tag_body(jaw, jaw_name + "_pad", pad_part)
  let switch_bracket_part = fabricated_part(
    "GRIP-SWITCH-BRACKET", "Limit-switch bracket", "6061-T6", "CNC", 3.0,
  )
  tag_body(base, name + "_home_switch_bracket", switch_bracket_part)
  tag_body(base, name + "_closed_switch_bracket", switch_bracket_part)
  let motor_bolt_length_mm = 12.0
  let bearing_bolt_length_mm = 10.0
  let wrist_bolt_length_mm = 12.0
  let _ = base.add_fastener(
    @cad.Fastener::new(
      "motor_bolts",
      @cad.FastenerKind::Screw,
      thread="M3",
      length_mm=motor_bolt_length_mm,
      engagement_mm=6.0,
      quantity=4,
      torque_nm=1.2,
      references=["motor_plate", "motor_mount"],
      part=Some(
        purchased_part(
          "SHCS-M3x12", "Socket head cap screw M3 x 12", "steel", bolt_m3_cost_usd,
        ),
      ),
    ),
  )
  let _ = base.add_fastener(
    @cad.Fastener::new(
      "bearing_bolts",
      @cad.FastenerKind::Screw,
      thread="M3",
      length_mm=bearing_bolt_length_mm,
      engagement_mm=5.0,
      quantity=4,
      torque_nm=1.0,
      references=["bearing_plate", "screw_bearing"],
      part=Some(
        purchased_part(
          "SHCS-M3x10", "Socket head cap screw M3 x 10", "steel", bolt_m3_cost_usd,
        ),
      ),
    ),
  )
  let _ = base.add_fastener(
    @cad.Fastener::new(
      "wrist_bolts",
      @cad.FastenerKind::Screw,
      thread="M4",
      length_mm=wrist_bolt_length_mm,
      engagement_mm=8.0,
      quantity=4,
      torque_nm=2.5,
      references=["wrist_flange", "tool_out"],
      part=Some(
        purchased_part(
          "SHCS-M4x12", "Socket head cap screw M4 x 12", "steel", bolt_m4_cost_usd,
        ),
      ),
    ),
  )
  // Electrical interfaces and explicit fits (sensors/PCB come later).
  let _ = base.add_port(
    @cad.Port::new("motor_power", @cad.PortKind::Power, spec="24 V DC, 1.5 A"),
  )
  let _ = base.add_port(
    @cad.Port::new("motor_step_dir", @cad.PortKind::Signal, spec="TTL STEP/DIR"),
  )
  let _ = base.add_fit(
    @cad.Fit::new(
      "screw_nut",
      @cad.FitClass::Clearance,
      nominal_mm=screw_diam_mm,
      min_mm=screw_diam_mm,
      max_mm=screw_diam_mm + nut_fit_mm,
    ),
  )
  let _ = base.add_fit(
    @cad.Fit::new(
      "rail_bushing",
      @cad.FitClass::Clearance,
      nominal_mm=rail_diam_mm,
      min_mm=rail_diam_mm,
      max_mm=rail_diam_mm + bushing_fit_mm,
    ),
  )
  let _ = base.add_fit(
    @cad.Fit::new(
      "screw_bearing",
      @cad.FitClass::Clearance,
      nominal_mm=screw_diam_mm,
      min_mm=screw_diam_mm,
      max_mm=screw_diam_mm + bearing_fit_mm,
    ),
  )
  let controller_name = name + "_controller"
  let _ = base.add_wire_run(
    @cad.WireRun::new(
      "motor_power",
      from_component=controller_name,
      from_port="power",
      to_component=motor_name + "_stator",
      to_port="power",
      gauge_awg=20,
      length_mm=180.0,
    ),
  )
  let _ = base.add_wire_run(
    @cad.WireRun::new(
      "motor_step_dir",
      from_component=controller_name,
      from_port="motor",
      to_component=motor_name + "_stator",
      to_port="step_dir",
      gauge_awg=26,
      length_mm=180.0,
    ),
  )
  let _ = base.add_wire_run(
    @cad.WireRun::new(
      "home_signal",
      from_component=name + "_home_switch",
      from_port="signal",
      to_component=controller_name,
      to_port="limit_home",
      gauge_awg=26,
      length_mm=120.0,
    ),
  )
  let _ = base.add_wire_run(
    @cad.WireRun::new(
      "closed_signal",
      from_component=name + "_closed_switch",
      from_port="signal",
      to_component=controller_name,
      to_port="limit_closed",
      gauge_awg=26,
      length_mm=120.0,
    ),
  )
  let motor = nema_stepper(
    name=motor_name,
    frame_size_mm=motor_frame_mm,
    body_length_mm=motor_body_mm,
    boss_diam_mm=motor_boss_diam_mm,
    boss_height_mm=motor_boss_height_mm,
    shaft_diam_mm=motor_shaft_diam_mm,
    shaft_length_mm=motor_shaft_mm,
    max_effort_nm=motor_effort_nm,
    max_vel_rad_s=motor_vel_rad_s,
  )
  let coupler = shaft_coupler(
    name=coupler_name,
    outer_diam_mm=coupler_outer_mm,
    bore_in_mm=motor_shaft_diam_mm + motor_shaft_fit_mm,
    bore_out_mm=screw_diam_mm + screw_fit_mm,
    length_mm=coupler_len_mm,
  )
  // Threaded screw: a smooth journal at each end and crest rings between.
  let mut screw = @cad.Component::new(
    screw_name,
    description="Threaded lead screw",
  ).add_body(
    @cad.BodyPart::cylinder_mm(
      screw_name + "_body",
      screw_diam_mm,
      screw_len,
      density~,
      color~,
    ),
  )
  for i in 0..<thread_count {
    let ring_x = thread_start_x + i.to_double() * lead_mm + half_lead_mm
    screw = screw.add_body(
      @cad.BodyPart::tube_mm(
        screw_name + "_thread_" + i.to_string(),
        thread_od_mm,
        screw_diam_mm + thread_crest_fit_mm,
        thread_crest_width_mm,
        z_mm=ring_x - screw_center_x,
        density~,
        color~,
      ),
    )
  }
  screw = screw
    .add_mate_mm_deg("input", z=-screw_len / 2.0)
    .add_mate_mm_deg("output", z=screw_len / 2.0)
  screw = screw.with_part(
    fabricated_part(
      "LEAD-SCREW-M6x2", "Threaded lead screw M6 x 2 mm", "steel", "machined", 9.0,
    ),
  )
  let bearing = ball_bearing(
    name=name + "_screw_bearing",
    inner_diam_mm=screw_diam_mm + bearing_fit_mm,
    outer_diam_mm=bearing_outer_mm,
    width_mm=bearing_width_mm,
  )
  let home_switch = limit_switch(name=name + "_home_switch")
  let closed_switch = limit_switch(name=name + "_closed_switch")
  let controller = pcb_board(
    name=controller_name,
    length_mm=pcb_len_mm,
    width_mm=pcb_w_mm,
    connectors=["power", "motor", "limit_home", "limit_closed", "can"],
  )
  let multiplier = lead_mm / mm_per_m / rad_per_rev
  base
  .attach(
    "motor_mount",
    parent_mate="motor_mount",
    motor,
    child_mate="face_mount",
    spec=@cad.JointSpec::fixed(),
  )
  .attach_to(
    motor_name + "_rotor",
    "coupler_mount",
    parent_mate="shaft_tip",
    coupler,
    child_mate="input_shaft",
    spec=@cad.JointSpec::fixed(),
  )
  .attach_to(
    coupler_name,
    "screw_mount",
    parent_mate="output_shaft",
    screw,
    child_mate="input",
    spec=@cad.JointSpec::fixed(),
  )
  .attach(
    "bearing_mount",
    parent_mate="bearing_seat",
    bearing,
    child_mate="center",
    spec=@cad.JointSpec::fixed(),
  )
  .attach(
    jaw_name,
    parent_mate="jaw_slide",
    jaw,
    child_mate="mount",
    spec=@cad.JointSpec::prismatic(
      @urdf.JointLimit::new(
        effort=jaw_effort_n,
        velocity=jaw_velocity_mps,
        lower=Some(jaw_lower_mm / mm_per_m),
        upper=Some(travel_mm / mm_per_m),
      ),
      mimic=Some(@urdf.JointMimic::new(motor_joint, multiplier~)),
    ),
  )
  .attach(
    "home_switch_mount",
    parent_mate="home_switch_mount",
    home_switch,
    child_mate="mount",
    spec=@cad.JointSpec::fixed(),
  )
  .attach(
    "closed_switch_mount",
    parent_mate="closed_switch_mount",
    closed_switch,
    child_mate="mount",
    spec=@cad.JointSpec::fixed(),
  )
  .attach(
    "pcb_mount",
    parent_mate="pcb_mount",
    controller,
    child_mate="mount",
    spec=@cad.JointSpec::fixed(),
  )
}

///|
/// Attaches part metadata to one body by its generated body name.
fn tag_body(
  comp : @cad.Component,
  body_name : String,
  part : @cad.PartMeta,
) -> Unit {
  for i in 0..<comp.bodies.length() {
    if comp.bodies[i].name == body_name {
      comp.bodies[i] = comp.bodies[i].with_part(part)
    }
  }
}
