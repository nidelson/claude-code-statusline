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
