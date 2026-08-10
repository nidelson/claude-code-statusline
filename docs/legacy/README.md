# Statuslines originais

Os três scripts que este plugin substitui, preservados como referência de
procedência. O port saiu daqui: comportamento, cores, glifos e a matemática da
barra de contexto foram lidos destes arquivos.

| Arquivo | Origem |
|---|---|
| `statusline.sh` | a versão em uso até a troca; era versionada no repositório de dotfiles |
| `statusline-2.sh` | a mais recente, com a integração do Flow; nunca versionada |

Eram três arquivos no `~/.claude`, não dois: a `statusline-1.sh` era cópia byte a
byte da `statusline.sh` e não foi arquivada.

Estão aqui porque a `statusline-2.sh` não existia em git nenhum e seria perdida
na limpeza do `~/.claude`. Não são executadas nem testadas — se um dia deixarem de
ter valor histórico, `git rm` resolve.

Diferenças de comportamento entre elas e o plugin estão registradas nos
comentários dos widgets e nas mensagens de commit do port.
