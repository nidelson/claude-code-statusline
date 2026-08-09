# Nome do modelo ativo.
#
# A cor é semântica — identifica a família do modelo, não uma preferência do
# usuário — então o widget é --self-color e pinta a si mesmo. Modelos da
# Anthropic saem no coral da marca; qualquer outro provedor sai em magenta, o
# que torna óbvio num relance que a sessão não está num modelo Claude.

register_widget model \
  --render widget_model_render \
  --self-color \
  --desc   "Active model name"

widget_model_render() {
  local needle

  [ -n "$SL_MODEL" ] || return 0
  # "Unknown" é o fallback do parser quando o campo não veio; mostrar isso na
  # statusline é pior que não mostrar nada.
  [ "$SL_MODEL" = "Unknown" ] && return 0

  # O id é mais confiável que o nome de exibição para identificar a família,
  # mas nem todo cliente o envia — daí o fallback.
  needle="$(printf '%s' "${SL_MODEL_ID:-$SL_MODEL}" | tr '[:upper:]' '[:lower:]')"

  case "$needle" in
    claude*|*anthropic*|*opus*|*sonnet*|*haiku*|*fable*)
      printf '%s%s%s' "$SL_BRAND" "$SL_MODEL" "$SL_RESET" ;;
    *)
      printf '%s%s%s' "$(sl_color magenta)" "$SL_MODEL" "$SL_RESET" ;;
  esac
}
