#!/usr/bin/env bash
# launcher — resolve QUAL cópia do plugin executa e delega para ela.
#
# Existe por causa de um detalhe da instalação: o plugin é instalado num caminho
# que carrega a versão,
#
#   ~/.claude/plugins/cache/<marketplace>/claude-code-statusline/0.2.0/bin/statusline.sh
#
# e o `settings.json` não expande variáveis de plugin — logo o caminho ali é
# absoluto e literal. Sem este intermediário, toda release nova deixa o
# `settings.json` apontando para uma versão que não existe mais, e a statusline
# some até o usuário rodar o setup de novo.
#
# O `settings.json` passa a apontar para cá, uma vez, e este arquivo resolve a
# versão a cada repaint. Instalar uma versão nova passa a não exigir nada.
#
# O segundo uso é desenvolvimento. Com o checkout local cravado no
# `settings.json`, é fácil passar semanas rodando código não publicado achando
# que se está usando o plugin instalado — e não notar que algo só funciona por
# causa de um arquivo que existe apenas nesta máquina. Aqui a troca é explícita
# e reversível num repaint:
#
#   echo ~/Projects/nidelson/claude-code-statusline > ~/.claude/statusline-dev
#   rm ~/.claude/statusline-dev
#
# Como todo entrypoint deste plugin, nunca usa `set -e`: um retorno diferente de
# zero apagaria a statusline do usuário.

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEV_FLAG="$CONFIG_DIR/statusline-dev"

# `exec` mantém o stdin: o JSON de sessão que o Claude Code envia chega ao alvo
# sem precisar ser lido e reemitido aqui.

# ── Desenvolvimento ──
# A primeira linha do arquivo é a raiz do checkout. O resto é ignorado, então
# dá para deixar um comentário abaixo lembrando por que a flag está ligada.
if [ -f "$DEV_FLAG" ]; then
  dev_root=$(head -1 "$DEV_FLAG" 2>/dev/null)
  case "$dev_root" in
    "~/"*) dev_root="$HOME/${dev_root#\~/}" ;;
  esac
  if [ -n "$dev_root" ] && [ -f "$dev_root/bin/statusline.sh" ]; then
    exec bash "$dev_root/bin/statusline.sh" "$@"
  fi
  # A flag existe mas não aponta para um checkout utilizável. Cair em silêncio
  # para produção seria o pior resultado: a mudança que se está testando
  # simplesmente não apareceria, e a statusline continuaria plausível.
  printf '⚠ statusline-dev aponta para %s, sem bin/statusline.sh\n' "${dev_root:-<vazio>}"
  exit 0
fi

# ── Produção ──
# Varre todos os marketplaces: o plugin pode ter sido instalado por qualquer um,
# e o nome do marketplace faz parte do caminho do cache.
best=""
best_version=""
for candidate in "$CONFIG_DIR"/plugins/cache/*/claude-code-statusline/*/bin/statusline.sh; do
  [ -f "$candidate" ] || continue
  version=${candidate%/bin/statusline.sh}
  version=${version##*/}
  # `sort -V` ordena 0.10.0 depois de 0.9.0, que é o ponto — a ordem
  # lexicográfica erraria exatamente aí.
  if [ -z "$best_version" ] ||
     [ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -1)" = "$version" ]; then
    best_version=$version
    best=$candidate
  fi
done

if [ -n "$best" ]; then
  exec bash "$best" "$@"
fi

# Nenhuma cópia encontrada. Dizer isso é melhor que imprimir nada: uma
# statusline vazia é indistinguível de uma que está funcionando e não tem o que
# mostrar, e o usuário não teria por onde começar a investigar.
printf '⚠ claude-code-statusline não instalado (nem %s)\n' "$DEV_FLAG"
exit 0
