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
) -> Component {
  let half_open = opening_mm / 2.0
  let base_w = opening_mm + 2.0 * finger_thick_mm
  let jaw_name = name + "_jaw"
  let base = Component::new(name, description="Parallel-jaw gripper")
    .with_param("opening_mm", opening_mm.to_string())
    .with_param("travel_mm", travel_mm.to_string())
    .with_param("finger_len_mm", finger_len_mm.to_string())
    .with_param("finger_width_mm", finger_width_mm.to_string())
    .with_param("finger_thick_mm", finger_thick_mm.to_string())
    .with_param("base_thick_mm", base_thick_mm.to_string())
    .with_param("finger_overlap_mm", finger_overlap_mm.to_string())
    .add_body(
      BodyPart::box_mm(
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
      BodyPart::box_mm(
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
  let jaw = Component::new(jaw_name, description="Moving gripper jaw")
    .add_body(
      BodyPart::box_mm(
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
    spec=JointSpec::prismatic(
      @urdf.JointLimit::new(
        effort=effort_n,
        velocity=velocity_mps,
        lower=Some(0.0),
        upper=Some(travel_mm / 1000.0),
      ),
    ),
  )
}
