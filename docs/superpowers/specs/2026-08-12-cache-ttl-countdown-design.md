# cache — countdown de expiração do prompt cache

> Primeira mudança no widget `cache` desde
> [2026-08-08-statusline-modular-design.md](2026-08-08-statusline-modular-design.md),
> que o criou. O percentual de acerto e seus limites de cor (70/30) ficam como
> estão; o widget ganha um segundo número ao lado.

## Problema

O widget diz `cache:100%` verde e quase nunca diz outra coisa.

Medido no transcript de uma sessão real deste repositório — 845 trocas,
deduplicadas por `requestId`, das quais 844 têm token para computar acerto:

| faixa de acerto | amostras | fatia |
| --------------- | -------- | ----- |
| ≥ 95%           | 805      | 95%   |
| 70–94%          | 14       | 2%    |
| 30–69%          | 2        | <1%   |
| < 30%           | 23       | 3%    |

Noventa e cinco por cento do tempo o número é verde e imóvel. É a mesma falha que
levou a projeção `→48%` a ser escondida em `widgets/rate-forecast.sh`: ocupa
espaço permanente para dizer "siga em frente", que já era o estado padrão de quem
não vê aviso nenhum.

### O acerto alto não significa cache barato

A conta atual soma `cache_read`, `cache_creation` e `input` no denominador, como
se um token gravado custasse o mesmo que um lido. Os multiplicadores da API dizem
o contrário: leitura custa 0,1× o preço cheio, gravação com TTL de uma hora custa
2,0×. Um token gravado custa **vinte vezes** um token lido.

As mesmas 845 trocas:

| categoria | tokens | multiplicador | fatia do custo |
| --------- | ------ | ------------- | -------------- |
| leitura   | 199,6M | 0,1×          | ~54%           |
| gravação  | 6,7M   | 2,0×          | ~37%           |
| saída     | 0,59M  | 5,0×          | ~8%            |

Em token o acerto é 96,7%. Em dinheiro, gravação leva mais de um terço.

> **Ressalva.** A soma acima, convertida a dólar, não fecha com o
> `cost.total_cost_usd` do mesmo payload — o transcript contém sidechains de
> subagentes que o campo de custo aparentemente não conta. As **proporções** da
> tabela são o achado; os valores absolutos em dólar não foram validados e não
> devem ser citados.

### O custo de gravação é concentrado, e chega sem aviso

Das 845 trocas, 27 gravaram mais de 20k tokens cada. Esses 27 eventos carregam
**86%** de tudo que foi gravado no período. São compactação, injeção de skill
grande, leitura de arquivo grande, mudança no conjunto de ferramentas — e o
primeiro turno da sessão, que gravou 53.909 tokens sobre 22.971 já em cache,
revelando um prefixo estático de ~77k tokens (system prompt, CLAUDE.md, schemas
de ferramenta) pago em toda troca.

## O que o ecossistema faz

| projeto                      | acerto | read/write separados | TTL | ponderado por preço |
| ---------------------------- | ------ | -------------------- | --- | ------------------- |
| ccstatusline                 | sim    | sim                  | sim | não                 |
| claude-statusline-enhanced   | sim    | não                  | não | não                 |
| claude-hud                   | não    | não                  | sim | não                 |
| claude-code-usage-bar        | não    | não                  | sim | não                 |
| este                         | sim    | não                  | não | não                 |

Dois achados.

**Ninguém pondera por preço.** A lacuna é do ecossistema inteiro, não deste
repositório — somar dois campos do JSON é fácil e justificar multiplicadores é
difícil.

**Três projetos independentes implementaram o TTL.** Convergência dessas não é
acaso: o TTL é o único sinal de cache que é *preditivo* em vez de retrospectivo.
O acerto conta o que já foi cobrado; o TTL diz o que a próxima troca vai custar,
enquanto ainda dá para agir. Os três derivam do carimbo de tempo da última
resposta lido do transcript, porque o payload não o entrega.

Nenhum deles mostra o peso do prefixo estático, nem quantas ferramentas MCP
custam por troca.

## Escopo

**Entra:** o countdown de expiração.

**Fica fora, decidido explicitamente:** alarme de gravação grande na última troca
(`⚡54k`), acerto ponderado por preço, e peso do prefixo estático. Os três
continuam válidos e cada um vale a própria entrega.

## Origem dos dados

`lib/stdin.sh` passa a expor `SL_TRANSCRIPT`, de `.transcript_path` — um campo
que o payload sempre entrega e que nenhum widget lê hoje.

A extração pega as últimas 400 linhas do arquivo e devolve dois valores: o
`timestamp` da última entrada `assistant`, e o TTL em segundos.

**O TTL é detectado, não configurado.** A entrada de uso traz
`cache_creation.ephemeral_1h_input_tokens` e `ephemeral_5m_input_tokens`; qual
dos dois é diferente de zero identifica a janela contratada. Uma conta Max cai em
3600 e uma conta com cache de cinco minutos cai em 300, sem que ninguém precise
declarar nada — o que importa porque o mesmo usuário alterna entre as duas
máquinas.

O carimbo vem da última entrada `assistant`; o TTL, da última entrada `assistant`
**com gravação diferente de zero**, que nem sempre é a mesma. Uma troca servida
inteiramente do cache não grava nada e não identifica a janela.

### Custo da leitura

Medido num transcript de 24 MB e 10.780 linhas:

- `tail -n 400 | jq -s` completo: **7 ms**.
- Maior corrida de linhas consecutivas sem nenhuma entrada `assistant`: **57**.
  A janela de 400 dá margem de sete vezes.

A chamada é embrulhada em `cache_by_mtime` com o próprio transcript como
sentinela, então o `jq` só roda quando o arquivo muda. O countdown em si é
aritmética sobre o valor em cache e não custa processo nenhum.

### Degradação

Transcript ausente, ilegível, sem entrada `assistant` na janela, ou sem nenhuma
gravação que identifique o TTL: o countdown não aparece e o percentual sobrevive
sozinho. Mesma regra do reset ilegível em `widgets/rate-forecast.sh`, onde um
carimbo quebrado apaga só a si mesmo.

## Formatação do tempo

`sl_fmt_countdown` tem piso `<1m`. Para uma janela de cinco minutos isso é
inaceitável: os últimos sessenta segundos são exatamente os que decidem se vale
mandar o prompt agora.

Entra uma função nova em `lib/timefmt.sh`, com a mesma regra de duas unidades e
omissão da menor quando zerada, uma faixa mais fina:

```
1h       acima de uma hora não ocorre: o TTL máximo é 3600s
58m      acima de cinco minutos, só o minuto
5m
4m59s    abaixo de cinco minutos, o segundo entra
4m       segundos zerados somem
47s
```

O corte dos segundos em cinco minutos vem do mesmo argumento que separou esta
função de `sl_fmt_countdown`, aplicado a ela própria: `59m45s` num repaint de
cinco segundos pisca permanentemente para dizer o que ninguém lê nessa
resolução, e movimento constante gasta a atenção que deveria sobrar para quando
o número fica curto.

Cinco minutos, e não os três do amarelo, porque é o tamanho da menor janela
contratável: numa conta de cinco minutos a regressiva inteira fica abaixo do
corte e mostra segundos o tempo todo, que é exatamente o caso em que eles
servem. Com três, os dois primeiros minutos daquela janela sairiam sem eles.

**A existente não é estendida.** O `<1m` do rate-forecast é escolha deliberada:
trocá-lo por `47s` faria o reset da janela de cinco horas piscar a cada repaint,
num widget onde a precisão de segundo não decide nada. As duas funções
compartilham a forma e divergem na faixa, e cada uma se lê isolada.

## Render

```
☁ 100%·4m12s
```

O glifo substitui o rótulo `cache:`. É `☁` (U+2601), o mesmo que a statusline
arquivada em `docs/legacy/statusline-2.sh:92` usava para este widget — o
`statusline.sh` mais antigo usava `U+F0C2`, área privada da Nerd Font, que este
projeto rejeita por depender de fonte instalada.

O glifo leva espaço depois. Largura ambígua colada em dígito disputa a mesma
célula em boa parte dos terminais, mesmo motivo do `⟳` em `sl_stamp_label` e do
`⏱` que abre o rate-forecast.

**Sobre o risco de apresentação emoji.** `U+2601` tem variante emoji (`☁️`), que
seria colorida fixa e de largura dupla, apagando a cor semântica. O risco é real
mas já está corrido e resolvido neste repositório: o `⚠` do flow (`U+26A0`) é da
mesma família, está em produção sem seletor de variação, e renderiza
monocromático e vermelho. Mesmo tratamento aqui — codepoint puro, sem `U+FE0E`.

O separador é `·`, a mesma pontuação que `sl_reset_label` usa entre data e
regressiva.

### Cores

Cada número carrega a própria semântica, então o widget passa a imprimir duas
cores. O percentual mantém os limites de hoje (verde ≥70, amarelo ≥30, vermelho
abaixo). O countdown tem os seus:

| restante  | cor      |
| --------- | -------- |
| ≥ 3min    | verde    |
| < 3min    | amarelo  |
| < 1min    | vermelho |
| expirado  | vermelho |

**Limites absolutos, não proporcionais ao TTL.** A pergunta que o countdown
responde — "dá tempo de eu formular o próximo prompt antes de esfriar?" — tem
duração absoluta: quem digita leva de trinta a sessenta segundos, e isso não
muda porque a janela contratada é de uma hora. Limites proporcionais dariam vinte
minutos de amarelo numa janela de 3600s, que é ruído; e numa de 300s dariam
alarme vermelho a trinta segundos, tarde demais.

O efeito colateral é desejado: numa conta com TTL de uma hora o countdown quase
nunca sai do verde, porque com uma hora de janela raramente se perde o cache.
Numa de cinco minutos ele acende o tempo todo, porque ali o cache se perde mesmo.

Expirado imprime `cold` na posição do tempo. Em inglês por coerência: os outros
rótulos do widget e dos vizinhos são `cache:`, `blocked:`, `5h:`, `7d:`, e as
datas já saem `31Aug` e `Fri` por causa do `LC_ALL=C` em `sl_date_fmt`.

## Estados independentes

O widget hoje sai inteiro do ar quando `total == 0`, e
`context_window.current_usage` vem `null` **entre trocas** — comportamento
registrado no comentário do próprio arquivo.

Implementado ingenuamente, o countdown herdaria esse retorno precoce e sumiria
justamente enquanto o usuário está parado pensando, que é o único momento em que
ele muda uma decisão. O retorno precoce sai; os dois lados passam a viver
separados:

| percentual | countdown | saída            |
| ---------- | --------- | ---------------- |
| válido     | válido    | `☁ 100%·4m12s`   |
| indefinido | válido    | `☁ 4m12s`        |
| válido     | ausente   | `☁ 100%`         |
| indefinido | ausente   | widget não sai   |

## Configuração

| opção       | valores                    | padrão   |
| ----------- | -------------------------- | -------- |
| `countdown` | `always` \| `near` \| `off`| `always` |
| `label`     | texto                      | `cache:` |

`near` mostra o countdown a partir do limite amarelo — reusa os 3min em vez de
inventar um segundo número para o usuário calibrar.

`icons: false`, global, volta a imprimir o rótulo `label` no lugar do `☁`, que é
o que a opção já significa nos outros widgets.

Os limites de 3min e 1min ficam como constantes nomeadas, não expostas. Se
incomodarem em uso real, viram opção depois.

## Testes

Transcript escrito por helper no diretório temporário do teste, um por caso, como
`flow.bats` já faz com o payload do Flow — e não fixture estática em
`tests/fixtures/`, que forçaria um arquivo por combinação. Os casos precisam de
entradas `assistant` de ambos os TTLs, entradas sem gravação, entradas de outros
tipos entre elas, e uma última linha truncada.

Cada escrita usa um nome de arquivo novo. `cache_by_mtime` tem resolução de um
segundo e a chave é derivada do caminho, então dois transcritos diferentes
escritos no mesmo segundo sobre o mesmo caminho colidiriam no cache.

Tempo injetado por `SL_NOW`, como no rate-forecast e no flow — a suíte não pode
depender do relógio, sob pena de falhar sozinha de madrugada ou só no CI, que
roda em UTC.

**Contraprova em toda asserção de ausência.** Um teste que afirma que algo *não*
aparece passa sozinho quando a funcionalidade inteira está quebrada. A regra do
repositório é renderizar duas vezes no mesmo teste — uma no caso sob teste e uma
num caso vizinho onde a coisa tem de aparecer. A PR #11 mostrou o custo de não
fazer isso: `flow.bats` não carregava `lib/timefmt.sh`, a renovação nunca
renderizava, e vários testes passaram assim mesmo, porque no bash 3.2 o `errexit`
não dispara em `[[ ]]` dentro de função e só a última asserção de cada teste é
cobrada.

Casos mínimos: os quatro estados da tabela de estados independentes; as quatro
faixas de cor; detecção de 3600 e de 300; TTL não identificável; transcript
ausente; os três valores de `countdown`; `icons: false`.

## Riscos

**O `☁` vira emoji em alguma fonte.** Mitigado pelo precedente do `⚠`, não
eliminado. Quem tiver o problema desliga com `icons: false` e recupera o rótulo
de texto.

**A janela de 400 linhas não alcança nenhuma entrada `assistant`.** Medido em 57
no pior caso observado, mas transcripts com muitos anexos por turno podem crescer
essa corrida. O sintoma é benigno — o countdown some — e o número vira constante
nomeada, ajustável sem redesenho.

**O carimbo é do fim da resposta, não do momento em que o cache foi tocado.** A
diferença é de segundos e desloca o countdown para o lado conservador: ele mostra
menos tempo do que existe, nunca mais.
