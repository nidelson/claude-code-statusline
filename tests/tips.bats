load helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/tips.sh"
}

# ── corte de ritmo ──

@test "cut turns 116 projected over 25 used into an 18 percent slowdown" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
}

@test "cut refuses a projection that is not above one hundred" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
  run _tip_cut 98 25
  [ "$status" -ne 0 ]
}

@test "cut refuses when used is not below the projection" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
  run _tip_cut 116 116
  [ "$status" -ne 0 ]
}

@test "cut refuses non numeric input" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
  run _tip_cut "abc" 25
  [ "$status" -ne 0 ]
}

# ── degrau ──

@test "step buckets the projection in slices of twenty five" {
  run _tip_step 101 ; [ "$output" = "0" ]
  run _tip_step 124 ; [ "$output" = "0" ]
  run _tip_step 125 ; [ "$output" = "1" ]
  run _tip_step 150 ; [ "$output" = "2" ]
  run _tip_step 999 ; [ "$output" = "3" ]
}

@test "step refuses a projection at or below one hundred" {
  run _tip_step 125
  [ "$output" = "1" ]
  run _tip_step 100
  [ "$status" -ne 0 ]
}

# ── turno corrente ──

mk_transcript() {   # mk_transcript <promptId>
  printf '{"type":"user","promptId":"%s","message":{"role":"user"}}\n' "$1" \
    > "$BATS_TEST_TMPDIR/transcript.jsonl"
  # O fim de um transcript real costuma ser `attachment`, que não carrega
  # promptId — é por isso que a leitura usa `tail -n` e não `tail -c`.
  printf '{"type":"attachment","note":"sem promptId no fim do arquivo"}\n' \
    >> "$BATS_TEST_TMPDIR/transcript.jsonl"
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
}

@test "prompt id comes from the last entry that carries one" {
  mk_transcript "turno-A"
  run _tip_prompt_id
  [ "$output" = "turno-A" ]
}

@test "prompt id gives up when there is no transcript" {
  mk_transcript "turno-A"
  run _tip_prompt_id
  [ "$output" = "turno-A" ]
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run _tip_prompt_id
  [ "$status" -ne 0 ]
}

# ── estado por fonte ──

@test "state round trips a source" {
  _tip_state_put flow 0 1755900000 turno-A
  run _tip_state_get flow
  [ "$output" = "0 1755900000 turno-A" ]
}

@test "state keeps sources independent" {
  _tip_state_put flow 0 1755900000 turno-A
  _tip_state_put 7d   2 1755800000 turno-B
  _tip_state_put flow 1 1755700000 turno-C
  run _tip_state_get 7d
  [ "$output" = "2 1755800000 turno-B" ]
}

@test "state drops one source and leaves the others" {
  _tip_state_put flow 0 1755900000 turno-A
  _tip_state_put 7d   2 1755800000 turno-B
  _tip_state_drop flow
  run _tip_state_get 7d
  [ "$output" = "2 1755800000 turno-B" ]
  run _tip_state_get flow
  [ "$status" -ne 0 ]
}

@test "state file disappears once the last source is dropped" {
  _tip_state_put flow 0 1755900000 turno-A
  [ -f "$SL_CACHE_DIR/tip-state.tsv" ]
  _tip_state_drop flow
  [ ! -f "$SL_CACHE_DIR/tip-state.tsv" ]
}

# ── a regra ──

@test "shows on the first crossing above one hundred" {
  mk_transcript "turno-A"
  run _tip_should_show flow 116 1755900000 1755000000
  [ "$status" -eq 0 ]
}

@test "keeps showing within the same turn" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  run _tip_should_show flow 117 1755900000 1755000000
  [ "$status" -eq 0 ]
}

@test "goes quiet on the next turn when nothing got worse" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  run _tip_should_show flow 117 1755900000 1755000000
  [ "$status" -ne 0 ]
}

@test "speaks again on the next turn when the step went up" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  run _tip_should_show flow 130 1755900000 1755000000
  [ "$status" -eq 0 ]
}

@test "speaks again when the block date moved more than a tenth closer" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  # Faltavam 900000s, então a margem é 90000s. Antecipar 200000s passa dela.
  run _tip_should_show flow 116 1755700000 1755000000
  [ "$status" -eq 0 ]
}

@test "stays quiet when the block date barely moved" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  run _tip_should_show flow 116 1755880000 1755000000
  [ "$status" -ne 0 ]
}
