# Branch atual e estado da árvore de trabalho.
#
# ── Por que TTL e não mtime ──
#
# A primeira versão invalidava por mtime de .git/HEAD, com a justificativa de que
# "troca de branch e commit ambos mexem nesse arquivo". Metade disso é falso.
#
# .git/HEAD contém "ref: refs/heads/<branch>". O commit atualiza
# refs/heads/<branch>, não o HEAD — o conteúdo do HEAD continua idêntico. E
# editar um arquivo qualquer da árvore não toca em nada dentro de .git: nem no
# HEAD, nem no index (o index só muda no `git add`). Resultado: a entrada de
# cache nascia válida e permanecia válida indefinidamente, através de commits e
# de edições. O contador de sujeira congelava no primeiro valor visto.
#
# Não existe arquivo que sirva de sentinela para "a árvore ficou suja", porque a
# informação não vive em arquivo nenhum — vive na comparação entre a árvore e o
# index. Então a única invalidação honesta é tempo, e o TTL vira o teto explícito
# de quão velho o número pode estar.
#
# ── Por que uma chamada só ──
#
# Medido nesta máquina: `status --porcelain` ~10,6 ms e `branch --show-current`
# ~8,4 ms. A diferença entre os dois é ~2 ms, ou seja, quase todo o custo é spawn
# de processo, não trabalho de git. Então `status --porcelain --branch` entrega
# branch e sujeira pelo preço de um spawn, contra três da versão anterior
# (rev-parse + branch + status).
#
# A chave do cache sai do SL_CWD justamente para dispensar o rev-parse. O preço é
# que dois diretórios do mesmo repositório não compartilham entrada — aceitável,
# porque cada um continua limitado a uma chamada por TTL.
#
# --no-optional-locks evita disputa por .git/index.lock com um git que o usuário
# esteja rodando na mesma hora.

register_widget git \
  --render widget_git_render \
  --color  magenta \
  --desc   "Branch and working tree state"

SL_GIT_DEFAULT_TTL=2

_git_compute() {
  local out header branch dirty

  out="$(git -C "$SL_CWD" --no-optional-locks status --porcelain --branch 2>/dev/null)" || return 0
  [ -n "$out" ] || return 0

  header="$(printf '%s\n' "$out" | sed -n 1p)"
  branch="${header#\#\# }"
  # "main...origin/main [ahead 1]" vira "main". Três pontos são inequívocos: o
  # git rejeita nomes de branch com pontos consecutivos.
  branch="${branch%%...*}"

  case "$branch" in
    # Nome de branch nunca tem espaço — se tem, é cabeçalho especial do git.
    "HEAD (no branch)")    return 0 ;;
    "No commits yet on "*) branch="${branch#No commits yet on }" ;;
    *\ *)                  return 0 ;;
  esac

  [ -n "$branch" ] || return 0

  dirty="$(printf '%s\n' "$out" | sed -n '2,$p' | wc -l | tr -d ' ')"

  if [ -n "$dirty" ] && [ "$dirty" != "0" ]; then
    printf '%s ●%s' "$branch" "$dirty"
  else
    printf '%s' "$branch"
  fi
}

widget_git_render() {
  local ttl key

  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  ttl="$(sl_config_widget_opt git ttl)"
  # TTL não-numérico cairia dentro de `[ -gt ]`, que escreve no stderr. A
  # statusline não pode sujar o terminal por causa de uma config torta.
  case "$ttl" in
    ""|*[!0-9]*) ttl="$SL_GIT_DEFAULT_TTL" ;;
  esac

  key="git-$(printf '%s' "$SL_CWD" | cksum | cut -d' ' -f1)"
  cache_by_ttl "$key" "$ttl" _git_compute
}
