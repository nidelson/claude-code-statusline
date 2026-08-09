load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/sanitize.sh"
  E=$'\033'
  BEL=$'\007'
}

# A configuração tem de estar carregada ANTES do source: é dela que o widget
# descobre quais instâncias registrar.
load_with() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/config.json"
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  source "$PROJECT_ROOT/widgets/command.sh"
}

@test "registers an instance named in the config" {
  load_with '{"version":1,"lines":[["command:hello"]],"widgets":{"command:hello":{"cmd":"echo oi"}}}'
  sl_widget_registered command:hello
}

@test "registers each instance separately" {
  load_with '{"version":1,"lines":[["command:a","command:b"]],"widgets":{"command:a":{"cmd":"echo A"},"command:b":{"cmd":"echo B"}}}'
  sl_widget_registered command:a
  sl_widget_registered command:b
  [ "$(sl_widget_attr RENDER command:a)" != "$(sl_widget_attr RENDER command:b)" ]
}

@test "instances render their own command" {
  load_with '{"version":1,"lines":[["command:a","command:b"]],"widgets":{"command:a":{"cmd":"echo A"},"command:b":{"cmd":"echo B"}}}'
  [ "$(widget_command_a_render)" = "A" ]
  [ "$(widget_command_b_render)" = "B" ]
}

@test "renders the command output" {
  load_with '{"version":1,"lines":[["command:hello"]],"widgets":{"command:hello":{"cmd":"echo oi"}}}'
  run _command_render command:hello
  [ "$output" = "oi" ]
}

@test "renders nothing without a cmd" {
  load_with '{"version":1,"lines":[["command:empty"]],"widgets":{"command:empty":{}}}'
  run _command_render command:empty
  [ "$output" = "" ]
}

@test "renders nothing when the command fails" {
  load_with '{"version":1,"lines":[["command:bad"]],"widgets":{"command:bad":{"cmd":"exit 1"}}}'
  run _command_render command:bad
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "renders nothing when the output is only whitespace" {
  # Um widget de um espaço só apareceria como separadores em volta de nada.
  load_with '{"version":1,"lines":[["command:blank"]],"widgets":{"command:blank":{"cmd":"printf \"   \""}}}'
  run _command_render command:blank
  [ "$output" = "" ]
}

@test "strips escape sequences by default" {
  load_with '{"version":1,"lines":[["command:esc"]],"widgets":{"command:esc":{"cmd":"printf \"\\033[31mred\\033[0m\""}}}'
  run _command_render command:esc
  [ "$output" = "red" ]
}

@test "keeps colours with the colors option" {
  load_with '{"version":1,"lines":[["command:col"]],"widgets":{"command:col":{"cmd":"printf \"\\033[31mred\\033[0m\"","colors":true}}}'
  got="$(_command_render command:col)"
  [ "$got" = "$(printf '%s[31mred%s[0m' "$E" "$E")" ]
}

@test "strips a clipboard write from command output" {
  # O caso que justifica a higienização existir.
  load_with '{"version":1,"lines":[["command:evil"]],"widgets":{"command:evil":{"cmd":"printf \"\\033]52;c;cGF5bG9hZA==\\007ok\""}}}'
  run _command_render command:evil
  [ "$output" = "ok" ]
}

@test "collapses multi-line output into one line" {
  load_with '{"version":1,"lines":[["command:multi"]],"widgets":{"command:multi":{"cmd":"printf \"a\\nb\""}}}'
  run _command_render command:multi
  [ "$output" = "a b" ]
}

@test "prefixes with the label option" {
  load_with '{"version":1,"lines":[["command:lbl"]],"widgets":{"command:lbl":{"cmd":"echo 42","label":"flow:"}}}'
  run _command_render command:lbl
  [ "$output" = "flow:42" ]
}

@test "expands a tilde in the command" {
  # O comando roda por bash -c, então o til é expandido pelo shell, como o
  # usuário espera ao escrever um caminho na configuração.
  printf 'CONTEUDO' > "$HOME/.sl-command-tilde-test"
  load_with '{"version":1,"lines":[["command:til"]],"widgets":{"command:til":{"cmd":"cat ~/.sl-command-tilde-test"}}}'
  run _command_render command:til
  rm -f "$HOME/.sl-command-tilde-test"
  [ "$output" = "CONTEUDO" ]
}

@test "kills a hung command at the timeout" {
  # Sem limite, um comando pendurado congelaria a statusline inteira.
  load_with '{"version":1,"lines":[["command:hang"]],"widgets":{"command:hang":{"cmd":"sleep 30; echo tarde","timeout":1}}}'
  start=$SECONDS
  run _command_render command:hang
  elapsed=$(( SECONDS - start ))
  [ "$output" = "" ]
  [ "$elapsed" -lt 10 ]
}

@test "an invalid timeout falls back to the default" {
  load_with '{"version":1,"lines":[["command:t"]],"widgets":{"command:t":{"cmd":"echo ok","timeout":"logo"}}}'
  run _command_render command:t
  [ "$output" = "ok" ]
}

@test "runs the refresh command" {
  load_with '{"version":1,"lines":[["command:r"]],"widgets":{"command:r":{"cmd":"echo lido","refresh":"touch '"$BATS_TEST_TMPDIR"'/refreshed"}}}'
  run _command_render command:r
  [ "$output" = "lido" ]
  # Destacado: pode ainda não ter terminado quando o render volta.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$BATS_TEST_TMPDIR/refreshed" ] && break
    sleep 0.2
  done
  [ -f "$BATS_TEST_TMPDIR/refreshed" ]
}

@test "a slow refresh does not hold up the render" {
  # O ponto do refresh destacado. Se o filho herdasse o pipe da substituição de
  # comando, a statusline esperaria por ele mesmo em segundo plano.
  load_with '{"version":1,"lines":[["command:slow"]],"widgets":{"command:slow":{"cmd":"echo rapido","refresh":"sleep 20"}}}'
  start=$SECONDS
  run _command_render command:slow
  elapsed=$(( SECONDS - start ))
  [ "$output" = "rapido" ]
  [ "$elapsed" -lt 10 ]
}

@test "reuses the cached value within the ttl" {
  load_with '{"version":1,"lines":[["command:c"]],"widgets":{"command:c":{"cmd":"echo original","ttl":3600}}}'
  _command_render command:c >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'command-*' | head -1)"
  [ -n "$cache_file" ]
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run _command_render command:c
  [ "$output" = "PLANTED" ]
}

@test "a zero ttl bypasses the cache" {
  load_with '{"version":1,"lines":[["command:z"]],"widgets":{"command:z":{"cmd":"echo fresco","ttl":0}}}'
  _command_render command:z >/dev/null
  cache_file="$(find "$SL_CACHE_DIR" -type f -name 'command-*' | head -1)"
  stamp="$(head -1 "$cache_file")"
  printf '%s\nPLANTED' "$stamp" > "$cache_file"
  run _command_render command:z
  [ "$output" = "fresco" ]
}

@test "different instances do not share a cache entry" {
  load_with '{"version":1,"lines":[["command:x","command:y"]],"widgets":{"command:x":{"cmd":"echo XIS","ttl":3600},"command:y":{"cmd":"echo IPS","ttl":3600}}}'
  [ "$(_command_render command:x)" = "XIS" ]
  [ "$(_command_render command:y)" = "IPS" ]
}

@test "the slug turns a colon into an underscore" {
  # Dois-pontos não é legal em nome de variável nem de função.
  [ "$(_sl_slug 'command:flow-x')" = "command_flow_x" ]
}
