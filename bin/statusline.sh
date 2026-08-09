#!/usr/bin/env bash
# Entrypoint. Lê o JSON de sessão do Claude Code no stdin e imprime a statusline.
# Nunca usa `set -e`: um retorno diferente de zero não pode apagar a statusline
# do usuário.

SL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$SL_ROOT/lib/stdin.sh"

input="$(cat)"
sl_parse_stdin "$input"

printf '%s\n' "$SL_MODEL"
