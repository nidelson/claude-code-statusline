# Adaptador para comandos externos.
#
# Este é o único widget que é núcleo e não domínio: em vez de saber sobre uma
# fonte de dados, ele deixa o usuário plugar qualquer uma sem escrever bash.
#
# ── Várias instâncias ──
#
# Nomeadas `command:<nome>` na configuração. Cada nome vira um widget registrado
# com função de render própria, gerada no carregamento a partir das linhas
# configuradas. Um arquivo, N instâncias.
#
# ── Ler e atualizar são coisas separadas ──
#
# `cmd` produz o texto e precisa ser rápido; `refresh` é opcional, roda destacado
# e existe para aquecer o que o `cmd` lê. A separação não é enfeite: um fetcher
# que fala com a rede não pode rodar de forma síncrona, ou a statusline inteira
# espera pela latência dele. Com os dois, o widget mostra o resultado da rodada
# anterior e dispara a próxima em segundo plano.
#
# O `refresh` só dispara quando o TTL expira — vive dentro da função de cálculo,
# que é justamente a que o cache pula.
#
# O redirecionamento de stdout do refresh não é higiene, é obrigatório: um filho
# em segundo plano que herde o pipe da substituição de comando a mantém aberta, e
# a statusline trava esperando o fetcher que ela mesma tentou não esperar.
#
# ── Timeout ──
#
# macOS não traz `timeout(1)`, e sem coreutils instalado não há `gtimeout`
# também — confirmado nesta máquina. Sem um limite, um comando pendurado
# congelaria a statusline. Quando nenhum dos dois existe, o widget usa um
# watchdog em bash puro, com arquivo temporário porque capturar a saída de um
# processo em segundo plano por substituição travaria pelo mesmo motivo acima.
#
# ── Saída de terceiros é higienizada ──
#
# Ver lib/sanitize.sh. Por padrão nada de escape passa; `colors: true` abre a
# exceção estreita do SGR.

_command_register_instances() {
  local name slug
  for name in $(printf '%s' "$SL_CONFIG_LINES" | tr '\n' ' '); do
    case "$name" in
      command:*) ;;
      *) continue ;;
    esac
    sl_widget_registered "$name" && continue
    slug="$(_sl_slug "$name")"
    # Uma função por instância, fechando sobre o próprio nome: o contrato de
    # render não recebe argumentos.
    eval "widget_${slug}_render() { _command_render '$name'; }"
    register_widget "$name" \
      --render "widget_${slug}_render" \
      --desc   "Output of an external command"
  done
}

SL_COMMAND_DEFAULT_TTL=60
SL_COMMAND_DEFAULT_TIMEOUT=2

# Resolvido uma vez, no carregamento.
SL_COMMAND_TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || printf '')"

_command_exec() {
  local secs="$1" cmdline="$2" tmp pid watcher

  if [ -n "$SL_COMMAND_TIMEOUT_BIN" ]; then
    "$SL_COMMAND_TIMEOUT_BIN" "$secs" bash -c "$cmdline" 2>/dev/null
    return 0
  fi

  mkdir -p "$SL_CACHE_DIR" 2>/dev/null
  tmp="$SL_CACHE_DIR/.command.$$.$RANDOM"

  bash -c "$cmdline" >"$tmp" 2>/dev/null &
  pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watcher=$!

  wait "$pid" 2>/dev/null
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null

  cat "$tmp" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
}

_command_compute() {
  local instance="$1" cmd refresh secs mode

  cmd="$(sl_config_widget_opt "$instance" cmd)"
  [ -n "$cmd" ] || return 0

  refresh="$(sl_config_widget_opt "$instance" refresh)"
  if [ -n "$refresh" ]; then
    # </dev/null além dos redirecionamentos de saída: sem isso o filho herda o
    # stdin da statusline e pode consumir o JSON da sessão.
    ( bash -c "$refresh" >/dev/null 2>&1 </dev/null & ) >/dev/null 2>&1
  fi

  secs="$(sl_config_widget_opt "$instance" timeout "$SL_COMMAND_DEFAULT_TIMEOUT")"
  case "$secs" in
    ""|*[!0-9]*) secs="$SL_COMMAND_DEFAULT_TIMEOUT" ;;
  esac

  mode=strip
  [ "$(sl_config_widget_opt "$instance" colors)" = "true" ] && mode=colors

  _command_exec "$secs" "$cmd" | sl_sanitize "$mode"
}

_command_render() {
  local instance="$1" ttl key out label

  [ -n "$(sl_config_widget_opt "$instance" cmd)" ] || return 0

  ttl="$(sl_config_widget_opt "$instance" ttl "$SL_COMMAND_DEFAULT_TTL")"
  case "$ttl" in
    ""|*[!0-9]*) ttl="$SL_COMMAND_DEFAULT_TTL" ;;
  esac

  key="command-$(printf '%s' "$instance" | cksum | cut -d' ' -f1)"
  out="$(cache_by_ttl "$key" "$ttl" _command_compute "$instance")"

  # Apara as pontas. Praticamente todo comando termina com uma quebra de linha,
  # que a higienização converte em espaço — e um espaço sobrando aqui vira um vão
  # visível entre o texto e o separador.
  out="${out#"${out%%[! ]*}"}"
  out="${out%"${out##*[! ]}"}"

  # Espaço em branco puro conta como vazio: um comando que devolve só uma quebra
  # de linha não deve render um widget de um espaço só, com separadores dos dois
  # lados.
  case "$out" in
    ''|*[!\ ]*) ;;
    *) return 0 ;;
  esac
  [ -n "$out" ] || return 0

  label="$(sl_config_widget_opt "$instance" label)"
  printf '%s%s' "$label" "$out"
}

_command_register_instances
