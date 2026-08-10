#!/bin/bash
# Status line inspirado no tema Pure do Oh My Zsh
# Estilo minimalista: diretório atual + branch git + barra de contexto truecolor

# Schema do JSON recebido na stdin (Claude Code statusLine):
# {
#     "session_id":"...",
#     "transcript_path":"...",
#     "cwd":"/Users/nidelson/Projects/nidelson/sip",
#     "model":{"id":"claude-...","display_name":"Sonnet 4.5"},
#     "workspace":{"current_dir":"...","project_dir":"..."},
#     "version":"2.0.76",
#     "output_style":{"name":"default"},
#     "cost":{"total_cost_usd":0.0234,"total_duration_ms":274957,"total_lines_added":0,"total_lines_removed":0},
#     "context_window":{
#         "total_input_tokens":9076,"total_output_tokens":1143,
#         "context_window_size":200000,
#         "current_usage":{"input_tokens":...,"cache_creation_input_tokens":...,"cache_read_input_tokens":...} | null
#     },
#     "exceeds_200k_tokens":false
# }

# Read JSON input once
input=$(cat)

# ── Colors ──
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
CLAUDE_BRAND='\033[38;2;217;119;87m'  # coral da marca Claude (#D97757)
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Truecolor helper ──
rgb() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }

# ── Token formatter: 69000 → "69k", 1000000 → "1.0M", 950 → "950" ──
fmt_tokens() {
  local n=$1
  [[ "$n" =~ ^[0-9]+$ ]] || { printf '0'; return; }
  if [ "$n" -ge 1000000 ]; then
    printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}

# ── Parse JSON fields ──
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
model_id=$(echo "$input" | jq -r '.model.id // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Ícone do modelo: ✻ na cor da marca Claude p/ modelos Anthropic, 🤖 p/ outros.
# Usa model.id quando presente (ex.: claude-opus-4-8, us.anthropic.claude-...),
# senão cai no display_name (família Opus/Sonnet/Haiku/Fable).
# ✻ (U+273B) é o mesmo glifo do indicador de "pensando" do Claude Code; é
# glifo-texto (aceita cor ANSI, ao contrário de emoji), pintado no coral da
# marca (#D97757).
# model_color: coral da marca p/ Anthropic (casa com o ícone ✻), MAGENTA p/ os
# demais. A cor aqui é decorativa (não codifica estado, ao contrário dos blocos
# de contexto/rate-limit) — serve só pra identidade visual do modelo.
model_lc=$(printf '%s' "${model_id:-$model}" | tr '[:upper:]' '[:lower:]')
case "$model_lc" in
  claude*|*anthropic*|*opus*|*sonnet*|*haiku*|*fable*) model_icon="${CLAUDE_BRAND}✻${RESET}"; model_color="$CLAUDE_BRAND" ;;
  *) model_icon="🤖"; model_color="$MAGENTA" ;;
esac
lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_del=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')

# ── Cache hit ratio ──
# cache_read_input_tokens  = tokens servidos do cache (5× mais barato)
# cache_creation_input_tokens = tokens gravados no cache (TTL 5min)
# Ratio alto = cache quente, sessão eficiente; ratio baixo = cache frio ou início de sessão
cache_part=""
usage_raw=$(echo "$input" | jq -c '.context_window.current_usage')
if [ "$usage_raw" != "null" ] && [ -n "$usage_raw" ]; then
  cache_read=$(echo "$usage_raw" | jq -r '.cache_read_input_tokens // 0')
  cache_create=$(echo "$usage_raw" | jq -r '.cache_creation_input_tokens // 0')
  fresh=$(echo "$usage_raw" | jq -r '.input_tokens // 0')
  total_for_cache=$(( cache_read + cache_create + fresh ))
  if [ "$total_for_cache" -gt 0 ]; then
    hit_pct=$(( (cache_read * 100 + total_for_cache / 2) / total_for_cache ))
    if [ "$hit_pct" -ge 70 ]; then cache_color="$GREEN"
    elif [ "$hit_pct" -ge 30 ]; then cache_color="$YELLOW"
    else cache_color="$RED"; fi
    cache_part="☁ ${cache_color}${hit_pct}%${RESET}"
  fi
fi

# ── Context % ──
# Usa total_input_tokens (acumulado da sessão) — alinhado com o % exibido pelo Claude UI.
# current_usage reflete apenas a última troca e subestima o contexto real (~9% de diferença).
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
total_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
used=""
if [[ "$total_tokens" =~ ^[0-9]+$ ]] && [ "$total_tokens" -gt 0 ] && [[ "$ctx_size" =~ ^[0-9]+$ ]] && [ "$ctx_size" -gt 0 ]; then
  used=$(( (total_tokens * 100 + ctx_size / 2) / ctx_size ))  # arredonda ao inteiro mais próximo
fi

# ── Git info ──
branch=""
repo=""
gitroot=""
worktree=""
dirty_count=""
ahead=""
behind=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  # Detached HEAD (comum em worktree de bot/CI): sha curto no lugar da branch.
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null | sed 's/^/@/')
  # gitroot = toplevel do working tree atual (em worktree, a raiz DO worktree —
  # tem seu próprio _bmad-output versionado, na branch dele). Usado pelo sprint.
  gitroot=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
  repo=$(basename "$gitroot" 2>/dev/null)

  # Worktree linkado: --git-dir aponta p/ .git/worktrees/<nome>; --git-common-dir,
  # p/ o .git do repo principal. Iguais = working tree principal.
  # --path-format=absolute (git >= 2.31) evita comparar ".git" relativo com absoluto.
  wt_paths=$(git -C "$cwd" --no-optional-locks rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)
  wt_gitdir=$(printf '%s\n' "$wt_paths" | sed -n 1p)
  wt_common=$(printf '%s\n' "$wt_paths" | sed -n 2p)
  if [ -n "$wt_gitdir" ] && [ -n "$wt_common" ] && [ "$wt_gitdir" != "$wt_common" ]; then
    worktree="$repo"                            # basename do diretório do worktree
    repo=$(basename "$(dirname "$wt_common")")  # nome do repo principal
  fi
  # Dirty count: arquivos modificados/untracked (porcelain = 1 linha por arquivo)
  dc=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | grep -c .)
  [ -n "$dc" ] && [ "$dc" -gt 0 ] && dirty_count="$dc"
  # Ahead/behind vs upstream (só quando há upstream configurado)
  ab=$(git -C "$cwd" --no-optional-locks rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  if [ -n "$ab" ]; then
    ahead=$(printf '%s' "$ab" | awk '{print $1}')
    behind=$(printf '%s' "$ab" | awk '{print $2}')
  fi
fi

# ── Git status glyphs: ●dirty ↑ahead ↓behind ──
gitstat=""
[ -n "$dirty_count" ] && gitstat="${YELLOW}●${dirty_count}${RESET}"
if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then gitstat="${gitstat:+$gitstat }${GREEN}↑${ahead}${RESET}"; fi
if [ -n "$behind" ] && [ "$behind" -gt 0 ]; then gitstat="${gitstat:+$gitstat }${RED}↓${behind}${RESET}"; fi

# ── Context bar: RGB gradient, full blocks only ──
BAR_WIDTH=20

if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")

  # Round to nearest block
  filled=$(( (used_int * BAR_WIDTH + 50) / 100 ))

  bar=""
  for (( i=0; i<BAR_WIDTH; i++ )); do
    pos=$(( i * 100 / (BAR_WIDTH - 1) ))

    if [ "$pos" -le 50 ]; then
      r=$(( 0 + 220 * pos / 50 ))
      g=200
      b=$(( 80 - 80 * pos / 50 ))
    else
      adj=$(( pos - 50 ))
      r=220
      g=$(( 200 - 160 * adj / 50 ))
      b=$(( 0 + 20 * adj / 50 ))
    fi

    if [ "$i" -lt "$filled" ]; then
      bar="${bar}$(rgb $r $g $b)█"
    else
      bar="${bar}\033[38;2;60;60;60m░"
    fi
  done
  bar="${bar}${RESET}"

  if [ "$used_int" -ge 90 ]; then status_emoji="🚨"
  elif [ "$used_int" -ge 70 ]; then status_emoji="🔥"
  elif [ "$used_int" -ge 20 ]; then status_emoji="⚡"
  else status_emoji="🟢"; fi

  if [ "$used_int" -ge 90 ]; then pct_color="$RED"
  elif [ "$used_int" -ge 70 ]; then pct_color="$YELLOW"
  else pct_color="$GREEN"; fi

  # Tokens usados/total entre parênteses (ex.: "(69k/1.0M)")
  ctx_tokens="${DIM}($(fmt_tokens "$total_tokens")/$(fmt_tokens "$ctx_size"))${RESET}"
  ctx_part="${status_emoji} ${bar} ${pct_color}${used_int}%${RESET} ${ctx_tokens}"
else
  ctx_part="🟢 \033[38;2;60;60;60m░░░░░░░░░░░░░░░░░░░░${RESET} --%"
fi

# ── Rate limits (5h e 7d) ──
rate_part=""
fh_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
wd_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
# Arredonda ao inteiro — a fonte traz float (ex.: 14.000000000000002) e o
# rate_color usa comparação inteira ([ -ge ]) que quebra com casas decimais.
[ -n "$fh_pct" ] && fh_pct=$(printf '%.0f' "$fh_pct")
[ -n "$wd_pct" ] && wd_pct=$(printf '%.0f' "$wd_pct")

# ── Reset da janela 5h: horário local + tempo restante ──
# resets_at vem como epoch numérico (Claude Code) ou ISO string (fallback).
# Normaliza ms→s, calcula relógio local (BSD date -r) e o restante "Xh Ym".
fh_reset_str=""
fh_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
if [ -n "$fh_reset" ] && [ "$fh_reset" != "null" ]; then
  reset_epoch=""
  if [[ "$fh_reset" =~ ^[0-9]+$ ]]; then
    if [ "${#fh_reset}" -ge 13 ]; then reset_epoch=$(( fh_reset / 1000 )); else reset_epoch=$fh_reset; fi
  elif [[ "$fh_reset" =~ ^[0-9]+\.[0-9]+$ ]]; then
    reset_epoch=${fh_reset%.*}
  else
    # ISO 8601 → epoch (python3 é robusto a fração de segundo e 'Z')
    reset_epoch=$(python3 -c 'import sys,datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "$fh_reset" 2>/dev/null)
  fi
  if [[ "$reset_epoch" =~ ^[0-9]+$ ]]; then
    clock=$(date -r "$reset_epoch" +%H:%M 2>/dev/null)
    rem=$(( reset_epoch - $(date +%s) ))
    [ "$rem" -lt 0 ] && rem=0
    rh=$(( rem / 3600 )); rm=$(( (rem % 3600) / 60 ))
    if [ "$rh" -gt 0 ]; then remstr="${rh}h${rm}m"; else remstr="${rm}m"; fi
    [ -n "$clock" ] && fh_reset_str="⟳${clock}·${remstr}"
  fi
fi

# ── Reset da janela 7d: dia da semana + tempo restante (dias/horas) ──
# Reset fica dias à frente — só HH:MM seria ambíguo, então mostra o dia (BSD date +%a).
wd_reset_str=""
wd_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
if [ -n "$wd_reset" ] && [ "$wd_reset" != "null" ]; then
  wr_epoch=""
  if [[ "$wd_reset" =~ ^[0-9]+$ ]]; then
    if [ "${#wd_reset}" -ge 13 ]; then wr_epoch=$(( wd_reset / 1000 )); else wr_epoch=$wd_reset; fi
  elif [[ "$wd_reset" =~ ^[0-9]+\.[0-9]+$ ]]; then
    wr_epoch=${wd_reset%.*}
  else
    wr_epoch=$(python3 -c 'import sys,datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "$wd_reset" 2>/dev/null)
  fi
  if [[ "$wr_epoch" =~ ^[0-9]+$ ]]; then
    wday=$(date -r "$wr_epoch" +%a 2>/dev/null)
    wrem=$(( wr_epoch - $(date +%s) ))
    [ "$wrem" -lt 0 ] && wrem=0
    wd_days=$(( wrem / 86400 )); wd_hrs=$(( (wrem % 86400) / 3600 ))
    if [ "$wd_days" -gt 0 ]; then wremstr="${wd_days}d${wd_hrs}h"; else wremstr="${wd_hrs}h"; fi
    [ -n "$wday" ] && wd_reset_str="⟳${wday}·${wremstr}"
  fi
fi

if [ -n "$fh_pct" ] || [ -n "$wd_pct" ]; then
  rate_color() {
    local p=$1
    if [ "$p" -ge 80 ]; then printf '%s' "$RED"
    elif [ "$p" -ge 50 ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"; fi
  }
  rate_part="⏱"
  [ -n "$fh_pct" ] && rate_part="${rate_part} ${DIM}5h:${RESET}$(rate_color "$fh_pct")${fh_pct}%${RESET}"
  [ -n "$fh_reset_str" ] && rate_part="${rate_part} ${DIM}${fh_reset_str}${RESET}"
  [ -n "$wd_pct" ] && rate_part="${rate_part} ${DIM}·${RESET} ${DIM}7d:${RESET}$(rate_color "$wd_pct")${wd_pct}%${RESET}"
  [ -n "$wd_reset_str" ] && rate_part="${rate_part} ${DIM}${wd_reset_str}${RESET}"
fi

# ── Cost ──
cost_part="${YELLOW}$(printf '$%.2f' "$cost")${RESET}"

# ── Code velocity ──
velocity="${GREEN}+${lines_add}${RESET} ${RED}-${lines_del}${RESET}"

# ── Linha 1: identidade (repo · branch · git status · velocity · cache · model · cost) ──
line1=""
[ -n "$repo" ] && line1="🗳  ${BOLD}${YELLOW}${repo}${RESET}"
# Worktree em magenta () p/ destacar que o cwd não é o repo principal.
# Quando o worktree tem o mesmo nome da branch, mostra só uma vez.
if [ -n "$worktree" ]; then
  if [ "$worktree" = "$branch" ]; then
    line1="${line1:+$line1 }${BOLD}${MAGENTA} (${branch})${RESET}"
  else
    line1="${line1:+$line1 }${BOLD}${MAGENTA} ${worktree}${RESET} ${BOLD}${CYAN}(${branch})${RESET}"
  fi
elif [ -n "$branch" ]; then
  line1="${line1:+$line1 }${BOLD}${CYAN}🌿 (${branch})${RESET}"
fi
[ -n "$gitstat" ] && line1="${line1:+$line1 }${gitstat}"
line1="${line1:+$line1 ${DIM}|${RESET} }${velocity}"
[ -n "$cache_part" ] && line1="${line1} ${DIM}|${RESET} ${cache_part}"
line1="${line1} ${DIM}|${RESET} ${model_icon} ${model_color}${model}${RESET}"
line1="${line1} ${DIM}|${RESET} ${cost_part}"

# ── Sprint health (projetos BMAD) ──
# Só quando existe sprint-status.yaml no repo (auto-pula projetos não-BMAD).
# Cache por mtime do yaml em $TMPDIR: o statusline renderiza a cada frame, então
# o parse (python) roda só quando o sprint muda; o caso comum é 1 stat + 1 read.
sprint_part=""
if [ -n "$gitroot" ]; then
  sprint_yaml="$gitroot/_bmad-output/implementation-artifacts/sprint-status.yaml"
  if [ -f "$sprint_yaml" ]; then
    ymt=$(stat -f %m "$sprint_yaml" 2>/dev/null || stat -c %Y "$sprint_yaml" 2>/dev/null || echo 0)
    skey=$(printf '%s' "$gitroot" | cksum | cut -d' ' -f1)
    sprint_cache="${TMPDIR:-/tmp}/claude-sprint-${skey}.cache"
    # sprint_raw = "<done>/<total> <ready> <review>" (helper). Cache = mtime + raw.
    sprint_raw=""
    if [ -f "$sprint_cache" ]; then
      read -r cmt cval < "$sprint_cache"
      [ "$cmt" = "$ymt" ] && sprint_raw="$cval"
    fi
    if [ -z "$sprint_raw" ]; then
      # Prioriza a cópia versionada no repo (funciona pro time sem depender do
      # dotfiles pessoal); cai pro global só se o projeto não tiver a cópia.
      script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
      sprint_helper="$script_dir/sprint-health-line.sh"
      [ -f "$sprint_helper" ] || sprint_helper="$HOME/.claude/sprint-health-line.sh"
      sprint_raw=$(bash "$sprint_helper" "$sprint_yaml" 2>/dev/null)
      [ -n "$sprint_raw" ] && printf '%s %s\n' "$ymt" "$sprint_raw" > "$sprint_cache" 2>/dev/null
    fi
    if [ -n "$sprint_raw" ]; then
      read -r s_ratio s_ready s_review <<< "$sprint_raw"
      s_done=${s_ratio%/*}; s_tot=${s_ratio#*/}
      # Cor por ratio de conclusão: ≥80 verde, ≥40 amarelo, <40 vermelho.
      s_color="$GREEN"
      if [[ "$s_done" =~ ^[0-9]+$ ]] && [[ "$s_tot" =~ ^[0-9]+$ ]] && [ "$s_tot" -gt 0 ]; then
        s_pct=$(( s_done * 100 / s_tot ))
        if [ "$s_pct" -ge 80 ]; then s_color="$GREEN"
        elif [ "$s_pct" -ge 40 ]; then s_color="$YELLOW"
        else s_color="$RED"; fi
      fi
      sprint_part="⚑ ${s_color}${s_ratio}${RESET}"
      # ▸N: stories ready-for-dev (fila) nos epics ativos — antes do review.
      if [[ "$s_ready" =~ ^[0-9]+$ ]] && [ "$s_ready" -gt 0 ]; then
        sprint_part="${sprint_part} ${CYAN}▸${s_ready}${RESET}"
      fi
      # ⚠N: stories em review nos epics ativos (só quando N > 0).
      if [[ "$s_review" =~ ^[0-9]+$ ]] && [ "$s_review" -gt 0 ]; then
        sprint_part="${sprint_part} ${YELLOW}⚠${s_review}${RESET}"
      fi
    fi
  fi
fi

# ── Flow consumption: budget (USD) + requests (CI&T) ──
# Consulta é assíncrona: statusline SÓ lê o cache; nunca espera rede.
# Cache expirado (>5min) + token presente → dispara refresh em background e
# segue com o valor da rodada anterior (ou nada, na primeira execução).
# flow-consumption-line.sh grava as duas métricas num único cache — um único
# refresh em background cobre ambos os "parts" abaixo.
#
# Countdown até o reset (mesmo padrão de wd_reset_str) — só faz sentido
# mostrar quando há risco (projeção presente) ou já bloqueado.
# args: renewal_epoch
fmt_flow_reset() {
  local renewal_epoch="$1"
  [[ "$renewal_epoch" =~ ^[0-9]+$ ]] || return
  local wday rem rem_days rem_hrs rem_str
  wday=$(date -r "$renewal_epoch" +%a 2>/dev/null)
  rem=$(( renewal_epoch - $(date +%s) ))
  [ "$rem" -lt 0 ] && rem=0
  rem_days=$(( rem / 86400 )); rem_hrs=$(( (rem % 86400) / 3600 ))
  if [ "$rem_days" -gt 0 ]; then rem_str="${rem_days}d${rem_hrs}h"; else rem_str="${rem_hrs}h"; fi
  [ -n "$wday" ] && printf ' %b⟳%s·%s%b' "$DIM" "$wday" "$rem_str" "$RESET"
}

# Countdown até o bloqueio projetado (proj > 100%) — quando a taxa atual leva
# ao limite ANTES do reset do ciclo. Mesmo formato do reset, mas com ícone e
# cor de alerta próprios, pra não confundir "quando renova" com "quando trava".
# args: blocked_epoch
fmt_flow_blocked() {
  local blocked_epoch="$1"
  [[ "$blocked_epoch" =~ ^[0-9]+$ ]] || return
  local wday rem rem_days rem_hrs rem_str
  wday=$(date -r "$blocked_epoch" +%a 2>/dev/null)
  rem=$(( blocked_epoch - $(date +%s) ))
  [ "$rem" -lt 0 ] && rem=0
  rem_days=$(( rem / 86400 )); rem_hrs=$(( (rem % 86400) / 3600 ))
  if [ "$rem_days" -gt 0 ]; then rem_str="${rem_days}d${rem_hrs}h"; else rem_str="${rem_hrs}h"; fi
  [ -n "$wday" ] && printf ' %b🔒%s·%s%b' "${BOLD}${RED}" "$wday" "$rem_str" "$RESET"
}

# Cor por faixa de percentual (budget/requests): <80 verde, <95 amarelo,
# <100 vermelho, ≥100 vermelho negrito. Aplicada independentemente ao valor
# atual e ao projetado, pra um não "contaminar" a cor do outro (ex.: atual
# 4% verde, projetado 116% vermelho).
flow_pct_color() {
  local p=$1
  if [ "$p" -ge 100 ]; then printf '%s' "${BOLD}${RED}"
  elif [ "$p" -ge 95 ]; then printf '%s' "$RED"
  elif [ "$p" -ge 80 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

flow_budget_part=""
flow_requests_part=""
flow_unlimited_part=""
flow_blocked_epoch=""
# Nem toda métrica que a API marca como "blocked" trava de fato a sessão —
# hoje só requests bloqueia; budget estourado (USD) é só aviso. Flags pra
# religar o countdown de 🔒 (bloqueio) se isso mudar no futuro.
FLOW_BUDGET_BLOCKS="${FLOW_BUDGET_BLOCKS:-false}"
FLOW_REQUESTS_BLOCKS="${FLOW_REQUESTS_BLOCKS:-true}"
if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  flow_cache="${XDG_CACHE_HOME:-$HOME/.cache}/flow-consumption.json"
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  flow_helper="$script_dir/flow-consumption-line.sh"
  fetched_at=0
  [ -f "$flow_cache" ] && fetched_at=$(jq -r '.fetched_at // 0' "$flow_cache" 2>/dev/null)
  [[ "$fetched_at" =~ ^[0-9]+$ ]] || fetched_at=0
  age=$(( $(date +%s) - fetched_at ))
  if [ -f "$flow_helper" ] && { [ ! -f "$flow_cache" ] || [ "$age" -ge 300 ]; }; then
    ( nohup bash "$flow_helper" >/dev/null 2>&1 & disown ) 2>/dev/null
  fi
  if [ -f "$flow_cache" ] && [ "$(jq -r '.ok // false' "$flow_cache" 2>/dev/null)" = "true" ]; then
    # -- budget (USD) --
    flow_limit=$(jq -r '.budget.budget_limit // 0' "$flow_cache" 2>/dev/null)
    flow_pct=$(jq -r '.budget.percentage // 0' "$flow_cache" 2>/dev/null)
    flow_pct_int=$(printf '%.0f' "${flow_pct:-0}" 2>/dev/null || echo 0)
    flow_proj=$(jq -r '.budget.projected_percentage // empty' "$flow_cache" 2>/dev/null)
    flow_renewal_epoch=$(jq -r '.budget.renewal_epoch // empty' "$flow_cache" 2>/dev/null)
    flow_budget_blocked_epoch=$(jq -r '.budget.blocked_epoch // empty' "$flow_cache" 2>/dev/null)
    if [ "$flow_limit" = "0" ]; then
      # Usuário ilimitado: sem % pra mostrar, mas o consumo em USD ainda dá
      # ciência do gasto (nunca bloqueia, só informa).
      flow_consumed=$(jq -r '.budget.consumed_usd // 0' "$flow_cache" 2>/dev/null)
      flow_consumed_int=$(printf '%.0f' "${flow_consumed:-0}" 2>/dev/null || echo 0)
      flow_budget_part="${CYAN}💰♾️ \$$(fmt_tokens "$flow_consumed_int")${RESET}"
    else
      # Cor independente pro atual e pro projetado — cada um segue os mesmos
      # limiares (<80 verde, <95 amarelo, <100 vermelho, ≥100 vermelho negrito),
      # mas aplicados ao seu próprio valor (ex.: atual 4% verde, projetado
      # 116% vermelho, em vez de os dois herdarem a cor do pior caso).
      flow_budget_part="💰 $(flow_pct_color "$flow_pct_int")${flow_pct_int}%${RESET}"
      if [ -n "$flow_proj" ]; then
        flow_proj_int=$(printf '%.0f' "$flow_proj" 2>/dev/null || echo "$flow_pct_int")
        flow_budget_part="${flow_budget_part}→$(flow_pct_color "$flow_proj_int")${flow_proj_int}%${RESET}"
      fi

      # Reset (renewal_date) é o mesmo ciclo pra budget e requests — vira um
      # único bloco no final da linha em vez de repetir em cada percentual.
      if [ -n "$flow_proj" ] || [ "$flow_pct_int" -ge 100 ]; then
        flow_reset_needed=true
        flow_reset_epoch="$flow_renewal_epoch"
      fi
      if [ "$FLOW_BUDGET_BLOCKS" = "true" ]; then
        [[ "$flow_budget_blocked_epoch" =~ ^[0-9]+$ ]] && flow_blocked_epoch="$flow_budget_blocked_epoch"
      fi
    fi

    # -- requests (contagem) --
    # Usuário NO_LIMIT (unlimited=true) já vem com percentual/projeção
    # calculados pelo helper sobre um limite de referência (nunca bloqueia) —
    # o selo ♾️ vai num bloco próprio, separado do percentual.
    req_pct=$(jq -r '.requests.percentage // 0' "$flow_cache" 2>/dev/null)
    req_pct_int=$(printf '%.0f' "${req_pct:-0}" 2>/dev/null || echo 0)
    req_proj=$(jq -r '.requests.projected_percentage // empty' "$flow_cache" 2>/dev/null)
    req_renewal_epoch=$(jq -r '.requests.renewal_epoch // empty' "$flow_cache" 2>/dev/null)
    req_unlimited=$(jq -r '.requests.unlimited // false' "$flow_cache" 2>/dev/null)
    req_blocked_epoch=$(jq -r '.requests.blocked_epoch // empty' "$flow_cache" 2>/dev/null)

    flow_requests_part="💬 $(flow_pct_color "$req_pct_int")${req_pct_int}%${RESET}"
    if [ -n "$req_proj" ]; then
      req_proj_int=$(printf '%.0f' "$req_proj" 2>/dev/null || echo "$req_pct_int")
      flow_requests_part="${flow_requests_part}→$(flow_pct_color "$req_proj_int")${req_proj_int}%${RESET}"
    fi

    # Persona ilimitada: percentual/projeção são só referência (limite fictício
    # que nunca bloqueia de fato) — não faz sentido acender countdown de risco.
    if [ "$req_unlimited" != "true" ]; then
      if [ -n "$req_proj" ] || [ "$req_pct_int" -ge 100 ]; then
        flow_reset_needed=true
        flow_reset_epoch="$req_renewal_epoch"
      fi
      if [ "$FLOW_REQUESTS_BLOCKS" = "true" ] && [[ "$req_blocked_epoch" =~ ^[0-9]+$ ]]; then
        # Se budget e requests projetam bloqueio, mostra o mais urgente (o que
        # bloqueia primeiro é o que efetivamente vai te travar).
        if [[ ! "$flow_blocked_epoch" =~ ^[0-9]+$ ]] || [ "$req_blocked_epoch" -lt "$flow_blocked_epoch" ]; then
          flow_blocked_epoch="$req_blocked_epoch"
        fi
      fi
    fi

    [ "$req_unlimited" = "true" ] && flow_unlimited_part="${CYAN}∞${RESET}"
  fi
fi

countdown_part=""
[[ "${flow_blocked_epoch:-}" =~ ^[0-9]+$ ]] && countdown_part="${countdown_part}$(fmt_flow_blocked "$flow_blocked_epoch")"
[ "${flow_reset_needed:-false}" = "true" ] && countdown_part="${countdown_part}$(fmt_flow_reset "$flow_reset_epoch")"
countdown_part="${countdown_part# }"  # tira o espaço-líder do printf da 1ª chamada (vira separador "|" abaixo)

[ -n "$flow_budget_part" ] && line1="${line1} ${DIM}|${RESET} ${flow_budget_part}"
[ -n "$flow_requests_part" ] && line1="${line1} ${DIM}|${RESET} ${flow_requests_part}"
[ -n "$countdown_part" ] && line1="${line1} ${DIM}|${RESET} ${countdown_part}"
[ -n "$flow_unlimited_part" ] && line1="${line1} ${DIM}|${RESET} ${flow_unlimited_part}"

# ── Linha 2: progress + janela · sessão (contexto · rate · sprint) ──
line2="${ctx_part}"
[ -n "$rate_part" ] && line2="${line2} ${rate_part}"
[ -n "$sprint_part" ] && line2="${line2} ${DIM}|${RESET} ${sprint_part}"

printf '%b' "${line1}\n${line2}"
