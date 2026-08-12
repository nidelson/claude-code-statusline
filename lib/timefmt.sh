# Normalização e formatação de tempo.
#
# ── Três formatos de resets_at ──
#
# A fonte entrega epoch em segundos, epoch em milissegundos ou string ISO 8601 —
# as três variantes estão tratadas na statusline arquivada em
# docs/legacy/statusline-2.sh:210-219. Milissegundo tratado como segundo não
# falha visivelmente: vira uma data no ano 57000 e uma regressiva absurda, que é
# pior que não mostrar nada. A detecção é por contagem de dígitos, como na
# original.
#
# ── `date` diverge entre plataformas ──
#
# BSD aceita `date -r <epoch>`; GNU quer `date -d @<epoch>`. A original só
# precisava de macOS; o CI deste repositório roda também em Ubuntu. A forma é
# resolvida uma vez, no carregamento, como widgets/command.sh:62 já faz para
# descobrir `timeout`.
#
# ── Sem python3 ──
#
# A original convertia ISO 8601 chamando python3. Uma statusline que precisa de
# Python para desenhar contraria a restrição de runtime do projeto, que é jq e
# git. Aqui a conversão é tentada com `date` e, falhando, o chamador perde os
# tempos e mantém o resto.

# GNU interpreta `-r` como "arquivo de referência", então `date -r 0` falha lá e
# só tem sucesso no BSD. A ordem importa.
if date -r 0 +%s >/dev/null 2>&1; then
  SL_DATE_FORM=bsd
elif date -d @0 +%s >/dev/null 2>&1; then
  SL_DATE_FORM=gnu
else
  SL_DATE_FORM=""
fi

sl_date_fmt() {
  local epoch="$1" fmt="$2"
  case "$epoch" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$SL_DATE_FORM" in
    bsd) LC_ALL=C date -r "$epoch" "+$fmt" 2>/dev/null ;;
    gnu) LC_ALL=C date -d "@$epoch" "+$fmt" 2>/dev/null ;;
    *)   return 1 ;;
  esac
}

_sl_epoch_from_iso() {
  local iso="$1" out
  case "$SL_DATE_FORM" in
    gnu) out="$(LC_ALL=C date -d "$iso" +%s 2>/dev/null)" ;;
    bsd)
      # BSD exige o formato explícito e não digere sufixo de fuso nem fração.
      iso="${iso%Z}"
      iso="${iso%%.*}"
      out="$(LC_ALL=C date -j -u -f '%Y-%m-%dT%H:%M:%S' "$iso" +%s 2>/dev/null)"
      ;;
    *) return 1 ;;
  esac
  case "$out" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s' "$out"
}

sl_epoch_normalize() {
  local v="$1"

  case "$v" in
    ''|null) return 1 ;;
  esac

  # Fração de segundo não interessa a nada aqui.
  case "$v" in
    *.*)
      case "${v%%.*}" in
        ''|*[!0-9]*) ;;
        *) v="${v%%.*}" ;;
      esac
      ;;
  esac

  case "$v" in
    ''|*[!0-9]*)
      _sl_epoch_from_iso "$1"
      return $?
      ;;
  esac

  # 13 dígitos ou mais só pode ser milissegundo: 10 dígitos cobrem até o ano
  # 2286 em segundos.
  if [ "${#v}" -ge 13 ]; then
    v=$(( v / 1000 ))
  fi

  printf '%s' "$v"
}

# Duas unidades, sempre as duas maiores que não são zero. A menor é omitida
# quando zerada: `20d0h` gasta duas colunas para dizer "e mais zero horas", e
# `3h0m` faz o mesmo uma faixa abaixo. Quando ela não é zero, fica — `1d3h` diz
# algo que `1d` não diz.
sl_fmt_countdown() {
  local rem="$1" d h m
  case "$rem" in
    ''|*[!0-9]*) printf '<1m'; return 0 ;;
  esac
  d=$(( rem / 86400 ))
  h=$(( (rem % 86400) / 3600 ))
  m=$(( (rem % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then
    if [ "$h" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
    else                    printf '%dd' "$d"
    fi
  elif [ "$h" -gt 0 ]; then
    if [ "$m" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
    else                    printf '%dh' "$h"
    fi
  elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
  else                      printf '<1m'
  fi
}

# `<marca><data>·<regressiva>` a partir de um epoch cru, ou 1 quando ele é
# ilegível, ausente ou já passou.
#
# A marca vem pronta do chamador e a cor fica por conta dele: o mesmo carimbo é
# contexto calmo quando diz "renova domingo" e alerta quando diz "trava sexta",
# e quem sabe a diferença é o widget, não esta função.
sl_stamp_label() {
  local mark="$1" epoch="$2" now="$3" norm label
  norm="$(sl_epoch_normalize "$epoch")" || return 1
  label="$(sl_reset_label "$norm" "$now")" || return 1
  printf '%s%s' "$mark" "$label"
}

sl_reset_label() {
  local epoch="$1" now="$2" rem stamp
  case "$epoch$now" in
    ''|*[!0-9]*) return 1 ;;
  esac
  rem=$(( epoch - now ))
  [ "$rem" -gt 0 ] || return 1

  # A escolha é pelo tempo restante, não pelo tipo de janela: uma janela de sete
  # dias que reseta daqui a quatro horas quer o horário, não o nome do dia.
  #
  # Acima de uma semana o nome do dia deixa de identificar: "Tue" a vinte dias de
  # distância descreve três terças diferentes, e quem lê não tem como escolher.
  # Daí a terceira faixa, que atende cotas de renovação mensal como a do Flow. O
  # `%b` sai em inglês porque sl_date_fmt força LC_ALL=C — o mesmo motivo pelo
  # qual `%a` já sai "Tue" e não "ter".
  if [ "$rem" -lt 86400 ]; then
    stamp="$(sl_date_fmt "$epoch" '%H:%M')" || return 1
  elif [ "$rem" -lt 604800 ]; then
    stamp="$(sl_date_fmt "$epoch" '%a')" || return 1
  else
    stamp="$(sl_date_fmt "$epoch" '%d%b')" || return 1
  fi
  [ -n "$stamp" ] || return 1

  printf '%s·%s' "$stamp" "$(sl_fmt_countdown "$rem")"
}
