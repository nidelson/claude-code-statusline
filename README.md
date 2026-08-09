# claude-code-statusline

A statusline for [Claude Code](https://claude.com/claude-code), built out of small
independent widgets.

```
✻ Opus 5 | feat/v0.1 ●3
5h:42%→70%
```

## Why another one

There are good statuslines for Claude Code already. This one exists because of
three things the others do not do, all of which come from using Claude Code as a
daily driver rather than as a demo:

**Forecasting, not just reporting.** `5h:42%` tells you where you are. It does
not tell you whether you will hit the wall before the window resets. The
`rate-forecast` widget extrapolates from your burn rate and colours the result,
so `42%→116%` reads as "stop or slow down" three hours before you find out the
hard way.

**Corporate providers.** Plenty of us do not talk to the Anthropic API directly.
We go through a company gateway with its own quota, its own dashboard and its own
way of running out. That consumption belongs on the same line as everything else.

**Workflow, not just machine state.** Model, branch and token count are facts
about the process. Whether the current sprint is healthy is a fact about the
work. The second one is harder to surface and easier to forget.

## Status

v0.1. The widget contract is settled and covered by tests; the widget set is
deliberately small. Eight widgets ship today — `model`, `git`, `worktree`,
`context`, `velocity`, `cache`, `cost` and `rate-forecast`. They were chosen
because each one exercises a different part of the contract: no state, cached
state, pure arithmetic, and an external process with semantic colours.

## Requirements

| | |
|---|---|
| `bash` | 3.2 or newer |
| `jq` | required in practice — nearly every field comes from parsing the session JSON |
| `git` | optional; only the git-aware widgets need it |

Bash 3.2 is not a typo. macOS still ships `/bin/bash` 3.2.57 and always will:
bash 4.0 moved to GPLv3, which Apple does not distribute. Targeting 3.2 means the
plugin works on a stock Mac with no `brew install` step. Everything here runs
unchanged on bash 5.

## Install

```
/plugin marketplace add nidelson/claude-code-statusline
/plugin install claude-code-statusline
/claude-code-statusline:setup
```

The setup command backs up `settings.json`, writes the `statusLine` key, and
creates a default config if you do not have one. Restart Claude Code afterwards.

To wire it by hand, point `statusLine.command` at `bin/statusline.sh`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/claude-code-statusline/bin/statusline.sh",
    "refreshInterval": 5
  }
}
```

## Configuration

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

| Key | Type | Default | Meaning |
|---|---|---|---|
| `version` | number | — | Config format version. Reserved; not yet enforced. |
| `lines` | array of arrays | `[["model","git"],["rate-forecast"]]` | One inner array per rendered line, listing widgets left to right. |
| `separator` | string | `\|` | Placed between widgets on a line, padded with spaces. |
| `icons` | boolean | `true` | Turns widget glyphs on or off. The glyphs are plain Unicode (`✻`, `◆`), not Nerd Font — no extra font needed. |
| `widgets` | object | `{}` | Per-widget options, keyed by widget name. |

Every widget accepts a `color` option: `red`, `green`, `yellow`, `blue`,
`magenta`, `cyan`, `dim`. It is ignored by widgets whose colour is semantic —
see `--self-color` below.

A widget name the plugin does not recognise is skipped silently, so a config
written for a newer version still works on an older one.

**A malformed config is never rewritten.** The plugin falls back to defaults in
memory, shows a `⚠`, and leaves your file exactly as you left it so you can fix
it.

## Widgets

### `model`

The active model. Anthropic models render in the Claude brand coral (`#D97757`);
anything else renders in magenta, so a switch to a different provider is visible
at a glance rather than something you have to read.

Colour is semantic — the `color` option does not apply.

### `git`

Current branch, plus a dirty count when the working tree is not clean
(`feat/v0.1 ●3`). Renders nothing on a detached HEAD.

| Option | Values | Default |
|---|---|---|
| `ttl` | seconds; `0` disables caching | `2` |

The dirty count cannot be invalidated by watching a file. Editing a file touches
nothing inside `.git` — not `HEAD`, not the index — because the information lives
in the comparison between the tree and the index, not on disk. So the cache is
time-based, and `ttl` is the explicit ceiling on how stale the number can be.

Raise it on a large repository, where `git status` costs real time.

### `worktree`

The directory name of a linked worktree, and nothing at all in the main working
tree — the point is to signal "you are not in the usual checkout". Stays quiet
when the directory name already matches the branch name, since `git` is showing
that anyway.

### `context`

Context window usage as a gradient bar, followed by the percentage and the token
counts: `████▌░░░░░░ 23% (45k/200k)`. The percentage is green, yellow from 70%,
red from 90%.

| Option | Values | Default |
|---|---|---|
| `width` | cells in the bar | `20` |
| `tokens` | `true`, `false` — show the `(used/total)` suffix | `true` |

The bar renders in eighths using Unicode block characters, so a 20-cell bar has
160 steps rather than 20. At full-block resolution each step is 5% and the bar
sits still through most of a session before jumping; at eighths it moves
continuously.

Usage is taken from `total_input_tokens`, the session accumulator, which is the
number Claude Code's own interface reports. Last-exchange usage understates the
real context by roughly 9%.

A window can be overrun by a single large exchange. The percentage then reads
past 100 — that is real information — but the bar stops at its configured width,
because a bar that outgrows its own track pushes the rest of the line sideways.

Colour is semantic — the `color` option does not apply.

### `velocity`

Lines added and removed this session: `+10 -2`, green and red.

Each half only appears when it has a value, and the widget disappears entirely
when nothing changed. The original always printed `+0 -0`, which in a session
spent reading code is permanent noise — space spent to say nothing happened.

Counts are exact, never abbreviated. `+1.2k` would hide the difference between
1200 and 1249, and unlike tokens, that difference matters here.

Colour is semantic — the `color` option does not apply.

### `cache`

Prompt cache hit rate: `cache:70%`. Green from 70%, yellow from 30%, red below.

| Option | Values | Default |
|---|---|---|
| `label` | prefix text; `""` removes it | `cache:` |

The rate is cache reads over the sum of cache reads, cache writes and fresh
input tokens. High means a warm cache and a cheap exchange; low means a cold
cache, the start of a session, or something having invalidated the prefix.

**This is a speedometer, not an odometer.** The counters come from
`current_usage`, which describes only the most recent exchange, so the number
moves every turn by design.

It renders nothing when all three counters are zero. A hit rate over zero tokens
is not 0%, it is undefined — printing `0%` would claim the cache missed when
nothing was asked of it.

The prefix is text rather than a glyph because `context`, `rate-forecast` and
this widget can share a line and all end in `%`. Text needs no font installed and
has a predictable width. Shorten it with `label` when space is tight.

Colour is semantic — the `color` option does not apply.

### `cost`

Accumulated session cost: `$3.50`.

| Option | Values | Default |
|---|---|---|
| `warn` | USD amount | unset |
| `crit` | USD amount | unset |
| `color` | a palette name | `yellow`, or `green` when a threshold is set |

With no thresholds the widget just reports, in yellow. Set `warn` or `crit` and
it becomes a traffic light: green below `warn`, yellow from `warn`, red from
`crit`. The floor turns green on purpose — leaving it yellow would make crossing
`warn` repaint yellow over yellow, and the warning would be invisible.

Amounts are formatted under `LC_ALL=C`. In a locale where the decimal separator
is a comma, bash's `printf` rejects `0.0234` outright: it prints `$0,00` and
writes to stderr. The value arrives from JSON, where the separator is always a
period, so the formatting has to agree with that regardless of the machine.

### `rate-forecast`

Rate limit window usage with an overflow forecast: `5h:42%→70%`, coloured green,
yellow or red by risk.

| Option | Values | Default |
|---|---|---|
| `window` | `5h`, `7d` | `5h` |

The arithmetic lives in an external helper, so you can replace the forecasting
model without touching the plugin:

```
$SL_FORECAST_BIN <label> <used_pct> <resets_at_epoch> <window_seconds>
→ stdout: "<level> <projection>"    level ∈ none|ok|warn|crit
→ exit:   0, always
```

`SL_FORECAST_BIN` defaults to `$HOME/.claude/rate-forecast.sh`. Without it the
widget still shows the current percentage — a degraded reading beats no reading.

Colour is semantic — the `color` option does not apply.

## Writing a widget

A widget is one file in `widgets/`. It registers itself when sourced and writes
to stdout. That is the whole contract. Here is `widgets/model.sh` in full, with
its comments stripped:

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

Then add it to `lines` in your config. Only widgets your config names are
sourced, so an unused widget costs nothing.

### `register_widget`

| Flag | Required | Meaning |
|---|---|---|
| `--render FN` | yes | Function that writes the widget's text to stdout. |
| `--color NAME` | no | Default colour, overridable by the user's config. |
| `--self-color` | no | The widget colours itself and the core leaves it alone. Use when colour carries information rather than preference. |
| `--desc TEXT` | no | One-line description. |

### Reading user options

```bash
sl_config_widget_opt <widget> <key> [default]
```

Returns the value from `widgets.<widget>.<key>` in the user's config, as a
string — numbers and booleans included, so `"tokens": false` comes back as the
string `false`.

Pass a default when you have one. It is applied inside `jq`, against the key
being absent — not in bash afterwards. That distinction matters: bash cannot tell
an absent key from a key set to `""`, so a bash-side fallback would quietly
override a deliberate empty value and make options like `"label": ""`
impossible.

### Rules

**Print nothing when you have nothing.** Empty output makes the widget vanish
and takes its separator with it. Do not print `n/a` or `-`.

**Never exit non-zero to signal a problem** — but if you do, the core catches it
and treats the widget as empty. The rest of the line survives either way.

**Never assume a dependency exists.** Degrade to less information instead of
disappearing.

### Input variables

Parsed from the session JSON in a single `jq` pass before any widget runs.

| Variable | Contents |
|---|---|
| `SL_MODEL` | Model display name, or `Unknown` |
| `SL_MODEL_ID` | Model identifier |
| `SL_CWD` | Session working directory |
| `SL_COST` | Session cost in USD |
| `SL_LINES_ADDED`, `SL_LINES_REMOVED` | Lines changed this session |
| `SL_CTX_SIZE`, `SL_CTX_USED` | Context window size and tokens used |
| `SL_INPUT_TOKENS` | Fresh input tokens, **last exchange only** |
| `SL_CACHE_READ`, `SL_CACHE_CREATE` | Prompt cache read and creation tokens, **last exchange only** |
| `SL_5H_PCT`, `SL_5H_RESET` | Five-hour window: percentage used, reset epoch |
| `SL_7D_PCT`, `SL_7D_RESET` | Seven-day window: percentage used, reset epoch |
| `SL_JQ_OK` | `1` when the session JSON parsed, `0` otherwise |

### Caching

Two helpers, for the two ways a value goes stale:

```bash
cache_by_mtime <key> <sentinel-file> <command...>   # invalidated by a file changing
cache_by_ttl   <key> <seconds>      <command...>    # invalidated by time
```

Use them for anything that spawns a process. The statusline repaints often
enough that an uncached subprocess is felt.

## The statusline never disappears

An empty statusline is indistinguishable from a dead plugin, so it never renders
empty. A `⚠` means an input failed — unparseable session JSON, or a malformed
config. A `—` means everything rendered empty without any error. Both are more
useful than a blank line, and neither can be confused with normal output.

The entrypoint also never runs under `set -e`. A non-zero return anywhere must
not be able to erase the user's statusline.

## Development

```bash
brew install bats-core jq     # macOS
bats -r tests
```

CI runs the suite on macOS and Ubuntu, and additionally smoke-tests the
entrypoint under macOS's system bash 3.2 to catch bash 4+ syntax before it
reaches anyone.

## License

MIT
