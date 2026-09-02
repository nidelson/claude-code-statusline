# Configuração do usuário.
#
# Um arquivo ilegível ou malformado nunca é reescrito: o usuário precisa poder
# consertar o próprio arquivo. A degradação acontece só em memória, sinalizada
# por SL_CONFIG_WARN para que a statusline mostre um marcador discreto.

# Mantenha em sincronia com o Passo 5 de commands/setup.md, que escreve este
# mesmo conjunto no arquivo do usuário. São dois caminhos para o mesmo default —
# quem roda o /setup recebe um arquivo, quem só aponta o statusLine.command para
# o entrypoint cai aqui — e vê-los divergir seria descobrir que a statusline
# muda conforme como foi instalada.
#
# As opções por widget não cabem aqui: este fallback é uma lista de linhas, não
# um JSON. Quem chega por este caminho recebe os widgets nos padrões deles, o
# que é a degradação certa — sem arquivo, não há preferência a respeitar.
SL_CONFIG_DEFAULT_LINES='repo branch git-status worktree velocity cache cost flow model
context rate-forecast sprint
tip'
SL_CONFIG_DEFAULT_SEP='|'
# Ícones ligados por padrão. Os glifos usados são Unicode padrão (✻, ◆), não
# Nerd Font — renderizam em qualquer terminal moderno sem exigir fonte extra.
SL_CONFIG_DEFAULT_ICONS='1'

sl_config_path() {
  printf '%s/claude-code-statusline/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# ── Uma leitura, duas passadas de jq ──
#
# Eram cinco: uma para validar o JSON, três para `lines`, `separator` e `icons`,
# mais uma por opção de widget. Cada uma custava dois processos, e o arquivo é o
# mesmo nas cinco. Sobraram duas — o cabeçalho de sl_config_widget_opt_set,
# abaixo, conta por que processo é o recurso que importa aqui.
#
# A validação separada foi junto. Ela existia para não aceitar lixo como
# configuração, e quem faz esse trabalho agora é a própria leitura: um jq que
# recusa a entrada não emite atribuição nenhuma, e sem atribuições o caminho é o
# mesmo de antes — defaults e o marcador de aviso.
sl_config_load() {
  local path="${1:-$(sl_config_path)}" raw meta
  local _SL_CFG_LINES="" _SL_CFG_SEP="" _SL_CFG_ICONS=""

  SL_CONFIG_WARN=""
  SL_CONFIG_RAW=""
  # Zera a tabela de opções de um load anterior, antes de qualquer retorno.
  sl_config_opts_load

  if [ ! -f "$path" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    SL_CONFIG_ICONS="$SL_CONFIG_DEFAULT_ICONS"
    return 0
  fi

  # `read -d ''` lê até o primeiro NUL, isto é, o arquivo inteiro, e devolve
  # não-zero ao topar com o EOF antes dele mesmo tendo preenchido a variável.
  # Um `$(cat ...)` faria o mesmo cobrando um processo e um subshell.
  raw=""
  IFS= read -r -d '' raw < "$path" 2>/dev/null || :

  SL_CONFIG_RAW="$raw"
  sl_config_opts_load

  # Os defaults continuam morando no bash: o jq devolve vazio para o que não
  # está no arquivo, e quem escolhe o que fazer com o vazio é o código abaixo,
  # como era antes.
  meta="$(printf '%s' "$raw" | sl_jq -r '
    @sh "_SL_CFG_LINES=\(.lines // [] | map(join(" ")) | join("\n"))",
    @sh "_SL_CFG_SEP=\(.separator // "")",
    @sh "_SL_CFG_ICONS=\(if .icons == null then "" elif .icons then "1" else "0" end)"
  ' 2>/dev/null)" || meta=""

  if [ -z "$meta" ]; then
    # JSON ilegível, ou jq ausente. O arquivo do usuário nunca é reescrito: a
    # degradação acontece só em memória.
    SL_CONFIG_RAW=""
    sl_config_opts_load
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_SEP="$SL_CONFIG_DEFAULT_SEP"
    SL_CONFIG_ICONS="$SL_CONFIG_DEFAULT_ICONS"
    SL_CONFIG_WARN="config"
    return 0
  fi

  eval "$meta"

  SL_CONFIG_ICONS="${_SL_CFG_ICONS:-$SL_CONFIG_DEFAULT_ICONS}"

  if [ -z "$_SL_CFG_LINES" ]; then
    SL_CONFIG_LINES="$SL_CONFIG_DEFAULT_LINES"
    SL_CONFIG_WARN="config"
  else
    SL_CONFIG_LINES="$_SL_CFG_LINES"
  fi

  SL_CONFIG_SEP="${_SL_CFG_SEP:-$SL_CONFIG_DEFAULT_SEP}"
  return 0
}

# ── Por que a configuração inteira é parseada de uma vez ──
#
# A implementação anterior chamava `jq` uma vez por opção lida, e cada chamada
# custa dois processos: o jq e o `tr` do invólucro `sl_jq`. Medido num repaint
# com doze widgets, eram 22 chamadas — 44 dos 116 processos externos do repaint
# inteiro, 38% do total, só para reler um arquivo de trinta linhas que já estava
# em memória.
#
# O custo importa porque o Claude Code cancela a statusline que ainda está
# rodando quando um novo evento chega. Numa máquina onde criar processo é caro
# — EDR interceptando cada fork, ~16 ms — o repaint passava de três segundos, e
# a statusline desaparecia durante trabalho ativo, voltando quando a sessão
# ficava quieta. O sintoma parecia intermitência; era o relógio.
#
# lib/stdin.sh já tinha resolvido o mesmo problema para o payload da sessão: um
# `jq` só, emitindo atribuições que o `eval` consome. Aqui vale o mesmo, com uma
# diferença — os nomes vêm da configuração do usuário, não de uma lista fixa.
#
# ── Como os nomes viram variáveis ──
#
# bash 3.2 não tem arrays associativos, então cada opção vira uma variável
# `_SL_OPT_<widget>__<chave>`. Nomes de widget trazem hífen (`git-status`) e
# dois-pontos (`command:build`), que não são legais em nome de variável — e o
# `_` já é legal, então trocar todos por `_`, como faz _sl_slug em lib/core.sh,
# faria `a-b` e `a_b` colidirem.
#
# O slug daqui escapa cada caractere como `_` seguido do hex do byte: `_` vira
# `_5F`, `-` vira `_2D`, `:` vira `_3A`. Nenhuma substituição produz dois
# underscores seguidos, então `__` fica livre para separar widget de chave sem
# ambiguidade.
#
# Chaves com qualquer outro caractere são descartadas dentro do jq. Elas não
# formariam nome de variável válido, e o `eval` não pode receber nome que o
# usuário controla sem passar por um filtro.
#
# ── Por que o teste contra null é explícito ──
#
# `// empty` seria o idioma óbvio, e está errado: em jq o `//` cai para o lado
# direito tanto em null quanto em false, então `"tokens": false` sairia vazio —
# indistinguível de "o usuário não configurou nada", e a opção nunca poderia ser
# desligada. Por isso o filtro é `select(.value != null)`: o que não está no
# JSON não vira variável, e `false`, `0` e `""` viram.
#
# É também o que faz o terceiro argumento de sl_config_widget_opt, o default,
# funcionar. bash não distingue "chave ausente" de "chave presente e vazia" —
# as duas chegariam como "". Quem distingue é a existência da variável, testada
# com `${!var+x}`, e é isso que permite a um widget aceitar `"label": ""` para
# esconder o rótulo sem que o próprio default reponha o texto.

SL_CONFIG_OPTS_SRC=""
SL_CONFIG_OPTS_VARS=""

sl_config_opts_load() {
  local assignments var

  # Uma configuração nova não pode herdar opções da anterior. Só quem criou as
  # variáveis sabe quais são, então o jq devolve a lista junto com elas.
  for var in $SL_CONFIG_OPTS_VARS; do unset "$var"; done
  SL_CONFIG_OPTS_VARS=""
  SL_CONFIG_OPTS_SRC="$SL_CONFIG_RAW"

  [ -n "$SL_CONFIG_RAW" ] || return 0

  assignments="$(printf '%s' "$SL_CONFIG_RAW" | sl_jq -r '
    def slug: gsub("_"; "_5F") | gsub("-"; "_2D") | gsub(":"; "_3A");
    def opts:
      (.widgets // {})
      | select(type == "object")
      | to_entries[]
      | select(.key | test("^[A-Za-z0-9_:-]+$"))
      | select(.value | type == "object")
      | .key as $w
      | .value
      | to_entries[]
      | select(.key | test("^[A-Za-z0-9_:-]+$"))
      | select(.value != null)
      | {n: "_SL_OPT_\($w | slug)__\(.key | slug)", v: (.value | tostring)};
    [opts] as $o
    | ($o[] | "\(.n)=\(.v | @sh)"),
      "SL_CONFIG_OPTS_VARS=\([$o[].n] | join(" ") | @sh)"
  ' 2>/dev/null)" || assignments=""
  # O `|| assignments=""` importa pelo mesmo motivo que em lib/stdin.sh: a
  # command substitution carrega o status do pipeline, e sob um chamador com
  # `set -e` uma falha do jq abortaria esta função antes do fallback.

  [ -n "$assignments" ] || return 0

  eval "$assignments"
  return 0
}

# Devolve por variável, em SL_CONFIG_OPT, pelo mesmo motivo de sl_color_set em
# lib/colors.sh: lib/core.sh lê a cor de cada widget no caminho quente, e um
# `$( )` por widget é exatamente o custo que esta mudança veio remover.
sl_config_widget_opt_set() {
  local widget="$1" key="$2" default="$3" w k var

  # Rede de segurança para quem monta SL_CONFIG_RAW à mão sem passar por
  # sl_config_load — os testes fazem isso. No caminho normal a comparação bate e
  # nada é reparseado, o que não é detalhe: quase toda chamada acontece dentro
  # de `$( )`, e um parse feito ali dentro morreria com a subshell, deixando o
  # custo por chamada exatamente onde estava.
  [ "$SL_CONFIG_OPTS_SRC" = "$SL_CONFIG_RAW" ] || sl_config_opts_load

  w="${widget//_/_5F}"; w="${w//-/_2D}"; w="${w//:/_3A}"
  k="${key//_/_5F}";    k="${k//-/_2D}";    k="${k//:/_3A}"
  var="_SL_OPT_${w}__${k}"

  # Um nome que o slug não deu conta de sanear nunca virou variável lá no jq, e
  # a indireção abaixo abortaria com "bad substitution" em vez de cair no
  # default.
  case "$var" in
    *[!A-Za-z0-9_]*) SL_CONFIG_OPT="$default"; return 0 ;;
  esac

  if [ -n "${!var+x}" ]; then
    SL_CONFIG_OPT="${!var}"
  else
    SL_CONFIG_OPT="$default"
  fi
  return 0
}

sl_config_widget_opt() {
  sl_config_widget_opt_set "$@"
  printf '%s' "$SL_CONFIG_OPT"
}
