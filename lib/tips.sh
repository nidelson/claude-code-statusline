# A dica que explica o bloqueio projetado.
#
# A barra já diz `Flow 💰 25%→116% 🔒 sex·2d8h`. Os três números são verdadeiros,
# e o segundo é ilegível na primeira vez: `→116%` é projeção, não consumo, e a
# leitura intuitiva do par — "gastei 25 de 116" — é o contrário do que a linha
# afirma. Esta lib produz a frase que ensina a ler isso, e some depois.
#
# Ela não mostra dado novo e não mexe em widget nenhum: o layout da barra já foi
# aprendido por quem a usa, e uma feature que o diluísse estaria competindo com
# o que deveria estar explicando.
#
# Spec: docs/superpowers/specs/2026-08-18-tips-bloqueio-projetado-design.md

# Quanto o ritmo precisa cair para a cota pousar em exatamente 100%.
#
# A projeção é `used + ritmo × restante`, e o ritmo que pousa em 100% é
# `(100 − used) / restante`. A razão entre os dois elimina o tempo E o ritmo:
#
#   corte = (proj − 100) / (proj − used)
#
# Nada de relógio, nada de taxa, e a mesma expressão serve às três fontes.
#
# O número importa porque a intuição erra feio aqui: `→116%` sugere "corte pela
# metade", quando o corte real é 18%. Uma dica que só assusta é pior que
# nenhuma — a pessoa desliga, e aí nem o alarme verdadeiro é lido.
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
# dica reaparecer, e uma dica que volta a cada ponto percentual é o mesmo que
# uma dica permanente — que é justamente o que esta feature existe para não ser.
#
# O teto em 3 existe porque bin/rate-forecast.sh clampa a projeção em 999: sem
# ele, o degrau continuaria subindo dentro de um número que já parou de subir, e
# a dica reapareceria por causa do clamp.
_tip_step() {
  local proj="$1" s
  case "$proj" in ''|*[!0-9]*) return 1 ;; esac
  [ "$proj" -gt 100 ] || return 1
  s=$(( (proj - 100) / 25 ))
  [ "$s" -gt 3 ] && s=3
  printf '%s' "$s"
}

# ── O que já foi dito, e em que turno ──
#
# O fato observado não é guardado: ele é recalculado das fontes a cada repaint.
# O que precisa de memória é só o que já foi anunciado — o degrau, para a regra
# de piora; a data de bloqueio, para a regra dos 10%; e o turno, para saber se a
# dica ainda é a mesma da última vez que alguém olhou.

_tip_state_file() {
  printf '%s/tip-state.tsv' "$SL_CACHE_DIR"
}

# O turno corrente, lido do transcript.
#
# `promptId` identifica o TURNO, não a mensagem: tudo que o Claude gera enquanto
# trabalha — inclusive os `tool_result`, que são mensagens `user` — herda o
# promptId do prompt que os originou. É por isso que ele serve e uma contagem de
# mensagens não: medido numa sessão real, 84 entradas `"type":"user"` para 8
# prompts de verdade, porque 71 delas eram tool_result. Errar por um fator de
# seis aqui significaria a dica sumindo enquanto o usuário está fora.
#
# `tail -n`, e não `tail -c`: o fim de um transcript costuma ser `attachment`,
# que não carrega o campo, e um corte por bytes volta vazio. Quarenta linhas
# cobrem a folga e custam 10 ms num transcript de 2,9 MB.
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

# A chave e o turno de uma fonte, separados por espaço.
#
# O arquivo é TSV, mas a saída não: nenhum dos valores contém espaço, e um
# retorno separado por espaço deixa o chamador usar `set --` em vez de fatiar
# string com TAB literal — que em bash 3.2 é fonte de erro silencioso.
_tip_state_get() {
  local src="$1" file f key pid
  file="$(_tip_state_file)"
  [ -r "$file" ] || return 1
  # `|| [ -n "$f" ]` cobre arquivo sem quebra final: read devolve não-zero ao
  # encontrar EOF mesmo tendo preenchido as variáveis.
  while IFS="$(printf '\t')" read -r f key pid || [ -n "$f" ]; do
    [ "$f" = "$src" ] || continue
    [ -n "$pid" ] || continue
    printf '%s %s' "$key" "$pid"
    return 0
  done < "$file"
  return 1
}

# Regrava a linha de uma fonte, preservando as outras.
#
# Escreve em temporário e move: dois terminais repintando ao mesmo tempo
# poderiam ler o arquivo no meio de uma reescrita in-place.
_tip_state_put() {
  local src="$1" key="$2" pid="$3" file tmp line f
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
  printf '%s\t%s\t%s\n' "$src" "$key" "$pid" >> "$tmp"
  mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# Esquece o que uma fonte disse. Arquivo que fica vazio é apagado: ausência é o
# estado normal, e é o que faz o widget custar um `[ -f ]` no caso comum.
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

# ── As fontes ──
#
# O tip lê as mesmas fontes que os outros widgets leem, na hora de renderizar.
#
# O caminho óbvio seria `flow` e `rate-forecast` publicarem o que já
# calcularam numa global. Não funciona: o núcleo captura widget com
# `out="$("$fn")"`, que é command substitution — subshell — e global atribuída
# lá dentro morre no retorno. É o isolamento que
# docs/superpowers/decisions/2026-08-08-canal-de-retorno.md celebra, valendo
# contra nós. Medido antes de desistir dele.

# O bin do forecast, com o mesmo default de widgets/rate-forecast.sh. Duplicado
# de propósito: esta lib precisa funcionar carregada antes do widget, e
# `: "${VAR:=...}"` não sobrescreve quem já definiu.
: "${SL_FORECAST_BIN:=${SL_ROOT:-$HOME/.claude}/bin/rate-forecast.sh}"

SL_TIP_FLOW_DEFAULT_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flow-consumption.json"

# A dica só fala do que está na tela.
#
# Quem tirou o `rate-forecast` da barra não vê `→116%`, e uma dica que explica o
# que a pessoa está vendo não teria o que explicar. É também o que impede o tip
# de chamar o bin do forecast por conta própria e passar a amostrar sozinho.
#
# SL_CONFIG_LINES é separada por quebras de linha; o `tr` a achata para que um
# `case` com espaços consiga casar palavra inteira — sem isso, `flow` casaria
# dentro de `rate-forecast-flow` ou de um `command:flow`.
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
#
# Saída: "proj used blocked reset", com proj e used já arredondados por
# sl_round — a mesma regra de arredondamento que todos os percentuais desta
# statusline usam.
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
# da diferença entre leituras e o arredondamento viraria um degrau de 1 ponto
# percentual extrapolado sobre a janela inteira.
#
# Chamar o helper uma segunda vez no mesmo repaint não grava amostra espúria:
# ele só registra quando `now − last_ts ≥ 60`, e o widget rate-forecast já
# amostrou no mesmo segundo. Verificado em bin/rate-forecast.sh.
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


# ── O contrato de fonte ──
#
# Cada fonte devolve "<chave><TAB><frase pronta>", e recebe a chave que ela mesma
# devolveu da última vez.
#
# A chave é opaca para o widget: ele só compara com a gravada. Quem sabe o que
# conta como mudança material é a fonte, e isso não é preferência de estilo. O
# flow considera "piorou" um degrau a mais OU uma antecipação acima de 10% do que
# faltava; comparada por igualdade simples, uma data de bloqueio que andou um
# segundo produziria chave nova e a dica voltaria a cada repaint.
#
# Foi essa inversão que abriu espaço para as dicas de cache: "o prefixo esfriou"
# não tem projeção nem data de trava, e no contrato anterior — proj/used/blocked/
# reset — teria de vir com quatro campos vazios que não significam nada.
SL_TIP_SOURCES="flow 7d 5h cache-cold cache-expiring"

# Piso da pausa do 5h. Travar quatro minutos antes de a janela virar não vale uma
# linha na barra: a janela renova em horas, e o custo de estourar ali é uma
# pausa, não um bloqueio.
SL_TIP_5H_MIN_PAUSE=900

# Tempo é entrada, não relógio — mesma razão de widgets/rate-forecast.sh: sem
# isso a suíte passaria a depender do dia em que roda.
_tip_now() {
  if [ -n "$SL_NOW" ]; then printf '%s' "$SL_NOW"; else date +%s; fi
}

# Hífen não é legal em nome de função. Mesma conversão que _sl_slug faz em
# lib/core.sh, pelo mesmo motivo.
_tip_slug() {
  local n="$1"
  printf '%s' "${n//-/_}"
}

# O rótulo da linha de dica.
#
# `⎿` é o glifo com que o Claude Code marca as próprias notas, e a linha de dica
# é exatamente isso: uma nota sobre a barra, não mais um dado dela. Emprestá-lo
# dá à linha o vocabulário visual que o usuário já reconhece, sem inventar marca
# nova.
#
# E ele paga o próprio espaço: se o glifo já diz "isto é uma nota", a palavra
# "Dica" vira redundante, e as frases encolhem seis colunas em vez de crescer
# duas. Mesma lição que cortou as datas das frases de projeção e o "esfriou" das
# de cache — a dica só carrega o que mais nada está dizendo.
#
# Sem ícones a palavra volta, porque aí não há glifo para sinalizar nada. É o
# mesmo arranjo de _flow_label em widgets/flow.sh.
#
# U+23BF é BMP e tem East Asian Width neutro — ao contrário do ⟳ e do 🔒, não
# disputa célula com o texto seguinte, então dispensa o espaço defensivo que
# aqueles exigem.
_tip_label() {
  if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then
    printf '⎿ %s' "$1"
  else
    printf '%s' "$2"
  fi
}

# A chave das fontes de projeção: "<degrau>:<blocked>".
#
# Devolve a chave ANTERIOR quando nada material mudou — é assim que a regra dos
# 10% sobrevive a uma comparação por igualdade. A margem é relativa de propósito:
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

# As três fontes de projeção, servidas por um corpo só.
#
# As frases são as mesmas de antes do refactor, palavra por palavra: os testes
# que as afirmam não foram editados, e é isso que prova que a generalização não
# mudou comportamento.
_tip_src_projection() {
  local src="$1" prev="$2" raw proj used blocked reset now key cut label step gap pause

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

  step="$(_tip_step "$proj")" || return 1
  cut="$(_tip_cut "$proj" "$used")" || cut=""
  key="$(_tip_flow_key "$prev" "$step" "$blocked" "$now")"

  # O 5h troca "não gasto" pela duração da pausa, porque é isso que muda a
  # decisão ali: a janela renova em horas, então o custo não é um bloqueio, é
  # ficar parado.
  if [ "$src" = "5h" ]; then
    case "$reset" in ''|*[!0-9]*) return 1 ;; esac
    gap=$(( reset - blocked ))
    [ "$gap" -ge "$SL_TIP_5H_MIN_PAUSE" ] || return 1
    pause="$(sl_fmt_countdown "$gap")"
    if [ -n "$cut" ]; then
      printf '%s\t%s →%s%% é projeção — reduzir %s%% evita %s parado' \
        "$key" "$(_tip_label "Janela 5h:" "Dica da janela 5h:")" "$proj" "$cut" "$pause"
    else
      printf '%s\t%s →%s%% é projeção — %s parado se o ritmo seguir' \
        "$key" "$(_tip_label "Janela 5h:" "Dica da janela 5h:")" "$proj" "$pause"
    fi
    return 0
  fi

  if [ "$src" = "flow" ]; then
    label="$(_tip_label "Flow:" "Dica do Flow:")"
  else
    label="$(_tip_label "Janela 7d:" "Dica da janela 7d:")"
  fi

  # A cauda difere entre as duas só no tamanho: "evita a trava" cabe na frase do
  # Flow, cujo rótulo é cinco colunas mais curto, e estouraria a do 7d.
  if [ -n "$cut" ]; then
    if [ "$src" = "flow" ]; then
      printf '%s\t%s →%s%% é projeção, não gasto — reduzir %s%% do ritmo evita a trava' \
        "$key" "$label" "$proj" "$cut"
    else
      printf '%s\t%s →%s%% é projeção, não gasto — reduzir %s%% do ritmo evita' \
        "$key" "$label" "$proj" "$cut"
    fi
  else
    printf '%s\t%s →%s%% é projeção, não gasto — a cota trava antes de renovar' \
      "$key" "$label" "$proj"
  fi
}

_tip_src_flow() { _tip_src_projection flow "$1"; }
_tip_src_7d()   { _tip_src_projection 7d   "$1"; }
_tip_src_5h()   { _tip_src_projection 5h   "$1"; }

# ── Quanto custa regravar o prefixo ──
#
# O plugin não conhece tabela de preços, e não deve conhecer: ela envelheceria a
# cada lançamento, e mentiria para quem passa por um gateway corporativo com
# preço próprio. O preço sai do custo que o Claude Code já reporta.
#
# O caminho ingênuo — custo total sobre tokens totais — foi medido e recusado.
# Numa sessão real de 435 trocas ele dá $0,90 por milhão contra $5,00 de
# verdade: erro de 5,5×. A causa é estrutural, não amostral: 106M de tokens
# lidos do cache a 0,1× dominam a CONTAGEM e quase não pesam no CUSTO, e a média
# desaba. A dica subestimaria a regravação em cinco vezes — pior que não existir,
# porque erra para menos justamente no número que deveria assustar.
#
# O que funciona é uma invariante: output custa 5× input em toda a linha Claude
# — Fable 10/50, Opus 5/25, Sonnet 3/15, Haiku 1/5. Com ela sobra uma incógnita:
#
#   custo = P_in × (input + 0,1·read + W·write + 5·output)
#
# Medido contra os mesmos agregados: erro de 0% com W=1,25 e 11% com W=2.
# Aceitável para um número que aparece com `~` na frente.

_tip_usage_totals_compute() {
  # `-Rrs` linha a linha com `fromjson?`, e não `-s`: a última linha do
  # transcript da sessão em curso pode estar pela metade no instante da leitura,
  # e `jq -s` recusaria o arquivo inteiro por causa dela. Mesmo motivo de
  # _cache_probe_compute.
  sl_jq -Rrs '
    [ split("\n")[] | fromjson?
      | select(.type == "assistant" and .message.usage != null)
      | .message.usage ] as $u
    | if ($u | length) == 0 then empty
      else "\([$u[].input_tokens // 0] | add) \([$u[].cache_read_input_tokens // 0] | add) \([$u[].cache_creation_input_tokens // 0] | add) \([$u[].output_tokens // 0] | add)"
      end' "$1" 2>/dev/null
}

# Os quatro agregados do transcript, cacheados por mtime: a varredura é do
# arquivo inteiro, e o resultado só muda quando ele cresce.
_tip_usage_totals() {
  local key out
  [ -n "$SL_TRANSCRIPT" ] || return 1
  [ -f "$SL_TRANSCRIPT" ] || return 1
  key="tip-usage-$(printf '%s' "$SL_TRANSCRIPT" | cksum | cut -d' ' -f1)"
  out="$(cache_by_mtime "$key" "$SL_TRANSCRIPT" _tip_usage_totals_compute "$SL_TRANSCRIPT")"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# Quantas leituras do prefixo a regravação precisa para se pagar.
#
#   com cache:  W + 0,1·(N−1)        sem cache:  1·N
#
# → 3 com TTL de uma hora, 2 com cinco minutos. Não é constante escolhida a
# dedo: sai do W que widgets/cache.sh detecta do payload, e muda sozinha quando
# a conta muda.
#
# A frase na tela diz "respostas", e não "leituras": leitura é vocabulário da
# API, e ninguém a vê acontecer. A tradução erra para o lado seguro — cada
# resposta vale ao menos uma leitura, e as que chamam ferramenta valem várias,
# então a dica pede mais paciência do que a conta exige, nunca menos.
#
# "Mensagens" faria o contrário, e foi por isso recusada: ancora no que a
# pessoa digita, e um único prompt que dispare quatro ferramentas já paga a
# regravação sozinho. A dica mandaria dar /clear numa hora em que continuar
# era mais barato.
_tip_breakeven() {
  awk -v w="$1" 'BEGIN{
    n = (w - 0.1) / 0.9
    v = int(n); if (n > v) v = v + 1
    if (v < 2) v = 2
    printf "%d", v
  }'
}

# Custo de regravar <tokens> tokens, em centavos. Retorna 1 quando não dá para
# derivar — e aí a frase omite a cifra e mantém o múltiplo e a contagem, que
# continuam verdadeiros.
#
# A conta vive inteira no awk: bash 3.2 só faz aritmética inteira, e aqui todo
# fator é fracionário.
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

# ── As dicas de cache ──

# Piso de contexto. Esfriar com 12k na sessão custa centavos, e uma dica que
# aparece nesse caso ensina a ignorar a que aparece com 393k. Uma casa acima do
# limiar de gravação do cache.sh (10k), porque lá o que está em jogo é uma troca
# e aqui é o contexto inteiro.
SL_TIP_CTX_FLOOR=100000

# Janela em que vale avisar que o cache está por esfriar. É o mesmo
# SL_CACHE_TTL_CRIT do widget, e de propósito: o tempo já aparece em vermelho
# lá, e a dica explica aquele vermelho. Dois números diferentes seriam duas
# verdades sobre o mesmo instante.
SL_TIP_CACHE_SOON=60

# "<segundos restantes> <W>" do cache, ou 1.
#
# Depende de _cache_probe, que vive em widgets/cache.sh. O acoplamento é
# deliberado e guardado: sem o widget na configuração a dica não fala, pela mesma
# razão que vale para o flow — explicar um número que não está na tela não
# explica nada. E quando ele está na configuração, o arquivo foi carregado antes
# de qualquer render.
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
  # do payload: 2× para uma hora, 1,25× para cinco minutos. O mesmo usuário
  # alterna entre as duas contas, então isto não pode ser configuração.
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
# formato e cor próprios. Repetir custava dez colunas e estourava os 80, que é a
# mesma lição que as datas ensinaram nas dicas de projeção.
_tip_src_cache_cold() {
  local st rem w cents money
  _tip_ctx_big || return 1
  st="$(_tip_cache_state)" || return 1
  set -- $st
  rem="$1"; w="$2"
  [ "$rem" -le 0 ] || return 1

  money=""
  if cents="$(_tip_regrave_cost "$SL_CTX_USED" "$w")"; then
    money="$(awk -v c="$cents" 'BEGIN{ printf " (~$%.2f)", c/100 }')"
  fi

  printf 'cold\t%s regravar %s custa %s×%s — compensa em %s respostas' \
    "$(_tip_label "Cache:" "Dica do cache:")" \
    "$(sl_fmt_tokens "$SL_CTX_USED")" "$w" "$money" "$(_tip_breakeven "$w")"
}

# O prefixo está por expirar, e ainda dá para aproveitá-lo.
#
# A chave é `warn` durante a janela inteira, e não o número de segundos: uma
# chave que mudasse a cada repaint faria a dica renascer sessenta vezes num
# minuto. O texto mostra o tempo correndo; o estado é um só.
_tip_src_cache_expiring() {
  local st rem w
  _tip_ctx_big || return 1
  st="$(_tip_cache_state)" || return 1
  set -- $st
  rem="$1"; w="$2"
  [ "$rem" -gt 0 ] || return 1
  [ "$rem" -le "$SL_TIP_CACHE_SOON" ] || return 1

  printf 'warn\t%s %ss até esfriar — mandar algo agora aproveita %s gravados' \
    "$(_tip_label "Cache:" "Dica do cache:")" "$rem" "$(sl_fmt_tokens "$SL_CTX_USED")"
}
