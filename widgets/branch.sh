# Branch atual, sozinha.
#
# O widget `git` mostra branch e sujeira juntos. Este mostra só a branch, para
# quem quer posicionar ou colorir as duas coisas separadamente — por exemplo
# branch na primeira linha e estado na segunda.
#
# ── A sentinela aqui é a certa ──
#
# .git/HEAD guarda "ref: refs/heads/<branch>" e é reescrito no checkout. O commit
# não mexe nele, mexe em refs/heads/<branch>. Ou seja: o mtime de HEAD muda
# exatamente quando a branch muda, e não muda quando ela não muda. É a sentinela
# ideal — e é a mesma que estava errada no contador de sujeira do widget `git`,
# porque lá a informação a rastrear era outra.
#
# Custo: zero spawn de git com cache quente, contra um por repaint se a resolução
# do git-dir ficasse fora do cache.
#
# Limite conhecido: o mtime tem resolução de um segundo, então trocar de branch e
# repintar dentro do mesmo segundo pode mostrar a branch anterior. A statusline
# repinta a cada poucos segundos de qualquer forma.
#
# ── HEAD solto ──
#
# Com HEAD detached não há branch, e o widget `git` fica mudo. Aqui ficar mudo
# seria perder a única informação que este widget existe para dar, então mostra o
# sha curto prefixado por @ — o prefixo marca que aquilo não é nome de branch.

register_widget branch \
  --render widget_branch_render \
  --color  cyan \
  --desc   "Current branch, or short sha when detached"

_branch_compute() {
  local name

  name="$(git -C "$SL_CWD" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)"
  if [ -n "$name" ]; then
    printf '%s' "$name"
    return 0
  fi

  name="$(git -C "$SL_CWD" --no-optional-locks rev-parse --short HEAD 2>/dev/null)"
  [ -n "$name" ] || return 0
  printf '@%s' "$name"
}

widget_branch_render() {
  local raw gitdir common top key

  raw="$(sl_git_paths)"
  [ -n "$raw" ] || return 0

  IFS=$'\t' read -r gitdir common top <<EOF
$raw
EOF

  [ -n "$gitdir" ] || return 0

  # A chave sai do git-dir e não do cwd: cada worktree tem HEAD próprio, e dois
  # diretórios da mesma árvore devem compartilhar a entrada.
  key="branch-$(printf '%s' "$gitdir" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$gitdir/HEAD" _branch_compute
}
