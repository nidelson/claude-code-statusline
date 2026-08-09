#!/usr/bin/env bash
# Entrypoint. Lê o JSON de sessão do Claude Code no stdin e imprime a statusline.
# Nunca usa `set -e`: um retorno diferente de zero não pode apagar a statusline
# do usuário.

SL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$SL_ROOT/lib/colors.sh"
. "$SL_ROOT/lib/core.sh"
. "$SL_ROOT/lib/cache.sh"
# Depois de cache.sh: sl_git_paths usa cache_by_ttl.
. "$SL_ROOT/lib/gitdir.sh"
. "$SL_ROOT/lib/stdin.sh"
. "$SL_ROOT/lib/config.sh"
. "$SL_ROOT/lib/sanitize.sh"

input="$(cat)"
sl_parse_stdin "$input"
sl_config_load

# Carrega apenas os widgets que a configuração pede. Widget inexistente é
# ignorado: a config pode nomear algo de uma versão mais nova.
for _w in $(printf '%s' "$SL_CONFIG_LINES" | tr '\n' ' '); do
  # `command:<nome>` são instâncias de um arquivo só: várias entradas na
  # configuração, um widgets/command.sh, que se registra uma vez por nome.
  case "$_w" in
    command:*) _f=command ;;
    *)         _f="$_w"   ;;
  esac
  [ -f "$SL_ROOT/widgets/$_f.sh" ] && . "$SL_ROOT/widgets/$_f.sh"
done

sl_render_all
