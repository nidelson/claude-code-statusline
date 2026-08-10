load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/gitdir.sh"
  source "$PROJECT_ROOT/widgets/worktree.sh"
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

@test "registers itself on load" {
  sl_widget_registered worktree
}

@test "renders nothing in the main working tree" {
  SL_CWD="$REPO"
  run widget_worktree_render
  [ "$output" = "" ]
}

@test "renders nothing outside a git repository" {
  SL_CWD="$BATS_TEST_TMPDIR"
  run widget_worktree_render
  [ "$output" = "" ]
}

@test "renders nothing for a missing directory" {
  SL_CWD="$BATS_TEST_TMPDIR/absent"
  run widget_worktree_render
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "shows the worktree directory name" {
  git -C "$REPO" worktree add -q -b feature "$BATS_TEST_TMPDIR/my-wt"
  SL_CWD="$BATS_TEST_TMPDIR/my-wt"
  run widget_worktree_render
  [ "$output" = "my-wt" ]
}

@test "stays quiet when the directory name matches the branch" {
  # O widget de git já mostra a branch; repetir o mesmo texto lado a lado
  # seria ruído. Este é o caso comum de `git worktree add -b x ../x`.
  git -C "$REPO" worktree add -q -b samename "$BATS_TEST_TMPDIR/samename"
  SL_CWD="$BATS_TEST_TMPDIR/samename"
  run widget_worktree_render
  [ "$output" = "" ]
}

@test "reuses the cached value" {
  git -C "$REPO" worktree add -q -b cached "$BATS_TEST_TMPDIR/cached-wt"
  SL_CWD="$BATS_TEST_TMPDIR/cached-wt"
  widget_worktree_render >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'worktree-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run widget_worktree_render
  [ "$output" = "PLANTED" ]
}
