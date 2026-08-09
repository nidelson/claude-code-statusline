#!/usr/bin/env bash
# Entrypoint. Reads the Claude Code session JSON on stdin, prints the statusline.
# Never uses `set -e`: a non-zero return must not blank the user's status line.

SL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

input="$(cat)"

# Placeholder until Task 2 wires the real parser.
printf '%s\n' "claude-code-statusline"
