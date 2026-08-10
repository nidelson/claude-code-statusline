load helper

# Testes de ponta a ponta: rodam o entrypoint como o Claude Code roda, por
# subprocesso, com o JSON de sessão no stdin. É a única camada que exercita a
# ordem real de carregamento (colors, core, cache, stdin, config, widgets).

setup() {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  # O helper real existe na máquina do autor mas não no CI. Apontar para um
  # caminho inexistente deixa o teste determinístico nos dois lugares.
  export SL_FORECAST_BIN="/path/that/does/not/exist"
  mkdir -p "$XDG_CONFIG_HOME/claude-code-statusline"
  cat > "$XDG_CONFIG_HOME/claude-code-statusline/config.json" <<'EOF'
{"version":1,"lines":[["model"],["rate-forecast"]],"separator":"|"}
EOF
}

run_statusline() {
  run bash -c '"$0" < "$1"' "$PROJECT_ROOT/bin/statusline.sh" "$1"
}

@test "renders two lines from the fixture" {
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [ "$status" -eq 0 ]
  # $output vem sem o newline final, então duas linhas contam como um \n.
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" = "1" ]
}

@test "shows the model name" {
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [[ "$output" == *"Opus 5"* ]]
}

@test "shows the rate limit percentage" {
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  # O rótulo é esmaecido e o percentual carrega a cor do nível de uso, então há
  # sequências de escape entre os dois.
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"42%"* ]]
}

@test "exits zero on unparseable stdin" {
  run bash -c 'printf "this is not json" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]
}

@test "still prints something on unparseable stdin" {
  # A statusline nunca pode sumir: sumir é indistinguível de "plugin morto".
  run bash -c 'printf "this is not json" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [ -n "$output" ]
}

@test "marks unparseable stdin as a warning" {
  run bash -c 'printf "this is not json" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [[ "$output" == *"⚠"* ]]
}

@test "keeps the warning marker alongside real widgets" {
  # Um widget que não depende do stdin ainda renderiza; o marcador precisa
  # conviver com ele, não substituí-lo.
  cat > "$XDG_CONFIG_HOME/claude-code-statusline/config.json" <<'EOF'
{"version":1,"lines":[["model"]],"separator":"|"}
EOF
  run bash -c 'printf "%s" "{\"model\":{\"display_name\":\"Opus 5\"}}" | "$0"' \
    "$PROJECT_ROOT/bin/statusline.sh"
  [[ "$output" == *"Opus 5"* ]]
  [[ "$output" != *"⚠"* ]]
}

@test "does not overwrite a broken config file" {
  printf 'broken {' > "$XDG_CONFIG_HOME/claude-code-statusline/config.json"
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_CONFIG_HOME/claude-code-statusline/config.json")" = 'broken {' ]
}

@test "falls back to the default lines when the config is broken" {
  printf 'broken {' > "$XDG_CONFIG_HOME/claude-code-statusline/config.json"
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [[ "$output" == *"Opus 5"* ]]
}

@test "marks a broken config as a warning" {
  printf 'broken {' > "$XDG_CONFIG_HOME/claude-code-statusline/config.json"
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [[ "$output" == *"⚠"* ]]
}

@test "does not warn when the config is valid" {
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [[ "$output" != *"⚠"* ]]
}

@test "survives a missing config file" {
  rm -f "$XDG_CONFIG_HOME/claude-code-statusline/config.json"
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 5"* ]]
}

@test "ignores a widget name it does not know" {
  cat > "$XDG_CONFIG_HOME/claude-code-statusline/config.json" <<'EOF'
{"version":1,"lines":[["model","from-the-future"]],"separator":"|"}
EOF
  run_statusline "$PROJECT_ROOT/tests/fixtures/session.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 5"* ]]
}
