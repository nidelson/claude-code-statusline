# Registro de widgets.
#
# bash 3.2 não tem arrays associativos, então os atributos moram em variáveis
# cujo nome deriva do nome do widget: _W_RENDER_model, _W_COLOR_model. A leitura
# usa indireção `${!var}`, que dispensa eval.
# Hífen não é legal em nome de variável, então vira underscore. Dois-pontos
# também não, e aparecem nas instâncias de `command:<nome>`.

SL_WIDGET_LIST=""

_sl_slug() {
  local name="$1"
  printf '%s' "${name//[-:]/_}"
}

register_widget() {
  local name="$1"; shift
  local render="" color="" desc="" selfcolor=0 slug

  while [ $# -gt 0 ]; do
    case "$1" in
      --render)     render="$2";  shift 2 ;;
      --color)      color="$2";   shift 2 ;;
      --desc)       desc="$2";    shift 2 ;;
      --self-color) selfcolor=1;  shift   ;;
      *)            shift                 ;;
    esac
  done

  # Widget sem função de render é erro de programação no arquivo do widget.
  # Rejeita agora, em vez de falhar depois com um "command not found" obscuro
  # no meio de um repaint.
  if [ -z "$render" ]; then
    return 1
  fi

  slug="$(_sl_slug "$name")"
  eval "_W_RENDER_$slug=\$render"
  eval "_W_COLOR_$slug=\$color"
  eval "_W_DESC_$slug=\$desc"
  eval "_W_SELFCOLOR_$slug=\$selfcolor"
  SL_WIDGET_LIST="$SL_WIDGET_LIST $name"
  return 0
}

sl_widget_attr() {
  local attr="$1" name="$2" var
  var="_W_${attr}_$(_sl_slug "$name")"
  printf '%s' "${!var}"
}

sl_widget_registered() {
  local var="_W_RENDER_$(_sl_slug "$1")"
  [ -n "${!var}" ]
}

# ── Montagem de linhas ──
#
# Widget que renderiza vazio desaparece sem deixar separador órfão: o separador
# só é emitido antes de um segmento quando já havia algo escrito na linha.
#
# A captura usa command substitution, decidida por medição na Task 4 (3,5 ms
# por repaint contra a alternativa sem subshell, abaixo do limiar de 5 ms).
# Ver docs/superpowers/decisions/2026-08-08-canal-de-retorno.md.

sl_render_line() {
  local name fn color selfcolor out line="" sep

  sep=" ${SL_CONFIG_SEP:-|} "

  for name in "$@"; do
    sl_widget_registered "$name" || continue

    fn="$(sl_widget_attr RENDER "$name")"

    # Widget que falha vira widget vazio. O resto da linha sobrevive.
    out="$("$fn" 2>/dev/null)" || out=""

    [ -n "$out" ] || continue

    selfcolor="$(sl_widget_attr SELFCOLOR "$name")"
    if [ "$selfcolor" != "1" ]; then
      color="$(sl_config_widget_opt "$name" color)"
      [ -n "$color" ] || color="$(sl_widget_attr COLOR "$name")"
      if [ -n "$color" ]; then
        out="$(sl_color "$color")$out$SL_RESET"
      fi
    fi

    if [ -n "$line" ]; then
      line="$line$sep$out"
    else
      line="$out"
    fi
  done

  printf '%s' "$line"
}

# A statusline nunca pode sair vazia. Vazio é indistinguível de "plugin morto",
# e o usuário não tem como saber a diferença olhando para o terminal. Por isso
# esta função acumula as linhas em memória em vez de imprimir direto: só depois
# de saber que nada renderizou é que dá para decidir o que colocar no lugar.
#
# Dois sinais distintos, com causas distintas:
#   ⚠  algo de entrada falhou — stdin ilegível ou config malformada. É erro do
#      ambiente, não do plugin, e o usuário é quem tem como consertar.
#   —  tudo renderizou vazio sem erro — apenas nada a dizer

sl_render_all() {
  local widgets out all="" first=1 mark=""

  if [ "${SL_JQ_OK:-1}" != "1" ] || [ -n "$SL_CONFIG_WARN" ]; then
    mark="$(sl_color yellow)⚠$SL_RESET"
  fi

  while IFS= read -r widgets; do
    [ -n "$widgets" ] || continue
    out="$(sl_render_line $widgets)"
    [ -n "$out" ] || continue
    if [ "$first" = "1" ]; then
      first=0
      # O marcador entra na primeira linha que de fato tem conteúdo, não em uma
      # linha própria: ele qualifica o que está sendo mostrado.
      if [ -n "$mark" ]; then out="$mark $out"; fi
      all="$out"
    else
      all="$all
$out"
    fi
  done <<EOF
$SL_CONFIG_LINES
EOF

  if [ -z "$all" ]; then
    all="$mark"
    # As chaves em ${SL_DIM} são obrigatórias: o bash 3.2 aceita bytes acima de
    # 127 como parte de nome de variável, então "$SL_DIM—" vira a variável
    # `SL_DIM\xE2`, que não existe. Ver widgets/rate-forecast.sh.
    [ -n "$all" ] || all="${SL_DIM}—${SL_RESET}"
  fi

  printf '%s\n' "$all"
}

# ── Por que existe um invólucro para o jq ──
#
# O jq compilado para Windows abre a saída em modo texto e traduz cada `\n` em
# `\r\n`. Medido no runner windows-latest, sob Git Bash:
#
#   jq -r '.model.display_name' fixture.json | od -c
#   0000000   O   p   u   s       5  \r  \n
#
# O `$(...)` do shell remove a quebra de linha final, mas não o `\r` que sobrou
# antes dela. O estrago é silencioso e desproporcional: em lib/stdin.sh a saída
# do jq é uma lista de atribuições que vai para `eval`, então um `\r` no fim de
# cada linha contamina TODOS os campos da sessão de uma vez — no runner, o
# widget do modelo sumia inteiro da statusline, e a comparação com "Opus 5"
# falhava sem que a string parecesse diferente em nenhum log.
#
# Nada disso aparece em macOS ou Linux, onde não existe modo texto.
#
# O invólucro repassa os argumentos e o stdin sem interpretar, então serve a
# todas as formas de chamada já usadas — com arquivo, com pipe, com --arg.
# O status devolvido é o do jq, não o do `tr`. Num pipeline o shell reporta o
# status do ÚLTIMO comando, e o `tr` tem sucesso mesmo quando o jq recusou a
# entrada — lib/config.sh usa `jq -e .` justamente para validar JSON, e sem isto
# ela aceitaria qualquer lixo como configuração válida.
sl_jq() {
  local st
  jq "$@" | tr -d '\r'
  st=${PIPESTATUS[0]}
  return "$st"
}
