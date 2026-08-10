#!/usr/bin/env bash
# Dublê de teste para o rate-forecast.sh real. Ecoa o que FAKE_FORECAST_OUT
# contiver, para que os testes controlem o nível sem depender do helper real
# nem de estado em disco.
printf '%s' "${FAKE_FORECAST_OUT:-none}"
exit 0
