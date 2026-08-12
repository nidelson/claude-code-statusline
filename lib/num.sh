# Formatação numérica compartilhada.
#
# Existia uma regra de arredondamento por widget, e elas não concordavam:
# `cache` e `context` arredondavam com o truque inteiro, `rate-forecast` com
# printf, `sprint` truncava por divisão inteira e `flow` truncava com o `floor`
# do jq. O efeito era 24,9% aparecer como `24%` num widget e como `25%` no
# vizinho, na mesma linha.
#
# Percentual é o vocabulário desta statusline — cinco widgets falam nele — e
# vocabulário compartilhado precisa de uma regra só.
#
# ── Duas funções, porque há duas entradas ──
#
# `sl_pct` recebe numerador e denominador inteiros: é o caso de quem conta
# tokens, stories ou linhas. `sl_round` recebe um número já em percentual, com
# casas decimais, vindo de uma API que fez a conta.

# Percentual inteiro a partir de uma razão, arredondado ao mais próximo.
#
# Somar metade do divisor antes de dividir arredonda em aritmética inteira sem
# depender de printf nem de ponto flutuante — o que importa em bash 3.2, onde
# `$(( ))` só faz inteiro.
#
# Denominador zero ou entrada não numérica devolve 1: não existe percentual de
# nada, e inventar `0%` afirmaria algo falso sobre o dado.
sl_pct() {
  local num="$1" den="$2"
  case "$num" in ''|*[!0-9]*) return 1 ;; esac
  case "$den" in ''|*[!0-9]*) return 1 ;; esac
  [ "$den" -gt 0 ] || return 1
  printf '%s' "$(( (num * 100 + den / 2) / den ))"
}

# Arredonda um número decimal ao inteiro mais próximo.
#
# `printf '%.0f'` arredonda meio-para-par: 24,5 vira 24 e 25,5 vira 26. Difere
# de `sl_pct`, que arredonda meio-para-cima, mas só no empate exato — que em
# percentual vindo de contagem de tokens ou de dinheiro praticamente não
# ocorre, e cuja escolha não muda nenhuma decisão de quem lê a statusline.
#
# LC_ALL=C porque num locale de vírgula decimal o printf do bash rejeita
# "24.30" — o valor vem de JSON, onde o separador é sempre ponto.
sl_round() {
  local v="$1"
  case "$v" in ''|*[!0-9.]*) return 1 ;; esac
  LC_ALL=C printf '%.0f' "$v" 2>/dev/null
}

# 69000 → "69k", 1000000 → "1.0M", 950 → "950".
#
# Ordem de grandeza é o que interessa num contador de token: a diferença entre
# 53.499 e 53.500 não muda decisão nenhuma, e os dígitos gastos com ela custam
# largura numa linha que disputa espaço. Diferente da contagem de linhas do
# velocity, onde "+1.2k" esconderia a distância entre 1200 e 1249.
sl_fmt_tokens() {
  local n="$1"
  case "$n" in
    ""|*[!0-9]*) printf '0'; return 0 ;;
  esac
  if [ "$n" -ge 1000000 ]; then
    printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}
