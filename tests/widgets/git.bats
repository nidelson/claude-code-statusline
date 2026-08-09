load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/widgets/git.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  # O usuário pode ter commit.gpgsign=true global (é o caso deste dotfiles);
  # o repo temporário não tem chave para a identidade fictícia acima.
  git -C "$REPO" config commit.gpgsign false
  printf 'a' > "$REPO/a.txt"
  git -C "$REPO" add a.txt
  git -C "$REPO" commit -qm initial
}

@test "shows the branch name" {
  SL_CWD="$REPO"
  run widget_git_render
  [[ "$output" == *"$(git -C "$REPO" branch --show-current)"* ]]
}

@test "renders nothing outside a git repository" {
  SL_CWD="$BATS_TEST_TMPDIR"
  run widget_git_render
  [ "$output" = "" ]
}

@test "missing directory renders nothing without erroring" {
  SL_CWD="$BATS_TEST_TMPDIR/absent"
  run widget_git_render
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "empty SL_CWD renders nothing" {
  SL_CWD=""
  run widget_git_render
  [ "$output" = "" ]
}

@test "marks a dirty working tree" {
  SL_CWD="$REPO"
  printf 'changed' > "$REPO/a.txt"
  run widget_git_render
  [[ "$output" == *"1"* ]]
}

@test "registers itself on load" {
  sl_widget_registered git
}
