# Configuração do usuário.
#
# Um arquivo ilegível ou malformado nunca é reescrito: o usuário precisa poder
# consertar o próprio arquivo. A degradação acontece só em memória, sinalizada
# por SL_CONFIG_WARN para que a statusline mostre um marcador discreto.

SL_CONFIG_DEFAULT_LINES='model git
rate-forecast'
SL_CONFIG_DEFAULT_SEP='|'

sl_config_path() {
  printf '%s/claude-code-statusline/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

sl_config_load() {
  local path="${1:-$(sl_config_path)}" raw lines sep

  SL_CONFIG_WARN=""
  SL_CONFIG_RAW=""

  if [ ! -f "$path" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    return 0
  fi

  raw="$(cat "$path" 2>/dev/null)" || raw=""

  if ! printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    SL_CONFIG_WARN="config"
    return 0
  fi

  SL_CONFIG_RAW="$raw"

  lines="$(printf '%s' "$raw" | jq -r '.lines // [] | .[] | join(" ")' 2>/dev/null)" || lines=""
  sep="$(printf '%s' "$raw" | jq -r '.separator // "|"' 2>/dev/null)" || sep=""

  if [ -z "$lines" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_WARN="config"
  else
    SL_CONFIG_LINES="$lines"
  fi

  SL_CONFIG_SEP="${sep:-$SL_CONFIG_DEFAULT_SEP}"
  return 0
}

sl_config_widget_opt() {
  local widget="$1" key="$2" value
  [ -n "$SL_CONFIG_RAW" ] || return 0
  value="$(printf '%s' "$SL_CONFIG_RAW" \
    | jq -r --arg w "$widget" --arg k "$key" '.widgets[$w][$k] // empty' 2>/dev/null)" || value=""
  printf '%s' "$value"
}
