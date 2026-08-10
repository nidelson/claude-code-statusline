load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/gitdir.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/repo.sh"
  SL_CONFIG_RAW=""
  OSC8=$'\033]8;;'
  BEL=$'\007'
}

make_repo() {
  REPO="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  git -C "$REPO" config commit.gpgsign false
  printf 'a' > "$REPO/a.txt"
  git -C "$REPO" add a.txt
  git -C "$REPO" commit -qm initial
}

use_config() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
}

# ── Conversão de URL: função pura, sem git ──

@test "converts an scp-like remote" {
  [ "$(_repo_url_from_remote 'git@github.com:nidelson/dotfiles.git')" \
    = "https://github.com/nidelson/dotfiles" ]
}

@test "converts an https remote and drops the .git suffix" {
  [ "$(_repo_url_from_remote 'https://github.com/nidelson/dotfiles.git')" \
    = "https://github.com/nidelson/dotfiles" ]
}

@test "strips credentials from an https remote" {
  # Sem isto, um remote com token embutido viraria um hyperlink com a
  # credencial dentro, visível no terminal e copiada junto com o link.
  [ "$(_repo_url_from_remote 'https://user:ghp_secret@github.com/n/d.git')" \
    = "https://github.com/n/d" ]
}

@test "converts an ssh remote and drops the port" {
  # Porta de SSH não vale para HTTPS.
  [ "$(_repo_url_from_remote 'ssh://git@github.com:22/nidelson/dotfiles.git')" \
    = "https://github.com/nidelson/dotfiles" ]
}

@test "converts an Azure DevOps ssh remote" {
  # O host web é outro e o path ganha um segmento _git — não dá para derivar
  # trocando ':' por '/'.
  [ "$(_repo_url_from_remote 'git@ssh.dev.azure.com:v3/ORG/PROJ/REPO')" \
    = "https://dev.azure.com/ORG/PROJ/_git/REPO" ]
}

@test "returns nothing for a local path remote" {
  # Um link errado é pior que nenhum link.
  [ "$(_repo_url_from_remote '/srv/git/bare.git')" = "" ]
}

@test "returns nothing for an empty remote" {
  [ "$(_repo_url_from_remote '')" = "" ]
}

# ── Widget ──

@test "registers itself on load" {
  sl_widget_registered repo
}

@test "shows the repository name" {
  make_repo myproject
  SL_CWD="$REPO"
  run widget_repo_render
  [[ "$output" == *"myproject"* ]]
}

@test "renders nothing outside a git repository" {
  SL_CWD="$BATS_TEST_TMPDIR"
  run widget_repo_render
  [ "$output" = "" ]
}

@test "renders nothing for a missing directory" {
  SL_CWD="$BATS_TEST_TMPDIR/absent"
  run widget_repo_render
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "plain text when there is no remote" {
  make_repo noremote
  SL_CWD="$REPO"
  run widget_repo_render
  [ "$output" = "noremote" ]
}

@test "wraps the name in a hyperlink when a remote exists" {
  make_repo linked
  git -C "$REPO" remote add origin git@github.com:nidelson/linked.git
  SL_CWD="$REPO"
  run widget_repo_render
  [ "$output" = "${OSC8}https://github.com/nidelson/linked${BEL}linked${OSC8}${BEL}" ]
}

@test "the link option turns the hyperlink off" {
  make_repo nolink
  git -C "$REPO" remote add origin git@github.com:nidelson/nolink.git
  use_config '{"version":1,"lines":[["repo"]],"widgets":{"repo":{"link":false}}}'
  SL_CWD="$REPO"
  run widget_repo_render
  [ "$output" = "nolink" ]
}

@test "shows the main repository name from inside a worktree" {
  # O widget worktree é quem diz em qual worktree você está; este diz de qual
  # repo ele saiu.
  make_repo mainrepo
  git -C "$REPO" worktree add -q -b probe "$BATS_TEST_TMPDIR/some-worktree"
  SL_CWD="$BATS_TEST_TMPDIR/some-worktree"
  run widget_repo_render
  [ "$output" = "mainrepo" ]
}

@test "reuses the cached value" {
  make_repo cached
  SL_CWD="$REPO"
  widget_repo_render >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'repo-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED\t' "$stamp" > "$cache_file"
  run widget_repo_render
  [ "$output" = "PLANTED" ]
}

@test "a cache entry without a tab still yields a name" {
  # Defesa contra entrada de cache truncada ou de uma versão anterior.
  make_repo tabless
  SL_CWD="$REPO"
  widget_repo_render >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'repo-*' | head -1)"
  stamp="$(head -1 "$cache_file")"
  printf '%s\nBARE' "$stamp" > "$cache_file"
  run widget_repo_render
  [ "$output" = "BARE" ]
}

@test "an invalid ttl falls back to the default" {
  make_repo badttl
  use_config '{"version":1,"lines":[["repo"]],"widgets":{"repo":{"ttl":"forever"}}}'
  SL_CWD="$REPO"
  run widget_repo_render
  [ "$output" = "badttl" ]
}

@test "returns zero when it renders nothing" {
  SL_CWD="$BATS_TEST_TMPDIR"
  widget_repo_render >/dev/null
}
