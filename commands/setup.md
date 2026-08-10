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
  "lines": [["model", "git"], ["rate-forecast"]],
  "separator": "|"
}
```

Se já existir, não toque nele.

## Passo 6: Verificar

Rode o entrypoint contra a fixture do repositório e confirme que imprime algo:

```bash
bash /caminho/absoluto/para/bin/statusline.sh < /caminho/absoluto/para/tests/fixtures/session.json
```

Um `⚠` na saída significa que a entrada falhou — JSON da sessão ilegível ou
config malformada, normalmente `jq` faltando. Relate isso em vez de tratar a
execução como sucesso.

Por fim, peça ao usuário para reiniciar o Claude Code.
