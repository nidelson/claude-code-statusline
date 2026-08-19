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
