///|
/// 03_hip_joint — reusable 2-stage (28.44:1) A12 hip actuator library for
/// Galileo X.
///
/// Preserves the high-torque two-stage 4-elbow print-in-place planetary gearbox
/// (m = 2.0, 12/20/52 -> 5.33:1 per stage, 28.44:1 total) with an A12 8318
/// 100KV motor, twin spaced output bearings, a 40 mm output flange hub, and a
/// protective `MG-MOTEUS-SHROUD` rear cover.

///|
/// Default hip-joint actuator configuration for `03_hip_joint`.
pub fn default_config() -> @common.GearboxConfig {
  @common.GearboxConfig::new(
    prog="03_hip_joint",
    description="High-torque 2-stage (28.44:1) A12 planetary hip-joint actuator with twin output bearings and moteus C1 shroud.",
    gearbox_name="hip_gearbox",
    links_path="examples/03_hip_joint/supplier-links.txt",
    num_stages=2,
    motor_source="a12",
    no_tire=true,
    dual_output_bearing=true,
    tire_mount_flush=false,
    moteus_shroud=true,
  )
}

///|
/// Builds the assembled `03_hip_joint` component for use in full-robot
/// assemblies.
pub async fn build_hip_joint(
  config~ : @common.GearboxConfig = default_config(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> (@cad.Component, Array[@components.MotorizedStageSpec], String, String) {
  @common.build_gearbox_component(config, detail~)
}

///|
/// Runs the `03_hip_joint` CLI.
pub async fn run_cli() -> Unit {
  @common.run_gearbox_cli(default_config())
}
