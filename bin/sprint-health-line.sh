#!/usr/bin/env bash
# Saúde do sprint BMAD, agregada numa linha.
#
#   sprint-health-line.sh <caminho/para/sprint-status.yaml>
#
# stdout: "<done>/<total> <ready> <review>", contando apenas as stories dos epics
#         em andamento. Vazio quando não há epic ativo, quando esses epics não
#         têm story, ou quando o arquivo não existe — nenhum desses é erro.
# exit:   0 sempre. Nenhuma falha pode quebrar a statusline.
#
# É o helper que widgets/sprint.sh chama, e o contrato acima é toda a fronteira
# entre os dois. Trocar de metodologia é trocar este arquivo por outro que
# escreva os mesmos três campos, apontando SL_SPRINT_BIN para ele.
#
# ── Sem python3 ──
#
# A versão original deste script embutia um parser em python3. Aqui ele é awk,
# pela mesma razão registrada em lib/timefmt.sh e no plano do rate-forecast: as
# dependências de runtime do plugin são `jq` e `git`, e uma statusline que exige
# um interpretador a mais fica muda onde ele não está. O Git Bash do Windows é o
# caso concreto — plataforma suportada e testada em CI, e python3 raramente
# presente nela. O awk é POSIX e acompanha os três sistemas.
#
# ── Por que não é um parser de YAML ──
#
# Um YAML de verdade tem âncoras, blocos, listas, tipos. Nada disso aparece na
# seção que interessa: `development_status` é um mapa plano de `chave: valor`,
# uma linha cada. Ler só isso com dois regex é honesto sobre o que o script faz,
# e não finge suportar um arquivo arbitrário. Qualquer coisa fora do formato é
# ignorada em silêncio, que é o comportamento certo para quem alimenta uma
# statusline.

yaml="$1"
[ -f "$yaml" ] || exit 0

awk '
  function trim(s) {
    sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s
  }

  # A story carrega o número do epic no próprio nome: "2-6-1-paradata" pertence
  # ao "epic-2". Não há campo de vínculo no arquivo, e é assim que a convenção
  # BMAD amarra os dois.
  function parent(key) {
    if (match(key, /^[0-9]+-/)) return "epic-" substr(key, 1, RLENGTH - 1)
    return ""
  }

  # O CI roda no Git Bash, onde o arquivo pode chegar com CRLF. Sem isto o "\r"
  # entra no valor e nenhuma comparação com "done" casa — falha silenciosa, que
  # é a pior forma desta função errar.
  { sub(/\r$/, "") }

  /^development_status:[ \t]*$/ { in_dev = 1; next }

  # A seção termina na primeira linha de nível zero. Linha em branco não a
  # encerra — ela separa os epics dentro do próprio bloco — e isso sai de graça:
  # `^[^ \t]` exige um caractere, e a linha vazia não tem nenhum.
  in_dev && /^[^ \t]/ { in_dev = 0 }
  !in_dev { next }

  {
    line = $0
    sub(/#.*/, "", line)          # comentário inline, e linhas que só têm comentário
    pos = index(line, ":")
    if (pos == 0) next
    # Corta no primeiro ":" e não em campos separados por espaço: o valor pode
    # conter ":" e o nome da story frequentemente contém "-".
    k = trim(substr(line, 1, pos - 1))
    v = trim(substr(line, pos + 1))
    if (k == "" || v == "") next

    # `epic-1-retrospective`, que o formato traz ao lado de cada epic, não casa
    # nenhum dos dois: o primeiro regex exige fim logo após o número, e o segundo
    # exige começo com dígito. Não há guarda para ela porque não é preciso.
    if (k ~ /^(epic|tw)-[0-9]+$/) {
      epic[k] = v
    } else if (k ~ /^[0-9]/) {
      story[k] = v
    }
  }

  END {
    for (k in epic)
      if (epic[k] == "in-progress") active[k] = 1

    for (k in story) {
      p = parent(k)
      if (p == "" || !(p in active)) continue
      total++
      if      (story[k] == "done")          done++
      else if (story[k] == "ready-for-dev") ready++
      else if (story[k] == "review")        review++
    }

    # Sem epic ativo, `active` fica vazio e nenhuma story é contada — o mesmo
    # caminho já cobre os dois casos de "nada a dizer".
    if (total > 0) printf "%d/%d %d %d\n", done, total, ready, review
  }
' "$yaml"
