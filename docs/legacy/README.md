# Statuslines originais

Os três scripts que este plugin substitui, preservados como referência de
procedência. O port saiu daqui: comportamento, cores, glifos e a matemática da
barra de contexto foram lidos destes arquivos.

| Arquivo | Origem |
|---|---|
| `statusline.sh` | a versão em uso até a troca; era versionada no repositório de dotfiles |
| `statusline-1.sh` | variação anterior, nunca versionada em lugar nenhum |
| `statusline-2.sh` | a mais recente das três, com a integração do Flow; nunca versionada |

Estão aqui porque duas delas não existiam em git nenhum e seriam perdidas na
limpeza do `~/.claude`. Não são executadas nem testadas — se um dia deixarem de
ter valor histórico, `git rm` resolve.

Diferenças de comportamento entre elas e o plugin estão registradas nos
comentários dos widgets e nas mensagens de commit do port.
