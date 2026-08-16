# Saúde do sprint, para projetos que mantêm o estado do sprint em arquivo.
#
#   7/10   stories concluídas sobre o total, nos epics ativos
#   ▸2     stories prontas para desenvolvimento — a fila
#   ⊙1     stories aguardando review
#
# Este é o widget de metodologia: os outros descrevem a máquina, este descreve o
# trabalho. Some sozinho em projeto que não usa a convenção, sem precisar ser
# desativado na configuração — se o arquivo não existe, não há o que dizer.
#
# ── O parse mora fora ──
#
# Ler o formato do sprint exige um parser, e formato de metodologia é coisa que
# cada equipe adapta. Então o widget não parseia nada: chama um helper externo e
# consome três números. Trocar de metodologia é trocar o helper, sem tocar no
# plugin. Mesmo arranjo do rate-forecast.
#
# Contrato do helper:
#   <bin> <caminho/do/arquivo>
#   stdout: "<done>/<total> <ready> <review>"
#           vazio quando não há sprint ativo — não é erro
#   exit:   0 sempre
#
# ── A sentinela aqui é um arquivo de verdade ──
#
# Ao contrário da sujeira da árvore de trabalho, o estado do sprint mora num
# arquivo. Então cache_by_mtime é exato: o parse roda quando o arquivo muda, e
# só então. No caso comum a renderização é um stat mais uma leitura.
#
# ── Nota sobre o glifo de review ──
#
# O statusline.sh original usava ⚠ para as stories em review. Aqui ⚠ já é o
# marcador de falha de entrada do núcleo, e as duas coisas podem aparecer na
# mesma linha — story em review não é erro, é estado de fila. Daí o ⊙.

register_widget sprint \
  --render widget_sprint_render \
  --self-color \
  --desc   "Sprint completion, queue and review counts"

# Mesmo caminho que widgets/rate-forecast.sh usa para o helper dele: a raiz
# resolvida por bin/statusline.sh, com o local de instalação como último recurso
# para quem carrega o widget fora dela. Até a v0.3.0 isto apontava direto para
# `$HOME/.claude/`, de quando o helper morava fora do repositório — e o widget
# ficava mudo em toda máquina que não fosse a de quem o escreveu.
: "${SL_SPRINT_BIN:=${SL_ROOT:-$HOME/.claude}/bin/sprint-health-line.sh}"
SL_SPRINT_DEFAULT_PATH="_bmad-output/implementation-artifacts/sprint-status.yaml"

# O nome da metodologia, à frente dos números. Sem ele `34/38 ▸2 ⊙1` é uma
# contagem sem dono: a linha já tem outra razão, a do contexto, e um segundo par
# de números soltos não diz de onde veio.
#
# O padrão é BMAD porque o caminho padrão também é — `_bmad-output/...`. Quem
# troca o helper por outra metodologia troca o rótulo junto, e `""` remove.
SL_SPRINT_DEFAULT_LABEL="BMAD"

_sprint_compute() {
  # `completed` e não `done`: done é palavra reservada do shell. Funciona como
  # nome de variável, mas tropeça a leitura de quem revisa.
  local file="$1" label="$2" raw ratio ready review completed total pct out

  raw="$("$SL_SPRINT_BIN" "$file" 2>/dev/null)" || return 0
  [ -n "$raw" ] || return 0

  # set -- divide nos três campos sem precisar de array.
  set -- $raw
  ratio="$1"; ready="$2"; review="$3"

  completed="${ratio%/*}"
  total="${ratio#*/}"
  # Helper com saída inesperada não pode inventar números de sprint.
  case "$completed" in ""|*[!0-9]*) return 0 ;; esac
  case "$total" in ""|*[!0-9]*) return 0 ;; esac
  [ "$total" -gt 0 ] || return 0

  pct="$(sl_pct "$completed" "$total")" || return 0
  if [ "$pct" -ge 80 ]; then
    out="$(sl_color green)"
  elif [ "$pct" -ge 40 ]; then
    out="$(sl_color yellow)"
  else
    out="$(sl_color red)"
  fi
  out="${out}${ratio}${SL_RESET}"

  case "$ready" in
    ""|*[!0-9]*) ready=0 ;;
  esac
  if [ "$ready" -gt 0 ]; then
    out="${out} $(sl_color cyan)▸${ready}${SL_RESET}"
  fi

  case "$review" in
    ""|*[!0-9]*) review=0 ;;
  esac
  if [ "$review" -gt 0 ]; then
    out="${out} $(sl_color yellow)⊙${review}${SL_RESET}"
  fi

  # O rótulo sai dim, como o `5h:` do rate-forecast: ele nomeia os números sem
  # disputar com a cor deles, que é semântica.
  [ -n "$label" ] && out="${SL_DIM}${label}${SL_RESET} ${out}"

  printf '%s' "$out"
}

widget_sprint_render() {
  local raw gitdir common top rel file key label

  raw="$(sl_git_paths)"
  [ -n "$raw" ] || return 0

  IFS=$'\t' read -r gitdir common top <<EOF
$raw
EOF

  # O toplevel, e não o repo principal: em worktree cada branch tem o próprio
  # estado de sprint versionado, e é o daquela branch que interessa.
  [ -n "$top" ] || return 0

  label="$(sl_config_widget_opt sprint label "$SL_SPRINT_DEFAULT_LABEL")"
  rel="$(sl_config_widget_opt sprint path "$SL_SPRINT_DEFAULT_PATH")"
  [ -n "$rel" ] || return 0

  file="$top/$rel"
  [ -f "$file" ] || return 0
  [ -x "$SL_SPRINT_BIN" ] || return 0

  # O rótulo entra na chave porque muda a saída: sem ele, trocar a opção não
  # teria efeito até o arquivo de sprint ser tocado — e o mtime tem resolução de
  # um segundo, então nem tocá-lo garantiria. Mesma razão pela qual a chave do
  # flow carrega as opções dele.
  key="sprint-$(printf '%s' "$file|$label" | cksum | cut -d' ' -f1)"
  cache_by_mtime "$key" "$file" _sprint_compute "$file" "$label"
}
