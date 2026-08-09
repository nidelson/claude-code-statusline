#!/usr/bin/env bash
# Dublê do sprint-health-line.sh real. Ecoa FAKE_SPRINT_OUT para que os testes
# controlem os números sem depender de python3 nem de um yaml BMAD de verdade.
# Recebe o caminho do yaml em $1 e o ignora, como o real faria com um yaml vazio.
printf '%s' "${FAKE_SPRINT_OUT-}"
exit 0
