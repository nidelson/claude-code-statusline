---
description: Instala a claude-code-statusline no settings.json
---

Configure este plugin como a statusline do usuário. Siga os passos na ordem e
relate no final o que foi feito.

## Passo 1: Localizar o entrypoint

O entrypoint é `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`. Confirme que existe e
resolva para caminho absoluto — o `settings.json` não expande variáveis de
plugin.

## Passo 2: Verificar as dependências

Rode `command -v jq` e `command -v git`.

- Sem `jq`, a statusline ainda renderiza mas mostra quase nada, porque
  praticamente todo campo vem do parse do JSON da sessão. Avise e sugira
  `brew install jq` no macOS ou o gerenciador de pacotes equivalente.
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
    "command": "bash /caminho/absoluto/para/bin/statusline.sh",
    "refreshInterval": 5
  }
}
```

Se já existir uma chave `statusLine`, mostre o valor atual ao usuário e pergunte
antes de substituir — pode ser uma statusline que ele queira manter.

## Passo 5: Criar a configuração padrão

Se `${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-statusline/config.json` não
existir, crie:

```json
{
  "version": 1,
  "lines": [
    ["repo", "branch", "git-status", "worktree", "velocity", "cache", "model", "cost"],
    ["context", "rate-forecast", "flow", "sprint"]
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
mudou, `cache` some sem tokens de cache, e `sprint` e `flow` somem sem o
respectivo helper ou token. O que sobra numa máquina recém-instalada são cinco ou
seis segmentos.

Widget que não tem nada a dizer desaparece, então incluir muitos no default custa
pouco e resolve a descoberta: ninguém precisa ler o README inteiro para saber que
existe um widget de custo.

O `command` fica de fora porque exige um `cmd` para fazer qualquer coisa, e o
`git` também, porque é o `branch` e o `git-status` fundidos — os três na mesma
linha rodariam `git status` duas vezes por repaint.

## Passo 6: Verificar

Rode o entrypoint contra a fixture do repositório e confirme que imprime algo:

```bash
bash /caminho/absoluto/para/bin/statusline.sh < /caminho/absoluto/para/tests/fixtures/session.json
```

Um `⚠` na saída significa que a entrada falhou — JSON da sessão ilegível ou
config malformada, normalmente `jq` faltando. Relate isso em vez de tratar a
execução como sucesso.

Por fim, peça ao usuário para reiniciar o Claude Code.
