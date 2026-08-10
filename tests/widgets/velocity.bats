load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/velocity.sh"
  SL_CONFIG_RAW=""
  SL_LINES_ADDED=10
  SL_LINES_REMOVED=2
}

@test "registers itself on load" {
  sl_widget_registered velocity
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR velocity)" = "1" ]
}

@test "shows both counts" {
  run widget_velocity_render
  [[ "$output" == *"+10"* ]]
  [[ "$output" == *"-2"* ]]
}

@test "paints the added lines green" {
  run widget_velocity_render
  [[ "$output" == *$'\033[32m'*"+10"* ]]
}

@test "paints the removed lines red" {
  run widget_velocity_render
  [[ "$output" == *$'\033[31m'*"-2"* ]]
}

@test "renders nothing when no line changed" {
  # +0 -0 numa sessão que só leu código é ruído permanente: diz "nada
  # aconteceu", que é o mesmo que não dizer nada.
  SL_LINES_ADDED=0
  SL_LINES_REMOVED=0
  run widget_velocity_render
  [ "$output" = "" ]
}

@test "omits the removed count when it is zero" {
  SL_LINES_REMOVED=0
  run widget_velocity_render
  [[ "$output" == *"+10"* ]]
  [[ "$output" != *"-0"* ]]
}

@test "omits the added count when it is zero" {
  SL_LINES_ADDED=0
  run widget_velocity_render
  [[ "$output" == *"-2"* ]]
  [[ "$output" != *"+0"* ]]
}

@test "treats a missing value as zero" {
  SL_LINES_REMOVED=""
  run widget_velocity_render
  [[ "$output" == *"+10"* ]]
  [[ "$output" != *"-"* ]]
}

@test "treats a non-numeric value as zero" {
  SL_LINES_ADDED="many"
  run widget_velocity_render
  [[ "$output" == *"-2"* ]]
  [[ "$output" != *"+"* ]]
}

@test "renders nothing when both values are unusable" {
  SL_LINES_ADDED=""
  SL_LINES_REMOVED="oops"
  run widget_velocity_render
  [ "$output" = "" ]
}

@test "handles large counts without separators" {
  # Contagem de linhas é para ser lida como número exato, não arredondada:
  # "+1.2k" esconde a diferença entre 1200 e 1249 num contexto onde ela importa.
  SL_LINES_ADDED=12345
  run widget_velocity_render
  [[ "$output" == *"+12345"* ]]
}

@test "returns zero even when it renders nothing" {
  # Um chamador com `set -e` não pode ser derrubado por um widget que apenas
  # não tem o que dizer.
  SL_LINES_ADDED=0
  SL_LINES_REMOVED=0
  widget_velocity_render >/dev/null
}

@test "returns zero when it renders something" {
  widget_velocity_render >/dev/null
}
