load helper

setup() {
  source "$PROJECT_ROOT/lib/core.sh"
}

@test "registers and retrieves the render function name" {
  register_widget model --render widget_model_render --color cyan
  [ "$(sl_widget_attr RENDER model)" = "widget_model_render" ]
  [ "$(sl_widget_attr COLOR model)" = "cyan" ]
}

@test "accepts a hyphenated widget name" {
  register_widget rate-forecast --render widget_rf_render
  [ "$(sl_widget_attr RENDER rate-forecast)" = "widget_rf_render" ]
}

@test "flags self-color widgets" {
  register_widget a --render fn_a --self-color
  register_widget b --render fn_b
  [ "$(sl_widget_attr SELFCOLOR a)" = "1" ]
  [ "$(sl_widget_attr SELFCOLOR b)" = "0" ]
}

@test "recognises registered widgets and rejects unknown ones" {
  register_widget model --render fn
  sl_widget_registered model
  ! sl_widget_registered nonexistent
}

@test "accumulates registered names in the list" {
  register_widget a --render fa
  register_widget b --render fb
  [ "$SL_WIDGET_LIST" = " a b" ]
}

@test "rejects registration without --render" {
  ! register_widget broken --color red
  ! sl_widget_registered broken
}

@test "sl_jq strips the carriage returns the Windows jq emits" {
  # O jq de verdade não emite `\r` fora do Windows, então quem finge ser ele é
  # uma função local — é o filtro que está sob teste, não o jq.
  jq() { printf 'Opus 5\r\n'; }

  # A contraprova — sem o filtro, o `\r` sobrevive — só vale onde a plataforma
  # não mexe em CRLF por conta própria. Sob Git Bash a camada de texto do MSYS
  # pode comer o par na própria captura, e aí a asserção falha dizendo algo
  # sobre o MSYS e nada sobre sl_jq. Medido: era assim que este teste quebrava
  # no runner windows-latest enquanto a asserção de baixo passava.
  case "$OSTYPE" in
    msys*|cygwin*|win32*) ;;
    *)
      SL_JQ_CRLF=0
      [ "$(sl_jq -r .x)" = "$(printf 'Opus 5\r')" ]
      ;;
  esac

  SL_JQ_CRLF=1
  [ "$(sl_jq -r .x)" = "Opus 5" ]
}

@test "sl_jq reports the status of jq and not of the filter" {
  # lib/config.sh valida a configuração com `jq -e .`. Se o status do `tr`
  # vazasse no lugar do status do jq, qualquer lixo passaria por JSON válido.
  SL_JQ_CRLF=0
  run sl_jq -e . <<< 'isto nao e json'
  [ "$status" -ne 0 ]
  SL_JQ_CRLF=1
  run sl_jq -e . <<< 'isto nao e json'
  [ "$status" -ne 0 ]
}
