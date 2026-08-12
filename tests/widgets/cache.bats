load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/timefmt.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/widgets/cache.sh"
  SL_CONFIG_RAW=""
  SL_CACHE_READ=700
  SL_CACHE_CREATE=200
  SL_INPUT_TOKENS=100
  SL_TRANSCRIPT=""
  # O cache em disco não pode sair do diretório do teste.
  SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  # Relógio fixo. 1800000000 é 2027-01-15T08:00:00Z.
  SL_NOW=1800000000
  SL_T_N=0
}

# Escreve um transcript e aponta SL_TRANSCRIPT para ele.
#
# Cada chamada usa um nome novo. O cache_by_mtime tem resolução de um segundo,
# então dois transcritos diferentes escritos no mesmo segundo sobre o mesmo
# caminho colidiriam — e a chave do cache é derivada do caminho.
write_transcript() {
  SL_T_N=$(( SL_T_N + 1 ))
  SL_TRANSCRIPT="$BATS_TEST_TMPDIR/tr$SL_T_N.jsonl"
  printf '%s\n' "$@" > "$SL_TRANSCRIPT"
}

# Uma entrada de assistant: carimbo, gravação de 1h, gravação de 5m.
turn() {
  printf '{"type":"assistant","message":{"usage":{"cache_read_input_tokens":100,"cache_creation_input_tokens":%d,"cache_creation":{"ephemeral_1h_input_tokens":%d,"ephemeral_5m_input_tokens":%d}}},"timestamp":"%s"}' \
    "$(( $2 + $3 ))" "$2" "$3" "$1"
}

use_config() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
}

@test "registers itself on load" {
  sl_widget_registered cache
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR cache)" = "1" ]
}

@test "shows the hit rate over all three counters" {
  # 700 / (700 + 200 + 100) = 70%
  run widget_cache_render
  [[ "$output" == *"70%"* ]]
}

@test "marks the number with the cloud glyph" {
  # Três percentuais podem dividir a mesma linha — contexto, rate limit e este.
  # Sem marca não há como saber qual é qual.
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"☁"* ]]
}

@test "renders nothing when every counter is zero" {
  # Início de sessão, ou current_usage null entre trocas. Uma taxa de acerto
  # sobre zero token não é 0%, é indefinida.
  SL_CACHE_READ=0
  SL_CACHE_CREATE=0
  SL_INPUT_TOKENS=0
  run widget_cache_render
  [ "$output" = "" ]
}

@test "renders nothing when the counters are missing" {
  SL_CACHE_READ=""
  SL_CACHE_CREATE=""
  SL_INPUT_TOKENS=""
  run widget_cache_render
  [ "$output" = "" ]
}

@test "treats a non-numeric counter as zero" {
  SL_CACHE_CREATE="lots"
  run widget_cache_render
  [[ "$output" == *"88%"* ]]
}

@test "rounds to the nearest integer" {
  # 2 / 3 = 66,67% arredonda para 67.
  SL_CACHE_READ=2
  SL_CACHE_CREATE=1
  SL_INPUT_TOKENS=0
  run widget_cache_render
  [[ "$output" == *"67%"* ]]
}

@test "paints green from seventy" {
  run widget_cache_render
  [[ "$output" == *$'\033[32m'* ]]
}

@test "paints yellow from thirty" {
  SL_CACHE_READ=400
  SL_CACHE_CREATE=400
  SL_INPUT_TOKENS=200
  run widget_cache_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "paints red below thirty" {
  SL_CACHE_READ=100
  SL_CACHE_CREATE=400
  SL_INPUT_TOKENS=500
  run widget_cache_render
  [[ "$output" == *$'\033[31m'* ]]
}

@test "a full cache hit reads as one hundred" {
  SL_CACHE_CREATE=0
  SL_INPUT_TOKENS=0
  run widget_cache_render
  [[ "$output" == *"100%"* ]]
}

@test "the label option replaces the prefix when icons are off" {
  use_config '{"version":1,"icons":false,"lines":[["cache"]],"widgets":{"cache":{"label":"c:"}}}'
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"c:70%"* ]]
  [[ "$output" != *"cache:"* ]]
}

@test "an empty label drops the prefix entirely" {
  use_config '{"version":1,"icons":false,"lines":[["cache"]],"widgets":{"cache":{"label":""}}}'
  run widget_cache_render
  [[ "$output" == *"70%"* ]]
  [[ "$output" != *"cache"* ]]
}

@test "returns zero when it renders nothing" {
  SL_CACHE_READ=0
  SL_CACHE_CREATE=0
  SL_INPUT_TOKENS=0
  widget_cache_render >/dev/null
}

@test "the probe reads timestamp and one hour ttl" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe reads a five minute ttl" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 300" ]
}

@test "the probe takes the timestamp from the last turn" {
  write_transcript \
    "$(turn 2027-01-15T07:00:00Z 500 0)" \
    "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe takes the ttl from the last turn that wrote" {
  # A última troca foi servida inteira do cache e não gravou nada, então não
  # identifica a janela; quem identifica é a anterior.
  #
  # A anterior grava em 1h de propósito: com 5m aqui, o teste passaria também
  # com o filtro de gravação quebrado, porque uma entrada sem gravação nenhuma
  # também tem ephemeral_1h zerado e cairia em 300 pelo caminho errado.
  write_transcript \
    "$(turn 2027-01-15T07:00:00Z 500 0)" \
    "$(turn 2027-01-15T07:58:00Z 0 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe ignores lines that are not assistant turns" {
  write_transcript \
    "$(turn 2027-01-15T07:00:00Z 500 0)" \
    '{"type":"user","timestamp":"2027-01-15T09:00:00Z"}' \
    '{"type":"attachment","timestamp":"2027-01-15T09:00:00Z"}'
  run _cache_probe
  [ "$output" = "2027-01-15T07:00:00Z 3600" ]
}

@test "the probe survives a truncated last line" {
  # O transcript da sessão em curso está sendo escrito enquanto se lê.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  printf '{"type":"assis' >> "$SL_TRANSCRIPT"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe gives nothing when no turn ever wrote" {
  # Contraprova primeiro: a mesma sonda com uma gravação presente responde.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 0)"
  run _cache_probe
  [ "$output" = "" ]
}

@test "the probe gives nothing when the transcript is missing" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
  SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run _cache_probe
  [ "$output" = "" ]
}

@test "the probe gives nothing when the transcript path is empty" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
  SL_TRANSCRIPT=""
  run _cache_probe
  [ "$output" = "" ]
}

@test "the clock comes from SL_NOW when it is set" {
  SL_NOW=1234567890
  run _cache_now
  [ "$output" = "1234567890" ]
}

@test "shows the countdown next to the hit rate" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%·3m" ]
}

@test "the countdown carries seconds" {
  # 07:57:48Z + 300s expira 08:02:48Z; faltam 168s = 2m48s.
  write_transcript "$(turn 2027-01-15T07:57:48Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·2m48s"* ]]
}

@test "a one hour ttl counts from the same stamp" {
  # 07:58:00Z + 3600s expira 08:58:00Z; faltam 3480s = 58m.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
}

@test "an expired cache reads as cold" {
  # 07:50:00Z + 300s expirou às 07:55:00Z, cinco minutos atrás.
  write_transcript "$(turn 2027-01-15T07:50:00Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·cold"* ]]
}

@test "the countdown is green with more than three minutes left" {
  # 07:58:01Z + 300s deixa 181s.
  write_transcript "$(turn 2027-01-15T07:58:01Z 0 500)"
  run widget_cache_render
    # A cor tem de estar COLADA ao texto. Com *cor*texto* o teste passaria pela
  # cor do percentual, que ocupa a mesma linha e muda junto — foi assim que uma
  # sabotagem do limiar do alarme não derrubou nada.
  [[ "$output" == *$'\033[32m'"3m1s"* ]]
}

@test "the countdown turns yellow under three minutes" {
  # 07:57:59Z + 300s deixa 179s.
  write_transcript "$(turn 2027-01-15T07:57:59Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[33m'"2m59s"* ]]
}

@test "the countdown turns red under one minute" {
  # 07:55:59Z + 300s deixa 59s.
  write_transcript "$(turn 2027-01-15T07:55:59Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[31m'"59s"* ]]
}

@test "a cache expiring this very second is already cold" {
  # 07:55:00Z + 300s expira 08:00:00Z, que é agora: restam exatamente zero
  # segundos. O limite é fechado — quem chegou a zero já não serve.
  # Contraprova primeiro: um segundo antes ainda há tempo, e o texto é outro.
  # A ordem não é estilo — no bash 3.2 só a última asserção de cada teste é
  # cobrada, então a que está sob teste tem de ser a última.
  write_transcript "$(turn 2027-01-15T07:55:01Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·1s"* ]]
  write_transcript "$(turn 2027-01-15T07:55:00Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·cold"* ]]
}

@test "a cold cache is red" {
  write_transcript "$(turn 2027-01-15T07:50:00Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[31m'"cold"* ]]
}

@test "the countdown survives without a hit rate" {
  # current_usage vem null entre trocas — e é justamente parado, entre trocas,
  # que o countdown decide alguma coisa.
  SL_CACHE_READ=0
  SL_CACHE_CREATE=0
  SL_INPUT_TOKENS=0
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 3m" ]
}

@test "the hit rate survives without a countdown" {
  SL_TRANSCRIPT=""
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%" ]
}

@test "renders nothing when neither side has anything to say" {
  SL_CACHE_READ=0
  SL_CACHE_CREATE=0
  SL_INPUT_TOKENS=0
  # Contraprova primeiro: com transcript, o widget aparece só com o tempo.
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 3m" ]
  SL_TRANSCRIPT=""
  run widget_cache_render
  [ "$output" = "" ]
}

@test "the glyph carries a space" {
  # ☁ tem largura ambígua em Unicode: colado num dígito disputa a mesma célula
  # em boa parte dos terminais. Mesmo motivo do ⟳ em sl_stamp_label.
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == "☁ "* ]]
}

@test "the countdown shows by default" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
}

@test "countdown off drops the countdown and keeps the rate" {
  # Contraprova primeiro: sem a opção, este transcript traz o tempo.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"off"}}}'
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%" ]
}

@test "countdown near hides the countdown while there is time" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"near"}}}'
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%" ]
}

@test "countdown near shows the countdown under three minutes" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"near"}}}'
  write_transcript "$(turn 2027-01-15T07:57:59Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·2m59s"* ]]
}

@test "countdown near still shows a cold cache" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"near"}}}'
  write_transcript "$(turn 2027-01-15T07:50:00Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·cold"* ]]
}

@test "an unknown countdown value behaves as always" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"talvez"}}}'
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
}

@test "a routine write raises no alarm" {
  # Contraprova primeiro: uma gravação grande tem de acender.
  SL_CACHE_CREATE=54000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲54k"* ]]
  # 699 é a mediana medida em produção. Nada deve aparecer.
  SL_CACHE_CREATE=699
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
}

@test "the alarm fires from ten thousand" {
  SL_CACHE_CREATE=9999
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
  SL_CACHE_CREATE=10000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲10k"* ]]
}

@test "the alarm is yellow between ten and fifty thousand" {
  SL_CACHE_CREATE=20000
  run widget_cache_render
  [[ "$output" == *$'\033[33m'"▲20k"* ]]
}

@test "the alarm turns red from fifty thousand" {
  SL_CACHE_CREATE=49999
  run widget_cache_render
  [[ "$output" == *$'\033[33m'"▲50k"* ]]
  SL_CACHE_CREATE=50000
  run widget_cache_render
  [[ "$output" == *$'\033[31m'"▲50k"* ]]
}

@test "the alarm abbreviates millions" {
  SL_CACHE_CREATE=1250000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲1.2M"* ]]
}

@test "the alarm sits after the countdown" {
  SL_CACHE_CREATE=54000
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 1%·58m ▲54k" ]
}

@test "the alarm shows without a countdown" {
  SL_CACHE_CREATE=54000
  SL_TRANSCRIPT=""
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 1% ▲54k" ]
}

@test "the write option turns the alarm off" {
  SL_CACHE_CREATE=54000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲54k"* ]]
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"write":false}}}'
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
}

@test "the alarm falls back to a label when icons are off" {
  SL_CACHE_CREATE=54000
  use_config '{"version":1,"icons":false,"lines":[["cache"]],"widgets":{"cache":{}}}'
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
  [[ "$(sl_test_plain "$output")" == *"w:54k"* ]]
}
