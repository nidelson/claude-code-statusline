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

@test "rounds a fractional rate limit percentage" {
  # A API manda float, e o binário morde: 55.00000000000001 é o que de fato
  # chega. Sem arredondar, a statusline exibe o erro de ponto flutuante inteiro.
  sl_parse_stdin '{"rate_limits":{"five_hour":{"used_percentage":55.00000000000001}}}'
  [ "$SL_5H_PCT" = "55" ]
}

@test "rounds the seven day percentage up when it should" {
  sl_parse_stdin '{"rate_limits":{"seven_day":{"used_percentage":13.6}}}'
  [ "$SL_7D_PCT" = "14" ]
}

@test "an absent percentage stays empty instead of becoming zero" {
  # Vazio e zero são coisas diferentes: zero é "não gastei nada", vazio é "não
  # sei". O widget precisa poder ficar calado no segundo caso.
  sl_parse_stdin '{"model":{"display_name":"X"}}'
  [ "$SL_5H_PCT" = "" ]
}

@test "value with quotes and spaces does not break eval" {
  sl_parse_stdin '{"workspace":{"current_dir":"/tmp/a b\"c"}}'
  [ "$SL_CWD" = '/tmp/a b"c' ]
}

@test "invalid JSON sets SL_JQ_OK=0 without aborting" {
  sl_parse_stdin 'isto nao e json'
  [ "$SL_JQ_OK" = "0" ]
}

@test "reads cache tokens from current_usage" {
  # Os campos de cache vivem em .context_window.current_usage, não na raiz.
  sl_parse_stdin '{"context_window":{"current_usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":700}}}'
  [ "$SL_CACHE_READ" = "700" ]
  [ "$SL_CACHE_CREATE" = "200" ]
  [ "$SL_INPUT_TOKENS" = "100" ]
}

@test "cache tokens default to zero when current_usage is null" {
  # current_usage é null entre trocas — documentado no statusline.sh original.
  sl_parse_stdin '{"context_window":{"context_window_size":200000,"current_usage":null}}'
  [ "$SL_CACHE_READ" = "0" ]
  [ "$SL_INPUT_TOKENS" = "0" ]
}

@test "still reads cache tokens from the root as a fallback" {
  sl_parse_stdin '{"cache_read_input_tokens":42}'
  [ "$SL_CACHE_READ" = "42" ]
}
