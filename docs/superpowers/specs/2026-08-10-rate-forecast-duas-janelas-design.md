# rate-forecast com duas janelas — design

> Estende o contrato de widget definido em
> [2026-08-08-statusline-modular-design.md](2026-08-08-statusline-modular-design.md).
> Nada aqui altera o núcleo: é uma mudança contida em `widgets/rate-forecast.sh`.

## Propósito

O widget mostra hoje uma janela de rate limit por vez — `5h:42%→70%` — escolhida
pela opção `window`. As duas janelas que o Claude Code reporta existem no parse
desde a Task 2 (`SL_5H_PCT`, `SL_5H_RESET`, `SL_7D_PCT`, `SL_7D_RESET`), mas só
uma chega à tela.

A janela de 5 horas responde "posso continuar agora". A de 7 dias responde
"quando eu paro". São perguntas diferentes, e ver só a primeira esconde
exatamente o bloqueio que dói — o de dias, que chega sem aviso porque ninguém
olhou.

Faltam também duas informações que o widget já tem em mãos e não usa: o horário
em que a janela reseta e quanto tempo falta. Percentual sem prazo não deixa
decidir nada; `91%` com reset em oito minutos é tranquilo, `91%` com reset em
quatro horas não é.

Nada disso é invenção. A `statusline-2.sh` arquivada em `docs/legacy/` já
mostrava as duas janelas com reset e contagem regressiva; o port para o plugin
perdeu esse comportamento ao reduzir o widget ao caso mínimo da Task 8. Esta
spec recupera o que existia e acrescenta a previsão de estouro, que é nova.

## Escopo

**Entra:** as duas janelas sempre visíveis, cada uma com percentual atual,
projeção de estouro quando houver, horário do reset e contagem regressiva;
coloração independente por número; normalização dos formatos de `resets_at`.

**Não entra:** alertas que interrompem o usuário (isso é hook, não statusline);
mudanças no contrato do helper externo; instâncias parametrizadas de widget
(avaliado e descartado — ver Alternativas).

## Formato

A gramática, com as duas janelas em estado normal:

```
⏱ 5h:31%→93% ⟳02:10·1h48m · 7d:15% ⟳Fri·5d6h
│  │  │   │   │ │     │    │
│  │  │   │   │ │     │    └─ separador entre janelas
│  │  │   │   │ │     └─ contagem regressiva
│  │  │   │   │ └─ horário do reset
│  │  │   │   └─ marca de reset
│  │  │   └─ projeção de estouro ao ritmo atual
│  │  └─ uso atual da janela
│  └─ rótulo da janela
└─ marca do widget
```

Os glifos `⏱` e `⟳` e a pontuação `·` vêm da `statusline-2.sh:262-265`, inclusive
o esmaecimento de tudo que não é percentual. A seta e a projeção são a única
adição.

Estados representativos:

```
tranquilo   ⏱ 5h:12%      ⟳04:55·3h20m · 7d:8%  ⟳Tue·6d2h
normal      ⏱ 5h:31%→93%  ⟳02:10·1h48m · 7d:15% ⟳Fri·5d6h
crítico     ⏱ 5h:91%→118% ⟳02:10·1h48m · 7d:94%→107% ⟳Fri·5d6h
sem ícones  5h:31%→93% 02:10·1h48m · 7d:15% Fri·5d6h
```

A largura fica entre 30 e 48 colunas. É um widget de linha própria ou de linha
pouco povoada; não cabe espremido entre outros seis.

Com `icons: false` na configuração, `⏱` e `⟳` somem e o resto permanece. O
mecanismo já existe: `SL_CONFIG_ICONS` em `lib/config.sh:47`, consumido como
`[ "${SL_CONFIG_ICONS:-1}" = "1" ]` em `widgets/model.sh:29`.

## Decisões

### Sempre visível, nunca condicional

Considerou-se esconder a janela de 7 dias enquanto estivesse calma, seguindo a
regra que o resto do plugin usa — `worktree` some na árvore principal,
`git-status` some com a árvore limpa. Foi descartado.

O motivo é layout. Aqueles widgets aparecem e somem em eventos raros e
significativos; a janela de 7 dias cruzaria o limiar no meio de uma sessão,
empurrando lateralmente tudo à direita, repetidamente, enquanto oscila em torno
do limiar. Uma statusline que muda de largura sozinha custa mais atenção do que
a largura que economiza.

Presença constante tem valor próprio: quem olha o mesmo lugar todo dia aprende o
que é normal, e passa a notar o anormal sem precisar que nada pisque.

### Duas cores no mesmo segmento

O widget é `--self-color` desde o início, porque sua cor é semântica. A mudança é
que ele passa a compor a cor **por número**, não por segmento:

- **uso atual** — verde abaixo de 50, amarelo de 50 a 79, vermelho a partir de
  80. É a escala da original, verificada idêntica em
  `docs/legacy/statusline-2.sh:256-260` e `docs/legacy/statusline.sh:348-350`.
- **projeção** — a cor vem do nível que o helper externo devolve (`ok`, `warn`,
  `crit`), sem reinterpretação.
- **rótulo, reset e regressiva** — sempre esmaecidos. São contexto para os
  números, não competem com eles.

As duas primeiras escalas respondem perguntas diferentes — "quanto já gastei" e
"vou estourar" — e por isso não usam os mesmos limiares. O helper classifica
projeção com `WARN=85` e `CRIT=100`, ajustáveis por `CLAUDE_RATE_WARN` e
`CLAUDE_RATE_CRIT`; o uso atual usa os limiares do widget, ajustáveis na
configuração. Um `31%` verde ao lado de um `→93%` amarelo não é inconsistência: é
uso baixo com ritmo alto, que é precisamente o que se quer enxergar.

A original não tinha quarto nível. Não há tratamento especial para 100% ou mais,
nem negrito: `BOLD` existe na `statusline-2.sh` mas decora apenas repo, branch e
worktree, nunca percentual de rate limit. Acima de 80 tudo é vermelho, e a
projeção carrega a informação de gravidade.

### Tempo é calculado localmente

Horário de reset e regressiva saem de `SL_5H_RESET` e `SL_7D_RESET`. Nenhuma
chamada externa, nenhum subprocesso, nenhum custo por repaint. O helper continua
responsável apenas pela projeção.

**`resets_at` chega em três formatos, e um deles engana.** A original normaliza
todos (`statusline-2.sh:210-219`): epoch em segundos; epoch em **milissegundos**,
detectado por ter 13 ou mais dígitos; e **string ISO 8601**, que ela converte
chamando `python3`. Nosso `lib/stdin.sh` entrega o valor cru. Um epoch em
milissegundos tratado como segundos não falha visivelmente — produz uma data no
ano 57000 e uma regressiva absurda, que é pior do que não mostrar nada.

O widget normaliza antes de qualquer aritmética:

| Entrada | Tratamento |
|---|---|
| `1800000000` | epoch em segundos, usado como está |
| `1800000000000` | 13+ dígitos: dividido por 1000 |
| `1800000000.5` | fração descartada |
| `2026-08-10T02:10:00Z` | convertido, se houver ferramenta; senão os tempos somem |
| qualquer outra coisa | os tempos somem, percentual permanece |

A conversão de ISO 8601 **não** replica a dependência de `python3` da original:
uma statusline que precisa de Python para desenhar contraria a restrição de
runtime do projeto, que é `jq` e `git`. A tentativa usa `date` e, falhando, os
tempos somem — degradação local, sem afetar percentual nem projeção.

**`date` diverge entre plataformas.** A original usa `date -r "$epoch" +%H:%M`,
que é BSD e não existe no GNU coreutils, onde a forma é `date -d "@$epoch"`. A
original rodava só em macOS; o plugin roda também em Ubuntu, no CI. O widget
resolve qual forma funciona uma vez, no carregamento, seguindo o padrão que
`widgets/command.sh:62` já usa para descobrir `timeout`.

A escolha entre horário e dia da semana é **pelo tempo restante, não pela
janela**:

- faltando menos de 24 horas → horário local em 24h: `02:10`
- faltando 24 horas ou mais → dia da semana abreviado: `Fri`

Aqui há divergência deliberada da original, que decide pelo tipo de janela: 5h
sempre com horário, 7d sempre com dia. Isso erra nos extremos — uma janela de 7
dias que reseta daqui a quatro horas mostraria só o nome do dia, quando o
horário é a informação útil. A regra por tempo restante produz saída idêntica no
caso comum e correta nos extremos.

A regressiva mostra as duas unidades mais significativas: `5d6h`, `1h48m`, `48m`.
Abaixo de um minuto, `<1m`.

Nomes de dia saem sob `LC_ALL=C`, para que largura e grafia não mudem com o
locale — mesma razão pela qual `widgets/cost.sh` já formata valores sob
`LC_ALL=C`.

### `window` deixa de escolher e passa a filtrar

A opção existe hoje e há configuração em uso que a define. Permanece válida, com
significado adjacente: **mostrar apenas a janela indicada**.

```jsonc
{ }                       // ambas as janelas
{ "window": "5h" }        // só a de 5 horas — comportamento de hoje
{ "window": "7d" }        // só a de 7 dias
```

Nenhuma configuração existente muda de comportamento, e quem não conhece a opção
recebe as duas janelas sem declarar nada.

## Configuração

| Opção | Valores | Padrão |
|---|---|---|
| `window` | `5h`, `7d`; ausente mostra ambas | ausente |
| `warn` | uso atual a partir do qual pinta amarelo | `50` |
| `crit` | uso atual a partir do qual pinta vermelho | `80` |
| `separator` | texto entre as duas janelas | `·` |
| `reset` | `true`, `false` — mostra horário e regressiva | `true` |

`color` continua sem efeito: a cor é semântica.

## Tratamento de erros

O widget não pode desaparecer nem imprimir lixo por causa de dado ruim. Cada
degradação é local, e a menor possível:

| Situação | Comportamento |
|---|---|
| `SL_5H_PCT` e `SL_7D_PCT` vazios | widget inteiro some — não há o que dizer |
| uma das janelas sem percentual | a outra renderiza sozinha, sem separador órfão |
| percentual com casas decimais | arredondado ao inteiro antes de comparar |
| helper ausente ou não executável | percentuais e tempos aparecem; projeção some |
| helper devolve nível desconhecido | tratado como "sem projeção", nunca como alerta |
| `resets_at` ausente ou ilegível | percentual e projeção aparecem; tempos somem |
| `resets_at` no passado | tempos somem — a janela já virou, o dado é obsoleto |
| `date` sem forma compatível | tempos somem; o resto permanece |

A regra que governa todas: **um pedaço ilegível apaga só a si mesmo**. Nunca a
janela inteira, nunca o widget.

O arredondamento não é detalhe. A fonte traz float — a original documenta ter
recebido `14.000000000000002` — e a comparação inteira de bash quebra com casas
decimais, abortando a função no meio (`statusline-2.sh:202-203`).

## Testes

`tests/widgets/rate-forecast.bats` cresce a partir dos sete casos atuais, que
continuam válidos. Acrescenta:

- as duas janelas renderizadas juntas, com o separador entre elas
- `window: "5h"` e `window: "7d"` produzindo exatamente uma janela cada
- uso atual verde, amarelo e vermelho nos limiares 50 e 80, e nas bordas exatas
- projeção com cor independente do uso atual — o caso `31%` verde com `→93%`
  amarelo, que é a razão de existir da mudança
- percentual float arredondado antes da comparação de cor
- `resets_at` em segundos, em milissegundos, com fração e em ISO 8601
- reset formatado como horário abaixo de 24h e como dia da semana acima
- regressiva em `5d6h`, `1h48m`, `48m` e `<1m`
- `icons: false` removendo `⏱` e `⟳` sem afetar o resto
- cada linha da tabela de erros acima

Tempo é entrada, não relógio: os testes injetam `resets_at` e o instante atual,
como o helper já permite via `CLAUDE_RATE_NOW`. Nenhum teste depende da hora em
que roda nem do fuso da máquina — caso contrário a suíte falharia sozinha às
duas da manhã, ou só no CI, que roda em UTC.

## Alternativas consideradas

**Instâncias parametrizadas de widget.** Nomes como `rate-forecast:5h` e
`rate-forecast:7d` na configuração, cada um com opções próprias, seguindo o
padrão que `widgets/command.sh` já implementa. Daria controle total de layout —
uma janela em cada linha, se quisesse.

Descartada por custo desproporcional. Exigiria generalizar o carregamento em
`bin/statusline.sh`, extrair um registrador de instâncias para `lib/core.sh` e
migrar `command.sh` para ele — três arquivos, um deles testado e funcionando, a
serviço de um único consumidor. O widget composto entrega o mesmo resultado
visual mexendo em um arquivo só.

O padrão continua disponível em `command.sh` para quando um segundo widget
precisar de instâncias de verdade. Aí haverá dois consumidores para justificar a
extração, e o custo se paga.

**Esconder a janela de 7 dias quando calma.** Economizaria largura no caso comum,
ao custo de a linha mudar de tamanho quando o limiar fosse cruzado. Descartada
pela razão de layout descrita acima.

**Mostrar apenas a janela que bloqueia primeiro.** Conceitualmente a leitura mais
útil: uma linha só, sempre a que importa. Exigiria que o helper devolvesse tempo
até o estouro, não percentual projetado — mudança de contrato num script que vive
fora deste repositório. Fica registrada porque é também a base do alerta
"bloqueado em 3d1h", que pertence a um hook e a um roadmap próprio.

## Premissas

Pontos que nem o exemplo de referência nem a original determinam, decididos aqui.
São o primeiro lugar a olhar em caso de discordância:

1. A regressiva mostra `<1m` abaixo de um minuto; a original mostraria `0m`.
2. A escolha entre horário e dia é por tempo restante, não por janela — divergência
   deliberada da original, justificada acima.
3. ISO 8601 é convertido com `date`, não com `python3`, e falha silenciosamente
   para os tempos se nenhuma forma funcionar.
4. Quando `window` está definida, a janela única renderiza sem separador.
5. Os limiares 50 e 80 valem para as duas janelas. A original também os
   compartilhava, ainda que 80% de uma janela de 7 dias e 80% de uma de 5 horas
   tenham urgências bem diferentes.
