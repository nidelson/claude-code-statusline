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

sl_color() {
  case "$1" in
    red)     printf '\033[31m' ;;
    green)   printf '\033[32m' ;;
    yellow)  printf '\033[33m' ;;
    blue)    printf '\033[34m' ;;
    magenta) printf '\033[35m' ;;
    cyan)    printf '\033[36m' ;;
    dim)     printf '\033[2m'  ;;
    *)       printf ''         ;;
  esac
}
