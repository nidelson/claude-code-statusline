load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/rate-forecast.sh"
  export SL_FORECAST_BIN="$PROJECT_ROOT/tests/fixtures/fake-forecast.sh"
  SL_CONFIG_RAW=""
  SL_5H_PCT="42"
  SL_5H_RESET="1800000000"
  SL_7D_PCT="13"
  SL_7D_RESET="1800600000"
}

@test "registers itself on load" {
  sl_widget_registered rate-forecast
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR rate-forecast)" = "1" ]
}

@test "renders nothing without a percentage" {
  SL_5H_PCT=""
  run widget_rate_forecast_render
  [ "$output" = "" ]
}

@test "level none shows the percentage only" {
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"→"* ]]
}

@test "level crit shows the projection" {
  export FAKE_FORECAST_OUT="crit 116"
  run widget_rate_forecast_render
  [[ "$output" == *"→116%"* ]]
}

@test "level crit paints red" {
  export FAKE_FORECAST_OUT="crit 116"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[31m'* ]]
}

@test "level warn paints yellow" {
  export FAKE_FORECAST_OUT="warn 92"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "level ok paints green" {
  export FAKE_FORECAST_OUT="ok 55"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[32m'* ]]
}

@test "missing helper still shows the percentage" {
  export SL_FORECAST_BIN="/path/that/does/not/exist"
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
}

@test "missing helper shows no projection" {
  export SL_FORECAST_BIN="/path/that/does/not/exist"
  run widget_rate_forecast_render
  [[ "$output" != *"→"* ]]
}

@test "garbage from the helper degrades to the percentage" {
  export FAKE_FORECAST_OUT="isto nao e um nivel valido"
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"→"* ]]
}

@test "window option selects the seven-day figures" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"window":"7d"}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"7d:13%"* ]]
}

@test "defaults to the five-hour window" {
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"5h:42%"* ]]
}
