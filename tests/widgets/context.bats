load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/context.sh"
  SL_CONFIG_RAW=""
  SL_CTX_SIZE=200000
  SL_CTX_USED=45000
}

# Conta células da barra pelo glifo. O bats força LC_ALL=C, então ${#var}
# contaria bytes e não caracteres; grep -o casa a sequência de bytes exata.
count_glyph() {
  printf '%s' "$1" | grep -o "$2" | wc -l | tr -d ' '
}

use_config() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
}

@test "registers itself on load" {
  sl_widget_registered context
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR context)" = "1" ]
}

@test "renders nothing without a context window size" {
  SL_CTX_SIZE=0
  run widget_context_render
  [ "$output" = "" ]
}

@test "renders nothing when the size is not a number" {
  SL_CTX_SIZE="lots"
  run widget_context_render
  [ "$output" = "" ]
}

@test "shows the percentage used" {
  # 45000/200000 = 22,5%, arredondado para 23.
  run widget_context_render
  [[ "$output" == *"23%"* ]]
}

@test "rounds the percentage to the nearest integer" {
  SL_CTX_USED=1
  run widget_context_render
  [[ "$output" == *"0%"* ]]
}

@test "shows the token counts" {
  run widget_context_render
  [[ "$output" == *"(45k/200k)"* ]]
}

@test "formats a million tokens with one decimal" {
  SL_CTX_SIZE=1000000
  SL_CTX_USED=690000
  run widget_context_render
  [[ "$output" == *"(690k/1.0M)"* ]]
}

@test "the tokens option hides the counts" {
  use_config '{"version":1,"lines":[["context"]],"widgets":{"context":{"tokens":false}}}'
  run widget_context_render
  [[ "$output" != *"45k"* ]]
  [[ "$output" == *"23%"* ]]
}

@test "a full window fills every cell" {
  use_config '{"version":1,"lines":[["context"]],"widgets":{"context":{"width":10}}}'
  SL_CTX_USED=200000
  run widget_context_render
  [ "$(count_glyph "$output" '█')" = "10" ]
}

@test "an empty window fills no cell" {
  use_config '{"version":1,"lines":[["context"]],"widgets":{"context":{"width":10}}}'
  SL_CTX_USED=0
  run widget_context_render
  [ "$(count_glyph "$output" '█')" = "0" ]
  [ "$(count_glyph "$output" '░')" = "10" ]
}

@test "the bar always has exactly the configured width" {
  # Um bloco parcial ocupa uma célula como qualquer outra: cheios + parcial +
  # trilho tem de somar a largura, senão a barra dança de tamanho conforme a
  # sessão enche.
  use_config '{"version":1,"lines":[["context"]],"widgets":{"context":{"width":10}}}'
  SL_CTX_USED=45000
  run widget_context_render
  full="$(count_glyph "$output" '█')"
  track="$(count_glyph "$output" '░')"
  partial=0
  for g in '▏' '▎' '▍' '▌' '▋' '▊' '▉'; do
    partial=$(( partial + $(count_glyph "$output" "$g") ))
  done
  [ "$(( full + track + partial ))" = "10" ]
}

@test "an invalid width falls back to the default" {
  use_config '{"version":1,"lines":[["context"]],"widgets":{"context":{"width":"wide"}}}'
  SL_CTX_USED=200000
  run widget_context_render
  [ "$(count_glyph "$output" '█')" = "20" ]
}

@test "a width of one still renders" {
  use_config '{"version":1,"lines":[["context"]],"widgets":{"context":{"width":1}}}'
  SL_CTX_USED=200000
  run widget_context_render
  [ "$(count_glyph "$output" '█')" = "1" ]
}

@test "paints the percentage green below seventy" {
  SL_CTX_USED=100000
  run widget_context_render
  [[ "$output" == *$'\033[32m'* ]]
}

@test "paints the percentage yellow from seventy" {
  SL_CTX_USED=140000
  run widget_context_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "paints the percentage red from ninety" {
  SL_CTX_USED=180000
  run widget_context_render
  [[ "$output" == *$'\033[31m'* ]]
}

@test "usage beyond the window does not overflow the bar" {
  # A janela pode ser estourada por uma troca única grande; a barra não pode
  # crescer além da largura por causa disso.
  use_config '{"version":1,"lines":[["context"]],"widgets":{"context":{"width":10}}}'
  SL_CTX_USED=400000
  run widget_context_render
  [ "$(count_glyph "$output" '█')" = "10" ]
}
