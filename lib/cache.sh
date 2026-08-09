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

_sl_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
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
