# Branch atual e estado da árvore de trabalho.
#
# Usa cache contra .git/HEAD: troca de branch e commit ambos mexem nesse
# arquivo, e o objetivo é justamente não invocar git a cada repaint.
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
  local root key

  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  root="$(git -C "$SL_CWD" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0

  # A chave deriva do caminho do repositório para que projetos diferentes não
  # compartilhem entrada de cache.
  key="git-$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$root/.git/HEAD" _git_compute
}
