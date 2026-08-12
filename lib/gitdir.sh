# Resolução dos caminhos do git, uma vez por diretório.
#
# Três widgets precisam saber onde o git mora — repo, branch e worktree — e cada
# um resolvia por conta própria. Três cópias de uma lógica que tem duas sutilezas
# fáceis de errar, e uma delas já produziu um bug real:
#
#   1. --git-common-dir pode voltar relativo (".git") quando o cwd é a raiz do
#      repo principal. Comparar isso com um caminho absoluto nunca casa.
#   2. `pwd -P` e não `pwd`: --absolute-git-dir já resolve symlinks, e no macOS
#      /var é symlink para /private/var. Com o caminho lógico os dois lados nunca
#      coincidiriam, e toda árvore principal seria classificada como worktree.
#
# O resultado é cacheado por diretório. Para um dado cwd os três caminhos são
# imutáveis na prática, então o TTL é alto — e mudar de diretório muda a chave,
# que é exatamente quando a resposta muda. Consequência assumida: rodar
# `git init` dentro de um diretório que já estava sendo exibido leva até o TTL
# para aparecer.

SL_GITDIR_DEFAULT_TTL=300

_sl_git_paths_compute() {
  local paths gitdir common top

  paths="$(git -C "$SL_CWD" --no-optional-locks rev-parse \
           --absolute-git-dir --git-common-dir --show-toplevel 2>/dev/null)" || return 0

  gitdir="$(printf '%s\n' "$paths" | sed -n 1p)"
  common="$(printf '%s\n' "$paths" | sed -n 2p)"
  top="$(printf '%s\n' "$paths" | sed -n 3p)"

  [ -n "$gitdir" ] && [ -n "$common" ] || return 0

  # Os dois passam pelo MESMO normalizador, e é isso que os torna comparáveis.
  #
  # A versão anterior normalizava só o `common`, e confiava no formato que o git
  # devolvia para o `gitdir`. Funciona onde os dois formatos coincidem, que é
  # macOS e Linux. No Git for Windows não coincidem: `--absolute-git-dir` sai em
  # formato Windows e `pwd -P` do MSYS sai em formato Unix, descrevendo o mesmo
  # diretório com strings diferentes —
  #
  #   gitdir  C:/Users/nome/repo/.git
  #   common  /c/Users/nome/repo/.git
  #
  # — e como a igualdade entre os dois é o que separa árvore principal de
  # worktree linkada, toda árvore principal virava worktree ali.
  #
  # É a terceira armadilha de normalização de caminho neste arquivo, depois do
  # `.git` relativo e do symlink /var do macOS. As três têm a mesma forma:
  # comparar caminhos que o sistema escreve de mais de um jeito.
  gitdir="$(cd "$gitdir" 2>/dev/null && pwd -P)" || return 0
  common="$(cd "$SL_CWD" 2>/dev/null && cd "$common" 2>/dev/null && pwd -P)" || return 0
  [ -n "$gitdir" ] && [ -n "$common" ] || return 0

  printf '%s\t%s\t%s' "$gitdir" "$common" "$top"
}

# Devolve "gitdir<TAB>commondir<TAB>toplevel", ou nada fora de um repositório.
sl_git_paths() {
  local ttl="${1:-$SL_GITDIR_DEFAULT_TTL}" key

  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  case "$ttl" in
    ""|*[!0-9]*) ttl="$SL_GITDIR_DEFAULT_TTL" ;;
  esac

  key="gitpaths-$(printf '%s' "$SL_CWD" | cksum | cut -d' ' -f1)"
  cache_by_ttl "$key" "$ttl" _sl_git_paths_compute
}

# Está numa worktree linkada? Em worktree o git-dir aponta para
# .git/worktrees/<nome> e o common-dir para o .git do repo principal; na árvore
# principal os dois coincidem.
sl_git_is_worktree() {
  [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ]
}
