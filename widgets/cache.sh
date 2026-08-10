# Taxa de acerto do cache de prompt.
#
# cache_read_input_tokens     tokens servidos do cache, cerca de 5× mais baratos
# cache_creation_input_tokens tokens gravados no cache, com TTL
# input_tokens                tokens novos, preço cheio
#
# A taxa é read sobre a soma dos três. Alta significa cache quente e troca
# barata; baixa significa cache frio, início de sessão, ou algo tendo invalidado
# o prefixo. A cor é semântica, então o widget é --self-color.
#
# ── O número é da última troca, não da sessão ──
#
# Os contadores vêm de .context_window.current_usage, que reflete só a troca mais
# recente e é null entre elas. Ou seja, isto é um velocímetro, não um hodômetro:
# oscila a cada turno, de propósito.
#
# ── Por que rótulo em vez de ícone ──
#
# Contexto, rate limit e cache podem dividir a mesma linha, todos terminando em
# "%". Sem rótulo não há como saber qual é qual. O statusline.sh original usava
# um glifo Nerd Font; aqui o rótulo é texto, que não depende de fonte instalada e
# tem largura previsível. Quem tiver pouco espaço encurta com a opção `label`.

register_widget cache \
  --render widget_cache_render \
  --self-color \
  --desc   "Prompt cache hit rate"

SL_CACHE_DEFAULT_LABEL="cache:"

_cache_int() {
  case "$1" in
    ""|*[!0-9]*) printf '0' ;;
    *)           printf '%s' "$1" ;;
  esac
}

widget_cache_render() {
  local read_tok create_tok fresh_tok total pct label color

  read_tok="$(_cache_int "$SL_CACHE_READ")"
  create_tok="$(_cache_int "$SL_CACHE_CREATE")"
  fresh_tok="$(_cache_int "$SL_INPUT_TOKENS")"

  total=$(( read_tok + create_tok + fresh_tok ))

  # Taxa de acerto sobre zero token não é 0%, é indefinida. Mostrar "0%" no
  # começo da sessão seria afirmar que o cache falhou, o que não aconteceu.
  [ "$total" -gt 0 ] || return 0

  pct=$(( (read_tok * 100 + total / 2) / total ))

  label="$(sl_config_widget_opt cache label "$SL_CACHE_DEFAULT_LABEL")"

  if [ "$pct" -ge 70 ]; then
    color="$(sl_color green)"
  elif [ "$pct" -ge 30 ]; then
    color="$(sl_color yellow)"
  else
    color="$(sl_color red)"
  fi

  printf '%s%s%s%%%s' "$color" "$label" "$pct" "$SL_RESET"
}
