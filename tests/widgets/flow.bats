load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/timefmt.sh"
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
  INF='∞'
  WARN='⚠'
  RNW='⟳'
  LOCK='🔒'
  # Relógio fixo e duas renovações à frente dele. Vinte e vinte e cinco dias
  # caem na faixa de dia-e-mês e produzem regressivas sem hora — `20d`, `25d` —
  # o que mantém as asserções curtas.
  NOW=1800000000
  RENEW=1801728000    # +20 dias
  RENEW2=1802160000   # +25 dias
  BLOCK=1800432000    # +5 dias, entre agora e a renovação
  BLOCK2=1800518400   # +6 dias
  SL_NOW="$NOW"
}

# Escreve o cache no formato que bin/flow-consumption.sh grava.
write_cache() {
  cat > "$JSON" <<EOF
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":${1:-34.7},"projected_percentage":${2:-58.2},"budget_limit":100,"consumed_usd":34.7},
 "requests":{"percentage":${3:-12.1},"projected_percentage":${4:-20.4},"limit":1000,"unlimited":false}}
EOF
}

# Cache com renovação nas duas cotas. Argumentos, em ordem: uso e projeção do
# budget, uso e projeção de requests, e os dois epochs de renovação. `null` é a
# ausência de projeção, que é como a API a manda.
write_renewal() {
  cat > "$JSON" <<EOF
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":${1:-24.3},"projected_percentage":${2:-null},
           "renewal_epoch":${5:-$RENEW}},
 "requests":{"percentage":${3:-14.0},"projected_percentage":${4:-null},
             "renewal_epoch":${6:-$RENEW},"unlimited":false}}
EOF
}

# Quantas vezes o glifo de renovação aparece. Uma só significa que as duas cotas
# estão sendo servidas pela mesma data; duas, que cada uma tem a sua.
count_renewals() {
  printf '%s' "$1" | grep -o "$RNW" | wc -l | tr -d ' '
}

count_locks() {
  printf '%s' "$1" | grep -o "$LOCK" | wc -l | tr -d ' '
}

# Cache com bloqueio previsto. Argumentos, em ordem: projeção e epoch de bloqueio
# do budget, os mesmos de requests, e o uso de requests. `null` para ausência.
write_blocked() {
  cat > "$JSON" <<EOF
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":24.3,"projected_percentage":${1:-130.0},
           "renewal_epoch":$RENEW,"blocked_epoch":${2:-$BLOCK}},
 "requests":{"percentage":${5:-14.0},"projected_percentage":${3:-null},
             "renewal_epoch":$RENEW,"blocked_epoch":${4:-null},"unlimited":false}}
EOF
}

# O cache guarda a linha pronta e é invalidado pelo mtime do JSON, cuja resolução
# é de um segundo: dois payloads escritos dentro do mesmo segundo colidiriam, e o
# segundo render devolveria a linha do primeiro. Quem renderiza duas vezes no
# mesmo teste limpa entre uma e outra.
drop_render_cache() {
  rm -f "$SL_CACHE_DIR"/flow-* 2>/dev/null || :
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

@test "a failure with no prior reading shows the warning alone" {
  # Antes isto renderizava vazio, e um Flow quebrado ficava indistinguível de um
  # Flow que ninguém configurou. O aviso sozinho é o único conteúdo honesto:
  # não há número anterior para mostrar.
  printf '{"ok":false,"message":"sem token"}' > "$JSON"
  quiet_config
  run widget_flow_render
  [[ "$output" == *"$WARN"* ]]
  [[ "$output" != *"$BUD"* ]]
  [[ "$output" != *"$SEP"* ]]
}

@test "the warning is painted red" {
  printf '{"ok":false,"message":"sem token"}' > "$JSON"
  quiet_config
  run widget_flow_render
  # Vermelho é o motivo de o glifo ser monocromático: emoji ignoram ANSI, e um
  # aviso que não consegue ficar vermelho não é aviso.
  [[ "$output" == *$'\033[31m'"$WARN"* ]]
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

# Payload real de uma conta com a cota de chamadas sem teto: a API manda
# `unlimited: true` E limite E contagem E percentual, tudo junto.
write_unlimited() {
  cat > "$JSON" <<'EOF'
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":24.30,"projected_percentage":92.33},
 "requests":{"percentage":13.96,"projected_percentage":null,"limit":5000,"unlimited":true}}
EOF
}

# Última leitura boa mais a marca de que a atualização falhou — o que o fetcher
# grava desde que parou de destruir o payload.
write_stale() {
  cat > "$JSON" <<'EOF'
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":24.30,"projected_percentage":92.33},
 "requests":{"percentage":61.4,"projected_percentage":71.2,"unlimited":false},
 "error":{"message":"sem token","at":1786243000}}
EOF
}

@test "an unlimited quota keeps its percentage" {
  # A API manda limite, contagem e percentual mesmo marcando unlimited. Esconder
  # tudo isso jogava fora dado verdadeiro; o teto ausente é dito pelo ∞ ao lado.
  write_unlimited
  quiet_config
  run widget_flow_render
  # Rótulo e percentual não são contíguos: o rótulo é esmaecido e o número
  # carrega a própria cor, com sequências de escape entre os dois.
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" == *"24%"* ]]
  [[ "$output" == *"$REQ"* ]]
  [[ "$output" == *"14%"* ]]
}

@test "an unlimited quota adds the infinity mark" {
  write_unlimited
  quiet_config
  run widget_flow_render
  [[ "$output" == *"$INF"* ]]
  [[ "$output" != *"$WARN"* ]]
}

@test "the infinity mark is dimmed, not coloured" {
  # Fato calmo, peso calmo: ele explica por que o percentual ao lado não vai
  # bloquear ninguém, e não compete com um aviso vermelho na mesma linha.
  write_unlimited
  quiet_config
  run widget_flow_render
  [[ "$output" == *$'\033[2m'"$INF"* ]]
}

@test "the infinity mark stays out when requests is filtered away" {
  # Filtrado para budget, o ∞ falaria de um número que não está na tela.
  write_unlimited
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [[ "$output" == *"$BUD"* ]]
  [[ "$output" != *"$INF"* ]]
}

@test "a stale reading keeps its numbers and adds the warning" {
  # O caso que importa: números de minutos atrás, mais o aviso de que não foi
  # possível atualizar. `⚠` significa "não consegui atualizar", não "não sei".
  write_stale
  quiet_config
  run widget_flow_render
  [[ "$output" == *"24%"* ]]
  [[ "$output" == *"61%"* ]]
  [[ "$output" == *"$WARN"* ]]
}

@test "a stale reading with no unlimited quota shows no infinity mark" {
  write_stale
  quiet_config
  run widget_flow_render
  [[ "$output" != *"$INF"* ]]
}

@test "both marks can share the status segment" {
  cat > "$JSON" <<'EOF'
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":24.30,"projected_percentage":92.33},
 "requests":{"percentage":13.96,"projected_percentage":null,"unlimited":true},
 "error":{"message":"sem token","at":1786243000}}
EOF
  quiet_config
  run widget_flow_render
  [[ "$output" == *"$INF"* ]]
  [[ "$output" == *"$WARN"* ]]
}

@test "icons off spells the status marks out" {
  write_unlimited
  no_icons_config
  run widget_flow_render
  [[ "$output" == *"unlimited"* ]]
  [[ "$output" != *"$INF"* ]]
}

@test "icons off spells the warning out" {
  write_stale
  no_icons_config
  run widget_flow_render
  [[ "$output" == *"offline"* ]]
  [[ "$output" != *"$WARN"* ]]
}

@test "a healthy limited quota renders no status segment" {
  # Nada a dizer, nada na tela: o terceiro segmento não pode virar decoração
  # permanente.
  write_cache
  quiet_config
  run widget_flow_render
  [[ "$output" != *"$INF"* ]]
  [[ "$output" != *"$WARN"* ]]
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

# ── Renovação ────────────────────────────────────────────────────────────────
#
# A data dá escala ao percentual: `24%` não diz se sobra um dia ou três semanas
# para gastar o resto. Onde ela mora depende de para quem ela decide alguma
# coisa, e é isso que os quatro primeiros testes fixam.
#
# As asserções de posição usam duas âncoras: `<n>% ⟳ ` prova de quem a data está
# ao lado, e `·20d` prova que a regressiva é a esperada. Separadas porque o
# carimbo entre elas depende do fuso da máquina, e o CI não roda no mesmo do
# desenvolvedor.

@test "shows the renewal right after the percentage" {
  write_renewal 24.3 92.33
  quiet_config
  run widget_flow_render
  [[ "$(sl_test_plain "$output")" == *"·20d"* ]]
  [[ "$(sl_test_plain "$output")" == *"92% $RNW "* ]]
}

@test "anchors the renewal to budget when only budget alerts" {
  write_renewal 24.3 92.33 14.0 null
  quiet_config
  run widget_flow_render
  [ "$(count_renewals "$output")" = "1" ]
  [[ "$(sl_test_plain "$output")" == *"92% $RNW "* ]]
}

@test "anchors the renewal to requests when only requests alerts" {
  write_renewal 24.3 null 88.0 110.0
  quiet_config
  run widget_flow_render
  [ "$(count_renewals "$output")" = "1" ]
  [[ "$(sl_test_plain "$output")" == *"110% $RNW "* ]]
}

@test "collapses the renewal when both quotas are calm" {
  write_renewal 24.3 null 14.0 null
  quiet_config
  run widget_flow_render
  [ "$(count_renewals "$output")" = "1" ]
  # Depois do separador, e não colada a nenhum dos dois números.
  [[ "$(sl_test_plain "$output")" == *"14% · $RNW "* ]]
}

@test "collapses the renewal when both quotas alert" {
  write_renewal 24.3 92.33 88.0 110.0
  quiet_config
  run widget_flow_render
  [ "$(count_renewals "$output")" = "1" ]
  [[ "$(sl_test_plain "$output")" == *"110% · $RNW "* ]]
}

@test "usage above the threshold alerts without any projection" {
  # 85% consumido com vinte dias pela frente é exatamente a pergunta que a data
  # responde, mesmo sem projeção nenhuma na tela.
  write_renewal 85.0 null 14.0 null
  quiet_config
  run widget_flow_render
  [ "$(count_renewals "$output")" = "1" ]
  [[ "$(sl_test_plain "$output")" == *"85% $RNW "* ]]
}

@test "different renewal dates stay in their own segments" {
  write_renewal 24.3 92.33 14.0 null "$RENEW" "$RENEW2"
  quiet_config
  run widget_flow_render
  [[ "$(sl_test_plain "$output")" == *"·25d"* ]]
  [ "$(count_renewals "$output")" = "2" ]
}

@test "a renewal on only one quota is not collapsed" {
  cat > "$JSON" <<EOF
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":24.3,"renewal_epoch":$RENEW},
 "requests":{"percentage":14.0,"unlimited":false}}
EOF
  quiet_config
  run widget_flow_render
  [ "$(count_renewals "$output")" = "1" ]
  [[ "$(sl_test_plain "$output")" == *"24% $RNW "* ]]
}

@test "a filtered metric keeps the renewal inside the segment" {
  # Com um segmento só em cena não há duplicação para resolver, então a data
  # nunca vira terceira faixa.
  write_renewal 24.3 null 14.0 null
  quiet_config_with '"metric":"budget"'
  run widget_flow_render
  [ "$(count_renewals "$output")" = "1" ]
  [[ "$(sl_test_plain "$output")" == *"24% $RNW "* ]]
}

# Os três testes abaixo afirmam uma AUSÊNCIA, e uma ausência passa sozinha
# quando o recurso inteiro está quebrado. Cada um renderiza duas vezes: uma no
# caso sob teste e outra no caso vizinho, onde a data precisa aparecer. Sem esse
# par eles continuariam verdes com a renovação nunca funcionando.
@test "renewal false drops the date entirely" {
  write_renewal 24.3 92.33
  quiet_config_with '"renewal":false'
  run widget_flow_render
  [[ "$output" != *"$RNW"* ]]
  quiet_config
  run widget_flow_render
  [[ "$output" == *"$RNW"* ]]
}

@test "a renewal already in the past disappears" {
  write_renewal 24.3 92.33 14.0 null 1799999000 1799999000
  quiet_config
  run widget_flow_render
  [[ "$output" != *"$RNW"* ]]
  drop_render_cache
  write_renewal 24.3 92.33
  run widget_flow_render
  [[ "$output" == *"$RNW"* ]]
}

@test "a payload without the renewal field renders as before" {
  write_cache
  quiet_config
  run widget_flow_render
  [[ "$output" != *"$RNW"* ]]
  [[ "$output" == *"$BUD"* ]]
  drop_render_cache
  write_renewal 24.3 92.33
  run widget_flow_render
  [[ "$output" == *"$RNW"* ]]
}

@test "icons off drops the mark but keeps the date" {
  write_renewal 24.3 92.33
  no_icons_config
  run widget_flow_render
  [[ "$output" != *"$RNW"* ]]
  # A regressiva sobrevive ao glifo, e serve de contraprova ao `!=` acima.
  [[ "$(sl_test_plain "$output")" == *"·20d"* ]]
}

# ── Previsão de bloqueio ─────────────────────────────────────────────────────
#
# O fetcher só grava `blocked_epoch` quando a projeção passa de 100%, então a
# presença do campo já é a condição — o widget não repete o limiar.

@test "a blocked epoch draws the lock" {
  write_blocked
  quiet_config
  run widget_flow_render
  [[ "$(sl_test_plain "$output")" == *"·5d"* ]]
  [[ "$output" == *"$LOCK"* ]]
}

@test "the lock comes before the renewal" {
  # Lidos na ordem, os dois carimbos contam a história inteira: trava quarta,
  # renova no dia 22. Invertidos, contariam ao contrário.
  write_blocked
  quiet_config
  run widget_flow_render
  [[ "$(sl_test_plain "$output")" == *"$LOCK"*"$RNW"* ]]
}

@test "the lock is painted red" {
  write_blocked
  quiet_config
  run widget_flow_render
  [[ "$output" == *"$(sl_color red)$LOCK"* ]]
}

@test "both quotas can carry their own lock" {
  write_blocked 130.0 "$BLOCK" 145.0 "$BLOCK2" 88.0
  quiet_config
  run widget_flow_render
  [[ "$(sl_test_plain "$output")" == *"·6d"* ]]
  [ "$(count_locks "$output")" = "2" ]
}

@test "renewal false keeps the lock" {
  # São perguntas diferentes: quem desliga a data de renovação não está dizendo
  # que aceita ser bloqueado sem aviso.
  write_blocked
  quiet_config_with '"renewal":false'
  run widget_flow_render
  [[ "$output" != *"$RNW"* ]]
  [[ "$output" == *"$LOCK"* ]]
}

@test "a blocked epoch already in the past drops the lock" {
  write_blocked 130.0 1799999000
  quiet_config
  run widget_flow_render
  [[ "$output" != *"$LOCK"* ]]
  drop_render_cache
  write_blocked
  run widget_flow_render
  [[ "$output" == *"$LOCK"* ]]
}

@test "a payload without blocked_epoch draws no lock" {
  write_renewal 24.3 92.33
  quiet_config
  run widget_flow_render
  [[ "$output" != *"$LOCK"* ]]
  drop_render_cache
  write_blocked
  run widget_flow_render
  [[ "$output" == *"$LOCK"* ]]
}

@test "icons off spells the lock out" {
  write_blocked
  no_icons_config
  run widget_flow_render
  [[ "$output" != *"$LOCK"* ]]
  [[ "$output" == *"blocked:"* ]]
}

@test "the shipped fetcher is executable" {
  [ -x "$PROJECT_ROOT/bin/flow-consumption.sh" ]
}

# Os três testes abaixo rodam o fetcher de verdade, sem rede: sem token ele
# aborta na verificação de credencial, muito antes de qualquer chamada HTTP.
# XDG_CACHE_HOME temporário mantém o cache real do usuário fora disso.
# O `|| :` é esperado, não tolerância: sem token o fetcher sai com status
# diferente de zero depois de gravar o arquivo, e é o arquivo que está sob
# teste.
run_fetcher_without_token() {
  env -u ANTHROPIC_AUTH_TOKEN XDG_CACHE_HOME="$BATS_TEST_TMPDIR/xdg" \
    bash "$PROJECT_ROOT/bin/flow-consumption.sh" || :
}

seed_good_payload() {
  mkdir -p "$BATS_TEST_TMPDIR/xdg"
  cat > "$BATS_TEST_TMPDIR/xdg/flow-consumption.json" <<'EOF'
{"ok":true,"fetched_at":1786240000,
 "budget":{"percentage":24.30,"projected_percentage":92.33},
 "requests":{"percentage":61.4,"projected_percentage":71.2,"unlimited":false}}
EOF
}

@test "a failed fetch preserves the last good reading" {
  # Uma sessão sem token zerava o widget a cada TTL. Um número de minutos atrás
  # é verdadeiro; apagá-lo não é mais honesto, é só menos útil.
  seed_good_payload
  run_fetcher_without_token
  saved="$BATS_TEST_TMPDIR/xdg/flow-consumption.json"
  [ "$(jq -r '.ok' "$saved")" = "true" ]
  [ "$(jq -r '.budget.percentage' "$saved")" = "24.30" ]
  [ "$(jq -r '.error.message' "$saved")" != "null" ]
  # fetched_at marca a idade do DADO, não da tentativa: quem falhou foi o
  # refresh, e o dado continua sendo o de antes.
  [ "$(jq -r '.fetched_at' "$saved")" = "1786240000" ]
}

@test "repeated failures do not stack error markers" {
  seed_good_payload
  run_fetcher_without_token
  run_fetcher_without_token
  saved="$BATS_TEST_TMPDIR/xdg/flow-consumption.json"
  [ "$(jq -r '.error | type' "$saved")" = "object" ]
  [ "$(jq -r '.fetched_at' "$saved")" = "1786240000" ]
  [ ! -f "$saved.tmp" ]
}

@test "a failed fetch with no prior reading falls back to the error payload" {
  run_fetcher_without_token
  saved="$BATS_TEST_TMPDIR/xdg/flow-consumption.json"
  [ "$(jq -r '.ok' "$saved")" = "false" ]
  [ "$(jq -r '.message' "$saved")" != "null" ]
}

@test "the shipped fetcher holds no hardcoded credential" {
  # Ele troca ANTHROPIC_AUTH_TOKEN por um token curto em runtime; nada de
  # segredo pode estar versionado junto.
  ! grep -qE '(client_secret|password|api_key) *= *["'"'"'][A-Za-z0-9]{8,}' \
    "$PROJECT_ROOT/bin/flow-consumption.sh"
}
