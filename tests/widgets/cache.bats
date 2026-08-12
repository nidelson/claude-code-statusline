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
  [[ "$output" != *"cache:"* ]]
  [[ "$(sl_test_plain "$output")" == *"c:70%"* ]]
}

@test "an empty label drops the prefix entirely" {
  use_config '{"version":1,"icons":false,"lines":[["cache"]],"widgets":{"cache":{"label":""}}}'
  run widget_cache_render
  [[ "$output" != *"cache"* ]]
  [[ "$output" == *"70%"* ]]
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
  write_transcript \
    "$(turn 2027-01-15T07:00:00Z 0 500)" \
    "$(turn 2027-01-15T07:58:00Z 0 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 300" ]
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
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 0)"
  run _cache_probe
  [ "$output" = "" ]
  # Contraprova: a mesma sonda com uma gravação presente tem de responder.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe gives nothing when the transcript is missing" {
  SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run _cache_probe
  [ "$output" = "" ]
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe gives nothing when the transcript path is empty" {
  SL_TRANSCRIPT=""
  run _cache_probe
  [ "$output" = "" ]
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
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
  [[ "$output" == *$'\033[32m'*"3m1s"* ]]
}

@test "the countdown turns yellow under three minutes" {
  # 07:57:59Z + 300s deixa 179s.
  write_transcript "$(turn 2027-01-15T07:57:59Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[33m'*"2m59s"* ]]
}

@test "the countdown turns red under one minute" {
  # 07:55:59Z + 300s deixa 59s.
  write_transcript "$(turn 2027-01-15T07:55:59Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[31m'*"59s"* ]]
}

@test "a cold cache is red" {
  write_transcript "$(turn 2027-01-15T07:50:00Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[31m'*"cold"* ]]
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
  SL_TRANSCRIPT=""
  run widget_cache_render
  [ "$output" = "" ]
  # Contraprova: com o transcript de volta, o widget tem de reaparecer.
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 3m" ]
}

@test "the glyph carries a space" {
  # ☁ tem largura ambígua em Unicode: colado num dígito disputa a mesma célula
  # em boa parte dos terminais. Mesmo motivo do ⟳ em sl_stamp_label.
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == "☁ "* ]]
}
