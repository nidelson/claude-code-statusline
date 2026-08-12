# cache — countdown de expiração do prompt cache — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Somar ao widget `cache` um segundo número — quanto falta para o prompt cache expirar — trocando o rótulo `cache:` pelo glifo `☁`.

**Architecture:** O carimbo de tempo da última resposta e o TTL contratado não vêm no payload; saem do transcript JSONL, cujo caminho o payload entrega em `.transcript_path`. Uma sonda lê as últimas 400 linhas do arquivo com `jq`, embrulhada em `cache_by_mtime` para só rodar quando o arquivo muda, e devolve dois campos. O widget passa a montar percentual e countdown como partes independentes: cada uma pode faltar sem levar a outra junto.

**Tech Stack:** bash 3.2, `jq`, `bats-core`.

**Spec:** [2026-08-12-cache-ttl-countdown-design.md](../specs/2026-08-12-cache-ttl-countdown-design.md)

## Global Constraints

- **Shell alvo: bash 3.2.57.** Sem `declare -A`, sem `${var^^}`, sem `mapfile`, sem `&>>`.
- **Nunca usar `set -e` nem `set -u`.** Erro se trata no ponto de ocorrência.
- **Dependências de runtime: apenas `jq` e `git`.** Nada além disso.
- **A statusline nunca pode desaparecer.** Qualquer falha degrada para saída parcial.
- **Idioma:** comentários, documentação e mensagens de commit em **português**. Identificadores em inglês. `--desc` de widget em inglês.
- **Nomes de teste `@test` obrigatoriamente em inglês ASCII.** O bats força `LC_ALL=C` e converte o título em nome de função; acento vira byte inválido e o teste falha com `unknown test name`.
- **Tempo é entrada, não relógio.** Toda leitura de hora passa por `SL_NOW` quando a variável está definida.
- **Contraprova em toda asserção de ausência.** Um teste que afirma que algo não aparece passa sozinho quando a funcionalidade inteira está quebrada. Renderizar duas vezes no mesmo teste — uma no caso sob teste, uma num caso vizinho onde a coisa tem de aparecer.
- **Verde local não é verde de CI.** No bash 3.2 o `errexit` não dispara em `[[ ]]` dentro de função, então no macOS só a última asserção de cada teste é cobrada. O job Linux do CI é o portão real. Ver `tests/helper.bash`.

---

### Task 1: `SL_TRANSCRIPT` no parse do stdin

O payload sempre entrega `.transcript_path` e nenhum widget o lê hoje. Sem essa variável nada mais do plano funciona.

**Files:**
- Modify: `lib/stdin.sh:11-42` (lista de campos do `jq`) e `lib/stdin.sh:52-56` (fallback)
- Test: `tests/stdin.bats`

**Interfaces:**
- Consumes: nada.
- Produces: `SL_TRANSCRIPT`, string. Caminho absoluto do transcript JSONL, ou `""` quando o campo falta ou o `jq` falha.

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar a `tests/stdin.bats`:

```bash
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
  sl_parse_stdin 'não é json'
  [ "$SL_TRANSCRIPT" = "" ]
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `bats tests/stdin.bats`
Expected: FAIL nos três — `SL_TRANSCRIPT` não existe, a comparação com `/tmp/session.jsonl` dá vazio.

- [ ] **Step 3: Implementar**

Em `lib/stdin.sh`, acrescentar o campo logo depois de `SL_CWD` (linha 16), mantendo a vírgula da lista:

```bash
    @sh "SL_CWD=\(.workspace.current_dir // .cwd // "")",
    # O caminho do transcript. É o único jeito de saber quando foi a última
    # troca: o payload traz os contadores de cache mas nenhum carimbo de tempo.
    @sh "SL_TRANSCRIPT=\(.transcript_path // "")",
```

E no bloco de fallback (linha 53), junto das outras zeradas:

```bash
    SL_LINES_ADDED=0; SL_LINES_REMOVED=0; SL_CWD=""; SL_TRANSCRIPT=""
```

- [ ] **Step 4: Rodar para ver passar**

Run: `bats tests/stdin.bats`
Expected: PASS, todos.

- [ ] **Step 5: Commit**

```bash
git add lib/stdin.sh tests/stdin.bats
git commit -m "feat: expõe SL_TRANSCRIPT no parse do stdin

O payload traz .transcript_path e nenhum widget o lia. É o único caminho
para o carimbo de tempo da última troca, que o payload não entrega."
```

---

### Task 2: `sl_fmt_ttl`, a regressiva com segundos

`sl_fmt_countdown` tem piso `<1m`. Numa janela de cinco minutos os últimos sessenta segundos são exatamente os que decidem se vale mandar o prompt agora.

**Files:**
- Modify: `lib/timefmt.sh` (função nova, depois de `sl_fmt_countdown`)
- Test: `tests/timefmt.bats`

**Interfaces:**
- Consumes: nada.
- Produces: `sl_fmt_ttl <segundos>` → imprime `1h2m` | `1h` | `4m12s` | `4m` | `47s`. Entrada não numérica ou vazia imprime `0s`. Nunca retorna diferente de zero.

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar a `tests/timefmt.bats`:

```bash
@test "ttl format keeps seconds below a minute" {
  [ "$(sl_fmt_ttl 47)" = "47s" ]
}

@test "ttl format pairs minutes with seconds" {
  [ "$(sl_fmt_ttl 252)" = "4m12s" ]
}

@test "ttl format drops zeroed seconds" {
  [ "$(sl_fmt_ttl 240)" = "4m" ]
}

@test "ttl format pairs hours with minutes" {
  [ "$(sl_fmt_ttl 3720)" = "1h2m" ]
}

@test "ttl format drops zeroed minutes" {
  [ "$(sl_fmt_ttl 3600)" = "1h" ]
}

@test "ttl format reads zero as zero seconds" {
  [ "$(sl_fmt_ttl 0)" = "0s" ]
}

@test "ttl format survives junk" {
  [ "$(sl_fmt_ttl abc)" = "0s" ]
  [ "$(sl_fmt_ttl '')" = "0s" ]
}

@test "the coarse countdown keeps its sub-minute floor" {
  # Contraprova de convivência: sl_fmt_ttl não pode ter sido implementado
  # trocando o piso da função existente. O reset de 5h do rate-forecast
  # depende de "<1m" — com segundos ali a linha pisca a cada repaint.
  [ "$(sl_fmt_countdown 47)" = "<1m" ]
  [ "$(sl_fmt_ttl 47)" = "47s" ]
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `bats tests/timefmt.bats`
Expected: FAIL com `sl_fmt_ttl: command not found` nos sete primeiros; o oitavo falha na segunda linha.

- [ ] **Step 3: Implementar**

Em `lib/timefmt.sh`, logo abaixo de `sl_fmt_countdown` (após a linha 122):

```bash
# A mesma regra de duas unidades, uma faixa abaixo: horas com minutos, minutos
# com segundos, segundos sozinhos.
#
# Existe separada de sl_fmt_countdown, e não como um parâmetro dela, porque as
# duas discordam de propósito no piso. Lá, `<1m` é escolha: o reset da janela de
# cinco horas não fica melhor sabendo que faltam 47 segundos, e um número que
# muda a cada repaint numa posição que ninguém consulta é ruído. Aqui, os
# últimos sessenta segundos são o único momento em que a informação muda uma
# decisão — se dá tempo de escrever o próximo prompt antes de o cache esfriar.
sl_fmt_ttl() {
  local rem="$1" h m s
  case "$rem" in
    ''|*[!0-9]*) printf '0s'; return 0 ;;
  esac
  h=$(( rem / 3600 ))
  m=$(( (rem % 3600) / 60 ))
  s=$(( rem % 60 ))
  if [ "$h" -gt 0 ]; then
    if [ "$m" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
    else                    printf '%dh' "$h"
    fi
  elif [ "$m" -gt 0 ]; then
    if [ "$s" -gt 0 ]; then printf '%dm%ds' "$m" "$s"
    else                    printf '%dm' "$m"
    fi
  else                      printf '%ds' "$s"
  fi
}
```

- [ ] **Step 4: Rodar para ver passar**

Run: `bats tests/timefmt.bats`
Expected: PASS, todos.

- [ ] **Step 5: Commit**

```bash
git add lib/timefmt.sh tests/timefmt.bats
git commit -m "feat: sl_fmt_ttl, regressiva com resolução de segundo

sl_fmt_countdown para em <1m, que serve ao reset de 5h e não serve a uma
janela de cache de 5min: ali o último minuto é o que decide."
```

---

### Task 3: sonda do transcript

Lê as últimas 400 linhas e devolve carimbo de tempo e TTL. Sem render ainda — a tarefa entrega uma função testável isoladamente.

**Files:**
- Modify: `widgets/cache.sh` (constantes e funções novas; o render fica intacto)
- Test: `tests/widgets/cache.bats`

**Interfaces:**
- Consumes: `SL_TRANSCRIPT` (Task 1); `cache_by_mtime` de `lib/cache.sh`.
- Produces:
  - `SL_CACHE_TAIL_LINES=400`, `SL_CACHE_TTL_WARN=180`, `SL_CACHE_TTL_CRIT=60`.
  - `_cache_probe_compute <arquivo>` → imprime `"<timestamp ISO> <ttl_segundos>"` ou nada.
  - `_cache_probe` → o mesmo, com cache por mtime, lendo `SL_TRANSCRIPT`. Retorna 1 quando não há o que devolver.
  - `_cache_now` → epoch, de `SL_NOW` quando definido.

- [ ] **Step 1: Corrigir o setup do teste antes de qualquer coisa**

`tests/widgets/cache.bats` não carrega `lib/timefmt.sh` nem `lib/cache.sh`. Sem isso as funções novas somem em silêncio, e no bash 3.2 os testes passam mesmo assim — foi exatamente o que aconteceu na PR #11 com `flow.bats`.

Substituir o `setup()` inteiro por:

```bash
setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/timefmt.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/widgets/cache.sh"
  SL_CONFIG_RAW=""
  SL_CACHE_READ=700
  SL_CACHE_CREATE=200
  SL_INPUT_TOKENS=100
  SL_TRANSCRIPT=""
  # O cache em disco não pode sair do diretório do teste.
  SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  # Relógio fixo. 1800000000 é 2027-01-15T08:00:00Z.
  SL_NOW=1800000000
  SL_T_N=0
}

# Escreve um transcript e aponta SL_TRANSCRIPT para ele.
#
# Cada chamada usa um nome novo. O cache_by_mtime tem resolução de um segundo,
# então dois transcritos diferentes escritos no mesmo segundo sobre o mesmo
# caminho colidiriam — e a chave do cache é derivada do caminho.
write_transcript() {
  SL_T_N=$(( SL_T_N + 1 ))
  SL_TRANSCRIPT="$BATS_TEST_TMPDIR/tr$SL_T_N.jsonl"
  printf '%s\n' "$@" > "$SL_TRANSCRIPT"
}

# Uma entrada de assistant: carimbo, gravação de 1h, gravação de 5m.
turn() {
  printf '{"type":"assistant","message":{"usage":{"cache_read_input_tokens":100,"cache_creation_input_tokens":%d,"cache_creation":{"ephemeral_1h_input_tokens":%d,"ephemeral_5m_input_tokens":%d}}},"timestamp":"%s"}' \
    "$(( $2 + $3 ))" "$2" "$3" "$1"
}
```

- [ ] **Step 2: Escrever os testes que falham**

Acrescentar a `tests/widgets/cache.bats`:

```bash
@test "the probe reads timestamp and one hour ttl" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe reads a five minute ttl" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 300" ]
}

@test "the probe takes the timestamp from the last turn" {
  write_transcript \
    "$(turn 2027-01-15T07:00:00Z 500 0)" \
    "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe takes the ttl from the last turn that wrote" {
  # A última troca foi servida inteira do cache e não gravou nada, então não
  # identifica a janela; quem identifica é a anterior.
  write_transcript \
    "$(turn 2027-01-15T07:00:00Z 0 500)" \
    "$(turn 2027-01-15T07:58:00Z 0 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 300" ]
}

@test "the probe ignores lines that are not assistant turns" {
  write_transcript \
    "$(turn 2027-01-15T07:00:00Z 500 0)" \
    '{"type":"user","timestamp":"2027-01-15T09:00:00Z"}' \
    '{"type":"attachment","timestamp":"2027-01-15T09:00:00Z"}'
  run _cache_probe
  [ "$output" = "2027-01-15T07:00:00Z 3600" ]
}

@test "the probe survives a truncated last line" {
  # O transcript da sessão em curso está sendo escrito enquanto se lê.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  printf '{"type":"assis' >> "$SL_TRANSCRIPT"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe gives nothing when no turn ever wrote" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 0)"
  run _cache_probe
  [ "$output" = "" ]
  # Contraprova: a mesma sonda com uma gravação presente tem de responder.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe gives nothing when the transcript is missing" {
  SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run _cache_probe
  [ "$output" = "" ]
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the probe gives nothing when the transcript path is empty" {
  SL_TRANSCRIPT=""
  run _cache_probe
  [ "$output" = "" ]
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run _cache_probe
  [ "$output" = "2027-01-15T07:58:00Z 3600" ]
}

@test "the clock comes from SL_NOW when it is set" {
  SL_NOW=1234567890
  run _cache_now
  [ "$output" = "1234567890" ]
}
```

- [ ] **Step 3: Rodar para ver falhar**

Run: `bats tests/widgets/cache.bats`
Expected: FAIL com `_cache_probe: command not found` / `_cache_now: command not found`.

- [ ] **Step 4: Implementar**

Em `widgets/cache.sh`, depois de `SL_CACHE_DEFAULT_LABEL` (linha 29):

```bash
# Quantas linhas do fim do transcript a sonda lê. Medido num transcript de 24 MB
# e 10.780 linhas: a maior corrida consecutiva sem nenhuma entrada `assistant`
# foi 57, e a leitura inteira custou 7 ms. A janela dá margem de sete vezes.
SL_CACHE_TAIL_LINES=400

# Limites do countdown, em segundos, absolutos e não proporcionais ao TTL. A
# pergunta que ele responde — dá tempo de escrever o próximo prompt antes de o
# cache esfriar? — tem duração humana: quem digita leva de trinta a sessenta
# segundos, e isso não muda porque a janela contratada é de uma hora.
SL_CACHE_TTL_WARN=180
SL_CACHE_TTL_CRIT=60
```

E, depois de `_cache_int`:

```bash
# Tempo é entrada, não relógio: sem isso a suíte falharia sozinha de madrugada,
# ou só no CI, que roda em UTC.
_cache_now() {
  if [ -n "$SL_NOW" ]; then
    printf '%s' "$SL_NOW"
  else
    date +%s
  fi
}

# `<timestamp ISO> <ttl em segundos>` da última troca, ou nada.
#
# O carimbo sai da última entrada `assistant`; o TTL, da última que GRAVOU. Nem
# sempre são a mesma: uma troca servida inteira do cache não grava nada e não
# identifica a janela contratada.
#
# O TTL é detectado, não configurado. `ephemeral_1h_input_tokens` e
# `ephemeral_5m_input_tokens` dizem qual janela a conta tem, e o mesmo usuário
# alterna entre uma máquina com uma hora e outra com cinco minutos.
#
# O parse é `-R` linha a linha com `fromjson?` em vez de `-s`: a última linha do
# transcript da sessão em curso pode estar pela metade no instante da leitura, e
# `jq -s` recusaria o arquivo inteiro por causa dela.
_cache_probe_compute() {
  tail -n "$SL_CACHE_TAIL_LINES" "$1" 2>/dev/null | jq -Rrs '
    [ split("\n")[]
      | fromjson?
      | select(.type == "assistant" and .message.usage != null) ] as $a
    | ($a | last) as $t
    | ([ $a[]
         | select(((.message.usage.cache_creation.ephemeral_1h_input_tokens // 0)
                 + (.message.usage.cache_creation.ephemeral_5m_input_tokens // 0)) > 0)
       ] | last) as $w
    | if $t == null or $w == null or ($t.timestamp | not) then empty
      else "\($t.timestamp) \(
             if (($w.message.usage.cache_creation.ephemeral_1h_input_tokens // 0) > 0)
             then 3600 else 300 end)"
      end' 2>/dev/null
}

_cache_probe() {
  local key out
  [ -n "$SL_TRANSCRIPT" ] || return 1
  [ -f "$SL_TRANSCRIPT" ] || return 1
  # A chave não inclui SL_NOW, ao contrário da do flow: o que se guarda aqui é a
  # leitura do arquivo, que não depende do relógio. A regressiva é recalculada a
  # cada repaint sobre o valor guardado, sem custo de processo.
  key="cache-ttl-$(printf '%s' "$SL_TRANSCRIPT" | cksum | cut -d' ' -f1)"
  out="$(cache_by_mtime "$key" "$SL_TRANSCRIPT" _cache_probe_compute "$SL_TRANSCRIPT")"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}
```

- [ ] **Step 5: Rodar para ver passar**

Run: `bats tests/widgets/cache.bats`
Expected: PASS, todos — inclusive os que já existiam, que a Task 3 não toca.

- [ ] **Step 6: Verificar o custo real, fora do bats**

Run:
```bash
TR="$(ls -t ~/.claude/projects/*/*.jsonl | head -1)"
time (tail -n 400 "$TR" | jq -Rrs '[ split("\n")[] | fromjson? | select(.type=="assistant" and .message.usage != null) ] | length')
```
Expected: um número maior que zero, em menos de 50 ms. Se der zero, a janela de 400 linhas é curta para transcripts reais e `SL_CACHE_TAIL_LINES` precisa subir.

- [ ] **Step 7: Commit**

```bash
git add widgets/cache.sh tests/widgets/cache.bats
git commit -m "feat: sonda o transcript para carimbo e TTL do cache

O payload traz os contadores de cache mas nenhum carimbo de tempo. A sonda
lê as últimas 400 linhas do transcript, cacheada por mtime, e devolve
quando foi a última troca e qual janela a conta tem — 1h ou 5min,
detectado de ephemeral_1h/5m, não configurado.

O setup de cache.bats não carregava timefmt.sh nem cache.sh. Corrigido no
mesmo commit: sem isso as funções novas sumiriam em silêncio e os testes
passariam mesmo assim, como aconteceu em flow.bats na PR #11."
```

---

### Task 4: countdown no render

Junta a sonda ao widget: glifo, segunda cor, e a separação entre percentual e countdown.

**Files:**
- Modify: `widgets/cache.sh:38-64` (`widget_cache_render`) e o cabeçalho de comentário
- Test: `tests/widgets/cache.bats`

**Interfaces:**
- Consumes: `_cache_probe`, `_cache_now`, `SL_CACHE_TTL_WARN`, `SL_CACHE_TTL_CRIT` (Task 3); `sl_fmt_ttl` (Task 2); `sl_epoch_normalize` de `lib/timefmt.sh`.
- Produces: `_cache_countdown` → imprime o pedaço colorido do countdown, ou retorna 1. `widget_cache_render` passa a emitir `☁ 100%·4m12s`.

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar a `tests/widgets/cache.bats`. `SL_NOW=1800000000` é `2027-01-15T08:00:00Z`; um carimbo de `07:58:00Z` com TTL de 300s expira às `08:03:00Z`, ou seja, faltam 180s.

```bash
@test "shows the countdown next to the hit rate" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%·3m" ]
}

@test "the countdown carries seconds" {
  # 07:57:48Z + 300s expira 08:02:48Z; faltam 168s = 2m48s.
  write_transcript "$(turn 2027-01-15T07:57:48Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·2m48s"* ]]
}

@test "a one hour ttl counts from the same stamp" {
  # 07:58:00Z + 3600s expira 08:58:00Z; faltam 3480s = 58m.
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
}

@test "an expired cache reads as cold" {
  # 07:50:00Z + 300s expirou às 07:55:00Z, cinco minutos atrás.
  write_transcript "$(turn 2027-01-15T07:50:00Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·cold"* ]]
}

@test "the countdown is green with more than three minutes left" {
  # 07:58:01Z + 300s deixa 181s.
  write_transcript "$(turn 2027-01-15T07:58:01Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[32m'*"3m1s"* ]]
}

@test "the countdown turns yellow under three minutes" {
  # 07:58:00Z + 300s deixa 180s, que já não é "mais de três minutos".
  write_transcript "$(turn 2027-01-15T07:57:59Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[33m'*"2m59s"* ]]
}

@test "the countdown turns red under one minute" {
  # 07:55:59Z + 300s deixa 59s.
  write_transcript "$(turn 2027-01-15T07:55:59Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[31m'*"59s"* ]]
}

@test "a cold cache is red" {
  write_transcript "$(turn 2027-01-15T07:50:00Z 0 500)"
  run widget_cache_render
  [[ "$output" == *$'\033[31m'*"cold"* ]]
}

@test "the countdown survives without a hit rate" {
  # current_usage vem null entre trocas — e é justamente parado, entre trocas,
  # que o countdown decide alguma coisa.
  SL_CACHE_READ=0
  SL_CACHE_CREATE=0
  SL_INPUT_TOKENS=0
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 3m" ]
}

@test "the hit rate survives without a countdown" {
  SL_TRANSCRIPT=""
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%" ]
}

@test "renders nothing when neither side has anything to say" {
  SL_CACHE_READ=0
  SL_CACHE_CREATE=0
  SL_INPUT_TOKENS=0
  SL_TRANSCRIPT=""
  run widget_cache_render
  [ "$output" = "" ]
  # Contraprova: com o transcript de volta, o widget tem de reaparecer.
  write_transcript "$(turn 2027-01-15T07:58:00Z 0 500)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 3m" ]
}

@test "the glyph carries a space" {
  # ☁ tem largura ambígua em Unicode: colado num dígito disputa a mesma célula
  # em boa parte dos terminais. Mesmo motivo do ⟳ em sl_stamp_label.
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == "☁ "* ]]
}
```

- [ ] **Step 2: Ajustar os dois testes existentes que o glifo quebra**

`labels the number` e `the label option replaces the prefix` assumem o rótulo de texto colado no percentual. Substituir os dois por:

```bash
@test "marks the number with the cloud glyph" {
  # Três percentuais podem dividir a mesma linha — contexto, rate limit e este.
  # Sem marca não há como saber qual é qual.
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"☁"* ]]
}

@test "the label option replaces the prefix when icons are off" {
  SL_CONFIG_ICONS=0
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"label":"c:"}}}'
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"c:70%"* ]]
  [[ "$output" != *"cache:"* ]]
}
```

E `an empty label drops the prefix entirely` ganha `SL_CONFIG_ICONS=0` como primeira linha do corpo, pelo mesmo motivo.

- [ ] **Step 3: Rodar para ver falhar**

Run: `bats tests/widgets/cache.bats`
Expected: FAIL — a saída ainda é `cache:70%`, sem glifo e sem countdown.

- [ ] **Step 4: Implementar**

Substituir `widget_cache_render` inteira e acrescentar `_cache_countdown` antes dela:

```bash
# O pedaço do countdown, já colorido, ou 1 quando não há o que dizer.
#
# A cor é a informação: verde é "manda quando quiser", vermelho é "manda agora
# ou pague a gravação de novo". Por isso o widget passa a imprimir duas cores —
# o percentual tem a semântica dele, o tempo tem a sua.
_cache_countdown() {
  local raw ts ttl epoch rem text color
  raw="$(_cache_probe)" || return 1
  # set -- divide na primeira palavra sem precisar de array.
  set -- $raw
  ts="$1"; ttl="$2"
  case "$ttl" in ''|*[!0-9]*) return 1 ;; esac
  epoch="$(sl_epoch_normalize "$ts")" || return 1
  rem=$(( epoch + ttl - $(_cache_now) ))

  if [ "$rem" -le 0 ]; then
    text="cold"
    color="$(sl_color red)"
  else
    text="$(sl_fmt_ttl "$rem")"
    if   [ "$rem" -lt "$SL_CACHE_TTL_CRIT" ]; then color="$(sl_color red)"
    elif [ "$rem" -lt "$SL_CACHE_TTL_WARN" ]; then color="$(sl_color yellow)"
    else                                           color="$(sl_color green)"
    fi
  fi

  printf '%s%s%s' "$color" "$text" "$SL_RESET"
}

widget_cache_render() {
  local read_tok create_tok fresh_tok total pct color
  local mark label pct_part cd_part out

  read_tok="$(_cache_int "$SL_CACHE_READ")"
  create_tok="$(_cache_int "$SL_CACHE_CREATE")"
  fresh_tok="$(_cache_int "$SL_INPUT_TOKENS")"
  total=$(( read_tok + create_tok + fresh_tok ))

  # Taxa de acerto sobre zero token não é 0%, é indefinida. Mostrar "0%" no
  # começo da sessão seria afirmar que o cache falhou, o que não aconteceu.
  #
  # O que mudou: isso já não derruba o widget inteiro. current_usage vem null
  # entre trocas, e é parado entre trocas que o countdown decide alguma coisa —
  # se ele herdasse este retorno, sumiria exatamente na hora de servir.
  pct_part=""
  if [ "$total" -gt 0 ]; then
    if pct="$(sl_pct "$read_tok" "$total")"; then
      if   [ "$pct" -ge 70 ]; then color="$(sl_color green)"
      elif [ "$pct" -ge 30 ]; then color="$(sl_color yellow)"
      else                         color="$(sl_color red)"
      fi
      pct_part="${color}${pct}%${SL_RESET}"
    fi
  fi

  cd_part="$(_cache_countdown)" || cd_part=""

  [ -n "$pct_part" ] || [ -n "$cd_part" ] || return 0

  # O glifo é U+2601, o mesmo que docs/legacy/statusline-2.sh:92 usava aqui. O
  # statusline.sh mais antigo usava U+F0C2, área privada da Nerd Font, que este
  # projeto rejeita por depender de fonte instalada.
  #
  # O espaço depois não é folga: largura ambígua colada em dígito disputa a
  # mesma célula em boa parte dos terminais, como o ⟳ e o ⏱.
  #
  # A marca sai dim, não na cor do número: com duas cores no widget, um prefixo
  # que herdasse uma delas afirmaria que ela vale para o conjunto.
  if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then
    mark="☁ "
  else
    mark="$(sl_config_widget_opt cache label "$SL_CACHE_DEFAULT_LABEL")"
  fi

  out=""
  [ -n "$mark" ] && out="${SL_DIM}${mark}${SL_RESET}"

  if [ -n "$pct_part" ]; then
    out="${out}${pct_part}"
    [ -n "$cd_part" ] && out="${out}${SL_DIM}·${SL_RESET}${cd_part}"
  else
    out="${out}${cd_part}"
  fi

  printf '%s' "$out"
}
```

Trocar também a primeira linha do arquivo, que descreve o widget:

```bash
# Taxa de acerto do cache de prompt e quanto falta para ele expirar.
```

E a linha do `--desc`:

```bash
  --desc   "Prompt cache hit rate and time to expiry"
```

- [ ] **Step 5: Rodar para ver passar**

Run: `bats tests/widgets/cache.bats`
Expected: PASS, todos.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `bats -r tests`
Expected: 0 falhas. `tests/golden.bats` e `tests/render.bats` podem conter a saída antiga `cache:` — se falharem, atualizar a expectativa para `☁ `, não o widget.

- [ ] **Step 7: Ver ao vivo**

Run: `bash bin/statusline.sh < ~/.claude/jobs/aec125a3/tmp/payload.json`
Expected: a primeira linha traz `☁ 100%·` seguido de um tempo, no lugar de `cache:100%`.

- [ ] **Step 8: Commit**

```bash
git add widgets/cache.sh tests/widgets/cache.bats
git commit -m "feat: countdown de expiração do cache no widget

O percentual fica acima de 95% em 95% das trocas medidas: verde imóvel,
que é o mesmo defeito que escondeu a projeção verde do rate-forecast. O
countdown é o sinal que se move — e o único preditivo, porque diz o que a
próxima troca vai custar enquanto ainda dá para agir.

Percentual e countdown passam a ser partes independentes: current_usage
vem null entre trocas, e o retorno precoce mataria o countdown justo
quando ele serve.

O rótulo cache: vira ☁, o mesmo glifo da statusline arquivada. Sai dim,
porque com duas cores no widget um prefixo colorido afirmaria que uma
delas vale para o conjunto."
```

---

### Task 5: opção `countdown` e documentação

**Files:**
- Modify: `widgets/cache.sh` (`_cache_countdown`)
- Modify: `README.md:287-310`
- Test: `tests/widgets/cache.bats`

**Interfaces:**
- Consumes: `_cache_countdown` (Task 4); `sl_config_widget_opt` de `lib/config.sh`.
- Produces: opção `countdown` com valores `always` (padrão), `near`, `off`.

- [ ] **Step 1: Escrever os testes que falham**

```bash
@test "the countdown shows by default" {
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
}

@test "countdown off drops the countdown and keeps the rate" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"off"}}}'
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%" ]
  # Contraprova: sem a opção, o mesmo transcript tem de trazer o tempo.
  SL_CONFIG_RAW=""
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
}

@test "countdown near hides the countdown while there is time" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"near"}}}'
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 70%" ]
}

@test "countdown near shows the countdown under three minutes" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"near"}}}'
  write_transcript "$(turn 2027-01-15T07:57:59Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·2m59s"* ]]
}

@test "countdown near still shows a cold cache" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"near"}}}'
  write_transcript "$(turn 2027-01-15T07:50:00Z 0 500)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·cold"* ]]
}

@test "an unknown countdown value behaves as always" {
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"countdown":"talvez"}}}'
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"·58m"* ]]
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `bats tests/widgets/cache.bats`
Expected: FAIL nos casos `off` e `near` — a opção ainda não é lida, e o countdown aparece sempre.

- [ ] **Step 3: Implementar**

Em `_cache_countdown`, declarar `mode` no `local` e inserir o `off` logo no começo, e o `near` depois de `rem` estar calculado:

```bash
_cache_countdown() {
  local raw ts ttl epoch rem text color mode

  # `near` e `off` não podem ser resolvidos no mesmo ponto: `off` dispensa a
  # leitura do transcript, `near` precisa do tempo restante para decidir.
  mode="$(sl_config_widget_opt cache countdown always)"
  [ "$mode" != "off" ] || return 1

  raw="$(_cache_probe)" || return 1
  set -- $raw
  ts="$1"; ttl="$2"
  case "$ttl" in ''|*[!0-9]*) return 1 ;; esac
  epoch="$(sl_epoch_normalize "$ts")" || return 1
  rem=$(( epoch + ttl - $(_cache_now) ))

  # `near` reusa o limite do amarelo em vez de inventar um segundo número para
  # o usuário calibrar: o tempo aparece quando passa a valer a pena olhar.
  # Expirado sempre aparece — é o único estado em que a próxima troca já tem
  # preço definido.
  if [ "$mode" = "near" ] && [ "$rem" -ge "$SL_CACHE_TTL_WARN" ]; then
    return 1
  fi

  if [ "$rem" -le 0 ]; then
  ...
```

O resto da função fica como está.

- [ ] **Step 4: Rodar para ver passar**

Run: `bats tests/widgets/cache.bats`
Expected: PASS, todos.

- [ ] **Step 5: Atualizar o README**

Substituir a seção `### \`cache\`` inteira (linhas 287-310) por:

```markdown
### `cache`

Taxa de acerto do cache de prompt e quanto falta para ele expirar:
`☁ 70%·4m12s`.

| Opção | Valores | Padrão |
|---|---|---|
| `countdown` | `always`, `near`, `off` | `always` |
| `label` | texto do prefixo com `icons: false`; `""` remove | `cache:` |

**A taxa** é o total de leituras de cache sobre a soma de leituras, escritas de
cache e tokens de entrada novos. Verde a partir de 70%, amarelo a partir de 30%,
vermelho abaixo. É um velocímetro, não um hodômetro: os contadores vêm de
`current_usage`, que descreve apenas a troca mais recente.

Não aparece quando os três contadores são zero. Uma taxa de acerto sobre zero
tokens não é 0%, é indefinida — imprimir `0%` afirmaria que o cache errou quando
nada lhe foi pedido.

**O countdown** diz quando o prefixo em cache expira. Passado esse ponto, a
próxima troca paga a gravação inteira de novo, e um token gravado custa vinte
vezes um token lido. Verde acima de três minutos, amarelo abaixo, vermelho
abaixo de um minuto e em `cold`.

Os limites são absolutos, não proporcionais à janela: a pergunta que o countdown
responde — dá tempo de escrever o próximo prompt antes de o cache esfriar? — tem
duração humana. Numa conta com janela de uma hora ele quase não sai do verde,
porque ali raramente se perde o cache; numa de cinco minutos acende o tempo
todo, porque ali se perde mesmo.

A janela não se configura: sai de `ephemeral_1h_input_tokens` e
`ephemeral_5m_input_tokens` no transcript, então a mesma configuração serve a
uma máquina com uma hora e a outra com cinco minutos.

`countdown: near` mostra o tempo só a partir do limite amarelo, e sempre quando
o cache já esfriou. `countdown: off` desliga.

O countdown depende de `transcript_path`, que vem no payload, e do arquivo
existir e ser legível. Faltando qualquer um, ele some sozinho e a taxa
permanece — e vice-versa: entre trocas, `current_usage` vem null e o widget
mostra só o tempo.

Com `icons: false` o glifo dá lugar ao texto de `label`.
```

- [ ] **Step 6: Rodar a suíte inteira e verificar ao vivo**

Run: `bats -r tests`
Expected: 0 falhas.

Run: `bash bin/statusline.sh < ~/.claude/jobs/aec125a3/tmp/payload.json`
Expected: primeira linha com `☁ 100%·<tempo>`.

- [ ] **Step 7: Commit**

```bash
git add widgets/cache.sh tests/widgets/cache.bats README.md
git commit -m "feat: opção countdown do widget cache, e README

always mostra sempre, near só a partir do limite amarelo, off desliga.
near reusa os três minutos do amarelo em vez de pedir ao usuário um
segundo número para calibrar, e nunca esconde o cache já frio."
```

---

### Task 6: sabotagem

Nenhum teste deste plano vale nada se não souber falhar. No bash 3.2 o `errexit` não dispara em `[[ ]]` dentro de função, então uma asserção que não é a última linha pode estar morta sem ninguém notar.

**Files:** nenhum do repositório. Trabalho numa cópia descartável.

**Interfaces:**
- Consumes: tudo das Tasks 1 a 5.
- Produces: confirmação de que cada quebra derruba testes, ou uma lista de testes a corrigir.

- [ ] **Step 1: Copiar o repositório para um diretório descartável**

```bash
SAB="${TMPDIR:-/tmp}/sab-cache-ttl"
rm -rf "$SAB" && cp -R . "$SAB"
```

- [ ] **Step 2: Quebrar uma coisa de cada vez e contar as quedas**

Para cada sabotagem: aplicar, rodar `bats -r tests` dentro de `$SAB`, anotar quantos testes caem, desfazer com `cp -R` de novo.

| # | Sabotagem | Onde | Testes que têm de cair |
|---|---|---|---|
| 1 | trocar `3600` por `300` no `if` do `jq` | `widgets/cache.sh`, `_cache_probe_compute` | os que fixam TTL de uma hora |
| 2 | trocar `last` por `first` no `$t` | `widgets/cache.sh`, `_cache_probe_compute` | `takes the timestamp from the last turn` |
| 3 | apagar o filtro `> 0` do `$w` | `widgets/cache.sh`, `_cache_probe_compute` | `takes the ttl from the last turn that wrote`, `gives nothing when no turn ever wrote` |
| 4 | trocar `SL_CACHE_TTL_WARN` por `0` | `widgets/cache.sh` | os de cor amarela e os de `near` |
| 5 | trocar `-le 0` por `-lt 0` no teste de expirado | `widgets/cache.sh`, `_cache_countdown` | `an expired cache reads as cold` |
| 6 | fazer `_cache_countdown` retornar 1 sempre | `widgets/cache.sh` | todos os de countdown, e nenhum dos de percentual |
| 7 | remover `SL_TRANSCRIPT` do `jq` | `lib/stdin.sh` | `exposes the transcript path` e os dois vizinhos |
| 8 | trocar `printf '%ds'` por `printf '<1m'` | `lib/timefmt.sh`, `sl_fmt_ttl` | `keeps seconds below a minute`, `reads zero as zero seconds` |
| 9 | trocar `☁ ` por `cache:` | `widgets/cache.sh` | `marks the number with the cloud glyph`, `the glyph carries a space` |

- [ ] **Step 3: Corrigir o que não caiu**

Sabotagem que não derruba nada significa asserção morta. Quase sempre é uma asserção que não é a última linha do teste. A correção é reordenar para que a asserção sob suspeita seja a última, ou dividir em dois testes.

- [ ] **Step 4: Apagar a cópia**

```bash
rm -rf "${TMPDIR:-/tmp}/sab-cache-ttl"
```

- [ ] **Step 5: Commit, se algum teste mudou**

```bash
git add tests/
git commit -m "test: reordena asserções que não sabiam falhar

Rodada de sabotagem numa cópia descartável. No bash 3.2 o errexit não
dispara em [[ ]] dentro de função, então só a última asserção de cada
teste é cobrada no macOS."
```

---

### Task 7: PR

- [ ] **Step 1: Confirmar a suíte e o CI local**

Run: `bats -r tests`
Expected: 0 falhas.

- [ ] **Step 2: Revisar o diff inteiro**

Run: `git diff main...HEAD`
Expected: mudanças apenas em `lib/stdin.sh`, `lib/timefmt.sh`, `widgets/cache.sh`, `tests/stdin.bats`, `tests/timefmt.bats`, `tests/widgets/cache.bats`, `README.md`, e os dois documentos em `docs/superpowers/`.

- [ ] **Step 3: Abrir a PR**

```bash
git push -u origin cache-ttl-countdown
gh pr create --title "feat: countdown de expiração do prompt cache" --body-file - <<'EOF'
O widget `cache` mostrava `cache:100%` verde em 95% das trocas medidas. Verde
imóvel é o mesmo defeito que levou a projeção `→48%` a ser escondida no
rate-forecast: ocupa espaço permanente para dizer "siga em frente".

Esta PR soma o número que se move — quanto falta para o prompt cache expirar —
e troca o rótulo pelo glifo `☁`.

```
☁ 100%·4m12s
```

## Por que o countdown, e não outra coisa

Levantamento sobre 845 trocas de uma sessão real, deduplicadas por `requestId`:

- 805 de 844 amostras ficam acima de 95% de acerto. O número não discrimina.
- Acerto alto não é cache barato. Em token a leitura é 96,7%; em preço a
  gravação leva ~37%, porque um token gravado custa 20× um lido.
- Dos quatro projetos comparados (ccstatusline, claude-statusline-enhanced,
  claude-hud, claude-code-usage-bar), três implementam o TTL e nenhum pondera
  por preço. O TTL é o único sinal de cache que é preditivo: diz o que a
  próxima troca vai custar enquanto ainda dá para agir.

## Decisões

**A janela é detectada, não configurada.** Sai de `ephemeral_1h_input_tokens` e
`ephemeral_5m_input_tokens` no transcript, então a mesma configuração serve a
uma conta de uma hora e a uma de cinco minutos.

**Limites de cor absolutos, não proporcionais.** A pergunta que o countdown
responde tem duração humana. Proporcional daria vinte minutos de amarelo numa
janela de uma hora.

**Percentual e countdown são independentes.** `current_usage` vem null entre
trocas; um retorno precoce compartilhado mataria o countdown justo quando ele
serve.

**O `☁` é U+2601**, o mesmo de `docs/legacy/statusline-2.sh:92`. O risco de
apresentação emoji é o mesmo já corrido pelo `⚠` do flow, e resolvido do mesmo
jeito: codepoint puro, sem `U+FE0E`. Quem tiver problema de fonte usa
`icons: false`.

## Custo

`tail -n 400 | jq`, embrulhado em `cache_by_mtime` com o transcript como
sentinela: 7 ms num arquivo de 24 MB, e só quando o arquivo muda. A maior
corrida observada sem entrada `assistant` foi 57 linhas, contra a janela de 400.

## Test plan

- [ ] `bats -r tests` verde no macOS e no CI Linux
- [ ] Rodada de sabotagem com nove quebras, cada uma derrubando os testes
      previstos
- [ ] Verificado ao vivo nas duas janelas: 1h e 5min

Spec: `docs/superpowers/specs/2026-08-12-cache-ttl-countdown-design.md`
Plano: `docs/superpowers/plans/2026-08-12-cache-ttl-countdown.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```
