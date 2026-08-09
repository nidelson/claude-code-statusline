#!/usr/bin/env bash
# Entrypoint. Lê o JSON de sessão do Claude Code no stdin e imprime a statusline.
# Nunca usa `set -e`: um retorno diferente de zero não pode apagar a statusline
# do usuário.

SL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$SL_ROOT/lib/colors.sh"
. "$SL_ROOT/lib/core.sh"
. "$SL_ROOT/lib/stdin.sh"
. "$SL_ROOT/lib/config.sh"

input="$(cat)"
sl_parse_stdin "$input"
sl_config_load

# Carrega apenas os widgets que a configuração pede. Widget inexistente é
# ignorado: a config pode nomear algo de uma versão mais nova.
for _w in $(printf '%s' "$SL_CONFIG_LINES" | tr '\n' ' '); do
  [ -f "$SL_ROOT/widgets/$_w.sh" ] && . "$SL_ROOT/widgets/$_w.sh"
done

sl_render_all
