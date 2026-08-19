# A dica que explica o bloqueio projetado.
#
# Este widget não mostra dado novo: ele explica o que a linha de cima já mostra.
# `Flow 💰 25%→116% 🔒 sex·2d8h` é denso e correto, e ilegível na primeira vez —
# a leitura intuitiva de `25%` ao lado de `116%` é "gastei 25 de 116", que é o
# contrário do que a linha afirma. A dica corrige isso, diz quanto o ritmo
# precisa cair, e some no próximo prompt do usuário.
#
# Nada no resto da barra muda. O layout existente já foi aprendido por quem o
# usa, e uma feature que o diluísse estaria competindo com o que deveria estar
# explicando.
#
# ── Por que ele fica sozinho numa linha ──
#
# Quando duas fontes projetam bloqueio, o widget emite duas linhas separadas por
# `\n`, e o núcleo as preserva. Dividindo a linha com outro widget, esse `\n`
# quebraria a montagem de separadores no meio. A configuração padrão o põe numa
# linha própria; linha que renderiza vazio não é desenhada — a mesma regra que
# já faz o `→48%` verde não aparecer — então ela não custa nada enquanto não há
# o que dizer.
#
# ── Por que ele lê as fontes de novo ──
#
# O caminho óbvio seria `flow` e `rate-forecast` publicarem o que já
# calcularam. Não funciona: o núcleo captura widget com `out="$("$fn")"`, que é
# subshell, e global atribuída lá dentro morre no retorno. É o isolamento que
# docs/superpowers/decisions/2026-08-08-canal-de-retorno.md celebra, valendo
# contra nós.
#
# Spec: docs/superpowers/specs/2026-08-18-tips-bloqueio-projetado-design.md

register_widget tip \
  --render widget_tip_render \
  --self-color \
  --desc   "Explains a projected quota block and how much to slow down"

# Uma fonte: chama, compara a chave com a gravada, decide.
_tip_one() {
  local src="$1" fn out key phrase prev pkey ppid pid

  fn="_tip_src_$(_tip_slug "$src")"
  command -v "$fn" >/dev/null 2>&1 || return 1

  if prev="$(_tip_state_get "$src")"; then
    pkey="${prev%% *}"
    ppid="${prev#* }"
  else
    pkey=""; ppid=""
  fi

  out="$("$fn" "$pkey")" || return 1
  key="${out%%	*}"
  phrase="${out#*	}"
  [ -n "$phrase" ] || return 1

  pid="$(_tip_prompt_id)" || pid="-"

  # Chave nova carimba o turno corrente — é assim que a dica reaparece quando
  # algo piorou, sem precisar de código de reexibição. Chave igual só continua
  # na tela enquanto o turno for o mesmo.
  if [ "$key" != "$pkey" ]; then
    _tip_state_put "$src" "$key" "$pid"
  else
    [ "$pid" = "$ppid" ] || return 1
  fi

  printf '%s' "$phrase"
}

widget_tip_render() {
  local src piece out=""

  # Ordem fixa, vinda da lista: que ela seja estável importa mais do que qual
  # ela é — uma linha que troca de lugar entre repaints é lida como mudança, e a
  # dica existe justamente para o momento em que algo mudou.
  for src in $SL_TIP_SOURCES; do
    if piece="$(_tip_one "$src")"; then
      out="${out}${out:+
}${piece}"
    else
      # Fonte que parou de ter o que dizer esquece o que disse, e volta a falar
      # do zero se a condição retornar.
      _tip_state_drop "$src"
    fi
  done

  [ -n "$out" ] || return 0
  printf '%s' "$out"
}
