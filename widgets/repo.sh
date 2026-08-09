# Nome do repositório, com hyperlink para o remote.
#
# ── Sempre o repo principal, nunca o worktree ──
#
# O nome sai de basename(dirname(git-common-dir)). Na árvore principal o
# common-dir é <toplevel>/.git, então isso dá o próprio toplevel; num worktree
# linkado o common-dir continua apontando para o .git do repo principal, então
# dá o repo de origem. Uma fórmula só serve aos dois casos, e o widget worktree
# é quem diz em qual worktree você está.
#
# ── OSC 8 ──
#
# \033]8;;<url>\007<texto>\033]8;;\007 transforma o texto em link clicável em
# terminais que suportam. Quem não suporta ignora a sequência — e por isso o
# fallback natural já é o nome puro, sem precisar detectar nada.
#
# O terminador é BEL e não o ST clássico (ESC \) porque BEL tem suporte mais
# amplo, incluindo tmux e terminais antigos.
#
# ── Cache longo ──
#
# Nome de repo e URL de remote são praticamente imutáveis, e descobri-los custa
# dois spawns de git. A chave sai do SL_CWD: mudar de diretório muda a chave, que
# é exatamente quando a resposta pode mudar. TTL alto por isso.
#
# O valor cacheado é "nome<TAB>url", e a montagem do link acontece fora do cache
# — assim ligar ou desligar a opção `link` tem efeito imediato em vez de esperar
# o TTL expirar.

register_widget repo \
  --render widget_repo_render \
  --color  yellow \
  --desc   "Repository name, linked to its remote"

SL_REPO_DEFAULT_TTL=300
SL_REPO_OSC8=$'\033]8;;'
SL_REPO_BEL=$'\007'

# URL de clone para URL navegável. Devolve vazio para qualquer formato que não
# saiba converter — um link errado é pior que nenhum link.
_repo_url_from_remote() {
  local raw="$1" hp host path scheme org rest proj name

  case "$raw" in
    # Azure DevOps por SSH não é derivável trocando ':' por '/': o host web é
    # outro e o path ganha um segmento '_git'.
    #   git@ssh.dev.azure.com:v3/ORG/PROJ/REPO
    *ssh.dev.azure.com*)
      hp="${raw##*v3/}"
      org="${hp%%/*}"; rest="${hp#*/}"
      proj="${rest%%/*}"; name="${rest#*/}"
      if [ "$org" != "$hp" ] && [ "$proj" != "$rest" ] && [ -n "$name" ]; then
        printf 'https://dev.azure.com/%s/%s/_git/%s' "$org" "$proj" "${name%.git}"
      fi
      ;;
    ssh://*|git+ssh://*)
      hp="${raw#*://}"; hp="${hp#*@}"
      host="${hp%%/*}"; path="${hp#*/}"
      host="${host%%:*}"          # porta de SSH não vale para HTTPS
      if [ -n "$host" ] && [ "$path" != "$hp" ]; then
        printf 'https://%s/%s' "$host" "${path%.git}"
      fi
      ;;
    *@*:*)                        # scp-like: user@host:caminho
      hp="${raw#*@}"
      host="${hp%%:*}"; path="${hp#*:}"
      if [ -n "$host" ] && [ -n "$path" ]; then
        printf 'https://%s/%s' "$host" "${path%.git}"
      fi
      ;;
    http://*|https://*)
      scheme="${raw%%://*}"; rest="${raw#*://}"
      # Descarta userinfo. Sem isto, um remote com token embutido viraria um
      # hyperlink com a credencial dentro, visível no terminal e copiável junto.
      rest="${rest#*@}"
      printf '%s://%s' "$scheme" "${rest%.git}"
      ;;
  esac
}

_repo_compute() {
  local common="$1" top name url

  # dirname e basename por expansão de parâmetro: dois forks a menos num
  # caminho que roda com o cache frio.
  top="${common%/*}"
  name="${top##*/}"
  [ -n "$name" ] || return 0

  url="$(_repo_url_from_remote \
    "$(git -C "$SL_CWD" --no-optional-locks remote get-url origin 2>/dev/null)")"

  printf '%s\t%s' "$name" "$url"
}

# Resolve onde estamos antes de calcular. Separado para que a descoberta dos
# caminhos também caia dentro do cache deste widget.
_repo_resolve() {
  local raw gitdir common top

  raw="$(sl_git_paths)"
  [ -n "$raw" ] || return 0

  IFS=$'\t' read -r gitdir common top <<EOF
$raw
EOF

  [ -n "$common" ] || return 0
  _repo_compute "$common"
}

widget_repo_render() {
  local ttl key raw name url link

  [ -n "$SL_CWD" ] && [ -d "$SL_CWD" ] || return 0

  ttl="$(sl_config_widget_opt repo ttl "$SL_REPO_DEFAULT_TTL")"
  case "$ttl" in
    ""|*[!0-9]*) ttl="$SL_REPO_DEFAULT_TTL" ;;
  esac

  key="repo-$(printf '%s' "$SL_CWD" | cksum | cut -d' ' -f1)"
  raw="$(cache_by_ttl "$key" "$ttl" _repo_resolve)"
  [ -n "$raw" ] || return 0

  name="${raw%%	*}"
  url="${raw#*	}"
  # Sem tabulação na string, o corte acima devolveria a string inteira.
  [ "$url" = "$raw" ] && url=""

  [ -n "$name" ] || return 0

  link="$(sl_config_widget_opt repo link "true")"
  if [ -n "$url" ] && [ "$link" != "false" ]; then
    printf '%s%s%s%s%s%s' \
      "$SL_REPO_OSC8" "$url" "$SL_REPO_BEL" \
      "$name" \
      "$SL_REPO_OSC8" "$SL_REPO_BEL"
  else
    printf '%s' "$name"
  fi
}
