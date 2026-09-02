# Paleta de cores.
#
# Widgets emitem texto cru; o núcleo aplica a cor configurada. A exceção são os
# widgets declarados com --self-color, cuja cor é semântica (o forecast pinta
# conforme o risco, não conforme preferência) e por isso pintam a si mesmos.

SL_RESET=$'\033[0m'
SL_DIM=$'\033[2m'

# Coral da marca Claude (#D97757), em truecolor. Terminais sem suporte a
# 24 bits ignoram a sequência e caem na cor padrão do texto — degradação
# aceitável, já que a cor aqui é decorativa e não carrega informação sozinha.
SL_BRAND=$'\033[38;2;217;119;87m'

# As cores vivem em variáveis, e não só dentro do `case` de sl_color, porque
# quem pinta a linha inteira está no caminho quente: lib/core.sh precisa da
# sequência de escape sem pagar um `$( )` por widget, e um subshell por widget é
# justamente o custo que fez a statusline passar de três segundos e ser
# cancelada em voo. Ver o cabeçalho de lib/config.sh.
#
# sl_color continua sendo a porta de entrada para os widgets, que chamam de
# dentro do próprio subshell e para quem um fork a mais não muda nada.
_SL_C_red=$'\033[31m'
_SL_C_green=$'\033[32m'
_SL_C_yellow=$'\033[33m'
_SL_C_blue=$'\033[34m'
_SL_C_magenta=$'\033[35m'
_SL_C_cyan=$'\033[36m'
_SL_C_dim=$'\033[2m'

# O nome da cor vem da configuração do usuário, então não pode virar nome de
# variável sem filtro: para o bash, colchetes num nome são índice de array, e
# `red[0]` leria o escalar `_SL_C_red`. O `case` recusa tudo que não seja o
# alfabeto dos nomes que existem.
# A resolução mora numa função que devolve por variável porque quem monta a
# linha, em lib/core.sh, chama uma vez por widget e não pode pagar um `$( )` por
# chamada — capturar por subshell aqui é o mesmo fork que fazia a barra ser
# cancelada em voo. sl_color existe por cima dela para os widgets, que já estão
# dentro do próprio subshell.
sl_color_set() {
  local var
  case "$1" in
    *[!a-z]*|'') SL_COLOR=""; return 0 ;;
  esac
  var="_SL_C_$1"
  SL_COLOR="${!var}"
  return 0
}

sl_color() {
  sl_color_set "$1"
  printf '%s' "$SL_COLOR"
}
