# Consumo da Flow Platform (CI&T).
#
# Este é o widget de provedor corporativo: quem passa por um gateway da empresa
# tem uma cota própria, com limite e renovação próprios, que não aparece em
# lugar nenhum do rate limit da Anthropic. Ela pertence à mesma linha que o
# resto.
#
# ── Buscar e mostrar são coisas separadas ──
#
# bin/flow-consumption.sh fala com a rede e grava JSON em cache. Este widget só
# lê esse JSON. A separação não é organização, é requisito: uma chamada de rede
# no caminho de renderização faria a statusline inteira esperar pela latência do
# gateway, a cada repaint.
#
# Daí os dois relógios:
#
#   render   invalidado pelo mtime do JSON — o número novo aparece no instante
#            em que a busca termina, sem esperar TTL nenhum
#   refresh  limitado por um arquivo marcador, para não martelar a API
#
# Um TTL único para os dois obrigaria a escolher entre mostrar dado velho e
# buscar demais.
#
# ── Sem token, sem ruído ──
#
# O fetcher precisa de ANTHROPIC_AUTH_TOKEN no ambiente. Sem ele grava
# {"ok": false}, e o widget simplesmente não renderiza. Máquina sem acesso ao
# Flow não vê erro nenhum — vê a statusline sem esse pedaço.

register_widget flow \
  --render widget_flow_render \
  --self-color \
  --desc   "CI&T Flow Platform consumption with forecast"

SL_FLOW_DEFAULT_TTL=300
SL_FLOW_DEFAULT_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flow-consumption.json"

_flow_fetcher() {
  local configured
  configured="$(sl_config_widget_opt flow bin)"
  if [ -n "$configured" ]; then
    printf '%s' "$configured"
  else
    printf '%s' "${SL_ROOT:-$HOME/.claude}/bin/flow-consumption.sh"
  fi
}

# Dispara a busca em segundo plano, no máximo uma vez por TTL.
_flow_maybe_refresh() {
  local ttl="$1" bin="$2" marker now last

  [ -n "$bin" ] || return 0
  [ -f "$bin" ] || return 0

  marker="$SL_CACHE_DIR/flow-refresh.stamp"
  now="$(date +%s)"
  last=0
  if [ -f "$marker" ]; then
    # O `|| :` não é decorativo: `read` devolve não-zero ao encontrar EOF sem
    # quebra de linha, mesmo tendo preenchido a variável. Sob um chamador com
    # `set -e` isso abortaria a função inteira.
    IFS= read -r last < "$marker" || :
    case "$last" in ""|*[!0-9]*) last=0 ;; esac
  fi

  [ $(( now - last )) -ge "$ttl" ] || return 0

  # Grava o marcador ANTES de disparar. Se gravasse depois, dois repaints quase
  # simultâneos disparariam duas buscas.
  mkdir -p "$SL_CACHE_DIR" 2>/dev/null
  printf '%s\n' "$now" > "$marker" 2>/dev/null

  # Os redirecionamentos são obrigatórios: um filho que herde o pipe da
  # substituição de comando o mantém aberto, e a renderização esperaria pela
  # rede — exatamente o que este arranjo existe para evitar.
  ( bash "$bin" >/dev/null 2>&1 </dev/null & ) >/dev/null 2>&1
}

_flow_compute() {
  local file="$1" metric="$2" label used proj color

  case "$metric" in
    requests) label="req:" ;;
    *)        label="flow:"; metric=budget ;;
  esac

  # Uma passada de jq devolve os dois números crus; vazio quando ok é falso.
  #
  # O jq entrega o valor como veio da API, sem arredondar. Antes ele aplicava
  # `floor`, e 24,9% aparecia como `24%` enquanto o widget vizinho, com a mesma
  # fração, mostrava `25%`. O arredondamento agora é o de lib/num.sh, o mesmo
  # que todos os outros percentuais usam.
  used="$(jq -r --arg m "$metric" '
    if (.ok | not) then empty
    else "\(.[$m].percentage // 0) \(.[$m].projected_percentage // "-")"
    end' "$file" 2>/dev/null)" || return 0
  [ -n "$used" ] || return 0

  set -- $used
  used="$(sl_round "$1")" || return 0
  # `-` é o sentinela de "sem projeção". Antes era `// 0`, que transformava um
  # projected_percentage nulo em `→0%` — uma projeção de zero por cento, que a
  # API nunca afirmou. A métrica `requests` chega assim quando é ilimitada.
  if [ "$2" = "-" ]; then
    proj=""
  else
    proj="$(sl_round "$2")" || proj=""
  fi

  if [ -n "$proj" ] && [ "$proj" -ge 100 ]; then
    color="$(sl_color red)"
  elif [ -n "$proj" ] && [ "$proj" -ge 80 ]; then
    color="$(sl_color yellow)"
  else
    color="$(sl_color green)"
  fi

  if [ -n "$proj" ]; then
    printf '%s%s%s%%→%s%%%s' "$color" "$label" "$used" "$proj" "$SL_RESET"
  else
    printf '%s%s%s%%%s' "$color" "$label" "$used" "$SL_RESET"
  fi
}

widget_flow_render() {
  local file metric ttl bin key

  file="$(sl_config_widget_opt flow cache "$SL_FLOW_DEFAULT_CACHE")"
  metric="$(sl_config_widget_opt flow metric budget)"

  ttl="$(sl_config_widget_opt flow ttl "$SL_FLOW_DEFAULT_TTL")"
  case "$ttl" in
    ""|*[!0-9]*) ttl="$SL_FLOW_DEFAULT_TTL" ;;
  esac

  if [ "$(sl_config_widget_opt flow refresh true)" != "false" ]; then
    bin="$(_flow_fetcher)"
    _flow_maybe_refresh "$ttl" "$bin"
  fi

  # Ainda sem a primeira busca concluída: nada a mostrar, e não é erro.
  [ -f "$file" ] || return 0

  key="flow-$(printf '%s' "$file$metric" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$file" _flow_compute "$file" "$metric"
}
