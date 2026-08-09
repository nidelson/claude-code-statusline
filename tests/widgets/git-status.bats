load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/git-status.sh"
  SL_CONFIG_RAW=""
  # TTL zero em quase todo teste: o widget cacheia por tempo, e testar o valor
  # exibido logo após mexer no repositório exigiria esperar o TTL expirar.
  no_cache
}

no_cache() {
  printf '%s' '{"version":1,"lines":[["git-status"]],"widgets":{"git-status":{"ttl":0}}}' \
    > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
}

git_config() {
  git -C "$1" config user.email t@t.t
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
}

# Repositório solto, sem upstream.
make_repo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git_config "$REPO"
  printf 'a' > "$REPO/a.txt"
  git -C "$REPO" add a.txt
  git -C "$REPO" commit -qm initial
}

# Clone com upstream configurado, sincronizado.
make_cloned() {
  BARE="$BATS_TEST_TMPDIR/remote.git"
  git init -q --bare "$BARE"
  SEED="$BATS_TEST_TMPDIR/seed"
  git clone -q "$BARE" "$SEED"
  git_config "$SEED"
  printf 'a' > "$SEED/a.txt"
  git -C "$SEED" add a.txt
  git -C "$SEED" commit -qm initial
  git -C "$SEED" push -q origin HEAD
  REPO="$BATS_TEST_TMPDIR/clone"
  git clone -q "$BARE" "$REPO"
  git_config "$REPO"
}

@test "registers itself on load" {
  sl_widget_registered git-status
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR git-status)" = "1" ]
}

@test "renders nothing outside a git repository" {
  SL_CWD="$BATS_TEST_TMPDIR"
  run widget_git_status_render
  [ "$output" = "" ]
}

@test "renders nothing for a missing directory" {
  SL_CWD="$BATS_TEST_TMPDIR/absent"
  run widget_git_status_render
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "renders nothing on a clean tree with no upstream" {
  # Nada a dizer é dizer nada. Um indicador de "tudo certo" ocuparia espaço
  # permanente para não informar.
  make_repo
  SL_CWD="$REPO"
  run widget_git_status_render
  [ "$output" = "" ]
}

@test "counts modified files" {
  make_repo
  printf 'changed' > "$REPO/a.txt"
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"●1"* ]]
}

@test "counts untracked files too" {
  make_repo
  printf 'new' > "$REPO/b.txt"
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"●1"* ]]
}

@test "paints the dirty count yellow" {
  make_repo
  printf 'changed' > "$REPO/a.txt"
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "renders nothing on a clean tree in sync with its upstream" {
  make_cloned
  SL_CWD="$REPO"
  run widget_git_status_render
  [ "$output" = "" ]
}

@test "shows commits ahead of the upstream" {
  make_cloned
  printf 'local' > "$REPO/local.txt"
  git -C "$REPO" add local.txt
  git -C "$REPO" commit -qm local
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"↑1"* ]]
}

@test "paints commits ahead green" {
  make_cloned
  printf 'local' > "$REPO/local.txt"
  git -C "$REPO" add local.txt
  git -C "$REPO" commit -qm local
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *$'\033[32m'* ]]
}

@test "shows commits behind the upstream" {
  make_cloned
  printf 'remote' > "$SEED/remote.txt"
  git -C "$SEED" add remote.txt
  git -C "$SEED" commit -qm remote
  git -C "$SEED" push -q origin HEAD
  git -C "$REPO" fetch -q
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"↓1"* ]]
}

@test "paints commits behind red" {
  make_cloned
  printf 'remote' > "$SEED/remote.txt"
  git -C "$SEED" add remote.txt
  git -C "$SEED" commit -qm remote
  git -C "$SEED" push -q origin HEAD
  git -C "$REPO" fetch -q
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *$'\033[31m'* ]]
}

@test "shows ahead and behind together when diverged" {
  # O cabeçalho vira "[ahead 1, behind 1]" — os dois números no mesmo colchete,
  # separados por vírgula. É o caso que quebra um parser ingênuo.
  make_cloned
  printf 'remote' > "$SEED/remote.txt"
  git -C "$SEED" add remote.txt
  git -C "$SEED" commit -qm remote
  git -C "$SEED" push -q origin HEAD
  git -C "$REPO" fetch -q
  printf 'local' > "$REPO/local.txt"
  git -C "$REPO" add local.txt
  git -C "$REPO" commit -qm local
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"↑1"* ]]
  [[ "$output" == *"↓1"* ]]
}

@test "shows all three at once" {
  make_cloned
  printf 'remote' > "$SEED/remote.txt"
  git -C "$SEED" add remote.txt
  git -C "$SEED" commit -qm remote
  git -C "$SEED" push -q origin HEAD
  git -C "$REPO" fetch -q
  printf 'local' > "$REPO/local.txt"
  git -C "$REPO" add local.txt
  git -C "$REPO" commit -qm local
  printf 'dirty' > "$REPO/a.txt"
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"●1"* ]]
  [[ "$output" == *"↑1"* ]]
  [[ "$output" == *"↓1"* ]]
}

@test "still counts dirty files on a detached HEAD" {
  # O cabeçalho vira "## HEAD (no branch)" e não traz upstream, mas as linhas
  # de arquivo continuam lá.
  make_repo
  git -C "$REPO" checkout -q --detach
  printf 'changed' > "$REPO/a.txt"
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"●1"* ]]
}

@test "reuses the cached value within the ttl" {
  make_repo
  printf 'changed' > "$REPO/a.txt"
  printf '%s' '{"version":1,"lines":[["git-status"]],"widgets":{"git-status":{"ttl":3600}}}' \
    > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  SL_CWD="$REPO"
  widget_git_status_render >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'gitstatus-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run widget_git_status_render
  [ "$output" = "PLANTED" ]
}

@test "an invalid ttl falls back to the default" {
  make_repo
  printf 'changed' > "$REPO/a.txt"
  printf '%s' '{"version":1,"lines":[["git-status"]],"widgets":{"git-status":{"ttl":"soon"}}}' \
    > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  SL_CWD="$REPO"
  run widget_git_status_render
  [[ "$output" == *"●1"* ]]
}

@test "returns zero when it renders nothing" {
  make_repo
  SL_CWD="$REPO"
  widget_git_status_render >/dev/null
}
