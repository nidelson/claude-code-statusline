# cache — alarme de gravação — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Marcar no widget `cache` a troca que gravou muito no prompt cache — `☁ 64%·58m ▲54k` — e ficar invisível quando a gravação é a rotina de ~700 tokens.

**Architecture:** Nenhuma leitura nova. O contador já chega em `SL_CACHE_CREATE` pelo payload e hoje só entra no denominador da taxa. O alarme vira uma terceira parte independente do render, ao lado da taxa e do countdown. A função de abreviação de tokens sobe de `widgets/context.sh` para `lib/num.sh`, ganhando o segundo consumidor.

**Tech Stack:** bash 3.2, `jq`, `bats-core`.

**Spec:** [2026-08-12-cache-write-alarm-design.md](../specs/2026-08-12-cache-write-alarm-design.md)

## Global Constraints

- **Shell alvo: bash 3.2.57.** Sem `declare -A`, sem `${var^^}`, sem `mapfile`.
- **Nunca usar `set -e` nem `set -u`.**
- **Dependências de runtime: apenas `jq` e `git`.**
- **A statusline nunca pode desaparecer.**
- **Idioma:** comentários, documentação e commits em **português**. Identificadores em inglês. `--desc` em inglês.
- **Nomes de teste `@test` em inglês ASCII** — o bats força `LC_ALL=C` e acento vira `unknown test name`.
- **Contraprova ANTES da asserção sob teste.** No bash 3.2 só a última asserção de cada teste é cobrada. Ver `tests/helper.bash`.

---

### Task 1: `sl_fmt_tokens` em `lib/num.sh`

Move a abreviação de tokens de dentro de um widget para a biblioteca, antes de ganhar o segundo consumidor.

**Files:**
- Modify: `lib/num.sh` (função nova ao fim)
- Modify: `widgets/context.sh:38-52` (remove a privada) e `widgets/context.sh:127` (chamada)
- Test: `tests/num.bats`

**Interfaces:**
- Produces: `sl_fmt_tokens <n>` → `950` | `54k` | `1.0M`. Entrada não numérica ou vazia imprime `0`.

- [ ] **Step 1: Escrever o teste que falha**

```bash
@test "token format leaves small numbers alone" {
  [ "$(sl_fmt_tokens 950)" = "950" ]
}

@test "token format abbreviates thousands" {
  [ "$(sl_fmt_tokens 54000)" = "54k" ]
}

@test "token format rounds to the nearest thousand" {
  [ "$(sl_fmt_tokens 53500)" = "54k" ]
  [ "$(sl_fmt_tokens 53499)" = "53k" ]
}

@test "token format abbreviates millions with one decimal" {
  [ "$(sl_fmt_tokens 1000000)" = "1.0M" ]
  [ "$(sl_fmt_tokens 1250000)" = "1.2M" ]
}

@test "token format reads junk as zero" {
  [ "$(sl_fmt_tokens abc)" = "0" ]
  [ "$(sl_fmt_tokens '')" = "0" ]
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `bats tests/num.bats`
Expected: FAIL com `sl_fmt_tokens: command not found`.

- [ ] **Step 3: Implementar**

Ao fim de `lib/num.sh`:

```bash
# 69000 → "69k", 1000000 → "1.0M", 950 → "950".
#
# Ordem de grandeza é o que interessa num contador de token: a diferença entre
# 53.499 e 53.500 não muda decisão nenhuma, e os dígitos gastos com ela custam
# largura numa linha que disputa espaço. Diferente da contagem de linhas do
# velocity, onde "+1.2k" esconderia a distância entre 1200 e 1249.
sl_fmt_tokens() {
  local n="$1"
  case "$n" in
    ""|*[!0-9]*) printf '0'; return 0 ;;
  esac
  if [ "$n" -ge 1000000 ]; then
    printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}
```

Em `widgets/context.sh`, apagar `_context_fmt_tokens` inteira (o comentário de
uma linha acima dela vai junto, porque a explicação agora vive em `lib/num.sh`)
e trocar as duas chamadas na linha 127 por `sl_fmt_tokens`.

- [ ] **Step 4: Rodar para ver passar**

Run: `bats tests/num.bats tests/widgets/context.bats`
Expected: PASS. Se `context.bats` falhar com `sl_fmt_tokens: command not found`,
o setup dele não carrega `lib/num.sh` — acrescentar
`source "$PROJECT_ROOT/lib/num.sh"`.

- [ ] **Step 5: Commit**

```bash
git add lib/num.sh widgets/context.sh tests/num.bats
git commit -m "refactor: sl_fmt_tokens sobe para lib/num.sh

A abreviação de tokens era privada do widget context e vai ganhar um
segundo consumidor no cache. Move antes de copiar."
```

---

### Task 2: o alarme no render

**Files:**
- Modify: `widgets/cache.sh` (constantes, `_cache_write_alarm`, `widget_cache_render`)
- Test: `tests/widgets/cache.bats`

**Interfaces:**
- Consumes: `sl_fmt_tokens` (Task 1); `SL_CACHE_CREATE`; `sl_config_widget_opt`.
- Produces: `SL_CACHE_WRITE_WARN=10000`, `SL_CACHE_WRITE_CRIT=50000`; `_cache_write_alarm` → imprime o pedaço colorido ou retorna 1.

- [ ] **Step 1: Escrever os testes que falham**

O setup existente já dá `SL_CACHE_READ=700 SL_CACHE_CREATE=200 SL_INPUT_TOKENS=100`,
ou seja, abaixo do limiar — o alarme não aparece por padrão nos testes antigos.

```bash
@test "a routine write raises no alarm" {
  # Contraprova primeiro: uma gravação grande tem de acender.
  SL_CACHE_CREATE=54000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲54k"* ]]
  # 699 é a mediana medida em produção. Nada deve aparecer.
  SL_CACHE_CREATE=699
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
}

@test "the alarm fires from ten thousand" {
  SL_CACHE_CREATE=9999
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
  SL_CACHE_CREATE=10000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲10k"* ]]
}

@test "the alarm is yellow between ten and fifty thousand" {
  SL_CACHE_CREATE=20000
  run widget_cache_render
  [[ "$output" == *$'\033[33m'*"▲20k"* ]]
}

@test "the alarm turns red from fifty thousand" {
  SL_CACHE_CREATE=49999
  run widget_cache_render
  [[ "$output" == *$'\033[33m'*"▲50k"* ]]
  SL_CACHE_CREATE=50000
  run widget_cache_render
  [[ "$output" == *$'\033[31m'*"▲50k"* ]]
}

@test "the alarm abbreviates millions" {
  SL_CACHE_CREATE=1250000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲1.2M"* ]]
}

@test "the alarm sits after the countdown" {
  SL_CACHE_CREATE=54000
  write_transcript "$(turn 2027-01-15T07:58:00Z 500 0)"
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 1%·58m ▲54k" ]
}

@test "the alarm shows without a countdown" {
  SL_CACHE_CREATE=54000
  SL_TRANSCRIPT=""
  run widget_cache_render
  [ "$(sl_test_plain "$output")" = "☁ 1% ▲54k" ]
}

@test "the write option turns the alarm off" {
  SL_CACHE_CREATE=54000
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"▲54k"* ]]
  use_config '{"version":1,"lines":[["cache"]],"widgets":{"cache":{"write":false}}}'
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
}

@test "the alarm falls back to a label when icons are off" {
  SL_CACHE_CREATE=54000
  use_config '{"version":1,"icons":false,"lines":[["cache"]],"widgets":{"cache":{}}}'
  run widget_cache_render
  [[ "$(sl_test_plain "$output")" == *"w:54k"* ]]
  [[ "$(sl_test_plain "$output")" != *"▲"* ]]
}
```

Nota sobre `☁ 1%·58m ▲54k`: com `SL_CACHE_CREATE=54000` sobre
`read=700, input=100`, a taxa é `700/54800 = 1,3%`, que arredonda para 1.

- [ ] **Step 2: Rodar para ver falhar**

Run: `bats tests/widgets/cache.bats`
Expected: FAIL nos nove — nenhum `▲` sai hoje.

- [ ] **Step 3: Implementar**

Em `widgets/cache.sh`, junto das outras constantes:

```bash
# Limiares do alarme de gravação, em tokens. 10k não é redondo por acaso: a
# mediana de gravação por troca é 699 e o p90 é 2.942, então o limiar fica três
# vezes acima do ruído de rotina e ainda captura as 33 trocas, de 943, que
# carregam 85% de tudo que foi gravado na sessão medida.
SL_CACHE_WRITE_WARN=10000
SL_CACHE_WRITE_CRIT=50000
```

E, depois de `_cache_countdown`:

```bash
# O pedaço do alarme, já colorido, ou 1 quando não há evento.
#
# Abaixo do limiar não sai nada — nem glifo, nem separador. Uma troca de rotina
# grava setecentos tokens, e anunciar isso todo turno gastaria espaço permanente
# para dizer "nada aconteceu", que é o estado padrão de quem não vê aviso.
#
# O glifo é ▲, U+25B2. O ⚡ que a forma pedia tem Emoji_Presentation=Yes: sai
# colorido de fábrica e ignora ANSI, e aqui a cor é a informação — amarelo
# separa caro de muito caro. O ▲ ainda está presente na fonte do terminal, no
# SF Mono e no Menlo, então não depende do fallback de que o ☁ depende.
_cache_write_alarm() {
  local written color mark
  [ "$(sl_config_widget_opt cache write true)" != "false" ] || return 1
  written="$(_cache_int "$SL_CACHE_CREATE")"
  [ "$written" -ge "$SL_CACHE_WRITE_WARN" ] || return 1
  if [ "$written" -ge "$SL_CACHE_WRITE_CRIT" ]; then color="$(sl_color red)"
  else                                               color="$(sl_color yellow)"
  fi
  if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then mark="▲"; else mark="w:"; fi
  printf '%s%s%s%s' "$color" "$mark" "$(sl_fmt_tokens "$written")" "$SL_RESET"
}
```

Em `widget_cache_render`, declarar `wr_part` no `local`, calcular junto das
outras partes e montar ao fim:

```bash
  cd_part="$(_cache_countdown)" || cd_part=""
  wr_part="$(_cache_write_alarm)" || wr_part=""

  [ -n "$pct_part" ] || [ -n "$cd_part" ] || [ -n "$wr_part" ] || return 0
```

e, depois do bloco que junta `pct_part` e `cd_part`:

```bash
  # Espaço e não `·`: o alarme é um evento, não uma segunda leitura do mesmo
  # relógio. A pontuação liga a taxa ao countdown porque os dois descrevem o
  # mesmo cache; o alarme descreve o que acabou de acontecer com ele.
  [ -n "$wr_part" ] && out="${out} ${wr_part}"
```

- [ ] **Step 4: Rodar para ver passar**

Run: `bats tests/widgets/cache.bats`
Expected: PASS, todos — inclusive os antigos, cujo `SL_CACHE_CREATE=200` fica
abaixo do limiar.

- [ ] **Step 5: Rodar a suíte inteira e ver ao vivo**

Run: `bats -r tests`
Expected: 0 falhas.

Run: `bash bin/statusline.sh < "$CLAUDE_JOB_DIR/tmp/p2.json"`
Expected: sem `▲` — o payload guardado tem `cache_creation_input_tokens: 654`.
Para ver o alarme:
`jq '.context_window.current_usage.cache_creation_input_tokens = 287000' "$CLAUDE_JOB_DIR/tmp/p2.json" | bash bin/statusline.sh`

- [ ] **Step 6: Commit**

```bash
git add widgets/cache.sh tests/widgets/cache.bats
git commit -m "feat: alarme de gravação de cache na última troca

33 trocas de 943 gravaram mais de 10k tokens, e essas 33 carregam 85% de
tudo que foi gravado na sessão medida. Hoje passam invisíveis: o contador
entra no denominador da taxa e some ali dentro.

O limiar de 10k fica três vezes acima do p90, então o alarme não acende no
ruído de rotina — a mediana de gravação por troca é 699 tokens."
```

---

### Task 3: sabotagem, README e PR

- [ ] **Step 1: Sabotar numa cópia descartável**

```bash
SAB="$(mktemp -d "${TMPDIR:-/tmp}/sab-write.XXXXXX")"
cp -R lib widgets tests bin "$SAB"/
```

Aplicar uma de cada vez, rodar `bats tests/widgets/cache.bats` dentro de `$SAB`,
restaurar o arquivo do repositório entre as rodadas:

| # | Sabotagem | Arquivo | Tem de derrubar |
|---|---|---|---|
| 1 | `SL_CACHE_WRITE_WARN=10000` → `=0` | `widgets/cache.sh` | supressão de rotina, limiar exato |
| 2 | `SL_CACHE_WRITE_CRIT=50000` → `=999999999` | `widgets/cache.sh` | o teste de vermelho |
| 3 | `-ge "$SL_CACHE_WRITE_WARN"` → `-gt` | `widgets/cache.sh` | limiar exato em 10.000 |
| 4 | `_cache_write_alarm` retorna 1 sempre | `widgets/cache.sh` | todos os de alarme, nenhum de taxa |
| 5 | `mark="▲"` → `mark="!"` | `widgets/cache.sh` | os que casam o glifo |
| 6 | `printf '%dk'` → `printf '%d'` | `lib/num.sh` | os de abreviação |

Sabotagem que não derruba nada é asserção morta ou caso não coberto — corrigir
o teste, não a expectativa.

- [ ] **Step 2: Atualizar o README**

Na seção `### \`cache\``, acrescentar `write` à tabela de opções e, depois do
parágrafo do countdown:

```markdown
**O alarme** marca a troca que gravou muito no cache: `▲54k`. Amarelo a partir
de 10k tokens, vermelho a partir de 50k, invisível abaixo disso.

Gravação é o que custa caro — um token gravado vale vinte lidos — e ela é
concentrada, não difusa: numa sessão medida, 33 trocas de 943 carregaram 85% de
tudo que foi gravado. São compactação, skill grande injetada, arquivo grande
lido, conjunto de ferramentas alterado. O limiar de 10k fica três vezes acima do
p90 de gravação por troca, então o alarme não acende na rotina.

`write: false` desliga. Com `icons: false` o glifo dá lugar a `w:`.
```

- [ ] **Step 3: Confirmar e abrir a PR**

```bash
bats -r tests
git diff main...HEAD --stat
git push -u origin cache-write-alarm
gh pr create --title "feat: alarme de gravação de cache na última troca" --body-file <corpo>
```

O corpo deve trazer: a distribuição medida (mediana 699, p90 2.942, p99 286.529),
os dois candidatos recusados com o motivo de cada um, a recusa técnica do `⚡`
por `Emoji_Presentation=Yes`, a recusa do `⌁` por cobertura de fonte com a tabela
de três fontes, e o resultado da rodada de sabotagem.
