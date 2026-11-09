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
        upper=Some(travel_mm / 1000.0),
      ),
    ),
  )
}

///|
/// Builds a motorized lead-screw parallel-jaw gripper.
///
/// Unlike `parallel_gripper` (a bare kinematic jaw), this is a real mechanism:
/// a NEMA stepper turns a lead screw through a coupler; the screw drives a nut
/// on the moving carriage; two guide rails take the moment; the screw's far end
/// runs in a ball bearing.  The jaw is a prismatic joint **mimicking the motor
/// rotor**: command the motor joint and the jaw follows through the screw lead.
///
/// Layout (local frame):
/// - `mount` is on the rear plate at `Z = 0`, normal `+Z`.
/// - The jaws extend along `+Z`; the carriage slides along `X`.
/// - The motor sits on the `-X` wall; the screw runs along `X`.
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
  base_depth_mm~ : Double = 70.0,
  base_h_mm~ : Double = 64.0,
  base_w_mm~ : Double = 110.0,
  wall_mm~ : Double = 6.0,
  screw_diam_mm~ : Double = 6.0,
  rail_diam_mm~ : Double = 6.0,
  rail_y_mm~ : Double = 20.0,
  motor_frame_mm~ : Double = 28.2,
  motor_body_mm~ : Double = 32.0,
  motor_shaft_mm~ : Double = 20.0,
  motor_shaft_diam_mm~ : Double = 5.0,
  motor_effort_nm~ : Double = 0.1,
  motor_vel_rad_s~ : Double = 20.0,
  density~ : @urdf.Density = @urdf.Density::aluminum_6061(),
  color~ : @step_cad.Rgb = @step_cad.Rgb::grey(),
) -> @cad.Component {
  let half_open = opening_mm / 2.0
  let half_base = base_w_mm / 2.0
  let screw_z = base_depth_mm / 2.0
  let wall_inner = half_base - wall_mm
  let jaw_name = name + "_jaw"
  let motor_name = name + "_motor"
  let coupler_name = name + "_coupler"
  let screw_name = name + "_screw"
  let motor_joint = motor_name + "_shaft_joint"
  // The motor face sits on the -X wall; the shaft tip and coupler occupy the
  // first part of the frame, then the screw runs to the far bearing.
  let shaft_tip_x = -half_base + 1.5 + motor_shaft_mm
  let coupler_out_x = shaft_tip_x + 20.0
  let screw_len = wall_inner - coupler_out_x
  let bearing_x = wall_inner
  let rail_len = base_w_mm - 2.0 * wall_mm + 8.0
  let finger_z = base_depth_mm + finger_len_mm / 2.0 - screw_z
  let arm_x = half_open + finger_thick_mm / 2.0
  let carriage_z = 8.0
  let carriage_thick = 8.0
  let post_z0 = 8.0
  let motor_hole = @step_cad.Profile2D::circle(24.0).rev()
  let bearing_hole = @step_cad.Profile2D::circle(16.4).rev()
  let base = @cad.Component::new(name, description="Lead-screw gripper")
    .with_param("opening_mm", opening_mm.to_string())
    .with_param("travel_mm", travel_mm.to_string())
    .with_param("lead_mm", lead_mm.to_string())
    .with_param("finger_len_mm", finger_len_mm.to_string())
    .with_param("finger_width_mm", finger_width_mm.to_string())
    .with_param("screw_diam_mm", screw_diam_mm.to_string())
    .with_param("rail_diam_mm", rail_diam_mm.to_string())
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_rear_plate",
        base_w_mm,
        base_h_mm,
        wall_mm,
        z_mm=wall_mm / 2.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_bottom_plate",
        base_w_mm,
        wall_mm,
        base_depth_mm,
        y_mm=-base_h_mm / 2.0 + wall_mm / 2.0,
        z_mm=base_depth_mm / 2.0,
        density~,
        color~,
      ),
    )
    // Side walls carry the motor and the far bearing; each has a clearance
    // hole so the shaft/bearing passes through instead of into a solid wall.
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_motor_wall",
        @step_cad.Profile2D::centered_rect(base_depth_mm, base_h_mm),
        wall_mm,
        holes=[motor_hole],
        x_mm=-half_base + wall_mm / 2.0,
        z_mm=screw_z,
        ry_deg=90.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::extruded_profile_mm(
        name + "_bearing_wall",
        @step_cad.Profile2D::centered_rect(base_depth_mm, base_h_mm),
        wall_mm,
        holes=[bearing_hole],
        x_mm=half_base - wall_mm / 2.0,
        z_mm=screw_z,
        ry_deg=90.0,
        density~,
        color~,
      ),
    )
    // Fixed jaw: a front crossbar welded to the bottom plate and to the
    // finger.  It stays outside the moving carriage's x path.
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_fixed_jaw_crossbar",
        finger_thick_mm,
        base_h_mm - 8.0,
        wall_mm,
        x_mm=half_open + finger_thick_mm / 2.0,
        z_mm=base_depth_mm - wall_mm / 2.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_fixed_jaw",
        finger_thick_mm,
        finger_width_mm,
        finger_len_mm + 4.0,
        x_mm=half_open + finger_thick_mm / 2.0,
        z_mm=base_depth_mm + finger_len_mm / 2.0 - 2.0,
        density~,
        color~,
      ),
    )
    // Two guide rails, welded into the side walls.
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_rail_left",
        rail_diam_mm,
        rail_len,
        y_mm=rail_y_mm,
        z_mm=screw_z,
        ry_deg=90.0,
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
        ry_deg=90.0,
        density~,
        color~,
      ),
    )
    .add_mate_mm_deg("mount")
    .add_mate_mm_deg("jaw_slide", z=screw_z, axis=(1.0, 0.0, 0.0))
    .add_mate_mm_deg("motor_mount", x=-half_base, z=screw_z, ry_deg=90.0)
    .add_mate_mm_deg("bearing_seat", x=bearing_x, z=screw_z, ry_deg=90.0)
  let jaw = @cad.Component::new(jaw_name, description="Lead-screw jaw carriage")
    .with_param("opening_mm", opening_mm.to_string())
    .with_param("travel_mm", travel_mm.to_string())
    .add_body(
      @cad.BodyPart::tube_mm(
        jaw_name + "_nut",
        16.0,
        screw_diam_mm + 0.2,
        12.0,
        ry_deg=90.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        jaw_name + "_bushing_left",
        12.0,
        rail_diam_mm + 0.2,
        14.0,
        y_mm=rail_y_mm,
        ry_deg=90.0,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::tube_mm(
        jaw_name + "_bushing_right",
        12.0,
        rail_diam_mm + 0.2,
        14.0,
        y_mm=-rail_y_mm,
        ry_deg=90.0,
        density~,
        color~,
      ),
    )
    // L-shaped carriage: a plate above the rails (welded to the nut and
    // bushings), a vertical post, and the finger.  The post travels behind
    // the fixed jaw's x range, so the two jaws never cross.
    .add_body(
      @cad.BodyPart::box_mm(
        jaw_name + "_carriage",
        arm_x,
        finger_width_mm,
        carriage_thick,
        x_mm=-arm_x / 2.0,
        z_mm=carriage_z,
        density~,
        color~,
      ),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        jaw_name + "_post",
        finger_thick_mm,
        finger_width_mm,
        finger_z - post_z0,
        x_mm=-arm_x,
        z_mm=post_z0 + (finger_z - post_z0) / 2.0,
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
    .add_mate_mm_deg("mount")
  let motor = nema_stepper(
    name=motor_name,
    frame_size_mm=motor_frame_mm,
    body_length_mm=motor_body_mm,
    boss_diam_mm=22.0,
    boss_height_mm=1.5,
    shaft_diam_mm=motor_shaft_diam_mm,
    shaft_length_mm=motor_shaft_mm,
    max_effort_nm=motor_effort_nm,
    max_vel_rad_s=motor_vel_rad_s,
  )
  let coupler = shaft_coupler(
    name=coupler_name,
    outer_diam_mm=16.0,
    bore_in_mm=motor_shaft_diam_mm + 0.2,
    bore_out_mm=screw_diam_mm + 0.2,
    length_mm=20.0,
  )
  let screw = @cad.Component::new(screw_name, description="Lead screw")
    .with_param("lead_mm", lead_mm.to_string())
    .add_body(
      @cad.BodyPart::cylinder_mm(
        screw_name + "_body",
        screw_diam_mm,
        screw_len,
        density~,
        color~,
      ),
    )
    .add_mate_mm_deg("input", z=-screw_len / 2.0)
    .add_mate_mm_deg("output", z=screw_len / 2.0)
  let bearing = ball_bearing(
    name=name + "_screw_bearing",
    inner_diam_mm=screw_diam_mm + 0.2,
    outer_diam_mm=16.0,
    width_mm=5.0,
  )
  let multiplier = lead_mm / 1000.0 / (2.0 * @math.PI)
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
        effort=200.0,
        velocity=0.05,
        lower=Some(0.0),
        upper=Some(travel_mm / 1000.0),
      ),
      mimic=Some(@urdf.JointMimic::new(motor_joint, multiplier~)),
    ),
  )
}
