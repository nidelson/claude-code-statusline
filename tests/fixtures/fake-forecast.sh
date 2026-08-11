#!/usr/bin/env bash
# Dublê de teste para o rate-forecast.sh real. Ecoa o que FAKE_FORECAST_OUT
# contiver, para que os testes controlem o nível sem depender do helper real
# nem de estado em disco.
#
# Com FAKE_FORECAST_ARGS_FILE apontando para um caminho, também registra os
# argumentos recebidos — é como um teste verifica o que o widget de fato
# entrega ao helper, e não apenas o que faz com a resposta.
[ -n "${FAKE_FORECAST_ARGS_FILE:-}" ] && printf '%s\n' "$*" > "$FAKE_FORECAST_ARGS_FILE"

printf '%s' "${FAKE_FORECAST_OUT:-none}"
exit 0
