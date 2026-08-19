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
SL_TIP_SOURCES="flow 7d 5h"

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
      printf '%s\tDica da janela 5h: →%s%% é projeção — cortar %s%% evita %s parado' \
        "$key" "$proj" "$cut" "$pause"
    else
      printf '%s\tDica da janela 5h: →%s%% é projeção — %s parado se o ritmo seguir' \
        "$key" "$proj" "$pause"
    fi
    return 0
  fi

  if [ "$src" = "flow" ]; then label="Dica do Flow"; else label="Dica da janela 7d"; fi

  # A cauda difere entre as duas só no tamanho: "evita a trava" cabe na frase do
  # Flow, cujo rótulo é cinco colunas mais curto, e estouraria a do 7d.
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
