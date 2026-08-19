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

# Os três campos de uma fonte, separados por espaço.
#
# O arquivo é TSV, mas a saída não: nenhum dos valores contém espaço, e um
# retorno separado por espaço deixa o chamador usar `set --` em vez de fatiar
# string com TAB literal — que em bash 3.2 é fonte de erro silencioso.
_tip_state_get() {
  local src="$1" file f step blocked pid
  file="$(_tip_state_file)"
  [ -r "$file" ] || return 1
  # `|| [ -n "$f" ]` cobre arquivo sem quebra final: read devolve não-zero ao
  # encontrar EOF mesmo tendo preenchido as variáveis.
  while IFS="$(printf '\t')" read -r f step blocked pid || [ -n "$f" ]; do
    [ "$f" = "$src" ] || continue
    [ -n "$pid" ] || continue
    printf '%s %s %s' "$step" "$blocked" "$pid"
    return 0
  done < "$file"
  return 1
}

# Regrava a linha de uma fonte, preservando as outras.
#
# Escreve em temporário e move: dois terminais repintando ao mesmo tempo
# poderiam ler o arquivo no meio de uma reescrita in-place.
_tip_state_put() {
  local src="$1" step="$2" blocked="$3" pid="$4" file tmp line f
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
  printf '%s\t%s\t%s\t%s\n' "$src" "$step" "$blocked" "$pid" >> "$tmp"
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

# Decide se esta fonte fala agora, e registra o que foi dito.
#
# Três motivos para falar: é a primeira vez; a projeção subiu de degrau; a data
# de bloqueio antecipou mais de 10% do que faltava. Fora isso a dica continua na
# tela enquanto for o mesmo turno, e cala no próximo — que é o que a faz esperar
# por quem saiu para almoçar, em vez de morrer no relógio.
#
# A regra dos 10% é relativa de propósito: antecipar duas horas numa trava que
# estava a três dias não muda decisão nenhuma; as mesmas duas horas numa que
# estava a seis mudam tudo.
#
# Transcript ilegível vira o turno `-`, que é estável entre repaints: a dica
# fica na tela em vez de piscar. Falhar mostrando é melhor que falhar calado,
# porque o `🔒` da linha de cima continua verdadeiro de qualquer jeito.
_tip_should_show() {
  local src="$1" proj="$2" blocked="$3" now="$4"
  local step prev pstep pblocked ppid pid margin

  step="$(_tip_step "$proj")" || return 1
  pid="$(_tip_prompt_id)" || pid="-"

  if ! prev="$(_tip_state_get "$src")"; then
    _tip_state_put "$src" "$step" "$blocked" "$pid"
    return 0
  fi

  set -- $prev
  pstep="$1"; pblocked="$2"; ppid="$3"
  case "$pstep"    in ''|*[!0-9]*) pstep=0 ;;    esac
  case "$pblocked" in ''|*[!0-9]*) pblocked=0 ;; esac

  if [ "$step" -gt "$pstep" ]; then
    _tip_state_put "$src" "$step" "$blocked" "$pid"
    return 0
  fi

  case "$blocked" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$pblocked" -gt 0 ] && [ "$blocked" -lt "$pblocked" ]; then
        margin=$(( (pblocked - now) / 10 ))
        [ "$margin" -ge 0 ] || margin=0
        if [ $(( pblocked - blocked )) -gt "$margin" ]; then
          _tip_state_put "$src" "$step" "$blocked" "$pid"
          return 0
        fi
      fi
      ;;
  esac

  [ "$pid" = "$ppid" ] || return 1
  return 0
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

# ── As frases ──

# Piso da pausa do 5h. Travar quatro minutos antes de a janela virar não vale
# uma linha na barra: a janela renova em horas, e o custo de estourar ali é uma
# pausa, não um bloqueio.
SL_TIP_5H_MIN_PAUSE=900

# A frase de uma fonte, em uma linha de no máximo 80 colunas.
#
# ── Nenhuma data aparece aqui ──
#
# É decisão, não esquecimento. `🔒 Fri·2d8h` e `⟳` já estão na linha de cima,
# cada um com seu formato decidido. Repetir a data custava trinta colunas para
# não acrescentar nada — e foi o que estourou os 80 caracteres no primeiro
# rascunho. Sobra o que a barra NÃO consegue dizer: que o número é projeção e
# não consumo, e quanto o ritmo precisa cair.
#
# ── "No ritmo atual" nunca vira "nas últimas 3h" ──
#
# O flow-consumption.json entrega `projected_percentage` pronto sem dizer sobre
# que período, e o bin/rate-forecast.sh reporta o MAIOR entre duas projeções —
# a da média da janela e a do ritmo recente — de modo que nem o LOOKBACK
# descreve o que gerou o número. Nomear uma janela que a fonte não afirma é
# inventar precisão, numa frase cujo trabalho é ensinar a ler um número.
#
# ── O 5h fala outra coisa ──
#
# Ele troca "não gasto" pela duração da pausa, porque é isso que muda a decisão
# ali: a janela renova em horas, então o custo não é um bloqueio, é ficar
# parado.
_tip_phrase() {
  local src="$1" proj="$2" used="$3" blocked="$4" reset="$5"
  local cut label pause gap

  case "$src" in
    flow|5h|7d) ;;
    *) return 1 ;;
  esac

  cut="$(_tip_cut "$proj" "$used")" || cut=""

  if [ "$src" = "5h" ]; then
    case "$reset" in ''|*[!0-9]*) return 1 ;; esac
    case "$blocked" in ''|*[!0-9]*) return 1 ;; esac
    gap=$(( reset - blocked ))
    [ "$gap" -ge "$SL_TIP_5H_MIN_PAUSE" ] || return 1
    pause="$(sl_fmt_countdown "$gap")"
    if [ -n "$cut" ]; then
      printf 'Dica da janela 5h: →%s%% é projeção — cortar %s%% evita %s parado' \
        "$proj" "$cut" "$pause"
    else
      printf 'Dica da janela 5h: →%s%% é projeção — %s parado se o ritmo seguir' \
        "$proj" "$pause"
    fi
    return 0
  fi

  if [ "$src" = "flow" ]; then label="Dica do Flow"; else label="Dica da janela 7d"; fi

  # A cauda difere entre as duas só no tamanho: "evita a trava" cabe na frase do
  # Flow, cujo rótulo é cinco colunas mais curto, e estouraria a do 7d.
  if [ -n "$cut" ]; then
    if [ "$src" = "flow" ]; then
      printf '%s: →%s%% é projeção, não gasto — cortar %s%% do ritmo evita a trava' \
        "$label" "$proj" "$cut"
    else
      printf '%s: →%s%% é projeção, não gasto — cortar %s%% do ritmo evita' \
        "$label" "$proj" "$cut"
    fi
  else
    printf '%s: →%s%% é projeção, não gasto — a cota trava antes de renovar' \
      "$label" "$proj"
  fi
}
