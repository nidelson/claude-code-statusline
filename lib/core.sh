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

# ── Montagem de linhas ──
#
# Widget que renderiza vazio desaparece sem deixar separador órfão: o separador
# só é emitido antes de um segmento quando já havia algo escrito na linha.
#
# A captura usa command substitution, decidida por medição na Task 4 (3,5 ms
# por repaint contra a alternativa sem subshell, abaixo do limiar de 5 ms).
# Ver docs/superpowers/decisions/2026-08-08-canal-de-retorno.md.

sl_render_line() {
  local name fn color selfcolor out line="" sep

  sep=" ${SL_CONFIG_SEP:-|} "

  for name in "$@"; do
    sl_widget_registered "$name" || continue

    fn="$(sl_widget_attr RENDER "$name")"

    # Widget que falha vira widget vazio. O resto da linha sobrevive.
    out="$("$fn" 2>/dev/null)" || out=""

    [ -n "$out" ] || continue

    selfcolor="$(sl_widget_attr SELFCOLOR "$name")"
    if [ "$selfcolor" != "1" ]; then
      color="$(sl_config_widget_opt "$name" color)"
      [ -n "$color" ] || color="$(sl_widget_attr COLOR "$name")"
      if [ -n "$color" ]; then
        out="$(sl_color "$color")$out$SL_RESET"
      fi
    fi

    if [ -n "$line" ]; then
      line="$line$sep$out"
    else
      line="$out"
    fi
  done

  printf '%s' "$line"
}

sl_render_all() {
  local widgets out first=1
  while IFS= read -r widgets; do
    [ -n "$widgets" ] || continue
    out="$(sl_render_line $widgets)"
    [ -n "$out" ] || continue
    if [ "$first" = "1" ]; then first=0; else printf '\n'; fi
    printf '%s' "$out"
  done <<EOF
$SL_CONFIG_LINES
EOF
  printf '\n'
}
