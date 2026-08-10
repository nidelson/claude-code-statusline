load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/flow.sh"
  SL_CONFIG_RAW=""
  JSON="$BATS_TEST_TMPDIR/flow.json"
}

# Escreve o cache no formato que bin/flow-consumption.sh grava.
write_cache() {
  cat > "$JSON" <<EOF
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":${1:-34.7},"projected_percentage":${2:-58.2},"budget_limit":100,"consumed_usd":34.7},
 "requests":{"percentage":${3:-12.1},"projected_percentage":${4:-20.4},"limit":1000,"unlimited":false}}
EOF
}

# refresh desligado em quase todo teste: o alvo aqui é a leitura, e disparar o
# fetcher de verdade tocaria a rede.
use_config() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
}

quiet_config() {
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"refresh\":false,\"cache\":\"$JSON\"}}}"
}

@test "registers itself on load" {
  sl_widget_registered flow
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR flow)" = "1" ]
}

@test "renders nothing before the first fetch" {
  # Máquina sem acesso ao Flow não vê erro, vê a statusline sem esse pedaço.
  quiet_config
  run widget_flow_render
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "renders nothing when the fetch reported failure" {
  printf '{"ok":false,"message":"sem token"}' > "$JSON"
  quiet_config
  run widget_flow_render
  [ "$output" = "" ]
}

@test "renders nothing when the cache is corrupt" {
  printf 'quebrado {' > "$JSON"
  quiet_config
  run widget_flow_render
  [ "$output" = "" ]
}

@test "shows budget usage and forecast" {
  write_cache
  quiet_config
  run widget_flow_render
  [[ "$output" == *"flow:34%→58%"* ]]
}

@test "floors the percentages instead of showing decimals" {
  write_cache 34.9 58.9
  quiet_config
  run widget_flow_render
  [[ "$output" == *"34%"* ]]
  [[ "$output" != *"."* ]]
}

@test "paints green on a low forecast" {
  write_cache 34.7 58.2
  quiet_config
  run widget_flow_render
  [[ "$output" == *$'\033[32m'* ]]
}

@test "paints yellow from eighty percent projected" {
  write_cache 60 91
  quiet_config
  run widget_flow_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "paints red when the forecast overruns the quota" {
  # O ponto do widget: avisar antes de bloquear, não depois.
  write_cache 66 117
  quiet_config
  run widget_flow_render
  [[ "$output" == *$'\033[31m'* ]]
  [[ "$output" == *"117%"* ]]
}

@test "the metric option switches to requests" {
  write_cache 34.7 58.2 12.1 20.4
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"refresh\":false,\"cache\":\"$JSON\",\"metric\":\"requests\"}}}"
  run widget_flow_render
  [[ "$output" == *"req:12%→20%"* ]]
}

@test "budget and requests do not share a cache entry" {
  write_cache 34.7 58.2 12.1 20.4
  quiet_config
  budget_out="$(widget_flow_render)"
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"refresh\":false,\"cache\":\"$JSON\",\"metric\":\"requests\"}}}"
  run widget_flow_render
  [ "$output" != "$budget_out" ]
}

@test "reuses the cached value" {
  write_cache
  quiet_config
  widget_flow_render >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'flow-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run widget_flow_render
  [ "$output" = "PLANTED" ]
}

@test "picks up a new fetch as soon as the file changes" {
  # O mtime do JSON é a sentinela exata: o número novo aparece no instante em
  # que a busca termina, sem esperar o TTL de refresh.
  write_cache 34.7 58.2
  quiet_config
  touch -t 202001010000 "$JSON"
  widget_flow_render >/dev/null
  write_cache 70 95
  run widget_flow_render
  [[ "$output" == *"70%→95%"* ]]
}

@test "throttles the refresh to once per ttl" {
  # Marcador gravado ANTES do disparo: dois repaints quase simultâneos não
  # podem virar duas buscas.
  write_cache
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"cache\":\"$JSON\",\"ttl\":3600,\"bin\":\"$BATS_TEST_TMPDIR/counter.sh\"}}}"
  cat > "$BATS_TEST_TMPDIR/counter.sh" <<'EOF'
#!/usr/bin/env bash
printf 'x' >> "$COUNTER_FILE"
EOF
  chmod +x "$BATS_TEST_TMPDIR/counter.sh"
  export COUNTER_FILE="$BATS_TEST_TMPDIR/count"
  widget_flow_render >/dev/null
  widget_flow_render >/dev/null
  widget_flow_render >/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$COUNTER_FILE" ] && break
    sleep 0.2
  done
  [ "$(wc -c < "$COUNTER_FILE" | tr -d ' ')" = "1" ]
}

@test "the refresh option turns the fetch off" {
  write_cache
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"refresh\":false,\"cache\":\"$JSON\",\"bin\":\"$BATS_TEST_TMPDIR/counter.sh\"}}}"
  cat > "$BATS_TEST_TMPDIR/counter.sh" <<'EOF'
#!/usr/bin/env bash
printf 'x' >> "$COUNTER_FILE"
EOF
  chmod +x "$BATS_TEST_TMPDIR/counter.sh"
  export COUNTER_FILE="$BATS_TEST_TMPDIR/count"
  widget_flow_render >/dev/null
  sleep 0.5
  [ ! -f "$COUNTER_FILE" ]
}

@test "a missing fetcher does not break the render" {
  write_cache
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"cache\":\"$JSON\",\"bin\":\"/path/that/does/not/exist\"}}}"
  run widget_flow_render
  [ "$status" -eq 0 ]
  [[ "$output" == *"flow:"* ]]
}

@test "an invalid ttl falls back to the default" {
  write_cache
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"refresh\":false,\"cache\":\"$JSON\",\"ttl\":\"sempre\"}}}"
  run widget_flow_render
  [[ "$output" == *"flow:"* ]]
}

@test "the shipped fetcher is executable" {
  [ -x "$PROJECT_ROOT/bin/flow-consumption.sh" ]
}

@test "the shipped fetcher holds no hardcoded credential" {
  # Ele troca ANTHROPIC_AUTH_TOKEN por um token curto em runtime; nada de
  # segredo pode estar versionado junto.
  ! grep -qE '(client_secret|password|api_key) *= *["'"'"'][A-Za-z0-9]{8,}' \
    "$PROJECT_ROOT/bin/flow-consumption.sh"
}
