load helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/tips.sh"
}

# ── corte de ritmo ──

@test "cut turns 116 projected over 25 used into an 18 percent slowdown" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
}

@test "cut refuses a projection that is not above one hundred" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
  run _tip_cut 98 25
  [ "$status" -ne 0 ]
}

@test "cut refuses when used is not below the projection" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
  run _tip_cut 116 116
  [ "$status" -ne 0 ]
}

@test "cut refuses non numeric input" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
  run _tip_cut "abc" 25
  [ "$status" -ne 0 ]
}

# ── degrau ──

@test "step buckets the projection in slices of twenty five" {
  run _tip_step 101 ; [ "$output" = "0" ]
  run _tip_step 124 ; [ "$output" = "0" ]
  run _tip_step 125 ; [ "$output" = "1" ]
  run _tip_step 150 ; [ "$output" = "2" ]
  run _tip_step 999 ; [ "$output" = "3" ]
}

@test "step refuses a projection at or below one hundred" {
  run _tip_step 125
  [ "$output" = "1" ]
  run _tip_step 100
  [ "$status" -ne 0 ]
}
