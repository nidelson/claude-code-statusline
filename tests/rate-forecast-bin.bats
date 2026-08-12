load helper

# Testes do helper de previsão, portados da suíte que ele trazia de fora do
# repositório. Relógio e diretório de estado são injetados por variável de
# ambiente, então nada aqui depende do horário real nem toca o estado de
# produção em ~/.claude.

setup() {
  BIN="$PROJECT_ROOT/bin/rate-forecast.sh"
  TESTDIR="$(mktemp -d)"

  # Base temporal fixa: janela de 5h que começou em 1000000 e corta em 1018000.
  WSTART=1000000
  RESETS=1018000
  WINDOW=18000

  # A de 7 dias corta no mesmo instante, para que as duas possam ser comparadas
  # com o mesmo "agora" sem recalcular nada à mão.
  WINDOW7=604800
}

teardown() {
  rm -rf "$TESTDIR"
}

# rf <now> <used> [resets] — chama o helper na janela de 5h.
rf() {
  local now="$1" used="$2" resets="${3:-$RESETS}"
  CLAUDE_RATE_NOW="$now" CLAUDE_RATE_STATE_DIR="$TESTDIR" \
    bash "$BIN" 5h "$used" "$resets" "$WINDOW"
}

# Nível e projeção, sem o terceiro campo. Um teste de nível não deve quebrar
# quando o bloqueio entra ou sai da linha — quem cobre o terceiro campo são os
# testes da seção própria, no fim do arquivo. `none` sai inteiro porque não tem
# segundo campo.
level_proj() {
  printf '%s' "$1" | cut -d' ' -f1,2
}

# rf7 <now> <used> <resets> — chama o helper na janela de 7 dias.
rf7() {
  CLAUDE_RATE_NOW="$1" CLAUDE_RATE_STATE_DIR="$TESTDIR" \
    bash "$BIN" 7d "$2" "$3" "$WINDOW7"
}

# seed <label> <resets> <ts> <pct> [<ts> <pct> ...] — grava o TSV do zero.
seed() {
  local label="$1" r="$2" f
  f="$TESTDIR/rate-samples-${label}.tsv"
  shift 2
  : > "$f"
  while [ $# -ge 2 ]; do
    printf '%s\t%s\t%s\n' "$1" "$2" "$r" >> "$f"
    shift 2
  done
}

lines() {
  [ -r "$TESTDIR/rate-samples-5h.tsv" ] || return 0
  wc -l < "$TESTDIR/rate-samples-5h.tsv" | tr -d ' '
}

# ── amostragem e estado ──

@test "the first call creates the file with one sample and refuses to project" {
  # elapsed de 600s fica abaixo do mínimo da média, então o veredito é "none".
  run rf $((WSTART + 600)) 20
  [ "$output" = "none" ]
  [ "$(lines)" = "1" ]
}

@test "the write throttle blocks a sample thirty seconds later" {
  rf $((WSTART + 5000)) 20
  rf $((WSTART + 5030)) 21
  [ "$(lines)" = "1" ]
}

@test "the write throttle releases a sample sixty seconds later" {
  rf $((WSTART + 5000)) 20
  rf $((WSTART + 5060)) 21
  [ "$(lines)" = "2" ]
}

@test "a new resets_at truncates the history" {
  seed 5h "$RESETS" $((WSTART + 1000)) 5 $((WSTART + 2000)) 9
  rf $((WSTART + 5000)) 20 999999
  [ "$(lines)" = "1" ]
  [ "$(cat "$TESTDIR/rate-samples-5h.tsv")" = "$((WSTART + 5000))	20	999999" ]
}

@test "pruning drops samples past the cutoff once the file grows" {
  {
    i=0
    while [ $i -lt 249 ]; do
      printf '%s\t%s\t%s\n' $((WSTART + 100)) 5 "$RESETS"
      i=$((i + 1))
    done
    printf '%s\t%s\t%s\n' $((WSTART + 9990)) 30 "$RESETS"
  } > "$TESTDIR/rate-samples-5h.tsv"
  rf $((WSTART + 10000)) 30
  [ "$(lines)" = "1" ]
}

# ── entrada inválida ──

@test "an invalid label refuses and writes no file" {
  run env CLAUDE_RATE_NOW=$((WSTART + 5000)) CLAUDE_RATE_STATE_DIR="$TESTDIR" \
    bash "$BIN" 'bad label' 20 "$RESETS" "$WINDOW"
  [ "$output" = "none" ]
  [ "$(lines)" = "" ]
}

@test "a non-numeric usage refuses" {
  run rf $((WSTART + 5000)) abc
  [ "$output" = "none" ]
}

@test "a non-numeric resets_at refuses" {
  run rf $((WSTART + 5000)) 20 nao-epoch
  [ "$output" = "none" ]
}

@test "a zero-length window refuses" {
  run env CLAUDE_RATE_NOW=$((WSTART + 5000)) CLAUDE_RATE_STATE_DIR="$TESTDIR" \
    bash "$BIN" 5h 20 "$RESETS" 0
  [ "$output" = "none" ]
}

@test "missing arguments refuse" {
  run env CLAUDE_RATE_STATE_DIR="$TESTDIR" bash "$BIN"
  [ "$output" = "none" ]
}

# ── estimador: média da janela ──

@test "an elapsed below the minimum does not project" {
  run rf $((WSTART + 600)) 5
  [ "$output" = "none" ]
}

@test "an elapsed at the boundary projects and the ceiling caps at 999" {
  run rf $((WSTART + 900)) 50
  [ "$(level_proj "$output")" = "crit 999" ]
}

@test "an elapsed longer than the window does not project" {
  run rf $((WSTART + 20000)) 30
  [ "$output" = "none" ]
}

@test "no time left projects the current usage" {
  run rf "$RESETS" 95
  [ "$(level_proj "$output")" = "warn 95" ]
}

# ── estimador: ritmo recente ──

@test "a span below the minimum leaves the average deciding alone" {
  seed 5h "$RESETS" $((WSTART + 13300)) 29
  run rf $((WSTART + 13500)) 30
  [ "$(level_proj "$output")" = "ok 40" ]
}

@test "a zero rate is ok and eases the average's crit down to warn" {
  seed 5h "$RESETS" $((WSTART + 3600)) 30
  run rf $((WSTART + 5400)) 30
  [ "$(level_proj "$output")" = "warn 100" ]
}

# ── regra de convergência ──

@test "ok plus ok is ok" {
  seed 5h "$RESETS" $((WSTART + 11700)) 28
  run rf $((WSTART + 13500)) 30
  [ "$(level_proj "$output")" = "ok 40" ]
}

@test "ok plus warn is warn" {
  seed 5h "$RESETS" $((WSTART + 11700)) 6
  run rf $((WSTART + 13500)) 30
  [ "$(level_proj "$output")" = "warn 90" ]
}

@test "ok plus crit is warn" {
  seed 5h "$RESETS" $((WSTART + 9400)) 10
  run rf $((WSTART + 10000)) 20
  [ "$(level_proj "$output")" = "warn 153" ]
}

@test "warn plus warn is warn" {
  seed 5h "$RESETS" $((WSTART + 4200)) 21
  run rf $((WSTART + 6000)) 30
  [ "$(level_proj "$output")" = "warn 90" ]
}

@test "warn plus crit is crit" {
  seed 5h "$RESETS" $((WSTART + 4200)) 15
  run rf $((WSTART + 6000)) 30
  [ "$(level_proj "$output")" = "crit 130" ]
}

@test "crit plus warn is crit" {
  seed 5h "$RESETS" $((WSTART + 3600)) 21
  run rf $((WSTART + 5400)) 30
  [ "$(level_proj "$output")" = "crit 100" ]
}

@test "crit plus crit is crit" {
  seed 5h "$RESETS" $((WSTART + 3600)) 10
  run rf $((WSTART + 5400)) 30
  [ "$(level_proj "$output")" = "crit 170" ]
}

# ── arco completo: rajada, pausa, retomada ──

@test "hammering away puts both estimators in crit" {
  seed 5h "$RESETS" $((WSTART + 1500)) 2
  run rf $((WSTART + 2700)) 30
  [ "$(level_proj "$output")" = "crit 387" ]
}

@test "a thirty-minute pause eases the average's crit down to warn" {
  seed 5h "$RESETS" $((WSTART + 2700)) 30
  run rf $((WSTART + 4500)) 30
  [ "$(level_proj "$output")" = "warn 120" ]
}

@test "resuming puts the recent rate back into crit" {
  seed 5h "$RESETS" $((WSTART + 3600)) 30
  run rf $((WSTART + 5400)) 45
  [ "$(level_proj "$output")" = "crit 150" ]
}

# ── calibragem por janela ──
#
# Os limiares fixos — 1800s de janela móvel, 300s de span mínimo — são frações
# da janela de 5 horas: `window/10` e `window/60`. Aplicá-los à janela de 7 dias
# extrapola um span de minutos sobre dias de tempo restante, e o menor
# incremento observável vira uma projeção de centenas por cento.

@test "the five-hour window keeps the historical thresholds" {
  # 18000/10 = 1800 e 18000/60 = 300, exatamente os valores fixos anteriores.
  # Todos os casos acima seguem valendo, e este declara a razão.
  seed 5h "$RESETS" $((WSTART + 13300)) 29
  run rf $((WSTART + 13500)) 30
  [ "$(level_proj "$output")" = "ok 40" ]
}

@test "a minutes-long span does not project hundreds of percent over seven days" {
  # Reprodução do caso observado: uso em 25%, um único incremento de 1% visto
  # sete minutos atrás e três dias de janela pela frente.
  local now=1786418401 resets=1786701600
  seed 7d "$resets" $((now - 440)) 24
  run rf7 "$now" 25 "$resets"
  [ "$(level_proj "$output")" = "ok 47" ]
}

@test "seven days still projects once the span is long enough to mean something" {
  # O limiar maior não emudece o estimador recente, apenas exige que ele meça
  # sobre um span que signifique algo. Quatro horas de subida real continuam
  # projetando alto; o nível sai `warn` e não `crit` porque a média da janela
  # ainda está em 47, e divergência entre os dois é incerteza.
  local now=1786418401 resets=1786701600
  seed 7d "$resets" $((now - 14400)) 5
  run rf7 "$now" 25 "$resets"
  [ "$(level_proj "$output")" = "warn 418" ]
}

@test "an explicit lookback still overrides the derived one" {
  local now=1786418401 resets=1786701600
  seed 7d "$resets" $((now - 440)) 24
  run env CLAUDE_RATE_LOOKBACK=1800 CLAUDE_RATE_MIN_SPAN=300 \
    CLAUDE_RATE_NOW="$now" CLAUDE_RATE_STATE_DIR="$TESTDIR" \
    bash "$BIN" 7d 25 "$resets" "$WINDOW7"
  [ "$(level_proj "$output")" = "warn 669" ]
}

@test "a garbage lookback falls back to the derived one instead of breaking" {
  local now=1786418401 resets=1786701600
  seed 7d "$resets" $((now - 440)) 24
  run env CLAUDE_RATE_LOOKBACK=abc CLAUDE_RATE_MIN_SPAN=abc \
    CLAUDE_RATE_NOW="$now" CLAUDE_RATE_STATE_DIR="$TESTDIR" \
    bash "$BIN" 7d 25 "$resets" "$WINDOW7"
  [ "$(level_proj "$output")" = "ok 47" ]
}

@test "a tiny window never derives thresholds below the historical floor" {
  # Numa janela de 600s, `window/60` daria um span mínimo de 10s — curto demais
  # para medir coisa alguma. O piso de 300s recusa este span de 100s; sem ele, o
  # estimador aceitaria a amostra e projetaria em cima de dez segundos de sinal.
  seed 5h 1000600 $((WSTART + 300)) 5
  run env CLAUDE_RATE_NOW=$((WSTART + 400)) CLAUDE_RATE_STATE_DIR="$TESTDIR" \
    bash "$BIN" 5h 20 1000600 600
  [ "$output" = "none" ]
}

@test "pruning does not rewrite a seven-day file that is merely at its normal size" {
  # Em regime a janela de 7 dias retém milhares de amostras. Um gatilho fixo em
  # 200 linhas dispararia a poda a cada repaint, reescrevendo o arquivo inteiro
  # sem descartar nada.
  local now=1786418401 resets=1786701600 f="$TESTDIR/rate-samples-7d.tsv"
  {
    i=0
    while [ $i -lt 400 ]; do
      printf '%s\t%s\t%s\n' $((now - 30000 + i * 60)) 24 "$resets"
      i=$((i + 1))
    done
  } > "$f"
  rf7 "$now" 25 "$resets"
  # A amostra nova entra; nenhuma das 400 é descartada, porque todas cabem na
  # retenção derivada da janela de 7 dias.
  [ "$(wc -l < "$f" | tr -d ' ')" = "401" ]
}

# ── Previsão de bloqueio ─────────────────────────────────────────────────────
#
# Terceiro campo, opcional. `→118%` diz que a janela estoura antes de resetar; a
# pergunta seguinte é a única que muda o que fazer hoje: estoura quando?
#
# A base é sempre a mesma para poder conferir a conta à mão: now=1010800 deixa
# 10800s decorridos da janela de 18000 e 7200s até o reset em 1018000.

# blocked <output> — o terceiro campo, ou vazio.
blocked() {
  printf '%s' "$1" | awk '{print $3}'
}

@test "a projection over a hundred says when the block lands" {
  # 70% em 3h é 0,0064815 pt/s. Faltam 30 pontos, logo 4628s — dentro dos 7200
  # que restam até o reset.
  run rf 1010800 70
  [ "$(level_proj "$output")" = "crit 117" ]
  [ "$(blocked "$output")" = "1015428" ]
}

@test "the block lands before the reset" {
  run rf 1010800 70
  [ "$(blocked "$output")" -lt 1018000 ]
}

# Os dois testes abaixo afirmam uma AUSÊNCIA, e ausência passa sozinha quando o
# recurso inteiro está quebrado. O par no fim de cada um é a contraprova: mesmo
# helper, entrada que precisa produzir o campo.
@test "a projection under a hundred says nothing about blocking" {
  run rf 1010800 50
  [ "$(printf '%s' "$output" | awk '{print NF}')" = "2" ]
  [ "$(level_proj "$output")" = "ok 83" ]
  run rf 1010800 70
  [ "$(printf '%s' "$output" | awk '{print NF}')" = "3" ]
}

@test "usage already at the limit blocks now" {
  # Sem tempo restante para gastar: o bloqueio é o próprio instante da leitura.
  run rf 1010800 100
  [ "$(blocked "$output")" = "1010800" ]
}

@test "no projection at all carries no block" {
  run rf 1000100 40
  [ "$(printf '%s' "$output" | awk '{print NF}')" = "1" ]
  [ "$output" = "none" ]
  run rf 1010800 70
  [ "$(printf '%s' "$output" | awk '{print NF}')" = "3" ]
}

@test "a faster recent rate moves the block earlier" {
  # O ritmo do bloqueio é o mesmo que gerou a projeção reportada — a maior das
  # duas. Uma rajada recente antecipa as duas coisas juntas.
  seed 5h "$RESETS" 1010200 60 1010500 65 1010800 70
  run rf 1010800 70
  [ "$(blocked "$output")" -lt 1015428 ]
}
