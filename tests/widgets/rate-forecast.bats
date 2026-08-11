load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/timefmt.sh"
  source "$PROJECT_ROOT/widgets/rate-forecast.sh"
  export SL_FORECAST_BIN="$PROJECT_ROOT/tests/fixtures/fake-forecast.sh"
  SL_CONFIG_RAW=""
  SL_5H_PCT="42"
  SL_5H_RESET="1800000000"
  SL_7D_PCT="13"
  SL_7D_RESET="1800600000"
  # Congela o instante para toda a suíte. Sem isso a contagem regressiva é
  # calculada contra o relógio real e muda a cada dia: os resets acima ficam a
  # centenas de dias daqui, e uma regressiva como "157d6h" contém "7d" como
  # substring — o suficiente para derrubar uma asserção que só queria saber se o
  # rótulo da janela de sete dias estava presente.
  SL_NOW=1799990000
}

@test "registers itself on load" {
  sl_widget_registered rate-forecast
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR rate-forecast)" = "1" ]
}

@test "renders nothing without any percentage" {
  SL_5H_PCT=""
  SL_7D_PCT=""
  run widget_rate_forecast_render
  [ "$output" = "" ]
}

@test "one window alone renders without a stray separator" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT=""
  run widget_rate_forecast_render
  [[ "$output" == *"7d:"* ]]
  [[ "$output" == *"13%"* ]]
  [[ "$output" != *"5h:"* ]]
  # O separador entre janelas vai cercado de espaços; o `·` interno do rótulo de
  # reset não vai. Só o primeiro seria órfão aqui.
  [[ "$output" != *" · "* ]]
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
  # Rótulo e percentual não são mais contíguos: o rótulo é esmaecido e o
  # percentual carrega a cor do nível de uso, com sequências de escape entre os
  # dois.
  [[ "$output" == *"7d:"* ]]
  [[ "$output" == *"13%"* ]]
}

@test "defaults to the five-hour window" {
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"42%"* ]]
}

@test "usage below warn paints green" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="49"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[32m'"49%"* ]]
}

@test "usage at warn paints yellow" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="50"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[33m'"50%"* ]]
}

@test "usage at crit paints red" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="80"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[31m'"80%"* ]]
}

@test "usage just below crit stays yellow" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="79"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[33m'"79%"* ]]
}

@test "a float percentage is rounded before comparison" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="49.6"
  run widget_rate_forecast_render
  [[ "$output" == *"50%"* ]]
  [[ "$output" == *$'\033[33m'"50%"* ]]
}

@test "configured thresholds override the defaults" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"warn":10,"crit":20}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="25"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[31m'"25%"* ]]
}

@test "a non-numeric percentage renders nothing" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="banana"
  SL_7D_PCT=""
  run widget_rate_forecast_render
  [ "$output" = "" ]
}

@test "shows the reset clock and countdown under a day" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800006480
  run widget_rate_forecast_render
  [[ "$output" =~ [0-9]{2}:[0-9]{2}.1h48m ]]
}

@test "shows the reset weekday and countdown over a day" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800454000
  run widget_rate_forecast_render
  [[ "$output" =~ [A-Za-z]{3}.5d6h ]]
}

@test "normalizes a reset given in milliseconds" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800006480000
  run widget_rate_forecast_render
  [[ "$output" =~ 1h48m ]]
}

@test "a reset in the past drops the times but keeps the percentage" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1799999000
  # Isola a janela de cinco horas: a de sete dias traria o próprio reset, e o
  # `·` dele mascararia a degradação que este teste mede.
  SL_7D_PCT=""
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"·"* ]]
}

@test "an unreadable reset drops the times but keeps the percentage" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET="banana"
  SL_7D_PCT=""
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"·"* ]]
}

@test "renders both windows by default" {
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"42%"* ]]
  [[ "$output" == *"7d:"* ]]
  [[ "$output" == *"13%"* ]]
}

@test "the five-hour window comes first" {
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "${output%%7d*}" == *"5h:"* ]]
}

@test "window five-hour filters out the seven-day window" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"window":"5h"}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"5h:"* ]]
  # Com dois-pontos: é o rótulo da janela que não pode aparecer. Sem eles, a
  # asserção casaria com um "7d" vindo de dentro de uma contagem regressiva.
  [[ "$output" != *"7d:"* ]]
}

@test "each window is coloured on its own figures" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="85"
  SL_7D_PCT="10"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[31m'"85%"* ]]
  [[ "$output" == *$'\033[32m'"10%"* ]]
}

@test "a configured separator replaces the default" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"separator":"//","reset":false}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"//"* ]]
}

@test "icons on shows the widget mark" {
  export FAKE_FORECAST_OUT="none"
  SL_CONFIG_ICONS=1
  run widget_rate_forecast_render
  [[ "$output" == *"⏱"* ]]
}

@test "icons off hides the widget mark" {
  export FAKE_FORECAST_OUT="none"
  SL_CONFIG_ICONS=0
  run widget_rate_forecast_render
  [[ "$output" != *"⏱"* ]]
  [[ "$output" == *"5h:"* ]]
}

@test "icons off hides the reset mark but keeps the times" {
  export FAKE_FORECAST_OUT="none"
  SL_CONFIG_ICONS=0
  SL_NOW=1800000000
  SL_5H_RESET=1800006480
  run widget_rate_forecast_render
  [[ "$output" != *"⟳"* ]]
  [[ "$output" == *"1h48m"* ]]
}

@test "reset false hides the times" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"reset":false}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800006480
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"1h48m"* ]]
}
