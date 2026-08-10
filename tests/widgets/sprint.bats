load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/gitdir.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/widgets/sprint.sh"
  SL_CONFIG_RAW=""
  export SL_SPRINT_BIN="$PROJECT_ROOT/tests/fixtures/fake-sprint.sh"
  export FAKE_SPRINT_OUT="7/10 2 1"

  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  git -C "$REPO" config commit.gpgsign false
  printf 'a' > "$REPO/a.txt"
  git -C "$REPO" add a.txt
  git -C "$REPO" commit -qm initial
  SL_CWD="$REPO"
}

make_yaml() {
  mkdir -p "$REPO/_bmad-output/implementation-artifacts"
  printf 'development_status:\n' > "$REPO/_bmad-output/implementation-artifacts/sprint-status.yaml"
}

use_config() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
}

@test "registers itself on load" {
  sl_widget_registered sprint
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR sprint)" = "1" ]
}

@test "renders nothing outside a git repository" {
  SL_CWD="$BATS_TEST_TMPDIR"
  run widget_sprint_render
  [ "$output" = "" ]
}

@test "renders nothing when the sprint file is absent" {
  # Projeto que não é BMAD simplesmente não tem o arquivo. O widget se cala
  # sozinho, sem precisar ser desativado na configuração.
  run widget_sprint_render
  [ "$output" = "" ]
}

@test "renders nothing when the helper is missing" {
  make_yaml
  export SL_SPRINT_BIN="/path/that/does/not/exist"
  run widget_sprint_render
  [ "$output" = "" ]
}

@test "renders nothing when the helper says nothing" {
  # Sem epic ativo, o helper sai vazio com status zero. Não é erro.
  make_yaml
  export FAKE_SPRINT_OUT=""
  run widget_sprint_render
  [ "$output" = "" ]
}

@test "shows the done over total ratio" {
  make_yaml
  run widget_sprint_render
  [[ "$output" == *"7/10"* ]]
}

@test "shows the ready queue" {
  make_yaml
  run widget_sprint_render
  [[ "$output" == *"▸2"* ]]
}

@test "shows the review count" {
  make_yaml
  run widget_sprint_render
  [[ "$output" == *"⊙1"* ]]
}

@test "omits the ready queue when it is zero" {
  make_yaml
  export FAKE_SPRINT_OUT="7/10 0 1"
  run widget_sprint_render
  [[ "$output" != *"▸"* ]]
}

@test "omits the review count when it is zero" {
  make_yaml
  export FAKE_SPRINT_OUT="7/10 2 0"
  run widget_sprint_render
  [[ "$output" != *"⊙"* ]]
}

@test "paints green from eighty percent done" {
  make_yaml
  export FAKE_SPRINT_OUT="8/10 0 0"
  run widget_sprint_render
  [[ "$output" == *$'\033[32m'* ]]
}

@test "paints yellow from forty percent done" {
  make_yaml
  export FAKE_SPRINT_OUT="4/10 0 0"
  run widget_sprint_render
  [[ "$output" == *$'\033[33m'* ]]
}

@test "paints red below forty percent done" {
  make_yaml
  export FAKE_SPRINT_OUT="3/10 0 0"
  run widget_sprint_render
  [[ "$output" == *$'\033[31m'* ]]
}

@test "garbage from the helper renders nothing" {
  # Um helper com saída inesperada não pode inventar números de sprint.
  make_yaml
  export FAKE_SPRINT_OUT="isto nao e um ratio"
  run widget_sprint_render
  [ "$output" = "" ]
}

@test "a zero total renders nothing" {
  # Divisão por zero no cálculo do percentual, e um sprint sem stories não
  # tem saúde a reportar.
  make_yaml
  export FAKE_SPRINT_OUT="0/0 0 0"
  run widget_sprint_render
  [ "$output" = "" ]
}

@test "a non-numeric ready count is dropped without killing the ratio" {
  make_yaml
  export FAKE_SPRINT_OUT="7/10 muitos 1"
  run widget_sprint_render
  [[ "$output" == *"7/10"* ]]
  [[ "$output" != *"▸"* ]]
}

@test "the path option points at another file" {
  mkdir -p "$REPO/custom"
  printf 'x\n' > "$REPO/custom/sprint.yaml"
  use_config '{"version":1,"lines":[["sprint"]],"widgets":{"sprint":{"path":"custom/sprint.yaml"}}}'
  run widget_sprint_render
  [[ "$output" == *"7/10"* ]]
}

@test "reuses the cached value" {
  make_yaml
  widget_sprint_render >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'sprint-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run widget_sprint_render
  [ "$output" = "PLANTED" ]
}

@test "follows a change to the sprint file" {
  # O yaml é um arquivo de verdade, então o mtime dele é a sentinela certa —
  # ao contrário da sujeira da árvore, que não vive em arquivo nenhum.
  make_yaml
  yaml="$REPO/_bmad-output/implementation-artifacts/sprint-status.yaml"
  touch -t 202001010000 "$yaml"
  widget_sprint_render >/dev/null
  export FAKE_SPRINT_OUT="9/10 0 0"
  printf 'development_status:\n# mudou\n' > "$yaml"
  run widget_sprint_render
  [[ "$output" == *"9/10"* ]]
}

@test "returns zero when it renders nothing" {
  widget_sprint_render >/dev/null
}
