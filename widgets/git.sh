# Branch atual e estado da árvore de trabalho.
#
# Usa cache contra o HEAD: troca de branch e commit ambos mexem nesse arquivo,
# e o objetivo é justamente não invocar git a cada repaint.
#
# A sentinela sai de `git rev-parse --git-dir`, não de "$toplevel/.git". Em um
# worktree linkado, .git é um ARQUIVO contendo "gitdir: /main/.git/worktrees/x",
# então "$toplevel/.git/HEAD" não existe — o cache cairia no caminho "sem
# sentinela" e o widget spawnaria git a cada repaint, justamente onde o cache
# mais importa. O --git-dir resolve certo nos dois casos, e cada worktree tem
# HEAD próprio, que é exatamente o que invalida a entrada.
#
# --no-optional-locks evita que a checagem em segundo plano crie disputa por
# .git/index.lock com um git que o usuário esteja rodando na mesma hora.

register_widget git \
  --render widget_git_render \
  --color  magenta \
  --desc   "Branch and working tree state"

_git_compute() {
  local branch dirty
  branch="$(git -C "$SL_CWD" --no-optional-locks branch --show-current 2>/dev/null)" || return 0
  [ -n "$branch" ] || return 0
  dirty="$(git -C "$SL_CWD" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ -n "$dirty" ] && [ "$dirty" != "0" ]; then
    printf '%s ●%s' "$branch" "$dirty"
  else
    printf '%s' "$branch"
  fi
}

widget_git_render() {
  local gitdir key

  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  # Uma única chamada resolve o git-dir e serve de teste "isto é um repo?".
  # Caminho relativo (o git devolve ".git" quando o cwd é a raiz) vira absoluto
  # com -C, senão a sentinela apontaria para o lugar errado.
  gitdir="$(git -C "$SL_CWD" --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  [ -n "$gitdir" ] || return 0

  # A chave deriva do git-dir, não do toplevel: em worktree os dois diferem, e
  # cada worktree precisa da própria entrada de cache.
  key="git-$(printf '%s' "$gitdir" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$gitdir/HEAD" _git_compute
}
