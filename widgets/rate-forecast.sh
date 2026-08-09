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

_forecast_window_seconds() {
  case "$1" in
    7d) printf '604800' ;;
    *)  printf '18000'  ;;
  esac
}

widget_rate_forecast_render() {
  local window pct reset level proj out color raw

  window="$(sl_config_widget_opt rate-forecast window)"
  [ -n "$window" ] || window="5h"

  if [ "$window" = "7d" ]; then
    pct="$SL_7D_PCT"; reset="$SL_7D_RESET"
  else
    window="5h"
    pct="$SL_5H_PCT"; reset="$SL_5H_RESET"
  fi

  [ -n "$pct" ] || return 0

  level="none"; proj=""
  if [ -x "$SL_FORECAST_BIN" ]; then
    raw="$("$SL_FORECAST_BIN" "$window" "$pct" "$reset" \
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

  case "$level" in
    crit) color="$(sl_color red)"    ;;
    warn) color="$(sl_color yellow)" ;;
    ok)   color="$(sl_color green)"  ;;
    *)    color=""                   ;;
  esac

  out="${window}:${pct}%"
  # As chaves em ${out} são obrigatórias, não estilo: o bash 3.2 aceita bytes
  # acima de 127 como parte de nome de variável, então "$out→" é lido como a
  # variável `out\xE2` — que não existe, expande vazio e ainda come o primeiro
  # byte da seta, deixando lixo na saída.
  [ -n "$proj" ] && out="${out}→${proj}%"

  if [ -n "$color" ]; then
    printf '%s%s%s' "$color" "$out" "$SL_RESET"
  else
    printf '%s' "$out"
  fi
}
