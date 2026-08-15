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
# Os emoji dizem qual cota é qual, mas não de onde ela vem. Numa linha que já
# mistura custo de sessão e limite de plano, `💰 24%` é ambíguo até a pessoa
# aprender a associá-lo ao provedor — e quem instala o plugin hoje não tem essa
# associação pronta. O rótulo a entrega de graça; `"label": ""` a dispensa
# quando ela virar redundante.
SL_FLOW_DEFAULT_LABEL="Flow"

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

# Rótulo do segmento. Com ícones, dois emoji; sem eles, as palavras inteiras.
#
# `budget:` e `requests:` são mais longos que os `flow:`/`req:` de antes, e é de
# propósito: quem desliga os ícones normalmente o faz por causa do terminal, não
# por falta de espaço, e a palavra inteira não exige que ninguém adivinhe o que
# `req` abrevia.
#
# Os emoji ignoram o SL_DIM — cor de emoji é fixa. O esmaecimento fica no
# caminho de texto, onde funciona; envolver os dois do mesmo jeito mantém o
# chamador sem casos especiais.
_flow_label() {
  if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then
    case "$1" in
      requests) printf '%s' '💬 ' ;;
      *)        printf '%s' '💰 ' ;;
    esac
  else
    case "$1" in
      requests) printf '%s' 'requests:' ;;
      *)        printf '%s' 'budget:'   ;;
    esac
  fi
}

_flow_color() {
  if   [ "$1" -ge "$SL_FLOW_CRIT" ]; then sl_color red
  elif [ "$1" -ge "$SL_FLOW_WARN" ]; then sl_color yellow
  else                                    sl_color green
  fi
}

# Tempo é entrada, não relógio — mesma razão de widgets/rate-forecast.sh: sem
# isso a suíte passaria a depender do dia em que roda.
_flow_now() {
  if [ -n "$SL_NOW" ]; then
    printf '%s' "$SL_NOW"
  else
    date +%s
  fi
}

# `⟳ <data>·<regressiva>` esmaecido, a partir do epoch cru. Retorna 1 quando o
# epoch não veio, é ilegível ou já passou — uma renovação que não dá para
# formatar apaga só a si mesma.
#
# O espaço depois do glifo não é folga: `⟳` tem largura ambígua em Unicode, e
# colado a um `3` ele disputa a mesma célula em boa parte dos terminais. Os
# outros glifos deste widget já carregam o espaço junto ('💰 ', '💬 '), então
# aqui ele é a regra, não a exceção. Com `icons: false` o glifo some inteiro, e
# o espaço com ele.
_flow_renewal_label() {
  local epoch="$1" mark="" label
  [ "$epoch" != "-" ] || return 1
  [ "${SL_CONFIG_ICONS:-1}" = "1" ] && mark="⟳ "
  label="$(sl_stamp_label "$mark" "$epoch" "$(_flow_now)")" || return 1
  printf '%s' "${SL_DIM}${label}${SL_RESET}"
}

# `🔒 <data>·<regressiva>` em vermelho, quando o ritmo atual leva a cota a
# estourar antes de renovar. O fetcher só grava `blocked_epoch` quando a projeção
# passa de 100%, então a presença do campo já é a condição.
#
# O 🔒 sai dourado mesmo dentro do vermelho, porque emoji ignora ANSI. Quem
# carrega a cor é a data — mesmo arranjo do `⚠`, pelo mesmo motivo. Sem ícones a
# palavra `blocked:` distingue os dois carimbos, que de outro modo seriam duas
# datas anônimas lado a lado.
_flow_blocked_label() {
  local epoch="$1" mark label
  [ "$epoch" != "-" ] || return 1
  if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then mark="🔒 "; else mark="blocked:"; fi
  label="$(sl_stamp_label "$mark" "$epoch" "$(_flow_now)")" || return 1
  printf '%s' "$(sl_color red)${label}${SL_RESET}"
}

# Uma passada de jq responde às duas perguntas de layout, antes de qualquer
# segmento ser desenhado: as duas cotas renovam juntas, e qual delas está
# pedindo atenção.
#
# Saída: "<renov_budget> <renov_requests> <alerta_budget> <alerta_requests>",
# com `-` para renovação ausente e 0/1 para o alerta. Payload ilegível responde
# "nada e ninguém" em vez de falhar, porque a decisão de layout não pode derrubar
# a linha inteira.
#
# Alerta é "há algo amarelo ou vermelho neste segmento": uso acima do limiar, ou
# projeção acima dele — que é exatamente a condição para a projeção aparecer. O
# `round` do jq empata com o `%.0f` de sl_round em todo valor que decide o
# limiar, então os dois lados concordam sobre quem está em alerta.
_flow_layout() {
  local file="$1" warn="$2"
  jq -r --argjson warn "$warn" '
    def alert($m):
      if ((.[$m].percentage // 0 | round) >= $warn
          or (.[$m].projected_percentage // 0 | round) >= $warn)
      then "1" else "0" end;
    if (.ok | not) then "- - 0 0"
    else "\(.budget.renewal_epoch // "-") \(.requests.renewal_epoch // "-") \(alert("budget")) \(alert("requests"))"
    end' "$file" 2>/dev/null || printf '%s' '- - 0 0'
}

# Um segmento: rótulo, uso e — só quando há o que dizer — projeção e renovação.
# Retorna 1 quando não há número utilizável, para que o chamador saiba não
# emitir separador.
#
# `skip_renewal` não-vazio significa que o chamador já vai mostrar essa data em
# outro lugar.
_flow_segment() {
  local file="$1" metric="$2" skip_renewal="$3"
  local label raw used proj renewal blocked out ucolor pcolor rlabel blabel

  label="$(_flow_label "$metric")"

  # Uma passada de jq devolve os dois números crus. Sai vazio — e o segmento
  # inteiro some — quando a busca falhou ou quando a métrica não veio no
  # payload.
  #
  # Cota ilimitada NÃO some: a API manda `unlimited: true` junto com limite,
  # contagem e percentual, e esconder tudo isso jogava fora dado verdadeiro. O
  # fato de não haver teto é dito pelo `∞` do segmento de status, ao lado.
  #
  # O jq entrega o valor como veio da API, sem arredondar. O arredondamento é o
  # de lib/num.sh, o mesmo que todos os outros percentuais usam.
  raw="$(sl_jq -r --arg m "$metric" '
    if (.ok | not) then empty
    elif (.[$m] | not) then empty
    else "\(.[$m].percentage // 0) \(.[$m].projected_percentage // "-") \(.[$m].renewal_epoch // "-") \(.[$m].blocked_epoch // "-")"
    end' "$file" 2>/dev/null)" || return 1
  [ -n "$raw" ] || return 1

  # set -- divide na primeira palavra sem precisar de array. Os posicionais são
  # copiados de uma vez porque o que vem depois chama funções em substituição de
  # comando, e ler `$3` no meio disso é mais frágil do que precisa ser.
  set -- $raw
  # `-` é o sentinela de "não veio no payload". Um `// 0` no jq transformaria um
  # projected_percentage nulo em `→0%` — uma projeção de zero por cento, que a
  # API nunca afirmou — e um renewal_epoch nulo na data de 1970.
  proj="$2"
  renewal="$3"
  blocked="$4"

  used="$(sl_round "$1")" || return 1
  if [ "$proj" = "-" ]; then
    proj=""
  else
    proj="$(sl_round "$proj")" || proj=""
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

  # O bloqueio vem antes da renovação porque é a data que chega primeiro. Lidos
  # na ordem, os dois carimbos contam a história inteira: "trava sexta, renova
  # domingo" — e a folga entre eles é o que decide se dá para seguir no ritmo.
  #
  # Ele não obedece a `renewal`: são perguntas diferentes. Quem desliga a data de
  # renovação está dizendo que não precisa saber quando o ciclo vira, não que
  # aceita ser bloqueado sem aviso.
  blabel="$(_flow_blocked_label "$blocked")" && out="${out} ${blabel}"

  # A renovação vem logo depois do percentual porque é o que dá escala a ele: um
  # `24%` não diz se sobra um dia ou três semanas para gastar o resto, e é essa
  # distância que decide se dá para manter o ritmo. Mesmo `⟳` e mesmo formato do
  # rate-forecast — a pergunta é a mesma, então a resposta se parece.
  if [ -z "$skip_renewal" ] &&
     [ "$(sl_config_widget_opt flow renewal true)" != "false" ]; then
    rlabel="$(_flow_renewal_label "$renewal")" && out="${out} ${rlabel}"
  fi

  printf '%s' "$out"
}

# Terceiro segmento: o que não é número.
#
# Dois estados, e nenhum deles cabe num percentual:
#
#   ∞  a cota de requests não tem teto. Fato calmo, então esmaecido: ele explica
#      por que o percentual ao lado não vai bloquear ninguém, e não pede reação.
#   ⚠  a última busca falhou. Vermelho, porque pede.
#
# O ⚠ é monocromático de propósito. Emoji têm cor própria e ignoram ANSI: não
# existe wifi vermelho em emoji, e um aviso que não consegue ficar vermelho não
# é aviso.
#
# Quando os dois aparecem juntos, os números ao lado são a última leitura boa —
# o fetcher preserva o payload e só marca a falha. `⚠` significa "não consegui
# atualizar", não "não sei de nada".
_flow_status() {
  local file="$1" metric="$2" raw out="" mark

  # `unlimited` só interessa se o segmento de requests estiver em cena: filtrado
  # para budget, o ∞ falaria de um número que não está na tela.
  raw="$(sl_jq -r --arg m "$metric" '
    [ (if ($m != "budget" and .requests.unlimited == true) then "unlimited" else empty end),
      (if (.error != null or (.ok | not)) then "offline" else empty end) ]
    | join(" ")' "$file" 2>/dev/null)" || return 1
  [ -n "$raw" ] || return 1

  for mark in $raw; do
    case "$mark" in
      unlimited)
        if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then
          out="${out}${out:+ }${SL_DIM}∞${SL_RESET}"
        else
          out="${out}${out:+ }${SL_DIM}unlimited${SL_RESET}"
        fi
        ;;
      offline)
        if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then
          out="${out}${out:+ }$(sl_color red)⚠${SL_RESET}"
        else
          out="${out}${out:+ }$(sl_color red)offline${SL_RESET}"
        fi
        ;;
    esac
  done

  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

_flow_compute() {
  local file="$1" metric="$2" sep="$3" label="$4" piece line=""
  local shared="" skip_b="" skip_r="" rb rr ab ar

  # Onde a data de renovação mora depende de para quem ela decide alguma coisa.
  #
  # Ela dá escala ao percentual: `24%` não diz se sobra um dia ou três semanas
  # para gastar o resto. Quando as duas cotas renovam no mesmo instante — o caso
  # de uma assinatura mensal única — repetir a mesma data nos dois segmentos
  # gasta treze colunas para não dizer nada novo. Mas apenas empurrá-la para o
  # fim a afasta justamente do número que estava pedindo atenção.
  #
  # Então: se exatamente um dos dois está em alerta, a data cola nele, porque é
  # ali que a distância até a renovação muda uma decisão. Se os dois estão no
  # mesmo estado — ambos calmos ou ambos em alerta — ela não pertence mais a um
  # que ao outro, e vira um segmento próprio depois dos números.
  #
  # Datas diferentes descrevem cotas diferentes: cada uma volta para o seu lado,
  # onde é a única leitura possível. E com `metric` filtrado não há duplicação
  # para resolver, porque só um segmento está em cena.
  if [ -z "$metric" ] &&
     [ "$(sl_config_widget_opt flow renewal true)" != "false" ]; then
    # set -- destrói os posicionais, mas file/metric/sep já foram copiados.
    set -- $(_flow_layout "$file" "$SL_FLOW_WARN")
    rb="$1"; rr="$2"; ab="$3"; ar="$4"
    if [ "$rb" != "-" ] && [ "$rb" = "$rr" ]; then
      if   [ "$ab" = "1" ] && [ "$ar" = "0" ]; then skip_r=1
      elif [ "$ar" = "1" ] && [ "$ab" = "0" ]; then skip_b=1
      else shared="$rb"; skip_b=1; skip_r=1
      fi
    fi
  fi

  if [ "$metric" != "requests" ]; then
    piece="$(_flow_segment "$file" budget "$skip_b")" && line="$piece"
  fi

  if [ "$metric" != "budget" ]; then
    if piece="$(_flow_segment "$file" requests "$skip_r")"; then
      # O separador só entra quando já há algo à esquerda: segmento ausente não
      # pode deixar pontuação órfã.
      if [ -n "$line" ]; then
        line="${line} ${SL_DIM}${sep}${SL_RESET} ${piece}"
      else
        line="$piece"
      fi
    fi
  fi

  # A data compartilhada só entra depois de algum número: sozinha ela informaria
  # quando renova uma cota que não está na tela.
  if [ -n "$shared" ] && [ -n "$line" ]; then
    if piece="$(_flow_renewal_label "$shared")"; then
      line="${line} ${SL_DIM}${sep}${SL_RESET} ${piece}"
    fi
  fi

  if piece="$(_flow_status "$file" "$metric")"; then
    if [ -n "$line" ]; then
      line="${line} ${SL_DIM}${sep}${SL_RESET} ${piece}"
    else
      line="$piece"
    fi
  fi

  # O rótulo sai dim, como o do sprint e o `5h:` do rate-forecast: nomeia os
  # números sem competir com eles. Só entra se houve linha — sozinho ele
  # anunciaria uma cota que não está na tela.
  if [ -n "$label" ] && [ -n "$line" ]; then
    line="${SL_DIM}${label}${SL_RESET} ${line}"
  fi

  printf '%s' "$line"
}

widget_flow_render() {
  local file metric sep ttl bin key renewal label

  file="$(sl_config_widget_opt flow cache "$SL_FLOW_DEFAULT_CACHE")"
  metric="$(sl_config_widget_opt flow metric)"
  sep="$(sl_config_widget_opt flow separator "·")"
  renewal="$(sl_config_widget_opt flow renewal true)"
  label="$(sl_config_widget_opt flow label "$SL_FLOW_DEFAULT_LABEL")"

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
  # configurações diferentes do mesmo JSON produzem linhas diferentes. `icons`
  # entra junto porque troca os rótulos.
  #
  # SL_NOW também, e por um motivo que só existe fora de produção: lá a variável
  # é vazia e some da chave, mas a suíte injeta relógios diferentes sobre o mesmo
  # fixture, e sem isso a segunda leitura receberia a linha da primeira.
  #
  # A regressiva da renovação, portanto, só é recalculada quando o JSON muda —
  # uma vez por TTL. Numa cota que renova por mês a menor unidade que aparece na
  # tela é a hora, e cinco minutos de defasagem não a movem.
  key="flow-$(printf '%s' \
    "$file|$metric|$sep|${SL_CONFIG_ICONS:-1}|$renewal|$label|${SL_NOW:-}" \
    | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$file" _flow_compute "$file" "$metric" "$sep" "$label"
}
