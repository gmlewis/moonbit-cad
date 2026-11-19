///|
/// Sensors and electronics envelopes: limit switches, encoders, IMUs, cameras,
/// force sensors, and PCB outlines.

///|
/// Builds a micro limit switch: a small body on a `mount` face at `Z = 0`.
///
/// The body extends along `+Z`, so attaching the `mount` mate to a shelf makes
/// the switch sit on that shelf.  Ports: `signal`, `power`, `ground`.
pub fn limit_switch(
  name~ : String = "limit_switch",
  body_len_mm~ : Double = 10.0,
  body_w_mm~ : Double = 10.0,
  body_h_mm~ : Double = 6.0,
  voltage_v~ : Double = 5.0,
  current_ma~ : Double = 10.0,
  color~ : @step_cad.Rgb = @step_cad.Rgb::red(),
) -> @cad.Component {
  let unit_cost_usd = 2.5
  let part = purchased_part(
    "LIMIT-SW-MICRO", "Micro limit switch", "mixed", unit_cost_usd,
  )
  let sensor = @cad.SensorSpec::new(
    @cad.SensorKind::LimitSwitch,
    model="microswitch",
    interface="GPIO",
    voltage_v~,
    current_ma~,
    range="5 mm",
    resolution="binary",
  )
  let screw = purchased_part(
    "SHCS-M2x6", "Socket head cap screw M2 x 6", "steel", 0.2,
  )
  @cad.Component::new(name, description="Micro limit switch")
  .with_param("voltage_v", voltage_v.to_string())
  .with_param("current_ma", current_ma.to_string())
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_body",
      body_len_mm,
      body_w_mm,
      body_h_mm,
      z_mm=body_h_mm / 2.0,
      density=@urdf.Density::pla(),
      color~,
    ),
  )
  .add_mate_mm_deg("mount")
  .with_part(part)
  .with_sensor(sensor)
  .add_port(@cad.Port::new("signal", @cad.PortKind::Signal, spec="NO to GND"))
  .add_port(
    @cad.Port::new(
      "power",
      @cad.PortKind::Power,
      spec=voltage_v.to_string() + " V, " + current_ma.to_string() + " mA",
    ),
  )
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  .add_fastener(
    @cad.Fastener::new(
      "mount_screws",
      @cad.FastenerKind::Screw,
      thread="M2",
      length_mm=6.0,
      engagement_mm=3.0,
      quantity=2,
      torque_nm=0.3,
      references=[name + "_body"],
      part=Some(screw),
    ),
  )
}

///|
/// Builds a magnetic encoder: a code disc under a small readout board.
pub fn magnetic_encoder(
  name~ : String = "magnetic_encoder",
  disc_diam_mm~ : Double = 22.0,
  board_len_mm~ : Double = 20.0,
  voltage_v~ : Double = 3.3,
  current_ma~ : Double = 15.0,
) -> @cad.Component {
  let unit_cost_usd = 8.0
  let part = purchased_part(
    "ENC-MAG-14BIT", "Magnetic encoder 14-bit", "mixed", unit_cost_usd,
  )
  let sensor = @cad.SensorSpec::new(
    @cad.SensorKind::Encoder,
    model="magnetic 14-bit",
    interface="SPI",
    voltage_v~,
    current_ma~,
    range="360 deg",
    resolution="0.022 deg",
  )
  @cad.Component::new(name, description="Magnetic encoder")
  .with_param("disc_diam_mm", disc_diam_mm.to_string())
  .with_param("voltage_v", voltage_v.to_string())
  .with_param("current_ma", current_ma.to_string())
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_disc",
      disc_diam_mm,
      2.0,
      z_mm=-1.0,
      density=@urdf.Density::aluminum_6061(),
      color=@step_cad.Rgb::grey(),
    ),
  )
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_board",
      board_len_mm,
      board_len_mm,
      1.6,
      z_mm=4.0,
      density=@urdf.Density::pla(),
      color=@step_cad.Rgb::green(),
    ),
  )
  .add_mate_mm_deg("shaft", z=-2.0)
  .add_mate_mm_deg("mount", z=4.8)
  .with_part(part)
  .with_sensor(sensor)
  .add_port(
    @cad.Port::new(
      "power",
      @cad.PortKind::Power,
      spec=voltage_v.to_string() + " V, " + current_ma.to_string() + " mA",
    ),
  )
  .add_port(@cad.Port::new("spi", @cad.PortKind::Bus, spec="SPI, 10 MHz"))
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
}

///|
/// Builds a moteus-style on-axis absolute position sensor: an AS5047P (or
/// equivalent 14-bit) magnetic encoder on a small PCB, with the chip on the
/// face that looks at a diametrically magnetized magnet.
///
/// The board bottom is at `z = 0`, the chip sits `chip_height_mm` below it, and
/// the `sensor_face` mate is at the chip face. Attach `mount` to a fixed cover
/// and place the magnet on the rotating shaft with a 0.5–1.5 mm air gap.
pub fn moteus_position_sensor(
  name~ : String = "position_sensor",
  board_len_mm~ : Double = 28.0,
  board_w_mm~ : Double = 22.0,
  thickness_mm~ : Double = 1.6,
  mounting_hole_diam_mm~ : Double = 2.7,
  hole_inset_mm~ : Double = 3.5,
  chip_size_mm~ : Double = 6.0,
  chip_height_mm~ : Double = 1.0,
  voltage_v~ : Double = 3.3,
  current_ma~ : Double = 15.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let _ = detail
  let half_l = board_len_mm / 2.0
  let half_w = board_w_mm / 2.0
  let hx = half_l - hole_inset_mm
  let hy = half_w - hole_inset_mm
  let board_outer = rect_arc_segments(board_len_mm, board_w_mm)
  let board_holes : Array[Array[@step_cad.ProfileSegment]] = [
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      hx,
      hy,
    ),
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      -hx,
      hy,
    ),
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      -hx,
      -hy,
    ),
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      hx,
      -hy,
    ),
  ]
  let part = purchased_part(
    "ENC-AS5047P", "AS5047P 14-bit on-axis magnetic encoder board", "FR-4 / mixed",
    12.0,
  )
  let sensor = @cad.SensorSpec::new(
    @cad.SensorKind::Encoder,
    model="AS5047P",
    interface="SPI/ABZ",
    voltage_v~,
    current_ma~,
    range="360 deg",
    resolution="14-bit (0.022 deg)",
  )
  let screw = purchased_part(
    "ISO4762-M2.5x6", "ISO 4762 socket head cap screw M2.5 x 6 mm", "steel", 0.25,
  )
  let comp = @cad.Component::new(
      name,
      description="On-axis absolute magnetic position sensor",
    )
    .with_param("board_len_mm", board_len_mm.to_string())
    .with_param("board_w_mm", board_w_mm.to_string())
    .with_param("chip", "AS5047P")
    .add_body(
      arc_profile_body(
        name + "_board",
        board_outer,
        thickness_mm,
        board_holes,
        @urdf.Density::pla(),
        @step_cad.Rgb::green(),
        0.0,
      ).with_part(part),
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_chip",
        chip_size_mm,
        chip_size_mm,
        chip_height_mm,
        z_mm=-chip_height_mm / 2.0,
        density=@urdf.Density::kg_per_m3(1850.0),
        color=@step_cad.Rgb::black(),
      ).with_part(part),
    )
    .add_mate_mm_deg("mount", axis=(0.0, 0.0, -1.0))
    .add_mate_mm_deg("top", z=thickness_mm)
    .add_mate_mm_deg("sensor_face", z=-chip_height_mm, axis=(0.0, 0.0, -1.0))
    .with_part(part)
    .with_sensor(sensor)
    .add_port(
      @cad.Port::new(
        "power",
        @cad.PortKind::Power,
        spec=voltage_v.to_string() + " V, " + current_ma.to_string() + " mA",
      ),
    )
    .add_port(@cad.Port::new("spi", @cad.PortKind::Bus, spec="SPI, 10 MHz"))
    .add_port(@cad.Port::new("abz", @cad.PortKind::Signal, spec="A/B/Z 5 V"))
    .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
    .add_fastener(
      @cad.Fastener::new(
        "sensor_screws",
        @cad.FastenerKind::Screw,
        thread="M2.5",
        length_mm=6.0,
        engagement_mm=3.0,
        quantity=4,
        torque_nm=0.4,
        references=[name + "_board"],
        part=Some(screw),
      ),
    )
  let holes : Array[(Double, Double)] = [
    (-hx, -hy),
    (hx, -hy),
    (hx, hy),
    (-hx, hy),
  ]
  let mut out = comp
  for i in 0..<holes.length() {
    out = out.add_mate_mm_deg(
      "bolt_" + i.to_string(),
      x=holes[i].0,
      y=holes[i].1,
    )
  }
  out
}

///|
/// The mjbots moteus C1 r1.2 controller, imported from the vendored vendor
/// STEP (`components/vendor/20240305-moteus-c1-r1_2.step`).
///
/// The board's on-axis AS5047P chip sits on the `mount` face; mount the board
/// with the chip facing the magnet it reads, 1-3 mm away. The caller passes
/// the file's text so this package stays file-system free. The chip face is
/// about 1.2 mm above the component origin (local +Z after the import
/// rotation), so a board attached at `z` reads a magnet whose face sits at
/// `z + 1.2 mm - gap`.
pub fn moteus_c1_board(
  step_text : String,
  name~ : String = "moteus_c1",
  source~ : String = "components/vendor/20240305-moteus-c1-r1_2.step",
) -> @cad.Component {
  let part = purchased_part(
    "MOTEUS-C1-R1.2",
    "moteus C1 r1.2 controller (mjbots); on-axis AS5047P encoder and BLDC FOC driver",
    "FR-4 / mixed",
    69.0,
    supplier_url="https://mjbots.com/products/moteus-c1",
  )
  @cad.Component::new(
    name,
    description="moteus C1 r1.2 controller board; on-axis AS5047P reads the rotor magnet for input (sun-gear) speed and FOC commutation",
  )
  .add_body(
    @cad.BodyPart::imported_step(
      name + "_board",
      step_text,
      source~,
      density=@urdf.Density::g_per_cm3(1.85),
      color=@step_cad.Rgb::green(),
      part=Some(part),
      rx_deg=-90.0,
    ),
  )
  .with_part(part)
  .with_param("chip", "AS5047P")
  .with_param("air_gap_target_mm", "2.0")
  .with_sensor(
    @cad.SensorSpec::new(
      @cad.SensorKind::Encoder,
      model="AS5047P",
      interface="SPI/ABZ",
      voltage_v=3.3,
      current_ma=15.0,
      range="360 deg",
      resolution="14-bit (0.022 deg)",
    ),
  )
  .add_port(
    @cad.Port::new(
      "power",
      @cad.PortKind::Power,
      spec="10-51 V (48 V bus), 20 A peak",
    ),
  )
  .add_port(@cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B"))
  .add_port(@cad.Port::new("motor", @cad.PortKind::Power, spec="3-phase"))
  .add_port(
    @cad.Port::new(
      "encoder",
      @cad.PortKind::Sensor,
      spec="On-board AS5047P, SPI/ABZ",
    ),
  )
  .add_mate_mm_deg("mount")
}

///|
/// Builds a diametrically magnetized encoder magnet.
///
/// The magnet's top face is at `z = 0` and it extends `thickness_mm` below, so
/// attaching `top` to an output-shaft end puts the magnet in the shaft's end
/// pocket. The `bottom`/`shaft` mates are on the far face.
pub fn encoder_magnet(
  name~ : String = "encoder_magnet",
  diameter_mm~ : Double = 6.0,
  thickness_mm~ : Double = 2.5,
  color~ : @step_cad.Rgb = @step_cad.Rgb::purple(),
) -> @cad.Component {
  let part = purchased_part(
    "MAG-\{diameter_mm}x\{thickness_mm}-DIA",
    "Diametrically magnetized NdFeB encoder magnet \{diameter_mm} x \{thickness_mm} mm",
    "NdFeB N42",
    1.20,
  )
  @cad.Component::new(
    name,
    description="Diametrically magnetized encoder magnet",
  )
  .with_param("diameter_mm", diameter_mm.to_string())
  .with_param("magnetization", "diametric")
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_magnet",
      diameter_mm,
      thickness_mm,
      z_mm=-thickness_mm / 2.0,
      density=@urdf.Density::kg_per_m3(7500.0),
      color~,
    ).with_part(part),
  )
  .add_mate_mm_deg("top")
  .add_mate_mm_deg("bottom", z=-thickness_mm)
  .add_mate_mm_deg("shaft", z=-thickness_mm)
  .with_part(part)
}

///|
/// Builds a six-axis IMU board.
pub fn imu_module(
  name~ : String = "imu_module",
  board_mm~ : Double = 16.0,
  voltage_v~ : Double = 3.3,
  current_ma~ : Double = 5.0,
) -> @cad.Component {
  let unit_cost_usd = 6.0
  let part = purchased_part("IMU-6AXIS", "6-axis IMU", "mixed", unit_cost_usd)
  let sensor = @cad.SensorSpec::new(
    @cad.SensorKind::Imu,
    model="6-axis IMU",
    interface="I2C",
    voltage_v~,
    current_ma~,
    range="+/-16 g, +/-2000 deg/s",
    resolution="16-bit",
  )
  @cad.Component::new(name, description="Six-axis IMU")
  .with_param("voltage_v", voltage_v.to_string())
  .with_param("current_ma", current_ma.to_string())
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_board",
      board_mm,
      board_mm,
      1.6,
      z_mm=0.8,
      density=@urdf.Density::pla(),
      color=@step_cad.Rgb::green(),
    ),
  )
  .add_mate_mm_deg("mount")
  .with_part(part)
  .with_sensor(sensor)
  .add_port(
    @cad.Port::new(
      "power",
      @cad.PortKind::Power,
      spec=voltage_v.to_string() + " V, " + current_ma.to_string() + " mA",
    ),
  )
  .add_port(@cad.Port::new("i2c", @cad.PortKind::Bus, spec="I2C, 400 kHz"))
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
}

///|
/// Builds a camera module: a housing with a lens and a CSI/USB interface.
pub fn camera_module(
  name~ : String = "camera_module",
  body_mm~ : Double = 30.0,
  body_h_mm~ : Double = 12.0,
  lens_diam_mm~ : Double = 12.0,
  voltage_v~ : Double = 5.0,
  current_ma~ : Double = 250.0,
) -> @cad.Component {
  let unit_cost_usd = 35.0
  let part = purchased_part(
    "CAM-1080P", "1080p camera module", "mixed", unit_cost_usd,
  )
  let sensor = @cad.SensorSpec::new(
    @cad.SensorKind::Camera,
    model="1080p camera",
    interface="MIPI CSI-2",
    voltage_v~,
    current_ma~,
    range="1920 x 1080",
    resolution="60 fps",
  )
  @cad.Component::new(name, description="Camera module")
  .with_param("voltage_v", voltage_v.to_string())
  .with_param("current_ma", current_ma.to_string())
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_body",
      body_mm,
      body_mm,
      body_h_mm,
      z_mm=body_h_mm / 2.0,
      density=@urdf.Density::pla(),
      color=@step_cad.Rgb::black(),
    ),
  )
  .add_body(
    @cad.BodyPart::cylinder_mm(
      name + "_lens",
      lens_diam_mm,
      6.0,
      z_mm=body_h_mm + 3.0,
      density=@urdf.Density::pla(),
      color=@step_cad.Rgb::blue(),
    ),
  )
  .add_mate_mm_deg("mount")
  .add_mate_mm_deg("lens_axis", z=body_h_mm + 6.0)
  .with_part(part)
  .with_sensor(sensor)
  .add_port(
    @cad.Port::new(
      "power",
      @cad.PortKind::Power,
      spec=voltage_v.to_string() + " V, " + current_ma.to_string() + " mA",
    ),
  )
  .add_port(
    @cad.Port::new("csi", @cad.PortKind::Bus, spec="MIPI CSI-2, 2 lanes"),
  )
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
}

///|
/// Builds a force sensor (load cell or FSR) with an analog output.
pub fn force_sensor(
  name~ : String = "force_sensor",
  body_len_mm~ : Double = 20.0,
  body_w_mm~ : Double = 10.0,
  body_h_mm~ : Double = 5.0,
  voltage_v~ : Double = 5.0,
  current_ma~ : Double = 5.0,
) -> @cad.Component {
  let unit_cost_usd = 9.0
  let part = purchased_part(
    "FSR-50N", "Force sensor 0-50 N", "mixed", unit_cost_usd,
  )
  let sensor = @cad.SensorSpec::new(
    @cad.SensorKind::Force,
    model="FSR 0-50 N",
    interface="analog",
    voltage_v~,
    current_ma~,
    range="0-50 N",
    resolution="0.1 N",
  )
  @cad.Component::new(name, description="Force sensor")
  .with_param("voltage_v", voltage_v.to_string())
  .with_param("current_ma", current_ma.to_string())
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_body",
      body_len_mm,
      body_w_mm,
      body_h_mm,
      z_mm=body_h_mm / 2.0,
      density=@urdf.Density::pla(),
      color=@step_cad.Rgb::orange(),
    ),
  )
  .add_mate_mm_deg("mount")
  .add_mate_mm_deg("sense_face", z=body_h_mm)
  .with_part(part)
  .with_sensor(sensor)
  .add_port(
    @cad.Port::new(
      "power",
      @cad.PortKind::Power,
      spec=voltage_v.to_string() + " V, " + current_ma.to_string() + " mA",
    ),
  )
  .add_port(
    @cad.Port::new("signal", @cad.PortKind::Signal, spec="analog 0-5 V"),
  )
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
}

///|
/// Builds a reusable assistive-vehicle joystick pod: a printable housing, a
/// two-axis Hall/potentiometer stick, an E-stop button, and a power button,
/// with typed ports for the two signal channels and the E-stop loop.
///
/// The pod's bottom face is at `z = 0`, so attaching `mount` to an armrest or
/// console puts the housing on that surface. It has no commandable joints; the
/// stick is an input device, not an actuator.
pub fn joystick_pod(
  name~ : String = "joystick_pod",
  housing_len_mm~ : Double = 90.0,
  housing_w_mm~ : Double = 70.0,
  housing_h_mm~ : Double = 40.0,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let _ = detail
  let housing_part = fabricated_part(
    "JOYSTICK-HOUSING-\{housing_len_mm}x\{housing_w_mm}",
    "Joystick pod housing",
    "PETG",
    "3D print",
    12.0,
  )
  let electronics_part = purchased_part(
    "JOYSTICK-2AXIS", "Two-axis Hall-effect joystick, E-stop, and power switch",
    "mixed", 18.0,
  )
  let insert = heat_set_insert(
    name=name + "_insert",
    outer_diam_mm=4.5,
    inner_diam_mm=3.0,
    length_mm=4.0,
  )
  let screw = purchased_part(
    "ISO4762-M3x10", "ISO 4762 socket head cap screw M3 x 10 mm", "steel", 0.35,
  )
  let top = housing_h_mm
  let stick_x = housing_len_mm * 0.10
  let axis_z = top + 8.0
  // The Hall-effect gimbal, stick, knob, E-stop, and power switch are one
  // purchased assembly, so they roll up as a single BOM line.
  let electronics = @cad.Component::new(
      name + "_electronics",
      description="Joystick electronics",
    )
    .add_body(
      @cad.BodyPart::box_mm(
        name + "_gimbal",
        34.0,
        34.0,
        14.0,
        x_mm=stick_x,
        z_mm=top + 7.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::grey(),
      ).with_part(electronics_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_stick",
        8.0,
        32.0,
        x_mm=stick_x,
        z_mm=top + 28.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::grey(),
      ).with_part(electronics_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_knob",
        24.0,
        12.0,
        x_mm=stick_x,
        z_mm=top + 48.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::black(),
      ).with_part(electronics_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_estop",
        22.0,
        10.0,
        x_mm=-stick_x,
        y_mm=housing_w_mm * 0.24,
        z_mm=top + 5.0,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::red(),
      ).with_part(electronics_part),
    )
    .add_body(
      @cad.BodyPart::cylinder_mm(
        name + "_power_button",
        14.0,
        5.0,
        x_mm=-stick_x,
        y_mm=-housing_w_mm * 0.24,
        z_mm=top + 2.5,
        density=@urdf.Density::pla(),
        color=@step_cad.Rgb::green(),
      ).with_part(electronics_part),
    )
    .with_part(electronics_part)
  @cad.Component::new(name, description="Assistive joystick pod")
  .with_param("housing_len_mm", housing_len_mm.to_string())
  .with_param("housing_w_mm", housing_w_mm.to_string())
  .with_param("housing_h_mm", housing_h_mm.to_string())
  .with_param("sticks", "2-axis Hall")
  .add_body(
    @cad.BodyPart::box_mm(
      name + "_housing",
      housing_len_mm,
      housing_w_mm,
      housing_h_mm,
      z_mm=housing_h_mm / 2.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::black(),
    ).with_part(housing_part),
  )
  .attach(
    "electronics_merge",
    parent_mate="mount",
    electronics,
    child_mate="origin",
    spec=@cad.JointSpec::merge_rigid(),
  )
  .add_mate_mm_deg("mount")
  .add_mate_mm_deg("stick", x=stick_x, z=axis_z)
  .add_mate_mm_deg("estop", x=-stick_x, y=housing_w_mm * 0.24, z=top)
  .add_mate_mm_deg("power_button", x=-stick_x, y=-housing_w_mm * 0.24, z=top)
  .add_port(
    @cad.Port::new(
      "signal",
      @cad.PortKind::Signal,
      spec="2 x analog / Hall, 0-3.3 V",
    ),
  )
  .add_port(@cad.Port::new("estop", @cad.PortKind::Signal, spec="NC to ground"))
  .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="5 V, 20 mA"))
  .add_port(@cad.Port::new("ground", @cad.PortKind::Ground, spec="0 V"))
  .attach(
    "stick_insert_merge",
    parent_mate="mount",
    insert,
    child_mate="seat",
    spec=@cad.JointSpec::merge_rigid(),
  )
  .add_fastener(
    @cad.Fastener::new(
      "pod_mount_screws",
      @cad.FastenerKind::Screw,
      thread="M3",
      length_mm=10.0,
      engagement_mm=4.0,
      quantity=2,
      torque_nm=0.8,
      references=[name + "_housing"],
      part=Some(screw),
    ),
  )
}

///|
/// Builds a printable bracket for an IMU, camera, or other sensor board.
///
/// The bracket is a flat plate with two mounting holes and a raised sensor
/// face. `process="3D print"` makes `printable_parts()` export it.
pub fn sensor_mount_bracket(
  name~ : String = "sensor_mount",
  width_mm~ : Double = 30.0,
  height_mm~ : Double = 20.0,
  thickness_mm~ : Double = 4.0,
  hole_diam_mm~ : Double = 2.7,
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> @cad.Component {
  let segments = @step_common.DetailPolicy::for_level(detail).circle_segments
  let part = fabricated_part(
    "SENSOR-MOUNT-\{width_mm}x\{height_mm}",
    "Sensor mount bracket",
    "PETG",
    "3D print",
    1.5,
  )
  let hole_offset = width_mm * 0.3
  @cad.Component::new(name, description="Sensor mount bracket")
  .with_param("width_mm", width_mm.to_string())
  .with_param("height_mm", height_mm.to_string())
  .with_param("thickness_mm", thickness_mm.to_string())
  .add_body(
    @cad.BodyPart::extruded_profile_mm(
      name + "_plate",
      @step_cad.Profile2D::centered_rect(width_mm, height_mm),
      thickness_mm,
      holes=[
        @step_cad.translate_pts(
          @step_cad.Profile2D::circle(hole_diam_mm, segments~),
          hx_offset(hole_offset),
          0.0,
        ),
        @step_cad.translate_pts(
          @step_cad.Profile2D::circle(hole_diam_mm, segments~),
          -hole_offset,
          0.0,
        ),
      ],
      z_mm=thickness_mm / 2.0,
      density=@urdf.Density::petg(),
      color=@step_cad.Rgb::grey(),
    ),
  )
  .add_mate_mm_deg("mount")
  .add_mate_mm_deg("sensor_face", z=thickness_mm)
  .with_part(part)
}

///|
fn hx_offset(value : Double) -> Double {
  value
}

///|
/// Builds a PCB envelope: a thin board with four mounting holes.
///
/// The board's back face is at `Z = 0` and it extends along `+Z`, so attaching
/// `mount` to a wall face puts the board flat against that wall.  The four
/// `bolt_*` mates sit at the mounting holes.
pub fn pcb_board(
  name~ : String = "controller_pcb",
  length_mm~ : Double = 40.0,
  width_mm~ : Double = 30.0,
  thickness_mm~ : Double = 1.6,
  mounting_hole_diam_mm~ : Double = 2.7,
  hole_inset_mm~ : Double = 3.5,
  max_component_height_mm~ : Double = 12.0,
  connectors~ : Array[String] = [],
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
  include_standoffs~ : Bool = false,
) -> @cad.Component {
  let half_l = length_mm / 2.0
  let half_w = width_mm / 2.0
  let hx = half_l - hole_inset_mm
  let hy = half_w - hole_inset_mm
  let board_outer = rect_arc_segments(length_mm, width_mm)
  let board_holes : Array[Array[@step_cad.ProfileSegment]] = [
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      hx,
      hy,
    ),
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      -hx,
      hy,
    ),
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      -hx,
      -hy,
    ),
    arc_segments_at(
      @step_gears.arc_circle_segments(mounting_hole_diam_mm),
      hx,
      -hy,
    ),
  ]
  let unit_cost_usd = 18.0
  let part = fabricated_part(
    "PCB-" + length_mm.to_string() + "x" + width_mm.to_string(),
    "Controller PCB " + length_mm.to_string() + " x " + width_mm.to_string(),
    "FR-4",
    "assembly",
    unit_cost_usd,
  )
  let spec = @cad.PcbSpec::new(
    model="CTRL-" + length_mm.to_string() + "x" + width_mm.to_string(),
    length_mm~,
    width_mm~,
    thickness_mm~,
    mounting_holes=4,
    mounting_hole_diam_mm~,
    max_component_height_mm~,
    connectors~,
  )
  let screw = purchased_part(
    "ISO4762-M2.5x6", "ISO 4762 socket head cap screw M2.5 x 6 mm", "steel", 0.25,
  )
  let comp = @cad.Component::new(name, description="Controller PCB")
    .with_param("length_mm", length_mm.to_string())
    .with_param("width_mm", width_mm.to_string())
    .with_param("thickness_mm", thickness_mm.to_string())
    .add_body(
      arc_profile_body(
        name + "_board",
        board_outer,
        thickness_mm,
        board_holes,
        @urdf.Density::pla(),
        @step_cad.Rgb::green(),
        0.0,
      ),
    )
    .add_mate_mm_deg("mount")
    .with_part(part)
    .with_pcb(spec)
    .add_port(@cad.Port::new("power", @cad.PortKind::Power, spec="24 V, 3 A"))
    .add_port(
      @cad.Port::new("motor", @cad.PortKind::Signal, spec="STEP/DIR, TTL"),
    )
    .add_port(@cad.Port::new("limit_home", @cad.PortKind::Sensor, spec="GPIO"))
    .add_port(
      @cad.Port::new("limit_closed", @cad.PortKind::Sensor, spec="GPIO"),
    )
    .add_port(
      @cad.Port::new("can", @cad.PortKind::Bus, spec="CAN 2.0B, 1 Mbps"),
    )
    .add_fastener(
      @cad.Fastener::new(
        "pcb_screws",
        @cad.FastenerKind::Screw,
        thread="M2.5",
        length_mm=6.0,
        engagement_mm=3.0,
        quantity=4,
        torque_nm=0.4,
        references=[name + "_board"],
        part=Some(screw),
      ),
    )
  let holes : Array[(Double, Double)] = [
    (-hx, -hy),
    (hx, -hy),
    (hx, hy),
    (-hx, hy),
  ]
  let mut with_mates = comp
  for i in 0..<holes.length() {
    with_mates = with_mates.add_mate_mm_deg(
      "bolt_" + i.to_string(),
      x=holes[i].0,
      y=holes[i].1,
    )
  }
  if include_standoffs || detail_is_rich(detail) {
    for i in 0..<holes.length() {
      let standoff = hex_standoff(
        name=name + "_standoff_" + i.to_string(),
        length_mm=6.0,
        across_flats_mm=5.0,
        bore_diam_mm=mounting_hole_diam_mm,
        detail~,
      )
      with_mates = with_mates.attach(
        "standoff_" + i.to_string(),
        parent_mate="bolt_" + i.to_string(),
        standoff,
        child_mate="bottom",
        spec=@cad.JointSpec::merge_rigid(),
      )
    }
  }
  with_mates
}
