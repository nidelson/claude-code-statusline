# Duas estratégias de cache, escritas uma vez e reusadas por qualquer widget.
#
# A statusline redesenha a cada poucos segundos em cada terminal aberto, então
# chamadas de git sem cache se multiplicam rápido. Os dois helpers degradam para
# "executa o comando" sempre que algo do cache estiver fora do lugar — nunca
# falham por causa do cache.
#
# Formato do arquivo: primeira linha é o carimbo (mtime ou epoch), o resto é o
# valor. Isso preserva valores de múltiplas linhas.

: "${SL_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline}"

# `stat` não tem sintaxe comum entre as plataformas, e as duas formas não são
# mutuamente exclusivas do jeito que um `||` pressupõe: no BSD, `-f` é o formato
# de saída; no GNU coreutils, `-f` é `--file-system`, uma opção válida que
# descreve o sistema de arquivos e não o arquivo. Encadear
# `stat -f %m || stat -c %Y` funciona no macOS por acidente — a primeira forma
# acerta — e falha no Linux sem erro nenhum: a primeira forma tem sucesso
# devolvendo algo que não é mtime, o fallback nunca roda, e o valor entra no
# cache como se fosse carimbo. O cache então compara carimbos que não descrevem
# o arquivo, e o resultado é que ele deixa de acertar.
#
# A forma é resolvida uma vez, no carregamento, contra um arquivo que
# certamente existe, exigindo dígitos como resposta — sucesso com saída não
# numérica não conta como sucesso. É o mesmo padrão que lib/timefmt.sh usa para
# `date` e widgets/command.sh para `timeout`.
_sl_stat_form_probe() {
  local out
  out="$(stat -f %m "${BASH_SOURCE[0]}" 2>/dev/null)"
  case "$out" in
    ''|*[!0-9]*) ;;
    *) printf 'bsd'; return 0 ;;
  esac
  out="$(stat -c %Y "${BASH_SOURCE[0]}" 2>/dev/null)"
  case "$out" in
    ''|*[!0-9]*) ;;
    *) printf 'gnu'; return 0 ;;
  esac
  printf ''
}
SL_STAT_FORM="$(_sl_stat_form_probe)"

_sl_mtime() {
  local out
  case "$SL_STAT_FORM" in
    bsd) out="$(stat -f %m "$1" 2>/dev/null)" ;;
    gnu) out="$(stat -c %Y "$1" 2>/dev/null)" ;;
    *)   printf '0'; return 0 ;;
  esac
  # Um carimbo não numérico envenenaria a comparação do cache em silêncio. `0`
  # degrada para "sempre recalcula", que é lento e correto.
  case "$out" in
    ''|*[!0-9]*) printf '0' ;;
    *)           printf '%s' "$out" ;;
  esac
}

_sl_cache_file() {
  printf '%s/%s' "$SL_CACHE_DIR" "$1"
}

cache_by_mtime() {
  local key="$1" sentinel="$2"; shift 2
  local file mt cached_mt value

  # Sem sentinela não há com o que comparar; executa e pronto.
  if [ ! -e "$sentinel" ]; then
    "$@"
    return 0
  fi

  mkdir -p "$SL_CACHE_DIR" 2>/dev/null
  file="$(_sl_cache_file "$key")"
  mt="$(_sl_mtime "$sentinel")"

  if [ -f "$file" ]; then
    IFS= read -r cached_mt < "$file"
    if [ "$cached_mt" = "$mt" ]; then
      sed -n '2,$p' "$file"
      return 0
    fi
  fi

  value="$("$@")" || value=""
  printf '%s\n%s' "$mt" "$value" > "$file" 2>/dev/null
  printf '%s' "$value"
}

cache_by_ttl() {
  local key="$1" ttl="$2"; shift 2
  local file now cached_at value

  mkdir -p "$SL_CACHE_DIR" 2>/dev/null
  file="$(_sl_cache_file "$key")"
  now="$(date +%s)"

  if [ -f "$file" ] && [ "$ttl" -gt 0 ]; then
    IFS= read -r cached_at < "$file"
    if [ $((now - cached_at)) -lt "$ttl" ]; then
      sed -n '2,$p' "$file"
      return 0
    fi
  fi

  value="$("$@")" || value=""
  printf '%s\n%s' "$now" "$value" > "$file" 2>/dev/null
  printf '%s' "$value"
}
