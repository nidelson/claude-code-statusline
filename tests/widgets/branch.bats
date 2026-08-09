load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/gitdir.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/branch.sh"
  SL_CONFIG_RAW=""
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
  sl_widget_registered branch
}

@test "shows the current branch" {
  SL_CWD="$REPO"
  run widget_branch_render
  [ "$output" = "$(git -C "$REPO" branch --show-current)" ]
}

@test "renders nothing outside a git repository" {
  SL_CWD="$BATS_TEST_TMPDIR"
  run widget_branch_render
  [ "$output" = "" ]
}

@test "renders nothing for a missing directory" {
  SL_CWD="$BATS_TEST_TMPDIR/absent"
  run widget_branch_render
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "shows a short sha on a detached HEAD" {
  # O widget git fica mudo com HEAD solto; aqui isso seria perder a única
  # informação que o widget existe para dar. O @ marca que não é uma branch.
  SL_CWD="$REPO"
  git -C "$REPO" checkout -q --detach
  run widget_branch_render
  [ "$output" = "@$(git -C "$REPO" rev-parse --short HEAD)" ]
}

@test "shows the branch of the worktree, not of the main tree" {
  git -C "$REPO" worktree add -q -b probe "$BATS_TEST_TMPDIR/wt"
  SL_CWD="$BATS_TEST_TMPDIR/wt"
  run widget_branch_render
  [ "$output" = "probe" ]
}

@test "follows a checkout" {
  # HEAD guarda "ref: refs/heads/<branch>" e é reescrito no checkout — ao
  # contrário do commit, que mexe em refs/heads/<branch>. Por isso o mtime de
  # HEAD é a sentinela certa AQUI, e era a errada no contador de sujeira.
  #
  # O touch antecipado é necessário porque o mtime tem resolução de um segundo:
  # sem ele, render e checkout no mesmo segundo dariam o mesmo carimbo.
  SL_CWD="$REPO"
  touch -t 202001010000 "$REPO/.git/HEAD"
  widget_branch_render >/dev/null
  git -C "$REPO" checkout -q -b outra
  run widget_branch_render
  [ "$output" = "outra" ]
}

@test "survives a commit without changing" {
  # O commit não reescreve HEAD, então o cache continua válido — e continua
  # certo, porque a branch não mudou.
  SL_CWD="$REPO"
  before="$(widget_branch_render)"
  printf 'b' > "$REPO/a.txt"
  git -C "$REPO" commit -qam second
  run widget_branch_render
  [ "$output" = "$before" ]
}

@test "reuses the cached value" {
  SL_CWD="$REPO"
  widget_branch_render >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'branch-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run widget_branch_render
  [ "$output" = "PLANTED" ]
}

@test "a worktree does not share the cache with the main tree" {
  git -C "$REPO" worktree add -q -b probe2 "$BATS_TEST_TMPDIR/wt2"
  SL_CWD="$REPO";                 main_out="$(widget_branch_render)"
  SL_CWD="$BATS_TEST_TMPDIR/wt2"; run widget_branch_render
  [ "$output" != "$main_out" ]
}

@test "returns zero when it renders nothing" {
  SL_CWD="$BATS_TEST_TMPDIR"
  widget_branch_render >/dev/null
}
