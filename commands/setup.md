---
description: Instala a claude-code-statusline no settings.json
---

Configure este plugin como a statusline do usuário. Siga os passos na ordem e
relate no final o que foi feito.

## Passo 0: Identificar a plataforma

Rode `uname -s` e guarde o resultado.

| saída | plataforma | como proceder |
|---|---|---|
| `Darwin` | macOS | siga normalmente |
| `Linux` | Linux, ou Claude Code dentro do WSL | siga normalmente; no WSL tudo é Linux |
| `MINGW64_NT-*`, `MSYS_NT-*` | Git Bash no Windows | siga, com as ressalvas dos passos 1 e 2 |
| o comando não existe | PowerShell sem Git Bash | **pare aqui**, ver abaixo |

Para distinguir Linux de WSL, quando importar: `grep -qi microsoft /proc/version`.

**Quando `uname` não existe**, o Claude Code está rodando via PowerShell sem Git
Bash instalado. Nenhum script deste plugin roda nesse ambiente.

**Não escreva nada no `settings.json`.** Configurar uma statusline que não
executa troca a linha padrão do Claude Code por uma linha vazia, e o usuário não
tem como descobrir o motivo — ele perde o que tinha e não ganha nada.

Explique as duas saídas e pare:

1. Instalar o Git for Windows (<https://git-scm.com/download/win>), que traz o
   Git Bash. O Claude Code passa a rotear a statusline por ele automaticamente.
2. Rodar o Claude Code dentro do WSL, onde o plugin funciona sem adaptação.

## Passo 1: Instalar o launcher

O `settings.json` **não** aponta para o entrypoint do plugin. Aponta para um
launcher instalado fora dele, que resolve o entrypoint a cada repaint.

A razão é o caminho de instalação, que carrega a versão:

```
~/.claude/plugins/cache/<marketplace>/claude-code-statusline/0.2.0/bin/statusline.sh
```

Como o `settings.json` não expande variáveis de plugin, o caminho ali é literal.
Gravar esse caminho direto significa que a próxima versão do plugin deixa o
`settings.json` apontando para um diretório que não existe mais — e a statusline
some até alguém rodar este setup outra vez. O launcher elimina isso: o
`settings.json` é escrito uma vez e nunca mais precisa mudar.

Copie `${CLAUDE_PLUGIN_ROOT}/bin/launcher.sh` para
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh` e torne-o executável. Esse é
o caminho que a documentação do Claude Code usa para statusline própria, então é
o que o usuário espera encontrar ao abrir o `settings.json`.

O destino fica fora do diretório do plugin de propósito: um launcher instalado
dentro do cache seria apagado pela próxima atualização, que é exatamente o
problema que ele resolve.

**Se o arquivo já existir, compare antes de escrever:**

- Conteúdo idêntico ao `launcher.sh` do plugin → não faça nada. Rodar o setup
  várias vezes não pode acumular backups idênticos.
- Conteúdo diferente → **é a statusline própria do usuário**, e ele
  provavelmente esqueceu que ela existia. Copie para
  `statusline.sh.bak.YYYYMMDD-HHMMSS`, diga o nome do backup na mensagem final,
  e só então sobrescreva. Perder isso em silêncio é o pior desfecho possível:
  ele veria a statusline mudar sem relacionar a causa.

**No Git Bash, converta o caminho com `cygpath -m`:**

```bash
cygpath -m "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh"
# → C:/Users/nome/.claude/statusline.sh
```

O caminho que o Git Bash usa internamente (`/c/Users/...`) não serve aqui: quem
lê o `settings.json` é o Claude Code, não o shell.

Use `-m`, que produz barras normais. **Nunca `-w`**, que produz contrabarras: o
Git Bash as trata como escape, o caminho chega ao runner sem separadores e o
comando falha sem erro nenhum — o pior modo de falha possível, porque não deixa
rastro para o usuário seguir.

## Passo 2: Verificar as dependências

Rode `command -v jq` e `command -v git`.

- Sem `jq`, a statusline ainda renderiza mas mostra quase nada, porque
  praticamente todo campo vem do parse do JSON da sessão. Avise e sugira
  `brew install jq` no macOS ou o gerenciador de pacotes equivalente. No
  Windows o `jq` **não** acompanha o Git Bash: `winget install jqlang.jq` ou
  `scoop install jq`.
- Sem `git`, apenas os widgets que dependem de git ficam em silêncio.

Nenhuma das duas é fatal. Não aborte a instalação por dependência faltando.

## Passo 3: Fazer backup do settings.json

O arquivo fica em `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`. Copie para
`settings.json.bak.YYYYMMDD-HHMMSS` antes de tocar nele.

**Esse arquivo é frequentemente um symlink gerenciado por um repositório de
dotfiles.** Ao escrever, use `cat arquivo-novo > settings.json` — nunca `mv`. Um
`mv` substitui o symlink por um arquivo comum e desconecta silenciosamente o
repositório de dotfiles do usuário, que só vai perceber na próxima máquina.

## Passo 4: Escrever a chave statusLine

Faça merge no JSON existente, preservando todas as outras chaves:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /caminho/absoluto/para/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 5
  }
}
```

O `padding` é escrito explicitamente como `0`. O padrão do Claude Code é `2`,
que recua a statusline em duas colunas — recuo que faz sentido para uma linha
curta de texto, e atrapalha aqui: os widgets já compõem o próprio espaçamento
com separadores, e a primeira linha do default passa de oitenta colunas em
repositório com nome longo. Duas colunas a menos de largura útil é o suficiente
para empurrar o último widget para fora em terminal estreito.

Se já existir uma chave `statusLine`, mostre o valor atual ao usuário e pergunte
antes de substituir — pode ser uma statusline que ele queira manter.

## Passo 5: Criar a configuração padrão

Se `${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-statusline/config.json` não
existir, crie:

```json
{
  "version": 1,
  "lines": [
    ["repo", "branch", "git-status", "worktree", "velocity", "cache", "cost", "flow", "model"],
    ["context", "rate-forecast", "sprint"],
    ["tip"]
  ],
  "separator": "|",
  "icons": true,
  "widgets": {
    "cost": { "warn": 5, "crit": 15 },
    "flow": { "ttl": 300 }
  }
}
```

Se já existir, não toque nele.

Este default mostra doze dos quatorze widgets. Ele parece cheio escrito assim,
mas quase metade não aparece na maioria das sessões: `worktree` some na árvore
principal, `git-status` some com a árvore limpa, `velocity` some quando nada
mudou, `cache` some sem tokens de cache, `sprint` some em projeto que não mantém
o estado da sprint em arquivo, e `flow` some sem o token do gateway. O que sobra
numa máquina recém-instalada são cinco ou seis segmentos.

Widget que não tem nada a dizer desaparece, então incluir muitos no default custa
pouco e resolve a descoberta: ninguém precisa ler o README inteiro para saber que
existe um widget de custo.

O `command` fica de fora porque exige um `cmd` para fazer qualquer coisa, e o
`git` também, porque é o `branch` e o `git-status` fundidos — os três na mesma
linha rodariam `git status` duas vezes por repaint.

## Passo 6: Verificar

Rode o **launcher** contra a fixture do repositório, não o entrypoint. É o
launcher que o `settings.json` invoca, então testá-lo exercita a cadeia inteira:
a resolução da versão instalada e o entrypoint que ela contém.

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh" < ${CLAUDE_PLUGIN_ROOT}/tests/fixtures/session.json
```

A saída tem três `⚠` possíveis, com causas distintas. A cor separa os dois
primeiros, e a posição confirma:

- **Sem cor, linha única começando com `⚠`** — o launcher não achou o que
  executar. Nenhum widget acompanha, e o texto diz qual dos dois casos é:
  plugin não instalado, ou flag de desenvolvimento apontando para um checkout
  inexistente. Esta é uma falha real de instalação; relate.
- **Amarelo, como primeiro caractere de uma linha com widgets** — a entrada
  falhou: JSON da sessão ilegível ou config malformada, normalmente `jq`
  faltando. Relate isso em vez de tratar a execução como sucesso.
- **Vermelho, dentro dos widgets** — a última busca do `flow` falhou. A fixture
  não traz token nem proxy, então este aparece em toda instalação nova rodando
  contra ela. É esperado; não relate como erro.

A distinção importa porque `flow` está no default do passo 5: tratar qualquer
`⚠` como falha faria toda instalação limpa parecer quebrada.

Por fim, peça ao usuário para reiniciar o Claude Code.
