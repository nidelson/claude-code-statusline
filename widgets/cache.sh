# Taxa de acerto do cache de prompt e quanto falta para ele expirar.
#
# cache_read_input_tokens     tokens servidos do cache, cerca de 5× mais baratos
# cache_creation_input_tokens tokens gravados no cache, com TTL
# input_tokens                tokens novos, preço cheio
#
# A taxa é read sobre a soma dos três. Alta significa cache quente e troca
# barata; baixa significa cache frio, início de sessão, ou algo tendo invalidado
# o prefixo. A cor é semântica, então o widget é --self-color.
#
# ── O número é da última troca, não da sessão ──
#
# Os contadores vêm de .context_window.current_usage, que reflete só a troca mais
# recente e é null entre elas. Ou seja, isto é um velocímetro, não um hodômetro:
# oscila a cada turno, de propósito.
#
# ── Por que a taxa não basta ──
#
# Medido sobre 845 trocas de uma sessão real: 805 de 844 amostras ficam acima de
# 95%. O número é verde e imóvel quase sempre, que é o mesmo defeito que levou a
# projeção `→48%` a ser escondida em widgets/rate-forecast.sh.
#
# Pior, a taxa engana sobre preço. Ela soma leitura e gravação no mesmo
# denominador, como se custassem igual; um token gravado custa vinte vezes um
# token lido. Naquela mesma sessão a leitura é 96,7% dos tokens e a gravação leva
# ~37% do dinheiro.
#
# Daí o segundo número. Quando o prefixo em cache expira, a próxima troca paga a
# gravação inteira de novo — e essa é a única coisa aqui que ainda dá para
# evitar, porque a taxa só conta o que já foi cobrado.
#
# ── Ícone e não rótulo ──
#
# Contexto, rate limit e cache podem dividir a mesma linha, todos terminando em
# "%", então a marca precisa distinguir. É `☁`, U+2601, o mesmo glifo que
# docs/legacy/statusline-2.sh:92 usava aqui — BMP, monocromático na prática, sem
# a Nerd Font que o statusline.sh mais antigo exigia com U+F0C2. Quem tiver
# problema de fonte volta ao texto com `icons: false`, e escolhe qual com a
# opção `label`.

register_widget cache \
  --render widget_cache_render \
  --self-color \
  --desc   "Prompt cache hit rate and time to expiry"

SL_CACHE_DEFAULT_LABEL="cache:"

# Quantas linhas do fim do transcript a sonda lê. Medido num transcript de 24 MB
# e 10.780 linhas: a maior corrida consecutiva sem nenhuma entrada `assistant`
# foi 57, e a leitura inteira custou 7 ms. A janela dá margem de sete vezes.
SL_CACHE_TAIL_LINES=400

# Limites do countdown, em segundos, absolutos e não proporcionais ao TTL. A
# pergunta que ele responde — dá tempo de escrever o próximo prompt antes de o
# cache esfriar? — tem duração humana: quem digita leva de trinta a sessenta
# segundos, e isso não muda porque a janela contratada é de uma hora.
SL_CACHE_TTL_WARN=180
SL_CACHE_TTL_CRIT=60

_cache_int() {
  case "$1" in
    ""|*[!0-9]*) printf '0' ;;
    *)           printf '%s' "$1" ;;
  esac
}

# Tempo é entrada, não relógio: sem isso a suíte falharia sozinha de madrugada,
# ou só no CI, que roda em UTC.
_cache_now() {
  if [ -n "$SL_NOW" ]; then
    printf '%s' "$SL_NOW"
  else
    date +%s
  fi
}

# `<timestamp ISO> <ttl em segundos>` da última troca, ou nada.
#
# O carimbo sai da última entrada `assistant`; o TTL, da última que GRAVOU. Nem
# sempre são a mesma: uma troca servida inteira do cache não grava nada e não
# identifica a janela contratada.
#
# O TTL é detectado, não configurado. `ephemeral_1h_input_tokens` e
# `ephemeral_5m_input_tokens` dizem qual janela a conta tem, e o mesmo usuário
# alterna entre uma máquina com uma hora e outra com cinco minutos.
#
# O parse é `-R` linha a linha com `fromjson?` em vez de `-s`: a última linha do
# transcript da sessão em curso pode estar pela metade no instante da leitura, e
# `jq -s` recusaria o arquivo inteiro por causa dela.
_cache_probe_compute() {
  tail -n "$SL_CACHE_TAIL_LINES" "$1" 2>/dev/null | jq -Rrs '
    [ split("\n")[]
      | fromjson?
      | select(.type == "assistant" and .message.usage != null) ] as $a
    | ($a | last) as $t
    | ([ $a[]
         | select(((.message.usage.cache_creation.ephemeral_1h_input_tokens // 0)
                 + (.message.usage.cache_creation.ephemeral_5m_input_tokens // 0)) > 0)
       ] | last) as $w
    | if $t == null or $w == null or ($t.timestamp | not) then empty
      else "\($t.timestamp) \(
             if (($w.message.usage.cache_creation.ephemeral_1h_input_tokens // 0) > 0)
             then 3600 else 300 end)"
      end' 2>/dev/null
}

_cache_probe() {
  local key out
  [ -n "$SL_TRANSCRIPT" ] || return 1
  [ -f "$SL_TRANSCRIPT" ] || return 1
  # A chave não inclui SL_NOW, ao contrário da do flow: o que se guarda aqui é a
  # leitura do arquivo, que não depende do relógio. A regressiva é recalculada a
  # cada repaint sobre o valor guardado, sem custo de processo.
  key="cache-ttl-$(printf '%s' "$SL_TRANSCRIPT" | cksum | cut -d' ' -f1)"
  out="$(cache_by_mtime "$key" "$SL_TRANSCRIPT" _cache_probe_compute "$SL_TRANSCRIPT")"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# O pedaço do countdown, já colorido, ou 1 quando não há o que dizer.
#
# A cor é a informação: verde é "manda quando quiser", vermelho é "manda agora
# ou pague a gravação de novo". Por isso o widget passa a imprimir duas cores —
# o percentual tem a semântica dele, o tempo tem a sua.
_cache_countdown() {
  local raw ts ttl epoch rem text color mode

  # `near` e `off` não podem ser resolvidos no mesmo ponto: `off` dispensa a
  # leitura do transcript, `near` precisa do tempo restante para decidir.
  mode="$(sl_config_widget_opt cache countdown always)"
  [ "$mode" != "off" ] || return 1

  raw="$(_cache_probe)" || return 1
  # set -- divide na primeira palavra sem precisar de array.
  set -- $raw
  ts="$1"; ttl="$2"
  case "$ttl" in ''|*[!0-9]*) return 1 ;; esac
  epoch="$(sl_epoch_normalize "$ts")" || return 1
  rem=$(( epoch + ttl - $(_cache_now) ))

  # `near` reusa o limite do amarelo em vez de inventar um segundo número para
  # o usuário calibrar: o tempo aparece quando passa a valer a pena olhar.
  # Expirado sempre aparece — é o único estado em que a próxima troca já tem
  # preço definido.
  if [ "$mode" = "near" ] && [ "$rem" -ge "$SL_CACHE_TTL_WARN" ]; then
    return 1
  fi

  if [ "$rem" -le 0 ]; then
    text="cold"
    color="$(sl_color red)"
  else
    text="$(sl_fmt_ttl "$rem")"
    if   [ "$rem" -lt "$SL_CACHE_TTL_CRIT" ]; then color="$(sl_color red)"
    elif [ "$rem" -lt "$SL_CACHE_TTL_WARN" ]; then color="$(sl_color yellow)"
    else                                           color="$(sl_color green)"
    fi
  fi

  printf '%s%s%s' "$color" "$text" "$SL_RESET"
}

widget_cache_render() {
  local read_tok create_tok fresh_tok total pct color
  local mark pct_part cd_part out

  read_tok="$(_cache_int "$SL_CACHE_READ")"
  create_tok="$(_cache_int "$SL_CACHE_CREATE")"
  fresh_tok="$(_cache_int "$SL_INPUT_TOKENS")"
  total=$(( read_tok + create_tok + fresh_tok ))

  # Taxa de acerto sobre zero token não é 0%, é indefinida. Mostrar "0%" no
  # começo da sessão seria afirmar que o cache falhou, o que não aconteceu.
  #
  # O que mudou: isso já não derruba o widget inteiro. current_usage vem null
  # entre trocas, e é parado entre trocas que o countdown decide alguma coisa —
  # se ele herdasse este retorno, sumiria exatamente na hora de servir.
  pct_part=""
  if [ "$total" -gt 0 ]; then
    if pct="$(sl_pct "$read_tok" "$total")"; then
      if   [ "$pct" -ge 70 ]; then color="$(sl_color green)"
      elif [ "$pct" -ge 30 ]; then color="$(sl_color yellow)"
      else                         color="$(sl_color red)"
      fi
      pct_part="${color}${pct}%${SL_RESET}"
    fi
  fi

  cd_part="$(_cache_countdown)" || cd_part=""

  [ -n "$pct_part" ] || [ -n "$cd_part" ] || return 0

  # O glifo é U+2601, o mesmo que docs/legacy/statusline-2.sh:92 usava aqui. O
  # statusline.sh mais antigo usava U+F0C2, área privada da Nerd Font, que este
  # projeto rejeita por depender de fonte instalada.
  #
  # O espaço depois não é folga: largura ambígua colada em dígito disputa a
  # mesma célula em boa parte dos terminais, como o ⟳ e o ⏱.
  #
  # A marca sai dim, não na cor do número: com duas cores no widget, um prefixo
  # que herdasse uma delas afirmaria que ela vale para o conjunto.
  if [ "${SL_CONFIG_ICONS:-1}" = "1" ]; then
    mark="☁ "
  else
    mark="$(sl_config_widget_opt cache label "$SL_CACHE_DEFAULT_LABEL")"
  fi

  out=""
  [ -n "$mark" ] && out="${SL_DIM}${mark}${SL_RESET}"

  if [ -n "$pct_part" ]; then
    out="${out}${pct_part}"
    [ -n "$cd_part" ] && out="${out}${SL_DIM}·${SL_RESET}${cd_part}"
  else
    out="${out}${cd_part}"
  fi

  printf '%s' "$out"
}
