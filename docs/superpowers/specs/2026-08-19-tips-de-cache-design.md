# tips de cache — quanto custa deixar o prefixo esfriar

> Segue [2026-08-18-tips-bloqueio-projetado-design.md](2026-08-18-tips-bloqueio-projetado-design.md),
> que criou o widget `tip`. Aquele spec desenhou uma fonte só — projeção que
> cruza 100% e uma data de bloqueio. Este acrescenta duas fontes que **não
> cabem naquele formato**, e generaliza o contrato para caber nas duas.
>
> Nada muda no que a barra desenha hoje: as frases do flow, 5h e 7d saem
> idênticas depois do refactor, e é assim que se sabe que ele está certo.

## Problema

O widget `cache` já mostra o suficiente para ver o problema, e não o bastante
para decidir:

```
☁ 100%·cold
```

`cold` diz que o prefixo expirou. O que ele não diz é o que isso custa: a
próxima troca **regrava o contexto inteiro**, e num contexto de 393k isso não é
detalhe de rodapé. A pergunta que a pessoa faz nesse instante — *continuo e pago
a regravação, ou dou `/clear` e recomeço?* — tem resposta aritmética, e a barra
tem todos os números para calculá-la.

## A aritmética

Os multiplicadores do prompt caching, relativos ao preço de input:

| Operação | Multiplicador |
| -------- | ------------- |
| Ler do cache | **0,1×** |
| Regravar, TTL de 5 min | **1,25×** |
| Regravar, TTL de 1 h | **2×** |

Regravar custa, portanto, **12,5× ou 20×** o que custaria ler os mesmos tokens
quentes — conforme a janela contratada, que `widgets/cache.sh` **já detecta** de
`ephemeral_1h_input_tokens` / `ephemeral_5m_input_tokens`. Não é configuração: o
mesmo usuário alterna entre uma conta de 1 h e outra de 5 min.

E o ponto de equilíbrio sai da mesma expressão. Com `W` trocas a partir da
regravação:

```
com cache:  W + 0,1·(N−1)        sem cache:  1·N
```

→ **3 trocas** com TTL de 1 h, **2 trocas** com 5 min. É o número que responde a
pergunta: abaixo dele, `/clear` sai mais barato.

## O preço em dólar

O múltiplo é invariante, mas dinheiro decide melhor. O plugin não conhece
tabela de preços — e não deve conhecer: ela envelheceria a cada lançamento, e
mentiria para quem passa por um gateway corporativo com preço próprio.

**A derivação parte do custo que o Claude Code já reporta.** O caminho ingênuo
— dividir custo total por tokens totais — foi medido e recusado:

```
preço médio "blended":  $0,90 por 1M        erro de 5,5×
preço de input real:    $5,00 por 1M
```

A causa é estrutural: numa sessão real, 106M de tokens lidos do cache a 0,1×
dominam a contagem e quase não pesam no custo. A média desaba, e a dica
subestimaria a regravação em cinco vezes — pior que não ter dica, porque erra
para menos justamente no número que deveria assustar.

**O que funciona é uma invariante**: a razão output/input é **5× em toda a linha
Claude** — Fable 10/50, Opus 5/25, Sonnet 3/15, Haiku 1/5. Com ela o sistema tem
uma incógnita só:

```
custo = P_in × (input + 0,1·read + W·write + 5·output)
```

Medido contra os agregados de uma sessão real de 435 trocas:

| | P_in derivado | real | erro |
| --- | --- | --- | --- |
| com `W = 1,25` | $5,02 / 1M | $5,00 | 0% |
| com `W = 2,0` | $4,46 / 1M | $5,00 | 11% |

Erro de 0–11% para um número que aparece precedido de `~`. Custo desconhecido,
zero ou negativo: a frase omite a cifra e mantém o múltiplo e as trocas, que
continuam verdadeiros.

O cálculo varre o transcript inteiro, então é **cacheado por mtime** e só roda
quando uma dica de cache está prestes a disparar. No caso comum não roda.

## O contrato de fonte, generalizado

O `tip` de hoje assume um formato só: `proj used blocked reset`, com
`_tip_phrase` decidindo a frase a partir deles. "Esfriou" não tem projeção nem
data de bloqueio; enfiá-lo ali significaria quatro campos vazios que não querem
dizer nada, e a segunda fonte de cache ficaria pior que a primeira.

Invertendo quem monta a frase, o `tip` deixa de saber o que é uma projeção:

```
_tip_src_<nome> <chave_anterior>   →   "<chave_nova><TAB><frase pronta>"
                                       ou retorna 1, quando não há o que dizer
```

**A chave é opaca para o widget.** Ele só compara com a gravada e aplica a regra
que já existe:

| Situação | Ação |
| -------- | ---- |
| Sem estado, ou chave diferente da gravada | mostra e carimba o turno corrente |
| Chave igual e mesmo turno | continua mostrando |
| Chave igual e turno novo | cala |
| Fonte retorna 1 | esquece o que ela disse |

**A fonte recebe a chave anterior**, e não é detalhe de conveniência: sem isso a
regra dos 10% do flow se perderia. Comparada por igualdade simples, uma data de
bloqueio que andou um segundo produziria chave nova e a dica voltaria a cada
repaint. Quem sabe o que conta como mudança material é a fonte — o flow devolve
a chave anterior inalterada quando a antecipação fica abaixo do limiar, e com
isso o comportamento de hoje é preservado exatamente.

As fontes ficam numa lista, e é ela que o widget percorre:

```bash
SL_TIP_SOURCES="flow 7d 5h cache-cold cache-expiring"
```

Hífen não é legal em nome de função, então vira underscore — a mesma conversão
que `_sl_slug` faz em `lib/core.sh`.

### O que o refactor apaga

`_tip_should_show`, `_tip_step`, `_tip_phrase` e a lista `for src in flow 7d 5h`
saem na forma atual. `_tip_cut`, `_tip_prompt_id` e as três funções de estado
ficam como estão.

**O teste do refactor é que nada muda na tela.** Os testes de `tests/tips.bats` e
`tests/widgets/tip.bats` que afirmam as frases do flow, 5h e 7d continuam
valendo palavra por palavra; se passarem sem edição, a migração está correta.

### Estado

Uma coluna a menos, porque a chave absorve degrau e data:

```
tip-state.tsv   fonte  chave  prompt_id
```

## As duas fontes novas

| Fonte | Dispara quando | Chave |
| ----- | -------------- | ----- |
| `cache-cold` | countdown expirou **e** contexto ≥ 100k | `cold` |
| `cache-expiring` | countdown < 60 s **e** contexto ≥ 100k | `warn` |

```
⎿ Cache: regravar 393k custa 2× (~$3,50) — vale a partir de 3 trocas    (74)
⎿ Cache: 45s até esfriar — mandar algo agora aproveita 393k gravados    (74)
```

**Nenhuma das duas diz "esfriou".** O primeiro rascunho dizia, e estourava os 80
caracteres — 83 e 84. A palavra é redundante: o `☁ 100%·cold` da linha de cima
já anuncia o estado, com formato próprio e cor própria. É a mesma lição que as
datas ensinaram no flow, e o mesmo remédio: a dica só carrega o que a barra não
consegue dizer. Sem a cifra a primeira cai para 65; no pior caso medido —
contexto de 1.0M e cifra de dois dígitos — ela chega a 75.

**O piso de 100k de contexto é o que separa dica de ruído.** Esfriar com 12k na
sessão custa centavos, e uma dica que aparece nesse caso ensina a ignorar a que
aparece com 393k. O número é da mesma ordem do limiar de gravação que o
`cache.sh` já usa (10k para o alarme `▲`), uma casa acima porque aqui o que está
em jogo é o contexto inteiro e não uma troca.

**As duas fontes nunca falam juntas**: `cold` e `< 60 s` são estados exclusivos
do mesmo countdown.

**A de esfriamento iminente não repete.** A chave é `warn` durante toda a janela
de 60 segundos, então ela aparece uma vez e fica até o turno seguinte — não volta
a cada repaint enquanto o relógio corre.

## Larguras

As frases precisam caber em 80 colunas, medidas em **caracteres** e não em bytes
— `tests/tips.bats` já traz `tip_width` para isso, escrito quando o CI do Windows
derrubou a medição ingênua.

A frase de `cache-cold` é a mais longa e cresce com três valores: os tokens
(`393k`), o múltiplo (`2×`) e a cifra (`~$3,50`). Sem a cifra ela encolhe
sozinha, que é o comportamento certo quando o preço não é derivável.

## Testes

`tests/tips.bats` — as funções novas:

- `_tip_price_per_token`: a fórmula com a invariante 5×, contra agregados de
  fixture; custo zero ou ausente devolve vazio
- `_tip_breakeven`: 3 com `W=2`, 2 com `W=1.25`
- `_tip_src_cache_cold`: dispara com contexto alto e countdown expirado; cala
  com contexto abaixo do piso; cala com o cache quente
- `_tip_src_cache_expiring`: dispara dentro dos 60 s; cala fora
- a frase sem cifra, quando o preço não é derivável
- todas as frases em ≤ 80 colunas, via `tip_width`

`tests/widgets/tip.bats` — o contrato generalizado:

- fonte que devolve chave nova aparece e carimba o turno
- chave igual e turno novo cala
- fonte que retorna 1 tem o estado esquecido
- duas fontes simultâneas produzem duas linhas, ordem estável
- **as frases de flow, 5h e 7d saem idênticas às de antes do refactor**

## O que fica de fora, e por quê

**Diagnóstico de prefixo invalidado** (`▲>50k` em várias trocas seguidas). Seria
a terceira dica mais valiosa, e exigiria estado novo — hoje só existe o contador
da última troca. Pior, o diagnóstico seria chute: o plugin não sabe se a pessoa
trocou de MCP, releu um arquivo grande ou compactou. Uma dica que aponta a
direção errada custa mais do que o silêncio.

**Contar as trocas restantes de verdade**, para dizer "você já fez 2 das 3".
Tentador e enganoso: o break-even conta trocas *futuras*, e o plugin não sabe se
a pessoa vai parar agora.

**Sugerir `/compact`.** Cabia na primeira versão da ideia e não sobreviveu à
aritmética: compactar também invalida o prefixo e paga a gravação de novo. A
recomendação honesta é sobre *quando* — antes de esfriar, não depois — e isso é
o que `cache-expiring` já diz sem precisar nomear o comando.

**Tabela de preços no plugin.** Recusada acima; a derivação cobre inclusive o
gateway corporativo, que uma tabela da Anthropic descreveria errado.
