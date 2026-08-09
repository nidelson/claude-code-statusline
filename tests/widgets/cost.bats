load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/cost.sh"
  SL_CONFIG_RAW=""
  SL_COST="0.0234"
}

use_config() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
}

@test "registers itself on load" {
  sl_widget_registered cost
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR cost)" = "1" ]
}

@test "formats with two decimals" {
  run widget_cost_render
  [[ "$output" == *'$0.02'* ]]
}

@test "formats a large amount" {
  SL_COST="253.4912"
  run widget_cost_render
  [[ "$output" == *'$253.49'* ]]
}

@test "zero renders as an amount, not as absence" {
  # Zero é informação: "ainda não gastei nada". Sumir seria dizer "não sei".
  SL_COST="0"
  run widget_cost_render
  [[ "$output" == *'$0.00'* ]]
}

@test "renders nothing when the cost is not a number" {
  SL_COST="lots"
  run widget_cost_render
  [ "$output" = "" ]
}

@test "renders nothing when the cost is empty" {
  SL_COST=""
  run widget_cost_render
  [ "$output" = "" ]
}

@test "never writes to stderr" {
  # printf com número inválido reclama no stderr. Uma statusline que suja o
  # terminal é pior que uma statusline incompleta.
  SL_COST="lots"
  err="$(widget_cost_render 2>&1 1>/dev/null)"
  [ -z "$err" ]
}

@test "handles scientific notation from jq" {
  # jq emite 1e-07 para valores muito pequenos, comuns no início da sessão.
  SL_COST="1e-07"
  run widget_cost_render
  [[ "$output" == *'$0.00'* ]]
}

@test "defaults to yellow" {
  run widget_cost_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "honours the configured colour when no threshold is set" {
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"color":"cyan"}}}'
  run widget_cost_render
  [[ "$output" == *$'\033[36m'* ]]
}

@test "paints yellow at the warn threshold" {
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"color":"cyan","warn":0.02}}}'
  run widget_cost_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "keeps the configured colour below the warn threshold" {
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"color":"cyan","warn":5}}}'
  run widget_cost_render
  [[ "$output" == *$'\033[36m'* ]]
}

@test "paints red at the crit threshold" {
  SL_COST="12.50"
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"warn":5,"crit":10}}}'
  run widget_cost_render
  [[ "$output" == *$'\033[31m'* ]]
}

@test "crit wins over warn" {
  SL_COST="12.50"
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"warn":5,"crit":10}}}'
  run widget_cost_render
  [[ "$output" != *$'\033[33m'* ]]
}

@test "an unparseable threshold is ignored rather than fatal" {
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"warn":"muito"}}}'
  run widget_cost_render
  [[ "$output" == *'$0.02'* ]]
}

@test "formats correctly under a comma decimal locale" {
  # Em pt_BR o separador decimal é vírgula, e o printf do bash passa a rejeitar
  # "0.0234" como número inválido: sai "$0,00" mais ruído no stderr. O widget
  # precisa fixar LC_ALL=C ao formatar.
  locale -a 2>/dev/null | grep -qi '^pt_BR' || skip "pt_BR locale not installed"
  export LC_ALL=pt_BR.UTF-8
  run widget_cost_render
  [[ "$output" == *'$0.02'* ]]
}

@test "goes green below the warn threshold when no colour is set" {
  # Com limites configurados o widget vira semáforo. Se o piso continuasse
  # amarelo, cruzar o `warn` pintaria de amarelo algo que já era amarelo, e o
  # aviso seria invisível.
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"warn":5,"crit":10}}}'
  SL_COST="3.50"
  run widget_cost_render
  [[ "$output" == *$'\033[32m'* ]]
}

@test "stays yellow with no thresholds at all" {
  use_config '{"version":1,"lines":[["cost"]]}'
  SL_COST="3.50"
  run widget_cost_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "a crit threshold alone still greens the floor" {
  use_config '{"version":1,"lines":[["cost"]],"widgets":{"cost":{"crit":10}}}'
  SL_COST="3.50"
  run widget_cost_render
  [[ "$output" == *$'\033[32m'* ]]
}
