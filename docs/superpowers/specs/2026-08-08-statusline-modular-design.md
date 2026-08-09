# claude-code-statusline — design

**Data:** 2026-08-08
**Status:** aprovado, pronto para plano de implementação

## Propósito

Statusline para o Claude Code construída em torno de três eixos que nenhuma
alternativa existente atende:

1. **Previsão, não só relato.** Projetar o estouro da janela de rate limit antes
   que aconteça, com countdown de bloqueio — não apenas mostrar o percentual atual.
2. **Provedores corporativos.** Gateways como o Flow (CI&T), com budget em USD,
   quota de requests e bloqueio por política.
3. **Workflow e metodologia.** Saúde de sprint BMAD, fila de stories, estado de épico.

O projeto não compete com o `ccstatusline` nem com o `claude-hud-enhanced`. Esses
já cobrem bem o terreno genérico (dezenas de widgets, powerline, temas, TUI). O
objetivo aqui é atender um contexto de trabalho específico com qualidade, e
publicar porque outros no mesmo contexto podem se beneficiar.

A base é o `statusline.sh` pessoal (446 linhas de bash, em produção há meses),
mais os helpers `rate-forecast.sh` e `flow-consumption-line.sh`. O projeto
reorganiza esse código em módulos; não o reescreve.

## Escopo

**Dentro do v0.1:**

- Núcleo com registro de widgets e montagem de linhas
- Configuração em JSON com versionamento e degradação segura
- Três widgets que exercitam os casos-limite do contrato
- Suíte de testes e CI em macOS e Linux
- Manifesto de plugin do Claude Code e comando de instalação

**Fora, deliberadamente:**

- Powerline, temas, gradientes por widget
- TUI interativa de configuração
- Paridade de widgets com os concorrentes

Cada um desses é um subsistema inteiro, e nenhum serve aos três eixos acima.

## Decisões de arquitetura

### Bash 3.2 como alvo

A máquina de desenvolvimento tem apenas `bash 3.2.57` (padrão do macOS) e
`zsh 5.9`. Não há bash 4+ instalado, nem via Homebrew.

Bash 3.2 não tem arrays associativos (`declare -A`). O registro de widgets usa
indireção por nome de variável, que existe desde o bash 2.

Bash 3.2 é também o denominador comum mais amplo: padrão no macOS, presente em
toda distribuição Linux, disponível no Git Bash. Exigir bash 4+ obrigaria todo
usuário de macOS a instalar o Homebrew. Usar zsh excluiria a maioria das
instalações Linux, e a tradução de bash para zsh tem uma armadilha silenciosa —
zsh não faz word splitting de variável não-quotada, então código bash existente
muda de comportamento sem emitir erro.

As 1.048 linhas já escritas (`statusline.sh` 446, `flow-consumption-line.sh` 387,
`rate-forecast.sh` 132, `sprint-health-line.sh` 83) migram sem tradução, porque
já são bash 3.2.

### Registro explícito em vez de switch

O `claude-hud-enhanced` enumera cada elemento em um `switch` fechado e em cinco
listas paralelas de configuração. Medido: adicionar um elemento custa alterações
em cerca de quinze arquivos.

Aqui, cada widget é um arquivo que se registra ao ser carregado. O núcleo nunca
sabe quantos widgets existem. Adicionar um widget é criar um arquivo.

### Widgets nativos carregados, pesados em subprocesso

Widgets nativos são funções carregadas por `source` no mesmo processo — custo
zero de fork. Trabalho pesado (rede, cálculo com estado) fica em script externo,
invocado por um widget adaptador `command`, e já resolvido de forma assíncrona
com cache em disco.

Esse híbrido não é novidade: é exatamente o que o `statusline.sh` atual faz ao
chamar `rate-forecast.sh` e `sprint-health-line.sh` como subprocessos enquanto
mantém o restante inline. O projeto apenas formaliza a prática.

Um modelo puramente de subprocessos (cada widget um executável, como o
`custom-command` do `ccstatusline`) daria isolamento perfeito e liberdade de
linguagem, mas custaria um fork mais um interpretador por widget por repaint.
Com onze widgets, a cada dois segundos, em cada terminal aberto, isso é caro
demais para o benefício.

## Layout de arquivos

```
claude-code-statusline/
├── .claude-plugin/plugin.json    manifesto do plugin
├── bin/statusline.sh             entrypoint, único executável
├── lib/
│   ├── core.sh                   register_widget, loop de render, montagem
│   ├── stdin.sh                  JSON do Claude Code → variáveis SL_*
│   ├── config.sh                 leitura, validação e merge da configuração
│   ├── colors.sh                 paleta, rgb(), gradiente
│   └── cache.sh                  cache por mtime e por TTL
├── widgets/
│   ├── model.sh
│   ├── git.sh
│   └── rate-forecast.sh
├── commands/setup.md             slash command de instalação
├── tests/
└── README.md
```

## Fluxo de um repaint

1. O Claude Code executa `bin/statusline.sh` com o JSON de sessão no stdin.
2. O entrypoint carrega os cinco arquivos de `lib/`.
3. `stdin.sh` parseia o JSON **uma vez** e exporta `SL_MODEL`, `SL_CWD`,
   `SL_COST`, `SL_TOKENS` e demais campos.
4. `config.sh` resolve quais widgets aparecem em quais linhas.
5. O núcleo carrega **apenas os widgets listados na configuração**. Cada um
   chama `register_widget` ao ser carregado.
6. Para cada linha, para cada widget: chama o render e coleta a saída.
7. Junta com o separador e imprime tudo em um único `printf`.

Duas otimizações embutidas no fluxo:

**Parse único do stdin.** O `statusline.sh` atual invoca `jq` exatamente quinze
vezes, uma por campo, cada uma um fork. Um único `jq` emitindo todos os campos
elimina catorze forks — provavelmente a maior economia isolada do projeto.

**Carregamento preguiçoso.** Widget não configurado nunca é lido do disco.

## Contrato de widget

```bash
# widgets/model.sh
register_widget model \
  --render     widget_model_render \
  --color      cyan \
  --desc       "Nome do modelo ativo"

widget_model_render() {
  [ -n "$SL_MODEL" ] || return 0     # sem dado, não renderiza
  WIDGET_OUT="$SL_MODEL"
}
```

**Entrada.** Variáveis `SL_*` com os dados já parseados do stdin, e `WOPT_*` com
as opções daquele widget vindas da configuração. Um widget nunca lê stdin nem
invoca `jq`.

**Saída vazia significa ausência.** O widget não renderiza, e o núcleo não emite
separador órfão nem espaço duplo.

**Cor pertence ao núcleo.** O widget emite texto cru e o núcleo aplica a cor
configurada. A exceção se declara com `--self-color`, para widgets cuja cor é
semântica: o forecast pinta verde, amarelo ou vermelho conforme o valor
projetado, não conforme a preferência do usuário.

**Falha isolada.** Um widget que falha vira widget vazio. Os demais renderizam.

### Canal de retorno

O render escreve na variável `WIDGET_OUT` em vez do stdout. A forma idiomática
seria `saida=$(widget_fn)`, mas command substitution em bash sempre cria um
subprocesso — com onze widgets, são onze forks por repaint.

Esta decisão está **pendente de medição**. O plano de implementação inclui uma
etapa que constrói os dois caminhos no esqueleto, mede com os três widgets do
v0.1 na máquina alvo, e decide com número em vez de estimativa. Se a diferença
for irrelevante, o stdout vence por legibilidade.

### Cache como infraestrutura

`lib/cache.sh` expõe dois padrões, escritos uma vez e usados por qualquer widget:

```bash
cache_by_mtime <chave> <arquivo-sentinela> <comando>   # git: .git/HEAD
cache_by_ttl   <chave> <segundos> <comando>            # flow: 300s
```

Ambos já existem, duplicados, no código atual — o cache de git por mtime do
config, o de sprint por mtime do YAML, o de flow por TTL de cinco minutos.

### Widget adaptador `command`

```json
"widgets": {
  "flow": {
    "type": "command",
    "exec": "~/.claude/flow-consumption-line.sh --segment",
    "self-color": true
  }
}
```

Executa um script externo e captura a saída, com `timeout`. O
`flow-consumption-line.sh` e o `rate-forecast.sh` entram por aqui sem port. O
custo do fork é pago apenas por quem usa o recurso.

## Configuração

Duas configurações, com donos e ciclos de vida diferentes:

| Arquivo | Conteúdo | Quem escreve |
|---|---|---|
| `~/.claude/settings.json` | chave `statusLine` | o `/setup`, uma vez |
| `~/.config/claude-code-statusline/config.json` | layout de widgets | o usuário, sempre |

Separá-las é uma lição de campo: o `/setup` do `claude-hud-enhanced` mistura as
duas no mesmo comando, e ao reescrever o `settings.json` arrisca destruir um
symlink quando esse arquivo é gerenciado por dotfiles.

### Formato

Configuração do v0.1, com os três widgets que existem:

```json
{
  "version": 1,
  "lines": [
    ["model", "git"],
    ["rate-forecast"]
  ],
  "separator": "|",
  "widgets": {
    "rate-forecast": { "window": "5h" }
  }
}
```

O formato não muda com a migração dos oito widgets restantes; a configuração
apenas ganha mais nomes:

```json
"lines": [
  ["repo", "branch", "git-status", "velocity", "cache", "model", "cost"],
  ["context", "rate-forecast", "sprint"]
]
```

`lines` é um array de arrays, um por linha da statusline. `widgets` guarda opções
por widget e é opcional — nome ausente usa os defaults que o próprio widget
registrou.

O campo `version` existe desde o v1 para permitir migração. O `ccstatusline`
chegou ao `version: 3`; quem não versiona desde o início paga depois com
configuração quebrada na máquina do usuário.

### Resolução

Três camadas, nesta ordem: defaults embutidos, arquivo do usuário, variáveis de
ambiente `SL_*` (para depuração e CI).

### Edição

No v0.1, edição manual do JSON, com o schema documentado no README. Um
configurador pode vir depois; quando vier, os metadados que cada widget já
registra (descrição, cor padrão) o alimentam sem trabalho adicional.

`userConfig` do manifesto de plugin fica de fora. Serve bem para flags simples,
como o plugin `ecc` faz com `hook_profile`, mas não comporta a estrutura
aninhada de `lines`. Ter configuração em dois lugares seria pior que em um.

## Tratamento de erros

A statusline nunca pode desaparecer. É o único elemento na tela que o usuário
não pediu; se falhar, precisa falhar mostrando algo.

| Falha | Comportamento |
|---|---|
| `jq` ausente | Linha mínima com o que se extrai sem jq, mais `⚠ jq` |
| Configuração inválida | Defaults em memória, arquivo intocado, `⚠ config` |
| Widget desconhecido na configuração | Ignorado; os demais renderizam |
| Widget lança erro | Vira vazio; os demais renderizam |
| Comando externo trava | `timeout` no widget `command`; vira vazio |

Configuração inválida jamais é sobrescrita. O usuário precisa poder consertar o
próprio arquivo — essa é a prática correta do `ccstatusline`.

### Sem `set -e` nem `set -u`

Contra-intuitivo, mas em um statusline `set -e` é nocivo: qualquer comando que
retorne diferente de zero encerra o processo e deixa a linha em branco. Erros se
tratam explicitamente, no ponto onde ocorrem. `set -u` também fica de fora,
porque variável indefinida é o estado normal de boa parte dos campos do stdin.

## Testes

A arquitetura entrega testabilidade de graça: um widget é função pura — recebe
`SL_*`, escreve `WIDGET_OUT`. Sem I/O, sem stdin, sem estado.

```bash
# tests/widgets/model.bats
@test "model renderiza o nome do modelo" {
  SL_MODEL="Opus 5"; widget_model_render
  [ "$WIDGET_OUT" = "Opus 5" ]
}

@test "model desaparece quando não há modelo" {
  SL_MODEL=""; widget_model_render
  [ -z "$WIDGET_OUT" ]
}
```

Quatro camadas:

- **Unitários por widget.** Baratos, cobrem a maior parte da superfície.
- **Núcleo.** Registro, resolução de configuração, montagem, ausência de
  separador órfão.
- **Golden.** JSON de entrada produz statusline completa, comparada byte a byte.
  Pega regressão de espaçamento e de sequência ANSI, que é onde esse tipo de
  código costuma quebrar sem alarde.
- **Degradação.** Cada linha da tabela de erros vira um teste.

Runner: `bats-core`, dependência apenas de desenvolvimento. Os testes atuais
(`rate-forecast.test.sh`, `statusline-forecast.test.sh`) migram para lá.

CI no GitHub Actions em macOS e Ubuntu. O bash 3.2 do macOS e o 5.x do Linux
divergem em detalhes que só aparecem em execução real.

## Escopo do v0.1

Três widgets, escolhidos por exercitarem os casos-limite do contrato:

| Widget | O que prova |
|---|---|
| `model` | Caminho feliz: sem estado, sem I/O |
| `git` | `cache_by_mtime` com sentinela em `.git/HEAD` |
| `rate-forecast` | I/O externo, `--self-color`, widget adaptador `command` |

Se o contrato sustenta os três, sustenta os outros oito da migração.

Durante o v0.1 o `statusline.sh` atual permanece em uso. A troca acontece quando
houver paridade suficiente, não antes.

## Questões em aberto

- **Canal de retorno do widget** (`WIDGET_OUT` versus stdout). Resolver por
  medição, em etapa dedicada do plano de implementação.

## Referências

Análises que embasaram estas decisões, feitas sobre código instalado localmente:

- `claude-hud-enhanced` v0.6.0 — cerca de 11 mil linhas de TypeScript. Boa
  injeção de dependências e consciência de performance; extensibilidade travada
  por `switch` fechado e por um `config.ts` de 888 linhas.
- `ccstatusline` v2.2.27 — modelo de widgets instanciáveis (`id` mais `type` por
  item, linhas ilimitadas, `flex-separator` como dado, editor embutido em cada
  widget). É a referência de extensibilidade.
- Contrato de plugin do Claude Code — `.claude-plugin/plugin.json`, com `name`
  como único campo obrigatório. Schema em
  `https://json.schemastore.org/claude-code-plugin-manifest.json`.
