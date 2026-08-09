# Higienização de saída de terceiros.
#
# O widget `command` coloca no terminal a saída de um programa que o plugin não
# escreveu. Sequências de escape não são decoração: OSC 52 escreve na área de
# transferência do usuário, OSC 0 e 2 trocam o título da janela, e CSI move o
# cursor e pode embaralhar a tela inteira. Nada disso pode atravessar por
# acidente.
#
# Por isso o padrão é remover tudo. O modo `colors` abre uma exceção estreita —
# apenas SGR, o CSI terminado em `m`, que só muda cor e estilo — e continua
# removendo o resto.
#
# Quebras de linha também somem: a statusline monta as próprias linhas, e uma
# quebra vinda de fora desalinharia tudo o que vem depois.

SL_SANITIZE_ESC=$'\033'
SL_SANITIZE_BEL=$'\007'

# Lê stdin, escreve stdout. $1 = strip (padrão) ou colors.
sl_sanitize() {
  local mode="${1:-strip}" e="$SL_SANITIZE_ESC" bel="$SL_SANITIZE_BEL"
  local osc_bel osc_st csi tail_csi other

  # OSC primeiro: o corpo é texto livre e pode conter colchetes que as regras
  # de CSI comeriam pela metade. Dois terminadores possíveis, BEL e ESC \.
  osc_bel="s/${e}\][^${bel}]*${bel}//g"
  osc_st="s/${e}\][^${e}]*${e}\\\\//g"

  if [ "$mode" = "colors" ]; then
    # Todo CSI cujo byte final NÃO é `m`. A faixa pula o m: @ até l, n até ~.
    csi="s/${e}\[[0-9;?]*[@-ln-~]//g"
    # Catch-all que preserva o `E[` do SGR que sobrou.
    other="s/${e}[^[]//g"
  else
    csi="s/${e}\[[0-9;?]*[@-~]//g"
    other="s/${e}.//g"
  fi

  # CSI sem byte final, no fim da string: inerte no arquivo, mas no terminal
  # engoliria o que viesse depois. O segundo corte pega o ESC solto no fim, que
  # a regra catch-all não alcança por exigir um caractere depois dele.
  tail_csi="s/${e}\[[0-9;?]*$//; s/${e}$//"

  # tr para as quebras e o NUL; sed para as sequências. LC_ALL=C porque o corte
  # é byte a byte e um locale multibyte pode recusar a entrada como inválida.
  LC_ALL=C tr -d '\000' \
    | LC_ALL=C tr '\n\r\t\013\014' '     ' \
    | LC_ALL=C sed -e "$osc_bel" -e "$osc_st" -e "$csi" -e "$tail_csi" -e "$other" \
    | LC_ALL=C tr -d '\001-\010\016-\032\034-\037\177'
  # A faixa pula \033 de propósito. ESC é 27 decimal e cairia dentro de um
  # \016-\037 ingênuo, apagando justamente o SGR que o modo `colors` acabou de
  # preservar. Em `strip` isso passaria despercebido: lá o ESC já saiu no sed.
}
