load helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/gitdir.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  git -C "$REPO" config commit.gpgsign false
  printf 'a' > "$REPO/a.txt"
  git -C "$REPO" add a.txt
  git -C "$REPO" commit -qm initial
}

fields() {
  IFS=$'\t' read -r GITDIR COMMON TOP <<EOF
$1
EOF
}

@test "returns nothing outside a git repository" {
  SL_CWD="$BATS_TEST_TMPDIR"
  run sl_git_paths
  [ "$output" = "" ]
}

@test "returns nothing for a missing directory" {
  SL_CWD="$BATS_TEST_TMPDIR/absent"
  run sl_git_paths
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "returns nothing for an empty cwd" {
  SL_CWD=""
  run sl_git_paths
  [ "$output" = "" ]
}

@test "returns three tab separated fields" {
  SL_CWD="$REPO"
  fields "$(sl_git_paths)"
  [ -n "$GITDIR" ]
  [ -n "$COMMON" ]
  [ -n "$TOP" ]
}

@test "resolves the common dir to an absolute path" {
  # O git devolve ".git" relativo quando o cwd é a raiz do repo. Comparar isso
  # com um caminho absoluto nunca casaria.
  SL_CWD="$REPO"
  fields "$(sl_git_paths)"
  case "$COMMON" in
    /*) ;;
    *) false ;;
  esac
}

@test "git dir and common dir match in the main working tree" {
  # É esta igualdade que distingue árvore principal de worktree linkada. Falhava
  # antes por causa do symlink /var para /private/var no macOS.
  SL_CWD="$REPO"
  fields "$(sl_git_paths)"
  [ "$GITDIR" = "$COMMON" ]
  ! sl_git_is_worktree "$GITDIR" "$COMMON"
}

@test "git dir and common dir differ inside a linked worktree" {
  git -C "$REPO" worktree add -q -b probe "$BATS_TEST_TMPDIR/wt"
  SL_CWD="$BATS_TEST_TMPDIR/wt"
  fields "$(sl_git_paths)"
  [ "$GITDIR" != "$COMMON" ]
  sl_git_is_worktree "$GITDIR" "$COMMON"
}

@test "the common dir points at the main repository from a worktree" {
  git -C "$REPO" worktree add -q -b probe2 "$BATS_TEST_TMPDIR/wt2"
  SL_CWD="$BATS_TEST_TMPDIR/wt2"
  fields "$(sl_git_paths)"
  [ "$COMMON" = "$(cd "$REPO" && pwd -P)/.git" ]
}

@test "the toplevel points at the worktree itself" {
  git -C "$REPO" worktree add -q -b probe3 "$BATS_TEST_TMPDIR/wt3"
  SL_CWD="$BATS_TEST_TMPDIR/wt3"
  fields "$(sl_git_paths)"
  [ "$(basename "$TOP")" = "wt3" ]
}

@test "reuses the cached value" {
  SL_CWD="$REPO"
  sl_git_paths >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'gitpaths-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run sl_git_paths
  [ "$output" = "PLANTED" ]
}

@test "different directories do not share a cache entry" {
  git -C "$REPO" worktree add -q -b probe4 "$BATS_TEST_TMPDIR/wt4"
  SL_CWD="$REPO";                  main_out="$(sl_git_paths)"
  SL_CWD="$BATS_TEST_TMPDIR/wt4";  wt_out="$(sl_git_paths)"
  [ "$main_out" != "$wt_out" ]
}

@test "a zero ttl bypasses the cache" {
  SL_CWD="$REPO"
  sl_git_paths 0 >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'gitpaths-*' | head -1)"
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run sl_git_paths 0
  [ "$output" != "PLANTED" ]
}

@test "an invalid ttl falls back to the default" {
  SL_CWD="$REPO"
  run sl_git_paths "forever"
  [ -n "$output" ]
}

@test "is not a worktree when either path is empty" {
  ! sl_git_is_worktree "" "/some/.git"
  ! sl_git_is_worktree "/some/.git" ""
}
