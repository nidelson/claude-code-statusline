# Statusline — previsão de estouro da janela de rate limit

**Data:** 2026-07-25
**Alvo:** `~/dotfiles/claude/.claude/statusline.sh` (+ script novo)

## Problema

A statusline mostra o estado **absoluto** da janela de 5h: `⏱ 5h:42% ⟳14:30·1h9m`.
Isso responde "quanto já gastei" e "quanto falta de relógio", mas não responde a
pergunta que de fato governa a decisão de continuar ou desacelerar:

> No ritmo em que estou queimando, chego em 14:30 sem estourar?

Hoje a resposta exige conta de cabeça a cada consulta. O ícone `⏱` é decorativo —
canal visual disponível e desperdiçado.

## Solução

Pintar o `⏱` conforme a **projeção** do uso no momento do corte da janela. Cinza
(sem cor, como hoje) quando folgado; amarelo quando apertado; vermelho quando a
projeção estoura. No estado de alerta, acrescentar o número projetado.

## Estimadores

Dois estimadores de ritmo, com falhas complementares:

| Estimador           | Como calcula                                                      | Enxerga                                   | Cego a                                      |
| ------------------- | ----------------------------------------------------------------- | ----------------------------------------- | ------------------------------------------- |
| **Média da janela** | `used% ÷ elapsed`, `elapsed = agora − (resets_at − duração)`      | queima acumulada desde o início da janela | mudança de ritmo — reage devagar            |
| **Ritmo recente**   | delta entre a amostra mais antiga da janela móvel e o valor atual | ritmo instantâneo                         | o que já foi queimado antes da janela móvel |

O ponto final do ritmo recente é sempre `(agora, used% do payload)` — o valor
vivo, não a última amostra gravada. O throttle de escrita não atrasa a leitura.

A média da janela é **stateless** — sai direto do payload. O ritmo recente exige
histórico, e é o único motivo do arquivo de estado.

Projeção de cada estimador:

```
projeção = used% + ritmo × (resets_at − agora)
```

## Regra de combinação — convergência

Cada projeção vira um nível: `ok=0` (< 85), `warn=1` (85–99), `crit=2` (≥ 100).

```
nível_final = ceil((nível_total + nível_recente) / 2)
```

Em aritmética inteira: `(a + b + 1) / 2`.

| total | recente | final    | leitura                            |
| ----- | ------- | -------- | ---------------------------------- |
| ok    | ok      | **ok**   | concordam: folgado                 |
| ok    | warn    | **warn** | rajada nova começando              |
| ok    | crit    | **warn** | rajada nova, média ainda não pegou |
| warn  | ok      | **warn** | desacelerou, mas o acumulado pesa  |
| warn  | warn    | **warn** | concordam: apertado                |
| warn  | crit    | **crit** | acelerando sobre base apertada     |
| crit  | ok      | **warn** | pausou de verdade — afrouxa        |
| crit  | warn    | **crit** | ainda queimando sobre base ruim    |
| crit  | crit    | **crit** | concordam: estoura                 |

Concordância vira sinal forte. Divergência vira incerteza, e incerteza é amarela.

`max()` puro foi descartado: a média da janela não esquece uma marretada até a
janela virar, então o vermelho gruda mesmo com o usuário parado — o ritmo recente
nunca teria voz para afrouxar. EWMA de estimador único foi descartada por não
permitir mostrar de onde veio o número.

### Estimador indisponível

Um estimador vale `none` quando não tem dados confiáveis:

- **média da janela**: `elapsed < 15min` (divisor pequeno explode a projeção), ou
  `elapsed` fora de `(0, duração]` (payload inconsistente)
- **ritmo recente**: menos de 2 amostras na janela atual, ou span entre a mais
  antiga e o instante atual `< 5min`

Ritmo **zero não é `none`** — é medição válida. Ocioso significa "no ritmo atual
você termina onde está", que projeta `used%` e quase sempre dá `ok`. É
justamente esse `ok` que faz a regra de convergência afrouxar um `crit` da média
para `warn` depois de uma pausa real. Tratar ocioso como `none` mataria o
comportamento aprovado no cenário marretada → pausa. Ritmo negativo (impossível
numa janela sã) é tratado como zero.

Combinação com `none`:

- ambos `none` → sem previsão, `⏱` cinza (comportamento idêntico ao de hoje)
- um `none` → usa o nível do outro, sem desconto

O "sem desconto" é deliberado: nos primeiros 15min de uma janela só o ritmo
recente existe, e uma marretada nesse período precisa alertar.

## Estado

Arquivo: `~/.claude/rate-samples-<label>.tsv`, global — o rate limit é da conta,
não da sessão. Uma linha por amostra:

```
<epoch>	<used_pct>	<resets_at_epoch>
```

Regras:

- **Throttle de escrita**: grava no máximo 1 amostra/min. Compara com a última
  linha antes de escrever. Sem isso o arquivo explode — a statusline re-renderiza
  a cada frame.
- **Rollover de janela**: `resets_at` diferente do da última amostra significa
  janela nova. Descarta tudo e recomeça.
- **Poda**: descarta amostras mais velhas que `max(3600, LOOKBACK × 2)` — folga
  para o usuário aumentar `CLAUDE_RATE_LOOKBACK` sem perder histórico útil.
  Reescreve via arquivo temporário + `mv` (rename atômico).
- **Concorrência**: sessões paralelas escrevem no mesmo arquivo. Append de linha
  curta com `>>` é atômico no macOS (< `PIPE_BUF`). A poda usa rename atômico; no
  pior caso uma corrida perde uma amostra, o que é inócuo.

## Componente novo

`~/.claude/rate-forecast.sh` — script separado, seguindo o precedente de
`sprint-health-line.sh`. O `statusline.sh` já tem 345 linhas e a lógica de
previsão se testa melhor isolada.

```
rate-forecast.sh <label> <used_pct> <resets_at_epoch> <duração_janela_s>

stdout: "<nível> <projeção>"      nível ∈ none|ok|warn|crit
exit:   0 sempre
```

`label` nomeia o arquivo de estado (`5h`, `7d`). `duração_janela_s` serve só ao
estimador de média (`18000` para 5h, `604800` para 7d); o ritmo recente não
precisa dela.

O script faz o append da amostra e devolve o veredito. Aritmética em uma chamada
de `awk` — sem `python3`, sem float em bash.

A duração de 5h é constante documentada, não derivável do payload. Se a premissa
estiver errada, só o estimador de média enviesa; o ritmo recente é imune, e o
guard de `elapsed` fora do intervalo derruba a média para `none`.

## Render

O `42%` mantém a cor absoluta que já tem (verde/amarelo/vermelho por valor). A
previsão pinta apenas o `⏱` e o número projetado. Duas informações, dois canais.

O número exibido é a **pior** projeção entre os estimadores disponíveis — se um
estiver `none`, mostra o do outro. Teto no número, confiança na cor.

```
ok    ⏱ 5h:42% ⟳14:30·1h9m           ⏱ sem cor, idêntico a hoje
warn  ⏱ 5h:42%→92% ⟳14:30·1h9m       ⏱ e →92% amarelos
crit  ⏱ 5h:42%→180% ⟳14:30·1h9m      ⏱ e →180% vermelhos
```

Projeções acima de 999% são exibidas como `→999%` para não estourar a largura.

## Escopo

Só a janela de 5h recebe alerta nesta entrega. O amostrador é genérico por
`label`, então ligar o 7d depois é uma chamada a mais — mas não se liga agora
(YAGNI: a 7d fica em 8% com dias de folga).

## Configuração

Variáveis de ambiente, com default:

| Variável                   | Default | Efeito                            |
| -------------------------- | ------- | --------------------------------- |
| `CLAUDE_RATE_WARN`         | `85`    | limiar ok → warn                  |
| `CLAUDE_RATE_CRIT`         | `100`   | limiar warn → crit                |
| `CLAUDE_RATE_LOOKBACK`     | `1800`  | janela móvel do ritmo recente (s) |
| `CLAUDE_RATE_MIN_SPAN`     | `300`   | span mínimo entre amostras (s)    |
| `CLAUDE_RATE_SAMPLE_EVERY` | `60`    | throttle de escrita (s)           |

## Degradação

Nenhuma falha pode quebrar a linha. Todos estes casos caem em "sem previsão,
`⏱` cinza":

- payload sem `rate_limits` ou sem `resets_at`
- arquivo de estado ausente, ilegível ou corrompido
- amostras insuficientes
- `awk` ausente ou com erro

## Testes

`~/.claude/rate-forecast.test.sh` — fixtures de TSV sintético, assertivas sobre a
saída. Casos:

1. arquivo ausente → `none`
2. 1 amostra só → `none` para o recente; média decide
3. span < 5min → `none` para o recente
4. ritmo zero (ocioso) → recente é `ok`, e afrouxa `crit` da média para `warn`
5. `elapsed` < 15min → `none` para a média
6. rollover de `resets_at` → descarta amostras, recomeça
7. throttle: duas chamadas em < 60s gravam uma linha só
8. poda: amostra de 2h atrás some do arquivo
9. os 9 pares da tabela de convergência
10. projeção > 999 → clamp em 999
11. duas chamadas em sequência rápida (throttle desligado) deixam duas linhas
    íntegras, sem intercalação

## Custo por render

1 leitura do TSV (últimas linhas), 1 escrita condicional por minuto, 1 `awk`.
Comparável às chamadas de `jq` que a statusline já faz.
