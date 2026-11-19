///|
/// 01-motorized-wheel — reusable Galileo X wheeled-foot drive library.
///
/// Defaults to a single 5.33:1 4-elbow print-in-place planetary stage driving
/// the 7-inch budrash tire through a dual-bearing output cap, a flush bolted
/// tire mount (`TIRE-MOUNT-86.3` with radial `SET-M4x10` hub locks), and a
/// protective `MG-MOTEUS-SHROUD` over the rear `moteus C1` controller.

///|
/// Default wheel-drive configuration for `01-motorized-wheel`.
pub fn default_config() -> @common.GearboxConfig {
  @common.GearboxConfig::new(
    prog="01-motorized-wheel",
    description="Compact 1-stage (5.33:1) A12 motorized wheel drive with dual spaced output bearings, flush tire mount, and moteus C1 shroud.",
    gearbox_name="wheel_gearbox",
    links_path="examples/01-motorized-wheel/supplier-links.txt",
    num_stages=1,
    motor_source="a12",
    no_tire=false,
    dual_output_bearing=true,
    tire_mount_flush=true,
    moteus_shroud=true,
  )
}

///|
/// Builds the assembled `01-motorized-wheel` component (callable directly from
/// top-level robot assemblies such as Galileo X).
pub async fn build_wheel(
  config~ : @common.GearboxConfig = default_config(),
  detail~ : @step_common.DetailLevel = @step_common.DetailLevel::Simplified,
) -> (@cad.Component, Array[@components.MotorizedStageSpec], String, String) {
  @common.build_gearbox_component(config, detail~)
}

///|
/// Runs the `01-motorized-wheel` CLI.
pub async fn run_cli() -> Unit {
  @common.run_gearbox_cli(default_config())
}
