# claude-code-statusline v0.1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir o núcleo de uma statusline modular para o Claude Code, com registro de widgets em bash, e três widgets que exercitam os casos-limite do contrato.

**Architecture:** Um entrypoint carrega bibliotecas de `lib/`, parseia o stdin uma única vez, lê a configuração e carrega apenas os widgets listados nela. Cada widget é um arquivo que se auto-registra por indireção de variável e expõe uma função de render. O núcleo monta as linhas e imprime tudo em um único `printf`.

**Tech Stack:** bash 3.2, `jq`, `bats-core` (apenas desenvolvimento), GitHub Actions.

## Global Constraints

- **Shell alvo: bash 3.2.57.** Sem `declare -A`, sem `${var^^}`, sem `mapfile`, sem `&>>`. Usar indireção `${!var}` para leitura dinâmica.
- **Shebang de todo script executável:** `#!/usr/bin/env bash`
- **Nunca usar `set -e` nem `set -u`.** Erros se tratam explicitamente no ponto de ocorrência.
- **Dependências de runtime:** apenas `jq` e `git`. Nada além disso.
- **A statusline nunca pode desaparecer.** Qualquer falha degrada para saída parcial com marcador de aviso, jamais para linha vazia.
- **Nome do plugin e do diretório de configuração:** `claude-code-statusline`.
- **Configuração do usuário:** `${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-statusline/config.json`
- **Idioma:** comentários de código, documentação (`docs/`, `README.md`) e
  mensagens de commit em **português**. Identificadores (funções, variáveis) em
  inglês, por convenção de shell. Strings de `--desc` dos widgets em inglês, por
  serem texto de interface de um plugin publicável.
- **Nomes de teste `@test` obrigatoriamente em inglês ASCII.** O bats força
  `LC_ALL=C` internamente e converte o título do teste em nome de função; um
  acento vira byte inválido e o teste falha com `unknown test name`. Descoberto
  na Task 3, com `@test "nome com hífen é aceito"`.
- **Widget cujo nome contém hífen** vira nome de variável com underscore: `rate-forecast` → `_W_RENDER_rate_forecast`.

---

### Task 1: Esqueleto do repositório e manifesto do plugin

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `bin/statusline.sh`
- Create: `.gitignore`
- Create: `tests/helper.bash`
- Test: `tests/smoke.bats`

**Interfaces:**
- Consumes: nada (primeira tarefa)
- Produces: `bin/statusline.sh` executável que lê stdin e imprime uma linha; `tests/helper.bash` com `PROJECT_ROOT` para as demais suítes.

- [ ] **Step 1: Instalar o runner de testes**

```bash
brew install bats-core
bats --version   # esperado: Bats 1.x
```

- [ ] **Step 2: Escrever o teste que falha**

Criar `tests/helper.bash`:

```bash
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export PROJECT_ROOT
```

Criar `tests/smoke.bats`:

```bash
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
```

- [ ] **Step 3: Rodar o teste para confirmar que falha**

Run: `bats tests/smoke.bats`
Expected: FAIL — `bin/statusline.sh` não existe.

- [ ] **Step 4: Criar o manifesto do plugin**

Criar `.claude-plugin/plugin.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "claude-code-statusline",
  "description": "Statusline for Claude Code with rate-limit forecasting, corporate provider quotas, and workflow health",
  "version": "0.1.0",
  "author": {
    "name": "Nidelson Gimenez",
    "url": "https://github.com/nidelson"
  },
  "homepage": "https://github.com/nidelson/claude-code-statusline",
  "repository": "https://github.com/nidelson/claude-code-statusline",
  "license": "MIT",
  "keywords": ["statusline", "claude-code", "rate-limit", "forecast", "bash"]
}
```

- [ ] **Step 5: Criar o entrypoint mínimo**

Criar `bin/statusline.sh`:

```bash
#!/usr/bin/env bash
# Entrypoint. Reads the Claude Code session JSON on stdin, prints the statusline.
# Never uses `set -e`: a non-zero return must not blank the user's status line.

SL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

input="$(cat)"

# Placeholder until Task 2 wires the real parser.
printf '%s\n' "claude-code-statusline"
```

```bash
chmod +x bin/statusline.sh
```

- [ ] **Step 6: Criar o .gitignore**

```gitignore
.DS_Store
*.log
tmp/
```

- [ ] **Step 7: Rodar os testes e confirmar que passam**

Run: `bats tests/smoke.bats`
Expected: 3 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add .claude-plugin bin tests .gitignore
git commit -m "feat: esqueleto do plugin e entrypoint mínimo"
```

---

### Task 2: Parse único do stdin

**Files:**
- Create: `lib/stdin.sh`
- Modify: `bin/statusline.sh`
- Test: `tests/stdin.bats`

**Interfaces:**
- Consumes: `bin/statusline.sh` da Task 1.
- Produces: função `sl_parse_stdin <json>` que define as variáveis `SL_MODEL`, `SL_MODEL_ID`, `SL_COST`, `SL_LINES_ADDED`, `SL_LINES_REMOVED`, `SL_CWD`, `SL_CACHE_READ`, `SL_CACHE_CREATE`, `SL_INPUT_TOKENS`, `SL_CTX_SIZE`, `SL_CTX_USED`, `SL_5H_PCT`, `SL_7D_PCT`, `SL_5H_RESET`, `SL_7D_RESET`. Define `SL_JQ_OK=1` em caso de sucesso, `SL_JQ_OK=0` caso contrário.

- [ ] **Step 1: Escrever o teste que falha**

Criar `tests/stdin.bats`:

```bash
load helper

setup() {
  source "$PROJECT_ROOT/lib/stdin.sh"
}

@test "extrai o nome do modelo" {
  sl_parse_stdin '{"model":{"display_name":"Opus 5","id":"claude-opus-5"}}'
  [ "$SL_MODEL" = "Opus 5" ]
  [ "$SL_MODEL_ID" = "claude-opus-5" ]
}

@test "campo ausente vira default, não erro" {
  sl_parse_stdin '{}'
  [ "$SL_MODEL" = "Unknown" ]
  [ "$SL_COST" = "0" ]
}

@test "extrai rate limits aninhados" {
  sl_parse_stdin '{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1800000000}}}'
  [ "$SL_5H_PCT" = "42" ]
  [ "$SL_5H_RESET" = "1800000000" ]
}

@test "valor com aspas e espaço não quebra o eval" {
  sl_parse_stdin '{"workspace":{"current_dir":"/tmp/a b\"c"}}'
  [ "$SL_CWD" = '/tmp/a b"c' ]
}

@test "JSON inválido marca SL_JQ_OK=0 sem abortar" {
  sl_parse_stdin 'isto nao e json'
  [ "$SL_JQ_OK" = "0" ]
}
```

- [ ] **Step 2: Rodar o teste para confirmar que falha**

Run: `bats tests/stdin.bats`
Expected: FAIL — `lib/stdin.sh` não existe.

- [ ] **Step 3: Implementar o parser**

Criar `lib/stdin.sh`:

```bash
# Single-pass stdin parser.
#
# The previous implementation called `jq` fifteen times, once per field, each
# one a fork. This emits every field in one pass. `@sh` quotes each value so
# the `eval` is safe with spaces, quotes and newlines in the payload.

sl_parse_stdin() {
  local json="$1" assignments

  assignments="$(printf '%s' "$json" | jq -r '
    @sh "SL_MODEL=\(.model.display_name // "Unknown")",
    @sh "SL_MODEL_ID=\(.model.id // "")",
    @sh "SL_COST=\(.cost.total_cost_usd // 0)",
    @sh "SL_LINES_ADDED=\(.cost.total_lines_added // 0)",
    @sh "SL_LINES_REMOVED=\(.cost.total_lines_removed // 0)",
    @sh "SL_CWD=\(.workspace.current_dir // .cwd // "")",
    @sh "SL_CACHE_READ=\(.cache_read_input_tokens // 0)",
    @sh "SL_CACHE_CREATE=\(.cache_creation_input_tokens // 0)",
    @sh "SL_INPUT_TOKENS=\(.input_tokens // 0)",
    @sh "SL_CTX_SIZE=\(.context_window.context_window_size // 0)",
    @sh "SL_CTX_USED=\(.context_window.total_input_tokens // 0)",
    @sh "SL_5H_PCT=\(.rate_limits.five_hour.used_percentage // "")",
    @sh "SL_7D_PCT=\(.rate_limits.seven_day.used_percentage // "")",
    @sh "SL_5H_RESET=\(.rate_limits.five_hour.resets_at // "")",
    @sh "SL_7D_RESET=\(.rate_limits.seven_day.resets_at // "")"
  ' 2>/dev/null)"

  if [ -z "$assignments" ]; then
    # Malformed JSON or missing jq. Widgets that need data will render empty;
    # the status line still prints.
    SL_JQ_OK=0
    SL_MODEL="Unknown"; SL_MODEL_ID=""; SL_COST=0
    SL_LINES_ADDED=0; SL_LINES_REMOVED=0; SL_CWD=""
    SL_CACHE_READ=0; SL_CACHE_CREATE=0; SL_INPUT_TOKENS=0
    SL_CTX_SIZE=0; SL_CTX_USED=0
    SL_5H_PCT=""; SL_7D_PCT=""; SL_5H_RESET=""; SL_7D_RESET=""
    return 0
  fi

  eval "$assignments"
  SL_JQ_OK=1
  return 0
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bats tests/stdin.bats`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Ligar o parser ao entrypoint**

Substituir o corpo de `bin/statusline.sh` abaixo da definição de `SL_ROOT`:

```bash
. "$SL_ROOT/lib/stdin.sh"

input="$(cat)"
sl_parse_stdin "$input"

printf '%s\n' "$SL_MODEL"
```

- [ ] **Step 6: Verificar de ponta a ponta**

Run:
```bash
echo '{"model":{"display_name":"Opus 5"}}' | ./bin/statusline.sh
```
Expected: `Opus 5`

- [ ] **Step 7: Commit**

```bash
git add lib/stdin.sh bin/statusline.sh tests/stdin.bats
git commit -m "feat: parse do stdin em uma única passada de jq"
```

---

### Task 3: Registro de widgets

**Files:**
- Create: `lib/core.sh`
- Test: `tests/core.bats`

**Interfaces:**
- Consumes: nada de tarefas anteriores.
- Produces:
  - `register_widget <nome> [--render FN] [--color COR] [--desc TEXTO] [--self-color]`
  - `sl_widget_attr <ATRIBUTO> <nome>` — imprime o valor; `ATRIBUTO` ∈ `RENDER`, `COLOR`, `DESC`, `SELFCOLOR`
  - `sl_widget_registered <nome>` — retorna 0 se registrado, 1 caso contrário
  - Variável `SL_WIDGET_LIST` com os nomes registrados, separados por espaço

- [ ] **Step 1: Escrever o teste que falha**

Criar `tests/core.bats`:

```bash
load helper

setup() {
  source "$PROJECT_ROOT/lib/core.sh"
}

@test "registra e recupera o nome da função de render" {
  register_widget model --render widget_model_render --color cyan
  [ "$(sl_widget_attr RENDER model)" = "widget_model_render" ]
  [ "$(sl_widget_attr COLOR model)" = "cyan" ]
}

@test "nome com hífen é aceito" {
  register_widget rate-forecast --render widget_rf_render
  [ "$(sl_widget_attr RENDER rate-forecast)" = "widget_rf_render" ]
}

@test "self-color é sinalizado" {
  register_widget a --render fn_a --self-color
  register_widget b --render fn_b
  [ "$(sl_widget_attr SELFCOLOR a)" = "1" ]
  [ "$(sl_widget_attr SELFCOLOR b)" = "0" ]
}

@test "widget registrado é reconhecido; não registrado não é" {
  register_widget model --render fn
  sl_widget_registered model
  ! sl_widget_registered inexistente
}

@test "a lista acumula os nomes registrados" {
  register_widget a --render fa
  register_widget b --render fb
  [ "$SL_WIDGET_LIST" = " a b" ]
}

@test "registro sem --render é rejeitado" {
  ! register_widget quebrado --color red
  ! sl_widget_registered quebrado
}
```

- [ ] **Step 2: Rodar o teste para confirmar que falha**

Run: `bats tests/core.bats`
Expected: FAIL — `lib/core.sh` não existe.

- [ ] **Step 3: Implementar o registro**

Criar `lib/core.sh`:

```bash
# Widget registry.
#
# bash 3.2 has no associative arrays, so attributes live in variables whose
# names are derived from the widget name: _W_RENDER_model, _W_COLOR_model.
# Reads go through `${!var}` indirection, which needs no eval.
# Hyphens are not legal in variable names, so they become underscores.

SL_WIDGET_LIST=""

_sl_slug() {
  local name="$1"
  printf '%s' "${name//-/_}"
}

register_widget() {
  local name="$1"; shift
  local render="" color="" desc="" selfcolor=0 slug

  while [ $# -gt 0 ]; do
    case "$1" in
      --render)     render="$2";  shift 2 ;;
      --color)      color="$2";   shift 2 ;;
      --desc)       desc="$2";    shift 2 ;;
      --self-color) selfcolor=1;  shift   ;;
      *)            shift           ;;
    esac
  done

  # A widget with no render function is a programming error in that widget
  # file. Reject it rather than failing later with an obscure "command not
  # found" in the middle of a repaint.
  if [ -z "$render" ]; then
    return 1
  fi

  slug="$(_sl_slug "$name")"
  eval "_W_RENDER_$slug=\$render"
  eval "_W_COLOR_$slug=\$color"
  eval "_W_DESC_$slug=\$desc"
  eval "_W_SELFCOLOR_$slug=\$selfcolor"
  SL_WIDGET_LIST="$SL_WIDGET_LIST $name"
  return 0
}

sl_widget_attr() {
  local attr="$1" name="$2" var
  var="_W_${attr}_$(_sl_slug "$name")"
  printf '%s' "${!var}"
}

sl_widget_registered() {
  local var="_W_RENDER_$(_sl_slug "$1")"
  [ -n "${!var}" ]
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bats tests/core.bats`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/core.sh tests/core.bats
git commit -m "feat: registro de widgets por indireção, compatível com bash 3.2"
```

---

### Task 4: Medir o canal de retorno e fixar o contrato

Esta tarefa resolve a única questão em aberto da spec. Ela não entrega
funcionalidade ao usuário; entrega uma **decisão medida** que as Tasks 5 a 8
dependem. Widgets sintéticos são usados de propósito: medir com os widgets
reais misturaria o custo do canal de retorno com o custo do trabalho de cada
widget.

**Files:**
- Create: `benchmarks/return-channel.sh`
- Create: `docs/superpowers/decisions/2026-08-08-canal-de-retorno.md`
- Modify: `docs/superpowers/specs/2026-08-08-statusline-modular-design.md` (seção "Questões em aberto")

**Interfaces:**
- Consumes: `lib/core.sh` da Task 3.
- Produces: decisão registrada. As tarefas seguintes usam `WIDGET_OUT` **ou**
  stdout conforme o resultado; o restante do contrato não muda.

- [ ] **Step 1: Escrever o benchmark**

Criar `benchmarks/return-channel.sh`:

```bash
#!/usr/bin/env bash
# Compares the two candidate widget return channels under a realistic load:
# 11 widgets, 200 repaints. Prints the elapsed time of each strategy.

REPAINTS=200
WIDGETS=11

# --- Strategy A: global variable, no subshell ---
make_var_widgets() {
  local i
  for i in $(seq 1 $WIDGETS); do
    eval "w_var_$i() { WIDGET_OUT=\"widget-$i\"; }"
  done
}

run_var() {
  local i out line
  line=""
  for i in $(seq 1 $WIDGETS); do
    WIDGET_OUT=""
    "w_var_$i"
    [ -n "$WIDGET_OUT" ] && line="$line|$WIDGET_OUT"
  done
}

# --- Strategy B: stdout captured by command substitution ---
make_out_widgets() {
  local i
  for i in $(seq 1 $WIDGETS); do
    eval "w_out_$i() { printf '%s' \"widget-$i\"; }"
  done
}

run_out() {
  local i out line
  line=""
  for i in $(seq 1 $WIDGETS); do
    out="$("w_out_$i")"
    [ -n "$out" ] && line="$line|$out"
  done
}

make_var_widgets
make_out_widgets

timeit() {
  local label="$1" fn="$2" start end i
  start=$(date +%s)
  for i in $(seq 1 $REPAINTS); do "$fn"; done
  end=$(date +%s)
  printf '%-28s %s repaints em %ss\n' "$label" "$REPAINTS" "$((end - start))"
}

printf 'bash %s | %s widgets | %s repaints\n\n' "$BASH_VERSION" "$WIDGETS" "$REPAINTS"
timeit "WIDGET_OUT (sem subshell)" run_var
timeit "stdout (command subst.)"   run_out
```

```bash
chmod +x benchmarks/return-channel.sh
```

- [ ] **Step 2: Rodar o benchmark três vezes**

Run: `./benchmarks/return-channel.sh; ./benchmarks/return-channel.sh; ./benchmarks/return-channel.sh`

Anotar o menor tempo de cada estratégia. O primeiro ciclo costuma ser mais lento
por cache frio; use o melhor dos três.

- [ ] **Step 3: Aplicar o critério de decisão**

Dividir a diferença total pelo número de repaints para obter o custo por
repaint. O critério, fixado **antes** de ver o número para não racionalizar
depois:

- Diferença **abaixo de 5 ms por repaint** → usar **stdout**. A legibilidade e o
  isolamento valem mais que uma economia imperceptível.
- Diferença **de 5 ms ou mais por repaint** → usar **`WIDGET_OUT`**. A statusline
  redesenha a cada 2 s em cada terminal aberto; o custo se acumula.

- [ ] **Step 4: Registrar a decisão**

Criar `docs/superpowers/decisions/2026-08-08-canal-de-retorno.md` com: os
números medidos das três execuções, a versão do bash, o critério acima, a
decisão tomada e a data.

- [ ] **Step 5: Atualizar a spec**

Em `docs/superpowers/specs/2026-08-08-statusline-modular-design.md`, na seção
"Questões em aberto", substituir o item pelo resultado, com link para o
documento de decisão. Se a seção ficar vazia, escrever "Nenhuma."

- [ ] **Step 6: Commit**

```bash
git add benchmarks docs/superpowers/decisions docs/superpowers/specs
git commit -m "chore: mede o canal de retorno de widget e fixa o contrato"
```

---

### Task 5: Configuração

**Files:**
- Create: `lib/config.sh`
- Test: `tests/config.bats`

**Interfaces:**
- Consumes: nada de tarefas anteriores.
- Produces:
  - `sl_config_load [caminho]` — popula `SL_CONFIG_LINES` (uma linha por índice,
    widgets separados por espaço, linhas separadas por quebra), `SL_CONFIG_SEP`,
    e `SL_CONFIG_WARN` (`""` quando tudo certo, `"config"` quando houve
    degradação).
  - `sl_config_widget_opt <widget> <chave>` — imprime o valor da opção ou vazio.

**Nota sobre os defaults:** os três widgets do v0.1 são `model`, `git` e
`rate-forecast`, implementados nas Tasks 6, 7 e 8. O default abaixo já os
referencia; até a Task 8 concluir, widgets não registrados são simplesmente
ignorados pelo núcleo, o que é o comportamento correto e está coberto por teste.

- [ ] **Step 1: Escrever o teste que falha**

Criar `tests/config.bats`:

```bash
load helper

setup() {
  source "$PROJECT_ROOT/lib/config.sh"
  TMPCFG="$BATS_TEST_TMPDIR/config.json"
}

@test "sem arquivo, usa os defaults e não avisa" {
  sl_config_load "$BATS_TEST_TMPDIR/nao-existe.json"
  [ "$SL_CONFIG_WARN" = "" ]
  [ -n "$SL_CONFIG_LINES" ]
}

@test "lê linhas e separador do arquivo" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["model","git"],["rate-forecast"]],"separator":"·"}
EOF
  sl_config_load "$TMPCFG"
  [ "$SL_CONFIG_SEP" = "·" ]
  [ "$(printf '%s' "$SL_CONFIG_LINES" | sed -n 1p)" = "model git" ]
  [ "$(printf '%s' "$SL_CONFIG_LINES" | sed -n 2p)" = "rate-forecast" ]
}

@test "JSON inválido cai nos defaults e sinaliza aviso" {
  printf 'isto { nao e json' > "$TMPCFG"
  sl_config_load "$TMPCFG"
  [ "$SL_CONFIG_WARN" = "config" ]
  [ -n "$SL_CONFIG_LINES" ]
}

@test "JSON inválido não é sobrescrito" {
  printf 'isto { nao e json' > "$TMPCFG"
  sl_config_load "$TMPCFG"
  [ "$(cat "$TMPCFG")" = 'isto { nao e json' ]
}

@test "lê opção de widget" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["rate-forecast"]],"widgets":{"rate-forecast":{"window":"5h"}}}
EOF
  sl_config_load "$TMPCFG"
  [ "$(sl_config_widget_opt rate-forecast window)" = "5h" ]
}

@test "opção ausente retorna vazio" {
  cat > "$TMPCFG" <<'EOF'
{"version":1,"lines":[["model"]]}
EOF
  sl_config_load "$TMPCFG"
  [ -z "$(sl_config_widget_opt model cor)" ]
}
```

- [ ] **Step 2: Rodar o teste para confirmar que falha**

Run: `bats tests/config.bats`
Expected: FAIL — `lib/config.sh` não existe.

- [ ] **Step 3: Implementar a configuração**

Criar `lib/config.sh`:

```bash
# User configuration.
#
# An unreadable or malformed config file must never be rewritten: the user has
# to be able to fix their own file. Degradation is in-memory only, flagged
# through SL_CONFIG_WARN so the status line can show a discreet marker.

SL_CONFIG_DEFAULT_LINES='model git
rate-forecast'
SL_CONFIG_DEFAULT_SEP='|'

sl_config_path() {
  printf '%s/claude-code-statusline/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

sl_config_load() {
  local path="${1:-$(sl_config_path)}" raw lines sep

  SL_CONFIG_WARN=""
  SL_CONFIG_RAW=""

  if [ ! -f "$path" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    return 0
  fi

  raw="$(cat "$path" 2>/dev/null)"

  if ! printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    SL_CONFIG_WARN="config"
    return 0
  fi

  SL_CONFIG_RAW="$raw"

  lines="$(printf '%s' "$raw" | jq -r '.lines // [] | .[] | join(" ")' 2>/dev/null)"
  sep="$(printf '%s' "$raw" | jq -r '.separator // "|"' 2>/dev/null)"

  if [ -z "$lines" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_WARN="config"
  else
    SL_CONFIG_LINES="$lines"
  fi

  SL_CONFIG_SEP="${sep:-$SL_CONFIG_DEFAULT_SEP}"
  return 0
}

sl_config_widget_opt() {
  local widget="$1" key="$2" value
  [ -n "$SL_CONFIG_RAW" ] || return 0
  value="$(printf '%s' "$SL_CONFIG_RAW" \
    | jq -r --arg w "$widget" --arg k "$key" '.widgets[$w][$k] // empty' 2>/dev/null)"
  printf '%s' "$value"
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bats tests/config.bats`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh tests/config.bats
git commit -m "feat: configuração em JSON com degradação segura"
```

---

### Task 6: Montagem de linhas e primeiro widget

**Files:**
- Create: `lib/colors.sh`
- Create: `widgets/model.sh`
- Modify: `lib/core.sh` (acrescentar `sl_render_line` e `sl_render_all`)
- Modify: `bin/statusline.sh`
- Test: `tests/render.bats`, `tests/widgets/model.bats`

**Interfaces:**
- Consumes: `register_widget`/`sl_widget_attr` (Task 3), `sl_config_load` (Task 5), `SL_MODEL` (Task 2).
- Produces:
  - `sl_color <nome>` e `SL_RESET` em `lib/colors.sh`
  - `sl_render_line <widgets...>` — imprime uma linha montada
  - `sl_render_all` — imprime todas as linhas de `SL_CONFIG_LINES`
  - `widget_model_render`

**Nota:** os exemplos abaixo usam `WIDGET_OUT`. Se a Task 4 decidiu por stdout,
trocar `WIDGET_OUT="X"` por `printf '%s' "X"` nos widgets e
`WIDGET_OUT=""; "$fn"` por `out="$("$fn")"` no núcleo. O restante é idêntico.

- [ ] **Step 1: Escrever o teste que falha**

Criar `tests/widgets/model.bats`:

```bash
load ../helper

setup() {
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/widgets/model.sh"
}

@test "renderiza o nome do modelo" {
  SL_MODEL="Opus 5"
  WIDGET_OUT=""
  widget_model_render
  [ "$WIDGET_OUT" = "Opus 5" ]
}

@test "desaparece quando não há modelo" {
  SL_MODEL=""
  WIDGET_OUT=""
  widget_model_render
  [ -z "$WIDGET_OUT" ]
}

@test "o widget se registra ao ser carregado" {
  sl_widget_registered model
}
```

Criar `tests/render.bats`:

```bash
load helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  # sl_render_line consulta sl_config_widget_opt para a cor por widget;
  # sem config.sh carregado o teste falharia com "command not found".
  source "$PROJECT_ROOT/lib/config.sh"
  SL_CONFIG_RAW=""
  SL_CONFIG_SEP="|"
  w_a() { WIDGET_OUT="A"; }
  w_b() { WIDGET_OUT="B"; }
  w_vazio() { WIDGET_OUT=""; }
  w_erro() { return 1; }
  register_widget a --render w_a
  register_widget b --render w_b
  register_widget vazio --render w_vazio
  register_widget erro --render w_erro
}

@test "junta dois widgets com o separador" {
  run sl_render_line a b
  [ "$output" = "A | B" ]
}

@test "widget vazio não deixa separador órfão" {
  run sl_render_line a vazio b
  [ "$output" = "A | B" ]
}

@test "widget vazio na ponta não deixa separador pendurado" {
  run sl_render_line vazio a vazio
  [ "$output" = "A" ]
}

@test "widget que falha não derruba a linha" {
  run sl_render_line a erro b
  [ "$output" = "A | B" ]
}

@test "widget não registrado é ignorado" {
  run sl_render_line a inexistente b
  [ "$output" = "A | B" ]
}

@test "linha só de widgets vazios sai vazia" {
  run sl_render_line vazio vazio
  [ "$output" = "" ]
}
```

- [ ] **Step 2: Rodar os testes para confirmar que falham**

Run: `bats tests/render.bats tests/widgets/model.bats`
Expected: FAIL — `lib/colors.sh`, `widgets/model.sh` e `sl_render_line` não existem.

- [ ] **Step 3: Criar a paleta de cores**

Criar `lib/colors.sh`:

```bash
# Color palette. Widgets emit plain text; the core applies the configured color.

SL_RESET=$'\033[0m'
SL_DIM=$'\033[2m'

sl_color() {
  case "$1" in
    red)     printf '\033[31m' ;;
    green)   printf '\033[32m' ;;
    yellow)  printf '\033[33m' ;;
    blue)    printf '\033[34m' ;;
    magenta) printf '\033[35m' ;;
    cyan)    printf '\033[36m' ;;
    dim)     printf '\033[2m'  ;;
    *)       printf ''         ;;
  esac
}
```

- [ ] **Step 4: Implementar a montagem no núcleo**

Acrescentar ao final de `lib/core.sh`:

```bash
# Line assembly.
#
# A widget that renders empty disappears without leaving an orphan separator:
# the separator is emitted before a segment only when something was already
# written to the line.

sl_render_line() {
  local name fn color selfcolor line="" sep

  sep=" ${SL_CONFIG_SEP:-|} "

  for name in "$@"; do
    sl_widget_registered "$name" || continue

    fn="$(sl_widget_attr RENDER "$name")"
    WIDGET_OUT=""

    # A failing widget becomes an empty widget. The rest of the line survives.
    "$fn" 2>/dev/null || WIDGET_OUT=""

    [ -n "$WIDGET_OUT" ] || continue

    selfcolor="$(sl_widget_attr SELFCOLOR "$name")"
    if [ "$selfcolor" != "1" ]; then
      color="$(sl_config_widget_opt "$name" color)"
      [ -n "$color" ] || color="$(sl_widget_attr COLOR "$name")"
      if [ -n "$color" ]; then
        WIDGET_OUT="$(sl_color "$color")$WIDGET_OUT$SL_RESET"
      fi
    fi

    if [ -n "$line" ]; then
      line="$line$sep$WIDGET_OUT"
    else
      line="$WIDGET_OUT"
    fi
  done

  printf '%s' "$line"
}

sl_render_all() {
  local widgets out first=1
  while IFS= read -r widgets; do
    [ -n "$widgets" ] || continue
    out="$(sl_render_line $widgets)"
    [ -n "$out" ] || continue
    if [ "$first" = "1" ]; then first=0; else printf '\n'; fi
    printf '%s' "$out"
  done <<EOF
$SL_CONFIG_LINES
EOF
  printf '\n'
}
```

- [ ] **Step 5: Criar o widget model**

Criar `widgets/model.sh`:

```bash
# Active model name.

register_widget model \
  --render widget_model_render \
  --color  cyan \
  --desc   "Active model name"

widget_model_render() {
  [ -n "$SL_MODEL" ] || return 0
  [ "$SL_MODEL" = "Unknown" ] && return 0
  WIDGET_OUT="$SL_MODEL"
}
```

- [ ] **Step 6: Rodar os testes e confirmar que passam**

Run: `bats tests/render.bats tests/widgets/model.bats`
Expected: 9 tests, 0 failures.

- [ ] **Step 7: Ligar tudo no entrypoint**

Substituir o corpo de `bin/statusline.sh` abaixo de `SL_ROOT`:

```bash
. "$SL_ROOT/lib/colors.sh"
. "$SL_ROOT/lib/core.sh"
. "$SL_ROOT/lib/stdin.sh"
. "$SL_ROOT/lib/config.sh"

input="$(cat)"
sl_parse_stdin "$input"
sl_config_load

# Load only the widgets the configuration actually asks for. A widget file that
# does not exist is skipped: the config may name a widget from a newer version.
for _w in $(printf '%s' "$SL_CONFIG_LINES" | tr '\n' ' '); do
  [ -f "$SL_ROOT/widgets/$_w.sh" ] && . "$SL_ROOT/widgets/$_w.sh"
done

sl_render_all
```

- [ ] **Step 8: Verificar de ponta a ponta**

Run:
```bash
echo '{"model":{"display_name":"Opus 5"}}' | ./bin/statusline.sh | cat -v
```
Expected: uma linha contendo `Opus 5` envolto em `^[[36m` e `^[[0m`.

- [ ] **Step 9: Commit**

```bash
git add lib/colors.sh lib/core.sh widgets/model.sh bin/statusline.sh tests/
git commit -m "feat: montagem de linhas e widget de modelo"
```

---

### Task 7: Cache e widget de git

**Files:**
- Create: `lib/cache.sh`
- Create: `widgets/git.sh`
- Modify: `bin/statusline.sh` (carregar `lib/cache.sh`)
- Test: `tests/cache.bats`, `tests/widgets/git.bats`

**Interfaces:**
- Consumes: `register_widget` (Task 3), `SL_CWD` (Task 2).
- Produces:
  - `cache_by_mtime <chave> <arquivo-sentinela> <comando...>` — imprime o valor
    em cache ou executa o comando e grava
  - `cache_by_ttl <chave> <segundos> <comando...>` — idem, expirando por tempo
  - `widget_git_render`

- [ ] **Step 1: Escrever o teste que falha**

Criar `tests/cache.bats`:

```bash
load helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/cache.sh"
  SENTINEL="$BATS_TEST_TMPDIR/sentinel"
  printf 'v1' > "$SENTINEL"
  CONTADOR="$BATS_TEST_TMPDIR/contador"
  printf '0' > "$CONTADOR"
  comando_contado() {
    local n; n=$(cat "$CONTADOR"); printf '%s' "$((n + 1))" > "$CONTADOR"
    printf 'resultado-%s' "$((n + 1))"
  }
}

@test "primeira chamada executa o comando" {
  run cache_by_mtime chave1 "$SENTINEL" comando_contado
  [ "$output" = "resultado-1" ]
  [ "$(cat "$CONTADOR")" = "1" ]
}

@test "segunda chamada com sentinela intacta usa o cache" {
  cache_by_mtime chave1 "$SENTINEL" comando_contado
  run cache_by_mtime chave1 "$SENTINEL" comando_contado
  [ "$output" = "resultado-1" ]
  [ "$(cat "$CONTADOR")" = "1" ]
}

@test "sentinela alterada invalida o cache" {
  cache_by_mtime chave1 "$SENTINEL" comando_contado
  sleep 1
  printf 'v2' > "$SENTINEL"
  run cache_by_mtime chave1 "$SENTINEL" comando_contado
  [ "$output" = "resultado-2" ]
}

@test "sentinela ausente executa o comando sem gravar cache" {
  run cache_by_mtime chave2 "$BATS_TEST_TMPDIR/nao-existe" comando_contado
  [ "$output" = "resultado-1" ]
}

@test "TTL não expirado usa o cache" {
  cache_by_ttl chave3 60 comando_contado
  run cache_by_ttl chave3 60 comando_contado
  [ "$output" = "resultado-1" ]
}

@test "TTL zero sempre recalcula" {
  cache_by_ttl chave4 0 comando_contado
  run cache_by_ttl chave4 0 comando_contado
  [ "$output" = "resultado-2" ]
}
```

Criar `tests/widgets/git.bats`:

```bash
load ../helper

setup() {
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/cache.sh"
  source "$PROJECT_ROOT/widgets/git.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  printf 'a' > "$REPO/a.txt"
  git -C "$REPO" add a.txt
  git -C "$REPO" commit -qm inicial
}

@test "mostra o nome da branch" {
  SL_CWD="$REPO"
  WIDGET_OUT=""
  widget_git_render
  [[ "$WIDGET_OUT" == *"$(git -C "$REPO" branch --show-current)"* ]]
}

@test "fora de repositório git, desaparece" {
  SL_CWD="$BATS_TEST_TMPDIR"
  WIDGET_OUT=""
  widget_git_render
  [ -z "$WIDGET_OUT" ]
}

@test "diretório inexistente desaparece sem erro" {
  SL_CWD="$BATS_TEST_TMPDIR/nao-existe"
  WIDGET_OUT=""
  run widget_git_render
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Rodar os testes para confirmar que falham**

Run: `bats tests/cache.bats tests/widgets/git.bats`
Expected: FAIL — `lib/cache.sh` e `widgets/git.sh` não existem.

- [ ] **Step 3: Implementar o cache**

Criar `lib/cache.sh`:

```bash
# Two caching strategies, written once and reused by any widget.
#
# The status line repaints every couple of seconds in every open terminal, so
# uncached git calls multiply fast. Both helpers degrade to running the command
# when anything about the cache is off.

: "${SL_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline}"

_sl_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

_sl_cache_file() {
  printf '%s/%s' "$SL_CACHE_DIR" "$1"
}

cache_by_mtime() {
  local key="$1" sentinel="$2"; shift 2
  local file mt cached_mt cached_val

  # No sentinel means nothing to compare against; just run.
  if [ ! -e "$sentinel" ]; then
    "$@"
    return 0
  fi

  mkdir -p "$SL_CACHE_DIR" 2>/dev/null
  file="$(_sl_cache_file "$key")"
  mt="$(_sl_mtime "$sentinel")"

  if [ -f "$file" ]; then
    IFS= read -r cached_mt < "$file"
    if [ "$cached_mt" = "$mt" ]; then
      cached_val="$(sed -n '2,$p' "$file")"
      printf '%s' "$cached_val"
      return 0
    fi
  fi

  cached_val="$("$@")"
  printf '%s\n%s' "$mt" "$cached_val" > "$file" 2>/dev/null
  printf '%s' "$cached_val"
}

cache_by_ttl() {
  local key="$1" ttl="$2"; shift 2
  local file now cached_at cached_val

  mkdir -p "$SL_CACHE_DIR" 2>/dev/null
  file="$(_sl_cache_file "$key")"
  now="$(date +%s)"

  if [ -f "$file" ] && [ "$ttl" -gt 0 ]; then
    IFS= read -r cached_at < "$file"
    if [ $((now - cached_at)) -lt "$ttl" ]; then
      cached_val="$(sed -n '2,$p' "$file")"
      printf '%s' "$cached_val"
      return 0
    fi
  fi

  cached_val="$("$@")"
  printf '%s\n%s' "$now" "$cached_val" > "$file" 2>/dev/null
  printf '%s' "$cached_val"
}
```

- [ ] **Step 4: Implementar o widget de git**

Criar `widgets/git.sh`:

```bash
# Current branch plus dirty/ahead/behind marks.
#
# Cached against .git/HEAD: branch changes and commits both touch it, and the
# whole point is to avoid spawning git on every repaint.

register_widget git \
  --render widget_git_render \
  --color  magenta \
  --desc   "Branch and working tree state"

_git_compute() {
  local branch dirty
  branch="$(git -C "$SL_CWD" --no-optional-locks branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || return 0
  dirty="$(git -C "$SL_CWD" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$dirty" != "0" ]; then
    printf '%s ●%s' "$branch" "$dirty"
  else
    printf '%s' "$branch"
  fi
}

widget_git_render() {
  local root key
  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  root="$(git -C "$SL_CWD" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$root" ] || return 0

  key="git-$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
  WIDGET_OUT="$(cache_by_mtime "$key" "$root/.git/HEAD" _git_compute)"
}
```

- [ ] **Step 5: Rodar os testes e confirmar que passam**

Run: `bats tests/cache.bats tests/widgets/git.bats`
Expected: 9 tests, 0 failures.

- [ ] **Step 6: Carregar o cache no entrypoint**

Em `bin/statusline.sh`, acrescentar após a linha que carrega `lib/core.sh`:

```bash
. "$SL_ROOT/lib/cache.sh"
```

- [ ] **Step 7: Verificar de ponta a ponta**

Run:
```bash
echo "{\"model\":{\"display_name\":\"Opus 5\"},\"workspace\":{\"current_dir\":\"$PWD\"}}" | ./bin/statusline.sh
```
Expected: linha com `Opus 5 | main` (ou o nome da branch corrente).

- [ ] **Step 8: Commit**

```bash
git add lib/cache.sh widgets/git.sh bin/statusline.sh tests/
git commit -m "feat: helpers de cache e widget de git"
```

---

### Task 8: Widget de previsão de rate limit

Este é o widget que valida o caso difícil: comando externo, cor semântica
própria e degradação quando o helper não existe.

**Desvio deliberado da spec.** A spec descreve um widget adaptador `command`
genérico, configurável por `type`/`exec`. Aqui o `rate-forecast` invoca o helper
diretamente, através de `SL_FORECAST_BIN`. A razão: o adaptador genérico precisa
resolver expansão de `~`, `timeout` portátil entre macOS e Linux, e sanitização
da saída — três problemas independentes que não cabem no v0.1 e que só têm
consumidor real quando o widget de Flow entrar. A chamada direta exercita o
mesmo caso-limite (processo externo, saída parseada, degradação quando ausente)
sem carregar esses três. O adaptador genérico vem junto do widget de Flow, e
substitui a chamada direta sem alterar o contrato de widget.

**Files:**
- Create: `widgets/rate-forecast.sh`
- Create: `tests/widgets/rate-forecast.bats`
- Create: `tests/fixtures/fake-forecast.sh`

**Interfaces:**
- Consumes: `register_widget` (Task 3), `SL_5H_PCT` e `SL_5H_RESET` (Task 2), `sl_config_widget_opt` (Task 5).
- Produces: `widget_rate_forecast_render`.

**Contrato do helper externo** (já existente, em `~/.claude/rate-forecast.sh`):

```
rate-forecast.sh <label> <used_pct> <resets_at_epoch> <duração_janela_s>
stdout: "<nível> <projeção>"   nível ∈ none|ok|warn|crit
        "none" sai sozinho, sem projeção
exit:   0 sempre
```

- [ ] **Step 1: Escrever o teste que falha**

Criar `tests/fixtures/fake-forecast.sh`:

```bash
#!/usr/bin/env bash
# Test double for rate-forecast.sh. Echoes what FAKE_FORECAST_OUT holds.
printf '%s' "${FAKE_FORECAST_OUT:-none}"
exit 0
```

```bash
chmod +x tests/fixtures/fake-forecast.sh
```

Criar `tests/widgets/rate-forecast.bats`:

```bash
load ../helper

setup() {
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/widgets/rate-forecast.sh"
  export SL_FORECAST_BIN="$PROJECT_ROOT/tests/fixtures/fake-forecast.sh"
  SL_5H_PCT="42"
  SL_5H_RESET="1800000000"
  SL_CONFIG_RAW=""
}

@test "sem percentual, desaparece" {
  SL_5H_PCT=""
  WIDGET_OUT=""
  widget_rate_forecast_render
  [ -z "$WIDGET_OUT" ]
}

@test "nível none mostra só o percentual" {
  export FAKE_FORECAST_OUT="none"
  WIDGET_OUT=""
  widget_rate_forecast_render
  [[ "$WIDGET_OUT" == *"42%"* ]]
  [[ "$WIDGET_OUT" != *"→"* ]]
}

@test "nível crit mostra a projeção" {
  export FAKE_FORECAST_OUT="crit 116"
  WIDGET_OUT=""
  widget_rate_forecast_render
  [[ "$WIDGET_OUT" == *"→116%"* ]]
}

@test "nível crit pinta de vermelho" {
  export FAKE_FORECAST_OUT="crit 116"
  WIDGET_OUT=""
  widget_rate_forecast_render
  [[ "$WIDGET_OUT" == *$'\033[31m'* ]]
}

@test "nível warn pinta de amarelo" {
  export FAKE_FORECAST_OUT="warn 92"
  WIDGET_OUT=""
  widget_rate_forecast_render
  [[ "$WIDGET_OUT" == *$'\033[33m'* ]]
}

@test "helper ausente ainda mostra o percentual" {
  export SL_FORECAST_BIN="/caminho/que/nao/existe"
  WIDGET_OUT=""
  widget_rate_forecast_render
  [[ "$WIDGET_OUT" == *"42%"* ]]
}

@test "o widget declara self-color" {
  [ "$(sl_widget_attr SELFCOLOR rate-forecast)" = "1" ]
}
```

- [ ] **Step 2: Rodar o teste para confirmar que falha**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: FAIL — `widgets/rate-forecast.sh` não existe.

- [ ] **Step 3: Implementar o widget**

Criar `widgets/rate-forecast.sh`:

```bash
# Rate-limit window usage with overflow forecast.
#
# Colour is semantic here — it encodes the forecast level, not a user
# preference — so the widget declares --self-color and paints itself.
#
# The forecast maths lives in an external helper (see SL_FORECAST_BIN). When
# that helper is missing, the widget still shows the current percentage: a
# degraded reading beats no reading.

register_widget rate-forecast \
  --render widget_rate_forecast_render \
  --self-color \
  --desc   "5h window usage with overflow forecast"

: "${SL_FORECAST_BIN:=$HOME/.claude/rate-forecast.sh}"

_forecast_window_seconds() {
  case "$1" in
    7d) printf '604800' ;;
    *)  printf '18000'  ;;
  esac
}

widget_rate_forecast_render() {
  local window pct reset level proj out color raw

  window="$(sl_config_widget_opt rate-forecast window)"
  [ -n "$window" ] || window="5h"

  if [ "$window" = "7d" ]; then
    pct="$SL_7D_PCT"; reset="$SL_7D_RESET"
  else
    pct="$SL_5H_PCT"; reset="$SL_5H_RESET"
  fi

  [ -n "$pct" ] || return 0

  level="none"; proj=""
  if [ -x "$SL_FORECAST_BIN" ]; then
    raw="$("$SL_FORECAST_BIN" "$window" "$pct" "$reset" \
           "$(_forecast_window_seconds "$window")" 2>/dev/null)"
    set -- $raw
    [ -n "$1" ] && level="$1"
    [ -n "$2" ] && proj="$2"
  fi

  case "$level" in
    crit) color="$(sl_color red)"    ;;
    warn) color="$(sl_color yellow)" ;;
    ok)   color="$(sl_color green)"  ;;
    *)    color=""                   ;;
  esac

  out="${window}:${pct}%"
  [ -n "$proj" ] && out="$out→${proj}%"

  if [ -n "$color" ]; then
    WIDGET_OUT="$color$out$SL_RESET"
  else
    WIDGET_OUT="$out"
  fi
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `bats tests/widgets/rate-forecast.bats`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `bats tests/ --recursive`
Expected: todas as suítes passam.

- [ ] **Step 6: Commit**

```bash
git add widgets/rate-forecast.sh tests/
git commit -m "feat: widget de previsão de rate limit com cor semântica"
```

---

### Task 9: Teste golden, comando de instalação, CI e README

**Files:**
- Create: `tests/golden.bats`
- Create: `tests/fixtures/session.json`
- Create: `commands/setup.md`
- Create: `.github/workflows/ci.yml`
- Create: `README.md`

**Interfaces:**
- Consumes: tudo das tarefas anteriores.
- Produces: repositório instalável e verificado em CI.

- [ ] **Step 1: Criar a fixture de sessão**

Criar `tests/fixtures/session.json`:

```json
{
  "model": { "display_name": "Opus 5", "id": "claude-opus-5" },
  "workspace": { "current_dir": "/tmp" },
  "cost": { "total_cost_usd": 1.23, "total_lines_added": 10, "total_lines_removed": 2 },
  "context_window": { "context_window_size": 200000, "total_input_tokens": 45000 },
  "rate_limits": {
    "five_hour": { "used_percentage": 42, "resets_at": 1800000000 },
    "seven_day": { "used_percentage": 13, "resets_at": 1800600000 }
  }
}
```

- [ ] **Step 2: Escrever o teste golden**

Criar `tests/golden.bats`:

```bash
load helper

setup() {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export SL_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export SL_FORECAST_BIN="/caminho/que/nao/existe"
  mkdir -p "$XDG_CONFIG_HOME/claude-code-statusline"
  cat > "$XDG_CONFIG_HOME/claude-code-statusline/config.json" <<'EOF'
{"version":1,"lines":[["model"],["rate-forecast"]],"separator":"|"}
EOF
}

@test "renderiza duas linhas com a fixture" {
  run bash -c '"$0" < "$1"' "$PROJECT_ROOT/bin/statusline.sh" "$PROJECT_ROOT/tests/fixtures/session.json"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" = "1" ]
  [[ "$output" == *"Opus 5"* ]]
  [[ "$output" == *"5h:42%"* ]]
}

@test "stdin inválido ainda imprime algo e sai com zero" {
  run bash -c 'printf "nao e json" | "$0"' "$PROJECT_ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]
}

@test "config inválida não é sobrescrita" {
  printf 'quebrado {' > "$XDG_CONFIG_HOME/claude-code-statusline/config.json"
  run bash -c '"$0" < "$1"' "$PROJECT_ROOT/bin/statusline.sh" "$PROJECT_ROOT/tests/fixtures/session.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_CONFIG_HOME/claude-code-statusline/config.json")" = 'quebrado {' ]
}
```

- [ ] **Step 3: Rodar o teste golden**

Run: `bats tests/golden.bats`
Expected: 3 tests, 0 failures. Se falhar por diferença de espaçamento, corrigir
o teste para refletir a saída real — desde que a saída real esteja correta.

- [ ] **Step 4: Escrever o comando de instalação**

Criar `commands/setup.md`:

```markdown
---
description: Instala a claude-code-statusline no settings.json
---

Configure a statusline deste plugin para o usuário.

## Passo 1: Localizar o entrypoint

O caminho é `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`. Confirme que existe e é
executável.

## Passo 2: Verificar as dependências

Rode `command -v jq` e `command -v git`. Se `jq` faltar, informe que a
statusline vai rodar em modo degradado e sugira `brew install jq` no macOS ou o
gerenciador de pacotes equivalente. Não aborte por isso.

## Passo 3: Fazer backup do settings.json

O arquivo fica em `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`.

Copie para `settings.json.bak.YYYYMMDD-HHMMSS`.

**Importante:** esse arquivo pode ser um symlink gerenciado por dotfiles.
Ao escrever, use `cat arquivo-novo > settings.json`, nunca `mv`. Um `mv`
substitui o symlink por um arquivo comum e desconecta o repositório de dotfiles
do usuário sem aviso.

## Passo 4: Escrever a chave statusLine

Faça merge preservando todas as demais chaves:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <caminho-absoluto>/bin/statusline.sh",
    "refreshInterval": 5
  }
}
```

## Passo 5: Criar a configuração padrão

Se `${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-statusline/config.json` não
existir, crie com:

```json
{
  "version": 1,
  "lines": [["model", "git"], ["rate-forecast"]],
  "separator": "|"
}
```

Se já existir, não toque nele.

## Passo 6: Verificar

Rode o entrypoint com uma sessão de exemplo e confirme que imprime algo:

```bash
echo '{"model":{"display_name":"Test"}}' | bash <caminho>/bin/statusline.sh
```

Peça ao usuário para reiniciar o Claude Code.
```

- [ ] **Step 5: Escrever o workflow de CI**

Criar `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-latest, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Instalar bats e jq (macOS)
        if: runner.os == 'macOS'
        run: brew install bats-core jq

      - name: Instalar bats e jq (Linux)
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y bats jq

      - name: Registrar a versão do bash
        run: bash --version

      - name: Rodar os testes
        run: bats tests/ --recursive
```

- [ ] **Step 6: Escrever o README**

Criar `README.md` em inglês, cobrindo: o que o projeto é e os três eixos que o
justificam; requisitos (bash 3.2+, `jq`, `git`); instalação via
`/claude-code-statusline:setup`; o schema completo do `config.json` com todos os
campos e um exemplo; a lista dos três widgets do v0.1 com suas opções; e uma
seção "Writing a widget" mostrando `widgets/model.sh` na íntegra como exemplo
mínimo, mais a tabela de flags de `register_widget`.

- [ ] **Step 7: Rodar a suíte completa uma última vez**

Run: `bats tests/ --recursive`
Expected: todas passam.

- [ ] **Step 8: Commit**

```bash
git add tests commands .github README.md
git commit -m "feat: teste golden, comando de instalação, CI e README"
```

- [ ] **Step 9: Instalar e usar de verdade**

Rodar `/claude-code-statusline:setup` no Claude Code, reiniciar, e confirmar que
a statusline aparece. Manter o `statusline.sh` antigo disponível para voltar
atrás — a troca definitiva só acontece quando houver paridade de widgets, que
está fora do v0.1.

---

## Notas para quem for migrar os oito widgets restantes

Fora do escopo do v0.1, mas mapeado durante o design. Os widgets que faltam para
paridade com o `statusline.sh` atual são: `repo` (com hyperlink OSC 8), `branch`
e `worktree`, `git-status` (dirty/ahead/behind separado), `velocity`, `cache`
(taxa de acerto), `cost`, `context` (barra com gradiente em oitavos) e `sprint`
(saúde de sprint BMAD). O `flow` (consumo do gateway CI&T) entra pelo widget
adaptador `command`, sem port.

Cada um é um arquivo em `widgets/`, um arquivo de teste em `tests/widgets/`, e
uma entrada no `README.md`. Nenhum exige alteração no núcleo — se algum exigir,
o contrato está errado e é isso que precisa ser corrigido, não o widget.

A exceção é o widget adaptador `command` genérico (ver o desvio declarado na
Task 8): ele é núcleo, não widget de domínio, e precisa resolver expansão de
`~`, `timeout` portátil entre macOS e Linux, e sanitização de sequências de
escape na saída de terceiros. Implementá-lo junto do widget de Flow dá a ele um
consumidor real desde o primeiro dia.
