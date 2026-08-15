load helper

# O launcher é o único arquivo do plugin que o `settings.json` referencia, e um
# defeito aqui não degrada a statusline: apaga. Por isso cada caso confere o que
# realmente executou, não apenas que houve saída.

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  LAUNCHER="$PROJECT_ROOT/bin/launcher.sh"
  FIXTURE="$PROJECT_ROOT/tests/fixtures/session.json"
}

# Instala um statusline.sh falso numa versão do cache. Falso e não real porque o
# que está sob teste é a ESCOLHA do alvo — um alvo que se identifica torna a
# escolha observável.
fake_install() {
  local marketplace=$1 version=$2
  local dir="$CLAUDE_CONFIG_DIR/plugins/cache/$marketplace/claude-code-statusline/$version/bin"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "alvo=%%s/%%s\\n" "%s" "%s"\n' \
    "$marketplace" "$version" > "$dir/statusline.sh"
}

fake_checkout() {
  local dir="$BATS_TEST_TMPDIR/$1/bin"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "alvo=checkout-%%s\\n" "%s"\n' \
    "$1" > "$dir/statusline.sh"
  printf '%s' "$BATS_TEST_TMPDIR/$1"
}

@test "warns instead of printing nothing when nothing is installed" {
  run bash "$LAUNCHER" < "$FIXTURE"
  [ "$status" -eq 0 ]
  # Casa pelo caminho da flag, que só esta mensagem cita — a outra cita o
  # destino lido de dentro dela. Escolhido por ser ASCII: um glob sobre o texto
  # acentuado dependeria do locale do shell, e no Git Bash isso não é dado.
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/statusline-dev"* ]]
}

@test "runs the installed version when no flag is set" {
  fake_install mkt 0.2.0
  run bash "$LAUNCHER" < "$FIXTURE"
  [ "$output" = "alvo=mkt/0.2.0" ]
}

@test "picks the highest version, not the lexicographically largest" {
  fake_install mkt 0.9.0
  fake_install mkt 0.10.0
  run bash "$LAUNCHER" < "$FIXTURE"
  # Lexicograficamente 0.9.0 vence; é justamente o erro que `sort -V` evita.
  [ "$output" = "alvo=mkt/0.10.0" ]
}

@test "finds the install under any marketplace" {
  fake_install outro-dono 1.0.0
  run bash "$LAUNCHER" < "$FIXTURE"
  [ "$output" = "alvo=outro-dono/1.0.0" ]
}

@test "the dev flag wins over the installed version" {
  fake_install mkt 9.9.9
  root=$(fake_checkout meu-checkout)
  printf '%s\n' "$root" > "$CLAUDE_CONFIG_DIR/statusline-dev"
  # Contraprova: sem a flag, o alvo é o cache — se a asserção seguinte passasse
  # por o launcher estar quebrado, esta linha teria falhado antes.
  run bash "$LAUNCHER" < "$FIXTURE"
  [ "$output" = "alvo=checkout-meu-checkout" ]
}

@test "expands a tilde in the flag, which the shell does not" {
  fake_checkout til > /dev/null
  printf '~/til\n' > "$CLAUDE_CONFIG_DIR/statusline-dev"
  # O checkout falso vive em BATS_TEST_TMPDIR; apontar HOME para lá é o que
  # torna `~/til` um caminho real sem escrever no HOME de verdade.
  run env HOME="$BATS_TEST_TMPDIR" bash "$LAUNCHER" < "$FIXTURE"
  [ "$output" = "alvo=checkout-til" ]
}

@test "ignores everything after the first line of the flag" {
  root=$(fake_checkout comentado)
  printf '%s\n# ligado para testar o widget de sprint\n' "$root" \
    > "$CLAUDE_CONFIG_DIR/statusline-dev"
  run bash "$LAUNCHER" < "$FIXTURE"
  [ "$output" = "alvo=checkout-comentado" ]
}

@test "a flag pointing nowhere warns instead of falling back" {
  fake_install mkt 0.2.0
  printf '/nao/existe\n' > "$CLAUDE_CONFIG_DIR/statusline-dev"
  run bash "$LAUNCHER" < "$FIXTURE"
  # Cair para produção em silêncio seria o pior desfecho: a mudança sob teste
  # não apareceria e a statusline seguiria plausível.
  [[ "$output" != *"alvo=mkt"* ]]
  [[ "$output" == *"statusline-dev aponta para /nao/existe"* ]]
}

@test "an empty flag warns instead of running anything" {
  fake_install mkt 0.2.0
  : > "$CLAUDE_CONFIG_DIR/statusline-dev"
  [[ "$(bash "$LAUNCHER" < "$FIXTURE")" != *"alvo="* ]]
  run bash "$LAUNCHER" < "$FIXTURE"
  [[ "$output" == *"<vazio>"* ]]
}

@test "stdin reaches the target intact" {
  local dir="$CLAUDE_CONFIG_DIR/plugins/cache/mkt/claude-code-statusline/0.2.0/bin"
  mkdir -p "$dir"
  # O alvo real consome o JSON de sessão pelo stdin; se o launcher o tivesse
  # lido, chegaria vazio aqui.
  printf '#!/usr/bin/env bash\nwc -c\n' > "$dir/statusline.sh"
  run bash "$LAUNCHER" < "$FIXTURE"
  [ "$(printf '%s' "$output" | tr -d ' ')" = "$(wc -c < "$FIXTURE" | tr -d ' ')" ]
}
