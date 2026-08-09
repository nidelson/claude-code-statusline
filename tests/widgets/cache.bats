load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/cache.sh"
  SL_CONFIG_RAW=""
  SL_CACHE_READ=700
  SL_CACHE_CREATE=200
  SL_INPUT_TOKENS=100
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

@test "labels the number" {
  # Três percentuais podem dividir a mesma linha — contexto, rate limit e este.
  # Sem rótulo não há como saber qual é qual.
  run widget_cache_render
  [[ "$output" == *"cache:"* ]]
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

@test "the label option replaces the prefix" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"label":"c:"}}}'
  run widget_cache_render
  [[ "$output" == *"c:70%"* ]]
  [[ "$output" != *"cache:"* ]]
}

@test "an empty label drops the prefix entirely" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"label":""}}}'
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
