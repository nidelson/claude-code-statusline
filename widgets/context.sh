# Ocupação da janela de contexto, como barra com gradiente.
#
# Usa total_input_tokens (acumulado da sessão), não o uso da última troca: é o
# número alinhado com o percentual que a própria interface do Claude Code
# mostra. O uso da última troca subestima o contexto real em torno de 9%.
#
# A cor é semântica — verde, amarelo e vermelho codificam quanto resta, não uma
# preferência — então o widget é --self-color.
#
# ── Resolução em oitavos ──
#
# Uma barra de 20 células com blocos cheios tem 20 passos, ou seja, 5% por
# passo: a barra fica parada durante boa parte do trabalho e depois pula. Os
# blocos parciais do Unicode (▏▎▍▌▋▊▉) dão 8 sub-posições por célula, levando a
# 160 passos, ou ~0,6% por passo. A barra passa a se mexer continuamente.
#
# O bloco parcial recebe o fundo do trilho, senão a calha some justamente na
# célula da ponta e a barra parece mais curta do que é.
#
# ── Sem subshell no laço ──
#
# A versão original chamava uma função via $(...) para cada célula — 20
# subshells por repaint, em algo que é aritmética pura. `printf -v` escreve
# direto na variável e mantém o widget em zero forks.

register_widget context \
  --render widget_context_render \
  --self-color \
  --desc   "Context window usage bar"

SL_CONTEXT_DEFAULT_WIDTH=20

# Montados uma vez, no source, e não a cada renderização.
SL_CONTEXT_PARTIALS=( "" "▏" "▎" "▍" "▌" "▋" "▊" "▉" )
SL_CONTEXT_ESC=$'\033'
SL_CONTEXT_TRACK_BG=$'\033[48;2;38;38;38m'
SL_CONTEXT_TRACK=$'\033[38;2;60;60;60m░'

# 69000 → "69k", 1000000 → "1.0M", 950 → "950"
_context_fmt_tokens() {
  local n="$1"
  case "$n" in
    ""|*[!0-9]*) printf '0'; return 0 ;;
  esac
  if [ "$n" -ge 1000000 ]; then
    printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}

widget_context_render() {
  local size used pct width tokens
  local eighths full rem i pos r g b cell bar="" color out

  size="$SL_CTX_SIZE"
  used="$SL_CTX_USED"

  case "$size" in ""|*[!0-9]*) return 0 ;; esac
  case "$used" in ""|*[!0-9]*) used=0 ;; esac
  [ "$size" -gt 0 ] || return 0

  pct="$(sl_pct "$used" "$size")" || return 0

  width="$(sl_config_widget_opt context width)"
  case "$width" in
    ""|*[!0-9]*|0) width="$SL_CONTEXT_DEFAULT_WIDTH" ;;
  esac

  tokens="$(sl_config_widget_opt context tokens)"
  [ -n "$tokens" ] || tokens="true"

  # A janela pode ser estourada por uma troca única grande. O percentual mostra
  # o valor real, mas a barra para na largura — uma barra que cresce além da
  # própria calha desalinha a linha inteira.
  eighths=$(( pct * width * 8 / 100 ))
  [ "$eighths" -gt $(( width * 8 )) ] && eighths=$(( width * 8 ))
  full=$(( eighths / 8 ))
  rem=$(( eighths % 8 ))

  for (( i=0; i<width; i++ )); do
    # O gradiente é posicional: a mesma célula tem sempre a mesma cor, e o
    # avanço da barra revela o degradê em vez de repintá-lo.
    if [ "$width" -le 1 ]; then
      pos=0
    else
      pos=$(( i * 100 / (width - 1) ))
    fi

    if [ "$pos" -le 50 ]; then
      r=$(( 220 * pos / 50 ))
      g=200
      b=$(( 80 - 80 * pos / 50 ))
    else
      r=220
      g=$(( 200 - 160 * (pos - 50) / 50 ))
      b=$(( 20 * (pos - 50) / 50 ))
    fi

    if [ "$i" -lt "$full" ]; then
      printf -v cell '%s[38;2;%d;%d;%dm█' "$SL_CONTEXT_ESC" "$r" "$g" "$b"
      bar="${bar}${cell}"
    elif [ "$i" -eq "$full" ] && [ "$rem" -gt 0 ]; then
      printf -v cell '%s%s[38;2;%d;%d;%dm%s%s' \
        "$SL_CONTEXT_TRACK_BG" "$SL_CONTEXT_ESC" "$r" "$g" "$b" \
        "${SL_CONTEXT_PARTIALS[$rem]}" "$SL_RESET"
      bar="${bar}${cell}"
    else
      bar="${bar}${SL_CONTEXT_TRACK}"
    fi
  done
  bar="${bar}${SL_RESET}"

  if [ "$pct" -ge 90 ]; then
    color="$(sl_color red)"
  elif [ "$pct" -ge 70 ]; then
    color="$(sl_color yellow)"
  else
    color="$(sl_color green)"
  fi

  out="${bar} ${color}${pct}%${SL_RESET}"

  if [ "$tokens" != "false" ]; then
    out="${out} ${SL_DIM}($(_context_fmt_tokens "$used")/$(_context_fmt_tokens "$size"))${SL_RESET}"
  fi

  printf '%s' "$out"
}
