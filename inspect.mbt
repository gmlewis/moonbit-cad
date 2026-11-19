///|
/// Machine-readable summary of the assembled design, written to
/// `inspect.json` in the build package and printed by `--inspect-json`.
///
/// The schema is deliberately flat and deterministic: a customizer, CI job,
/// or agent can read masses, poses, torque margins, printable parts, and the
/// interference pass without parsing prose.

///|
fn inspect_bbox(
  bbox : (Double, Double, Double, Double, Double, Double)?,
) -> @json.Json {
  match bbox {
    Some((x0, x1, y0, y1, z0, z1)) =>
      @json.Json::array([
        @json.Json::number(x0),
        @json.Json::number(y0),
        @json.Json::number(z0),
        @json.Json::number(x1),
        @json.Json::number(y1),
        @json.Json::number(z1),
      ])
    None => @json.Json::null()
  }
}

///|
fn inspect_opt_number(value : Double?) -> @json.Json {
  match value {
    Some(number) => @json.Json::number(number)
    None => @json.Json::null()
  }
}

///|
fn inspect_vec3(value : (Double, Double, Double)) -> @json.Json {
  @json.Json::array([
    @json.Json::number(value.0),
    @json.Json::number(value.1),
    @json.Json::number(value.2),
  ])
}

///|
fn inspect_object(entries : Array[(String, @json.Json)]) -> @json.Json {
  let map : Map[String, @json.Json] = Map([])
  for entry in entries {
    map.set(entry.0, entry.1)
  }
  @json.Json::object(map)
}

///|
/// Whole-robot summary as a JSON document.
///
/// Includes the mass, CoM, inertia, world bounding box, links, joints,
/// static torque margins, printable parts (size, bed fit, estimated printed
/// mass), the OBB interference pass, BOM totals, and the generated view names.
pub fn Component::inspect_json(
  self : Component,
  bed~ : PrintBedSpec = PrintBedSpec::default(),
  joint_positions~ : Map[String, Double] = Map([]),
) -> String {
  let robot = self.to_robot()
  let analysis = analyze_robot(self, [("default", joint_positions)])
  let pose = analysis.poses[0]
  let design = self.to_design(joint_positions~)
  let (links, _, _) = self.compile_links()
  let bom = self.bom()

  let links_json : Array[@json.Json] = []
  for link in links {
    let mass = match link.urdf_link.inertial {
      Some(inertial) => inertial.mass
      None => 0.0
    }
    links_json.push(
      inspect_object([
        ("name", @json.Json::string(link.name)),
        ("mass_kg", @json.Json::number(mass)),
        ("bodies", @json.Json::number(link.bodies.length().to_double())),
      ]),
    )
  }

  let joints_json : Array[@json.Json] = []
  for joint in robot.joints {
    let (lower, upper, effort, velocity) = match joint.limit {
      Some(limit) => (limit.lower, limit.upper, limit.effort, limit.velocity)
      None => (None, None, 0.0, 0.0)
    }
    joints_json.push(
      inspect_object([
        ("name", @json.Json::string(joint.name)),
        ("type", @json.Json::string(joint.joint_type.to_urdf_str())),
        ("parent", @json.Json::string(joint.parent)),
        ("child", @json.Json::string(joint.child)),
        ("lower", inspect_opt_number(lower)),
        ("upper", inspect_opt_number(upper)),
        ("effort_nm", @json.Json::number(effort)),
        ("velocity_rad_s", @json.Json::number(velocity)),
      ]),
    )
  }

  let margins_json : Array[@json.Json] = []
  for joint in pose.joints {
    margins_json.push(
      inspect_object([
        ("joint", @json.Json::string(joint.joint)),
        ("tau_static_nm", @json.Json::number(joint.tau_static_nm)),
        ("tau_rated_nm", @json.Json::number(joint.tau_rated_nm)),
        ("safety_factor", @json.Json::number(joint.safety_factor)),
        ("ok", @json.Json::boolean(joint.ok)),
      ]),
    )
  }

  let part_map = printable_part_map(self.printable_parts())
  let parts_json : Array[@json.Json] = []
  for line in bom.lines {
    if line.process == "purchased" {
      continue
    }
    match part_map.get(line.part_number) {
      Some(part) => {
        let bbox = match part.bbox_mm() {
          Some((w, d, h)) =>
            @json.Json::array([
              @json.Json::number(w),
              @json.Json::number(d),
              @json.Json::number(h),
            ])
          None => @json.Json::null()
        }
        parts_json.push(
          inspect_object([
            ("part_number", @json.Json::string(line.part_number)),
            ("quantity", @json.Json::number(line.quantity.to_double())),
            ("process", @json.Json::string(line.process)),
            ("bbox_mm", bbox),
            ("fits_bed", @json.Json::boolean(part.fits_bed(bed))),
            ("est_mass_g", @json.Json::number(part.est_mass_g(line))),
          ]),
        )
      }
      None => ()
    }
  }

  let mut purchased = 0
  let mut cost = 0.0
  for line in bom.lines {
    if line.process == "purchased" {
      purchased = purchased + 1
      cost = cost + line.total_cost_usd
    }
  }

  let reports = self.collision_reports(joint_positions~)
  let mut collisions = 0
  let mut contacts = 0
  let mut fits = 0
  let mut indeterminate = 0
  for report in reports {
    match report.kind {
      @step_collision.CollisionKind::Collision => collisions = collisions + 1
      @step_collision.CollisionKind::Contact => contacts = contacts + 1
      @step_collision.CollisionKind::InterferenceFit => fits = fits + 1
      @step_collision.CollisionKind::Indeterminate =>
        indeterminate = indeterminate + 1
      @step_collision.CollisionKind::Clearance => ()
    }
  }
  let interference = inspect_object([
    ("collisions", @json.Json::number(collisions.to_double())),
    ("contacts", @json.Json::number(contacts.to_double())),
    ("fits", @json.Json::number(fits.to_double())),
    ("indeterminate", @json.Json::number(indeterminate.to_double())),
  ])

  inspect_object([
    ("name", @json.Json::string(self.display_name())),
    ("total_mass_kg", @json.Json::number(pose.total_mass_kg)),
    ("com_m", inspect_vec3(pose.com_m)),
    (
      "inertia_kgm2",
      inspect_object([
        ("ixx", @json.Json::number(pose.inertia.ixx)),
        ("iyy", @json.Json::number(pose.inertia.iyy)),
        ("izz", @json.Json::number(pose.inertia.izz)),
      ]),
    ),
    ("world_bbox_mm", inspect_bbox(design_bbox(design))),
    ("links", @json.Json::array(links_json)),
    ("joints", @json.Json::array(joints_json)),
    ("torque_margins", @json.Json::array(margins_json)),
    ("printable_parts", @json.Json::array(parts_json)),
    ("interference_summary", interference),
    (
      "bom",
      inspect_object([
        ("lines", @json.Json::number(bom.lines.length().to_double())),
        ("purchased", @json.Json::number(purchased.to_double())),
        ("estimated_cost_usd", @json.Json::number(cost)),
      ]),
    ),
    (
      "views",
      @json.Json::array([
        @json.Json::string("iso"),
        @json.Json::string("front"),
        @json.Json::string("left"),
        @json.Json::string("top"),
        @json.Json::string("exploded"),
      ]),
    ),
  ]).stringify()
}
