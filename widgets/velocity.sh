# Linhas adicionadas e removidas na sessão.
#
# A cor é semântica — verde é adição, vermelho é remoção, convenção de diff que
# ninguém quer reconfigurar — então o widget é --self-color.
#
# ── Por que zero some ──
#
# O statusline.sh original mostrava "+0 -0" sempre. Numa sessão de leitura ou de
# pesquisa isso é ruído permanente: ocupa espaço para dizer "nada aconteceu", o
# que é o mesmo que não dizer nada. Aqui cada metade só aparece quando tem valor,
# e o widget inteiro some quando as duas são zero.
#
# Contagem sai sem abreviação. "+1.2k" esconderia a diferença entre 1200 e 1249
# num número em que ela importa — diferente de tokens, onde a ordem de grandeza é
# o que interessa.

register_widget velocity \
  --render widget_velocity_render \
  --self-color \
  --desc   "Lines added and removed this session"

# Valor ausente ou ilegível vale zero: a alternativa seria o widget sumir por
# causa de um campo que o cliente simplesmente não mandou.
_velocity_int() {
  case "$1" in
    ""|*[!0-9]*) printf '0' ;;
    *)           printf '%s' "$1" ;;
  esac
}

widget_velocity_render() {
  local added removed out=""

  added="$(_velocity_int "$SL_LINES_ADDED")"
  removed="$(_velocity_int "$SL_LINES_REMOVED")"

  # `if` e não `[ a ] && [ b ] && return`. Não por causa de `set -e`: medido, um
  # AND-list com o lado esquerdo falso não derruba o shell. O problema é o status
  # de retorno — a forma encadeada devolve 1 quando a condição é falsa, e basta
  # alguém acrescentar uma linha depois dela virar a última instrução da função
  # para o widget passar a "falhar" sem ter falhado.
  if [ "$added" = "0" ] && [ "$removed" = "0" ]; then
    return 0
  fi

  if [ "$added" != "0" ]; then
    out="$(sl_color green)+${added}${SL_RESET}"
  fi

  if [ "$removed" != "0" ]; then
    if [ -n "$out" ]; then
      out="${out} "
    fi
    out="${out}$(sl_color red)-${removed}${SL_RESET}"
  fi

  printf '%s' "$out"
}
