# Widget registry.
#
# bash 3.2 has no associative arrays, so attributes live in variables whose
# names are derived from the widget name: _W_RENDER_model, _W_COLOR_model.
# Reads go through `${!var}` indirection, which needs no eval.
# Hyphens are not legal in variable names, so they become underscores.

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

  # A widget with no render function is a programming error in that widget
  # file. Reject it rather than failing later with an obscure "command not
  # found" in the middle of a repaint.
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
