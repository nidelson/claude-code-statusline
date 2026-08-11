load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/flow.sh"
  SL_CONFIG_RAW=""
  JSON="$BATS_TEST_TMPDIR/flow.json"
  # O separador entre segmentos sai esmaecido: espaço, escape, glifo, reset,
  # espaço. Procurar por " · " cru nunca casaria — e uma asserção que nunca casa
  # também nunca falha, que é pior do que não existir.
  SEP=$' \033[2m·\033[0m '
  # Rótulos com ícones ligados, que é o padrão. Nomeados porque aparecem em
  # quase toda asserção e trocá-los não deve exigir varrer o arquivo.
  BUD='💰'
  REQ='💬'
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

# Mesma configuração, mais as opções passadas — para variar `metric` e
# `separator` sem repetir o JSON inteiro.
quiet_config_with() {
  use_config "{\"version\":1,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"refresh\":false,\"cache\":\"$JSON\",$1}}}"
}

# `icons` é chave de topo, não opção do widget.
no_icons_config() {
  use_config "{\"version\":1,\"icons\":false,\"lines\":[[\"flow\"]],\"widgets\":{\"flow\":{\"refresh\":false,\"cache\":\"$JSON\"}}}"
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

@test "renders both segments by default" {
  # Budget e requests são cotas independentes: estourar uma não diz nada sobre a
  # outra, então as duas ficam visíveis.
  write_cache
  quiet_config
  run widget_flow_render
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" == *"35%"* ]]
  [[ "$output" == *"$REQ"* ]]
  [[ "$output" == *"12%"* ]]
  [[ "$output" == *"$SEP"* ]]
}

@test "budget comes first" {
  write_cache
  quiet_config
  run widget_flow_render
  [[ "${output%%$REQ*}" == *"$BUD"* ]]
}

@test "the metric option narrows to budget alone" {
  write_cache
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" != *"$REQ"* ]]
}

@test "the metric option narrows to requests alone" {
  write_cache
  quiet_config_with '"metric":"requests"'
  run widget_flow_render
  [[ "$output" == *"$REQ"* ]]
  [[ "$output" != *"$BUD"* ]]
}

@test "icons off swaps the glyphs for whole words" {
  # Quem desliga os ícones normalmente o faz por causa do terminal, não por
  # falta de espaço: a palavra inteira não exige adivinhar o que `req` abrevia.
  write_cache
  no_icons_config
  run widget_flow_render
  [[ "$output" == *"budget:"* ]]
  [[ "$output" == *"requests:"* ]]
  [[ "$output" != *"$BUD"* ]]
  [[ "$output" != *"$REQ"* ]]
}

@test "icons off keeps the numbers and the separator" {
  write_cache
  no_icons_config
  run widget_flow_render
  [[ "$output" == *"35%"* ]]
  [[ "$output" == *"12%"* ]]
  [[ "$output" == *"$SEP"* ]]
}

@test "the icons setting does not leak across cache entries" {
  # A chave do cache guarda a linha pronta, e os rótulos fazem parte dela.
  write_cache
  no_icons_config
  plain_out="$(widget_flow_render)"
  quiet_config
  run widget_flow_render
  [ "$output" != "$plain_out" ]
  [[ "$output" == *"$BUD"* ]]
}

@test "a configured separator replaces the default" {
  write_cache
  quiet_config_with '"separator":"//"'
  run widget_flow_render
  [[ "$output" == *"//"* ]]
}

@test "one segment alone renders without a stray separator" {
  write_cache
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  # Segmento ausente não pode deixar pontuação órfã.
  [[ "$output" != *"$SEP"* ]]
}

@test "an unlimited quota drops its segment" {
  # Percentual de um limite que não se aplica não decide nada, e ocuparia espaço
  # permanente ao lado de um que decide.
  cat > "$JSON" <<'EOF'
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":24.30,"projected_percentage":92.33},
 "requests":{"percentage":13.96,"projected_percentage":null,"unlimited":true}}
EOF
  quiet_config
  run widget_flow_render
  # Rótulo e percentual não são contíguos: o rótulo é esmaecido e o número
  # carrega a própria cor, com sequências de escape entre os dois.
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" == *"24%"* ]]
  [[ "$output" != *"$REQ"* ]]
  [[ "$output" != *"$SEP"* ]]
}

@test "a missing metric in the payload drops its segment" {
  printf '{"ok":true,"budget":{"percentage":40,"projected_percentage":50}}' > "$JSON"
  quiet_config
  run widget_flow_render
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" == *"40%"* ]]
  [[ "$output" != *"$REQ"* ]]
}

@test "a calm projection is not shown at all" {
  # 58% projetado não muda decisão nenhuma: quem não vê aviso já sabia seguir em
  # frente. A seta fica reservada para o que pede reação.
  write_cache 34.7 58.2
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" == *"35%"* ]]
  [[ "$output" != *"→"* ]]
}

@test "a projection at eighty percent is shown in yellow" {
  write_cache 60 91
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *"→91%"* ]]
  [[ "$output" == *$'\033[33m'"→91%"* ]]
}

@test "a projection over the quota is shown in red" {
  # O ponto do widget: avisar antes de bloquear, não depois.
  write_cache 66 117
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *$'\033[31m'"→117%"* ]]
}

@test "a null projection shows no arrow at all" {
  cat > "$JSON" <<'EOF'
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":13.96,"projected_percentage":null}}
EOF
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  # Projeção nula é ausência de projeção, não projeção de zero. `→0%` afirmaria
  # um número que a API nunca devolveu.
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" == *"14%"* ]]
  [[ "$output" != *"→"* ]]
}

@test "usage is coloured on its own figure, not on the projection" {
  # Com a projeção tranquila omitida, é o uso que precisa carregar o sinal:
  # um `95%` em verde afirmaria calma onde não há.
  write_cache 95 60
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *$'\033[33m'"95%"* ]]
  [[ "$output" != *"→"* ]]
}

@test "usage below eighty percent paints green" {
  write_cache 34.7 58.2
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *$'\033[32m'"35%"* ]]
}

@test "usage at the quota paints red" {
  write_cache 100 60
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *$'\033[31m'"100%"* ]]
}

@test "each segment is coloured on its own figures" {
  write_cache 90 60 10 20
  quiet_config
  run widget_flow_render
  [[ "$output" == *$'\033[33m'"90%"* ]]
  [[ "$output" == *$'\033[32m'"10%"* ]]
}

@test "rounds the percentages to whole numbers" {
  write_cache 34.9 91.6
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *"35%"* ]]
  [[ "$output" == *"92%"* ]]
  [[ "$output" != *"."* ]]
}

@test "two metric settings do not share a cache entry" {
  write_cache 34.7 58.2 12.1 20.4
  quiet_config_with '"metric":"budget"'
  budget_out="$(widget_flow_render)"
  quiet_config_with '"metric":"requests"'
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
  # Uso e projeção não são mais contíguos: cada um carrega a própria cor, com
  # sequências de escape entre os dois.
  [[ "$output" == *"70%"* ]]
  [[ "$output" == *"→95%"* ]]
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
  [[ "$output" == *"$BUD"* ]]
}

@test "an invalid ttl falls back to the default" {
  write_cache
  quiet_config_with '"ttl":"sempre"'
  run widget_flow_render
  [[ "$output" == *"$BUD"* ]]
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
