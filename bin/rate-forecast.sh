#!/bin/bash
# Previsão de estouro de janela de rate limit.
#
#   rate-forecast.sh <label> <used_pct> <resets_at_epoch> <duração_janela_s>
#
# stdout: "<nível> <projeção>" — nível ∈ none|ok|warn|crit.
#         "none" sai sozinho, sem projeção.
# exit:   0 sempre. Nenhuma falha pode quebrar a statusline.
#
# <label> só nomeia o arquivo de estado ("5h", "7d"). <duração_janela_s> alimenta
# o estimador de média (18000 p/ 5h, 604800 p/ 7d) e calibra os limiares de
# tempo do estimador de ritmo recente — ver "Calibragem" abaixo.
#
# Spec: docs/superpowers/specs/2026-07-25-statusline-rate-forecast-design.md

label=${1:-}
used=${2:-}
resets=${3:-}
window=${4:-}

WARN=${CLAUDE_RATE_WARN:-85}
CRIT=${CLAUDE_RATE_CRIT:-100}
MIN_ELAPSED=${CLAUDE_RATE_MIN_ELAPSED:-900}
SAMPLE_EVERY=${CLAUDE_RATE_SAMPLE_EVERY:-60}
STATE_DIR=${CLAUDE_RATE_STATE_DIR:-$HOME/.claude}
now=${CLAUDE_RATE_NOW:-$(date +%s)}

give_up() { printf 'none\n'; exit 0; }

# Validação estrita: entrada suspeita vira "none" em vez de aritmética errada.
[[ "$label"  =~ ^[A-Za-z0-9_-]+$ ]]     || give_up
[[ "$used"   =~ ^[0-9]+([.][0-9]+)?$ ]] || give_up
[[ "$resets" =~ ^[0-9]+$ ]]             || give_up
[[ "$window" =~ ^[0-9]+$ ]]             || give_up
[[ "$now"    =~ ^[0-9]+$ ]]             || give_up
[ "$window" -gt 0 ]                     || give_up

# ── Calibragem ──
# Os dois limiares de tempo do ritmo recente nasceram como constantes em
# segundos, 1800 e 300, calibradas contra a única janela que existia então. Elas
# são frações dela: 18000/10 e 18000/60.
#
# Uma constante em segundos não sobrevive à troca de janela. O ritmo recente
# extrapola `delta/span` sobre o tempo restante, então o erro da projeção é
# `(resolução do delta / span) × restante`. Passar de 5 horas para 7 dias
# multiplica o restante por 33 sem mexer no span, e o menor incremento
# observável — 1 ponto percentual, que é o que a statusline entrega — projeta
# centenas por cento. Observado em produção: `7d:25%→670%`, de um único 1% visto
# sete minutos antes.
#
# Derivar da janela reproduz 1800 e 300 para as 5 horas, dígito por dígito, e
# escala sozinho para qualquer outra. O piso existe porque uma janela curta
# derivaria limiares curtos demais para medir coisa alguma; abaixo dele, o
# comportamento é o de antes desta mudança.
derive() { # derive <divisor> <piso> <override>
  local v=$(( window / $1 ))
  [[ "$3" =~ ^[0-9]+$ ]] && [ "$3" -gt 0 ] && { printf '%s' "$3"; return; }
  [ "$v" -lt "$2" ] && v=$2
  printf '%s' "$v"
}

LOOKBACK=$(derive 10 1800 "${CLAUDE_RATE_LOOKBACK:-}")
MIN_SPAN=$(derive 60 300  "${CLAUDE_RATE_MIN_SPAN:-}")

# O throttle passou a ser divisor no cálculo do gatilho da poda, então zero
# deixou de ser apenas inútil e passou a ser um erro de aritmética.
[[ "$SAMPLE_EVERY" =~ ^[0-9]+$ ]] && [ "$SAMPLE_EVERY" -gt 0 ] || SAMPLE_EVERY=60

file="$STATE_DIR/rate-samples-${label}.tsv"
mkdir -p "$STATE_DIR" 2>/dev/null

# ── Amostragem ──
# A última linha diz se a janela virou e se o throttle já liberou.
last_ts=0
last_resets=""
if [ -r "$file" ]; then
  IFS=$'\t' read -r last_ts _ last_resets < <(tail -n 1 "$file" 2>/dev/null)
  [[ "$last_ts" =~ ^[0-9]+$ ]] || last_ts=0
fi

if [ "$last_resets" != "$resets" ]; then
  # resets_at diferente = janela nova. O histórico anterior não vale mais.
  printf '%s\t%s\t%s\n' "$now" "$used" "$resets" > "$file" 2>/dev/null
elif [ $(( now - last_ts )) -ge "$SAMPLE_EVERY" ]; then
  # Append de linha curta é atômico (< PIPE_BUF): sessões paralelas convivem.
  printf '%s\t%s\t%s\n' "$now" "$used" "$resets" >> "$file" 2>/dev/null
fi

# ── Poda ──
# Só quando o arquivo cresce, p/ não reescrever a cada minuto. O corte tem folga
# sobre o LOOKBACK para o usuário poder aumentá-lo sem perder histórico útil.
#
# O gatilho acompanha o corte, em vez de ser um número fixo de linhas. Quantas
# amostras cabem na retenção é `prune_age / SAMPLE_EVERY`, e esse número muda
# com a janela: 60 nas 5 horas, mais de 2000 nos 7 dias. Um gatilho fixo em 200
# dispararia a cada repaint da janela longa, reescrevendo o arquivo inteiro sem
# ter nada para descartar — que é o oposto do que a poda existe para fazer. A
# folga em cima garante que a reescrita seja amortizada: quando roda, corta de
# volta ao tamanho de regime e só volta a disparar depois de acumular a folga
# outra vez.
# stderr do grupo inteiro: um binário ausente no pipe também não pode vazar.
prune_age=$(( LOOKBACK * 2 ))
[ "$prune_age" -lt 3600 ] && prune_age=3600
prune_at=$(( prune_age / SAMPLE_EVERY + 60 ))

sample_lines=$( { wc -l < "$file" | tr -d ' '; } 2>/dev/null )
if [[ "$sample_lines" =~ ^[0-9]+$ ]] && [ "$sample_lines" -gt "$prune_at" ]; then
  tmp="${file}.$$"
  if awk -F'\t' -v cut=$(( now - prune_age )) '$1 + 0 >= cut' "$file" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$file" 2>/dev/null
  fi
  rm -f "$tmp" 2>/dev/null
fi

# ── Previsão ──
# Dois estimadores com falhas complementares (ver spec):
#   A = média da janela   → enxerga o acumulado, reage devagar a mudança de ritmo
#   B = ritmo recente     → enxerga o ritmo atual, esquece o que já foi queimado
# Nível final = ceil da média dos dois níveis: concordância vira sinal forte,
# divergência vira warn. É o que permite ao B afrouxar um crit do A após pausa.
# Um único awk faz leitura do TSV, os dois estimadores e a combinação.
src="$file"
[ -r "$src" ] || src=/dev/null

out=$(awk -F'\t' \
  -v now="$now" -v used="$used" -v resets="$resets" -v window="$window" \
  -v lookback="$LOOKBACK" -v minspan="$MIN_SPAN" -v minelapsed="$MIN_ELAPSED" \
  -v warn="$WARN" -v crit="$CRIT" '
  function level(p) {
    if (p >= crit) return 2
    if (p >= warn) return 1
    return 0
  }
  # Amostra mais antiga que ainda está na janela móvel E na janela de rate atual.
  $3 + 0 == resets + 0 && $1 + 0 >= now - lookback {
    if (t0 == 0 || $1 + 0 < t0) { t0 = $1 + 0; p0 = $2 + 0 }
  }
  END {
    remaining = resets - now
    if (remaining < 0) remaining = 0

    lvlA = -1; projA = -1
    elapsed = now - (resets - window)
    if (elapsed >= minelapsed && elapsed <= window) {
      projA = used + (used / elapsed) * remaining
      lvlA = level(projA)
    }

    lvlB = -1; projB = -1
    if (t0 > 0 && now - t0 >= minspan) {
      rateB = (used - p0) / (now - t0)
      if (rateB < 0) rateB = 0    # pct não decresce numa janela sã
      projB = used + rateB * remaining
      lvlB = level(projB)
    }

    if (lvlA < 0 && lvlB < 0) { print "none"; exit }

    if (lvlA < 0)      final = lvlB
    else if (lvlB < 0) final = lvlA
    else               final = int((lvlA + lvlB + 1) / 2)

    proj = (projA > projB) ? projA : projB
    if (proj > 999) proj = 999    # teto p/ não estourar a largura da linha

    name[0] = "ok"; name[1] = "warn"; name[2] = "crit"
    printf "%s %d\n", name[final], proj + 0.5
  }
' "$src" 2>/dev/null)

# awk ausente, quebrado ou saída vazia: degrada em silêncio.
[ -z "$out" ] && out="none"
printf '%s\n' "$out"
