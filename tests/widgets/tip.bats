load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/timefmt.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/tips.sh"
  source "$PROJECT_ROOT/widgets/tip.sh"
  SL_CONFIG_LINES="repo branch
context rate-forecast flow
tip"
  FLOW="$BATS_TEST_TMPDIR/flow.json"
  SL_NOW=1755000000
  # Sem forecast utilizável, 5h e 7d se calam sozinhos — os testes que os
  # querem em cena instalam o próprio helper falso.
  SL_FORECAST_BIN="$BATS_TEST_TMPDIR/sem-forecast.sh"
  SL_5H_PCT=""; SL_5H_RESET=""; SL_7D_PCT=""; SL_7D_RESET=""
  turn "turno-A"
}

turn() {   # turn <promptId>
  printf '{"type":"user","promptId":"%s"}\n' "$1" > "$BATS_TEST_TMPDIR/t.jsonl"
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
}

write_flow() {   # write_flow <pct> <proj> <blocked|null>
  cat > "$FLOW" <<EOF
{"ok":true,
 "budget":{"percentage":$1,"projected_percentage":$2,"blocked_epoch":$3,"renewal_epoch":1756100000},
 "requests":{"percentage":5,"projected_percentage":null,"renewal_epoch":1756100000}}
EOF
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$FLOW\"}}}"
}

FLOW_TIP="Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava"
SEVEN_TIP="Dica da janela 7d: →134% é projeção, não gasto — cortar 31% do ritmo evita"

@test "renders the flow tip when a block is projected" {
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ "$output" = "$FLOW_TIP" ]
}

@test "renders nothing when no source projects a block" {
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ "$output" = "$FLOW_TIP" ]
  write_flow 25 48.0 null
  run widget_tip_render
  [ "$output" = "" ]
}

@test "renders nothing on a later turn when nothing got worse" {
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ "$output" = "$FLOW_TIP" ]
  widget_tip_render >/dev/null
  turn "turno-B"
  run widget_tip_render
  [ "$output" = "" ]
}

@test "speaks again on a later turn when the projection got worse" {
  write_flow 25 116.4 1755900000
  widget_tip_render >/dev/null
  turn "turno-B"
  run widget_tip_render
  [ "$output" = "" ]
  write_flow 25 160.0 1755900000
  run widget_tip_render
  [ "$output" = "Dica do Flow: →160% é projeção, não gasto — cortar 44% do ritmo evita a trava" ]
}

@test "renders one line per source when two of them fire" {
  cat > "$BATS_TEST_TMPDIR/fake-forecast.sh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "7d" ]; then printf 'crit 134 1755870000\n'; else printf 'ok 40\n'; fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_FORECAST_BIN="$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_5H_PCT=12 ; SL_5H_RESET=1755010000
  SL_7D_PCT=23 ; SL_7D_RESET=1756000000
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$FLOW_TIP" ]
  [ "${lines[1]}" = "$SEVEN_TIP" ]
}

@test "renders anyway when the transcript is missing" {
  write_flow 25 116.4 1755900000
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run widget_tip_render
  [ "$output" = "$FLOW_TIP" ]
}

@test "survives a corrupted state file" {
  write_flow 25 116.4 1755900000
  mkdir -p "$SL_CACHE_DIR"
  printf 'lixo sem tabs\n\n' > "$SL_CACHE_DIR/tip-state.tsv"
  run widget_tip_render
  [ "$status" -eq 0 ]
  [ "$output" = "$FLOW_TIP" ]
}

@test "forgets a source that stopped projecting a block" {
  write_flow 25 116.4 1755900000
  widget_tip_render >/dev/null
  [ -f "$SL_CACHE_DIR/tip-state.tsv" ]
  write_flow 25 48.0 null
  widget_tip_render >/dev/null
  [ ! -f "$SL_CACHE_DIR/tip-state.tsv" ]
}

@test "stays silent for the five hour window inside the pause floor" {
  cat > "$BATS_TEST_TMPDIR/fake-forecast.sh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "5h" ]; then printf 'crit 118 1755009400\n'; else printf 'ok 40\n'; fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_FORECAST_BIN="$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_5H_PCT=60 ; SL_5H_RESET=1755010000
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ "$output" = "$FLOW_TIP" ]
}
