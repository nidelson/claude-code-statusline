load helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/cache.sh"
  SENTINEL="$BATS_TEST_TMPDIR/sentinel"
  printf 'v1' > "$SENTINEL"
  COUNTER="$BATS_TEST_TMPDIR/counter"
  printf '0' > "$COUNTER"
  counted_command() {
    local n; n=$(cat "$COUNTER"); printf '%s' "$((n + 1))" > "$COUNTER"
    printf 'result-%s' "$((n + 1))"
  }
}

@test "first call runs the command" {
  run cache_by_mtime key1 "$SENTINEL" counted_command
  [ "$output" = "result-1" ]
  [ "$(cat "$COUNTER")" = "1" ]
}

@test "second call with untouched sentinel uses the cache" {
  cache_by_mtime key1 "$SENTINEL" counted_command
  run cache_by_mtime key1 "$SENTINEL" counted_command
  [ "$output" = "result-1" ]
  [ "$(cat "$COUNTER")" = "1" ]
}

@test "touched sentinel invalidates the cache" {
  cache_by_mtime key1 "$SENTINEL" counted_command
  sleep 1
  printf 'v2' > "$SENTINEL"
  run cache_by_mtime key1 "$SENTINEL" counted_command
  [ "$output" = "result-2" ]
}

@test "missing sentinel runs the command without caching" {
  run cache_by_mtime key2 "$BATS_TEST_TMPDIR/absent" counted_command
  [ "$output" = "result-1" ]
}

@test "unexpired TTL uses the cache" {
  cache_by_ttl key3 60 counted_command
  run cache_by_ttl key3 60 counted_command
  [ "$output" = "result-1" ]
}

@test "zero TTL always recomputes" {
  cache_by_ttl key4 0 counted_command
  run cache_by_ttl key4 0 counted_command
  [ "$output" = "result-2" ]
}

@test "multi-line values survive the round trip" {
  multiline() { printf 'line one\nline two'; }
  run cache_by_mtime key5 "$SENTINEL" multiline
  [ "$output" = "line one
line two" ]
  run cache_by_mtime key5 "$SENTINEL" multiline
  [ "$output" = "line one
line two" ]
}

@test "a stat form was detected on this platform" {
  [ "$SL_STAT_FORM" = "bsd" ] || [ "$SL_STAT_FORM" = "gnu" ]
}

@test "the timestamp is a single-line integer" {
  run _sl_mtime "$SENTINEL"
  [ "$status" -eq 0 ]
  # Uma linha só, e só dígitos. Um carimbo com várias linhas ou com texto
  # envenena a comparação do cache em silêncio: `read` lê a primeira linha do
  # arquivo e compara com o valor inteiro, que nunca coincide, e o cache deixa
  # de acertar sem nunca dar erro.
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "the timestamp tracks the file, not the filesystem" {
  local before after
  before="$(_sl_mtime "$SENTINEL")"
  sleep 1
  printf 'v2' > "$SENTINEL"
  after="$(_sl_mtime "$SENTINEL")"
  # Dois arquivos do mesmo sistema de arquivos não podem compartilhar carimbo:
  # é isso que distingue ler o arquivo de ler o sistema de arquivos.
  [ "$after" != "$before" ]
}

@test "an unreadable target degrades to zero" {
  run _sl_mtime "$BATS_TEST_TMPDIR/nao-existe"
  [ "$output" = "0" ]
}
