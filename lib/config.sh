# Configuração do usuário.
#
# Um arquivo ilegível ou malformado nunca é reescrito: o usuário precisa poder
# consertar o próprio arquivo. A degradação acontece só em memória, sinalizada
# por SL_CONFIG_WARN para que a statusline mostre um marcador discreto.

# Mantenha em sincronia com o Passo 5 de commands/setup.md, que escreve este
# mesmo conjunto no arquivo do usuário. São dois caminhos para o mesmo default —
# quem roda o /setup recebe um arquivo, quem só aponta o statusLine.command para
# o entrypoint cai aqui — e vê-los divergir seria descobrir que a statusline
# muda conforme como foi instalada.
#
# As opções por widget não cabem aqui: este fallback é uma lista de linhas, não
# um JSON. Quem chega por este caminho recebe os widgets nos padrões deles, o
# que é a degradação certa — sem arquivo, não há preferência a respeitar.
SL_CONFIG_DEFAULT_LINES='repo branch git-status worktree velocity cache model cost flow
context rate-forecast sprint'
SL_CONFIG_DEFAULT_SEP='|'
# Ícones ligados por padrão. Os glifos usados são Unicode padrão (✻, ◆), não
# Nerd Font — renderizam em qualquer terminal moderno sem exigir fonte extra.
SL_CONFIG_DEFAULT_ICONS='1'

sl_config_path() {
  printf '%s/claude-code-statusline/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

sl_config_load() {
  local path="${1:-$(sl_config_path)}" raw lines sep icons

  SL_CONFIG_WARN=""
  SL_CONFIG_RAW=""

  if [ ! -f "$path" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    SL_CONFIG_ICONS="$SL_CONFIG_DEFAULT_ICONS"
    return 0
  fi

  raw="$(cat "$path" 2>/dev/null)" || raw=""

  if ! printf '%s' "$raw" | sl_jq -e . >/dev/null 2>&1; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    SL_CONFIG_ICONS="$SL_CONFIG_DEFAULT_ICONS"
    SL_CONFIG_WARN="config"
    return 0
  fi

  SL_CONFIG_RAW="$raw"

  lines="$(printf '%s' "$raw" | sl_jq -r '.lines // [] | .[] | join(" ")' 2>/dev/null)" || lines=""
  sep="$(printf '%s' "$raw" | sl_jq -r '.separator // "|"' 2>/dev/null)" || sep=""
  # jq devolve "1"/"0" para o booleano; ausente vira o default.
  icons="$(printf '%s' "$raw" | sl_jq -r 'if .icons == null then empty elif .icons then "1" else "0" end' 2>/dev/null)" || icons=""
  SL_CONFIG_ICONS="${icons:-$SL_CONFIG_DEFAULT_ICONS}"

  if [ -z "$lines" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_WARN="config"
  else
    SL_CONFIG_LINES="$lines"
  fi

  SL_CONFIG_SEP="${sep:-$SL_CONFIG_DEFAULT_SEP}"
  return 0
}

# `// empty` seria o idioma óbvio aqui, e está errado: em jq o `//` cai para o
# lado direito tanto em null quanto em false, então `"tokens": false` voltaria
# vazio — indistinguível de "o usuário não configurou nada", e a opção nunca
# poderia ser desligada. O teste explícito contra null preserva o false, e o
# tostring devolve números e booleanos como string, que é o que o bash consome.
#
# O terceiro argumento é o default, e existe porque bash não distingue "chave
# ausente" de "chave presente com string vazia" — as duas chegariam como "". Sem
# ele, um widget que queira permitir `"label": ""` para esconder o rótulo não
# teria como: o fallback do próprio widget reporia o default. Passando o default
# para dentro do jq, quem decide é o teste contra null, que enxerga a diferença.
sl_config_widget_opt() {
  local widget="$1" key="$2" default="$3" value
  if [ -z "$SL_CONFIG_RAW" ]; then
    printf '%s' "$default"
    return 0
  fi
  value="$(printf '%s' "$SL_CONFIG_RAW" | sl_jq -r --arg w "$widget" --arg k "$key" --arg d "$default" \
    '.widgets[$w][$k] | if . == null then $d else tostring end' 2>/dev/null)" || value="$default"
  printf '%s' "$value"
}
