load helper

# Testes do helper de sprint. Ele é o único ponto do plugin que lê um arquivo de
# metodologia, e erra em silêncio por contrato — saída vazia é resposta válida em
# quatro situações distintas. Por isso quase todo teste aqui começa por uma
# contraprova: sem ela, um helper completamente quebrado passaria em metade da
# suíte.

setup() {
  BIN="$PROJECT_ROOT/bin/sprint-health-line.sh"
  YAML="$BATS_TEST_TMPDIR/sprint-status.yaml"
}

# Escreve um yaml com as linhas dadas dentro de development_status. A indentação
# entra aqui e não em cada teste: o que separa epic de story é o nome, não o
# recuo, e deixar isso implícito manteria os testes legíveis.
write_status() {
  {
    printf 'development_status:\n'
    for line in "$@"; do printf '  %s\n' "$line"; done
  } > "$YAML"
}

health() {
  bash "$BIN" "$YAML"
}

@test "counts done, ready and review of the active epic" {
  write_status \
    'epic-1: in-progress' \
    '1-1-primeira: done' \
    '1-2-segunda: done' \
    '1-3-terceira: ready-for-dev' \
    '1-4-quarta: review' \
    '1-5-quinta: backlog'
  [ "$(health)" = "2/5 1 1" ]
}

@test "ignores stories of epics that are not in progress" {
  # Contraprova: com os dois epics ativos, as quatro stories contam.
  write_status \
    'epic-1: in-progress' 'epic-2: in-progress' \
    '1-1-a: done' '1-2-b: done' '2-1-c: done' '2-2-d: backlog'
  [ "$(health)" = "3/4 0 0" ]
  # Sob teste: com o epic-2 em backlog, as stories dele saem da conta.
  write_status \
    'epic-1: in-progress' 'epic-2: backlog' \
    '1-1-a: done' '1-2-b: done' '2-1-c: done' '2-2-d: backlog'
  [ "$(health)" = "2/2 0 0" ]
}

@test "produces nothing when no epic is in progress" {
  write_status 'epic-1: in-progress' '1-1-a: done'
  [ "$(health)" = "1/1 0 0" ]
  write_status 'epic-1: backlog' '1-1-a: done'
  [ "$(health)" = "" ]
}

@test "produces nothing when the active epic has no story" {
  write_status 'epic-1: in-progress' '1-1-a: done'
  [ "$(health)" = "1/1 0 0" ]
  # O epic está ativo, mas nenhuma story pertence a ele: o `2-` aponta para o
  # epic-2, que nem existe no arquivo.
  write_status 'epic-1: in-progress' '2-1-a: done'
  [ "$(health)" = "" ]
}

@test "produces nothing and exits zero for a missing file" {
  write_status 'epic-1: in-progress' '1-1-a: done'
  [ "$(health)" = "1/1 0 0" ]
  YAML="$BATS_TEST_TMPDIR/nao-existe.yaml"
  run health
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "reads a file shaped like a real sprint-status.yaml" {
  # Um arquivo com a forma completa: cabeçalho antes da seção, comentários de
  # bloco, retrospectivas ao lado de cada epic, epics em três estados e outra
  # seção depois. Nenhum dos testes acima sozinho prova que as regras convivem;
  # este prova, e é o que uma sabotagem larga derruba primeiro.
  cat > "$YAML" <<'EOF'
generated: 2026-08-16
sprint: 12

development_status:
  # Epic 0 fechado na sprint passada.
  epic-0: done
  0-1-tokens: done
  epic-0-retrospective: optional

  epic-1: in-progress
  1-1-login: done
  1-2-cache: done
  1-3-wizard: ready-for-dev
  1-4-rbac: review          # aguardando revisão do time
  1-5-crud: backlog
  epic-1-retrospective: optional

  epic-2: in-progress
  2-1-schema: done
  2-2-engine: backlog
  epic-2-retrospective: optional

  epic-3: backlog
  3-1-nunca-comeca: backlog

notes:
  9-9-fora-da-secao: done
EOF
  # done: 1-1, 1-2, 2-1. total: as cinco do epic-1 mais as duas do epic-2.
  # Fora: tudo do epic-0 (done), do epic-3 (backlog) e a seção `notes`.
  [ "$(health)" = "3/7 1 1" ]
}

@test "strips inline comments instead of reading them as values" {
  write_status 'epic-1: in-progress' '1-1-a: done # concluída na sprint passada'
  # Sem o corte, o valor seria "done # concluída..." e não casaria com "done":
  # a story contaria no total e não no done, saindo "0/1 0 0".
  [ "$(health)" = "1/1 0 0" ]
}

@test "ignores comment-only lines" {
  write_status 'epic-1: in-progress' '# 1-9-fantasma: done' '1-1-a: done'
  [ "$(health)" = "1/1 0 0" ]
}

@test "stops at the first top-level key after the section" {
  # Contraprova: dentro da seção, a story conta.
  write_status 'epic-1: in-progress' '1-1-a: done' '1-2-b: done'
  [ "$(health)" = "2/2 0 0" ]
  # Sob teste: o mesmo par de linhas depois de outra chave de nível zero é
  # ignorado. Um arquivo BMAD traz outras seções abaixo desta.
  {
    printf 'development_status:\n'
    printf '  epic-1: in-progress\n'
    printf '  1-1-a: done\n'
    printf 'outra_secao:\n'
    printf '  1-2-b: done\n'
  } > "$YAML"
  [ "$(health)" = "1/1 0 0" ]
}

@test "blank lines do not end the section" {
  # Linha em branco separa epics dentro do bloco; tratá-la como fim cortaria
  # tudo a partir do primeiro respiro do arquivo.
  {
    printf 'development_status:\n'
    printf '  epic-1: in-progress\n'
    printf '  1-1-a: done\n'
    printf '\n'
    printf '  epic-2: in-progress\n'
    printf '  2-1-b: done\n'
  } > "$YAML"
  [ "$(health)" = "2/2 0 0" ]
}

@test "reads a file with CRLF line endings" {
  # Contraprova: com LF o arquivo equivalente conta a story como done.
  write_status 'epic-1: in-progress' '1-1-a: done'
  [ "$(health)" = "1/1 0 0" ]
  # Sob teste: com CRLF, o "\r" ficaria colado em "done" e a comparação falharia
  # em silêncio — a story contaria no total e não no done. É o arquivo que o
  # Git Bash entrega no Windows.
  printf 'development_status:\r\n  epic-1: in-progress\r\n  1-1-a: done\r\n' > "$YAML"
  [ "$(health)" = "1/1 0 0" ]
}
