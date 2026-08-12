# Parse do stdin em uma única passada.
#
# A implementação anterior chamava `jq` quinze vezes, uma por campo, cada uma
# um fork. Esta emite todos os campos de uma vez. O `@sh` cuida do quoting, então
# valores com espaço, aspas ou quebra de linha não quebram o `eval`.

sl_parse_stdin() {
  local json="$1" assignments

  assignments="$(printf '%s' "$json" | sl_jq -r '
    @sh "SL_MODEL=\(.model.display_name // "Unknown")",
    @sh "SL_MODEL_ID=\(.model.id // "")",
    @sh "SL_COST=\(.cost.total_cost_usd // 0)",
    @sh "SL_LINES_ADDED=\(.cost.total_lines_added // 0)",
    @sh "SL_LINES_REMOVED=\(.cost.total_lines_removed // 0)",
    @sh "SL_CWD=\(.workspace.current_dir // .cwd // "")",
    # O caminho do transcript. É o único jeito de saber quando foi a última
    # troca: o payload traz os contadores de cache mas nenhum carimbo de tempo.
    @sh "SL_TRANSCRIPT=\(.transcript_path // "")",
    # Os contadores de cache vivem em .context_window.current_usage, que pode
    # ser null entre trocas. O fallback para a raiz cobre clientes que mandem os
    # campos achatados; o `// 0` final cobre o null.
    @sh "SL_CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // .cache_read_input_tokens // 0)",
    @sh "SL_CACHE_CREATE=\(.context_window.current_usage.cache_creation_input_tokens // .cache_creation_input_tokens // 0)",
    @sh "SL_INPUT_TOKENS=\(.context_window.current_usage.input_tokens // .input_tokens // 0)",
    @sh "SL_CTX_SIZE=\(.context_window.context_window_size // 0)",
    @sh "SL_CTX_USED=\(.context_window.total_input_tokens // 0)",
    # A API manda os percentuais como float, e o binário morde: o que chega é
    # 55.00000000000001, não 55. Cortar em duas casas mata essa cauda sem jogar
    # fora a precisão que o número de fato carrega — 13.6 continua 13.6.
    #
    # Arredondar ao inteiro aqui, como se fazia antes, resolvia a exibição e
    # cobrava caro de quem calcula: o helper de previsão deriva uma taxa a
    # partir da diferença entre duas leituras, e com o valor inteiro a menor
    # diferença observável é 1 ponto percentual inteiro. Extrapolado sobre os
    # dias restantes da janela de 7 dias, esse degrau de arredondamento vira uma
    # projeção de centenas por cento. Quem exibe arredonda — `sl_round`, em
    # widgets/rate-forecast.sh — e quem calcula recebe o número como veio.
    #
    # O `if type=="number"` protege o campo ausente: `// ""` já resolveu para
    # string vazia, e a aritmética em string é erro que derruba a passada inteira.
    @sh "SL_5H_PCT=\(.rate_limits.five_hour.used_percentage // "" | if type == "number" then (. * 100 | round) / 100 else . end)",
    @sh "SL_7D_PCT=\(.rate_limits.seven_day.used_percentage // "" | if type == "number" then (. * 100 | round) / 100 else . end)",
    @sh "SL_5H_RESET=\(.rate_limits.five_hour.resets_at // "")",
    @sh "SL_7D_RESET=\(.rate_limits.seven_day.resets_at // "")"
  ' 2>/dev/null)" || assignments=""
  # O `|| assignments=""` importa: command substitution carrega o exit status
  # do pipeline, então sob um chamador com `set -e` uma falha do jq abortaria
  # esta função antes de o fallback abaixo rodar.

  if [ -z "$assignments" ]; then
    # JSON malformado ou jq ausente. Widgets que dependem de dado renderizam
    # vazio; a statusline continua imprimindo.
    SL_JQ_OK=0
    SL_MODEL="Unknown"; SL_MODEL_ID=""; SL_COST=0
    SL_LINES_ADDED=0; SL_LINES_REMOVED=0; SL_CWD=""; SL_TRANSCRIPT=""
    SL_CACHE_READ=0; SL_CACHE_CREATE=0; SL_INPUT_TOKENS=0
    SL_CTX_SIZE=0; SL_CTX_USED=0
    SL_5H_PCT=""; SL_7D_PCT=""; SL_5H_RESET=""; SL_7D_RESET=""
    return 0
  fi

  eval "$assignments"
  SL_JQ_OK=1
  return 0
}
