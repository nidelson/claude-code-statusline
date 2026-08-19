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

# Tempo é entrada, não relógio — mesma razão de widgets/rate-forecast.sh: sem
# isso a suíte passaria a depender do dia em que roda.
_tip_now() {
  if [ -n "$SL_NOW" ]; then printf '%s' "$SL_NOW"; else date +%s; fi
}

# Uma fonte: colhe, decide e formata. Retorna 1 quando não há o que dizer.
_tip_one() {
  local src="$1" raw proj used blocked reset now phrase

  case "$src" in
    flow) raw="$(_tip_flow_source)"      || return 1 ;;
    *)    raw="$(_tip_rf_source "$src")" || return 1 ;;
  esac

  set -- $raw
  proj="$1"; used="$2"; blocked="$3"; reset="$4"

  # A frase vem ANTES da decisão de mostrar, e a ordem não é estilo: o 5h pode
  # recusar por causa do piso de 15 minutos, e se o estado fosse gravado antes
  # disso a fonte consumiria a virada em silêncio — a dica nunca apareceria,
  # nem quando a pausa ficasse longa o bastante para valer a pena.
  phrase="$(_tip_phrase "$src" "$proj" "$used" "$blocked" "$reset")" || return 1

  now="$(_tip_now)"
  _tip_should_show "$src" "$proj" "$blocked" "$now" || return 1

  printf '%s' "$phrase"
}

widget_tip_render() {
  local src piece out=""

  # Ordem fixa: Flow primeiro, porque a cota do provedor é a que bloqueia por
  # dias; depois a janela mais longa. Que a ordem seja estável importa mais do
  # que qual ela é — uma linha que troca de lugar entre repaints é lida como
  # mudança, e a dica existe justamente para o momento em que algo mudou.
  for src in flow 7d 5h; do
    if piece="$(_tip_one "$src")"; then
      out="${out}${out:+
}${piece}"
    else
      # Fonte que parou de projetar bloqueio esquece o que já disse, e volta a
      # falar do zero se a condição retornar.
      _tip_state_drop "$src"
    fi
  done

  [ -n "$out" ] || return 0
  printf '%s' "$out"
}
