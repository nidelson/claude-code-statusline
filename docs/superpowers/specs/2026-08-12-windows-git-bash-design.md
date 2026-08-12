# Windows — suporte via Git Bash, WSL documentado

## Problema

O projeto nunca teve Windows como alvo. O CI roda macOS e Ubuntu, e o
repositório não menciona Windows, PowerShell ou WSL em lugar nenhum. Um usuário
de Windows que rode `/claude-code-statusline:setup` hoje recebe um
`settings.json` escrito e uma statusline que não aparece — e nada na saída
sugere que a plataforma é o motivo. A falha se parece com bug.

## Como o Claude Code executa a statusline no Windows

Da documentação oficial:

> On Windows, Claude Code runs status line commands through Git Bash when Git
> Bash is installed, or through PowerShell when Git Bash is absent.

E, ainda dela, o aviso que decide o formato do caminho:

> Git Bash treats unquoted backslashes as escape characters, so a Windows-style
> path such as `C:\Users\username\script.mjs` reaches the script runner with its
> separators removed and the command fails without a visible error.

São **três cenários**, não dois, e eles pedem tratamentos diferentes.

| cenário | estado hoje | o que falta |
| ------- | ----------- | ----------- |
| Claude Code dentro do WSL | **já funciona** | documentar |
| Windows nativo, Git Bash presente | quase funciona | formato do caminho no `setup` |
| Windows nativo, sem Git Bash | não funciona | falhar cedo e explicar |

### Dentro do WSL não há nada a portar

Ali tudo é Linux: bash 5, coreutils GNU, `$HOME`, convenção XDG. O código atual
roda sem alteração. O que existe é uma lacuna de documentação — ninguém sabe que
funciona.

### Com Git Bash, o código shell já serve

O Git Bash traz MSYS2, que fornece `awk`, `sed`, `cut`, `tr`, `tail`, `wc`,
`cksum` e `stat`. O `date` vem na variante **GNU**, e `lib/timefmt.sh` já resolve
BSD contra GNU no carregamento; `lib/cache.sh` faz o mesmo com `stat`. O
`timeout` pode faltar, e `widgets/command.sh` já cai para um watchdog em bash
puro quando nem `timeout` nem `gtimeout` existem.

Sobra `jq`, que **não** acompanha o Git Bash e precisa de instalação à parte —
`winget install jqlang.jq` ou `scoop install jq`.

Ou seja: `lib/` e `widgets/` não mudam. O que muda é o `setup`, o CI e a
documentação.

## O que muda

### 1. O caminho no `settings.json`

O `setup` hoje resolve o entrypoint e escreve `bash /caminho/absoluto/...`, no
formato que o macOS produz. No Git Bash o `CLAUDE_PLUGIN_ROOT` chega em formato
MSYS (`/c/Users/...`), e escrever isso no `settings.json` — lido pelo Node do
Claude Code — não resolve.

A conversão é `cygpath -m`, que o Git Bash fornece:

```
cygpath -m /c/Users/nome/.claude/plugins/...
→ C:/Users/nome/.claude/plugins/...
```

`-m` é a forma com barras normais, que é exatamente o que a documentação pede.
Nunca `-w`, que produz backslashes e cai na armadilha descrita acima.

### 2. Parar cedo quando não há Git Bash

Sem Git Bash, o Claude Code roteia pela PowerShell e nenhum script bash roda. O
`setup` precisa detectar isso **antes** de escrever qualquer coisa, e dizer o que
fazer: instalar Git for Windows, ou rodar o Claude Code dentro do WSL.

Escrever um `settings.json` que não pode funcionar é pior que não escrever nada,
porque o usuário perde a statusline padrão em troca de uma linha vazia — é
exatamente o que o relato da issue #66455 descreve como sintoma.

### 3. Shebang dos helpers

`bin/rate-forecast.sh` e `bin/flow-consumption.sh` usam `#!/bin/bash` fixo;
`bin/statusline.sh` usa `#!/usr/bin/env bash`. Os três passam a usar a segunda
forma, que é a que sobrevive a ambientes onde o bash não está em `/bin`.

Isto é higiene, não correção: no Git Bash `/bin/bash` existe. Mas os três
arquivos discordando entre si é dívida gratuita.

### 4. CI com `windows-latest`

É a única validação contínua possível. O runner `windows-latest` do GitHub
Actions traz Git Bash e `jq`; `bats` entra por `npm install -g bats`.

**O primeiro run é descoberta, não confirmação.** A expectativa honesta é que
parte dos 546 testes falhe por razões de ambiente — configuração de git, fim de
linha, permissões — e não por defeito do código. O trabalho é ler esse resultado
e decidir caso a caso entre corrigir o teste e declarar o limite.

Por isso o CI é o **primeiro** passo do plano, não o último: ele produz o
levantamento sobre o qual as outras decisões se apoiam.

## O que não muda

**Nada em `lib/` nem em `widgets/`.** Se o CI Windows mostrar o contrário, isso é
achado novo e vira decisão à parte, não escopo assumido de antemão.

**Nenhuma reescrita em PowerShell.** Um entrypoint `.ps1` significaria duas
implementações do mesmo comportamento para manter em sincronia, e brigaria com a
premissa de runtime do projeto, que é `jq` e `git`. Windows sem Git Bash fica
declarado como não suportado.

## Riscos

**Pode haver um bug do Claude Code no caminho.** A issue
[#66455](https://github.com/anthropics/claude-code/issues/66455) relata
`statusLine` nunca executada no Windows com Git Bash na versão 2.1.156 — zero
invocações em log, com o script funcionando quando chamado à mão. Foi fechada
como duplicata, sem resposta de mantenedor. Se o comportamento persistir, o
plugin pode ficar correto e ainda assim não aparecer, e nada neste trabalho
resolve isso. A validação manual é o que vai dizer.

**O CI verde não prova uso real.** Ele roda `bats` sobre o Git Bash do runner;
não exercita o Claude Code executando a statusline. Só a verificação na máquina
do usuário fecha essa lacuna.

## Verificação

Duas camadas, e as duas são necessárias.

**Automática:** `windows-latest` no CI, a cada PR.

**Manual, na máquina Windows do usuário:** rodar o `setup`, conferir o caminho
gravado no `settings.json`, executar o entrypoint à mão contra a fixture, e
reiniciar o Claude Code para ver se a linha aparece. Os comandos exatos ficam no
plano.

Enquanto a manual não acontecer, o README declara o suporte a Windows como
**verificado em CI, não confirmado em uso**.
