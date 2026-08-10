load helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  # sl_render_line consulta sl_config_widget_opt para a cor por widget;
  # sem config.sh carregado o teste falharia com "command not found".
  source "$PROJECT_ROOT/lib/config.sh"
  SL_CONFIG_RAW=""
  SL_CONFIG_SEP="|"
  w_a()     { printf 'A'; }
  w_b()     { printf 'B'; }
  w_empty() { return 0; }
  w_fail()  { return 1; }
  register_widget a --render w_a
  register_widget b --render w_b
  register_widget empty --render w_empty
  register_widget fail --render w_fail
}

@test "joins two widgets with the separator" {
  run sl_render_line a b
  [ "$output" = "A | B" ]
}

@test "empty widget leaves no orphan separator" {
  run sl_render_line a empty b
  [ "$output" = "A | B" ]
}

@test "empty widget at the edges leaves no dangling separator" {
  run sl_render_line empty a empty
  [ "$output" = "A" ]
}

@test "failing widget does not take down the line" {
  run sl_render_line a fail b
  [ "$output" = "A | B" ]
}

@test "unregistered widget is skipped" {
  run sl_render_line a nonexistent b
  [ "$output" = "A | B" ]
}

@test "line of only empty widgets renders empty" {
  run sl_render_line empty empty
  [ "$output" = "" ]
}

@test "applies the registered default colour" {
  register_widget coloured --render w_a --color cyan
  run sl_render_line coloured
  [ "$output" = "$(printf '\033[36mA\033[0m')" ]
}

@test "renders one line per configured line" {
  SL_JQ_OK=1
  SL_CONFIG_LINES="a b
a"
  run sl_render_all
  [ "$output" = "A | B
A" ]
}

@test "a line that renders empty is dropped entirely" {
  SL_JQ_OK=1
  SL_CONFIG_LINES="a
empty
a"
  run sl_render_all
  [ "$output" = "A
A" ]
}

@test "never renders an empty statusline" {
  # Sair vazio é indistinguível de plugin morto. Sempre sobra um sinal de vida.
  SL_JQ_OK=1
  SL_CONFIG_LINES="empty"
  run sl_render_all
  [ -n "$output" ]
}

@test "self-color widget is left untouched by the core" {
  w_self() { printf '\033[31mRED\033[0m'; }
  register_widget selfy --render w_self --color cyan --self-color
  run sl_render_line selfy
  [ "$output" = "$(printf '\033[31mRED\033[0m')" ]
}
