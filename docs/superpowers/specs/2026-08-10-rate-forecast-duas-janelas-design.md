# rate-forecast com duas janelas — design

> Estende o contrato de widget definido em
> [2026-08-08-statusline-modular-design.md](2026-08-08-statusline-modular-design.md).
> Nada aqui altera o núcleo: é uma mudança contida em `widgets/rate-forecast.sh`.

## Propósito

O widget mostra hoje uma janela de rate limit por vez — `5h:42%→70%` — escolhida
pela opção `window`. As duas janelas que o Claude Code reporta existem no parse
desde o primeiro dia (`SL_5H_PCT`, `SL_5H_RESET`, `SL_7D_PCT`, `SL_7D_RESET`),
mas só uma chega à tela.

A janela de 5 horas responde "posso continuar agora". A de 7 dias responde
"quando eu paro". São perguntas diferentes, e ver só a primeira esconde
exatamente o bloqueio que dói — o de dias, que chega sem aviso porque ninguém
olhou.

Além disso, faltam duas informações que o widget já tem em mãos e não usa: o
horário em que a janela reseta e quanto tempo falta para isso. Um percentual sem
prazo não deixa decidir nada; `91%` com reset em oito minutos é tranquilo,
`91%` com reset em quatro horas não é.

## Escopo

**Entra:** as duas janelas sempre visíveis, cada uma com percentual atual,
projeção de estouro quando houver, horário do reset e contagem regressiva;
coloração independente por número.

**Não entra:** alertas que interrompem o usuário (isso é hook, não statusline);
mudanças no contrato do helper externo; instâncias parametrizadas de widget
(avaliado e descartado — ver Alternativas).

## Formato

A gramática completa, com as duas janelas em estado normal:

```
5h:31%→93% 02:10 1h48m - 7d:15% Fri 5d6h
│  │   │    │     │    │ │
│  │   │    │     │    │ └─ segunda janela, mesma gramática
│  │   │    │     │    └─ separador entre janelas
│  │   │    │     └─ contagem regressiva até o reset
│  │   │    └─ horário do reset
│  │   └─ projeção de estouro ao ritmo atual
│  └─ uso atual da janela
└─ rótulo da janela
```

Cada janela é `<rótulo>:<atual>%[→<projeção>%] <reset> <regressiva>`. A projeção
e sua seta somem quando o helper não tem amostras suficientes para projetar —
comportamento que já existe hoje e não muda.

Estados representativos:

```
tranquilo   5h:12%      04:55 3h20m - 7d:8%  Tue 6d2h
normal      5h:31%→93%  02:10 1h48m - 7d:15% Fri 5d6h
crítico     5h:91%→118% 02:10 1h48m - 7d:94%→107% Fri 5d6h
```

A largura fica entre 30 e 45 colunas. É um widget de linha própria ou de linha
pouco povoada; não cabe espremido entre outros seis.

## Decisões

### Sempre visível, nunca condicional

Considerou-se esconder a janela de 7 dias enquanto ela estivesse calma, seguindo
a regra que o resto do plugin usa — `worktree` some na árvore principal,
`git-status` some com a árvore limpa. Foi descartado.

O motivo é layout. Aqueles widgets aparecem e somem em eventos raros e
significativos; a janela de 7 dias cruzaria o limiar no meio de uma sessão de
trabalho, empurrando lateralmente tudo que estivesse à direita, repetidamente,
enquanto oscila em torno do limiar. Uma statusline que muda de largura sozinha
custa mais atenção do que a largura que economiza.

Presença constante também tem valor próprio: quem olha o mesmo lugar todo dia
aprende o que é normal, e passa a notar o anormal sem precisar que nada pisque.

### Duas cores no mesmo segmento

O widget é `--self-color` desde o início, porque sua cor é semântica. A mudança
é que ele passa a compor a cor **por número**, não por segmento:

- **uso atual** — verde abaixo de `warn`, amarelo de `warn` a `crit`, vermelho
  acima de `crit`. Padrão: `warn: 80`, `crit: 95`.
- **projeção** — a cor vem do nível que o helper externo devolve (`ok`, `warn`,
  `crit`), sem reinterpretação.
- **reset e contagem regressiva** — sempre esmaecidos. São contexto para os
  números, não competem com eles.

As duas primeiras escalas respondem perguntas diferentes — "quanto já gastei" e
"vou estourar" — e por isso não precisam usar os mesmos limiares. O helper
classifica projeção com `WARN=85` e `CRIT=100`, ajustáveis por
`CLAUDE_RATE_WARN` e `CLAUDE_RATE_CRIT`; o uso atual usa os limiares do widget,
ajustáveis na configuração. Um `31%` verde ao lado de um `→93%` amarelo não é
inconsistência: é uso baixo com ritmo alto, que é precisamente o que se quer
enxergar.

### Tempo é calculado localmente

Horário de reset e contagem regressiva saem de `SL_5H_RESET` e `SL_7D_RESET`,
que já chegam como epoch no parse único do stdin. Nenhuma chamada externa,
nenhum subprocesso, nenhum custo por repaint. O helper continua responsável
apenas pela projeção.

A escolha entre mostrar horário ou dia da semana é **pelo tempo restante, não
pela janela**:

- faltando menos de 24 horas → horário local em 24h: `02:10`
- faltando 24 horas ou mais → dia da semana abreviado: `Fri`

Isso reproduz o exemplo de referência — a janela de 5 horas quase sempre reseta
hoje, a de 7 dias quase sempre em dias — e se comporta corretamente nos casos de
borda que uma regra fixa por janela erraria, como uma janela de 7 dias que
reseta daqui a seis horas.

A contagem regressiva mostra as duas unidades mais significativas: `5d6h`,
`1h48m`, `48m`. Abaixo de um minuto, `<1m`.

Nomes de dia saem sob `LC_ALL=C`, para que a largura e a grafia não mudem com o
locale da máquina — mesma razão pela qual `widgets/cost.sh` já formata valores
sob `LC_ALL=C`.

### `window` deixa de escolher e passa a filtrar

A opção existe hoje e há configuração em uso que a define. Ela permanece válida,
com significado adjacente: **mostrar apenas a janela indicada**.

```jsonc
{ }                       // ambas as janelas
{ "window": "5h" }        // só a de 5 horas — comportamento de hoje
{ "window": "7d" }        // só a de 7 dias
```

Nenhuma configuração existente muda de comportamento, e quem não conhece a opção
recebe as duas janelas sem precisar declarar nada.

## Configuração

| Opção | Valores | Padrão |
|---|---|---|
| `window` | `5h`, `7d`; ausente mostra ambas | ausente |
| `warn` | percentual de uso atual a partir do qual pinta amarelo | `80` |
| `crit` | percentual de uso atual a partir do qual pinta vermelho | `95` |
| `separator` | texto entre as duas janelas | `-` |
| `reset` | `true`, `false` — mostra horário e regressiva | `true` |

`color` continua sem efeito: a cor é semântica.

## Tratamento de erros

O widget não pode desaparecer nem imprimir lixo por causa de dado ruim. Cada
degradação é local, e a menor possível:

| Situação | Comportamento |
|---|---|
| `SL_5H_PCT` e `SL_7D_PCT` vazios | widget inteiro some — não há o que dizer |
| uma das janelas sem percentual | a outra renderiza sozinha, sem separador órfão |
| helper ausente ou não executável | percentuais e tempos aparecem; projeção some |
| helper devolve nível desconhecido | tratado como "sem projeção", nunca como alerta |
| `resets_at` ausente ou não numérico | percentual e projeção aparecem; tempos somem |
| `resets_at` no passado | tempos somem — janela já virou, o dado é obsoleto |

A regra que governa todas: **um pedaço ilegível apaga só a si mesmo**. Nunca a
janela inteira, nunca o widget.

## Testes

`tests/widgets/rate-forecast.bats` cresce a partir dos sete casos atuais, que
continuam válidos. Acrescenta:

- as duas janelas renderizadas juntas, com o separador entre elas
- `window: "5h"` e `window: "7d"` produzindo exatamente uma janela cada
- uso atual verde, amarelo e vermelho nos limiares configurados
- projeção com cor independente do uso atual — o caso `31%` verde com `→93%`
  amarelo, que é a razão de existir da mudança
- reset formatado como horário abaixo de 24h e como dia da semana acima
- regressiva em `5d6h`, `1h48m`, `48m` e `<1m`
- cada linha da tabela de erros acima

Tempo é entrada, não relógio: os testes injetam `resets_at` e o instante atual,
como o helper já permite via `CLAUDE_RATE_NOW`. Nenhum teste depende da hora em
que roda, nem do fuso da máquina.

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

**Mostrar apenas a janela que bloqueia primeiro.** Conceitualmente a leitura mais
útil: uma linha só, sempre a que importa. Exigiria que o helper devolvesse tempo
até o estouro, não percentual projetado — mudança de contrato num script que
vive fora deste repositório. Fica registrada porque é também a base do alerta
"bloqueado em 3d1h", que pertence a um hook e a um roadmap próprio.

## Premissas

Pontos que o exemplo de referência não determina e que foram decididos aqui. São
o primeiro lugar a olhar em caso de discordância:

1. O separador entre janelas é `-`, cercado de espaços, configurável.
2. Reset e regressiva aparecem esmaecidos, não coloridos pelo nível.
3. O limiar de amarelo do uso atual é 80; o de vermelho, 95. O exemplo cita
   apenas o 80.
4. Horário sai em 24h sem segundos; dia da semana em três letras sob `LC_ALL=C`.
5. Faltando menos de um minuto, a regressiva mostra `<1m` em vez de `0m`.
6. Quando `window` está definida, a janela única renderiza sem separador.
