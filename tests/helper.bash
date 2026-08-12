# Resolve a raiz do projeto a partir do caminho DESTE arquivo, não do arquivo de
# teste: o helper está sempre em tests/, enquanto os testes podem estar em
# subdiretórios (tests/widgets/), onde "dirname do teste /.." pararia em tests/.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

# ── Um verde local não é o mesmo verde do CI ──
#
# O bats roda o corpo de cada teste como função, sob `set -e`. No bash 3.2 — o
# único bash do macOS — o errexit não dispara quando um `[[ ]]` falha dentro de
# uma função:
#
#   /bin/bash -c 'set -e; f() { [[ a == b ]]; echo SEGUIU; }; f'
#   SEGUIU
#
# Consequência: no macOS só a ÚLTIMA asserção de cada teste é de fato cobrada.
# Todas as anteriores podem falhar em silêncio. No Linux (bash 5) o mesmo teste
# aborta na primeira que falha, e é lá que a suíte tem valor de portão.
#
# Portanto: `bats -r tests` verde no macOS não prova nada sobre as asserções
# intermediárias. O job Linux do CI é o portão real. Ao escrever um teste novo,
# vale rodá-lo com a asserção invertida uma vez para confirmar que ele sabe
# falhar — sobretudo quando ela não é a última linha.
#
# ── A contraprova vem ANTES, nunca depois ──
#
# Um teste que afirma uma ausência passa sozinho quando a funcionalidade inteira
# está quebrada: `[ "$output" = "" ]` é verdade tanto para "o caso sob teste
# suprime a saída" quanto para "nada nunca renderiza". A defesa é renderizar
# duas vezes no mesmo teste, uma num caso vizinho onde a coisa TEM de aparecer.
#
# A ordem das duas não é estilo. Escrita assim, a contraprova protege a si mesma
# e deixa o teste desprotegido:
#
#   [ "$output" = "" ]              # asserção sob teste — não é cobrada
#   ...
#   [ "$output" = "esperado" ]      # contraprova — a única cobrada
#
# Medido: com essa ordem, uma sabotagem que fazia o widget imprimir `·0s` em vez
# de `·cold` não derrubou teste nenhum. Invertida, derrubou. Contraprova
# primeiro, asserção sob teste na última linha.

# Remove os escapes de cor, para quando o que está sob teste é a ORDEM dos
# pedaços e não a cor deles. Um `[[ $out == *"92% ⟳ 20d"* ]]` só é escrevível
# assim: no output cru há um reset entre os dois.
#
# LC_ALL=C não é detalhe. Sem ele o sed do BSD tenta interpretar o UTF-8 dos
# emoji e aborta com "illegal byte sequence"; com ele o padrão — que é todo
# ASCII — casa por byte e os glifos multibyte passam intactos.
sl_test_plain() {
  printf '%s' "$1" | LC_ALL=C sed $'s/\033\\[[0-9;]*m//g'
}
