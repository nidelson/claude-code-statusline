# rate-forecast com duas janelas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o `rate-forecast` mostrar as duas janelas de rate limit ao mesmo tempo, cada uma com uso atual, projeção de estouro, horário do reset e contagem regressiva.

**Architecture:** A aritmética de tempo sai do widget e vira `lib/timefmt.sh`, uma biblioteca sem estado que normaliza `resets_at` e formata relógio, dia e regressiva. O widget passa a compor a linha por janela, chamando um render interno duas vezes e colorindo número a número.

**Tech Stack:** bash 3.2, `jq`, `date` (BSD e GNU), `bats-core` para testes.

**Spec:** [2026-08-10-rate-forecast-duas-janelas-design.md](../specs/2026-08-10-rate-forecast-duas-janelas-design.md)

## Global Constraints

- **Shell alvo: bash 3.2.57.** Sem `declare -A`, sem `${var^^}`, sem `mapfile`, sem `&>>`. Indireção `${!var}` para leitura dinâmica.
- **Shebang de todo script executável:** `#!/usr/bin/env bash`
- **Nunca usar `set -e` nem `set -u`.** Erros se tratam no ponto de ocorrência.
- **Dependências de runtime: apenas `jq` e `git`.** `date` conta como parte do sistema. **`python3` está proibido** — a original usava, e não replicamos.
- **A statusline nunca pode desaparecer.** Qualquer falha degrada para saída parcial, jamais para linha vazia.
- **Idioma:** comentários, documentação e mensagens de commit em **português**. Identificadores em inglês. Strings de `--desc` em inglês.
- **Nomes de teste `@test` obrigatoriamente em inglês ASCII.** O bats força `LC_ALL=C` e converte o título em nome de função; um acento vira byte inválido e o teste falha com `unknown test name`.
- **Nenhum teste pode depender do relógio, do fuso ou do locale da máquina.** Tempo é entrada injetada.
- **Escala de cor do uso atual: verde abaixo de 50, amarelo de 50 a 79, vermelho a partir de 80.** Copiada de `docs/legacy/statusline-2.sh:256-260`.

---

### Task 1: Biblioteca de tempo

Toda a aritmética de `resets_at` num arquivo só, sem estado e sem conhecer o widget. É a tarefa que carrega os três achados de portabilidade da spec.

**Files:**
- Create: `lib/timefmt.sh`
- Create: `tests/timefmt.bats`
- Modify: `bin/statusline.sh` (carregar a biblioteca)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `sl_epoch_normalize <valor>` — imprime epoch em segundos; retorna 1 se ilegível
  - `sl_date_fmt <epoch> <formato>` — imprime `date` formatado sob `LC_ALL=C`; retorna 1 se não houver forma de `date` compatível
  - `sl_fmt_countdown <segundos>` — imprime `5d6h`, `1h48m`, `48m` ou `<1m`
  - `sl_reset_label <epoch> <now>` — imprime `02:10·1h48m` ou `Fri·5d6h`; retorna 1 se o reset já passou ou se `date` falhou
  - Variável `SL_DATE_FORM` com `bsd`, `gnu` ou vazio

- [ ] **Step 1: Escrever o teste que falha**

Criar `tests/timefmt.bats`:

```bash
load helper

setup() {
  source "$PROJECT_ROOT/lib/timefmt.sh"
}

@test "normalizes an epoch in seconds unchanged" {
  run sl_epoch_normalize 1800000000
  [ "$output" = "1800000000" ]
}

@test "normalizes an epoch in milliseconds" {
  run sl_epoch_normalize 1800000000000
  [ "$output" = "1800000000" ]
}

@test "drops the fractional part" {
  run sl_epoch_normalize 1800000000.5
  [ "$output" = "1800000000" ]
}

@test "rejects an empty value" {
  run sl_epoch_normalize ""
  [ "$status" -eq 1 ]
}

@test "rejects a non-numeric value that is not a date" {
  run sl_epoch_normalize "banana"
  [ "$status" -eq 1 ]
}

@test "normalizes an ISO 8601 timestamp with Z" {
  run sl_epoch_normalize "2027-01-15T08:00:00Z"
  [ "$status" -eq 0 ]
  [ "$output" = "1800000000" ]
}

@test "formats a clock time under LC_ALL=C" {
  run sl_date_fmt 1800000000 '%H:%M'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{2}:[0-9]{2}$ ]]
}

@test "formats a weekday in three ASCII letters" {
  run sl_date_fmt 1800000000 '%a'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z]{3}$ ]]
}

@test "counts down in days and hours" {
  run sl_fmt_countdown 454000
  [ "$output" = "5d6h" ]
}

@test "counts down in hours and minutes" {
  run sl_fmt_countdown 6480
  [ "$output" = "1h48m" ]
}

@test "counts down in minutes alone" {
  run sl_fmt_countdown 2880
  [ "$output" = "48m" ]
}

@test "counts down under a minute" {
  run sl_fmt_countdown 30
  [ "$output" = "<1m" ]
}

@test "counts down at zero" {
  run sl_fmt_countdown 0
  [ "$output" = "<1m" ]
}

@test "reset under a day shows the clock" {
  run sl_reset_label 1800006480 1800000000
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{2}:[0-9]{2}.1h48m$ ]]
}

@test "reset over a day shows the weekday" {
  run sl_reset_label 1800454000 1800000000
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z]{3}.5d6h$ ]]
}

@test "reset in the past is refused" {
  run sl_reset_label 1799999000 1800000000
  [ "$status" -eq 1 ]
}

@test "no usable date form refuses instead of printing garbage" {
  SL_DATE_FORM=""
  run sl_reset_label 1800006480 1800000000
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Rodar o teste para confirmar que falha**

Run: `bats tests/timefmt.bats`
Expected: FAIL — `lib/timefmt.sh` não existe.

- [ ] **Step 3: Implementar a biblioteca**

Criar `lib/timefmt.sh`:

```bash
# Normalização e formatação de tempo.
#
# ── Três formatos de resets_at ──
#
# A fonte entrega epoch em segundos, epoch em milissegundos ou string ISO 8601 —
# as três variantes estão tratadas na statusline arquivada em
# docs/legacy/statusline-2.sh:210-219. Milissegundo tratado como segundo não
# falha visivelmente: vira uma data no ano 57000 e uma regressiva absurda, que é
# pior que não mostrar nada. A detecção é por contagem de dígitos, como na
# original.
#
# ── `date` diverge entre plataformas ──
#
# BSD aceita `date -r <epoch>`; GNU quer `date -d @<epoch>`. A original só
# precisava de macOS; o CI deste repositório roda também em Ubuntu. A forma é
# resolvida uma vez, no carregamento, como widgets/command.sh:62 já faz para
# descobrir `timeout`.
#
# ── Sem python3 ──
#
# A original convertia ISO 8601 chamando python3. Uma statusline que precisa de
# Python para desenhar contraria a restrição de runtime do projeto, que é jq e
# git. Aqui a conversão é tentada com `date` e, falhando, o chamador perde os
# tempos e mantém o resto.

# GNU interpreta `-r` como "arquivo de referência", então `date -r 0` falha lá e
# só tem sucesso no BSD. A ordem importa.
if date -r 0 +%s >/dev/null 2>&1; then
  SL_DATE_FORM=bsd
elif date -d @0 +%s >/dev/null 2>&1; then
  SL_DATE_FORM=gnu
else
  SL_DATE_FORM=""
fi

sl_date_fmt() {
  local epoch="$1" fmt="$2"
  case "$epoch" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$SL_DATE_FORM" in
    bsd) LC_ALL=C date -r "$epoch" "+$fmt" 2>/dev/null ;;
    gnu) LC_ALL=C date -d "@$epoch" "+$fmt" 2>/dev/null ;;
    *)   return 1 ;;
  esac
}

_sl_epoch_from_iso() {
  local iso="$1" out
  case "$SL_DATE_FORM" in
    gnu) out="$(LC_ALL=C date -d "$iso" +%s 2>/dev/null)" ;;
    bsd)
      # BSD exige o formato explícito e não digere sufixo de fuso nem fração.
      iso="${iso%Z}"
      iso="${iso%%.*}"
      out="$(LC_ALL=C date -j -u -f '%Y-%m-%dT%H:%M:%S' "$iso" +%s 2>/dev/null)"
      ;;
    *) return 1 ;;
  esac
  case "$out" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s' "$out"
}

sl_epoch_normalize() {
  local v="$1"

  case "$v" in
    ''|null) return 1 ;;
  esac

  # Fração de segundo não interessa a nada aqui.
  case "$v" in
    *.*)
      case "${v%%.*}" in
        ''|*[!0-9]*) ;;
        *) v="${v%%.*}" ;;
      esac
      ;;
  esac

  case "$v" in
    ''|*[!0-9]*)
      _sl_epoch_from_iso "$1"
      return $?
      ;;
  esac

  # 13 dígitos ou mais só pode ser milissegundo: 10 dígitos cobrem até o ano
  # 2286 em segundos.
  if [ "${#v}" -ge 13 ]; then
    v=$(( v / 1000 ))
  fi

  printf '%s' "$v"
}

sl_fmt_countdown() {
  local rem="$1" d h m
  case "$rem" in
    ''|*[!0-9]*) printf '<1m'; return 0 ;;
  esac
  d=$(( rem / 86400 ))
  h=$(( (rem % 86400) / 3600 ))
  m=$(( (rem % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
  else                      printf '<1m'
  fi
}

sl_reset_label() {
  local epoch="$1" now="$2" rem stamp
  case "$epoch$now" in
    *[!0-9]*) return 1 ;;
  esac
  rem=$(( epoch - now ))
  [ "$rem" -gt 0 ] || return 1

  # A escolha é pelo tempo restante, não pelo tipo de janela: uma janela de sete
  # dias que reseta daqui a quatro horas quer o horário, não o nome do dia.
  if [ "$rem" -lt 86400 ]; then
    stamp="$(sl_date_fmt "$epoch" '%H:%M')" || return 1
  else
    stamp="$(sl_date_fmt "$epoch" '%a')" || return 1
  fi
  [ -n "$stamp" ] || return 1

  printf '%s·%s' "$stamp" "$(sl_fmt_countdown "$rem")"
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bats tests/timefmt.bats`
Expected: 17 tests, 0 failures.

- [ ] **Step 5: Carregar a biblioteca no entrypoint**

Em `bin/statusline.sh`, acrescentar após a linha que carrega `lib/sanitize.sh`:

```bash
. "$SL_ROOT/lib/timefmt.sh"
```

- [ ] **Step 6: Confirmar que a suíte inteira segue verde**

Run: `bats tests/ --recursive`
Expected: todas passam. A biblioteca ainda não tem consumidor; nada de comportamento mudou.

- [ ] **Step 7: Commit**

```bash
git add lib/timefmt.sh tests/timefmt.bats bin/statusline.sh
git commit -m "feat: biblioteca de tempo com os três formatos de resets_at"
```

---

### Task 2: Cor do uso atual e arredondamento

O widget passa a pintar o percentual atual pela escala da original, e a arredondar o float antes de comparar. Ainda uma janela por vez — a composição vem na Task 4.

**Files:**
- Modify: `widgets/rate-forecast.sh`
- Modify: `tests/widgets/rate-forecast.bats`

**Interfaces:**
- Consumes: `sl_color` (`lib/colors.sh`), `sl_config_widget_opt <widget> <chave> <default>` (`lib/config.sh:71`).
- Produces:
  - `_rf_round <valor>` — imprime o inteiro mais próximo; retorna 1 se não for número
  - `_rf_usage_color <inteiro> <warn> <crit>` — imprime a sequência de cor

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar ao final de `tests/widgets/rate-forecast.bats`:

```bash
@test "usage below warn paints green" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="49"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[32m'"49%"* ]]
}

@test "usage at warn paints yellow" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="50"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[33m'"50%"* ]]
}

@test "usage at crit paints red" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="80"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[31m'"80%"* ]]
}

@test "usage just below crit stays yellow" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="79"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[33m'"79%"* ]]
}

@test "a float percentage is rounded before comparison" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="49.6"
  run widget_rate_forecast_render
  [[ "$output" == *"50%"* ]]
  [[ "$output" == *$'\033[33m'"50%"* ]]
}

@test "configured thresholds override the defaults" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"warn":10,"crit":20}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="25"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[31m'"25%"* ]]
}

@test "a non-numeric percentage renders nothing" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="banana"
  SL_7D_PCT=""
  run widget_rate_forecast_render
  [ "$output" = "" ]
}
```

- [ ] **Step 2: Rodar os testes para confirmar que falham**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: FAIL nos sete casos novos — o widget hoje não pinta o percentual atual.

- [ ] **Step 3: Implementar arredondamento e cor**

Em `widgets/rate-forecast.sh`, acrescentar após a linha `: "${SL_FORECAST_BIN:=$HOME/.claude/rate-forecast.sh}"`:

```bash
SL_RF_DEFAULT_WARN=50
SL_RF_DEFAULT_CRIT=80

# A fonte entrega float — a statusline arquivada registra ter recebido
# 14.000000000000002 — e a comparação inteira do bash aborta a função no meio
# quando encontra casa decimal. Arredondar antes de comparar não é higiene, é o
# que mantém a cor funcionando.
_rf_round() {
  local v="$1"
  case "$v" in
    ''|*[!0-9.]*) return 1 ;;
  esac
  LC_ALL=C printf '%.0f' "$v" 2>/dev/null
}

# Escala da original, verificada idêntica em docs/legacy/statusline-2.sh:256-260
# e docs/legacy/statusline.sh:348-350. Não há quarto nível: acima de crit tudo é
# vermelho, e a projeção carrega a gravidade.
_rf_usage_color() {
  local pct="$1" warn="$2" crit="$3"
  if   [ "$pct" -ge "$crit" ]; then sl_color red
  elif [ "$pct" -ge "$warn" ]; then sl_color yellow
  else                              sl_color green
  fi
}
```

- [ ] **Step 4: Ligar a cor ao render**

Em `widgets/rate-forecast.sh`, substituir o corpo de `widget_rate_forecast_render` a partir da linha `[ -n "$pct" ] || return 0` até o `printf` final por:

```bash
  local int warn crit ucolor
  int="$(_rf_round "$pct")" || return 0

  warn="$(sl_config_widget_opt rate-forecast warn "$SL_RF_DEFAULT_WARN")"
  crit="$(sl_config_widget_opt rate-forecast crit "$SL_RF_DEFAULT_CRIT")"
  case "$warn" in ''|*[!0-9]*) warn="$SL_RF_DEFAULT_WARN" ;; esac
  case "$crit" in ''|*[!0-9]*) crit="$SL_RF_DEFAULT_CRIT" ;; esac

  level="none"; proj=""
  if [ -x "$SL_FORECAST_BIN" ]; then
    raw="$("$SL_FORECAST_BIN" "$window" "$int" "$reset" \
           "$(_forecast_window_seconds "$window")" 2>/dev/null)" || raw=""
    set -- $raw
    case "$1" in
      ok|warn|crit) level="$1"; proj="$2" ;;
      *) level="none"; proj="" ;;
    esac
  fi

  case "$level" in
    crit) color="$(sl_color red)"    ;;
    warn) color="$(sl_color yellow)" ;;
    ok)   color="$(sl_color green)"  ;;
    *)    color=""                   ;;
  esac

  ucolor="$(_rf_usage_color "$int" "$warn" "$crit")"

  out="${SL_DIM}${window}:${SL_RESET}${ucolor}${int}%${SL_RESET}"
  if [ -n "$proj" ]; then
    out="${out}${color}→${proj}%${SL_RESET}"
  fi

  printf '%s' "$out"
```

Declarar `int warn crit ucolor` junto dos demais `local` no topo da função, e remover a declaração duplicada acrescentada acima.

- [ ] **Step 5: Rodar os testes e confirmar que passam**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: 19 tests, 0 failures. Os doze casos antigos seguem válidos: o percentual continua presente, a seta continua ausente quando não há projeção, e as cores de projeção não mudaram.

- [ ] **Step 6: Commit**

```bash
git add widgets/rate-forecast.sh tests/widgets/rate-forecast.bats
git commit -m "feat: cor do uso atual na escala 50/80 da statusline original"
```

---

### Task 3: Reset e contagem regressiva

A janela ganha horário e regressiva, esmaecidos, usando a biblioteca da Task 1.

**Files:**
- Modify: `widgets/rate-forecast.sh`
- Modify: `tests/widgets/rate-forecast.bats`

**Interfaces:**
- Consumes: `sl_epoch_normalize`, `sl_reset_label` (Task 1).
- Produces: `SL_NOW` — variável opcional que congela o instante atual; vazia em produção.

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar ao final de `tests/widgets/rate-forecast.bats`:

```bash
@test "shows the reset clock and countdown under a day" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800006480
  run widget_rate_forecast_render
  [[ "$output" =~ [0-9]{2}:[0-9]{2}.1h48m ]]
}

@test "shows the reset weekday and countdown over a day" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800454000
  run widget_rate_forecast_render
  [[ "$output" =~ [A-Za-z]{3}.5d6h ]]
}

@test "normalizes a reset given in milliseconds" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800006480000
  run widget_rate_forecast_render
  [[ "$output" =~ 1h48m ]]
}

@test "a reset in the past drops the times but keeps the percentage" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1799999000
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"·"* ]]
}

@test "an unreadable reset drops the times but keeps the percentage" {
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET="banana"
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"·"* ]]
}

@test "reset false hides the times" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"reset":false}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  SL_NOW=1800000000
  SL_5H_RESET=1800006480
  run widget_rate_forecast_render
  [[ "$output" == *"42%"* ]]
  [[ "$output" != *"1h48m"* ]]
}
```

- [ ] **Step 2: Rodar os testes para confirmar que falham**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: FAIL nos seis casos novos — o widget ainda não imprime tempos.

- [ ] **Step 3: Implementar o instante injetável**

Em `widgets/rate-forecast.sh`, acrescentar junto das demais constantes:

```bash
# Tempo é entrada, não relógio. Sem isso a suíte falharia sozinha às duas da
# manhã, ou só no CI, que roda em UTC.
_rf_now() {
  if [ -n "$SL_NOW" ]; then
    printf '%s' "$SL_NOW"
  else
    date +%s
  fi
}
```

- [ ] **Step 4: Acrescentar os tempos ao render**

Em `widget_rate_forecast_render`, logo antes do `printf '%s' "$out"` final:

```bash
  local repoch rlabel show_reset
  show_reset="$(sl_config_widget_opt rate-forecast reset true)"
  if [ "$show_reset" != "false" ]; then
    repoch="$(sl_epoch_normalize "$reset")" \
      && rlabel="$(sl_reset_label "$repoch" "$(_rf_now)")" \
      && out="${out} ${SL_DIM}${rlabel}${SL_RESET}"
  fi
```

Declarar `repoch rlabel show_reset` junto dos demais `local` no topo da função.

- [ ] **Step 5: Rodar os testes e confirmar que passam**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: 25 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add widgets/rate-forecast.sh tests/widgets/rate-forecast.bats
git commit -m "feat: horário do reset e contagem regressiva no rate-forecast"
```

---

### Task 4: As duas janelas

O render de uma janela vira função, chamada duas vezes. `window` deixa de escolher e passa a filtrar.

**Attention:** o teste `renders nothing without a percentage` (`tests/widgets/rate-forecast.bats:24`) limpa apenas `SL_5H_PCT` e mantém `SL_7D_PCT="13"`. Ele passa a falhar nesta tarefa, porque a janela de sete dias agora renderiza. O Step 1 o corrige — não é regressão, é o teste descrevendo o comportamento antigo.

**Files:**
- Modify: `widgets/rate-forecast.sh`
- Modify: `tests/widgets/rate-forecast.bats`

**Interfaces:**
- Consumes: tudo das Tasks 1 a 3.
- Produces: `_rf_window <rótulo> <pct> <reset>` — imprime uma janela completa; retorna 1 quando não há percentual utilizável.

- [ ] **Step 1: Corrigir o teste que descreve o comportamento antigo**

Em `tests/widgets/rate-forecast.bats`, substituir o teste `renders nothing without a percentage` por:

```bash
@test "renders nothing without any percentage" {
  SL_5H_PCT=""
  SL_7D_PCT=""
  run widget_rate_forecast_render
  [ "$output" = "" ]
}

@test "one window alone renders without a stray separator" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT=""
  run widget_rate_forecast_render
  [[ "$output" == *"7d:13%"* ]]
  [[ "$output" != *"5h"* ]]
  [ "${output#*·}" = "$output" ] || [[ "$output" =~ [0-9]{2}:[0-9]{2}. ]] || [[ "$output" =~ [A-Za-z]{3}. ]]
}
```

- [ ] **Step 2: Escrever os testes que faltam**

Acrescentar ao final de `tests/widgets/rate-forecast.bats`:

```bash
@test "renders both windows by default" {
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"5h:42%"* ]]
  [[ "$output" == *"7d:13%"* ]]
}

@test "the five-hour window comes first" {
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "${output%%7d*}" == *"5h:42%"* ]]
}

@test "window five-hour filters out the seven-day window" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"window":"5h"}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"5h:42%"* ]]
  [[ "$output" != *"7d"* ]]
}

@test "each window is coloured on its own figures" {
  export FAKE_FORECAST_OUT="none"
  SL_5H_PCT="85"
  SL_7D_PCT="10"
  run widget_rate_forecast_render
  [[ "$output" == *$'\033[31m'"85%"* ]]
  [[ "$output" == *$'\033[32m'"10%"* ]]
}

@test "a configured separator replaces the default" {
  cat > "$BATS_TEST_TMPDIR/config.json" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"separator":"//","reset":false}}}
EOF
  sl_config_load "$BATS_TEST_TMPDIR/config.json"
  export FAKE_FORECAST_OUT="none"
  run widget_rate_forecast_render
  [[ "$output" == *"//"* ]]
}

@test "icons on shows the widget mark" {
  export FAKE_FORECAST_OUT="none"
  SL_CONFIG_ICONS=1
  run widget_rate_forecast_render
  [[ "$output" == *"⏱"* ]]
}

@test "icons off hides the widget mark" {
  export FAKE_FORECAST_OUT="none"
  SL_CONFIG_ICONS=0
  run widget_rate_forecast_render
  [[ "$output" != *"⏱"* ]]
  [[ "$output" == *"5h:42%"* ]]
}

@test "icons off hides the reset mark but keeps the times" {
  export FAKE_FORECAST_OUT="none"
  SL_CONFIG_ICONS=0
  SL_NOW=1800000000
  SL_5H_RESET=1800006480
  run widget_rate_forecast_render
  [[ "$output" != *"⟳"* ]]
  [[ "$output" == *"1h48m"* ]]
}
```

- [ ] **Step 3: Rodar os testes para confirmar que falham**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: FAIL nos casos novos e no `one window alone renders without a stray separator`.

- [ ] **Step 4: Extrair o render de uma janela**

Em `widgets/rate-forecast.sh`, substituir `widget_rate_forecast_render` inteira por:

```bash
# Uma janela: rótulo, uso atual, projeção e tempos. Retorna 1 quando não há
# percentual utilizável, para que o chamador saiba não emitir separador.
_rf_window() {
  local label="$1" pct="$2" reset="$3"
  local int warn crit ucolor level proj raw color out
  local repoch rlabel show_reset mark

  int="$(_rf_round "$pct")" || return 1

  warn="$(sl_config_widget_opt rate-forecast warn "$SL_RF_DEFAULT_WARN")"
  crit="$(sl_config_widget_opt rate-forecast crit "$SL_RF_DEFAULT_CRIT")"
  case "$warn" in ''|*[!0-9]*) warn="$SL_RF_DEFAULT_WARN" ;; esac
  case "$crit" in ''|*[!0-9]*) crit="$SL_RF_DEFAULT_CRIT" ;; esac

  level="none"; proj=""
  if [ -x "$SL_FORECAST_BIN" ]; then
    raw="$("$SL_FORECAST_BIN" "$label" "$int" "$reset" \
           "$(_forecast_window_seconds "$label")" 2>/dev/null)" || raw=""
    set -- $raw
    case "$1" in
      ok|warn|crit) level="$1"; proj="$2" ;;
      *) level="none"; proj="" ;;
    esac
  fi

  case "$level" in
    crit) color="$(sl_color red)"    ;;
    warn) color="$(sl_color yellow)" ;;
    ok)   color="$(sl_color green)"  ;;
    *)    color=""                   ;;
  esac

  ucolor="$(_rf_usage_color "$int" "$warn" "$crit")"

  out="${SL_DIM}${label}:${SL_RESET}${ucolor}${int}%${SL_RESET}"
  # As chaves em ${out} são obrigatórias, não estilo: o bash 3.2 aceita bytes
  # acima de 127 como parte de nome de variável, então "$out→" é lido como a
  # variável `out\xE2` — que não existe, expande vazio e ainda come o primeiro
  # byte da seta, deixando lixo na saída.
  [ -n "$proj" ] && out="${out}${color}→${proj}%${SL_RESET}"

  show_reset="$(sl_config_widget_opt rate-forecast reset true)"
  if [ "$show_reset" != "false" ]; then
    mark=""
    [ "${SL_CONFIG_ICONS:-1}" = "1" ] && mark="⟳"
    repoch="$(sl_epoch_normalize "$reset")" \
      && rlabel="$(sl_reset_label "$repoch" "$(_rf_now)")" \
      && out="${out} ${SL_DIM}${mark}${rlabel}${SL_RESET}"
  fi

  printf '%s' "$out"
}

widget_rate_forecast_render() {
  local window sep out piece mark line=""

  window="$(sl_config_widget_opt rate-forecast window "")"
  sep="$(sl_config_widget_opt rate-forecast separator "·")"

  if [ "$window" != "7d" ]; then
    piece="$(_rf_window 5h "$SL_5H_PCT" "$SL_5H_RESET")" && line="$piece"
  fi

  if [ "$window" != "5h" ]; then
    # O separador só entra quando já há algo à esquerda: janela ausente não
    # pode deixar pontuação órfã, do mesmo modo que o núcleo trata widget vazio.
    if piece="$(_rf_window 7d "$SL_7D_PCT" "$SL_7D_RESET")"; then
      if [ -n "$line" ]; then
        line="${line} ${SL_DIM}${sep}${SL_RESET} ${piece}"
      else
        line="$piece"
      fi
    fi
  fi

  [ -n "$line" ] || return 0

  mark=""
  [ "${SL_CONFIG_ICONS:-1}" = "1" ] && mark="${SL_DIM}⏱${SL_RESET} "

  printf '%s%s' "$mark" "$line"
}
```

- [ ] **Step 5: Rodar os testes e confirmar que passam**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: 34 tests, 0 failures.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `bats tests/ --recursive`
Expected: todas passam. `tests/golden.bats` merece atenção: ele afirma `5h:42%` na saída, que continua presente.

- [ ] **Step 7: Verificar de ponta a ponta**

Run:
```bash
jq '.rate_limits.five_hour.used_percentage = 31' tests/fixtures/session.json | ./bin/statusline.sh | cat -v
```
Expected: uma linha com `5h:31%`, o reset das duas janelas e `7d:13%`, com `⏱` no começo.

- [ ] **Step 8: Commit**

```bash
git add widgets/rate-forecast.sh tests/widgets/rate-forecast.bats
git commit -m "feat: rate-forecast mostra as duas janelas ao mesmo tempo"
```

---

### Task 5: Documentação

**Files:**
- Modify: `README.md` (seção `### rate-forecast`)

**Interfaces:**
- Consumes: o comportamento final das Tasks 1 a 4.
- Produces: nada que outro código use.

- [ ] **Step 1: Reescrever a seção do widget**

Em `README.md`, substituir a seção `### rate-forecast` por uma que cubra: o formato completo com as duas janelas (`⏱ 5h:31%→93% ⟳02:10·1h48m · 7d:15% ⟳Fri·5d6h`); a tabela de opções abaixo; a explicação de que a cor do uso atual e a da projeção respondem perguntas diferentes e por isso usam escalas diferentes; e a nota de que `window` filtra em vez de escolher.

Tabela de opções a usar:

| Option | Values | Default |
|---|---|---|
| `window` | `5h`, `7d`; omit to show both | omitted |
| `warn` | usage percentage that turns yellow | `50` |
| `crit` | usage percentage that turns red | `80` |
| `separator` | text between the two windows | `·` |
| `reset` | `true`, `false` — show reset time and countdown | `true` |

Manter a nota existente de que `color` não se aplica, porque a cor é semântica, e a explicação do helper externo.

- [ ] **Step 2: Conferir que o exemplo do README bate com a saída real**

Run:
```bash
./bin/statusline.sh < tests/fixtures/session.json
```
Compare com o formato documentado. Se divergirem, o errado é o README.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rate-forecast com duas janelas no README"
```

---

## Notas para quem executar

**A ordem importa.** A Task 1 entrega uma biblioteca sem consumidor; ela existe separada porque a aritmética de tempo tem seus próprios casos de borda e merece testes que não passem pelo widget. As Tasks 2 e 3 mantêm uma janela por vez de propósito — a composição na Task 4 fica trivial porque tudo que ela precisa já está pronto e testado.

**O que quebra e quando.** Um único teste existente descreve o comportamento antigo e falha na Task 4; está sinalizado ali. Nenhum outro teste da suíte deve mudar. Se algum mudar, a alteração passou do escopo.

**O helper externo não muda.** `~/.claude/rate-forecast.sh` continua com o contrato de hoje. Ele já isola o histórico por janela em `rate-samples-<label>.tsv`, então as duas chamadas por repaint não colidem. O primeiro argumento continua sendo o rótulo da janela — `5h` ou `7d` — e nunca outra coisa: o helper valida com `^[A-Za-z0-9_-]+$` e cai em `none` silenciosamente se receber algo fora disso.

**Custo por repaint.** O widget passa a chamar o helper duas vezes em vez de uma. É um `fork` a mais a cada cinco segundos. Se isso aparecer em medição, o caminho é `cache_by_ttl` em volta da chamada, como `widgets/command.sh:123` faz — mas não antecipe: meça primeiro.
