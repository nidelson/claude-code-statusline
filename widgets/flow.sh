# Consumo da Flow Platform (CI&T).
#
# Este é o widget de provedor corporativo: quem passa por um gateway da empresa
# tem uma cota própria, com limite e renovação próprios, que não aparece em
# lugar nenhum do rate limit da Anthropic. Ela pertence à mesma linha que o
# resto.
#
# ── Dois segmentos, dois indicadores ──
#
# A API do Flow reporta duas cotas independentes: `budget`, em dinheiro, e
# `requests`, em chamadas. Estourar uma não diz nada sobre a outra — são
# perguntas diferentes, do mesmo jeito que as janelas de 5h e 7d do
# rate-forecast. Por isso os dois aparecem lado a lado, e a opção `metric` serve
# para filtrar, não para escolher.
#
# `requests` some quando a API marca `unlimited`. Percentual de um limite que não
# se aplica é um número que não decide nada, e ocuparia espaço permanente ao lado
# de um que decide.
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
  --desc   "CI&T Flow Platform budget and requests, with forecast"

SL_FLOW_DEFAULT_TTL=300
SL_FLOW_DEFAULT_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flow-consumption.json"

# A mesma escala serve ao uso e à projeção: um só vocabulário para o widget
# inteiro, e nenhum limiar novo para o usuário aprender.
SL_FLOW_WARN=80
SL_FLOW_CRIT=100

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

_flow_color() {
  if   [ "$1" -ge "$SL_FLOW_CRIT" ]; then sl_color red
  elif [ "$1" -ge "$SL_FLOW_WARN" ]; then sl_color yellow
  else                                    sl_color green
  fi
}

# Um segmento: rótulo, uso e — só quando há o que dizer — projeção. Retorna 1
# quando não há número utilizável, para que o chamador saiba não emitir
# separador.
_flow_segment() {
  local file="$1" metric="$2"
  local label raw used proj out ucolor pcolor

  case "$metric" in
    requests) label="req:"  ;;
    *)        label="flow:" ;;
  esac

  # Uma passada de jq devolve os dois números crus. Sai vazio — e o segmento
  # inteiro some — quando a busca falhou, quando a métrica não veio no payload,
  # ou quando ela é ilimitada.
  #
  # O jq entrega o valor como veio da API, sem arredondar. O arredondamento é o
  # de lib/num.sh, o mesmo que todos os outros percentuais usam.
  raw="$(jq -r --arg m "$metric" '
    if (.ok | not) then empty
    elif (.[$m] | not) then empty
    elif (.[$m].unlimited == true) then empty
    else "\(.[$m].percentage // 0) \(.[$m].projected_percentage // "-")"
    end' "$file" 2>/dev/null)" || return 1
  [ -n "$raw" ] || return 1

  # set -- divide na primeira palavra sem precisar de array.
  set -- $raw
  used="$(sl_round "$1")" || return 1
  # `-` é o sentinela de "sem projeção". Um `// 0` no jq transformaria um
  # projected_percentage nulo em `→0%` — uma projeção de zero por cento, que a
  # API nunca afirmou.
  if [ "$2" = "-" ]; then
    proj=""
  else
    proj="$(sl_round "$2")" || proj=""
  fi

  ucolor="$(_flow_color "$used")"
  out="${SL_DIM}${label}${SL_RESET}${ucolor}${used}%${SL_RESET}"

  # Projeção só aparece quando muda uma decisão. Um `→48%` verde ocupa espaço
  # permanente para dizer "siga em frente", que já era o estado padrão de quem
  # não vê aviso nenhum — e o olho que aprende a ignorá-la deixa de ver o dia em
  # que ela vira `→116%`.
  #
  # As chaves em ${out} são obrigatórias, não estilo: o bash 3.2 aceita bytes
  # acima de 127 como parte de nome de variável, então "$out→" é lido como a
  # variável `out\xE2` — que não existe, expande vazio e ainda come o primeiro
  # byte da seta, deixando lixo na saída.
  if [ -n "$proj" ] && [ "$proj" -ge "$SL_FLOW_WARN" ]; then
    pcolor="$(_flow_color "$proj")"
    out="${out}${pcolor}→${proj}%${SL_RESET}"
  fi

  printf '%s' "$out"
}

_flow_compute() {
  local file="$1" metric="$2" sep="$3" piece line=""

  if [ "$metric" != "requests" ]; then
    piece="$(_flow_segment "$file" budget)" && line="$piece"
  fi

  if [ "$metric" != "budget" ]; then
    if piece="$(_flow_segment "$file" requests)"; then
      # O separador só entra quando já há algo à esquerda: segmento ausente não
      # pode deixar pontuação órfã.
      if [ -n "$line" ]; then
        line="${line} ${SL_DIM}${sep}${SL_RESET} ${piece}"
      else
        line="$piece"
      fi
    fi
  fi

  printf '%s' "$line"
}

widget_flow_render() {
  local file metric sep ttl bin key

  file="$(sl_config_widget_opt flow cache "$SL_FLOW_DEFAULT_CACHE")"
  metric="$(sl_config_widget_opt flow metric)"
  sep="$(sl_config_widget_opt flow separator "·")"

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

  # As opções entram na chave: o cache guarda a linha pronta, e duas
  # configurações diferentes do mesmo JSON produzem linhas diferentes.
  key="flow-$(printf '%s' "$file|$metric|$sep" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$file" _flow_compute "$file" "$metric" "$sep"
}
