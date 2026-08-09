# Nome do worktree linkado.
#
# Renderiza apenas quando o diretório atual está em um worktree linkado, nunca
# na árvore principal — o objetivo é sinalizar "você não está no repo de
# sempre". A detecção compara --absolute-git-dir com --git-common-dir: em um
# worktree linkado o primeiro aponta para .git/worktrees/<nome> e o segundo para
# o .git do repo principal; na árvore principal os dois coincidem.
#
# Fica em silêncio quando o nome do diretório é igual ao da branch, caso comum
# de `git worktree add -b x ../x`: o widget de git já mostra a branch, e repetir
# o mesmo texto lado a lado seria ruído.

register_widget worktree \
  --render widget_worktree_render \
  --color  magenta \
  --desc   "Linked worktree name"

_worktree_compute() {
  local name branch
  name="$(basename "$1")"
  branch="$(git -C "$SL_CWD" --no-optional-locks branch --show-current 2>/dev/null)" || branch=""
  [ "$name" = "$branch" ] && return 0
  printf '%s' "$name"
}

widget_worktree_render() {
  local paths gitdir common top key

  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  # Uma chamada só devolve os três caminhos, um por linha.
  paths="$(git -C "$SL_CWD" --no-optional-locks \
           rev-parse --absolute-git-dir --git-common-dir --show-toplevel 2>/dev/null)" || return 0

  gitdir="$(printf '%s\n' "$paths" | sed -n 1p)"
  common="$(printf '%s\n' "$paths" | sed -n 2p)"
  top="$(printf '%s\n' "$paths" | sed -n 3p)"

  [ -n "$gitdir" ] && [ -n "$common" ] && [ -n "$top" ] || return 0

  # --git-common-dir pode voltar relativo (".git") quando o cwd é a raiz do repo
  # principal; nesse caso os dois nunca seriam iguais na comparação textual.
  # Resolver para absoluto evita falso positivo de "é worktree".
  #
  # `pwd -P` (físico) e não `pwd`: --absolute-git-dir já resolve symlinks, e no
  # macOS o diretório temporário fica sob /var, que é symlink para /private/var.
  # Com o caminho lógico os dois lados nunca coincidiriam e toda árvore
  # principal seria classificada como worktree.
  case "$common" in
    /*) ;;
    *) common="$(cd "$SL_CWD" && cd "$common" 2>/dev/null && pwd -P)" || return 0 ;;
  esac

  # Mesmo git-dir e common-dir: árvore principal, nada a mostrar.
  [ "$gitdir" != "$common" ] || return 0

  key="worktree-$(printf '%s' "$gitdir" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$gitdir/HEAD" _worktree_compute "$top"
}
