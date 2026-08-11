# rate-forecast — calibragem por janela e helper interno

> Estende [2026-07-25-statusline-rate-forecast-design.md](2026-07-25-statusline-rate-forecast-design.md),
> que definiu os dois estimadores e a regra de convergência, e
> [2026-08-10-rate-forecast-duas-janelas-design.md](2026-08-10-rate-forecast-duas-janelas-design.md),
> que ligou a segunda janela. Nada aqui muda a regra de convergência nem o
> formato da linha.

## Problema

Observado em produção:

```
⏱ 5h:19%→83% ⟳02:10·1h56m · 7d:25%→670% ⟳Fri·3d6h
```

Uma projeção de 670% na janela de sete dias, pintada de amarelo. A cor está
correta e a spec de 2026-07-25 a prevê: a média da janela dizia `ok` (47%), o
ritmo recente dizia `crit` (669%), e divergência entre estimadores é incerteza,
que é amarela. O erro não está na cor. Está no 670.

O número saiu de **um único incremento de 1 ponto percentual, visto sete minutos
antes**, extrapolado sobre os três dias que faltavam para a janela virar.

### Por que o estimador recente estava quebrado nos sete dias

O ritmo recente projeta `used + (delta / span) × restante`. O erro da projeção é
portanto `(resolução do delta / span) × restante`. Dois dos três termos estavam
errados para uma janela de sete dias:

- **resolução do delta.** O percentual chegava ao helper já arredondado ao
  inteiro, então o menor delta observável era 1 ponto inteiro — mesmo quando o
  consumo real tinha subido 0,02.
- **span.** O mínimo era 300 segundos, fixo. Numa janela de 5 horas o restante
  máximo é 18000s, então o pior caso multiplica o delta por 60. Em 7 dias o
  restante chega a 604800s, e o mesmo delta é multiplicado por 2016.

Medido no helper antes desta mudança, com uso em 25% e três dias restantes:

| span da amostra | projeção do ritmo recente |
| --------------- | ------------------------- |
| 300s            | 969%                      |
| 900s            | 340%                      |
| 1800s           | 182%                      |

Qualquer delta de 1 ponto dentro da janela móvel de 1800s projetava no mínimo
182% — sempre `crit`. O estimador recente da janela de sete dias tinha só dois
estados possíveis, `ok` (delta zero) e `crit` (delta não-zero); a faixa `warn`
era inalcançável.

Isso tem uma consequência pior que o número feio: com `lvlB ∈ {0, 2}` e a média
da janela normalmente calma, a regra de convergência nunca chegava a `crit`. **A
janela de sete dias não conseguia ficar vermelha por rajada** — só por acumulado.
O canal de alerta que a spec de 2026-08-10 quis abrir estava mudo.

### A raiz: constantes calibradas contra uma janela só

Os dois limiares nasceram como constantes em segundos, quando havia uma única
janela. Eles são frações dela:

```
1800 = 18000 / 10       janela móvel do ritmo recente
 300 = 18000 / 60       span mínimo entre amostras
```

A spec de 2026-07-25 registra o escopo original com todas as letras: *"Só a
janela de 5h recebe alerta nesta entrega... não se liga agora (YAGNI: a 7d fica
em 8% com dias de folga)."* A entrega de 2026-08-10 ligou a segunda janela sem
revisitar a calibragem, porque a calibragem não estava expressa como decisão —
estava embutida em dois números.

## Solução

### Limiares derivados da duração da janela

```
LOOKBACK = max(1800, duração / 10)
MIN_SPAN = max( 300, duração / 60)
```

Para 5 horas isso reproduz 1800 e 300 dígito por dígito, então a janela que já
funcionava não muda de comportamento — os 27 casos herdados da suíte original
passam sem alteração. Para 7 dias dá 60480s e 10080s.

O piso existe porque uma janela curta derivaria limiares curtos demais para
medir coisa alguma: em 600 segundos, `duração / 60` daria um span mínimo de 10s.
Abaixo do piso, o comportamento é o de antes desta mudança.

**O span mínimo é o que corrige o caso observado; a janela móvel sozinha não
corrige.** Medido: com a amostra de 440s como única disponível, subir apenas o
`LOOKBACK` mantém `warn 669`, porque a janela móvel só amplia a *busca* pela
amostra mais antiga — e com uma amostra só, a mais antiga continua sendo aquela.
É o `MIN_SPAN` que recusa medir ritmo sobre um span curto demais para significar
algo, devolvendo `ok 47`. A janela móvel maior entra para que, em regime, exista
histórico longo o bastante para o span crescer.

Ambos continuam sobrescritíveis por `CLAUDE_RATE_LOOKBACK` e
`CLAUDE_RATE_MIN_SPAN`; um override não-numérico cai no derivado em vez de
quebrar a aritmética, como o resto do script já faz com entrada suspeita.

### Percentual entregue sem arredondar

O parse do stdin arredondava o percentual ao inteiro antes de qualquer
consumidor. Isso serve à exibição e cobra caro de quem calcula: para um
estimador que deriva taxa de uma diferença, um arredondamento de apresentação é
um degrau de 1 ponto inteiro.

`lib/stdin.sh` passa a cortar em duas casas em vez de arredondar ao inteiro. As
duas casas matam a cauda binária que motivou o arredondamento original — o
`55.00000000000001` que a API de fato entrega — sem jogar fora a precisão real:
`13.6` continua `13.6`.

Isso alinha o `rate-forecast` ao precedente que o `flow` já seguia desde
`800b0bc`: o jq entrega o número como veio e `sl_round`, em `lib/num.sh`,
arredonda na apresentação. Aquele commit removeu o `floor` do jq no `flow`
justamente porque arredondar no parse fazia 24,9% virar 24%. O mesmo argumento
vale aqui, e o resultado é **menos** arredondamento espalhado, não mais: antes
havia dois pontos arredondando em série no caminho deste widget, e o `sl_round`
do widget era no-op porque recebia um inteiro.

O ganho é maior na janela de cinco horas do que na de sete dias, o que parece
invertido mas não é: em sete dias o span mínimo derivado já protege a
extrapolação, enquanto em cinco horas o span mínimo é necessariamente curto e o
degrau do arredondamento continua sendo o termo dominante. Medido numa subida
real de 0,02 ponto sobre 300s, com a janela de 5h no início: `crit 620` com o
valor arredondado, `warn 610` com o valor cru.

### Gatilho da poda proporcional à retenção

A poda descartava amostras mais velhas que `max(3600, LOOKBACK × 2)`, mas só
disparava acima de 200 linhas — um número fixo, escolhido quando a retenção
também era fixa.

Com a retenção derivada da janela, quantas amostras cabem nela passa a depender
da janela: cerca de 60 nas cinco horas e mais de 2000 nos sete dias. O gatilho
fixo dispararia a cada repaint da janela longa, reescrevendo o arquivo inteiro
sem ter nada a descartar — o oposto do que a poda existe para fazer.

```
prune_at = retenção / SAMPLE_EVERY + 60
```

A folga de 60 amostras em cima do tamanho de regime é o que mantém a reescrita
amortizada: quando roda, corta de volta ao tamanho de regime, e só volta a
disparar depois de acumular a folga de novo.

`SAMPLE_EVERY` passou a ser divisor, então zero deixou de ser apenas inútil e
virou erro de aritmética. Um valor não-numérico ou zero cai no default.

## Helper interno

`bin/rate-forecast.sh` passa a viver neste repositório, ao lado de
`bin/flow-consumption.sh`, e `SL_FORECAST_BIN` aponta para
`${SL_ROOT}/bin/rate-forecast.sh` — o mesmo caminho que `widgets/flow.sh` já
resolve para o helper dele.

A spec de 2026-08-10 listava "mudanças no contrato do helper externo" fora de
escopo, e descartou uma alternativa por exigir *"mudança de contrato num script
que vive fora deste repositório"*. Aquela restrição fazia sentido enquanto o
helper era de fato externo, mas ela cobrava um preço que só agora ficou visível:
o plugin é distribuído por marketplace, e quem o instalasse sem já ter o script
em `~/.claude` nunca veria projeção nenhuma. A previsão era, na prática, um
recurso de uma máquina só.

O contrato de invocação não muda, e `SL_FORECAST_BIN` continua apontando para
outro caminho quando se quiser trocar o modelo de previsão. O que muda é o
default: existe um helper embarcado, e ele funciona numa instalação limpa.

## Testes

`tests/rate-forecast-bin.bats` porta os 27 casos que a suíte do helper trazia de
fora do repositório — eles continuam passando sem alteração, o que é a evidência
de que a derivação reproduz os limiares antigos na janela de 5 horas. Acrescenta:

- o caso observado em produção, com o span de minutos, projetando `ok 47`
- o mesmo ritmo sobre um span que a janela de 7 dias considera significativo,
  que volta a projetar alto
- override explícito continuando a vencer o derivado
- override não-numérico caindo no derivado em vez de quebrar
- o piso recusando um span curto numa janela curta
- a poda não reescrevendo um arquivo de 7 dias que está apenas no tamanho normal

`tests/stdin.bats` troca a asserção de arredondamento ao inteiro por duas: a
cauda binária cortada e a precisão real preservada.

`tests/widgets/rate-forecast.bats` acrescenta que o helper recebe o percentual
sem arredondar e que a exibição continua inteira. O dublê em
`tests/fixtures/fake-forecast.sh` ganha `FAKE_FORECAST_ARGS_FILE`, para que um
teste possa verificar o que o widget entrega, e não apenas o que faz com a
resposta.

## Premissas

1. Os divisores 10 e 60 vêm dos valores que já existiam, não de uma calibragem
   nova. São o que a janela de 5 horas usava, expressos como fração dela.
2. O piso é o par de constantes antigas. Uma janela menor que 5 horas fica com o
   comportamento de hoje, que é o único que já foi observado funcionando.
3. Duas casas decimais são suficientes. É uma escolha de resolução: 0,01 ponto
   sobre o span mínimo de 7 dias projeta menos de um ponto percentual de erro.
