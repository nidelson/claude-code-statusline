# Windows via Git Bash — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o plugin instalar e rodar no Windows com Git Bash, declarar o WSL como já suportado, e falhar cedo com explicação quando não há Git Bash.

**Architecture:** Nada em `lib/` nem em `widgets/` muda — o código shell já serve, porque o Git Bash traz MSYS2 e a variante GNU do `date` e do `stat`, que as duas bibliotecas já detectam. O trabalho é no `setup` (formato do caminho e verificação de plataforma), no CI (um terceiro runner) e na documentação.

**Tech Stack:** bash 3.2+, `jq`, `bats-core`, GitHub Actions.

**Spec:** [2026-08-12-windows-git-bash-design.md](../specs/2026-08-12-windows-git-bash-design.md)

## Global Constraints

- **Shell alvo: bash 3.2.57.** O piso continua sendo o macOS; Git Bash traz bash 4+ ou 5, que é mais permissivo, então não relaxa nada.
- **Nunca usar `set -e` nem `set -u`.**
- **Dependências de runtime: apenas `jq` e `git`.** Windows não abre exceção.
- **A statusline nunca pode desaparecer.**
- **Idioma:** comentários, documentação e commits em **português**. Identificadores em inglês.
- **Nomes de teste `@test` em inglês ASCII.**
- **Contraprova ANTES da asserção sob teste**, e **cor colada ao texto**. Ver `tests/helper.bash`.
- **`cygpath -m`, nunca `-w`.** A forma `-w` produz backslashes, que o Git Bash consome como escape e some com os separadores sem erro visível.

---

### Task 1: `windows-latest` no CI

Primeiro, e de propósito: este passo é **levantamento**, não correção. Ele produz
a lista real do que quebra, sobre a qual as tarefas seguintes se apoiam.

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Acrescentar o runner e as dependências**

Na matriz:

```yaml
        os: [macos-latest, ubuntu-latest, windows-latest]
```

E um passo de instalação, junto dos outros dois:

```yaml
      # O runner windows-latest já traz Git Bash e jq; falta o bats, que não tem
      # pacote nativo e vem por npm. Todos os passos deste job rodam sob
      # `shell: bash`, que no runner Windows É o Git Bash — o mesmo interpretador
      # que o Claude Code usa para a statusline quando ele está instalado.
      - name: Install bats (Windows)
        if: runner.os == 'Windows'
        run: npm install -g bats
```

E, no job, forçar o shell para todos os passos:

```yaml
    defaults:
      run:
        shell: bash
```

- [ ] **Step 2: Abrir uma PR só com isso e ler o resultado**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: acrescenta windows-latest à matriz

Levantamento antes de suporte: o job Windows roda sob Git Bash, que é o
mesmo interpretador que o Claude Code usa para a statusline naquela
plataforma. O primeiro resultado é descoberta, não confirmação."
git push -u origin windows-git-bash
gh pr create --draft --title "ci: windows-latest (levantamento)" --body "PR de rascunho para ler o que quebra no Windows antes de escrever suporte."
```

- [ ] **Step 3: Registrar o que falhou**

Run: `gh run view --log-failed`

Anotar, para cada teste que falhar, se a causa é (a) ambiente do runner —
configuração de git, fim de linha, permissão —, (b) diferença real de
plataforma, ou (c) defeito do teste que macOS e Linux escondiam.

**Não corrigir nada ainda.** A lista alimenta a Task 2.

---

### Task 2: corrigir o que o levantamento mostrou

**Files:** depende do resultado da Task 1. Provavelmente `tests/` e talvez
`lib/`.

**Interfaces:** nenhuma nova.

- [ ] **Step 1: Classificar cada falha**

Para cada uma, decidir entre:

- **corrigir o teste** — quando ele assume algo de POSIX que não é essencial ao
  comportamento, por exemplo permissão de arquivo ou caminho absoluto começando
  em `/`;
- **corrigir o código** — quando o comportamento está de fato errado no Git Bash;
- **declarar o limite** — quando a funcionalidade não pode existir ali, com um
  `skip` no bats que traga o motivo no texto, e uma linha no README.

- [ ] **Step 2: Aplicar, uma causa por commit**

Cada commit resolve uma causa e diz qual. Um commit que arrume três coisas
diferentes não deixa reverter uma delas.

- [ ] **Step 3: CI verde nos três runners**

Run: `gh pr checks`
Expected: `macos-latest`, `ubuntu-latest` e `windows-latest` passando.

---

### Task 3: shebang uniforme nos helpers

**Files:**
- Modify: `bin/rate-forecast.sh:1`, `bin/flow-consumption.sh:1`

- [ ] **Step 1: Trocar os dois**

De `#!/bin/bash` para:

```bash
#!/usr/bin/env bash
```

`bin/statusline.sh` já usa essa forma. Os três discordando entre si é dívida
gratuita — e a forma com `env` é a que sobrevive a ambientes onde o bash não
mora em `/bin`.

- [ ] **Step 2: Confirmar que os helpers ainda rodam**

```bash
bash bin/rate-forecast.sh 5h 42 1800000000 18000
./bin/rate-forecast.sh 5h 42 1800000000 18000
```
Expected: as duas formas imprimem a mesma linha.

- [ ] **Step 3: Rodar a suíte e commitar**

Run: `bats -r tests`
Expected: 0 falhas.

```bash
git add bin/rate-forecast.sh bin/flow-consumption.sh
git commit -m "chore: env bash nos dois helpers de bin/

statusline.sh já usava #!/usr/bin/env bash e os outros dois não. A forma
com env é a que sobrevive a ambientes onde o bash não mora em /bin."
```

---

### Task 4: o `setup` reconhece a plataforma

**Files:**
- Modify: `commands/setup.md`

- [ ] **Step 1: Inserir um passo de plataforma antes de tudo**

Novo **Passo 0**, antes de localizar o entrypoint:

````markdown
## Passo 0: Identificar a plataforma

Rode `uname -s` e guarde o resultado.

| saída | plataforma | como proceder |
|---|---|---|
| `Darwin` | macOS | siga normalmente |
| `Linux` sem WSL | Linux | siga normalmente |
| `Linux` com WSL | Claude Code dentro do WSL | siga normalmente; tudo ali é Linux |
| `MINGW64_NT-*`, `MSYS_NT-*` | Git Bash no Windows | siga, com as ressalvas dos passos 1 e 2 |
| o comando não existe | PowerShell sem Git Bash | **pare aqui**, ver abaixo |

Para separar Linux de WSL: `grep -qi microsoft /proc/version`.

**Quando `uname` não existe**, o Claude Code está rodando via PowerShell sem Git
Bash instalado. Nenhum script deste plugin pode rodar nesse ambiente. **Não
escreva nada no `settings.json`** — configurar uma statusline que não executa
troca a linha padrão do Claude Code por uma linha vazia, e o usuário não tem como
saber por quê.

Explique as duas saídas e pare:

1. Instalar o Git for Windows (<https://git-scm.com/download/win>), que traz o
   Git Bash. O Claude Code passa a rotear a statusline por ele automaticamente.
2. Rodar o Claude Code dentro do WSL, onde o plugin funciona sem adaptação.
````

- [ ] **Step 2: Ajustar o Passo 1 para o formato de caminho**

Substituir o Passo 1 por:

````markdown
## Passo 1: Localizar o entrypoint

O entrypoint é `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`. Confirme que existe e
resolva para caminho absoluto — o `settings.json` não expande variáveis de
plugin.

**No Git Bash, converta o caminho com `cygpath -m`:**

```bash
cygpath -m "$CLAUDE_PLUGIN_ROOT/bin/statusline.sh"
# → C:/Users/nome/.claude/plugins/.../bin/statusline.sh
```

O caminho que o Git Bash usa internamente (`/c/Users/...`) não serve: quem lê o
`settings.json` é o Claude Code, não o shell.

Use `-m`, que produz barras normais. **Nunca `-w`**, que produz backslashes: o
Git Bash os trata como escape, o caminho chega ao runner sem separadores, e o
comando falha sem nenhum erro visível — o modo de falha mais caro que existe
aqui, porque não deixa rastro.
````

- [ ] **Step 3: Ajustar o Passo 2, das dependências**

Acrescentar ao bloco do `jq`:

````markdown
O `jq` **não** acompanha o Git Bash e precisa de instalação à parte no Windows:
`winget install jqlang.jq` ou `scoop install jq`. O `git` já está lá, por
definição — é o Git for Windows que traz o Git Bash.
````

- [ ] **Step 4: Ajustar o Passo 6, da verificação**

Acrescentar:

````markdown
No Windows, rode a verificação com o mesmo caminho que foi gravado no
`settings.json`, não com o caminho MSYS — é o que prova que a conversão ficou
certa:

```bash
bash "C:/caminho/como/foi/gravado/bin/statusline.sh" < "C:/.../tests/fixtures/session.json"
```
````

---

### Task 5: README com a matriz de suporte

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Acrescentar a seção, logo após a instalação**

````markdown
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
do primeiro caso — o Git for Windows já o traz.

Sem Git Bash, o `setup` para e explica em vez de escrever uma configuração que
não pode funcionar.

Duas notas para quem usa Windows:

- O `jq` não vem com o Git Bash. Instale com `winget install jqlang.jq` ou
  `scoop install jq`.
- O caminho no `settings.json` precisa de barras normais (`C:/Users/...`). O
  `setup` já escreve assim; se editar à mão, não use backslashes — o Git Bash os
  consome como escape e a statusline falha em silêncio.
````

- [ ] **Step 2: Marcar o estado da verificação**

Enquanto a verificação manual não acontecer, acrescentar abaixo da tabela:

```markdown
> O suporte a Windows é verificado no CI, sob o mesmo Git Bash que o Claude Code
> usa. A execução ponta a ponta pelo próprio Claude Code ainda não foi
> confirmada por um usuário — se você rodar, conte como foi.
```

Remover esta nota depois da Task 6.

---

### Task 6: verificação manual na máquina Windows

Esta tarefa é do usuário, não do agente. O CI prova que os testes passam sob Git
Bash; só isto prova que o Claude Code executa a statusline.

- [ ] **Step 1: Instalar a partir da branch**

```
/plugin marketplace add nidelson/claude-code-statusline
/plugin install claude-code-statusline
/claude-code-statusline:setup
```

Observar se o `setup` identificou a plataforma como Git Bash e se **não** houve
aviso de plataforma não suportada.

- [ ] **Step 2: Conferir o caminho gravado**

```bash
cat ~/.claude/settings.json | jq -r '.statusLine.command'
```

Expected: algo como `bash C:/Users/<nome>/.claude/plugins/.../bin/statusline.sh`
— **com barras normais**. Um backslash aqui é falha da Task 4.

- [ ] **Step 3: Executar à mão**

```bash
bash "$(jq -r '.statusLine.command' ~/.claude/settings.json | sed 's/^bash //')" \
  < ~/.claude/plugins/*/claude-code-statusline/tests/fixtures/session.json
```

Expected: uma linha com modelo, diretório e barra de contexto. Um `⚠` significa
entrada ilegível — quase sempre `jq` ausente.

- [ ] **Step 4: Reiniciar o Claude Code**

Expected: a statusline aparece.

**Se não aparecer**, e o Passo 3 tiver funcionado, o problema não é do plugin: é
o comportamento descrito na issue
[#66455](https://github.com/anthropics/claude-code/issues/66455), em que o
Claude Code não invoca a statusline no Windows com Git Bash. Colete
`claude --debug` e registre no README como limitação conhecida, com a versão do
Claude Code.

- [ ] **Step 5: Fechar o ciclo**

Confirmado o funcionamento, remover a nota de "não confirmada por um usuário" do
README e mesclar a PR.
