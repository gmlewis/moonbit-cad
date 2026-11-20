///|
fn wbr_like_params() -> @mechanisms.FourBarParams {
  @mechanisms.FourBarParams::new(
    ax=-88.0,
    az=-18.0,
    cx=12.0,
    cz=-70.0,
    crank_len_mm=128.0,
    coupler_len_mm=76.0,
    guide_len_mm=165.0,
    output_len_mm=225.0,
    output_beta_deg=-4.0,
  )
}

///|
fn grashof_params() -> @mechanisms.FourBarParams {
  @mechanisms.FourBarParams::new(
    ax=0.0,
    az=0.0,
    cx=50.0,
    cz=0.0,
    crank_len_mm=10.0,
    coupler_len_mm=45.5,
    guide_len_mm=15.0,
    output_len_mm=30.0,
  )
}

///|
fn dead_point_params() -> @mechanisms.FourBarParams {
  @mechanisms.FourBarParams::new(
    ax=0.0,
    az=0.0,
    cx=50.0,
    cz=0.0,
    crank_len_mm=100.0,
    coupler_len_mm=1.0,
    guide_len_mm=1.0,
    output_len_mm=30.0,
  )
}

///|
test "four bar closes across the full stroke" {
  let params = wbr_like_params()
  let sweep = @mechanisms.sweep_four_bar(
    params,
    start_deg=10.0,
    end_deg=62.0,
    steps=52,
  )
  assert_eq(sweep.errors.length(), 0)
  assert_true(sweep.solutions.length() == 53)
  for solution in sweep.solutions {
    assert_true(@mechanisms.loop_closure_residual(params, solution) < 1.0e-9)
    assert_true(solution.transmission_deg > 0.0)
    assert_true(solution.transmission_deg < 180.0)
  }
}

///|
test "grashof check distinguishes crank and rocker linkages" {
  assert_true(grashof_params().grashof())
  let non_grashof = @mechanisms.FourBarParams::new(
    ax=0.0,
    az=0.0,
    cx=50.0,
    cz=0.0,
    crank_len_mm=10.0,
    coupler_len_mm=5.0,
    guide_len_mm=5.0,
    output_len_mm=30.0,
  )
  assert_false(non_grashof.grashof())
}

///|
test "dead point returns an error instead of aborting" {
  match @mechanisms.solve_four_bar(dead_point_params(), 0.0) {
    Ok(_) => fail("expected a dead-point error")
    Err(_) => ()
  }
  let sweep = @mechanisms.sweep_four_bar(
    dead_point_params(),
    start_deg=-10.0,
    end_deg=10.0,
    steps=4,
  )
  assert_true(sweep.errors.length() > 0)
  assert_true(sweep.has_warnings())
}

///|
test "transmission angle diagnostics flag a poor linkage" {
  let sweep = @mechanisms.sweep_four_bar(
    grashof_params(),
    start_deg=-5.0,
    end_deg=5.0,
    steps=10,
  )
  assert_true(sweep.solutions.length() > 0)
  assert_true(
    sweep.max_transmission_deg > 150.0 || sweep.min_transmission_deg < 30.0,
  )
  let has_transmission_warning = sweep.warnings.fold(init=false, fn(
    acc,
    warning,
  ) {
    acc || warning.contains("transmission angle")
  })
  assert_true(has_transmission_warning)
}

///|
test "upper_branch selects upper-Z pivot D and closes cleanly" {
  let params = @mechanisms.FourBarParams::new(
    ax=255.0,
    az=0.0,
    cx=195.0,
    cz=26.0,
    crank_len_mm=178.0,
    coupler_len_mm=48.0,
    guide_len_mm=175.0,
    output_len_mm=215.0,
    output_beta_deg=152.0,
    upper_branch=true,
  )
  let sweep = @mechanisms.sweep_four_bar(
    params,
    start_deg=22.9,
    end_deg=57.9,
    steps=35,
  )
  assert_eq(sweep.errors.length(), 0)
  for sol in sweep.solutions {
    assert_true(@mechanisms.loop_closure_residual(params, sol) < 1.0e-9)
    assert_true(sol.dz > sol.bz)
    assert_true(sol.transmission_deg > 35.0 && sol.transmission_deg < 100.0)
  }
}
