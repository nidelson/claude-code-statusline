#!/usr/bin/env bash
# flow-consumption — consulta consumo de budget (USD) e de requests da
# Flow Platform (CI&T) e grava em cache pro statusline ler. NUNCA chamado de
# forma síncrona pelo statusline (rede pode ser lenta) — é disparado em
# background e o statusline só lê o cache da rodada anterior. Self-contained:
# bash + curl + jq (sem depender de Python, exceto pra ISO→epoch).
#
# Autenticação: ANTHROPIC_AUTH_TOKEN é um JWT cujo payload traz clientSecret +
# tenant. Trocamos isso por um FlowToken de curta duração (auth-engine-api),
# cacheado até expirar (com margem de 60s), e usamos o FlowToken pra consultar
# o endpoint de consumo (metrics-collector-api). O mesmo endpoint, chamado com
# e sem "?mode=budget", retorna duas métricas independentes: budget em USD e
# contagem de requests — cada uma com seu próprio limite/percentual/reset.
#
# Uso: flow-consumption-line.sh (sem args — lê ANTHROPIC_AUTH_TOKEN do ambiente)

set -u

AUTH_ENGINE_URL="https://flow.ciandt.com/auth-engine-api/v2/api-key/token"
CONSUMPTION_URL="https://flow.ciandt.com/metrics-collector-api/rate-limit/me"
TIMEOUT_S=5
EXPIRY_MARGIN_S=60

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
TOKEN_CACHE="$CACHE_DIR/flow-token.json"
CONSUMPTION_CACHE="$CACHE_DIR/flow-consumption.json"
BUDGET_HISTORY_FILE="$CACHE_DIR/flow-budget-history.jsonl"
BUDGET_ANCHOR_FILE="$CACHE_DIR/flow-budget-cycle-anchor.json"
REQUESTS_HISTORY_FILE="$CACHE_DIR/flow-requests-history.jsonl"
REQUESTS_ANCHOR_FILE="$CACHE_DIR/flow-requests-cycle-anchor.json"
LOCK_DIR="$CACHE_DIR/flow-consumption.lock"
HISTORY_MAX_LINES=30
RECENT_WINDOW_S=1800
MIN_SAMPLE_GAP_S=600
# Idade mínima do CICLO (desde a âncora) antes de confiar em qualquer
# projeção. Sem isso, logo após o rollover mensal um burst de poucos minutos
# de uso já é extrapolado como se fosse o ritmo do mês inteiro, gerando
# projeções absurdas (ex.: 1000%+). Overridable via FLOW_MIN_CYCLE_AGE_S.
MIN_CYCLE_AGE_S="${FLOW_MIN_CYCLE_AGE_S:-86400}"

mkdir -p "$CACHE_DIR" 2>/dev/null

# mtime de um caminho, em epoch. `stat` não tem sintaxe comum entre as
# plataformas — mesmo problema e mesma solução de lib/cache.sh:_sl_mtime,
# reimplementado aqui porque este script é self-contained e não dá source em
# libs. `find -newermt` foi descartado: aceita "@epoch" no GNU find, mas o
# BSD find do macOS recusa esse formato ("Can't parse date/time"), e é
# exatamente a plataforma onde este script roda.
_lock_mtime() {
  local out
  out="$(stat -f %m "$1" 2>/dev/null)"
  case "$out" in
    ''|*[!0-9]*) out="$(stat -c %Y "$1" 2>/dev/null)" ;;
  esac
  case "$out" in
    ''|*[!0-9]*) printf '0' ;;
    *)           printf '%s' "$out" ;;
  esac
}

# Descarte de lock órfão, antes de tentar o lock de verdade logo abaixo.
#
# Um lock nunca solto trava toda atualização futura para sempre: se o processo
# em background morrer antes do `trap EXIT` rodar — pai encerrado, kill -9 —
# `mkdir` abaixo falha a cada TTL, sem erro nenhum, e o widget congela no
# último dado bom. STALE_LOCK_S é a defesa: um lock mais velho do que o pior
# caminho legítimo (até três chamadas de rede em série, TIMEOUT_S cada, mais
# folga) não pode ser de uma consulta ainda em voo, e é seguro descartar.
# mtime ilegível (`0`) não decide nada: degrada para "lock não é stale",
# igual a lib/cache.sh faz com carimbo não numérico.
STALE_LOCK_S=60
if [ -d "$LOCK_DIR" ]; then
  lock_mtime="$(_lock_mtime "$LOCK_DIR")"
  if [ "$lock_mtime" != "0" ] && [ $(( $(date +%s) - lock_mtime )) -ge "$STALE_LOCK_S" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
fi

# Lock via mkdir (atômico): se já tem uma consulta em voo, essa instância desiste.
mkdir "$LOCK_DIR" 2>/dev/null || exit 0
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# Registra a falha SEM apagar a última leitura boa.
#
# Antes, qualquer erro — token ausente, rede fora, gateway de mau humor —
# gravava `{ok:false}` por cima do payload inteiro, e a statusline perdia o
# número que já tinha. Uma sessão sem ANTHROPIC_AUTH_TOKEN zerava o widget a
# cada TTL. Um número de dois minutos atrás é verdadeiro; nenhum número não é
# mais honesto que ele, é só menos útil.
#
# Agora a falha vira um campo `error` ao lado dos dados preservados. `ok`
# continua true porque os dados seguem válidos — o que falhou foi a
# atualização, não a leitura. `fetched_at` fica onde estava, marcando a idade
# real do dado; `error.at` marca a tentativa.
#
# Sem leitura boa anterior — primeira execução numa máquina sem acesso — cai no
# formato antigo, e aí o widget mostra só o aviso.
write_error() {
  local msg="$1" now prev
  now="$(date +%s)"

  # `del(.error)` impede que erros sucessivos se empilhem; o `at` novo
  # sobrescreve o antigo, e `fetched_at` não é tocado em nenhum dos dois casos.
  if [ -s "$CONSUMPTION_CACHE" ] &&
     prev="$(jq -e 'select(.ok == true) | del(.error)' "$CONSUMPTION_CACHE" 2>/dev/null)"; then
    # Arquivo temporário e mv: o widget pode estar lendo este arquivo agora, e
    # um redirecionamento direto o exporia truncado.
    if printf '%s' "$prev" | jq --arg msg "$msg" --argjson at "$now" \
         '. + {error: {message: $msg, at: $at}}' > "$CONSUMPTION_CACHE.tmp" 2>/dev/null; then
      mv -f "$CONSUMPTION_CACHE.tmp" "$CONSUMPTION_CACHE" 2>/dev/null
    fi
    rm -f "$CONSUMPTION_CACHE.tmp" 2>/dev/null
  else
    jq -n --arg msg "$msg" --argjson fetched_at "$now" \
      '{ok: false, message: $msg, fetched_at: $fetched_at}' > "$CONSUMPTION_CACHE" 2>/dev/null
  fi

  chmod 600 "$CONSUMPTION_CACHE" 2>/dev/null
}

# ISO 8601 → epoch (mesmo padrão usado no statusline.sh pros resets de rate-limit)
iso_to_epoch() {
  python3 -c 'import sys,datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "$1" 2>/dev/null
}

# Grava uma amostra {t, v} no histórico do ciclo atual; detecta rollover
# (v novo menor que o último registrado = resetou no início do mês) e trunca
# o histórico nesse caso. Mantém só as últimas HISTORY_MAX_LINES — serve só
# pro cálculo da taxa RECENTE (últimos ~30min).
# args: hist_file anchor_file now value
record_history_sample() {
  local hist="$1" anchor="$2" now="$3" value="$4"
  local last_value=""
  local rollover=0
  if [ -f "$hist" ] && [ -s "$hist" ]; then
    last_value=$(tail -n1 "$hist" | jq -r '.v // empty' 2>/dev/null)
  fi
  if [ -n "$last_value" ] && awk -v a="$value" -v b="$last_value" 'BEGIN{exit !(a+0 < b+0)}'; then
    rollover=1
  fi
  [ "$rollover" -eq 1 ] && : > "$hist"
  jq -nc --argjson t "$now" --argjson v "$value" '{t: $t, v: $v}' >> "$hist" 2>/dev/null
  tail -n "$HISTORY_MAX_LINES" "$hist" > "${hist}.tmp" 2>/dev/null && mv "${hist}.tmp" "$hist"
  chmod 600 "$hist" 2>/dev/null

  # Âncora do ciclo: ponto fixo (NUNCA podado) usado pra medir o ritmo médio
  # desde o início real do mês. O histórico acima é limitado a
  # HISTORY_MAX_LINES amostras — em uso intenso isso pode cobrir só algumas
  # horas, não o mês inteiro, então sozinho não serve pra taxa "cheia".
  if [ "$rollover" -eq 1 ] || [ ! -f "$anchor" ]; then
    jq -nc --argjson t "$now" --argjson v "$value" '{t: $t, v: $v}' > "$anchor" 2>/dev/null
    chmod 600 "$anchor" 2>/dev/null
  fi
}

# Taxa RECENTE (unidade/dia): entre a amostra mais antiga dentro da janela de
# "age_filter" segundos e a mais nova. Exige intervalo mínimo de
# MIN_SAMPLE_GAP_S pra não virar ruído.
# args: hist_file now age_filter
compute_rate() {
  local hist="$1" now="$2" age_filter="$3"
  [ -f "$hist" ] || { echo ""; return; }
  local oldest
  oldest=$(jq -s --argjson now "$now" --argjson age "$age_filter" '
    map(select(($now - .t) <= $age)) | sort_by(.t) | .[0] // empty
  ' "$hist" 2>/dev/null)
  local newest
  newest=$(jq -s 'sort_by(.t) | .[-1] // empty' "$hist" 2>/dev/null)
  [ -z "$oldest" ] || [ -z "$newest" ] && { echo ""; return; }
  [ "$oldest" = "null" ] || [ "$newest" = "null" ] && { echo ""; return; }
  local ot ov nt nv
  ot=$(echo "$oldest" | jq -r '.t'); ov=$(echo "$oldest" | jq -r '.v')
  nt=$(echo "$newest" | jq -r '.t'); nv=$(echo "$newest" | jq -r '.v')
  local gap=$(( nt - ot ))
  if [ "$gap" -lt "$MIN_SAMPLE_GAP_S" ]; then echo ""; return; fi
  awk -v ov="$ov" -v nv="$nv" -v gap="$gap" 'BEGIN { printf "%.6f", (nv - ov) / (gap / 86400) }'
}

# Taxa CHEIA (unidade/dia): desde a âncora do ciclo (ponto fixo) até agora —
# cobre o mês real, ao contrário do histórico podado usado em compute_rate.
# args: anchor_file now value
compute_rate_full() {
  local anchor="$1" now="$2" value="$3"
  [ -f "$anchor" ] || { echo ""; return; }
  local at av
  at=$(jq -r '.t // empty' "$anchor" 2>/dev/null)
  av=$(jq -r '.v // empty' "$anchor" 2>/dev/null)
  [ -z "$at" ] || [ -z "$av" ] && { echo ""; return; }
  local gap=$(( now - at ))
  if [ "$gap" -lt "$MIN_SAMPLE_GAP_S" ]; then echo ""; return; fi
  awk -v ov="$av" -v nv="$value" -v gap="$gap" 'BEGIN { printf "%.6f", (nv - ov) / (gap / 86400) }'
}

classify_threshold() {
  awk -v p="$1" 'BEGIN {
    if (p+0 >= 100) print "blocked_100";
    else if (p+0 >= 95) print "critical_95";
    else if (p+0 >= 80) print "warning_80";
    else print "normal";
  }'
}

# Projeta o percentual do limite na data de renovação, combinando taxa
# recente (últimos RECENT_WINDOW_S) e taxa cheia (desde a âncora do ciclo) —
# usa o pior caso entre as duas, evitando que um pico recente seja mascarado
# pela média ou vice-versa. Grava a amostra atual no histórico antes de
# calcular. Só retorna valor quando a projeção já indica risco (>=80%) —
# abaixo disso o usuário não precisa do aviso, evita poluir a linha à toa.
# Quando a projeção passa de 100% (vai estourar o limite antes da renovação),
# também calcula o epoch em que isso deve acontecer, na taxa atual.
# Saída: "proj_pct blocked_epoch" (blocked_epoch vazio se não houver risco de
# bloqueio antes do reset); string vazia se não há projeção a reportar.
# args: hist_file anchor_file now value limit renewal_epoch
compute_projection() {
  local hist="$1" anchor="$2" now="$3" value="$4" limit="$5" renewal_epoch="$6"
  record_history_sample "$hist" "$anchor" "$now" "$value"

  [ "$renewal_epoch" = "null" ] && { echo ""; return; }
  awk -v l="$limit" 'BEGIN{exit !(l+0 > 0)}' || { echo ""; return; }

  # Ciclo ainda muito novo (logo após o rollover mensal): não há dados
  # suficientes pra extrapolar com confiança, então não projeta nada ainda.
  local anchor_t
  anchor_t=$(jq -r '.t // empty' "$anchor" 2>/dev/null)
  if [ -n "$anchor_t" ] && [ $(( now - anchor_t )) -lt "$MIN_CYCLE_AGE_S" ]; then
    echo ""
    return
  fi

  local rate_recent rate_full effective_rate
  rate_recent=$(compute_rate "$hist" "$now" "$RECENT_WINDOW_S")
  rate_full=$(compute_rate_full "$anchor" "$now" "$value")
  effective_rate=""
  if [ -n "$rate_recent" ] && [ -n "$rate_full" ]; then
    effective_rate=$(awk -v r="$rate_recent" -v f="$rate_full" 'BEGIN { print (r+0 > f+0) ? r : f }')
  elif [ -n "$rate_recent" ]; then
    effective_rate="$rate_recent"
  elif [ -n "$rate_full" ]; then
    effective_rate="$rate_full"
  fi
  [ -z "$effective_rate" ] && { echo ""; return; }

  local days_to_renewal proj_pct
  days_to_renewal=$(awk -v re="$renewal_epoch" -v now="$now" 'BEGIN { d = (re - now) / 86400; print (d > 0) ? d : 0 }')
  proj_pct=$(awk -v v="$value" -v rate="$effective_rate" -v days="$days_to_renewal" -v limit="$limit" \
    'BEGIN { printf "%.2f", (v + rate * days) / limit * 100 }')

  if ! awk -v p="$proj_pct" 'BEGIN{exit !(p+0 >= 80)}'; then
    echo ""
    return
  fi

  local blocked_epoch=""
  if awk -v p="$proj_pct" 'BEGIN{exit !(p+0 > 100)}'; then
    blocked_epoch=$(awk -v v="$value" -v rate="$effective_rate" -v limit="$limit" -v now="$now" 'BEGIN {
      if (rate+0 <= 0) { print ""; exit }
      days = (limit - v) / rate; if (days < 0) days = 0;
      printf "%d", now + days * 86400
    }')
  fi

  printf '%s %s\n' "$proj_pct" "$blocked_epoch"
}

b64url_decode() {
  local input="$1"
  local rem=$(( ${#input} % 4 ))
  if [ "$rem" -eq 2 ]; then input="${input}=="
  elif [ "$rem" -eq 3 ]; then input="${input}="
  fi
  printf '%s' "$input" | tr '_-' '/+' | base64 -d 2>/dev/null
}

AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-}"
if [ -z "$AUTH_TOKEN" ]; then
  write_error "ANTHROPIC_AUTH_TOKEN não encontrado"
  exit 1
fi

payload_b64=$(printf '%s' "$AUTH_TOKEN" | cut -d. -f2)
payload_json=$(b64url_decode "$payload_b64")
if [ -z "$payload_json" ]; then
  write_error "Falha ao decodificar payload do ANTHROPIC_AUTH_TOKEN"
  exit 1
fi

client_secret=$(printf '%s' "$payload_json" | jq -r '.clientSecret // empty' 2>/dev/null)
tenant=$(printf '%s' "$payload_json" | jq -r '.tenant // empty' 2>/dev/null)

if [ -z "$client_secret" ]; then
  write_error "clientSecret ausente no ANTHROPIC_AUTH_TOKEN"
  exit 1
fi
if [ -z "$tenant" ]; then
  write_error "tenant ausente no ANTHROPIC_AUTH_TOKEN"
  exit 1
fi

# Hash do clientSecret só pra invalidar o cache de token se o usuário trocar de
# credencial (rotação) — nunca grava o secret em si no cache.
cache_key=$(printf '%s' "$client_secret" | shasum -a 256 | cut -d' ' -f1)

flow_token=""
if [ -f "$TOKEN_CACHE" ]; then
  cached_key=$(jq -r '.key // empty' "$TOKEN_CACHE" 2>/dev/null)
  if [ "$cached_key" = "$cache_key" ]; then
    expires_at=$(jq -r '.expires_at // 0' "$TOKEN_CACHE" 2>/dev/null)
    expires_at_int=${expires_at%.*}
    [ -z "$expires_at_int" ] && expires_at_int=0
    remaining=$(( expires_at_int - $(date +%s) ))
    if [ "$remaining" -gt "$EXPIRY_MARGIN_S" ]; then
      flow_token=$(jq -r '.access_token // empty' "$TOKEN_CACHE" 2>/dev/null)
    fi
  fi
fi

if [ -z "$flow_token" ]; then
  auth_body=$(jq -n --arg cs "$client_secret" '{clientSecret: $cs}')
  auth_resp=$(curl -sS --max-time "$TIMEOUT_S" -X POST "$AUTH_ENGINE_URL" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -H "FlowTenant: $tenant" \
    -d "$auth_body" \
    -w $'\n%{http_code}' 2>/dev/null)
  auth_http_code=$(printf '%s' "$auth_resp" | tail -n1)
  auth_json=$(printf '%s' "$auth_resp" | sed '$d')

  if [ "$auth_http_code" != "200" ]; then
    write_error "HTTP ${auth_http_code:-000} no auth-engine"
    exit 1
  fi

  flow_token=$(printf '%s' "$auth_json" | jq -r '.access_token // empty' 2>/dev/null)
  expires_in=$(printf '%s' "$auth_json" | jq -r '.expires_in // 3600' 2>/dev/null)
  if [ -z "$flow_token" ]; then
    write_error "auth-engine não retornou access_token"
    exit 1
  fi

  token_expires_at=$(( $(date +%s) + ${expires_in%.*} ))
  jq -n --arg key "$cache_key" --arg token "$flow_token" --argjson expires_at "$token_expires_at" \
    '{key: $key, access_token: $token, expires_at: $expires_at}' > "$TOKEN_CACHE" 2>/dev/null
  chmod 600 "$TOKEN_CACHE" 2>/dev/null
fi

# ── Budget (USD) ──
budget_resp=$(curl -sS --max-time "$TIMEOUT_S" "${CONSUMPTION_URL}?mode=budget" \
  -H "accept: application/json" \
  -H "FlowToken: $flow_token" \
  -w $'\n%{http_code}' 2>/dev/null)
budget_http_code=$(printf '%s' "$budget_resp" | tail -n1)
budget_json=$(printf '%s' "$budget_resp" | sed '$d')

if [ "$budget_http_code" != "200" ]; then
  write_error "HTTP ${budget_http_code:-000} em /rate-limit/me?mode=budget"
  exit 1
fi

# ── Requests (contagem) ──
requests_resp=$(curl -sS --max-time "$TIMEOUT_S" "$CONSUMPTION_URL" \
  -H "accept: application/json" \
  -H "FlowToken: $flow_token" \
  -w $'\n%{http_code}' 2>/dev/null)
requests_http_code=$(printf '%s' "$requests_resp" | tail -n1)
requests_json=$(printf '%s' "$requests_resp" | sed '$d')

if [ "$requests_http_code" != "200" ]; then
  write_error "HTTP ${requests_http_code:-000} em /rate-limit/me"
  exit 1
fi

now=$(date +%s)

# ── Processa budget ──
b_percentage=$(printf '%s' "$budget_json" | jq -r '.percentage // 0' 2>/dev/null)
b_status=$(printf '%s' "$budget_json" | jq -r '.status // ""' 2>/dev/null)
b_renewal_date=$(printf '%s' "$budget_json" | jq -r '.renewal_date // ""' 2>/dev/null)
b_limit=$(printf '%s' "$budget_json" | jq -r '.limit // 0' 2>/dev/null)
b_consumed_usd=$(printf '%s' "$budget_json" | jq -r '.consumed_usd // 0' 2>/dev/null)
b_threshold=$(classify_threshold "$b_percentage")

b_renewal_epoch="null"
if [ -n "$b_renewal_date" ]; then
  re=$(iso_to_epoch "$b_renewal_date")
  [[ "$re" =~ ^[0-9]+$ ]] && b_renewal_epoch="$re"
fi

b_projected="null"
b_blocked_epoch="null"
proj_out=$(compute_projection "$BUDGET_HISTORY_FILE" "$BUDGET_ANCHOR_FILE" "$now" "$b_consumed_usd" "$b_limit" "$b_renewal_epoch")
if [ -n "$proj_out" ]; then
  b_projected=$(printf '%s' "$proj_out" | awk '{print $1}')
  proj_blocked=$(printf '%s' "$proj_out" | awk '{print $2}')
  [[ "$proj_blocked" =~ ^[0-9]+$ ]] && b_blocked_epoch="$proj_blocked"
fi

# ── Processa requests ──
r_status=$(printf '%s' "$requests_json" | jq -r '.status // ""' 2>/dev/null)
r_renewal_date=$(printf '%s' "$requests_json" | jq -r '.renewal_date // ""' 2>/dev/null)
r_limit=$(printf '%s' "$requests_json" | jq -r '.limit // 0' 2>/dev/null)
r_requests_used=$(printf '%s' "$requests_json" | jq -r '.requests_used // 0' 2>/dev/null)

# Usuário NO_LIMIT: a API retorna limit=0/percentage=0 (não calcula %). Usamos
# um limite de referência configurável (nunca bloqueia, só dá ciência do
# consumo) pra exibir percentual/projeção como os demais usuários.
r_unlimited=false
if [ "$r_limit" = "0" ]; then
  r_unlimited=true
  r_limit="${FLOW_REQUESTS_LIMIT:-5000}"
fi
r_percentage=$(awk -v u="$r_requests_used" -v l="$r_limit" 'BEGIN { printf "%.2f", (l+0 > 0) ? (u / l * 100) : 0 }')
r_threshold=$(classify_threshold "$r_percentage")

r_renewal_epoch="null"
if [ -n "$r_renewal_date" ]; then
  re=$(iso_to_epoch "$r_renewal_date")
  [[ "$re" =~ ^[0-9]+$ ]] && r_renewal_epoch="$re"
fi

r_projected="null"
r_blocked_epoch="null"
proj_out=$(compute_projection "$REQUESTS_HISTORY_FILE" "$REQUESTS_ANCHOR_FILE" "$now" "$r_requests_used" "$r_limit" "$r_renewal_epoch")
if [ -n "$proj_out" ]; then
  r_projected=$(printf '%s' "$proj_out" | awk '{print $1}')
  # NO_LIMIT usa um teto de referência que nunca bloqueia de fato — não faz
  # sentido projetar "bloqueio" nesse caso.
  if [ "$r_unlimited" != "true" ]; then
    proj_blocked=$(printf '%s' "$proj_out" | awk '{print $2}')
    [[ "$proj_blocked" =~ ^[0-9]+$ ]] && r_blocked_epoch="$proj_blocked"
  fi
fi

jq -n \
  --argjson fetched_at "$now" \
  --argjson b_percentage "$b_percentage" --arg b_threshold "$b_threshold" --arg b_status "$b_status" \
  --arg b_renewal_date "$b_renewal_date" --argjson b_limit "$b_limit" --argjson b_consumed_usd "$b_consumed_usd" \
  --argjson b_renewal_epoch "$b_renewal_epoch" --argjson b_projected "$b_projected" --argjson b_blocked_epoch "$b_blocked_epoch" \
  --argjson r_percentage "$r_percentage" --arg r_threshold "$r_threshold" --arg r_status "$r_status" \
  --arg r_renewal_date "$r_renewal_date" --argjson r_limit "$r_limit" --argjson r_requests_used "$r_requests_used" \
  --argjson r_renewal_epoch "$r_renewal_epoch" --argjson r_projected "$r_projected" --argjson r_unlimited "$r_unlimited" \
  --argjson r_blocked_epoch "$r_blocked_epoch" \
  '{
    ok: true, fetched_at: $fetched_at,
    budget: {
      percentage: $b_percentage, threshold: $b_threshold, status: $b_status,
      renewal_date: $b_renewal_date, budget_limit: $b_limit, consumed_usd: $b_consumed_usd,
      renewal_epoch: $b_renewal_epoch, projected_percentage: $b_projected, blocked_epoch: $b_blocked_epoch
    },
    requests: {
      percentage: $r_percentage, threshold: $r_threshold, status: $r_status,
      renewal_date: $r_renewal_date, limit: $r_limit, requests_used: $r_requests_used,
      renewal_epoch: $r_renewal_epoch, projected_percentage: $r_projected, unlimited: $r_unlimited,
      blocked_epoch: $r_blocked_epoch
    }
  }' > "$CONSUMPTION_CACHE" 2>/dev/null
chmod 600 "$CONSUMPTION_CACHE" 2>/dev/null
