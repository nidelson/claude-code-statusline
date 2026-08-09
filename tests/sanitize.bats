load helper

setup() {
  source "$PROJECT_ROOT/lib/sanitize.sh"
  E=$'\033'
  BEL=$'\007'
}

@test "plain text passes through untouched" {
  [ "$(printf 'hello world' | sl_sanitize)" = "hello world" ]
}

@test "strips a colour sequence by default" {
  [ "$(printf '%s[31mred%s[0m' "$E" "$E" | sl_sanitize)" = "red" ]
}

@test "keeps colour sequences in colors mode" {
  # Chamada direta, não via `run bash -c`: um bash novo não conhece a função.
  got="$(printf '%s[31mred%s[0m' "$E" "$E" | sl_sanitize colors)"
  [ "$got" = "$(printf '%s[31mred%s[0m' "$E" "$E")" ]
}

@test "strips cursor movement even in colors mode" {
  # CSI H reposiciona o cursor: embaralharia a tela inteira.
  [ "$(printf '%s[2Jclean' "$E" | sl_sanitize colors)" = "clean" ]
}

@test "strips an OSC clipboard write" {
  # OSC 52 escreve na área de transferência do usuário. É o pior caso.
  [ "$(printf '%s]52;c;cGF5bG9hZA==%stexto' "$E" "$BEL" | sl_sanitize)" = "texto" ]
}

@test "strips an OSC clipboard write in colors mode too" {
  [ "$(printf '%s]52;c;cGF5bG9hZA==%stexto' "$E" "$BEL" | sl_sanitize colors)" = "texto" ]
}

@test "strips a window title change" {
  [ "$(printf '%s]0;titulo falso%sok' "$E" "$BEL" | sl_sanitize)" = "ok" ]
}

@test "strips an OSC terminated by string terminator" {
  [ "$(printf '%s]0;x%s\\ok' "$E" "$E" | sl_sanitize)" = "ok" ]
}

@test "strips a hyperlink sequence" {
  # OSC 8 é legítimo no widget repo, mas vindo de terceiro é link arbitrário.
  [ "$(printf '%s]8;;http://evil%sclique%s]8;;%s' "$E" "$BEL" "$E" "$BEL" | sl_sanitize)" = "clique" ]
}

@test "collapses a newline into a space" {
  # A statusline monta as próprias linhas; uma quebra vinda de fora desalinha
  # tudo o que vem depois.
  [ "$(printf 'a\nb' | sl_sanitize)" = "a b" ]
}

@test "collapses a carriage return" {
  [ "$(printf 'a\rb' | sl_sanitize)" = "a b" ]
}

@test "removes a bare bell" {
  [ "$(printf 'a%sb' "$BEL" | sl_sanitize)" = "ab" ]
}

@test "removes a null byte" {
  [ "$(printf 'a\000b' | sl_sanitize)" = "ab" ]
}

@test "removes a backspace" {
  # Backspace reescreve o que já foi impresso — dá para forjar texto.
  [ "$(printf 'seguro\010\010\010\010\010\010falso' | sl_sanitize)" = "segurofalso" ]
}

@test "removes an unterminated csi at the end" {
  # Inerte no arquivo, mas no terminal engoliria o que viesse depois.
  [ "$(printf 'texto%s[38;5' "$E" | sl_sanitize)" = "texto" ]
}

@test "removes an unterminated csi at the end in colors mode" {
  [ "$(printf 'texto%s[38;5' "$E" | sl_sanitize colors)" = "texto" ]
}

@test "handles empty input" {
  [ "$(printf '' | sl_sanitize)" = "" ]
}

@test "keeps accented characters" {
  # LC_ALL=C no corte é byte a byte; não pode destroçar UTF-8 no caminho.
  [ "$(printf 'previsão está boa' | sl_sanitize)" = "previsão está boa" ]
}

@test "keeps box drawing characters" {
  [ "$(printf '████░░ 70%%' | sl_sanitize)" = "████░░ 70%" ]
}
