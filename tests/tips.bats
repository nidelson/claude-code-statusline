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
  _tip_state_put flow "0:1755900000" turno-A
  run _tip_state_get flow
  [ "$output" = "0:1755900000 turno-A" ]
}

@test "state keeps sources independent" {
  _tip_state_put flow "0:1755900000" turno-A
  _tip_state_put 7d   "2:1755800000" turno-B
  _tip_state_put flow "1:1755700000" turno-C
  run _tip_state_get 7d
  [ "$output" = "2:1755800000 turno-B" ]
}

@test "state drops one source and leaves the others" {
  _tip_state_put flow "0:1755900000" turno-A
  _tip_state_put 7d   "2:1755800000" turno-B
  _tip_state_drop flow
  run _tip_state_get 7d
  [ "$output" = "2:1755800000 turno-B" ]
  run _tip_state_get flow
  [ "$status" -ne 0 ]
}

@test "state file disappears once the last source is dropped" {
  _tip_state_put flow "0:1755900000" turno-A
  [ -f "$SL_CACHE_DIR/tip-state.tsv" ]
  _tip_state_drop flow
  [ ! -f "$SL_CACHE_DIR/tip-state.tsv" ]
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
  write_flow 25 116 1755900000
  SL_NOW=1755000000
  run _tip_src_flow ""
  [ "${output#*	}" = "⎿ Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}

@test "seven day phrase names its own window" {
  fake_forecast "crit 134 1755870000"
  SL_7D_PCT=23 ; SL_7D_RESET=1756000000 ; SL_NOW=1755000000
  run _tip_src_7d ""
  [ "${output#*	}" = "⎿ Janela 7d: →134% é projeção, não gasto — cortar 31% do ritmo evita" ]
}

@test "five hour phrase trades the reading fix for the length of the pause" {
  fake_forecast "crit 118 1755897000"
  SL_5H_PCT=60 ; SL_5H_RESET=1755900000 ; SL_NOW=1755000000
  run _tip_src_5h ""
  [ "${output#*	}" = "⎿ Janela 5h: →118% é projeção — cortar 31% evita 50m parado" ]
}

@test "five hour phrase stays silent when the pause is shorter than the floor" {
  SL_5H_PCT=60 ; SL_5H_RESET=1755900000 ; SL_NOW=1755000000
  fake_forecast "crit 118 1755897000"
  run _tip_src_5h ""
  [ -n "$output" ]
  fake_forecast "crit 118 1755899400"
  run _tip_src_5h ""
  [ "$status" -ne 0 ]
}

@test "projection source refuses a window it does not know" {
  fake_forecast "crit 134 1755870000"
  SL_7D_PCT=23 ; SL_7D_RESET=1756000000 ; SL_NOW=1755000000
  run _tip_src_projection 7d ""
  [ -n "$output" ]
  run _tip_src_projection 30d ""
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
  SL_NOW=1755000000
  write_flow 25 116 1755900000
  run _tip_src_flow ""
  n="$(tip_width "${output#*	}")" ; [ "$n" -gt "$widest" ] && widest="$n"
  SL_7D_PCT=23 ; SL_7D_RESET=1756000000
  fake_forecast "crit 134 1755870000"
  run _tip_src_7d ""
  n="$(tip_width "${output#*	}")" ; [ "$n" -gt "$widest" ] && widest="$n"
  SL_5H_PCT=60 ; SL_5H_RESET=1755900000
  fake_forecast "crit 118 1755897000"
  run _tip_src_5h ""
  n="$(tip_width "${output#*	}")" ; [ "$n" -gt "$widest" ] && widest="$n"
  # Uma projeção de três dígitos é o pior caso de largura que a fonte produz.
  fake_forecast "crit 999 1755870000"
  run _tip_src_7d ""
  n="$(tip_width "${output#*	}")" ; [ "$n" -gt "$widest" ] && widest="$n"
  # Contraprova: sem ela, funções ausentes deixam widest em zero e o teste passa
  # afirmando que frases inexistentes cabem em 80 colunas.
  [ "$widest" -ge 60 ]
  [ "$widest" -le 80 ]
}

# ── contrato de fonte generalizado ──

@test "slug turns a dashed source name into a function suffix" {
  run _tip_slug cache-cold
  [ "$output" = "cache_cold" ]
}

@test "flow key changes when the step goes up" {
  run _tip_flow_key "0:1755900000" 1 1755900000 1755000000
  [ "$output" = "1:1755900000" ]
}

@test "flow key survives a block date that barely moved" {
  run _tip_flow_key "0:1755900000" 1 1755900000 1755000000
  [ "$output" = "1:1755900000" ]
  # faltavam 900000s, margem 90000s; andou só 20000s
  run _tip_flow_key "0:1755900000" 0 1755880000 1755000000
  [ "$output" = "0:1755900000" ]
}

@test "flow key changes when the block date moved materially" {
  run _tip_flow_key "0:1755900000" 0 1755700000 1755000000
  [ "$output" = "0:1755700000" ]
}

@test "flow key with no previous state is the current one" {
  run _tip_flow_key "" 0 1755900000 1755000000
  [ "$output" = "0:1755900000" ]
}

@test "flow source emits a key and the very same phrase as before" {
  write_flow 25 116.4 1755900000
  SL_NOW=1755000000
  run _tip_src_flow ""
  [ "$output" = "$(printf '0:1755900000\t⎿ Flow: →116%% é projeção, não gasto — cortar 18%% do ritmo evita a trava')" ]
}

# ── preço derivado do custo real ──

mk_usage_transcript() {   # <input> <read> <write> <output>
  local f="$BATS_TEST_TMPDIR/usage.jsonl"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$1" "$2" "$3" "$4" > "$f"
  export SL_TRANSCRIPT="$f"
}

@test "usage totals add up the transcript" {
  mk_usage_transcript 870 106711624 2938536 639464
  run _tip_usage_totals
  [ "$output" = "870 106711624 2938536 639464" ]
}

@test "breakeven is three exchanges on a one hour ttl" {
  run _tip_breakeven 2
  [ "$output" = "3" ]
}

@test "breakeven is two exchanges on a five minute ttl" {
  run _tip_breakeven 2
  [ "$output" = "3" ]
  run _tip_breakeven 1.25
  [ "$output" = "2" ]
}

@test "regrave cost matches the price derived from real aggregates" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88
  # den = 870 + 0.1*106711624 + 2*2938536 + 5*639464 = 19746424
  # P_in = 88/19746424 ; 393000 tokens a 2x  =>  ~350 centavos
  run _tip_regrave_cost 393000 2
  [ "$output" -ge 340 ]
  [ "$output" -le 360 ]
}

@test "regrave cost gives up when the session cost is zero" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88
  run _tip_regrave_cost 393000 2
  [ "$status" -eq 0 ]
  SL_COST=0
  run _tip_regrave_cost 393000 2
  [ "$status" -ne 0 ]
}

@test "regrave cost gives up without a transcript" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88
  run _tip_regrave_cost 393000 2
  [ "$status" -eq 0 ]
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run _tip_regrave_cost 393000 2
  [ "$status" -ne 0 ]
}

# ── fontes de cache ──

# _cache_probe vive em widgets/cache.sh e devolve "<timestamp> <ttl>". O tip só a
# chama quando o widget cache está configurado; aqui ela é substituída direto.
fake_probe() {   # fake_probe <epoch da última troca> <ttl>
  eval "_cache_probe() { printf '%s %s' '$1' '$2'; }"
  SL_CONFIG_LINES="repo branch
context rate-forecast flow cache
tip"
}

@test "cache cold speaks when the prefix expired with a large context" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [[ "$output" == *"⎿ Cache: regravar 393k custa 2×"* ]]
  [[ "$output" == *"vale a partir de 3 trocas"* ]]
}

@test "cache cold stays quiet below the context floor" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [ -n "$output" ]
  SL_CTX_USED=12000
  run _tip_src_cache_cold ""
  [ "$status" -ne 0 ]
}

@test "cache cold stays quiet while the cache is still warm" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [ -n "$output" ]
  fake_probe 1754999000 3600
  run _tip_src_cache_cold ""
  [ "$status" -ne 0 ]
}

@test "cache cold drops the price when it cannot be derived" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [[ "$output" == *'(~$'* ]]
  SL_COST=0
  run _tip_src_cache_cold ""
  [[ "$output" == *"custa 2×"* ]]
  [[ "$output" != *'(~$'* ]]
}

@test "cache cold uses the five minute multiplier on a short ttl" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 300
  run _tip_src_cache_cold ""
  [[ "$output" == *"custa 1.25×"* ]]
  [[ "$output" == *"vale a partir de 2 trocas"* ]]
}

@test "cache expiring speaks inside the last minute" {
  SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754996445 3600
  run _tip_src_cache_expiring ""
  [[ "$output" == *"45s até esfriar"* ]]
}

@test "cache expiring stays quiet outside the last minute" {
  SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754996445 3600
  run _tip_src_cache_expiring ""
  [ -n "$output" ]
  fake_probe 1754999000 3600
  run _tip_src_cache_expiring ""
  [ "$status" -ne 0 ]
}

@test "cache sources stay quiet when the cache widget is not on the bar" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [ -n "$output" ]
  SL_CONFIG_LINES="repo branch
context flow
tip"
  run _tip_src_cache_cold ""
  [ "$status" -ne 0 ]
}

@test "cache phrases fit in eighty columns" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=1000000 ; SL_NOW=1755000000
  local w1 w2
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  w1="$(tip_width "${output#*	}")"
  fake_probe 1754996445 3600
  run _tip_src_cache_expiring ""
  w2="$(tip_width "${output#*	}")"
  [ "$w1" -ge 50 ]
  [ "$w2" -ge 50 ]
  [ "$w1" -le 80 ]
  [ "$w2" -le 80 ]
}

# ── o prefixo da linha de dica ──

@test "label uses the note glyph when icons are on" {
  SL_CONFIG_ICONS=1
  run _tip_label "Flow:" "Dica do Flow:"
  [ "$output" = "⎿ Flow:" ]
}

@test "label falls back to the spelled out word without icons" {
  SL_CONFIG_ICONS=1
  run _tip_label "Flow:" "Dica do Flow:"
  [ "$output" = "⎿ Flow:" ]
  SL_CONFIG_ICONS=0
  run _tip_label "Flow:" "Dica do Flow:"
  [ "$output" = "Dica do Flow:" ]
}

@test "flow phrase carries the note glyph with icons on" {
  SL_CONFIG_ICONS=1
  write_flow 25 116 1755900000
  SL_NOW=1755000000
  run _tip_src_flow ""
  [ "${output#*	}" = "⎿ Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}

@test "flow phrase spells out the word with icons off" {
  SL_CONFIG_ICONS=0
  write_flow 25 116 1755900000
  SL_NOW=1755000000
  run _tip_src_flow ""
  [ "${output#*	}" = "Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}

@test "cache phrase carries the note glyph too" {
  SL_CONFIG_ICONS=1
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [ "${output#*	}" = "⎿ Cache: regravar 393k custa 2× (~\$3.50) — vale a partir de 3 trocas" ]
}
