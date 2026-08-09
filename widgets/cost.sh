# Custo acumulado da sessão, em dólares.
#
# ── Por que --self-color com fallback manual ──
#
# Cor de custo é preferência enquanto o número é pequeno e vira semântica quando
# passa de um limite que só o usuário sabe qual é. Os dois modos do contrato,
# condicionalmente. Então o widget declara --self-color e resolve a cor
# configurada por conta própria quando nenhum limite foi cruzado — as três linhas
# duplicadas do núcleo são o preço de não ter um terceiro modo no contrato só
# para este caso.
#
# Sem `warn` nem `crit` configurados o comportamento é o do statusline.sh
# original: amarelo, sempre.
#
# ── Por que LC_ALL=C ──
#
# Em locales onde o separador decimal é vírgula (pt_BR, de_DE, fr_FR...), o
# printf do bash rejeita "0.0234" como número inválido: imprime $0,00 e ainda
# escreve no stderr. Medido: sob LC_ALL=pt_BR.UTF-8, `printf '%.2f' 0.0234`
# falha. O valor vem do JSON, onde o separador é sempre ponto por definição, e a
# formatação precisa concordar com isso independentemente da máquina.
#
# `local LC_ALL=C` basta e se restaura no retorno da função — LC_NUMERIC não
# bastaria, porque LC_ALL tem precedência sobre ele.

register_widget cost \
  --render widget_cost_render \
  --self-color \
  --desc   "Session cost in USD"

# Dólares para centavos, como inteiro, para poder comparar em bash.
# O sufixo "e2" multiplica por 100 dentro do próprio strtod do printf, sem
# precisar de aritmética de ponto flutuante, que o bash não tem.
_cost_cents() {
  local LC_ALL=C n
  printf -v n '%.0f' "${1}e2" 2>/dev/null || return 1
  printf '%s' "$n"
}

_cost_format() {
  local LC_ALL=C out
  printf -v out '$%.2f' "$1" 2>/dev/null || return 1
  printf '%s' "$out"
}

widget_cost_render() {
  local cost text cents warn crit warn_cents crit_cents color

  cost="$SL_COST"

  # Peneira grosseira antes do printf: barra lixo óbvio sem chegar perto do
  # stderr. `e`, `+` e `-` passam porque o jq emite 1e-07 para valores muito
  # pequenos, comuns nos primeiros segundos de sessão.
  case "$cost" in
    ""|*[!0-9.eE+-]*) return 0 ;;
  esac

  text="$(_cost_format "$cost")" || return 0
  [ -n "$text" ] || return 0

  color="$(sl_config_widget_opt cost color)"
  [ -n "$color" ] && color="$(sl_color "$color")"

  cents="$(_cost_cents "$cost")" || cents=""
  crit="$(sl_config_widget_opt cost crit)"
  warn="$(sl_config_widget_opt cost warn)"
  # Limite ilegível é ignorado, nunca fatal: uma config torta não pode fazer o
  # custo sumir da statusline.
  crit_cents="$(_cost_cents "$crit")" || crit_cents=""
  warn_cents="$(_cost_cents "$warn")" || warn_cents=""

  if [ -n "$crit_cents" ] || [ -n "$warn_cents" ]; then
    # Com limites configurados o widget vira semáforo, e o piso passa a ser
    # verde. Manter o amarelo default aqui tornaria o `warn` invisível: cruzar o
    # limite pintaria de amarelo algo que já estava amarelo.
    [ -n "$color" ] || color="$(sl_color green)"
    if [ -n "$cents" ] && [ -n "$crit_cents" ] && [ "$cents" -ge "$crit_cents" ]; then
      color="$(sl_color red)"
    elif [ -n "$cents" ] && [ -n "$warn_cents" ] && [ "$cents" -ge "$warn_cents" ]; then
      color="$(sl_color yellow)"
    fi
  fi

  # Sem limite nenhum, o comportamento é o do statusline.sh original.
  [ -n "$color" ] || color="$(sl_color yellow)"

  printf '%s%s%s' "$color" "$text" "$SL_RESET"
}
