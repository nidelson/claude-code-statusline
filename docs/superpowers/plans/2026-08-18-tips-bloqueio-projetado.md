# tips — dica de bloqueio projetado — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** acrescentar à statusline uma linha efêmera que explica o `→116%` e diz quanto o ritmo precisa cair, quando Flow, 5h ou 7d projetam bloqueio.

**Architecture:** um widget novo (`tip`) e uma lib nova (`lib/tips.sh`). O widget lê as mesmas fontes que `flow` e `rate-forecast` leem, aplica a regra de virada/piora contra um TSV de estado, e renderiza uma linha por fonte. **Nenhum widget existente é modificado.**

**Tech Stack:** bash 3.2 (piso do macOS), jq, bats.

**Spec:** `docs/superpowers/specs/2026-08-18-tips-bloqueio-projetado-design.md`

## Global Constraints

- **bash 3.2** — sem arrays associativos, sem `${var^^}`, sem `printf -v`. `$(( ))` só faz inteiro.
- **Nunca `set -e`** em entrypoint. Retorno não-zero não pode apagar a statusline.
- **Widgets escrevem em stdout**, e rodam em subshell — global atribuída dentro de widget não sobrevive.
- **Frases ≤ 80 colunas.**
- **Testes:** contraprova primeiro, asserção sob teste na ÚLTIMA linha do teste. No bash 3.2 do macOS só a última asserção é cobrada (`tests/helper.bash`).
- **Chaves obrigatórias em `${var}`** quando seguidas de byte > 127: `"${out}→"`, nunca `"$out→"` — bash 3.2 lê `out\xE2` como nome de variável.
- **Percentual arredonda com `sl_round`**, nunca com jq ou aritmética própria.
- Comentários e mensagens em **português**, no tom do repositório: explicar *por que*, não *o que*.

## File Structure

| Arquivo | Responsabilidade |
| ------- | ---------------- |
| `lib/tips.sh` (criar) | cálculo do corte, degrau, promptId, estado, leitura das fontes, montagem das frases |
| `widgets/tip.sh` (criar) | registro do widget e renderização das linhas |
| `bin/statusline.sh` (modificar) | carregar `lib/tips.sh` |
| `tests/tips.bats` (criar) | funções de `lib/tips.sh` isoladas |
| `tests/widgets/tip.bats` (criar) | renderização |
| `README.md`, `commands/setup.md` (modificar) | documentar o widget e incluí-lo na config sugerida |

---

### Task 1: cálculo puro — corte e degrau

**Files:**
- Create: `lib/tips.sh`
- Test: `tests/tips.bats`

**Interfaces:**
- Consumes: nada
- Produces: `_tip_cut <proj> <used>` → inteiro (percentual de corte), retorna 1 se indefinido. `_tip_step <proj>` → 0..3, retorna 1 se `proj ≤ 100`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/tips.bats
load helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/tips.sh"
}

@test "cut turns 116 projected over 25 used into an 18 percent slowdown" {
  run _tip_cut 116 25
  [ "$output" = "18" ]
}

@test "cut refuses a projection that is not above one hundred" {
  run _tip_cut 116 25
  [ "$output" = "18" ]          # contraprova: a função sabe responder
  run _tip_cut 98 25
  [ "$status" -ne 0 ]
}

@test "cut refuses when used is not below the projection" {
  run _tip_cut 116 25
  [ "$output" = "18" ]          # contraprova
  run _tip_cut 116 116
  [ "$status" -ne 0 ]
}

@test "step buckets the projection in slices of twenty five" {
  run _tip_step 101 ; [ "$output" = "0" ]
  run _tip_step 124 ; [ "$output" = "0" ]
  run _tip_step 125 ; [ "$output" = "1" ]
  run _tip_step 150 ; [ "$output" = "2" ]
  run _tip_step 999 ; [ "$output" = "3" ]
}

@test "step refuses a projection at or below one hundred" {
  run _tip_step 125
  [ "$output" = "1" ]           # contraprova
  run _tip_step 100
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/tips.bats`
Expected: FAIL — `lib/tips.sh` não existe.

- [ ] **Step 3: Write minimal implementation**

```bash
# lib/tips.sh
# A dica que explica o bloqueio projetado.
#
# A barra já diz `25%→116% 🔒 sex·2d8h`. Os três números são verdadeiros e o
# segundo é ilegível na primeira vez: `→116%` é projeção, não consumo, e a
# leitura intuitiva do par — "gastei 25 de 116" — é o contrário do que a linha
# afirma. Esta lib produz a frase que ensina a ler isso, e some depois.
#
# Spec: docs/superpowers/specs/2026-08-18-tips-bloqueio-projetado-design.md

# Quanto o ritmo precisa cair para a cota pousar em exatamente 100%.
#
# A projeção é `used + ritmo × restante`, e o ritmo que pousa em 100% é
# `(100 − used) / restante`. A razão entre os dois elimina o tempo E o ritmo:
#
#   corte = (proj − 100) / (proj − used)
#
# Nada de relógio, nada de taxa, e a mesma expressão serve às três fontes. O
# número importa porque a intuição erra feio: `→116%` sugere "corte pela
# metade", quando o corte real é 18%. Uma dica que só assusta é pior que
# nenhuma — a pessoa desliga.
#
# `+ den/2` antes de dividir arredonda ao mais próximo em aritmética inteira,
# mesmo truque de sl_pct. Bash 3.2 não tem ponto flutuante.
_tip_cut() {
  local proj="$1" used="$2" num den
  case "$proj" in ''|*[!0-9]*) return 1 ;; esac
  case "$used" in ''|*[!0-9]*) return 1 ;; esac
  [ "$proj" -gt 100 ] || return 1
  num=$(( proj - 100 ))
  den=$(( proj - used ))
  [ "$den" -gt 0 ] || return 1
  printf '%s' "$(( (num * 100 + den / 2) / den ))"
}

# Faixa da projeção, em degraus de 25 pontos.
#
# É o que separa "piorou" de "oscilou". Sem degrau, um `112% → 113%` faria a
# dica reaparecer, e uma dica que volta a cada ponto percentual é a mesma coisa
# que uma dica permanente — que é o que esta feature existe para não ser.
#
# O teto em 3 existe porque `bin/rate-forecast.sh` clampa a projeção em 999:
# sem ele, o degrau continuaria subindo dentro de um número que já parou.
_tip_step() {
  local proj="$1" s
  case "$proj" in ''|*[!0-9]*) return 1 ;; esac
  [ "$proj" -gt 100 ] || return 1
  s=$(( (proj - 100) / 25 ))
  [ "$s" -gt 3 ] && s=3
  printf '%s' "$s"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/tips.bats`
Expected: PASS (6 testes).

- [ ] **Step 5: Commit**

```bash
git add lib/tips.sh tests/tips.bats
git commit -m "feat(tips): cálculo do corte de ritmo e do degrau de projeção"
```

---

### Task 2: promptId e estado

**Files:**
- Modify: `lib/tips.sh`
- Test: `tests/tips.bats`

**Interfaces:**
- Consumes: `_tip_step` (Task 1)
- Produces: `_tip_prompt_id` → id do turno corrente (usa `$SL_TRANSCRIPT`), retorna 1 se indisponível. `_tip_state_get <fonte>` → `degrau<TAB>blocked<TAB>prompt_id`, retorna 1 se ausente. `_tip_state_put <fonte> <degrau> <blocked> <pid>`. `_tip_state_drop <fonte>`. `_tip_should_show <fonte> <proj> <blocked> <now>` → 0 mostra / 1 cala, com efeito colateral de regravar o estado na virada e na piora.

- [ ] **Step 1: Write the failing test**

```bash
# acrescentar a tests/tips.bats

mk_transcript() {   # mk_transcript <promptId>
  printf '{"type":"user","promptId":"%s","message":{"role":"user"}}\n' "$1" \
    > "$BATS_TEST_TMPDIR/transcript.jsonl"
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
  [ "$output" = "turno-A" ]     # contraprova
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run _tip_prompt_id
  [ "$status" -ne 0 ]
}

@test "state round trips a source" {
  _tip_state_put flow 0 1755900000 turno-A
  run _tip_state_get flow
  [ "$output" = "$(printf '0\t1755900000\tturno-A')" ]
}

@test "state keeps sources independent" {
  _tip_state_put flow 0 1755900000 turno-A
  _tip_state_put 7d   2 1755800000 turno-B
  _tip_state_put flow 1 1755700000 turno-C
  run _tip_state_get 7d
  [ "$output" = "$(printf '2\t1755800000\tturno-B')" ]
}

@test "state drops one source and leaves the others" {
  _tip_state_put flow 0 1755900000 turno-A
  _tip_state_put 7d   2 1755800000 turno-B
  _tip_state_drop flow
  run _tip_state_get 7d
  [ "$output" = "$(printf '2\t1755800000\tturno-B')" ]   # contraprova
  run _tip_state_get flow
  [ "$status" -ne 0 ]
}

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
  # faltavam 900000s; a margem é 90000s. Antecipar 200000s passa dela.
  run _tip_should_show flow 116 1755700000 1755000000
  [ "$status" -eq 0 ]
}

@test "stays quiet when the block date barely moved" {
  mk_transcript "turno-A"
  _tip_should_show flow 116 1755900000 1755000000
  mk_transcript "turno-B"
  run _tip_should_show flow 116 1755880000 1755000000   # 20000s < 90000s
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/tips.bats`
Expected: FAIL — `_tip_prompt_id: command not found`.

- [ ] **Step 3: Write minimal implementation**

```bash
# acrescentar a lib/tips.sh

_tip_state_file() {
  printf '%s/tip-state.tsv' "$SL_CACHE_DIR"
}

# O turno corrente, lido do transcript.
#
# `promptId` identifica o TURNO, não a mensagem: tudo que o Claude gera enquanto
# trabalha — inclusive os `tool_result`, que são mensagens `user` — herda o
# promptId do prompt que os originou. É por isso que ele serve e uma contagem de
# mensagens não: medido numa sessão real, 84 entradas `"type":"user"` para 8
# prompts de verdade, porque 71 delas eram tool_result.
#
# `tail -n`, não `tail -c`: as últimas entradas costumam ser `attachment`, que
# não carregam o campo, e um corte por bytes volta vazio. Quarenta linhas cobrem
# a folga com sobra e custam 10 ms num transcript de 2,9 MB.
_tip_prompt_id() {
  local id
  [ -n "$SL_TRANSCRIPT" ] || return 1
  [ -f "$SL_TRANSCRIPT" ] || return 1
  id="$(tail -n 40 "$SL_TRANSCRIPT" 2>/dev/null \
        | grep -o '"promptId":"[^"]*"' | tail -1)"
  [ -n "$id" ] || return 1
  id="${id##*:\"}"
  printf '%s' "${id%\"}"
}

# A linha de uma fonte, sem o nome dela: "degrau<TAB>blocked<TAB>prompt_id".
_tip_state_get() {
  local src="$1" file line f
  file="$(_tip_state_file)"
  [ -r "$file" ] || return 1
  # `|| [ -n "$line" ]` cobre arquivo sem quebra final: read devolve não-zero
  # ao encontrar EOF mesmo tendo preenchido a variável.
  while IFS= read -r line || [ -n "$line" ]; do
    f="${line%%	*}"
    [ "$f" = "$src" ] || continue
    printf '%s' "${line#*	}"
    return 0
  done < "$file"
  return 1
}

# Regrava a linha de uma fonte, preservando as outras.
#
# Escreve em temporário e move: dois terminais repintando ao mesmo tempo
# poderiam ler o arquivo no meio de uma reescrita in-place.
_tip_state_put() {
  local src="$1" step="$2" blocked="$3" pid="$4" file tmp line f
  file="$(_tip_state_file)"
  tmp="$file.$$"
  mkdir -p "$SL_CACHE_DIR" 2>/dev/null || return 0
  : > "$tmp" 2>/dev/null || return 0
  if [ -r "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      f="${line%%	*}"
      [ "$f" = "$src" ] && continue
      printf '%s\n' "$line"
    done < "$file" >> "$tmp"
  fi
  printf '%s\t%s\t%s\t%s\n' "$src" "$step" "$blocked" "$pid" >> "$tmp"
  mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# Remove a linha de uma fonte. Arquivo que fica vazio é apagado: ausência é o
# estado normal, e é o que faz o widget custar um `[ -f ]`.
_tip_state_drop() {
  local src="$1" file tmp line f
  file="$(_tip_state_file)"
  [ -r "$file" ] || return 0
  tmp="$file.$$"
  : > "$tmp" 2>/dev/null || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    f="${line%%	*}"
    [ "$f" = "$src" ] && continue
    printf '%s\n' "$line"
  done < "$file" >> "$tmp"
  if [ -s "$tmp" ]; then
    mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" "$file" 2>/dev/null
  fi
}

# Decide se esta fonte fala agora, e registra o que foi dito.
#
# Três motivos para falar: é a primeira vez; a projeção subiu de degrau; a data
# de bloqueio antecipou mais de 10% do que faltava. Fora isso, a dica continua
# na tela enquanto for o mesmo turno e cala no próximo — que é o que a faz
# esperar por quem saiu para almoçar, em vez de morrer no relógio.
#
# A regra dos 10% é relativa de propósito: antecipar duas horas numa trava que
# estava a três dias não muda decisão nenhuma; as mesmas duas horas numa que
# estava a seis mudam tudo.
_tip_should_show() {
  local src="$1" proj="$2" blocked="$3" now="$4"
  local step prev pstep pblocked ppid pid margin

  step="$(_tip_step "$proj")" || return 1
  pid="$(_tip_prompt_id)" || pid="-"

  if ! prev="$(_tip_state_get "$src")"; then
    _tip_state_put "$src" "$step" "$blocked" "$pid"
    return 0
  fi

  pstep="${prev%%	*}"
  prev="${prev#*	}"
  pblocked="${prev%%	*}"
  ppid="${prev#*	}"

  case "$pstep"    in ''|*[!0-9]*) pstep=0 ;;    esac
  case "$pblocked" in ''|*[!0-9]*) pblocked=0 ;; esac

  if [ "$step" -gt "$pstep" ]; then
    _tip_state_put "$src" "$step" "$blocked" "$pid"
    return 0
  fi

  if [ "$pblocked" -gt 0 ] && [ "$blocked" -lt "$pblocked" ]; then
    margin=$(( (pblocked - now) / 10 ))
    [ "$margin" -ge 0 ] || margin=0
    if [ $(( pblocked - blocked )) -gt "$margin" ]; then
      _tip_state_put "$src" "$step" "$blocked" "$pid"
      return 0
    fi
  fi

  [ "$pid" = "$ppid" ] || return 1
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/tips.bats`
Expected: PASS (17 testes).

- [ ] **Step 5: Commit**

```bash
git add lib/tips.sh tests/tips.bats
git commit -m "feat(tips): estado por fonte e regra de virada, piora e turno"
```

---

### Task 3: leitura das fontes

**Files:**
- Modify: `lib/tips.sh`
- Test: `tests/tips.bats`

**Interfaces:**
- Consumes: `sl_config_widget_opt`, `sl_jq`, `sl_round`
- Produces: `_tip_widget_configured <nome>` → 0/1. `_tip_flow_source` → `proj used blocked reset`. `_tip_rf_source <5h|7d>` → `proj used blocked reset`. Todas retornam 1 quando não há bloqueio projetado.

- [ ] **Step 1: Write the failing test**

```bash
# acrescentar a tests/tips.bats — e ao setup(), estas fontes:
#   source "$PROJECT_ROOT/lib/colors.sh"
#   source "$PROJECT_ROOT/lib/core.sh"
#   source "$PROJECT_ROOT/lib/num.sh"
#   source "$PROJECT_ROOT/lib/cache.sh"
#   source "$PROJECT_ROOT/lib/config.sh"
#   SL_CONFIG_RAW=""
#   SL_CONFIG_LINES="repo branch
# context rate-forecast flow
# tip"

write_flow() {   # write_flow <pct> <proj> <blocked|null>
  cat > "$BATS_TEST_TMPDIR/flow.json" <<EOF
{"ok":true,
 "budget":{"percentage":$1,"projected_percentage":$2,"blocked_epoch":$3,"renewal_epoch":1756100000},
 "requests":{"percentage":5,"projected_percentage":null,"renewal_epoch":1756100000}}
EOF
  export SL_FLOW_TEST_CACHE="$BATS_TEST_TMPDIR/flow.json"
}

@test "flow source reports projection, usage and block date" {
  write_flow 25 116.4 1755900000
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$SL_FLOW_TEST_CACHE\"}}}"
  run _tip_flow_source
  [ "$output" = "116 25 1755900000 1756100000" ]
}

@test "flow source stays silent without a block date" {
  write_flow 25 116.4 1755900000
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$SL_FLOW_TEST_CACHE\"}}}"
  run _tip_flow_source
  [ "$output" = "116 25 1755900000 1756100000" ]   # contraprova
  write_flow 25 48.0 null
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$SL_FLOW_TEST_CACHE\"}}}"
  run _tip_flow_source
  [ "$status" -ne 0 ]
}

@test "flow source stays silent when the widget is not on the bar" {
  write_flow 25 116.4 1755900000
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$SL_FLOW_TEST_CACHE\"}}}"
  run _tip_flow_source
  [ "$output" = "116 25 1755900000 1756100000" ]   # contraprova
  SL_CONFIG_LINES="repo branch
context rate-forecast
tip"
  run _tip_flow_source
  [ "$status" -ne 0 ]
}

@test "rate forecast source reports what the helper projects" {
  cat > "$BATS_TEST_TMPDIR/fake-forecast.sh" <<'EOF'
#!/usr/bin/env bash
printf 'crit 134 1755870000\n'
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_FORECAST_BIN="$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_7D_PCT=23.4
  SL_7D_RESET=1756000000
  run _tip_rf_source 7d
  [ "$output" = "134 23 1755870000 1756000000" ]
}

@test "rate forecast source stays silent when the helper reports no block" {
  cat > "$BATS_TEST_TMPDIR/fake-forecast.sh" <<'EOF'
#!/usr/bin/env bash
printf 'crit 134 1755870000\n'
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_FORECAST_BIN="$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_7D_PCT=23.4
  SL_7D_RESET=1756000000
  run _tip_rf_source 7d
  [ "$output" = "134 23 1755870000 1756000000" ]   # contraprova
  cat > "$BATS_TEST_TMPDIR/fake-forecast.sh" <<'EOF'
#!/usr/bin/env bash
printf 'warn 92\n'
EOF
  run _tip_rf_source 7d
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/tips.bats`
Expected: FAIL — `_tip_flow_source: command not found`.

- [ ] **Step 3: Write minimal implementation**

```bash
# acrescentar a lib/tips.sh

# O bin do forecast, com o mesmo default de widgets/rate-forecast.sh. Duplicado
# de propósito: `lib/tips.sh` precisa funcionar quando carregada antes do widget,
# e `: "${VAR:=...}"` não sobrescreve quem já definiu.
: "${SL_FORECAST_BIN:=${SL_ROOT:-$HOME/.claude}/bin/rate-forecast.sh}"

SL_TIP_FLOW_DEFAULT_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flow-consumption.json"

# A dica só fala do que está na tela.
#
# Quem tirou o `rate-forecast` da barra não vê `→116%`, e uma dica que explica o
# que a pessoa está vendo não teria o que explicar. É também o que impede o tip
# de chamar o bin do forecast por conta própria e amostrar sozinho.
#
# SL_CONFIG_LINES é uma lista separada por quebras de linha; o `tr` a achata para
# que um `case` com espaços consiga casar palavra inteira.
_tip_widget_configured() {
  local name="$1" hay
  hay=" $(printf '%s' "$SL_CONFIG_LINES" | tr '\n' ' ') "
  case "$hay" in
    *" $name "*) return 0 ;;
  esac
  return 1
}

# Flow: o JSON do fetcher já traz projeção e data de bloqueio prontas.
#
# Das duas cotas, responde a que trava PRIMEIRO — é a que decide o que fazer
# hoje. `blocked_epoch` ausente é o sinal de "não há bloqueio projetado": o
# fetcher só o grava quando a projeção passa de 100%.
_tip_flow_source() {
  local file raw
  _tip_widget_configured flow || return 1
  file="$(sl_config_widget_opt flow cache "$SL_TIP_FLOW_DEFAULT_CACHE")"
  [ -r "$file" ] || return 1
  raw="$(sl_jq -r '
    if (.ok | not) then empty
    else
      [ .budget, .requests ]
      | map(select(. != null
                   and .blocked_epoch != null
                   and .projected_percentage != null))
      | sort_by(.blocked_epoch)
      | if length == 0 then empty
        else .[0]
             | "\(.projected_percentage) \(.percentage) \(.blocked_epoch) \(.renewal_epoch // 0)"
        end
    end' "$file" 2>/dev/null)" || return 1
  [ -n "$raw" ] || return 1
  set -- $raw
  printf '%s %s %s %s' "$(sl_round "$1")" "$(sl_round "$2")" "$3" "$4"
}

# 5h e 7d: a projeção vem do mesmo helper que o widget usa, com os mesmos
# argumentos — inclusive o `pct` sem arredondar, porque o helper deriva uma taxa
# da diferença entre leituras e o arredondamento viraria degrau de 1 ponto.
#
# Chamar o helper uma segunda vez no mesmo repaint não grava amostra espúria:
# ele só registra quando `now − last_ts ≥ 60`, e o widget rate-forecast já
# amostrou no mesmo segundo.
_tip_rf_source() {
  local window="$1" pct reset secs raw
  _tip_widget_configured rate-forecast || return 1
  case "$window" in
    5h) pct="$SL_5H_PCT"; reset="$SL_5H_RESET"; secs=18000  ;;
    7d) pct="$SL_7D_PCT"; reset="$SL_7D_RESET"; secs=604800 ;;
    *)  return 1 ;;
  esac
  [ -n "$pct" ] || return 1
  [ -n "$reset" ] || return 1
  [ -x "$SL_FORECAST_BIN" ] || return 1
  raw="$("$SL_FORECAST_BIN" "$window" "$pct" "$reset" "$secs" 2>/dev/null)" || return 1
  set -- $raw
  case "$1" in ok|warn|crit) ;; *) return 1 ;; esac
  # O terceiro campo só existe quando a projeção passa de 100% e o estouro cai
  # antes do reset. Sem ele não há bloqueio a anunciar.
  [ -n "$3" ] || return 1
  printf '%s %s %s %s' "$2" "$(sl_round "$pct")" "$3" "$reset"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/tips.bats`
Expected: PASS (22 testes).

- [ ] **Step 5: Commit**

```bash
git add lib/tips.sh tests/tips.bats
git commit -m "feat(tips): leitura das fontes flow, 5h e 7d"
```

---

### Task 4: as frases

**Files:**
- Modify: `lib/tips.sh`
- Test: `tests/tips.bats`

**Interfaces:**
- Consumes: `_tip_cut` (Task 1), `sl_fmt_countdown`
- Produces: `_tip_phrase <fonte> <proj> <used> <blocked> <reset>` → uma linha de texto, retorna 1 se a fonte for desconhecida ou se o 5h estiver dentro do piso de 15 min.

- [ ] **Step 1: Write the failing test**

```bash
# acrescentar a tests/tips.bats — e ao setup():
#   source "$PROJECT_ROOT/lib/timefmt.sh"

@test "flow phrase corrects the reading and gives the slowdown target" {
  run _tip_phrase flow 116 25 1755900000 1756100000
  [ "$output" = "Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}

@test "seven day phrase names its own window" {
  run _tip_phrase 7d 134 23 1755870000 1756000000
  [ "$output" = "Dica da janela 7d: →134% é projeção, não gasto — cortar 25% do ritmo evita" ]
}

@test "five hour phrase trades the reading fix for the length of the pause" {
  # trava 3000s antes do reset = 50 min parado
  run _tip_phrase 5h 118 60 1755897000 1755900000
  [ "$output" = "Dica da janela 5h: →118% é projeção — cortar 12% evita 50m parado" ]
}

@test "five hour phrase stays silent when the pause is shorter than the floor" {
  run _tip_phrase 5h 118 60 1755897000 1755900000
  [ "$output" = "Dica da janela 5h: →118% é projeção — cortar 12% evita 50m parado" ]  # contraprova
  # trava 600s antes do reset = 10 min, abaixo do piso de 15
  run _tip_phrase 5h 118 60 1755899400 1755900000
  [ "$status" -ne 0 ]
}

@test "every phrase fits in eighty columns" {
  run _tip_phrase flow 116 25 1755900000 1756100000
  [ "${#output}" -le 80 ]
  run _tip_phrase 7d 134 23 1755870000 1756000000
  [ "${#output}" -le 80 ]
  run _tip_phrase 5h 118 60 1755897000 1755900000
  [ "${#output}" -le 80 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/tips.bats`
Expected: FAIL — `_tip_phrase: command not found`.

- [ ] **Step 3: Write minimal implementation**

```bash
# acrescentar a lib/tips.sh

# Piso da pausa do 5h. Travar quatro minutos antes de a janela virar não vale
# uma linha na barra: a janela renova em horas, e o custo de estourar ali é uma
# pausa, não um bloqueio.
SL_TIP_5H_MIN_PAUSE=900

# A frase de uma fonte, em uma linha de no máximo 80 colunas.
#
# Nenhuma data aparece aqui, e isso é decisão, não esquecimento: `🔒 Fri·2d8h` e
# `⟳` já estão na linha de cima, cada um com seu formato decidido. Repetir a
# data custava trinta colunas para não acrescentar nada — e foi o que estourou
# os 80 caracteres no primeiro rascunho.
#
# Sobra o que a barra NÃO consegue dizer: que o número é projeção e não consumo,
# e quanto o ritmo precisa cair.
#
# "No ritmo atual" nunca vira "nas últimas 3h": o flow-consumption.json entrega
# `projected_percentage` pronto sem dizer sobre que período, e o
# bin/rate-forecast.sh reporta o MAIOR entre duas projeções. Nomear uma janela
# que a fonte não afirma é inventar precisão, numa frase cujo trabalho é ensinar
# a ler um número.
_tip_phrase() {
  local src="$1" proj="$2" used="$3" blocked="$4" reset="$5"
  local cut label pause gap

  cut="$(_tip_cut "$proj" "$used")" || cut=""

  case "$src" in
    flow) label="Dica do Flow" ;;
    5h)   label="Dica da janela 5h" ;;
    7d)   label="Dica da janela 7d" ;;
    *)    return 1 ;;
  esac

  if [ "$src" = "5h" ]; then
    case "$reset$blocked" in *[!0-9]*) return 1 ;; esac
    gap=$(( reset - blocked ))
    [ "$gap" -ge "$SL_TIP_5H_MIN_PAUSE" ] || return 1
    pause="$(sl_fmt_countdown "$gap")"
    if [ -n "$cut" ]; then
      printf 'Dica da janela 5h: →%s%% é projeção — cortar %s%% evita %s parado' \
        "$proj" "$cut" "$pause"
    else
      printf 'Dica da janela 5h: →%s%% é projeção — %s parado se o ritmo seguir' \
        "$proj" "$pause"
    fi
    return 0
  fi

  if [ -n "$cut" ]; then
    if [ "$src" = "flow" ]; then
      printf '%s: →%s%% é projeção, não gasto — cortar %s%% do ritmo evita a trava' \
        "$label" "$proj" "$cut"
    else
      printf '%s: →%s%% é projeção, não gasto — cortar %s%% do ritmo evita' \
        "$label" "$proj" "$cut"
    fi
  else
    printf '%s: →%s%% é projeção, não gasto — a cota trava antes de renovar' \
      "$label" "$proj"
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/tips.bats`
Expected: PASS (27 testes).

- [ ] **Step 5: Commit**

```bash
git add lib/tips.sh tests/tips.bats
git commit -m "feat(tips): as frases das três fontes, em 80 colunas"
```

---

### Task 5: o widget

**Files:**
- Create: `widgets/tip.sh`
- Modify: `bin/statusline.sh:17` (acrescentar o source de `lib/tips.sh`)
- Test: `tests/widgets/tip.bats`

**Interfaces:**
- Consumes: tudo de `lib/tips.sh`
- Produces: `widget_tip_render` → uma linha por fonte em alerta, separadas por `\n`; vazio quando não há nada a dizer.

- [ ] **Step 1: Write the failing test**

```bash
# tests/widgets/tip.bats
load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/num.sh"
  source "$PROJECT_ROOT/lib/timefmt.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/tips.sh"
  source "$PROJECT_ROOT/widgets/tip.sh"
  SL_CONFIG_LINES="repo branch
context rate-forecast flow
tip"
  printf '{"type":"user","promptId":"turno-A"}\n' > "$BATS_TEST_TMPDIR/t.jsonl"
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
  SL_NOW=1755000000
  FLOW="$BATS_TEST_TMPDIR/flow.json"
  SL_CONFIG_RAW="{\"widgets\":{\"flow\":{\"cache\":\"$FLOW\"}}}"
}

write_flow() {   # write_flow <pct> <proj> <blocked|null>
  cat > "$FLOW" <<EOF
{"ok":true,
 "budget":{"percentage":$1,"projected_percentage":$2,"blocked_epoch":$3,"renewal_epoch":1756100000},
 "requests":{"percentage":5,"projected_percentage":null,"renewal_epoch":1756100000}}
EOF
}

@test "renders the flow tip when a block is projected" {
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ "$output" = "Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}

@test "renders nothing when no source projects a block" {
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ -n "$output" ]                      # contraprova
  write_flow 25 48.0 null
  run widget_tip_render
  [ "$output" = "" ]
}

@test "renders nothing on a later turn when nothing got worse" {
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ -n "$output" ]                      # contraprova
  widget_tip_render >/dev/null          # grava o estado no turno A
  printf '{"type":"user","promptId":"turno-B"}\n' > "$BATS_TEST_TMPDIR/t.jsonl"
  run widget_tip_render
  [ "$output" = "" ]
}

@test "renders one line per source when two of them fire" {
  cat > "$BATS_TEST_TMPDIR/fake-forecast.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "7d" ] && printf 'crit 134 1755870000\n' || printf 'ok 40\n'
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_FORECAST_BIN="$BATS_TEST_TMPDIR/fake-forecast.sh"
  SL_5H_PCT=12 ; SL_5H_RESET=1755010000
  SL_7D_PCT=23 ; SL_7D_RESET=1756000000
  write_flow 25 116.4 1755900000
  run widget_tip_render
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
  [ "${lines[1]}" = "Dica da janela 7d: →134% é projeção, não gasto — cortar 25% do ritmo evita" ]
}

@test "renders anyway when the transcript is missing" {
  write_flow 25 116.4 1755900000
  export SL_TRANSCRIPT="$BATS_TEST_TMPDIR/nao-existe.jsonl"
  run widget_tip_render
  [ "$output" = "Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}

@test "survives a corrupted state file" {
  write_flow 25 116.4 1755900000
  mkdir -p "$SL_CACHE_DIR"
  printf 'lixo sem tabs\n\n\t\t\n' > "$SL_CACHE_DIR/tip-state.tsv"
  run widget_tip_render
  [ "$status" -eq 0 ]
  [ "$output" = "Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/widgets/tip.bats`
Expected: FAIL — `widgets/tip.sh` não existe.

- [ ] **Step 3: Write minimal implementation**

```bash
# widgets/tip.sh
# A dica que explica o bloqueio projetado.
#
# Este widget não mostra dado novo: ele explica o que a linha de cima já mostra.
# `Flow 💰 25%→116% 🔒 sex·2d8h` é denso e correto, e ilegível na primeira vez —
# a leitura intuitiva de `25%` ao lado de `116%` é "gastei 25 de 116", que é o
# contrário do que a linha afirma. A dica corrige isso, diz quanto o ritmo
# precisa cair, e some no próximo prompt do usuário.
#
# ── Por que ele fica sozinho numa linha ──
#
# Quando duas fontes projetam bloqueio, o widget emite duas linhas separadas por
# `\n`, e o núcleo as preserva. Dividindo a linha com outro widget, esse `\n`
# quebraria a montagem de separadores no meio. A configuração sugerida põe
# `tip` numa linha própria; uma linha que renderiza vazio não é desenhada, então
# ela não custa nada enquanto não há o que dizer.
#
# ── Por que ele lê as fontes de novo ──
#
# O caminho óbvio seria os widgets `flow` e `rate-forecast` publicarem o que já
# calcularam. Não funciona: o núcleo captura widget com `out="$("$fn")"`, que é
# subshell, e global atribuída lá dentro morre no retorno. É o isolamento que
# docs/superpowers/decisions/2026-08-08-canal-de-retorno.md celebra, valendo
# contra nós.
#
# Spec: docs/superpowers/specs/2026-08-18-tips-bloqueio-projetado-design.md

register_widget tip \
  --render widget_tip_render \
  --self-color \
  --desc   "Explains a projected quota block and how much to slow down"

# Tempo é entrada, não relógio — mesma razão de widgets/rate-forecast.sh: sem
# isso a suíte passaria a depender do dia em que roda.
_tip_now() {
  if [ -n "$SL_NOW" ]; then printf '%s' "$SL_NOW"; else date +%s; fi
}

# Uma fonte: colhe, decide e formata. Retorna 1 quando não há o que dizer.
_tip_one() {
  local src="$1" raw proj used blocked reset now

  case "$src" in
    flow) raw="$(_tip_flow_source)"      || return 1 ;;
    *)    raw="$(_tip_rf_source "$src")" || return 1 ;;
  esac

  set -- $raw
  proj="$1"; used="$2"; blocked="$3"; reset="$4"

  # A frase vem ANTES da decisão de mostrar: o 5h pode recusar por causa do piso
  # de 15 minutos, e nesse caso a fonte não deve sequer gravar estado — senão
  # ela consumiria a virada em silêncio e a dica nunca apareceria.
  local phrase
  phrase="$(_tip_phrase "$src" "$proj" "$used" "$blocked" "$reset")" || return 1

  now="$(_tip_now)"
  _tip_should_show "$src" "$proj" "$blocked" "$now" || return 1

  printf '%s' "$phrase"
}

widget_tip_render() {
  local src piece out=""

  # Ordem fixa: Flow primeiro, porque a cota do provedor é a que bloqueia por
  # dias; depois a janela mais longa. Ordem estável importa mais do que qual é a
  # ordem — uma linha que troca de lugar entre repaints é lida como mudança.
  for src in flow 7d 5h; do
    if piece="$(_tip_one "$src")"; then
      out="${out}${out:+
}${piece}"
    else
      # Fonte que parou de projetar bloqueio esquece o que já disse, e volta a
      # falar se a condição retornar.
      _tip_state_drop "$src"
    fi
  done

  [ -n "$out" ] || return 0
  printf '%s' "$out"
}
```

- [ ] **Step 4: Carregar a lib no entrypoint**

Em `bin/statusline.sh`, depois da linha `. "$SL_ROOT/lib/num.sh"`:

```bash
# Depois de num.sh e timefmt.sh: lib/tips.sh usa sl_round e sl_fmt_countdown.
. "$SL_ROOT/lib/tips.sh"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats -r tests`
Expected: PASS — os 571 que já existiam mais os novos.

- [ ] **Step 6: Commit**

```bash
git add widgets/tip.sh tests/widgets/tip.bats bin/statusline.sh
git commit -m "feat(tips): widget tip, uma linha por fonte em alerta"
```

---

### Task 6: documentação e configuração sugerida

**Files:**
- Modify: `commands/setup.md` (Passo 5, o JSON de configuração)
- Modify: `README.md` (lista de widgets e seção do widget)
- Modify: `lib/config.sh:19-20` (`SL_CONFIG_DEFAULT_LINES`)

**Interfaces:**
- Consumes: `widget_tip_render` (Task 5)
- Produces: nada — é documentação e default.

- [ ] **Step 1: Acrescentar `tip` ao default de `lib/config.sh`**

A constante hoje tem duas linhas; passa a ter três:

```bash
SL_CONFIG_DEFAULT_LINES='repo branch git-status worktree velocity cache cost flow model
context rate-forecast sprint
tip'
```

O comentário acima dela manda manter isto em sincronia com o Passo 5 de
`commands/setup.md` — os dois precisam mudar juntos.

- [ ] **Step 2: Verificar que o default não quebra a suíte**

Run: `bats -r tests`
Expected: PASS. Se algum teste afirmar o valor literal de `SL_CONFIG_DEFAULT_LINES`, atualizá-lo — a mudança é intencional.

- [ ] **Step 3: Atualizar `commands/setup.md`**

No JSON do Passo 5, acrescentar `"tip"` como terceira linha do array `lines`, espelhando exatamente o valor do Step 1.

- [ ] **Step 4: Documentar no README**

Acrescentar `tip` à tabela de widgets, com a descrição: "Explica um bloqueio de cota projetado e quanto o ritmo precisa cair. Aparece só quando Flow, 5h ou 7d projetam estouro; some no próximo prompt."

E uma seção própria, seguindo o formato das outras, cobrindo: que ela é aditiva (nada muda nos outros widgets), que precisa ficar sozinha na linha, que fala apenas de fontes cujos widgets estão configurados, e que desligar é tirar `tip` de `lines`.

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh commands/setup.md README.md
git commit -m "docs(tips): documenta o widget e o inclui na configuração padrão"
```

---

## Self-Review

**Cobertura da spec:**

| Seção da spec | Task |
| ------------- | ---- |
| Onde a dica aparece / uma linha por fonte | 5 |
| Quando falar (virada, degrau, data) | 2 |
| Quando some (promptId) | 2 |
| A meta de corte | 1 |
| Peças / tip autossuficiente | 3, 5 |
| Só fala do que está na tela | 3 |
| Estado | 2 |
| As frases / 80 colunas / piso do 5h | 4 |
| Configuração | 6 |
| Testes | 1–5 |

**Consistência de nomes:** `_tip_cut`, `_tip_step`, `_tip_prompt_id`, `_tip_state_file`, `_tip_state_get`, `_tip_state_put`, `_tip_state_drop`, `_tip_should_show`, `_tip_widget_configured`, `_tip_flow_source`, `_tip_rf_source`, `_tip_phrase`, `_tip_now`, `_tip_one`, `widget_tip_render`. Cada uma é definida em uma task e consumida com a mesma assinatura nas seguintes.

**Contrato de campos:** as três fontes devolvem `proj used blocked reset`, nessa ordem, com `proj` e `used` já arredondados por `sl_round`. `_tip_phrase` e `_tip_should_show` consomem nessa ordem.
