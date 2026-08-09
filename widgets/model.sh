# Nome do modelo ativo.

register_widget model \
  --render widget_model_render \
  --color  cyan \
  --desc   "Active model name"

widget_model_render() {
  [ -n "$SL_MODEL" ] || return 0
  # "Unknown" é o fallback do parser quando o campo não veio; mostrar isso na
  # statusline é pior que não mostrar nada.
  [ "$SL_MODEL" = "Unknown" ] && return 0
  printf '%s' "$SL_MODEL"
}
