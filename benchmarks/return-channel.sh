#!/usr/bin/env bash
# Compara os dois candidatos a canal de retorno de widget sob carga realista:
# 11 widgets, 200 repaints.
#
# Usa o builtin `time` com TIMEFORMAT='%3R' porque `date +%s` só tem resolução
# de um segundo — a estratégia sem subshell termina bem abaixo disso e a
# medição sairia "0s vs 1s", inútil. O BSD date do macOS não tem %N.
#
# Os laços usam `for ((...))` em vez de `seq` de propósito: `seq` é um binário
# externo e forkaria dentro da região medida, poluindo justamente o que se quer
# medir.

REPAINTS=200
WIDGETS=11

# --- Estratégia A: variável global, sem subshell ---
for ((i = 1; i <= WIDGETS; i++)); do
  eval "w_var_$i() { WIDGET_OUT=\"widget-$i\"; }"
done

run_var() {
  local i line=""
  for ((i = 1; i <= WIDGETS; i++)); do
    WIDGET_OUT=""
    "w_var_$i"
    [ -n "$WIDGET_OUT" ] && line="$line|$WIDGET_OUT"
  done
}

# --- Estratégia B: stdout capturado por command substitution ---
for ((i = 1; i <= WIDGETS; i++)); do
  eval "w_out_$i() { printf '%s' \"widget-$i\"; }"
done

run_out() {
  local i out line=""
  for ((i = 1; i <= WIDGETS; i++)); do
    out="$("w_out_$i")"
    [ -n "$out" ] && line="$line|$out"
  done
}

measure() {
  local fn="$1" i
  TIMEFORMAT='%3R'
  { time { for ((i = 0; i < REPAINTS; i++)); do "$fn"; done; }; } 2>&1
}

printf 'bash %s | %s widgets | %s repaints\n\n' "$BASH_VERSION" "$WIDGETS" "$REPAINTS"

var_time="$(measure run_var)"
out_time="$(measure run_out)"

printf 'WIDGET_OUT (sem subshell)  %ss\n' "$var_time"
printf 'stdout (command subst.)    %ss\n' "$out_time"

# Diferença por repaint, em milissegundos. awk porque bash 3.2 não faz
# aritmética de ponto flutuante.
awk -v a="$var_time" -v b="$out_time" -v n="$REPAINTS" \
  'BEGIN { printf "\ndiferenca por repaint: %.2f ms\n", (b - a) * 1000 / n }'
