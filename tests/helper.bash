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
