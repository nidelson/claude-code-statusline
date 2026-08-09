load helper

@test "entrypoint exists and is executable" {
  [ -x "$PROJECT_ROOT/bin/statusline.sh" ]
}

@test "entrypoint prints something for valid stdin" {
  run bash -c 'echo "{\"model\":{\"display_name\":\"Opus 5\"}}" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "entrypoint survives empty stdin" {
  run bash -c 'printf "" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]
}
