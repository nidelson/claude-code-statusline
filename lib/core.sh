# Registro de widgets.
#
# bash 3.2 não tem arrays associativos, então os atributos moram em variáveis
# cujo nome deriva do nome do widget: _W_RENDER_model, _W_COLOR_model. A leitura
# usa indireção `${!var}`, que dispensa eval.
# Hífen não é legal em nome de variável, então vira underscore.

SL_WIDGET_LIST=""

_sl_slug() {
  local name="$1"
  printf '%s' "${name//-/_}"
}

register_widget() {
  local name="$1"; shift
  local render="" color="" desc="" selfcolor=0 slug

  while [ $# -gt 0 ]; do
    case "$1" in
      --render)     render="$2";  shift 2 ;;
      --color)      color="$2";   shift 2 ;;
      --desc)       desc="$2";    shift 2 ;;
      --self-color) selfcolor=1;  shift   ;;
      *)            shift                 ;;
    esac
  done

  # Widget sem função de render é erro de programação no arquivo do widget.
  # Rejeita agora, em vez de falhar depois com um "command not found" obscuro
  # no meio de um repaint.
  if [ -z "$render" ]; then
    return 1
  fi

  slug="$(_sl_slug "$name")"
  eval "_W_RENDER_$slug=\$render"
  eval "_W_COLOR_$slug=\$color"
  eval "_W_DESC_$slug=\$desc"
  eval "_W_SELFCOLOR_$slug=\$selfcolor"
  SL_WIDGET_LIST="$SL_WIDGET_LIST $name"
  return 0
}

sl_widget_attr() {
  local attr="$1" name="$2" var
  var="_W_${attr}_$(_sl_slug "$name")"
  printf '%s' "${!var}"
}

sl_widget_registered() {
  local var="_W_RENDER_$(_sl_slug "$1")"
  [ -n "${!var}" ]
}
