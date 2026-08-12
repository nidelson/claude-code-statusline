# Taxa de acerto do cache de prompt.
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
# ── Por que rótulo em vez de ícone ──
#
# Contexto, rate limit e cache podem dividir a mesma linha, todos terminando em
# "%". Sem rótulo não há como saber qual é qual. O statusline.sh original usava
# um glifo Nerd Font; aqui o rótulo é texto, que não depende de fonte instalada e
# tem largura previsível. Quem tiver pouco espaço encurta com a opção `label`.

register_widget cache \
  --render widget_cache_render \
  --self-color \
  --desc   "Prompt cache hit rate"

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

widget_cache_render() {
  local read_tok create_tok fresh_tok total pct label color

  read_tok="$(_cache_int "$SL_CACHE_READ")"
  create_tok="$(_cache_int "$SL_CACHE_CREATE")"
  fresh_tok="$(_cache_int "$SL_INPUT_TOKENS")"

  total=$(( read_tok + create_tok + fresh_tok ))

  # Taxa de acerto sobre zero token não é 0%, é indefinida. Mostrar "0%" no
  # começo da sessão seria afirmar que o cache falhou, o que não aconteceu.
  [ "$total" -gt 0 ] || return 0

  pct="$(sl_pct "$read_tok" "$total")" || return 0

  label="$(sl_config_widget_opt cache label "$SL_CACHE_DEFAULT_LABEL")"

  if [ "$pct" -ge 70 ]; then
    color="$(sl_color green)"
  elif [ "$pct" -ge 30 ]; then
    color="$(sl_color yellow)"
  else
    color="$(sl_color red)"
  fi

  printf '%s%s%s%%%s' "$color" "$label" "$pct" "$SL_RESET"
}
