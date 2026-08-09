load helper

@test "entrypoint existe e é executável" {
  [ -x "$PROJECT_ROOT/bin/statusline.sh" ]
}

@test "entrypoint imprime algo com stdin válido" {
  run bash -c 'echo "{\"model\":{\"display_name\":\"Opus 5\"}}" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "entrypoint não quebra com stdin vazio" {
  run bash -c 'printf "" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]
}
