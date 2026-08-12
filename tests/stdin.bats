load helper

setup() {
  source "$PROJECT_ROOT/lib/core.sh"
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

@test "drops the floating point tail from a rate limit percentage" {
  # A API manda float, e o binário morde: 55.00000000000001 é o que de fato
  # chega. Sem cortar, a statusline exibe o erro de ponto flutuante inteiro.
  sl_parse_stdin '{"rate_limits":{"five_hour":{"used_percentage":55.00000000000001}}}'
  [ "$SL_5H_PCT" = "55" ]
}

@test "keeps the real precision of a fractional percentage" {
  # Cortar em duas casas mata a cauda binária sem inventar um inteiro. Quem
  # exibe arredonda; quem deriva uma taxa precisa do número como veio, porque
  # para ele um degrau de 1 ponto percentual é ruído extrapolado sobre a janela.
  sl_parse_stdin '{"rate_limits":{"seven_day":{"used_percentage":13.6}}}'
  [ "$SL_7D_PCT" = "13.6" ]
}

@test "keeps two decimal places and no more" {
  sl_parse_stdin '{"rate_limits":{"seven_day":{"used_percentage":24.4832}}}'
  [ "$SL_7D_PCT" = "24.48" ]
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

@test "exposes the transcript path" {
  sl_parse_stdin '{"transcript_path":"/tmp/session.jsonl"}'
  [ "$SL_TRANSCRIPT" = "/tmp/session.jsonl" ]
}

@test "the transcript path is empty when absent" {
  # Contraprova: o mesmo parse com o campo presente tem de preenchê-lo, senão
  # este teste passaria com a variável nunca sendo atribuída.
  sl_parse_stdin '{"model":{"display_name":"X"}}'
  [ "$SL_TRANSCRIPT" = "" ]
  sl_parse_stdin '{"transcript_path":"/tmp/a.jsonl"}'
  [ "$SL_TRANSCRIPT" = "/tmp/a.jsonl" ]
}

@test "the transcript path is empty when the json is malformed" {
  sl_parse_stdin 'nao e json'
  [ "$SL_TRANSCRIPT" = "" ]
}
