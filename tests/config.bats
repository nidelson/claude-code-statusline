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

@test "missing widget option returns empty" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["model"]]}
EOF
  sl_config_load "$TMPCFG"
  [ -z "$(sl_config_widget_opt model color)" ]
}
