# tips de cache — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** generalizar o contrato de fonte do widget `tip` e acrescentar duas dicas de cache que dizem quanto custa regravar o prefixo e a partir de quantas trocas isso se paga.

**Architecture:** cada fonte passa a devolver `"<chave><TAB><frase>"` e recebe a chave anterior, decidindo ela mesma o que conta como mudança material. O widget só compara chaves. As fontes de cache derivam o preço do input do custo real da sessão, usando a invariante output = 5× input.

**Tech Stack:** bash 3.2, awk, jq, bats.

**Spec:** `docs/superpowers/specs/2026-08-19-tips-de-cache-design.md`

## Global Constraints

- **bash 3.2** — `$(( ))` só faz inteiro; toda aritmética com fração vai para `awk`.
- **Nunca `set -e`** em entrypoint; retorno não-zero não pode apagar a statusline.
- **Frases ≤ 80 colunas**, medidas com `tip_width` (caracteres, não bytes).
- **As frases de flow, 5h e 7d não podem mudar** — os testes que as afirmam não podem ser editados. É essa a prova do refactor.
- **Chaves obrigatórias em `${var}`** antes de byte > 127.
- Comentários em português, explicando o *porquê*.

## File Structure

| Arquivo | Responsabilidade |
| ------- | ---------------- |
| `lib/tips.sh` (modificar) | contrato de fonte, preço derivado, as cinco fontes |
| `widgets/tip.sh` (modificar) | itera `SL_TIP_SOURCES`, compara chaves |
| `tests/tips.bats` (modificar) | testes das funções novas; os antigos ficam intactos |
| `tests/widgets/tip.bats` (modificar) | contrato generalizado; asserções de frase intactas |
| `README.md` (modificar) | seção do `tip` ganha as dicas de cache |

---

### Task 1: contrato de fonte generalizado

**Files:**
- Modify: `lib/tips.sh`, `widgets/tip.sh`
- Test: `tests/tips.bats`, `tests/widgets/tip.bats`

**Interfaces:**
- Produces: `_tip_slug <nome>` → nome com `-` virado `_`. `_tip_flow_key <prev> <step> <blocked> <now>` → chave, preservando a anterior quando nada material mudou. `_tip_src_flow <prev>` / `_tip_src_7d <prev>` / `_tip_src_5h <prev>` → `"<chave><TAB><frase>"` ou 1. `SL_TIP_SOURCES`.
- Consumes: `_tip_cut`, `_tip_step`, `_tip_flow_source`, `_tip_rf_source`, `_tip_state_*`, `_tip_prompt_id` (todos já existem).

- [ ] **Step 1: Write the failing test**

```bash
# acrescentar a tests/tips.bats

@test "slug turns a dashed source name into a function suffix" {
  run _tip_slug cache-cold
  [ "$output" = "cache_cold" ]
}

@test "flow key changes when the step goes up" {
  run _tip_flow_key "0:1755900000" 1 1755900000 1755000000
  [ "$output" = "1:1755900000" ]
}

@test "flow key survives a block date that barely moved" {
  # faltavam 900000s, margem 90000s; andou 20000s
  run _tip_flow_key "0:1755900000" 0 1755880000 1755000000
  [ "$output" = "0:1755900000" ]
}

@test "flow key changes when the block date moved materially" {
  run _tip_flow_key "0:1755900000" 0 1755700000 1755000000
  [ "$output" = "0:1755700000" ]
}

@test "flow key with no previous state is the current one" {
  run _tip_flow_key "" 0 1755900000 1755000000
  [ "$output" = "0:1755900000" ]
}

@test "flow source emits a key and the same phrase as before" {
  write_flow 25 116.4 1755900000
  run _tip_src_flow ""
  [ "$output" = "$(printf '0:1755900000\tDica do Flow: →116%% é projeção, não gasto — cortar 18%% do ritmo evita a trava')" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/tips.bats`
Expected: FAIL — `_tip_slug: command not found`.

- [ ] **Step 3: Write the implementation**

Em `lib/tips.sh`, **substituir** `_tip_should_show` e `_tip_phrase` por:

```bash
# ── O contrato de fonte ──
#
# Cada fonte devolve "<chave><TAB><frase>", e recebe a chave que ela mesma
# devolveu da última vez.
#
# A chave é opaca para o widget: ele só compara com a gravada. Quem sabe o que
# conta como mudança material é a fonte — e isso não é preferência de estilo. O
# flow considera "piorou" um degrau a mais OU uma antecipação acima de 10% do
# que faltava; comparada por igualdade simples, uma data que andou um segundo
# produziria chave nova e a dica voltaria a cada repaint.
SL_TIP_SOURCES="flow 7d 5h"

# Hífen não é legal em nome de função. Mesma conversão que _sl_slug faz em
# lib/core.sh, pelo mesmo motivo.
_tip_slug() {
  local n="$1"
  printf '%s' "${n//-/_}"
}

# A chave do flow e das janelas: "<degrau>:<blocked>".
#
# Devolve a chave ANTERIOR quando nada material mudou — é assim que a regra dos
# 10% sobrevive à comparação por igualdade. A margem é relativa de propósito:
# antecipar duas horas numa trava que estava a três dias não muda decisão
# nenhuma; as mesmas duas horas numa que estava a seis mudam tudo.
_tip_flow_key() {
  local prev="$1" step="$2" blocked="$3" now="$4" pstep pblocked margin
  [ -n "$prev" ] || { printf '%s:%s' "$step" "$blocked"; return 0; }

  pstep="${prev%%:*}"
  pblocked="${prev##*:}"
  case "$pstep"    in ''|*[!0-9]*) pstep=0 ;;    esac
  case "$pblocked" in ''|*[!0-9]*) pblocked=0 ;; esac

  if [ "$step" -gt "$pstep" ]; then
    printf '%s:%s' "$step" "$blocked"; return 0
  fi

  if [ "$pblocked" -gt 0 ] && [ "$blocked" -lt "$pblocked" ]; then
    margin=$(( (pblocked - now) / 10 ))
    [ "$margin" -ge 0 ] || margin=0
    if [ $(( pblocked - blocked )) -gt "$margin" ]; then
      printf '%s:%s' "$step" "$blocked"; return 0
    fi
  fi

  printf '%s' "$prev"
}

# As três fontes de projeção. A frase é a mesma de antes, palavra por palavra:
# os testes que a afirmam não foram editados, e é isso que prova o refactor.
_tip_src_projection() {
  local src="$1" prev="$2" raw proj used blocked reset now key cut label

  case "$src" in
    flow) raw="$(_tip_flow_source)"      || return 1 ;;
    *)    raw="$(_tip_rf_source "$src")" || return 1 ;;
  esac

  set -- $raw
  proj="$1"; used="$2"; blocked="$3"; reset="$4"

  now="$(_tip_now)"

  # Data de bloqueio no passado não é dica: sl_stamp_label recusa formatá-la, o
  # widget da fonte esconde o cadeado, e a barra não mostra bloqueio nenhum.
  case "$blocked" in ''|*[!0-9]*) return 1 ;; esac
  [ "$blocked" -gt "$now" ] || return 1

  local step
  step="$(_tip_step "$proj")" || return 1
  cut="$(_tip_cut "$proj" "$used")" || cut=""

  if [ "$src" = "5h" ]; then
    local gap pause
    case "$reset" in ''|*[!0-9]*) return 1 ;; esac
    gap=$(( reset - blocked ))
    [ "$gap" -ge "$SL_TIP_5H_MIN_PAUSE" ] || return 1
    pause="$(sl_fmt_countdown "$gap")"
    key="$(_tip_flow_key "$prev" "$step" "$blocked" "$now")"
    if [ -n "$cut" ]; then
      printf '%s\tDica da janela 5h: →%s%% é projeção — cortar %s%% evita %s parado' \
        "$key" "$proj" "$cut" "$pause"
    else
      printf '%s\tDica da janela 5h: →%s%% é projeção — %s parado se o ritmo seguir' \
        "$key" "$proj" "$pause"
    fi
    return 0
  fi

  if [ "$src" = "flow" ]; then label="Dica do Flow"; else label="Dica da janela 7d"; fi
  key="$(_tip_flow_key "$prev" "$step" "$blocked" "$now")"

  if [ -n "$cut" ]; then
    if [ "$src" = "flow" ]; then
      printf '%s\t%s: →%s%% é projeção, não gasto — cortar %s%% do ritmo evita a trava' \
        "$key" "$label" "$proj" "$cut"
    else
      printf '%s\t%s: →%s%% é projeção, não gasto — cortar %s%% do ritmo evita' \
        "$key" "$label" "$proj" "$cut"
    fi
  else
    printf '%s\t%s: →%s%% é projeção, não gasto — a cota trava antes de renovar' \
      "$key" "$label" "$proj"
  fi
}

_tip_src_flow() { _tip_src_projection flow "$1"; }
_tip_src_7d()   { _tip_src_projection 7d   "$1"; }
_tip_src_5h()   { _tip_src_projection 5h   "$1"; }
```

`_tip_now` sai de `widgets/tip.sh` para `lib/tips.sh` (as fontes precisam dele, e o widget continua funcionando por já ter a lib carregada).

Em `widgets/tip.sh`, **substituir** `_tip_one` e o laço por:

```bash
# Uma fonte: chama, compara a chave com a gravada, decide.
_tip_one() {
  local src="$1" fn out key phrase prev pkey ppid pid

  fn="_tip_src_$(_tip_slug "$src")"
  command -v "$fn" >/dev/null 2>&1 || return 1

  prev="$(_tip_state_get "$src")" || prev=""
  pkey="${prev%% *}"
  ppid="${prev#* }"
  [ -n "$prev" ] || { pkey=""; ppid=""; }

  out="$("$fn" "$pkey")" || return 1
  key="${out%%	*}"
  phrase="${out#*	}"
  [ -n "$phrase" ] || return 1

  pid="$(_tip_prompt_id)" || pid="-"

  # Chave nova carimba o turno corrente — é assim que a dica reaparece quando
  # algo piorou, sem código de reexibição. Chave igual só continua na tela
  # enquanto o turno for o mesmo.
  if [ "$key" != "$pkey" ]; then
    _tip_state_put "$src" "$key" "$pid"
  else
    [ "$pid" = "$ppid" ] || return 1
  fi

  printf '%s' "$phrase"
}

widget_tip_render() {
  local src piece out=""

  # Ordem fixa e estável: uma linha que troca de lugar entre repaints é lida
  # como mudança, e a dica existe para o momento em que algo mudou.
  for src in $SL_TIP_SOURCES; do
    if piece="$(_tip_one "$src")"; then
      out="${out}${out:+
}${piece}"
    else
      _tip_state_drop "$src"
    fi
  done

  [ -n "$out" ] || return 0
  printf '%s' "$out"
}
```

`_tip_state_put` e `_tip_state_get` passam a três colunas: `fonte`, `chave`, `prompt_id`.

- [ ] **Step 4: Run all tests**

Run: `bats -r tests`
Expected: PASS. **Nenhum teste de frase pode ter sido editado** — se algum falhar, o refactor mudou comportamento e está errado.

- [ ] **Step 5: Commit**

```bash
git add lib/tips.sh widgets/tip.sh tests/
git commit -m "refactor(tips): contrato de fonte genérico, com chave opaca"
```

---

### Task 2: preço derivado do custo real

**Files:**
- Modify: `lib/tips.sh`
- Test: `tests/tips.bats`

**Interfaces:**
- Produces: `_tip_usage_totals` → `"input read write output"` do transcript. `_tip_regrave_cost <tokens> <W>` → centavos, ou 1. `_tip_breakeven <W>` → número de trocas.

- [ ] **Step 1: Write the failing test**

```bash
# acrescentar a tests/tips.bats

mk_usage_transcript() {   # <input> <read> <write> <output>
  local f="$BATS_TEST_TMPDIR/usage.jsonl"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$1" "$2" "$3" "$4" > "$f"
  export SL_TRANSCRIPT="$f"
}

@test "usage totals add up the transcript" {
  mk_usage_transcript 870 106711624 2938536 639464
  run _tip_usage_totals
  [ "$output" = "870 106711624 2938536 639464" ]
}

@test "breakeven is three exchanges on a one hour ttl" {
  run _tip_breakeven 2
  [ "$output" = "3" ]
}

@test "breakeven is two exchanges on a five minute ttl" {
  run _tip_breakeven 1.25
  [ "$output" = "2" ]
}

@test "regrave cost matches the price derived from real aggregates" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88
  # den = 870 + 0.1*106711624 + 2*2938536 + 5*639464 = 19746424
  # P_in = 88/19746424 ; 393000 tokens a 2x  =>  ~350 centavos
  run _tip_regrave_cost 393000 2
  [ "$output" -ge 340 ]
  [ "$output" -le 360 ]
}

@test "regrave cost gives up when the session cost is zero" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88
  run _tip_regrave_cost 393000 2
  [ "$status" -eq 0 ]
  SL_COST=0
  run _tip_regrave_cost 393000 2
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/tips.bats`
Expected: FAIL — `_tip_usage_totals: command not found`.

- [ ] **Step 3: Write the implementation**

```bash
# acrescentar a lib/tips.sh

# ── Quanto custa regravar o prefixo ──
#
# O plugin não conhece tabela de preços, e não deve conhecer: ela envelheceria a
# cada lançamento e mentiria para quem passa por gateway corporativo. O preço
# sai do custo que o Claude Code já reporta.
#
# O caminho ingênuo — custo total sobre tokens totais — foi medido e recusado:
# numa sessão real dá $0,90/1M contra $5,00/1M de verdade, erro de 5,5×. A causa
# é estrutural: 106M de tokens lidos do cache a 0,1× dominam a contagem e quase
# não pesam no custo, e a média desaba. A dica subestimaria a regravação em cinco
# vezes, justamente no número que deveria assustar.
#
# O que funciona é uma invariante: output custa 5× input em toda a linha Claude
# — Fable 10/50, Opus 5/25, Sonnet 3/15, Haiku 1/5. Com ela sobra uma incógnita:
#
#   custo = P_in × (input + 0,1·read + W·write + 5·output)
#
# Medido contra 435 trocas reais: erro de 0% com W=1,25 e 11% com W=2. Aceitável
# para um número que aparece com `~` na frente.

# Os quatro agregados do transcript. Cacheado por mtime: varre o arquivo inteiro,
# e o resultado só muda quando ele cresce.
_tip_usage_totals_compute() {
  sl_jq -Rrs '
    [ split("\n")[] | fromjson?
      | select(.type == "assistant" and .message.usage != null)
      | .message.usage ] as $u
    | if ($u | length) == 0 then empty
      else "\([$u[].input_tokens // 0] | add) \([$u[].cache_read_input_tokens // 0] | add) \([$u[].cache_creation_input_tokens // 0] | add) \([$u[].output_tokens // 0] | add)"
      end' "$1" 2>/dev/null
}

_tip_usage_totals() {
  local key out
  [ -n "$SL_TRANSCRIPT" ] || return 1
  [ -f "$SL_TRANSCRIPT" ] || return 1
  key="tip-usage-$(printf '%s' "$SL_TRANSCRIPT" | cksum | cut -d' ' -f1)"
  out="$(cache_by_mtime "$key" "$SL_TRANSCRIPT" _tip_usage_totals_compute "$SL_TRANSCRIPT")"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# Quantas trocas a regravação precisa para se pagar.
#
#   com cache:  W + 0,1·(N−1)      sem cache:  1·N
#
# → 3 com TTL de 1 h, 2 com 5 min. Não é constante escolhida a dedo; sai do W
# que widgets/cache.sh detecta do payload.
_tip_breakeven() {
  awk -v w="$1" 'BEGIN{
    n = (w - 0.1) / 0.9
    v = int(n); if (n > v) v = v + 1
    if (v < 2) v = 2
    printf "%d", v
  }'
}

# Custo de regravar <tokens> tokens, em centavos. Retorna 1 quando não dá para
# derivar — e nesse caso a frase omite a cifra e mantém o múltiplo, que continua
# verdadeiro.
#
# A conta inteira vive no awk porque bash 3.2 não faz ponto flutuante, e aqui
# todo fator é fracionário.
_tip_regrave_cost() {
  local tokens="$1" w="$2" totals
  totals="$(_tip_usage_totals)" || return 1
  set -- $totals
  awk -v cost="$SL_COST" -v inp="$1" -v rd="$2" -v wr="$3" -v out="$4" \
      -v w="$w" -v tok="$tokens" 'BEGIN{
    den = inp + 0.1*rd + w*wr + 5*out
    if (cost <= 0 || den <= 0 || tok <= 0) exit 1
    printf "%.0f", tok * w * (cost/den) * 100
  }'
}
```

- [ ] **Step 4: Run tests**

Run: `bats tests/tips.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tips.sh tests/tips.bats
git commit -m "feat(tips): preço de input derivado do custo real da sessão"
```

---

### Task 3: as duas fontes de cache

**Files:**
- Modify: `lib/tips.sh`
- Test: `tests/tips.bats`, `tests/widgets/tip.bats`

**Interfaces:**
- Produces: `_tip_src_cache_cold <prev>`, `_tip_src_cache_expiring <prev>`.
- Consumes: `_cache_probe` e `sl_epoch_normalize` (de `widgets/cache.sh` e `lib/timefmt.sh`), `_tip_regrave_cost`, `_tip_breakeven`.

- [ ] **Step 1: Write the failing test**

```bash
# acrescentar a tests/tips.bats

# _cache_probe vive em widgets/cache.sh e devolve "<timestamp ISO> <ttl>". O tip
# só a chama quando o widget cache está configurado, então nos testes ela é
# substituída diretamente.
fake_probe() {   # fake_probe <epoch da última troca> <ttl>
  eval "_cache_probe() { printf '%s %s' '$1' '$2'; }"
}

@test "cache cold speaks when the prefix expired with a large context" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600          # expirou faz tempo
  run _tip_src_cache_cold ""
  [[ "$output" == *"Dica do cache: regravar 393k custa 2×"* ]]
  [[ "$output" == *"vale a partir de 3 trocas"* ]]
}

@test "cache cold stays quiet below the context floor" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [ -n "$output" ]
  SL_CTX_USED=12000
  run _tip_src_cache_cold ""
  [ "$status" -ne 0 ]
}

@test "cache cold stays quiet while the cache is still warm" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [ -n "$output" ]
  fake_probe 1754999000 3600          # ainda quente
  run _tip_src_cache_cold ""
  [ "$status" -ne 0 ]
}

@test "cache cold drops the price when it cannot be derived" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  [[ "$output" == *"(~\$"* ]]
  SL_COST=0
  run _tip_src_cache_cold ""
  [[ "$output" == *"custa 2×"* ]]
  [[ "$output" != *"(~\$"* ]]
}

@test "cache expiring speaks inside the last minute" {
  SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754996445 3600          # faltam 45s
  run _tip_src_cache_expiring ""
  [[ "$output" == *"45s até esfriar"* ]]
}

@test "cache expiring stays quiet outside the last minute" {
  SL_CTX_USED=393000 ; SL_NOW=1755000000
  fake_probe 1754996445 3600
  run _tip_src_cache_expiring ""
  [ -n "$output" ]
  fake_probe 1754999000 3600          # faltam bem mais
  run _tip_src_cache_expiring ""
  [ "$status" -ne 0 ]
}

@test "cache phrases fit in eighty columns" {
  mk_usage_transcript 870 106711624 2938536 639464
  SL_COST=88 ; SL_CTX_USED=1000000 ; SL_NOW=1755000000
  fake_probe 1754990000 3600
  run _tip_src_cache_cold ""
  local w1; w1="$(tip_width "${output#*	}")"
  fake_probe 1754996445 3600
  run _tip_src_cache_expiring ""
  local w2; w2="$(tip_width "${output#*	}")"
  [ "$w1" -ge 50 ]
  [ "$w2" -ge 50 ]
  [ "$w1" -le 80 ]
  [ "$w2" -le 80 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/tips.bats`
Expected: FAIL — `_tip_src_cache_cold: command not found`.

- [ ] **Step 3: Write the implementation**

```bash
# acrescentar a lib/tips.sh

# Piso de contexto para as dicas de cache. Esfriar com 12k na sessão custa
# centavos, e uma dica que aparece nesse caso ensina a ignorar a que aparece com
# 393k. Uma casa acima do limiar de gravação do cache.sh (10k), porque lá o que
# está em jogo é uma troca e aqui é o contexto inteiro.
SL_TIP_CTX_FLOOR=100000

# Janela em que vale avisar que o cache está por esfriar. É o mesmo
# SL_CACHE_TTL_CRIT do widget: o tempo aparece em vermelho lá, e a dica explica
# o vermelho — dois números diferentes seriam duas verdades sobre o mesmo
# instante.
SL_TIP_CACHE_SOON=60

# "<segundos restantes> <W>" do cache, ou 1.
#
# Depende de _cache_probe, que vive em widgets/cache.sh. O acoplamento é
# deliberado e guardado: sem o widget na configuração a dica não fala, pela mesma
# razão que vale para o flow — explicar um número que não está na tela não
# explica nada. Quando ele está na configuração, o arquivo foi carregado antes de
# qualquer render.
_tip_cache_state() {
  local raw ts ttl epoch rem
  _tip_widget_configured cache || return 1
  command -v _cache_probe >/dev/null 2>&1 || return 1
  raw="$(_cache_probe)" || return 1
  set -- $raw
  ts="$1"; ttl="$2"
  case "$ttl" in ''|*[!0-9]*) return 1 ;; esac
  epoch="$(sl_epoch_normalize "$ts")" || return 1
  rem=$(( epoch + ttl - $(_tip_now) ))
  # O multiplicador de gravação sai da janela contratada, que o cache.sh detecta
  # do payload: 2× para uma hora, 1,25× para cinco minutos.
  if [ "$ttl" -ge 3600 ]; then printf '%s 2' "$rem"; else printf '%s 1.25' "$rem"; fi
}

# Contexto grande o bastante para a regravação doer.
_tip_ctx_big() {
  case "$SL_CTX_USED" in ''|*[!0-9]*) return 1 ;; esac
  [ "$SL_CTX_USED" -ge "$SL_TIP_CTX_FLOOR" ]
}

# O prefixo expirou: a próxima troca regrava o contexto inteiro.
#
# A frase não diz "esfriou" — o `☁ 100%·cold` da linha de cima já diz, com
# formato e cor próprios. Repetir custava dez colunas e estourava os 80.
_tip_src_cache_cold() {
  local st rem w cents money phrase
  _tip_ctx_big || return 1
  st="$(_tip_cache_state)" || return 1
  set -- $st
  rem="$1"; w="$2"
  [ "$rem" -le 0 ] || return 1

  money=""
  if cents="$(_tip_regrave_cost "$SL_CTX_USED" "$w")"; then
    money="$(awk -v c="$cents" 'BEGIN{ printf " (~$%.2f)", c/100 }')"
  fi

  printf 'cold\tDica do cache: regravar %s custa %s×%s — vale a partir de %s trocas' \
    "$(sl_fmt_tokens "$SL_CTX_USED")" "$w" "$money" "$(_tip_breakeven "$w")"
}

# O prefixo está por expirar, e ainda dá para aproveitá-lo.
#
# A chave é `warn` durante a janela inteira, e não o número de segundos: uma
# chave que mudasse a cada repaint faria a dica reaparecer sessenta vezes num
# minuto. O texto mostra o tempo, o estado é um só.
_tip_src_cache_expiring() {
  local st rem w
  _tip_ctx_big || return 1
  st="$(_tip_cache_state)" || return 1
  set -- $st
  rem="$1"; w="$2"
  [ "$rem" -gt 0 ] || return 1
  [ "$rem" -le "$SL_TIP_CACHE_SOON" ] || return 1

  printf 'warn\tDica do cache: %ss até esfriar — mandar algo agora aproveita %s gravados' \
    "$rem" "$(sl_fmt_tokens "$SL_CTX_USED")"
}
```

E a lista ganha as duas:

```bash
SL_TIP_SOURCES="flow 7d 5h cache-cold cache-expiring"
```

- [ ] **Step 4: Run all tests**

Run: `bats -r tests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tips.sh tests/
git commit -m "feat(tips): dicas de custo de cache — regravação e esfriamento iminente"
```

---

### Task 4: documentação

**Files:**
- Modify: `README.md` (seção `### \`tip\``)

- [ ] **Step 1: Documentar as dicas de cache**

Acrescentar à seção do `tip`, depois do bloco sobre a meta de corte:

- que o `tip` agora tem cinco fontes, e o cache é uma delas
- a aritmética: ler custa 0,1×, regravar 1,25× (5 min) ou 2× (1 h), e o break-even sai daí
- que o preço em dólar é **derivado** do custo real da sessão, não de tabela — funciona atrás de gateway corporativo, e some quando não é derivável
- o piso de 100k de contexto
- que a dica não repete o `cold` da linha de cima

- [ ] **Step 2: Verificar a suíte**

Run: `bats -r tests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(tips): documenta as dicas de custo de cache"
```

---

## Self-Review

**Cobertura da spec:** aritmética e break-even → Task 2; preço derivado → Task 2; contrato generalizado → Task 1; fontes de cache e piso → Task 3; larguras → Task 3 (teste próprio); docs → Task 4.

**Consistência de nomes:** `_tip_slug`, `_tip_flow_key`, `_tip_src_projection`, `_tip_src_flow/_7d/_5h`, `_tip_usage_totals`, `_tip_breakeven`, `_tip_regrave_cost`, `_tip_cache_state`, `_tip_ctx_big`, `_tip_src_cache_cold`, `_tip_src_cache_expiring`, `_tip_one`, `widget_tip_render`.

**Contrato:** toda fonte recebe a chave anterior e devolve `"<chave><TAB><frase>"`; o estado tem três colunas.
