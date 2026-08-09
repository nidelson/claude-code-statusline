#!/usr/bin/env bash
# Entrypoint. Reads the Claude Code session JSON on stdin, prints the statusline.
# Never uses `set -e`: a non-zero return must not blank the user's status line.

SL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$SL_ROOT/lib/stdin.sh"

input="$(cat)"
sl_parse_stdin "$input"

printf '%s\n' "$SL_MODEL"
