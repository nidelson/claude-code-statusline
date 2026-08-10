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
  local raw gitdir common top key

  # A resolução dos caminhos, com todas as suas sutilezas, vive em lib/gitdir.sh
  # e é compartilhada com os widgets repo e branch.
  raw="$(sl_git_paths)"
  [ -n "$raw" ] || return 0

  IFS=$'\t' read -r gitdir common top <<EOF
$raw
EOF

  [ -n "$top" ] || return 0

  # Árvore principal: nada a mostrar.
  sl_git_is_worktree "$gitdir" "$common" || return 0

  key="worktree-$(printf '%s' "$gitdir" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$gitdir/HEAD" _worktree_compute "$top"
}
