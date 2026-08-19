load helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/timefmt.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/tips.sh"
  SL_CONFIG_RAW=""
  SL_CONFIG_LINES="repo branch
context rate-forecast flow
tip"
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

# ── turno corrente ──

mk_transcript() {   # mk_transcript <promptId>
  printf '{"type":"user","promptId":"%s","message":{"role":"user"}}\n' "$1" \
    > "$BATS_TEST_TMPDIR/transcript.jsonl"
  # O fim de um transcript real costuma ser `attachment`, que não carrega
  # promptId — é por isso que a leitura usa `tail -n` e não `tail -c`.
  printf '{"type":"attachment","note":"sem promptId no fim do arquivo"}\n' \
    >> "$BATS_TEST_TMPDIR/transcript.jsonl"
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
}

@test "prompt id comes from the last entry that carries one" {
  mk_transcript "turno-A"
  run _tip_prompt_id
  [ "$output" = "turno-A" ]
}

@test "prompt id gives up when there is no transcript" {
  mk_transcript "turno-A"
  run _tip_prompt_id
  [ "$output" = "turno-A" ]
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run _tip_prompt_id
  [ "$status" -ne 0 ]
}

# ── estado por fonte ──

@test "state round trips a source" {
  _tip_state_put flow 0 1755900000 turno-A
  run _tip_state_get flow
  [ "$output" = "0 1755900000 turno-A" ]
}

@test "state keeps sources independent" {
  _tip_state_put flow 0 1755900000 turno-A
  _tip_state_put 7d   2 1755800000 turno-B
  _tip_state_put flow 1 1755700000 turno-C
  run _tip_state_get 7d
  [ "$output" = "2 1755800000 turno-B" ]
}

@test "state drops one source and leaves the others" {
  _tip_state_put flow 0 1755900000 turno-A
  _tip_state_put 7d   2 1755800000 turno-B
  _tip_state_drop flow
  run _tip_state_get 7d
  [ "$output" = "2 1755800000 turno-B" ]
  run _tip_state_get flow
  [ "$status" -ne 0 ]
}

@test "state file disappears once the last source is dropped" {
  _tip_state_put flow 0 1755900000 turno-A
  [ -f "$SL_CACHE_DIR/tip-state.tsv" ]
  _tip_state_drop flow
  [ ! -f "$SL_CACHE_DIR/tip-state.tsv" ]
}

# ── a regra ──

@test "shows on the first crossing above one hundred" {
  mk_transcript "turno-A"
  run _tip_should_show flow 116 1755900000 1755000000
  [ "$status" -eq 0 ]
}

@test "keeps showing within the same turn" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  run _tip_should_show flow 117 1755900000 1755000000
  [ "$status" -eq 0 ]
}

@test "goes quiet on the next turn when nothing got worse" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  run _tip_should_show flow 117 1755900000 1755000000
  [ "$status" -ne 0 ]
}

@test "speaks again on the next turn when the step went up" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  run _tip_should_show flow 130 1755900000 1755000000
  [ "$status" -eq 0 ]
}

@test "speaks again when the block date moved more than a tenth closer" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  # Faltavam 900000s, então a margem é 90000s. Antecipar 200000s passa dela.
  run _tip_should_show flow 116 1755700000 1755000000
  [ "$status" -eq 0 ]
}

@test "stays quiet when the block date barely moved" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  run _tip_should_show flow 116 1755880000 1755000000
  [ "$status" -ne 0 ]
}

# ── fontes ──

write_flow() {   # write_flow <pct> <proj> <blocked|null>
  FLOW_JSON="$BATS_TEST_TMPDIR/flow.json"
  cat > "$FLOW_JSON" <<EOF
{"ok":true,
 "budget":{"percentage":$1,"projected_percentage":$2,"blocked_epoch":$3,"renewal_epoch":1756100000},
 "requests":{"percentage":5,"projected_percentage":null,"renewal_epoch":1756100000}}
EOF
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$FLOW_JSON\"}}}"
}

fake_forecast() {   # fake_forecast <linha que o helper imprime>
  cat > "$BATS_TEST_TMPDIR/fake-forecast.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$1"
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_FORECAST_BIN="$BATS_TEST_TMPDIR/fake-forecast.sh"
}

@test "flow source reports projection, usage and block date" {
  write_flow 25 116.4 1755900000
  run _tip_flow_source
  [ "$output" = "116 25 1755900000 1756100000" ]
}

@test "flow source stays silent without a block date" {
  write_flow 25 116.4 1755900000
  run _tip_flow_source
  [ "$output" = "116 25 1755900000 1756100000" ]
  write_flow 25 48.0 null
  run _tip_flow_source
  [ "$status" -ne 0 ]
}

@test "flow source stays silent when the widget is not on the bar" {
  write_flow 25 116.4 1755900000
  run _tip_flow_source
  [ "$output" = "116 25 1755900000 1756100000" ]
  SL_CONFIG_LINES="repo branch
context rate-forecast
tip"
  run _tip_flow_source
  [ "$status" -ne 0 ]
}

@test "flow source answers with the quota that locks first" {
  FLOW_JSON="$BATS_TEST_TMPDIR/flow.json"
  cat > "$FLOW_JSON" <<'EOF'
{"ok":true,
 "budget":{"percentage":25,"projected_percentage":116,"blocked_epoch":1755900000,"renewal_epoch":1756100000},
 "requests":{"percentage":40,"projected_percentage":210,"blocked_epoch":1755800000,"renewal_epoch":1756100000}}
EOF
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$FLOW_JSON\"}}}"
  run _tip_flow_source
  [ "$output" = "210 40 1755800000 1756100000" ]
}

@test "rate forecast source reports what the helper projects" {
  fake_forecast "crit 134 1755870000"
  SL_7D_PCT=23.4
  SL_7D_RESET=1756000000
  run _tip_rf_source 7d
  [ "$output" = "134 23 1755870000 1756000000" ]
}

@test "rate forecast source stays silent when the helper reports no block" {
  fake_forecast "crit 134 1755870000"
  SL_7D_PCT=23.4
  SL_7D_RESET=1756000000
  run _tip_rf_source 7d
  [ "$output" = "134 23 1755870000 1756000000" ]
  fake_forecast "warn 92"
  run _tip_rf_source 7d
  [ "$status" -ne 0 ]
}

@test "rate forecast source stays silent when the widget is not on the bar" {
  fake_forecast "crit 134 1755870000"
  SL_7D_PCT=23.4
  SL_7D_RESET=1756000000
  run _tip_rf_source 7d
  [ "$output" = "134 23 1755870000 1756000000" ]
  SL_CONFIG_LINES="repo branch
context flow
tip"
  run _tip_rf_source 7d
  [ "$status" -ne 0 ]
}

# ── as frases ──

@test "flow phrase corrects the reading and gives the slowdown target" {
  run _tip_phrase flow 116 25 1755900000 1756100000
  [ "$output" = "Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}

@test "seven day phrase names its own window" {
  run _tip_phrase 7d 134 23 1755870000 1756000000
  [ "$output" = "Dica da janela 7d: →134% é projeção, não gasto — cortar 31% do ritmo evita" ]
}

@test "five hour phrase trades the reading fix for the length of the pause" {
  run _tip_phrase 5h 118 60 1755897000 1755900000
  [ "$output" = "Dica da janela 5h: →118% é projeção — cortar 31% evita 50m parado" ]
}

@test "five hour phrase stays silent when the pause is shorter than the floor" {
  run _tip_phrase 5h 118 60 1755897000 1755900000
  [ "$output" = "Dica da janela 5h: →118% é projeção — cortar 31% evita 50m parado" ]
  run _tip_phrase 5h 118 60 1755899400 1755900000
  [ "$status" -ne 0 ]
}

@test "phrase refuses a source it does not know" {
  run _tip_phrase flow 116 25 1755900000 1756100000
  [ -n "$output" ]
  run _tip_phrase 30d 116 25 1755900000 1756100000
  [ "$status" -ne 0 ]
}

# Largura em COLUNAS, não em bytes.
#
# `${#var}` conta bytes quando o locale é C, que é o do runner do Windows: a
# frase do Flow tem 77 caracteres e 85 bytes, porque `→` ocupa três e cada
# acento dois. Remover os bytes de continuação de UTF-8 (0x80–0xBF) deixa
# exatamente um byte por caractere, e a contagem passa a valer em qualquer
# locale. O que a barra disputa é coluna de terminal, não byte.
tip_width() {
  printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' \n'
}

@test "every phrase fits in eighty columns" {
  local widest=0 n
  run _tip_phrase flow 116 25 1755900000 1756100000
  n="$(tip_width "$output")" ; [ "$n" -gt "$widest" ] && widest="$n"
  run _tip_phrase 7d 134 23 1755870000 1756000000
  n="$(tip_width "$output")" ; [ "$n" -gt "$widest" ] && widest="$n"
  run _tip_phrase 5h 118 60 1755897000 1755900000
  n="$(tip_width "$output")" ; [ "$n" -gt "$widest" ] && widest="$n"
  # Uma projeção de três dígitos é o pior caso de largura que a fonte produz.
  run _tip_phrase 7d 999 23 1755870000 1756000000
  n="$(tip_width "$output")" ; [ "$n" -gt "$widest" ] && widest="$n"
  # Contraprova: sem ela, uma função que não existe deixa widest em zero e o
  # teste passa afirmando que frases inexistentes cabem em 80 colunas.
  [ "$widest" -ge 60 ]
  [ "$widest" -le 80 ]
}
