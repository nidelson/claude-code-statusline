# Consumo da janela de rate limit, com previsão de estouro.
#
# A cor aqui é semântica — codifica o nível do risco, não uma preferência do
# usuário — então o widget declara --self-color e pinta a si mesmo.
#
# A matemática da previsão vive em um helper externo (SL_FORECAST_BIN). Quando
# esse helper não existe, o widget ainda mostra o percentual atual: uma leitura
# degradada é melhor que leitura nenhuma. Essa é a razão de o widget não abortar
# em nenhum dos caminhos de erro.
#
# Contrato do helper:
#   <bin> <label> <used_pct> <resets_at_epoch> <duração_janela_s>
#   stdout: "<nível> <projeção>", nível ∈ none|ok|warn|crit
#           "none" sai sozinho, sem projeção
#   exit:   0 sempre

register_widget rate-forecast \
  --render widget_rate_forecast_render \
  --self-color \
  --desc   "Rate limit window usage with overflow forecast"

: "${SL_FORECAST_BIN:=$HOME/.claude/rate-forecast.sh}"

SL_RF_DEFAULT_WARN=50
SL_RF_DEFAULT_CRIT=80

# Tempo é entrada, não relógio. Sem isso a suíte falharia sozinha às duas da
# manhã, ou só no CI, que roda em UTC.
_rf_now() {
  if [ -n "$SL_NOW" ]; then
    printf '%s' "$SL_NOW"
  else
    date +%s
  fi
}

# Escala da original, verificada idêntica em docs/legacy/statusline-2.sh:256-260
# e docs/legacy/statusline.sh:348-350. Não há quarto nível: acima de crit tudo é
# vermelho, e a projeção carrega a gravidade.
_rf_usage_color() {
  local pct="$1" warn="$2" crit="$3"
  if   [ "$pct" -ge "$crit" ]; then sl_color red
  elif [ "$pct" -ge "$warn" ]; then sl_color yellow
  else                              sl_color green
  fi
}

_forecast_window_seconds() {
  case "$1" in
    7d) printf '604800' ;;
    *)  printf '18000'  ;;
  esac
}

# Uma janela: rótulo, uso atual, projeção e tempos. Retorna 1 quando não há
# percentual utilizável, para que o chamador saiba não emitir separador.
_rf_window() {
  local window="$1" pct="$2" reset="$3"
  local level proj out color raw
  local int warn crit ucolor repoch rlabel show_reset mark

  [ -n "$pct" ] || return 1
  # A fonte entrega float — a statusline arquivada registra ter recebido
  # 14.000000000000002 — e a comparação inteira do bash aborta a função no meio
  # quando encontra casa decimal. Arredondar antes de comparar não é higiene, é
  # o que mantém a cor funcionando.
  int="$(sl_round "$pct")" || return 1

  warn="$(sl_config_widget_opt rate-forecast warn "$SL_RF_DEFAULT_WARN")"
  crit="$(sl_config_widget_opt rate-forecast crit "$SL_RF_DEFAULT_CRIT")"
  case "$warn" in ''|*[!0-9]*) warn="$SL_RF_DEFAULT_WARN" ;; esac
  case "$crit" in ''|*[!0-9]*) crit="$SL_RF_DEFAULT_CRIT" ;; esac

  level="none"; proj=""
  if [ -x "$SL_FORECAST_BIN" ]; then
    raw="$("$SL_FORECAST_BIN" "$window" "$int" "$reset" \
           "$(_forecast_window_seconds "$window")" 2>/dev/null)" || raw=""
    # set -- divide na primeira palavra sem precisar de array.
    set -- $raw
    case "$1" in
      ok|warn|crit) level="$1"; proj="$2" ;;
      # Qualquer outra coisa, inclusive lixo, é tratada como "sem previsão".
      # Um helper com saída inesperada não pode inventar um alerta.
      *) level="none"; proj="" ;;
    esac
  fi

  # Projeção só aparece quando muda uma decisão. Um `→48%` verde ocupa espaço
  # permanente para dizer "siga em frente", que já era o estado padrão de quem
  # não vê aviso nenhum. Pior: com a projeção sempre presente, o olho aprende a
  # ignorá-la, e o dia em que ela vira `→116%` chega sem contraste. `ok` sai
  # pelo mesmo caminho de `none` — nos dois casos não há nada a dizer.
  case "$level" in
    crit) color="$(sl_color red)"    ;;
    warn) color="$(sl_color yellow)" ;;
    *)    color=""; proj=""          ;;
  esac

  ucolor="$(_rf_usage_color "$int" "$warn" "$crit")"

  out="${SL_DIM}${window}:${SL_RESET}${ucolor}${int}%${SL_RESET}"
  # As chaves em ${out} são obrigatórias, não estilo: o bash 3.2 aceita bytes
  # acima de 127 como parte de nome de variável, então "$out→" é lido como a
  # variável `out\xE2` — que não existe, expande vazio e ainda come o primeiro
  # byte da seta, deixando lixo na saída.
  [ -n "$proj" ] && out="${out}${color}→${proj}%${SL_RESET}"

  # Um reset ilegível apaga só a si mesmo: percentual e projeção sobrevivem.
  show_reset="$(sl_config_widget_opt rate-forecast reset true)"
  if [ "$show_reset" != "false" ]; then
    mark=""
    [ "${SL_CONFIG_ICONS:-1}" = "1" ] && mark="⟳"
    repoch="$(sl_epoch_normalize "$reset")" \
      && rlabel="$(sl_reset_label "$repoch" "$(_rf_now)")" \
      && out="${out} ${SL_DIM}${mark}${rlabel}${SL_RESET}"
  fi

  printf '%s' "$out"
}

widget_rate_forecast_render() {
  local window sep piece mark line=""

  window="$(sl_config_widget_opt rate-forecast window)"
  sep="$(sl_config_widget_opt rate-forecast separator "·")"

  if [ "$window" != "7d" ]; then
    piece="$(_rf_window 5h "$SL_5H_PCT" "$SL_5H_RESET")" && line="$piece"
  fi

  if [ "$window" != "5h" ]; then
    if piece="$(_rf_window 7d "$SL_7D_PCT" "$SL_7D_RESET")"; then
      # O separador só entra quando já há algo à esquerda: janela ausente não
      # pode deixar pontuação órfã, do mesmo modo que o núcleo trata widget
      # vazio.
      if [ -n "$line" ]; then
        line="${line} ${SL_DIM}${sep}${SL_RESET} ${piece}"
      else
        line="$piece"
      fi
    fi
  fi

  [ -n "$line" ] || return 0

  mark=""
  [ "${SL_CONFIG_ICONS:-1}" = "1" ] && mark="${SL_DIM}⏱${SL_RESET} "

  printf '%s%s' "$mark" "$line"
}
