# tips — a dica que explica o bloqueio projetado

> Depende de [2026-08-10-rate-forecast-duas-janelas-design.md](2026-08-10-rate-forecast-duas-janelas-design.md),
> que estabeleceu `proj` e `blocked` como saída do `bin/rate-forecast.sh`, e do
> widget `flow`, que já lê `blocked_epoch` do payload. **Nada do que está no ar
> muda:** nenhum widget existente é alterado, nenhum campo sai da linha. Esta
> spec só acrescenta uma linha que se apaga sozinha.

## Problema

A barra já sabe dizer que a cota vai estourar. Ela diz assim:

```
Flow 💰 25%→116% 🔒 sex·2d8h
```

Três informações verdadeiras e uma pergunta sem resposta. O `25%` é o gasto, o
`→116%` é a projeção, o `🔒 sex·2d8h` é quando trava — mas **nada ali explica
que o segundo número não é consumo**, e quem vê `25%` ao lado de `116%` não tem
como saber, olhando, que os dois medem coisas diferentes. Pior: a única leitura
intuitiva do par é "gastei 25 de 116", que é exatamente ao contrário do que a
linha afirma.

Essa linha é boa. Depois de instruída, a pessoa a lê num relance, e cada peça
dela já teve sua decisão própria. **O problema não é o layout — é a primeira
leitura.** Por isso a dica não reorganiza nada: ela ensina a ler o que já está
lá, e depois some. Uma feature que diluísse a linha estaria competindo com o que
deveria estar explicando.

Há também o que a barra não tem espaço para dizer, e que é a única informação
acionável do conjunto: **quanto o ritmo precisa cair** para a cota chegar
inteira até a renovação.

## Onde a dica aparece

Uma linha nova, abaixo das que já existem, com rótulo da fonte:

```
 sip │ fix/backend-type-errors │ ●2 │ +453 −10 │ ▲ 99%·45m │ $32.80 │ ✱ Opus 5 (1M context)
 ▓▓▓░ 33% (330k/1.0M) │ 🕐 5h:12% ⟳23:20·1h7m · 7d:23% ⟳Fri·2d8h │ BMAD 56/85 ▸5
 Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava
```

O rótulo por fonte resolve dois problemas de uma vez. Diz **de quem** é a dica,
num rodapé que mistura sessão, plano e provedor; e dispensa eleger uma fonte
vencedora — se Flow e 7d projetam bloqueio ao mesmo tempo, são duas linhas, cada
uma falando por si.

O mecanismo já existe e não precisa de nada novo no núcleo: `sl_render_all`
**pula linhas que renderizam vazio**. Uma linha configurada com o widget `tip`
simplesmente não ocupa espaço enquanto não há o que dizer. É a mesma regra que
já faz o `→48%` verde não aparecer.

## O canal recusado, e por quê

O desenho inicial usava o transcript, via hook do plugin com `systemMessage` —
o bloco `⎿` onde o Claude Code escreve suas próprias dicas. Três spikes com
`claude -p --output-format stream-json` mediram o canal antes de recusá-lo.

**O que funciona.** `systemMessage` é o único caminho até o usuário: stdout de
hook nunca chega ao transcript (em `SessionStart`/`UserPromptSubmit` vira
**contexto do modelo**, o oposto do desejado), `suppressOutput` é aceito e
ignorado, `stopReason` exige `continue: false`, e exit 2 + stderr entrega ao
Claude, não a quem lê.

**O que impede.** O Claude Code antepõe `<hook_name> says: ` ao texto, e o
carimbo é aplicado **por linha**:

| Tentativa | Resultado medido |
| --------- | ---------------- |
| Linha única | `Stop says: 🔒 Flow projeta bloqueio…` |
| `\n` inicial | `Stop says: \nStop says: 🔒…` — dois prefixos |
| `\n\n` inicial | três prefixos |
| `\r` inicial | normalizado para `\n`; dois prefixos |
| `ESC[2K\r` | idem — o ANSI não escapa |
| `name` no grupo, `name` no comando, `matcher` | prefixo idêntico nos quatro |

Nenhum evento tem nome apresentável: `Stop says:` (11 colunas) é o mais curto,
`PostToolBatch says:` (20) e `UserPromptSubmit says:` (22) são piores, e
`PreToolUse:Read says:` carrega o matcher junto. `SessionStart` executa o hook e
**descarta** o `systemMessage`.

Um hack de terminal que dependesse de o Claude Code não sanitizar entrada
quebraria numa atualização silenciosa, e não é assim que este repositório toma
decisões.

**O que se perde ao recusar**, e é real: a dica no transcript persiste no
scroll, dá para reler depois, e comporta um parágrafo inteiro. A da barra é
efêmera e cabe em uma linha.

**O que se ganha:** o plugin continua sendo só uma statusline. Sem
`hooks/hooks.json`, sem processo novo a cada turno, sem escrever no transcript
de quem instalou, sem opt-out a documentar — e sem `says:`.

## Quando falar

A condição dura dias. Um aviso que se repete enquanto ela durar é ruído, e ruído
ensina a ignorar — o mesmo raciocínio que já mantém a projeção `→48%` fora da
barra quando ela é verde.

Fala-se **na virada e na piora**:

| Situação | Ação |
| -------- | ---- |
| Projeção cruza 100% pela primeira vez | Aparece |
| Projeção sobe de degrau (faixas de 25: 100‑125, 125‑150, …) | Reaparece |
| Data de bloqueio antecipa mais de 10% do tempo que faltava | Reaparece |
| Projeção estável dentro do mesmo degrau | Continua até expirar |
| Projeção cai abaixo de 100% | Some e **re-arma** o gatilho |

Sem degrau, um `112% → 113%` reapareceria. Sem a regra da data, uma projeção
parada escondendo uma trava que se aproximou não diria nada — e é a data, não o
percentual, que decide o que fazer hoje.

## Quando some

**No próximo prompt do usuário.** Não por relógio.

A diferença importa no caso em que a dica mais serve: a pessoa deixa uma tarefa
longa rodando e volta depois. Um timer de cinco minutos apagaria a dica
justamente aí; esperar pelo próximo prompt garante que ela esteve na tela quando
alguém olhou.

O sinal é o **`promptId`** do transcript. Ele identifica o turno, não a
mensagem: todas as entradas geradas enquanto o Claude trabalha — inclusive os
`tool_result`, que são mensagens `user` — herdam o promptId do prompt que as
originou. Medido numa sessão real: 8 promptIds distintos para 8 prompts do
usuário, contra 84 entradas `"type":"user"`, das quais 71 eram `tool_result`.
**Contar mensagens `user` erraria por um fator de seis; o promptId acerta.**

Lê-se do fim do arquivo, sem varrer o transcript inteiro:

```bash
tail -n 40 "$SL_TRANSCRIPT" | grep -o '"promptId":"[^"]*"' | tail -1
```

Medido em 10 ms sobre um transcript de 2,9 MB, com o mesmo resultado de varrer
tudo. `tail -c` foi descartado: as últimas entradas costumam ser `attachment`,
que não carregam o campo, e um corte por bytes volta vazio.

O custo só é pago quando existe dica pendente. Sem estado, o widget termina no
primeiro `[ -f ]`.

## A meta de corte

A projeção é `used + ritmo × tempo_restante`. Pousar em exatamente 100% exige o
ritmo `(100 − used) / tempo_restante`. A razão entre os dois elimina o tempo e o
ritmo de uma vez:

```
corte = (proj − 100) / (proj − used)
```

Nada de relógio, nada de taxa, e a mesma expressão serve às três fontes. Com
`used = 25` e `proj = 116`: `16 / 91 = 17,6%`.

O número importa porque a intuição erra feio aqui — uma projeção de 116% sugere
"preciso cortar pela metade", quando o corte real é menos de um quinto. Uma
dica que só assusta é pior que nenhuma; a pessoa desliga.

Guarda: `proj > used` sempre vale quando `proj > 100` e `used ≤ 100`. Se a
desigualdade não valer — payload estranho, `used` fora de faixa — a meta é
omitida e o resto da frase continua de pé.

## Peças

```
widgets/tip.sh    registra o widget e renderiza a linha
lib/tips.sh       lê as fontes, aplica a regra, monta a frase
tip-state.tsv     o que já foi mostrado, e em que turno
```

**Nenhum widget existente é modificado.** Um rascunho anterior fazia `flow` e
`rate-forecast` publicarem o que já haviam calculado numa variável global, para
um passo pós-render consolidar. Isso não funciona, e o motivo está na decisão de
[canal-de-retorno](../decisions/2026-08-08-canal-de-retorno.md): o núcleo captura
widgets com `out="$("$fn")"`, que é command substitution — **subshell**. Uma
global atribuída dentro de um widget morre no retorno. O isolamento que aquela
decisão celebrava ("é impossível um widget vazar estado para o seguinte") é
real, e vale contra nós também.

Medido, para não restar dúvida:

```
stdout capturado: [render-ok]
global sobreviveu:  []
```

Então o `tip` é autossuficiente: lê as mesmas fontes que os outros widgets leem,
na hora de renderizar.

| Fonte | De onde o `tip` lê |
| ----- | ------------------ |
| Flow | `flow-consumption.json`, que já traz `projected_percentage` e `blocked_epoch` prontos |
| 5h / 7d | `$SL_FORECAST_BIN`, com `SL_5H_PCT`/`SL_5H_RESET` e `SL_7D_PCT`/`SL_7D_RESET`, exatamente como `_rf_window` faz |

### A segunda chamada ao forecast é inofensiva

Chamar `bin/rate-forecast.sh` uma segunda vez no mesmo repaint **não** grava
amostra espúria. O bin só registra quando `now − last_ts ≥ SAMPLE_EVERY` (60 s):
como o widget `rate-forecast` já amostrou no mesmo segundo, a chamada do `tip`
cai no `elif` e não escreve nada.

Isso derruba a objeção que havia motivado o desenho por globais. O custo real é
um fork por janela configurada, pago só quando o widget `tip` está na
configuração.

### O tip só fala do que está na tela

Antes de calcular qualquer coisa, o `tip` verifica se a fonte tem widget
configurado, procurando `flow` e `rate-forecast` em `$SL_CONFIG_LINES`. Quem
tirou o `rate-forecast` da barra não vê `→116%`, e uma dica que explica o que a
pessoa está vendo não teria o que explicar.

É também o que impede o efeito colateral do item anterior de virar um: sem o
widget `rate-forecast` na configuração, o `tip` não chama o bin, e ninguém
amostra por conta própria.

### Uma linha por fonte

O widget emite as fontes separadas por `\n`, e o núcleo as preserva — verificado
contra `sl_render_line`. É por isso que o `tip` **precisa ficar sozinho na sua
linha** de configuração: dividindo a linha com outro widget, o `\n` quebraria a
montagem de separadores no meio.

### Estado

Um arquivo, em `$SL_CACHE_DIR`
(`${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline`), TSV para dispensar
`jq`. Uma linha por fonte que já falou:

```
tip-state.tsv   fonte  degrau  blocked  prompt_id
```

O fato observado não é guardado — ele é recalculado a cada repaint, das fontes.
O que precisa de memória é só o que já foi dito: `degrau` para a regra de piora,
`blocked` para a regra dos 10%, e `prompt_id` para saber se ainda é o mesmo
turno. Uma piora regrava `prompt_id` com o turno corrente — é assim que a dica
reaparece, sem código de reexibição.

Fonte que deixa de projetar bloqueio tem sua linha removida; arquivo vazio é
apagado. Ausência é o estado normal.

## As frases

Uma linha, com rótulo da fonte, em 80 colunas ou menos:

```
Dica do Flow: →116% é projeção, não gasto — cortar 18% do ritmo evita a trava   (77)
Dica da janela 7d: →134% é projeção, não gasto — cortar 25% do ritmo evita      (74)
Dica da janela 5h: →118% é projeção — cortar 12% evita 50 min parado            (68)
```

**A dica não repete data nenhuma.** O primeiro rascunho dizia "trava sex 22/08,
2 dias antes de renovar" — e essa informação já está na linha de cima, no
`🔒 Fri·2d8h` e no `⟳`, onde teve sua própria decisão de formato. Repeti-la
custava trinta colunas para não acrescentar nada, e foi o que estourou os 80
caracteres.

Sobra exatamente o que a barra **não** consegue dizer: que o número é projeção e
não consumo, e quanto o ritmo precisa cair. As duas coisas pelas quais a feature
existe.

O limite de 80 colunas é requisito, não meta. A statusline vive num rodapé de
altura fixa; uma linha que estoure a largura é truncada ou quebrada por fora do
nosso controle, e o que se perde é o fim da frase — justamente a meta de corte.

**"No ritmo atual", e nunca "no ritmo das últimas 3h".** Um rascunho anterior
dizia a segunda coisa, e ela é indefensável: o `flow-consumption.json` entrega
`projected_percentage` pronto, sem informar sobre que período foi medido, e o
`bin/rate-forecast.sh` reporta o **maior** entre duas projeções — a da média da
janela e a do ritmo recente — de modo que nem o `LOOKBACK` descreve o que de
fato gerou o número. Nomear uma janela que a fonte não afirma é inventar
precisão, e numa frase cujo propósito é ensinar a ler um número isso é o pior
erro possível.

**O 5h troca "não gasto" pela duração da pausa**, porque é isso que muda a
decisão ali: a janela renova em horas, então o custo de estourar não é um
bloqueio, é ficar parado 50 minutos. E ele só fala se `reset − blocked ≥
15 min` — travar quatro minutos antes da janela virar não vale uma linha.

**A sugestão de modelo fica fora.** Ela cabia no parágrafo do transcript; numa
linha só, disputa espaço com a meta de corte, que é mais acionável e sempre
verdadeira. O plugin não sabe o que a pessoa está fazendo, e conselho que não se
aplica ensina a ignorar a dica.

## Configuração

O `tip` é um widget como os outros. Entra numa linha própria:

```json
{ "lines": [ "repo branch git-status cost model", "context rate-forecast flow", "tip" ] }
```

Linha sem conteúdo não é desenhada, então uma terceira linha com só o `tip`
não ocupa nada enquanto não há dica. Tirar o widget da configuração desliga a
feature — não há chave nova, nem default a discutir.

O `/setup` e o README precisam incluir a linha na configuração sugerida; caso
contrário a feature existe e ninguém a vê.

## O que fica de fora, e por quê

**O canal do transcript.** Medido e recusado acima. A evidência fica registrada:
se um dia fizer falta, os três spikes não precisam ser refeitos.

**Sugestão de ação por modelo.** Ver acima — cabia no parágrafo, não cabe na
linha.

**Granularidade por fonte** (`"tips": {"5h": false}`). O 5h é o mais falante e
seria o primeiro candidato a desligar sozinho. Fica de fora até haver queixa
real: a regra dos 15 minutos já corta o caso ruidoso, e desligar o widget
inteiro já é possível.

**Dica de melhora** ("seu ritmo caiu, a cota agora chega inteira"). Simétrica e
tentadora, mas ninguém precisa ser avisado de que um problema deixou de existir.

## Testes

`tests/tips.bats` — as funções de `lib/tips.sh`, isoladas:

- `_tip_cut`: `116/25 → 18`; `proj ≤ used` devolve vazio
- `_tip_step`: `101→0`, `124→0`, `125→1`, `150→2`, `999→3` (teto); `100` recusa
- `_tip_prompt_id`: lê o último do fixture; transcript ausente devolve vazio
- `_tip_should_show`: sem estado mostra; mesmo degrau e mesmo turno mostra;
  mesmo degrau e turno novo cala; degrau maior mostra e regrava
- antecipação da data: acima de 10% mostra, abaixo cala
- `_tip_phrase`: as três frases, cada uma com ≤ 80 colunas

`tests/widgets/tip.bats` — a renderização, com fixtures de fonte:

- sem fonte em alerta: saída vazia (e a linha some inteira)
- Flow em alerta: renderiza a frase do Flow
- `rate-forecast` fora de `SL_CONFIG_LINES`: 5h/7d não falam
- duas fontes simultâneas produzem duas linhas, ordem estável
- transcript ausente: renderiza mesmo assim (falha mostrando)
- `tip-state.tsv` corrompido: renderiza, sem erro
- 5h com `reset − blocked < 15 min` não fala

Toda asserção de ausência vem **depois** de uma contraprova no mesmo teste, na
última linha — `tests/helper.bash` documenta por quê: no bash 3.2 do macOS só a
última asserção de cada teste é de fato cobrada.

## Riscos residuais

**Frase que cresce.** As três frases cabem em 80 colunas hoje (77, 74, 68), mas
a folga é pequena e some com qualquer acréscimo — foi o que aconteceu com a
sugestão de modelo e com as datas repetidas. Qualquer texto novo precisa ser
medido, e o que cede é a frase, nunca o layout da barra.

**Data longa.** As larguras acima assumem `sex 22/08` fora da frase. Se algum
formato de data voltar para dentro dela, a conta muda — e o `sl_stamp_label`
produz rótulos de comprimento variável conforme a distância até o evento.

**Um repaint de atraso.** A dica nasce até cinco segundos depois da virada.
Aceitável por construção, mas é o preço de não depender da ordem das linhas, e
está escrito aqui para que ninguém o "conserte" sem saber o que estava
comprando.

**`promptId` é formato interno do transcript.** Não é API pública, e pode mudar.
O widget precisa tratar ausência do campo como "não sei" — renderizando a dica,
não escondendo: falhar mostrando é melhor que falhar calado, porque o alarme
`🔒` na linha de cima continua verdadeiro de qualquer jeito.
