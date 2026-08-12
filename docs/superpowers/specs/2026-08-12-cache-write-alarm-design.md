# cache — alarme de gravação da última troca

> Segue [2026-08-12-cache-ttl-countdown-design.md](2026-08-12-cache-ttl-countdown-design.md),
> que somou o countdown ao widget e estabeleceu a estrutura de partes
> independentes. Aquele spec listou este alarme como explicitamente fora de
> escopo; aqui ele entra. Nada muda no countdown nem na taxa.

## Problema

O countdown diz quando a gravação vai acontecer. Não diz quando ela aconteceu.

A distribuição de `cache_creation_input_tokens` por troca, medida sobre 943
trocas de uma sessão real deste repositório, deduplicadas por `requestId`:

| medida | tokens gravados |
| ------ | --------------- |
| mediana | 699 |
| p90 | 2.942 |
| p99 | 286.529 |
| máximo | 416.171 |

**33 trocas gravaram mais de 10k tokens, e essas 33 carregam 85% de tudo que
foi gravado na sessão.** São 3,5% dos turnos concentrando quase todo o custo de
gravação — compactação, injeção de skill grande, leitura de arquivo grande,
mudança no conjunto de ferramentas.

Hoje esses eventos passam invisíveis. O contador de gravação existe no payload,
entra no denominador da taxa e some ali dentro: uma troca que gravou 287k baixa
o percentual, mas o percentual não diz **quanto** nem **que isto foi um evento**.

## O que fica de fora, e por quê

Dois candidatos foram medidos junto e recusados.

**Peso do prefixo estático.** Mediria o custo fixo pago em toda troca — 76.880
tokens nesta sessão, dos quais 53.909 gravados no primeiro turno sobre 22.971 já
em cache. Recusado por dois motivos: o transcript guarda metadados e **não** o
system prompt nem os schemas de ferramenta, então o número não se decompõe em
"MCP custa X, CLAUDE.md custa Y" — que era a pergunta que ele deveria responder;
e o total não muda durante a sessão, o que o torna diagnóstico e não
acompanhamento. Se voltar, volta como comando, não como widget.

**Taxa ponderada por preço.** Trocar o denominador por `read×0,1 + write×2,0 +
input×1,0`. Medido sobre 941 trocas:

| faixa | taxa crua | taxa ponderada |
| ----- | --------- | -------------- |
| ≥ 95% | 96% das trocas | 45% |
| ≥ 70% — o limiar verde de hoje | — | **92%** |

O número se move de verdade (a mediana cai de ~100 para 94), mas **a cor não**:
com os limites atuais o widget continuaria verde em 92% das trocas. Só valeria
junto de uma recalibragem, o que muda o significado de um número que já está no
ar. Fica para uma decisão própria.

## Render

```
☁ 64%·58m ▲54k
```

O alarme entra depois do countdown, porque é a parte mais nova da linha e a
menos frequente: lidos na ordem, os três contam "cache assim, esfria então,
e esta troca custou isto".

**Abaixo do limiar o alarme não existe** — nem glifo, nem número, nem separador.
Numa troca de rotina o widget continua exatamente como está hoje. É a mesma
regra da projeção `→48%` no rate-forecast e do zero que some no velocity: o
espaço permanente é para o que muda uma decisão.

### Cores e limiares

| gravado | cor |
| ------- | --- |
| < 10k | não aparece |
| ≥ 10k | amarelo |
| ≥ 50k | vermelho |

O limiar de 10k não é redondo por acaso: o p90 é 2.942, então ele fica acima do
ruído de rotina com folga de mais de três vezes, e ainda assim captura as 33
trocas que carregam 85% do custo. Um limiar mais baixo acenderia todo dia; mais
alto perderia eventos de skill e de arquivo grande, que ficam na casa das
dezenas de milhares.

### Sobre o glifo

`▲`, U+25B2. O evento é um pico, e a forma diz isso.

**`⚡` foi recusado por um motivo técnico, não estético.** U+26A1 tem
`Emoji_Presentation = Yes`: renderiza colorido por padrão e ignora ANSI. Como a
cor aqui é a informação — amarelo separa "caro" de "muito caro" em vermelho — um
raio de cor fixa não serve. É a diferença entre ele e o `☁` (U+2601) e o `⚠`
(U+26A0), que têm `Emoji_Presentation = No` e por isso aceitam a cor.

**`⌁` (U+2301) foi recusado por cobertura de fonte.** Verificado com um parser
de `cmap` sobre as fontes instaladas:

| glifo | Menlo | SF Mono | JetBrains Mono NF |
| ----- | ----- | ------- | ----------------- |
| `⌁` U+2301 | sim | não | **não** |
| `☁` U+2601 | sim | não | **não** |
| `▲` U+25B2 | sim | sim | **sim** |

O `☁` já em produção depende de fallback do sistema para o Menlo, e funciona.
Mas o fallback custa largura: a fonte substituta não casa necessariamente com a
métrica monoespaçada. `▲` está presente na fonte do terminal, no SF Mono e no
Menlo, então dispensa fallback e tem largura garantida. Um glifo com fallback na
linha já é o preço aceito; dois seriam escolha.

O `▲` fica colado ao número, sem o espaço que o `☁` e o `⟳` levam. Se o
alinhamento incomodar em uso, é uma linha para mudar.

## Formatação do número

`54k`, `287k`, `1.0M`. A função já existe como `_context_fmt_tokens` em
`widgets/context.sh:39`, privada de um widget. Sobe para `lib/num.sh` como
`sl_fmt_tokens` e passa a ter dois consumidores, em vez de ser copiada.

## Configuração

| opção | valores | padrão |
| ----- | ------- | ------ |
| `write` | `true`, `false` | `true` |

Não há `near` aqui: o alarme já é auto-suprimido abaixo do limiar, então o modo
que o `countdown` precisa é o comportamento natural deste.

Com `icons: false` o glifo dá lugar a `w:`, no estilo dos rótulos vizinhos.

Os limiares ficam como constantes nomeadas, não expostas, pelo mesmo critério do
countdown: viram opção se incomodarem em uso real.

## Estados

O alarme é uma terceira parte independente, junto da taxa e do countdown. As
combinações que importam:

| taxa | countdown | alarme | saída |
| ---- | --------- | ------ | ----- |
| válida | válido | acima do limiar | `☁ 64%·58m ▲54k` |
| válida | válido | abaixo | `☁ 100%·58m` |
| válida | ausente | acima | `☁ 64% ▲54k` |
| indefinida | válido | — | `☁ 58m` |

A quarta linha merece nota: o alarme lê `SL_CACHE_CREATE`, o mesmo contador que
alimenta a taxa. Quando `current_usage` vem null entre trocas, os dois somem
juntos, e é correto — não houve troca para gravar nada.

## Testes

Nenhuma leitura nova: os dados já estão em `SL_CACHE_CREATE`, então os testes não
precisam de transcript. Casos mínimos: as três faixas de cor; a supressão abaixo
do limiar, com contraprova; os limiares exatos (10.000 e 50.000); a formatação
em k e em M; `write: false`; `icons: false`; e a convivência com as outras duas
partes.

**A contraprova vem antes da asserção sob teste**, pela regra registrada em
`tests/helper.bash`: no bash 3.2 só a última asserção de cada teste é cobrada, e
escrita depois a contraprova protege a si mesma. A rodada de sabotagem da PR #13
encontrou oito testes com esse defeito.
