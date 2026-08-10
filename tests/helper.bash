# Resolve a raiz do projeto a partir do caminho DESTE arquivo, não do arquivo de
# teste: o helper está sempre em tests/, enquanto os testes podem estar em
# subdiretórios (tests/widgets/), onde "dirname do teste /.." pararia em tests/.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT
