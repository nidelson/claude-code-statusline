load helper

setup() {
  source "$PROJECT_ROOT/lib/stdin.sh"
}

@test "extracts the model name" {
  sl_parse_stdin '{"model":{"display_name":"Opus 5","id":"claude-opus-5"}}'
  [ "$SL_MODEL" = "Opus 5" ]
  [ "$SL_MODEL_ID" = "claude-opus-5" ]
}

@test "missing field falls back to default, not error" {
  sl_parse_stdin '{}'
  [ "$SL_MODEL" = "Unknown" ]
  [ "$SL_COST" = "0" ]
}

@test "extracts nested rate limits" {
  sl_parse_stdin '{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1800000000}}}'
  [ "$SL_5H_PCT" = "42" ]
  [ "$SL_5H_RESET" = "1800000000" ]
}

@test "value with quotes and spaces does not break eval" {
  sl_parse_stdin '{"workspace":{"current_dir":"/tmp/a b\"c"}}'
  [ "$SL_CWD" = '/tmp/a b"c' ]
}

@test "invalid JSON sets SL_JQ_OK=0 without aborting" {
  sl_parse_stdin 'isto nao e json'
  [ "$SL_JQ_OK" = "0" ]
}
