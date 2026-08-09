# Decisão: canal de retorno dos widgets

**Data:** 2026-08-08
**Status:** decidido
**Decisão:** widgets escrevem no **stdout**. O núcleo captura com command
substitution.

## Contexto

O contrato de widget precisa de um canal para devolver o texto renderizado. Dois
candidatos:

- **`WIDGET_OUT`** — o widget atribui a uma variável global; o núcleo lê. Sem
  subprocesso.
- **stdout** — o widget imprime; o núcleo captura com `out="$(widget_fn)"`.
  Idiomático, mas command substitution em bash sempre cria um subprocesso.

A statusline redesenha a cada poucos segundos, em cada terminal aberto, então o
custo por repaint importa. A dúvida era se importava o suficiente para justificar
uma variável global como canal de retorno — construção que confunde quem chega
depois e permite vazamento de estado entre widgets.

## Critério, fixado antes da medição

- Diferença **abaixo de 5 ms por repaint** → **stdout**. Legibilidade e
  isolamento valem mais que economia imperceptível.
- Diferença **de 5 ms ou mais por repaint** → **`WIDGET_OUT`**.

O limiar foi escrito antes de rodar o benchmark, de propósito: com o número na
mão é fácil racionalizar qualquer um dos lados.

## Medição

`benchmarks/return-channel.sh`, três execuções, 11 widgets sintéticos, 200
repaints, bash 3.2.57 em Apple Silicon.

| Execução | `WIDGET_OUT` | stdout | Diferença por repaint |
|---|---|---|---|
| 1 | 0,023 s | 0,733 s | 3,55 ms |
| 2 | 0,017 s | 0,716 s | 3,50 ms |
| 3 | 0,016 s | 0,724 s | 3,54 ms |

Melhor de três: 0,016 s contra 0,716 s. **3,5 ms por repaint.**

O benchmark usa o builtin `time` com `TIMEFORMAT='%3R'`. A primeira versão usava
`date +%s`, com resolução de um segundo — a estratégia sem subshell termina em
16 ms e a medição teria saído "0s contra 1s". O BSD `date` do macOS não tem
`%N`. Os laços usam `for ((...))` em vez de `seq`, que é binário externo e
forkaria dentro da região medida.

## Decisão

**stdout**, porque 3,5 ms está abaixo do limiar.

Em termos relativos a diferença é grande — stdout é cerca de 45 vezes mais lento
neste microbenchmark. Em termos absolutos é pequena: um repaint completo custa
algo em torno de 40 ms, então isto acrescenta perto de 9%. O critério mede o que
o usuário sente, não a razão entre os números.

Contrato resultante:

```bash
widget_model_render() {
  [ -n "$SL_MODEL" ] || return 0
  printf '%s' "$SL_MODEL"
}
```

E no núcleo:

```bash
out="$("$fn" 2>/dev/null)" || out=""
```

## Consequências

- Widgets ficam isolados de verdade. É impossível um widget vazar estado para o
  seguinte por engano, que era o risco real da variável global.
- Testes de widget ficam mais naturais: `run widget_x_render` e `$output`, em vez
  de zerar `WIDGET_OUT` antes de cada chamada.
- O custo é conhecido e medido, não estimado.

## Quando revisitar

Se o total de widgets configurados passar de vinte, ou se um perfil de repaint
real mostrar a montagem acima de 100 ms, medir de novo. O caminho de volta para
`WIDGET_OUT` é mecânico: trocar `printf` por atribuição nos widgets e a captura
no núcleo. O restante do contrato não muda.
