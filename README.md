# claude-code-statusline

Uma statusline para o [Claude Code](https://claude.com/claude-code), construída a
partir de widgets pequenos e independentes.

```
✻ Opus 5 | feat/v0.1 ●3
5h:42%→70%
```

## Por que mais uma

Já existem boas statuslines para o Claude Code. Esta existe por causa de três
coisas que as outras não fazem, todas nascidas de usar o Claude Code no dia a dia
e não como demonstração:

**Previsão, não apenas relato.** `5h:42%` diz onde você está. Não diz se você vai
bater no teto antes de a janela resetar. O widget `rate-forecast` extrapola a
partir do seu ritmo de consumo e colore o resultado, de modo que `42%→116%` se lê
como "pare ou desacelere" três horas antes de você descobrir do jeito difícil.

**Provedores corporativos.** Muitos de nós não falamos com a API da Anthropic
diretamente. Passamos por um gateway da empresa, com quota própria, painel
próprio e um jeito próprio de acabar. Esse consumo pertence à mesma linha que
todo o resto.

**Fluxo de trabalho, não só estado da máquina.** Modelo, branch e contagem de
tokens são fatos sobre o processo. Se a sprint atual está saudável é um fato
sobre o trabalho. O segundo é mais difícil de expor e mais fácil de esquecer.

## Status

v0.1. O contrato de widget está estabelecido e coberto por testes. Quatorze
widgets estão disponíveis hoje — `model`, `repo`, `branch`, `git`, `git-status`,
`worktree`, `context`, `velocity`, `cache`, `cost`, `rate-forecast`, `sprint`,
`flow` e `command` — cada um exercitando uma parte diferente do contrato: sem
estado, estado em cache, aritmética pura, sequências de escape de terminal e
processos externos com cores semânticas.

O `command` é a válvula de escape: ele roda qualquer programa e renderiza a
saída, de modo que uma fonte de dados da qual o plugin nunca ouviu falar exige
configuração em vez de código.

O `flow` é específico da empresa e vem com o próprio fetcher. Este repositório é
privado e destinado a colegas da CI&T; o widget é inerte em qualquer outro lugar,
então nada quebra se você nunca o configurar.

O `git` é o `branch` e o `git-status` fundidos em um. Use o `git` sozinho, ou os
outros dois — nunca os três, ou o mesmo `git status` roda duas vezes por repaint.

## Requisitos

| | |
|---|---|
| `bash` | 3.2 ou mais recente |
| `jq` | obrigatório na prática — quase todo campo vem do parse do JSON da sessão |
| `git` | opcional; só os widgets que conhecem git precisam dele |

Bash 3.2 não é erro de digitação. O macOS ainda entrega `/bin/bash` 3.2.57 e
sempre vai entregar: o bash 4.0 migrou para a GPLv3, que a Apple não distribui.
Mirar no 3.2 significa que o plugin funciona num Mac de fábrica, sem passo de
`brew install`. Tudo aqui roda sem alteração no bash 5.

## Instalação

```
/plugin marketplace add nidelson/claude-code-statusline
/plugin install claude-code-statusline
/claude-code-statusline:setup
```

O comando de setup faz backup do `settings.json`, escreve a chave `statusLine` e
cria uma configuração padrão caso você não tenha uma. Reinicie o Claude Code
depois.

Para ligar na mão, aponte `statusLine.command` para o `bin/statusline.sh`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /caminho/para/claude-code-statusline/bin/statusline.sh",
    "padding": 0,
    "refreshInterval": 5
  }
}
```

`padding: 0` remove o recuo de duas colunas que o Claude Code aplica por padrão.
Os widgets já compõem o próprio espaçamento, e a largura importa: a primeira
linha do default passa de oitenta colunas em repositório de nome longo.

## Plataformas

| plataforma | estado |
|---|---|
| macOS | suportado, testado em CI |
| Linux | suportado, testado em CI |
| Windows dentro do WSL | suportado — ali tudo é Linux |
| Windows com Git Bash | suportado, testado em CI |
| Windows sem Git Bash | **não suportado** |

No Windows, o Claude Code roteia a statusline pelo Git Bash quando ele está
instalado, e pela PowerShell quando não está. Este plugin é bash, então precisa
do primeiro caso — e o Git for Windows já traz o Git Bash.

Sem Git Bash, o `setup` para e explica, em vez de escrever uma configuração que
não pode funcionar. Uma statusline configurada que nunca executa é pior que
nenhuma: o Claude Code deixa de mostrar a linha padrão e nada indica o motivo.

Duas notas para quem usa Windows:

- O `jq` não acompanha o Git Bash. Instale com `winget install jqlang.jq` ou
  `scoop install jq`.
- O caminho no `settings.json` precisa de barras normais (`C:/Users/...`). O
  `setup` já escreve assim; editando à mão, não use contrabarras — o Git Bash as
  consome como escape e a statusline falha em silêncio.

No CI o Windows roda um subconjunto de 222 dos 546 testes: as bibliotecas, o
núcleo e o entrypoint, que é onde as diferenças de plataforma aparecem. A suíte
inteira leva mais de vinte minutos naquele runner, contra um minuto e meio nos
outros.

> O suporte a Windows é verificado no CI, sob o mesmo Git Bash que o Claude Code
> usa. A execução ponta a ponta pelo próprio Claude Code ainda não foi
> confirmada por um usuário — se você rodar, conte como foi.

## Configuração

`${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-statusline/config.json`:

```json
{
  "version": 1,
  "lines": [["model", "git", "worktree"], ["rate-forecast"]],
  "separator": "|",
  "icons": true,
  "widgets": {
    "git": { "color": "cyan" },
    "rate-forecast": { "window": "7d" }
  }
}
```

| Chave | Tipo | Padrão | Significado |
|---|---|---|---|
| `version` | número | — | Versão do formato de configuração. Reservado; ainda não é validado. |
| `lines` | lista de listas | `[["model","git"],["rate-forecast"]]` | Uma lista interna por linha renderizada, com os widgets da esquerda para a direita. |
| `separator` | string | `\|` | Colocado entre os widgets de uma linha, cercado de espaços. |
| `icons` | booleano | `true` | Liga ou desliga os glifos dos widgets. Os glifos são Unicode comum (`✻`, `◆`), não Nerd Font — nenhuma fonte extra necessária. |
| `widgets` | objeto | `{}` | Opções por widget, indexadas pelo nome do widget. |

Todo widget aceita a opção `color`: `red`, `green`, `yellow`, `blue`, `magenta`,
`cyan`, `dim`. Ela é ignorada pelos widgets cuja cor é semântica — veja
`--self-color` abaixo.

Um nome de widget que o plugin não reconhece é ignorado em silêncio, de modo que
uma configuração escrita para uma versão mais nova continua funcionando numa mais
antiga.

**Uma configuração malformada nunca é reescrita.** O plugin cai nos padrões em
memória, mostra um `⚠` e deixa o seu arquivo exatamente como você o deixou, para
que você possa corrigi-lo.

## Widgets

### `model`

O modelo ativo. Modelos da Anthropic renderizam no coral da marca Claude
(`#D97757`); qualquer outro renderiza em magenta, de modo que a troca para um
provedor diferente é visível de relance, em vez de ser algo que você precisa ler.

A cor é semântica — a opção `color` não se aplica.

### `repo`

Nome do repositório, embrulhado num hyperlink OSC 8 para o remoto, de modo que o
nome é clicável.

| Opção | Valores | Padrão |
|---|---|---|
| `link` | `true`, `false` | `true` |
| `ttl` | segundos | `300` |

Dentro de um worktree linkado ele ainda mostra o nome do repositório
**principal** — o widget `worktree` é o que diz em qual worktree você está. Uma
fórmula cobre os dois casos: o nome é `basename(dirname(git-common-dir))`, e o
diretório comum aponta para o `.git` do repositório principal de qualquer forma.

URLs de clone são convertidas em navegáveis: estilo scp (`git@host:caminho`),
`ssh://`, `git+ssh://`, `http(s)://` e Azure DevOps por SSH — cujo host web é
diferente e cujo caminho ganha um segmento `_git`, e por isso não pode ser
derivado trocando `:` por `/`. Qualquer outra coisa renderiza como texto puro; um
link errado é pior que link nenhum.

Credenciais num remoto `https://` são removidas. Sem isso, um remoto com token
embutido viraria um hyperlink carregando o token, visível no terminal e copiado
junto com o link.

Terminais sem suporte a OSC 8 ignoram a sequência, então o fallback é o nome puro
sem necessidade de detecção. Defina `link: false` se o seu fizer algo pior que
ignorar.

### `branch`

A branch atual sozinha, para quando você quer a branch e o estado da árvore de
trabalho em lugares ou cores diferentes. Num HEAD destacado, mostra o sha curto
prefixado com `@`.

Onde o `git` combina os dois, este separa — use um ou outro, nunca ambos.

O cache dele observa o `.git/HEAD`, e essa é a sentinela certa aqui pelo mesmo
motivo que era a errada para o contador de sujeira: o `HEAD` guarda
`ref: refs/heads/<branch>` e é reescrito no checkout, mas não no commit. O mtime
dele muda exatamente quando a branch muda.

O `mtime` tem resolução de um segundo, então trocar de branch e repintar dentro
do mesmo segundo ainda pode mostrar a branch anterior. A statusline repinta a
cada poucos segundos de qualquer forma.

### `git`

Branch atual, mais um contador de sujeira quando a árvore de trabalho não está
limpa (`feat/v0.1 ●3`). Não renderiza nada num HEAD destacado.

| Opção | Valores | Padrão |
|---|---|---|
| `ttl` | segundos; `0` desliga o cache | `2` |

O contador de sujeira não pode ser invalidado observando um arquivo. Editar um
arquivo não toca em nada dentro do `.git` — nem no `HEAD`, nem no index — porque
a informação vive na comparação entre a árvore e o index, não em disco. Então o
cache é por tempo, e o `ttl` é o teto explícito de quão velho o número pode
ficar.

Aumente-o num repositório grande, onde o `git status` custa tempo de verdade.

### `git-status`

Estado da árvore de trabalho e distância do upstream: `●3 ↑1 ↓2` — três arquivos
sujos, um commit que falta ao upstream, dois commits que faltam a você. Amarelo,
verde, vermelho.

| Opção | Valores | Padrão |
|---|---|---|
| `ttl` | segundos; `0` desliga o cache | `2` |

Limpo e em sincronia não renderiza nada. Um indicador de "está tudo bem" ocuparia
espaço permanentemente para não dizer nada.

Ele custa uma chamada ao `git`, não duas. A original usava `status --porcelain`
para o contador de sujeira e `rev-list --left-right --count HEAD...@{upstream}`
para o resto, mas `status --porcelain --branch` coloca os dois números no
cabeçalho:

```
## main...origin/main [ahead 1, behind 2]
 M arquivo
```

Como o custo do git é quase todo criação de processo, ler o cabeçalho corta o
preço pela metade para a mesma informação.

Os contadores são extraídos de dentro dos colchetes, e não do cabeçalho como um
todo, de modo que uma branch de fato chamada `ahead` ou `behind` não pode ser
confundida com informação de rastreamento. Um cabeçalho sem colchetes — sem
upstream, ou com um upstream `[gone]` — simplesmente não produz contadores.

Como o `git`, ele usa cache por tempo; veja aquele widget para entender por que
nenhum arquivo serve de sentinela para uma árvore suja.

A cor é semântica — a opção `color` não se aplica.

### `worktree`

O nome do diretório de um worktree linkado, e absolutamente nada na árvore de
trabalho principal — o objetivo é sinalizar "você não está no checkout de
sempre". Fica quieto quando o nome do diretório já coincide com o nome da branch,
já que o `git` está mostrando isso de qualquer forma.

### `context`

Uso da janela de contexto como barra em gradiente, seguida do percentual e das
contagens de tokens: `████▌░░░░░░ 23% (45k/200k)`. O percentual é verde, amarelo
a partir de 70%, vermelho a partir de 90%.

| Opção | Valores | Padrão |
|---|---|---|
| `width` | células da barra | `20` |
| `tokens` | `true`, `false` — mostra o sufixo `(usado/total)` | `true` |

A barra renderiza em oitavos usando caracteres de bloco Unicode, então uma barra
de 20 células tem 160 passos em vez de 20. Na resolução de bloco cheio cada passo
é 5% e a barra fica parada durante boa parte da sessão antes de saltar; em
oitavos ela se move continuamente.

O uso vem de `total_input_tokens`, o acumulador da sessão, que é o número que a
própria interface do Claude Code reporta. O uso da última troca subestima o
contexto real em cerca de 9%.

Uma janela pode ser estourada por uma única troca grande. O percentual então
passa de 100 — isso é informação real —, mas a barra para na largura configurada,
porque uma barra que cresce além do próprio trilho empurra o resto da linha para
o lado.

A cor é semântica — a opção `color` não se aplica.

### `velocity`

Linhas adicionadas e removidas nesta sessão: `+10 -2`, verde e vermelho.

Cada metade só aparece quando tem valor, e o widget desaparece por completo
quando nada mudou. A original sempre imprimia `+0 -0`, o que numa sessão gasta
lendo código é ruído permanente — espaço gasto para dizer que nada aconteceu.

As contagens são exatas, nunca abreviadas. `+1.2k` esconderia a diferença entre
1200 e 1249 e, ao contrário do que acontece com tokens, essa diferença importa
aqui.

A cor é semântica — a opção `color` não se aplica.

### `cache`

Taxa de acerto do cache de prompt e quanto falta para ele expirar:
`☁ 70%·4m12s`.

| Opção | Valores | Padrão |
|---|---|---|
| `countdown` | `always`, `near`, `off` | `always` |
| `write` | `true`, `false` | `true` |
| `label` | texto do prefixo com `icons: false`; `""` remove | `cache:` |

**A taxa** é o total de leituras de cache sobre a soma de leituras, escritas de
cache e tokens de entrada novos. Verde a partir de 70%, amarelo a partir de 30%,
vermelho abaixo. É um velocímetro, não um hodômetro: os contadores vêm de
`current_usage`, que descreve apenas a troca mais recente.

Não aparece quando os três contadores são zero. Uma taxa de acerto sobre zero
tokens não é 0%, é indefinida — imprimir `0%` afirmaria que o cache errou quando
nada lhe foi pedido.

**O countdown** diz quando o prefixo em cache expira. Passado esse ponto, a
próxima troca paga a gravação inteira de novo, e um token gravado custa vinte
vezes um token lido. Verde acima de três minutos, amarelo abaixo, vermelho
abaixo de um minuto e em `cold`.

Os segundos só aparecem abaixo de cinco minutos — `58m`, `5m`, `4m59s`, `47s`.
Cinco minutos é o tamanho da menor janela contratável, então numa conta de cinco
minutos a regressiva inteira mostra segundos, que é onde eles servem. Acima
disso seriam um dígito piscando a cada repaint para dizer o que ninguém lê nessa
resolução.

Os limites são absolutos, não proporcionais à janela: a pergunta que o countdown
responde — dá tempo de escrever o próximo prompt antes de o cache esfriar? — tem
duração humana. Numa conta com janela de uma hora ele quase não sai do verde,
porque ali raramente se perde o cache; numa de cinco minutos acende o tempo
todo, porque ali se perde mesmo.

**O alarme** marca a troca que gravou muito no cache: `▲54k`. Amarelo a partir
de 10k tokens, vermelho a partir de 50k, invisível abaixo disso.

Gravação é o que custa caro — um token gravado vale vinte lidos — e ela é
concentrada, não difusa: numa sessão medida, 33 trocas de 943 carregaram 85% de
tudo que foi gravado. São compactação, skill grande injetada, arquivo grande
lido, conjunto de ferramentas alterado. O limiar de 10k fica três vezes acima do
p90 de gravação por troca, então o alarme não acende na rotina.

`write: false` desliga.

A janela não se configura: sai de `ephemeral_1h_input_tokens` e
`ephemeral_5m_input_tokens` no transcript, então a mesma configuração serve a
uma máquina com uma hora e a outra com cinco minutos.

`countdown: near` mostra o tempo só a partir do limite amarelo, e sempre quando
o cache já esfriou. `countdown: off` desliga.

O countdown depende de `transcript_path`, que vem no payload, e do arquivo
existir e ser legível. Faltando qualquer um, ele some sozinho e a taxa
permanece — e vice-versa: entre trocas, `current_usage` vem null e o widget
mostra só o tempo.

Com `icons: false` o `☁` dá lugar ao texto de `label`, e o `▲` a `w:`.

A cor é semântica — a opção `color` não se aplica.

### `cost`

Custo acumulado da sessão: `$3.50`.

| Opção | Valores | Padrão |
|---|---|---|
| `warn` | valor em USD | não definido |
| `crit` | valor em USD | não definido |
| `color` | um nome da paleta | `yellow`, ou `green` quando há limiar definido |

Sem limiares, o widget apenas reporta, em amarelo. Defina `warn` ou `crit` e ele
vira um semáforo: verde abaixo de `warn`, amarelo a partir de `warn`, vermelho a
partir de `crit`. O piso fica verde de propósito — deixá-lo amarelo faria a
travessia de `warn` repintar amarelo sobre amarelo, e o aviso seria invisível.

Valores são formatados sob `LC_ALL=C`. Num locale em que o separador decimal é a
vírgula, o `printf` do bash rejeita `0.0234` de saída: imprime `$0,00` e escreve
no stderr. O valor chega do JSON, onde o separador é sempre o ponto, então a
formatação tem de concordar com isso independentemente da máquina.

### `rate-forecast`

As duas janelas de rate limit, cada uma com uso atual, previsão de estouro,
horário do reset e contagem regressiva:

```
⏱ 5h:31%→93% ⟳ 02:10·1h48m · 7d:15% ⟳ Fri·5d6h
```

A janela de cinco horas responde "posso continuar agora"; a de sete dias responde
"quando eu paro". As duas ficam sempre visíveis, de modo que o widget mantém
largura constante e você aprende como é o normal.

| Opção | Valores | Padrão |
|---|---|---|
| `window` | `5h`, `7d`; omita para mostrar as duas | omitido |
| `warn` | percentual de uso que fica amarelo | `50` |
| `crit` | percentual de uso que fica vermelho | `80` |
| `separator` | texto entre as duas janelas | `·` |
| `reset` | `true`, `false` — mostra horário do reset e regressiva | `true` |

`window` filtra em vez de escolher: deixe de fora para as duas janelas, defina
para mostrar apenas uma.

**Duas cores, duas perguntas.** O uso atual é verde abaixo de `warn`, amarelo a
partir de `warn`, vermelho a partir de `crit`. A projeção, por sua vez, tira a
cor do nível devolvido pelo helper. Um `31%` verde ao lado de um `→93%` amarelo
não é contradição — é uso baixo com ritmo alto, que é exatamente o que se quer
enxergar.

**A projeção só aparece quando pede reação.** Nível `ok` não vira texto: no
exemplo acima a janela de sete dias não mostra projeção nenhuma porque o ritmo
dela está tranquilo. Um `→48%` verde ocupa espaço permanente para dizer "siga em
frente", que já era o estado padrão de quem não vê aviso — e o olho que aprende a
ignorar a seta deixa de ver o dia em que ela vira `→116%`. Silêncio aqui é
informação: seta na tela significa que alguma coisa mudou.

O reset mostra o horário abaixo de 24 horas, o dia da semana entre um dia e uma
semana, e dia e mês acima disso — escolhido pelo tempo restante e não pela
janela, de modo que uma janela de sete dias que reseta em quatro horas ainda
mostra a hora. Acima de uma semana o nome do dia deixaria de identificar: "Tue"
a vinte dias descreve três terças diferentes. Horário e regressiva ficam
esmaecidos: são contexto para os números, não concorrentes deles.

A regressiva mostra duas unidades, e omite a menor quando ela é zero: `20d` em
vez de `20d0h`, `3h` em vez de `3h0m`. Quando ela não é zero, fica — `1d3h` diz
o que `1d` não diz.

**Quando a projeção estoura, o cadeado diz quando.** `→118%` significa que a
janela acaba antes de resetar; a pergunta seguinte é a única que muda o que fazer
hoje:

```
⏱ 5h:70%→117% 🔒 06:17·1h17m ⟳ 07:00·2h
```

Trava às 06:17, libera às 07:00. O carimbo do bloqueio vem **antes** do reset
porque é a data que chega primeiro — lidos na ordem, os dois contam a história
inteira, e a folga entre eles é o que decide se dá para seguir no ritmo.

O limiar é 100% físico, não o `crit` configurável: cem por cento é onde o
bloqueio acontece, independentemente de onde você pôs a cor. O ritmo usado é o
mesmo que gerou a projeção exibida, e não uma segunda estimativa que a
contradiria.

O 🔒 sai dourado mesmo dentro do vermelho, porque emoji ignora ANSI — quem
carrega a cor é a data ao lado. Com `icons: false` ele vira `blocked:`, e a
palavra existe para distinguir os dois carimbos: sem ela seriam duas datas
anônimas lado a lado, e a que sobra sem rótulo é o reset.

Qualquer pedaço ilegível apaga só a si mesmo. Um reset malformado descarta os
tempos e mantém o percentual; um helper ausente descarta a projeção e mantém
todo o resto. `resets_at` é aceito como epoch em segundos, epoch em
milissegundos ou string ISO 8601.

Os dois glifos respeitam `icons: false`.

A aritmética da previsão vive num processo à parte, `bin/rate-forecast.sh` — ela
precisa de estado em disco entre repaints, e o widget não. O contrato é fechado,
de modo que você pode trocar o modelo de previsão sem tocar no plugin:

```
$SL_FORECAST_BIN <label> <used_pct> <resets_at_epoch> <window_seconds>
→ stdout: "<nível> <projeção> [<bloqueio_epoch>]"   nível ∈ none|ok|warn|crit
→ exit:   0, sempre
```

O terceiro campo é opcional e só aparece quando a projeção passa de 100% e o
estouro cai antes do reset. Ele é o **último** justamente para que um helper de
antes dele continue válido: quem emite dois campos segue funcionando, e o widget
apenas não desenha o cadeado.

`none` e `ok` renderizam igual — sem projeção. A diferença entre "não sei
estimar" e "estimei, está tranquilo" não muda nada para quem lê a statusline, e
o helper continua distinguindo os dois para quem quiser inspecioná-lo.

O `SL_FORECAST_BIN` aponta por padrão para o helper que acompanha o plugin, então
a previsão funciona numa instalação limpa. Aponte-o para outro caminho para usar
o seu. Sem helper algum, o widget ainda mostra o percentual atual — uma leitura
degradada é melhor que leitura nenhuma.

**Dois estimadores.** A média da janela enxerga o acumulado e reage devagar; o
ritmo recente enxerga a rajada e esquece o que já foi queimado. O nível final é o
arredondamento para cima da média dos dois, de modo que concordância vira sinal
forte e divergência vira amarelo. O número mostrado é a pior das duas projeções:
teto no número, confiança na cor.

Os limiares de tempo do ritmo recente derivam da duração da janela — a janela
móvel é um décimo dela, o span mínimo entre amostras é um sessenta avos, ambos
com piso nos valores da janela de cinco horas. Uma constante em segundos não
sobrevive à troca de janela: extrapolar um span de minutos sobre os dias que
faltam numa janela de sete dias transforma ruído de medição em projeção de
centenas por cento — foi assim que um único incremento de 1 ponto percentual, na
resolução em que a statusline entregava o número, virou um `7d:25%→670%`. Ajuste
com `CLAUDE_RATE_LOOKBACK` e `CLAUDE_RATE_MIN_SPAN` se quiser outra calibragem;
`CLAUDE_RATE_WARN` e `CLAUDE_RATE_CRIT` movem os limiares de nível da projeção,
que são `85` e `100`.

A cor é semântica — a opção `color` não se aplica.

### `sprint`

Saúde da sprint para projetos que mantêm o estado dela num arquivo:
`BMAD 7/10 ▸2 ⊙1` — stories concluídas sobre o total nos épicos ativos, duas na
fila para desenvolvimento, uma aguardando revisão. A razão é verde a partir de 80%
concluído, amarela a partir de 40%, vermelha abaixo disso.

| Opção | Valores | Padrão |
|---|---|---|
| `label` | nome da metodologia, à frente dos números; `""` remove | `BMAD` |
| `path` | caminho do arquivo, relativo à raiz da árvore de trabalho | `_bmad-output/implementation-artifacts/sprint-status.yaml` |

O rótulo nomeia os números. Sem ele `7/10 ▸2 ⊙1` é uma contagem sem dono: a
linha já carrega outra razão, a do `context`, e um segundo par de números soltos
não diz de onde veio. O padrão é `BMAD` porque o caminho padrão também é — quem
troca o helper por outra metodologia troca o rótulo junto.

Este é o widget de metodologia. Os outros descrevem a máquina; este descreve o
trabalho. Ele não renderiza nada num projeto que não segue a convenção — sem
arquivo, nada a dizer —, então não há necessidade de desligá-lo projeto a
projeto.

O parse vive num helper externo, porque o formato é algo que os times adaptam.
Trocar de metodologia significa trocar o helper, não remendar o plugin:

```
$SL_SPRINT_BIN <caminho/para/arquivo>
→ stdout: "<feitas>/<total> <prontas> <revisão>", vazio quando não há sprint ativa
→ exit:   0, sempre
```

O `SL_SPRINT_BIN` aponta por padrão para `$HOME/.claude/sprint-health-line.sh`.
Sem ele o widget fica em silêncio — não há leitura parcial para a qual recorrer,
ao contrário do `rate-forecast`.

Dentro de um worktree linkado ele lê o arquivo daquele worktree, não o da árvore
principal: cada branch carrega o próprio estado de sprint.

Ao contrário dos widgets de git, este usa cache por `mtime`, e aqui isso é exato
— o estado da sprint de fato vive num arquivo, então o parse roda quando o
arquivo muda e somente então.

O contador de revisão usa `⊙`, onde a statusline original usava `⚠`. Aqui o `⚠`
já é o marcador de falha de entrada do núcleo, e os dois podem cair na mesma
linha. Uma story em revisão é um estado de fila, não um erro.

A cor é semântica — a opção `color` não se aplica.

### `flow`

Consumo na CI&T Flow Platform: as duas cotas, cada uma com uso atual, previsão de
estouro e data de renovação, mais um segmento de status para o que não cabe num
percentual.

```
💰 24%→92% ⟳ 31Aug·20d · 💬 14% · ∞
```

| Opção | Valores | Padrão |
|---|---|---|
| `metric` | `budget`, `requests`; omita para mostrar as duas | omitido |
| `separator` | texto entre os segmentos | `·` |
| `renewal` | `true`, `false` — mostra a data de renovação e a regressiva | `true` |
| `ttl` | segundos entre buscas | `300` |
| `refresh` | `true`, `false` — se deve buscar | `true` |
| `cache` | caminho do JSON buscado | `$XDG_CACHE_HOME/flow-consumption.json` |
| `bin` | caminho do fetcher | `bin/flow-consumption.sh` neste plugin |

Este é o widget de provedor corporativo. Passar por um gateway da empresa
significa uma quota com limite e renovação próprios, invisível ao rate limit da
Anthropic, e ela pertence à mesma linha que todo o resto.

**Duas cotas independentes**, do mesmo jeito que o `rate-forecast` tem duas
janelas: `budget` conta dinheiro, `requests` conta chamadas, e estourar uma não
diz nada sobre a outra. As duas ficam visíveis, e `metric` filtra em vez de
escolher — deixe de fora para ver ambas, defina para ver só uma.

**A renovação mora onde ela decide alguma coisa.** A data dá escala ao
percentual: `24%` não diz se sobra um dia ou três semanas para gastar o resto, e
é essa distância que decide se dá para manter o ritmo. Quando as duas cotas
renovam no mesmo instante — o caso de uma assinatura mensal única — repetir a
mesma data nos dois segmentos gastaria treze colunas para não dizer nada novo.
Então ela vai para onde serve:

```
só budget em alerta     💰 24%→92% ⟳ 31Aug·20d · 💬 14%
só requests em alerta   💰 24% · 💬 88%→110% ⟳ 31Aug·20d
ambos no mesmo estado   💰 24% · 💬 14% · ⟳ 31Aug·20d
datas diferentes        💰 24%→92% ⟳ 31Aug·20d · 💬 14% ⟳ 05Sep·25d
```

"Em alerta" é ter qualquer coisa amarela ou vermelha no segmento: uso a partir de
80% **ou** projeção a partir de 80%. Um budget em 85% sem projeção nenhuma puxa a
data do mesmo jeito, porque 85% consumido com vinte dias pela frente é exatamente
a pergunta que a data responde.

O formato é o mesmo do `rate-forecast`, inclusive o `⟳`: horário abaixo de 24
horas, dia da semana até uma semana, dia e mês acima disso. A regressiva omite a
unidade menor quando ela é zero — `20d`, não `20d0h`.

Uma renovação que não dá para formatar apaga só a si mesma: percentual e projeção
sobrevivem. Payload sem o campo renderiza como se a opção estivesse desligada.

**Quando a projeção estoura, o cadeado diz quando.** Uma projeção de 92% ainda
chega à renovação; uma de 130% não chega. Aí a pergunta deixa de ser "vou
estourar?" e vira "estouro quando?":

```
💰 24%→130% 🔒 Wed·5d ⟳ 22Jan·7d · 💬 14%
```

Trava na quarta, renova no dia 22 — e a folga entre os dois é a resposta. O
carimbo do bloqueio vem antes da renovação porque é a data que chega primeiro.
Quando as duas cotas travam, cada uma leva o próprio cadeado.

Ele **não** obedece a `renewal: false`: são perguntas diferentes. Quem desliga a
data de renovação está dizendo que não precisa saber quando o ciclo vira, não que
aceita ser bloqueado sem aviso.

Quem calcula é `bin/flow-consumption.sh`, que grava `blocked_epoch` no payload
quando a projeção passa de 100% — o widget não repete o limiar, a presença do
campo já é a condição. Um bloqueio que já passou desaparece sozinho.

**O terceiro segmento é o status**, e só aparece quando tem o que dizer:

| Marca | Significa |
|---|---|
| `∞` esmaecido | a cota de chamadas não tem teto |
| `⚠` vermelho | a última busca falhou |

O `∞` é fato calmo e tem peso calmo: ele explica por que o percentual ao lado não
vai bloquear ninguém. O `⚠` pede reação, então é vermelho — e por isso é
monocromático, e não emoji: emoji têm cor própria e ignoram ANSI, de modo que não
existe wifi vermelho em emoji, e um aviso que não consegue ficar vermelho não é
aviso.

Os dois podem aparecer juntos. Quando o `⚠` está lá, os números ao lado são a
última leitura boa — o fetcher preserva o payload e apenas marca a falha, então
`⚠` quer dizer "não consegui atualizar", não "não sei de nada". Sem leitura
anterior nenhuma, o aviso aparece sozinho.

Todos os glifos respeitam `icons: false`, e nesse modo viram palavras inteiras:

```
icons: true    💰 24%→130% 🔒 Wed·5d ⟳ 31Aug·20d · 💬 14% · ∞
icons: false   budget:24%→130% blocked:Wed·5d 31Aug·20d · requests:14% · unlimited
```

`budget:` e `requests:` são mais longos que uma abreviação seria, de propósito:
quem desliga os ícones costuma fazê-lo por causa do terminal, não por falta de
espaço, e a palavra inteira não exige que ninguém adivinhe o que `req` significa.
Ao contrário dos glifos monocromáticos do `rate-forecast`, os emoji têm cor
própria e ignoram o esmaecimento — é o preço de serem reconhecíveis de relance.

**As mesmas duas cores do `rate-forecast`.** Uso e projeção são pintados cada um
pelo próprio número: verde abaixo de 80%, amarelo a partir de 80%, vermelho a
partir de 100%. E, também como lá, projeção tranquila não vira texto — no exemplo
acima `req` não mostra seta porque o ritmo dela não pede reação.

**Um segmento some quando não há número.** Métrica ausente do payload desaparece;
projeção nula não vira `→0%`, porque a API nunca afirmou zero, ela afirmou nada.
Cota `unlimited`, por outro lado, **não** some: a API manda `unlimited: true`
junto com limite, contagem e percentual, e esconder tudo isso jogava fora dado
verdadeiro. O teto ausente é dito pelo `∞`, ao lado.

**Buscar e mostrar são coisas separadas, e os relógios delas também.** O
`bin/flow-consumption.sh` fala com a rede e escreve JSON; o widget apenas lê esse
JSON. Uma chamada de rede no caminho de renderização faria a statusline inteira
esperar pela latência do gateway, a cada repaint.

- A renderização é invalidada pelo mtime do JSON, então um número novo aparece no
  instante em que a busca termina, e não quando algum timer expira.
- A busca é limitada por um arquivo marcador, para que a API não seja martelada.

Um TTL único para os dois forçaria escolher entre mostrar números velhos e buscar
com frequência demais.

O marcador é escrito *antes* de a busca ser disparada, não depois: dois repaints
caindo quase no mesmo instante não podem virar duas buscas.

**Falha não apaga o que já foi lido.** O fetcher precisa do
`ANTHROPIC_AUTH_TOKEN` no ambiente. Quando ele falta — ou quando a rede cai, ou o
gateway responde errado — a busca registra um campo `error` **ao lado dos dados
que já estavam lá**, em vez de gravar `{"ok": false}` por cima de tudo. O
`fetched_at` continua marcando a idade do dado, e `error.at` marca a tentativa.

Isso importa mais do que parece: uma sessão iniciada sem o token zerava o widget
a cada TTL, e o número que existia dois minutos antes se perdia. Um número de dois
minutos atrás é verdadeiro; apagá-lo não é mais honesto, é só menos útil.

Numa máquina que nunca conseguiu ler nada, não há o que preservar, e o widget
mostra só o `⚠`. Numa máquina que nem tem o `flow` na configuração, o arquivo de
cache não existe e o widget não renderiza nada — silêncio continua sendo o
comportamento de quem não pediu esse widget.

### `command`

Roda um comando externo e mostra a saída. Esta é a válvula de escape: qualquer
fonte de dados, sem precisar escrever bash.

As instâncias são nomeadas `command:<nome>`, então você pode ter várias:

```json
{
  "lines": [["model", "command:flow", "command:weather"]],
  "widgets": {
    "command:flow": {
      "cmd": "~/.claude/flow-line.sh",
      "refresh": "~/.claude/flow-consumption-line.sh",
      "ttl": 60,
      "colors": true
    },
    "command:weather": { "cmd": "curl -s wttr.in/?format=3", "ttl": 900 }
  }
}
```

| Opção | Valores | Padrão |
|---|---|---|
| `cmd` | comando de shell que produz o texto | obrigatório |
| `refresh` | comando de shell rodado destacado quando o ttl expira | nenhum |
| `ttl` | segundos; `0` desliga o cache | `60` |
| `timeout` | segundos até o comando ser morto | `2` |
| `colors` | `true` preserva as sequências de cor da saída | `false` |
| `label` | texto prefixado à saída | nenhum |

**Ler e atualizar são separados de propósito.** O `cmd` produz o texto e precisa
ser rápido. O `refresh` é opcional, roda destacado e existe para aquecer o que o
`cmd` lê. Um fetcher que fala com a rede não pode rodar de forma síncrona — a
statusline inteira esperaria pela latência dele. Com os dois, o widget mostra o
resultado da rodada anterior e dispara a próxima em segundo plano.

**Saída de terceiros é higienizada.** Sequências de escape não são enfeite: OSC
52 escreve na área de transferência do usuário, OSC 0 e 2 mudam o título da
janela, e CSI move o cursor e pode embaralhar a tela. Por padrão nada passa. O
`colors: true` abre uma exceção estreita — SGR, o CSI terminado em `m`, que só
muda cor e estilo — e ainda assim remove o resto. Quebras de linha também são
colapsadas, já que a statusline compõe as próprias linhas.

**O `cmd` roda através de `bash -c`**, então `~` e `$VAR` expandem como você
esperaria ao escrever um caminho na configuração. Isso também significa que o
arquivo de configuração é conteúdo executável: trate-o com o mesmo cuidado que
trata o rc do seu shell.

**Timeouts funcionam sem coreutils.** O macOS não traz `timeout(1)` e, sem o
coreutils do Homebrew, também não há `gtimeout`. Quando nenhum dos dois existe, o
widget recorre a um watchdog em bash puro, de modo que um comando pendurado ainda
assim não consegue congelar a statusline.

## Escrevendo um widget

Um widget é um arquivo em `widgets/`. Ele se registra ao ser carregado e escreve
no stdout. Esse é o contrato inteiro. Aqui está o `widgets/model.sh` na íntegra,
com os comentários removidos:

```bash
register_widget model \
  --render widget_model_render \
  --self-color \
  --desc   "Active model name"

widget_model_render() {
  local needle icon=""

  [ -n "$SL_MODEL" ] || return 0
  [ "$SL_MODEL" = "Unknown" ] && return 0

  needle="$(printf '%s' "${SL_MODEL_ID:-$SL_MODEL}" | tr '[:upper:]' '[:lower:]')"
  case "$needle" in
    claude*|*anthropic*|*opus*|*sonnet*|*haiku*|*fable*)
      [ "${SL_CONFIG_ICONS:-1}" = "1" ] && icon='✻ '
      printf '%s%s%s%s' "$SL_BRAND" "$icon" "$SL_MODEL" "$SL_RESET" ;;
    *)
      [ "${SL_CONFIG_ICONS:-1}" = "1" ] && icon='◆ '
      printf '%s%s%s%s' "$(sl_color magenta)" "$icon" "$SL_MODEL" "$SL_RESET" ;;
  esac
}
```

Depois acrescente-o a `lines` na sua configuração. Só os widgets que a sua
configuração nomeia são carregados, então um widget não usado não custa nada.

As strings de `--desc` ficam em inglês por serem texto de interface de um plugin
publicável; comentários e documentação seguem em português.

### `register_widget`

| Flag | Obrigatória | Significado |
|---|---|---|
| `--render FN` | sim | Função que escreve o texto do widget no stdout. |
| `--color NOME` | não | Cor padrão, sobrescrevível pela configuração do usuário. |
| `--self-color` | não | O widget pinta a si mesmo e o núcleo o deixa em paz. Use quando a cor carrega informação em vez de preferência. |
| `--desc TEXTO` | não | Descrição de uma linha. |

### Lendo opções do usuário

```bash
sl_config_widget_opt <widget> <chave> [padrão]
```

Devolve o valor de `widgets.<widget>.<chave>` na configuração do usuário, como
string — números e booleanos inclusive, então `"tokens": false` volta como a
string `false`.

Passe um padrão quando tiver um. Ele é aplicado dentro do `jq`, contra a ausência
da chave — não no bash depois. Essa distinção importa: o bash não consegue
distinguir uma chave ausente de uma chave definida como `""`, então um fallback
do lado do bash sobrescreveria silenciosamente um vazio deliberado e tornaria
impossíveis opções como `"label": ""`.

### Regras

**Não imprima nada quando não tiver nada.** Saída vazia faz o widget sumir e leva
o separador junto. Não imprima `n/a` nem `-`.

**Nunca saia com código diferente de zero para sinalizar problema** — mas, se
sair, o núcleo captura e trata o widget como vazio. O resto da linha sobrevive
nos dois casos.

**Nunca presuma que uma dependência existe.** Degrade para menos informação em
vez de desaparecer.

### Variáveis de entrada

Extraídas do JSON da sessão numa única passada de `jq`, antes de qualquer widget
rodar.

| Variável | Conteúdo |
|---|---|
| `SL_MODEL` | Nome de exibição do modelo, ou `Unknown` |
| `SL_MODEL_ID` | Identificador do modelo |
| `SL_CWD` | Diretório de trabalho da sessão |
| `SL_COST` | Custo da sessão em USD |
| `SL_LINES_ADDED`, `SL_LINES_REMOVED` | Linhas alteradas nesta sessão |
| `SL_CTX_SIZE`, `SL_CTX_USED` | Tamanho da janela de contexto e tokens usados |
| `SL_INPUT_TOKENS` | Tokens de entrada novos, **apenas da última troca** |
| `SL_CACHE_READ`, `SL_CACHE_CREATE` | Tokens de leitura e criação de cache de prompt, **apenas da última troca** |
| `SL_5H_PCT`, `SL_5H_RESET` | Janela de cinco horas: percentual usado, epoch do reset |
| `SL_7D_PCT`, `SL_7D_RESET` | Janela de sete dias: percentual usado, epoch do reset |
| `SL_JQ_OK` | `1` quando o JSON da sessão foi parseado, `0` caso contrário |

### Cache

Dois helpers, para os dois jeitos de um valor envelhecer:

```bash
cache_by_mtime <chave> <arquivo-sentinela> <comando...>   # invalidado por arquivo que muda
cache_by_ttl   <chave> <segundos>          <comando...>   # invalidado por tempo
```

Use-os para qualquer coisa que crie um processo. A statusline repinta com
frequência suficiente para que um subprocesso sem cache seja sentido.

### Localizando o repositório

```bash
raw="$(sl_git_paths)"           # "gitdir<TAB>commondir<TAB>toplevel", ou nada
IFS=$'\t' read -r gitdir common top <<EOF
$raw
EOF
sl_git_is_worktree "$gitdir" "$common" && echo "worktree linkado"
```

Resolvido uma vez por diretório e cacheado, então vários widgets que conhecem git
na mesma linha custam uma consulta entre todos. Use isso em vez de chamar
`git rev-parse` por conta própria — ele já trata as duas coisas fáceis de errar:
o `--git-common-dir` voltando relativo, e o macOS resolvendo `/var` por um
symlink, o que de outro modo faz toda árvore de trabalho principal parecer um
worktree.

## A statusline nunca desaparece

Uma statusline vazia é indistinguível de um plugin morto, então ela nunca
renderiza vazia. Um `⚠` significa que uma entrada falhou — JSON de sessão
ilegível, ou configuração malformada. Um `—` significa que tudo renderizou vazio
sem erro nenhum. Ambos são mais úteis que uma linha em branco, e nenhum dos dois
pode ser confundido com saída normal.

O entrypoint também nunca roda sob `set -e`. Um retorno diferente de zero em
qualquer lugar não pode ser capaz de apagar a statusline do usuário.

## Desenvolvimento

```bash
brew install bats-core jq     # macOS
bats -r tests
```

O CI roda a suíte no macOS e no Ubuntu e, além disso, faz um teste de fumaça do
entrypoint sob o bash 3.2 de sistema do macOS, para pegar sintaxe de bash 4+
antes que ela chegue a alguém.

## Licença

MIT
