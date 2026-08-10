load helper

setup() {
  source "$PROJECT_ROOT/lib/config.sh"
  TMPCFG="$BATS_TEST_TMPDIR/config.json"
}

@test "falls back to defaults when the file is missing" {
  sl_config_load "$BATS_TEST_TMPDIR/does-not-exist.json"
  [ "$SL_CONFIG_WARN" = "" ]
  [ -n "$SL_CONFIG_LINES" ]
}

@test "reads lines and separator from the file" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["model","git"],["rate-forecast"]],"separator":"."}
EOF
  sl_config_load "$TMPCFG"
  [ "$SL_CONFIG_SEP" = "." ]
  [ "$(printf '%s' "$SL_CONFIG_LINES" | sed -n 1p)" = "model git" ]
  [ "$(printf '%s' "$SL_CONFIG_LINES" | sed -n 2p)" = "rate-forecast" ]
}

@test "invalid JSON falls back to defaults and raises a warning" {
  printf 'this { is not json' > "$TMPCFG"
  sl_config_load "$TMPCFG"
  [ "$SL_CONFIG_WARN" = "config" ]
  [ -n "$SL_CONFIG_LINES" ]
}

@test "invalid JSON is never overwritten" {
  printf 'this { is not json' > "$TMPCFG"
  sl_config_load "$TMPCFG"
  [ "$(cat "$TMPCFG")" = 'this { is not json' ]
}

@test "reads a widget option" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"window":"5h"}}}
EOF
  sl_config_load "$TMPCFG"
  [ "$(sl_config_widget_opt rate-forecast window)" = "5h" ]
}

@test "icons default to enabled when unset" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["model"]]}
EOF
  sl_config_load "$TMPCFG"
  [ "$SL_CONFIG_ICONS" = "1" ]
}

@test "icons can be disabled" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["model"]],"icons":false}
EOF
  sl_config_load "$TMPCFG"
  [ "$SL_CONFIG_ICONS" = "0" ]
}

@test "icons default to enabled when the file is missing" {
  sl_config_load "$BATS_TEST_TMPDIR/does-not-exist.json"
  [ "$SL_CONFIG_ICONS" = "1" ]
}

@test "missing widget option returns empty" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["model"]]}
EOF
  sl_config_load "$TMPCFG"
  [ -z "$(sl_config_widget_opt model color)" ]
}

@test "a false widget option survives as false" {
  # Em jq, `//` cai para o lado direito em null E em false. Com `// empty` uma
  # opção booleana desligada voltaria vazia, e seria lida como "não configurado".
  cat > "$BATS_TEST_TMPDIR/config.json" <<'JSON'
{"version":1,"lines":[["model"]],"widgets":{"context":{"tokens":false}}}
JSON
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  [ "$(sl_config_widget_opt context tokens)" = "false" ]
}

@test "a true widget option comes back as true" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'JSON'
{"version":1,"lines":[["model"]],"widgets":{"context":{"tokens":true}}}
JSON
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  [ "$(sl_config_widget_opt context tokens)" = "true" ]
}

@test "a numeric widget option comes back as a string" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'JSON'
{"version":1,"lines":[["git"]],"widgets":{"git":{"ttl":30}}}
JSON
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  [ "$(sl_config_widget_opt git ttl)" = "30" ]
}

@test "an unset widget option comes back empty" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'JSON'
{"version":1,"lines":[["git"]]}
JSON
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  [ "$(sl_config_widget_opt git ttl)" = "" ]
}

@test "an absent option falls back to the given default" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'JSON'
{"version":1,"lines":[["cache"]]}
JSON
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  [ "$(sl_config_widget_opt cache label "cache:")" = "cache:" ]
}

@test "an explicitly empty option beats the default" {
  # bash não distingue "ausente" de "presente e vazio" — as duas chegariam
  # como "". Quem decide é o teste contra null, dentro do jq.
  cat > "$BATS_TEST_TMPDIR/config.json" <<'JSON'
{"version":1,"lines":[["cache"]],"widgets":{"cache":{"label":""}}}
JSON
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  [ "$(sl_config_widget_opt cache label "cache:")" = "" ]
}

@test "the default applies with no config file at all" {
  sl_config_load "$BATS_TEST_TMPDIR/absent.json"
  [ "$(sl_config_widget_opt cache label "cache:")" = "cache:" ]
}
