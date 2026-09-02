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
. "$SL_ROOT/lib/timefmt.sh"
. "$SL_ROOT/lib/num.sh"
# Por último: lib/tips.sh consome sl_round, sl_fmt_countdown, sl_jq e
# sl_config_widget_opt, então precisa de todas as anteriores já em memória.
. "$SL_ROOT/lib/tips.sh"

input="$(cat)"
sl_parse_stdin "$input"

# O relógio do repaint é lido uma vez e vale para todos os widgets.
#
# SL_NOW já existia como injeção de teste — os helpers `_cache_now`, `_rf_now`,
# `_flow_now` e `_tip_now` a consultam antes de chamar `date`. Preenchê-la aqui
# não muda o contrato deles e resolve duas coisas de uma vez: cada `date` era um
# processo, e eram meia dúzia por repaint num sistema em que processo é o
# recurso caro (ver o cabeçalho de lib/config.sh); e dois widgets que leem o
# relógio em momentos diferentes do mesmo repaint podiam discordar em um
# segundo, o bastante para uma regressiva e a dica que a comenta divergirem.
#
# O `:-` preserva quem já a define: os testes continuam mandando no relógio.
SL_NOW="${SL_NOW:-$(date +%s)}"

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
