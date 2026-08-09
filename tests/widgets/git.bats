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

@test "shows the branch inside a linked worktree" {
  WT="$BATS_TEST_TMPDIR/wt"
  git -C "$REPO" worktree add -q -b probe "$WT"
  SL_CWD="$WT"
  run widget_git_render
  [[ "$output" == *"probe"* ]]
}

@test "caches inside a linked worktree" {
  # Em um worktree linkado, .git é um arquivo com "gitdir: ...", não um
  # diretório — então $toplevel/.git/HEAD não existe e o cache cairia no
  # caminho "sem sentinela", spawnando git a cada repaint. A sentinela precisa
  # sair de `git rev-parse --git-dir`.
  #
  # A contagem usa `find`, não `ls | wc -l` capturado por `run`: o `run` do bats
  # combina stdout e stderr, então um diretório inexistente faria a mensagem de
  # erro do ls entrar na saída e o teste passaria sem cache nenhum.
  WT="$BATS_TEST_TMPDIR/wt2"
  git -C "$REPO" worktree add -q -b probe2 "$WT"
  SL_CWD="$WT"
  widget_git_render >/dev/null
  [ -d "$SL_CACHE_DIR" ]
  [ "$(find "$SL_CACHE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]
}

@test "the cached value is reused inside a worktree" {
  WT="$BATS_TEST_TMPDIR/wt4"
  git -C "$REPO" worktree add -q -b probe4 "$WT"
  SL_CWD="$WT"
  widget_git_render >/dev/null
  # Adultera o cache: se a segunda chamada o consultar, devolve o valor plantado.
  cache_file="$(find "$SL_CACHE_DIR" -type f | head -1)"
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run widget_git_render
  [ "$output" = "PLANTED" ]
}

@test "worktree and main repo do not share a cache entry" {
  WT="$BATS_TEST_TMPDIR/wt3"
  git -C "$REPO" worktree add -q -b probe3 "$WT"
  SL_CWD="$REPO"; run widget_git_render
  main_out="$output"
  SL_CWD="$WT";   run widget_git_render
  [ "$output" != "$main_out" ]
}
