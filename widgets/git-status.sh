# Estado da árvore de trabalho: sujeira, e distância para o upstream.
#
#   ●3   três arquivos modificados ou não rastreados
#   ↑1   um commit local que o upstream não tem
#   ↓2   dois commits no upstream que a árvore local não tem
#
# É a metade "estado" do widget `git`; a metade "branch" é o widget `branch`.
# Use `git` sozinho, ou estes dois — nunca os três, ou o mesmo `git status`
# roda duas vezes.
#
# ── Uma chamada só ──
#
# O statusline.sh original usava duas: `status --porcelain` para a sujeira e
# `rev-list --left-right --count HEAD...@{upstream}` para o ahead/behind. Mas
# `status --porcelain --branch` já traz os dois números no cabeçalho:
#
#   ## main...origin/main [ahead 1, behind 2]
#    M arquivo
#
# Como o custo de git é quase todo spawn de processo, isso corta o preço pela
# metade sem perder nada.
#
# ── Cache por tempo ──
#
# Mesmo motivo do widget `git`: editar um arquivo não toca em nada dentro de
# .git, então não existe sentinela de mtime para "a árvore ficou suja". O TTL é
# o teto explícito de quão velho o número pode estar.

register_widget git-status \
  --render widget_git_status_render \
  --self-color \
  --desc   "Dirty count and distance from upstream"

SL_GIT_STATUS_DEFAULT_TTL=2

# Extrai um número do bloco de tracking do cabeçalho. O bloco é "ahead 1",
# "behind 2" ou "ahead 1, behind 2" — daí o corte na vírgula.
_git_status_count() {
  local track="$1" word="$2" rest
  case "$track" in
    *"$word "*) ;;
    *) return 0 ;;
  esac
  rest="${track#*$word }"
  rest="${rest%%[,]*}"
  case "$rest" in
    ""|*[!0-9]*) return 0 ;;
  esac
  printf '%s' "$rest"
}

_git_status_compute() {
  local out header track dirty ahead behind result=""

  out="$(git -C "$SL_CWD" --no-optional-locks status --porcelain --branch 2>/dev/null)" || return 0
  [ -n "$out" ] || return 0

  header="$(printf '%s\n' "$out" | sed -n 1p)"
  # Tudo depois do cabeçalho é uma linha por arquivo.
  dirty="$(printf '%s\n' "$out" | sed -n '2,$p' | wc -l | tr -d ' ')"

  # Recorta o miolo dos colchetes antes de procurar as palavras. Sem esse
  # escopo, uma branch chamada "ahead" ou "behind" confundiria a busca.
  # Cabeçalho sem colchetes — sem upstream, ou upstream sumido ([gone]) — deixa
  # o bloco vazio e os dois contadores fora.
  case "$header" in
    *\[*\]) track="${header#*\[}"; track="${track%%\]*}" ;;
    *)      track="" ;;
  esac

  ahead="$(_git_status_count "$track" ahead)"
  behind="$(_git_status_count "$track" behind)"

  if [ -n "$dirty" ] && [ "$dirty" != "0" ]; then
    result="$(sl_color yellow)●${dirty}$SL_RESET"
  fi

  if [ -n "$ahead" ] && [ "$ahead" != "0" ]; then
    if [ -n "$result" ]; then result="$result "; fi
    result="$result$(sl_color green)↑${ahead}$SL_RESET"
  fi

  if [ -n "$behind" ] && [ "$behind" != "0" ]; then
    if [ -n "$result" ]; then result="$result "; fi
    result="$result$(sl_color red)↓${behind}$SL_RESET"
  fi

  # Árvore limpa e em dia não rende nada. Um indicador de "tudo certo" ocuparia
  # espaço permanente para não informar.
  printf '%s' "$result"
}

widget_git_status_render() {
  local ttl key

  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  ttl="$(sl_config_widget_opt git-status ttl "$SL_GIT_STATUS_DEFAULT_TTL")"
  case "$ttl" in
    ""|*[!0-9]*) ttl="$SL_GIT_STATUS_DEFAULT_TTL" ;;
  esac

  key="gitstatus-$(printf '%s' "$SL_CWD" | cksum | cut -d' ' -f1)"
  cache_by_ttl "$key" "$ttl" _git_status_compute
}
