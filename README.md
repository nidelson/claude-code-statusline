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

v0.1. The widget contract is settled and covered by tests. Fourteen widgets ship
today — `model`, `repo`, `branch`, `git`, `git-status`, `worktree`, `context`,
`velocity`, `cache`, `cost`, `rate-forecast`, `sprint`, `flow` and `command` — each
exercising a different part of the contract: no state, cached state, pure
arithmetic, terminal escape sequences, and external processes with semantic
colours.

`command` is the escape hatch: it runs any program and renders its output, so a
data source the plugin has never heard of needs configuration rather than code.

`flow` is company-specific and ships with its own fetcher. This repository is
private and intended for CI&T colleagues; the widget is inert everywhere else,
so nothing breaks if you never configure it.

`git` is `branch` and `git-status` fused into one. Use `git` on its own, or the
other two — never all three, or the same `git status` runs twice per repaint.

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

### `repo`

Repository name, wrapped in an OSC 8 hyperlink to its remote so the name is
clickable.

| Option | Values | Default |
|---|---|---|
| `link` | `true`, `false` | `true` |
| `ttl` | seconds | `300` |

Inside a linked worktree it still shows the **main** repository's name — the
`worktree` widget is what tells you which worktree you are in. One formula
covers both cases: the name is `basename(dirname(git-common-dir))`, and the
common dir points at the main repository's `.git` either way.

Clone URLs are converted to browsable ones: scp-like (`git@host:path`), `ssh://`,
`git+ssh://`, `http(s)://`, and Azure DevOps SSH — whose web host differs and
whose path gains a `_git` segment, so it cannot be derived by swapping `:` for
`/`. Anything else renders as plain text; a wrong link is worse than no link.

Credentials in an `https://` remote are stripped. Without that, a remote with an
embedded token would become a hyperlink carrying the token, visible in the
terminal and copied along with the link.

Terminals without OSC 8 support ignore the sequence, so the fallback is the plain
name with no detection needed. Set `link: false` if yours does something worse
than ignore it.

### `branch`

The current branch on its own, for when you want the branch and the working-tree
state in different places or different colours. On a detached HEAD it shows the
short sha prefixed with `@`.

Where `git` combines both, this splits them — use one or the other, not both.

Its cache watches `.git/HEAD`, and that is the right sentinel here for the same
reason it was the wrong one for the dirty count: `HEAD` holds
`ref: refs/heads/<branch>` and is rewritten on checkout, but not on commit. Its
mtime changes exactly when the branch changes.

`mtime` has one-second resolution, so switching branches and repainting inside
the same second can still show the previous branch. The statusline repaints every
few seconds anyway.

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

### `git-status`

Working-tree state and distance from the upstream: `●3 ↑1 ↓2` — three files
dirty, one commit the upstream lacks, two commits you lack. Yellow, green, red.

| Option | Values | Default |
|---|---|---|
| `ttl` | seconds; `0` disables caching | `2` |

Clean and in sync renders nothing. A "you're fine" indicator would occupy space
permanently in order to say nothing.

It takes one `git` call, not two. The original used `status --porcelain` for the
dirty count and `rev-list --left-right --count HEAD...@{upstream}` for the rest,
but `status --porcelain --branch` puts both numbers in its header:

```
## main...origin/main [ahead 1, behind 2]
 M file
```

Since git's cost is almost entirely process spawn, reading the header halves the
price for the same information.

The counts are parsed from inside the brackets rather than from the header at
large, so a branch actually named `ahead` or `behind` cannot be mistaken for
tracking information. A header with no brackets — no upstream, or an upstream
that is `[gone]` — simply yields no counts.

Like `git`, it caches by time; see that widget for why no file can serve as a
sentinel for a dirty tree.

Colour is semantic — the `color` option does not apply.

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

Both rate limit windows, each with current usage, an overflow forecast, the
reset time and a countdown:

```
⏱ 5h:31%→93% ⟳02:10·1h48m · 7d:15% ⟳Fri·5d6h
```

The five-hour window answers "can I keep going right now"; the seven-day window
answers "when do I stop". Both are always shown, so the widget keeps a constant
width and you learn what normal looks like.

| Option | Values | Default |
|---|---|---|
| `window` | `5h`, `7d`; omit to show both | omitted |
| `warn` | usage percentage that turns yellow | `50` |
| `crit` | usage percentage that turns red | `80` |
| `separator` | text between the two windows | `·` |
| `reset` | `true`, `false` — show reset time and countdown | `true` |

`window` filters rather than selects: leave it out for both windows, set it to
show only one.

**Two colours, two questions.** Current usage is green below `warn`, yellow from
`warn`, red from `crit`. The projection takes its colour from the helper's level
instead. A green `31%` next to a yellow `→93%` is not a contradiction — it is low
usage at a high burn rate, which is precisely what you want to see.

The reset shows a clock below 24 hours and a weekday above it, chosen by time
remaining rather than by window, so a seven-day window resetting in four hours
still shows the hour. Reset time and countdown are dimmed: they are context for
the numbers, not competitors.

Anything unreadable erases only itself. A malformed reset drops the times and
keeps the percentage; a missing helper drops the projection and keeps everything
else. `resets_at` is accepted as epoch seconds, epoch milliseconds or an ISO 8601
string.

Both glyphs honour `icons: false`.

The forecast arithmetic lives in an external helper, so you can replace the
forecasting model without touching the plugin:

```
$SL_FORECAST_BIN <label> <used_pct> <resets_at_epoch> <window_seconds>
→ stdout: "<level> <projection>"    level ∈ none|ok|warn|crit
→ exit:   0, always
```

`SL_FORECAST_BIN` defaults to `$HOME/.claude/rate-forecast.sh`. Without it the
widget still shows the current percentage — a degraded reading beats no reading.

Colour is semantic — the `color` option does not apply.

### `sprint`

Sprint health for projects that keep sprint state in a file: `7/10 ▸2 ⊙1` —
stories done over total in the active epics, two queued for development, one
waiting on review. The ratio is green from 80% done, yellow from 40%, red below.

| Option | Values | Default |
|---|---|---|
| `path` | file path, relative to the working tree root | `_bmad-output/implementation-artifacts/sprint-status.yaml` |

This is the methodology widget. The others describe the machine; this one
describes the work. It renders nothing in a project that does not follow the
convention — no file, nothing to say — so there is no need to switch it off per
project.

The parsing lives in an external helper, because the format is something teams
adapt. Swapping methodology means swapping the helper, not patching the plugin:

```
$SL_SPRINT_BIN <path/to/file>
→ stdout: "<done>/<total> <ready> <review>", empty when no sprint is active
→ exit:   0, always
```

`SL_SPRINT_BIN` defaults to `$HOME/.claude/sprint-health-line.sh`. Without it the
widget stays silent — there is no partial reading to fall back to, unlike
`rate-forecast`.

Inside a linked worktree it reads that worktree's own file, not the main tree's:
each branch carries its own sprint state.

Unlike the git widgets, this one caches on `mtime` and that is exact — sprint
state does live in a file, so the parse runs when the file changes and only then.

The review count uses `⊙`, where the original statusline used `⚠`. Here `⚠` is
already the core's input-failure marker, and both can land on the same line. A
story in review is a queue state, not an error.

Colour is semantic — the `color` option does not apply.

### `flow`

Consumption on the CI&T Flow Platform, with a forecast: `flow:34%→58%`. Green
below 80% projected, yellow from 80%, red from 100%.

| Option | Values | Default |
|---|---|---|
| `metric` | `budget`, `requests` | `budget` |
| `ttl` | seconds between fetches | `300` |
| `refresh` | `true`, `false` — whether to fetch at all | `true` |
| `cache` | path to the fetched JSON | `$XDG_CACHE_HOME/flow-consumption.json` |
| `bin` | path to the fetcher | `bin/flow-consumption.sh` in this plugin |

This is the corporate-provider widget. Going through a company gateway means a
quota with its own limit and its own renewal, invisible to the Anthropic rate
limit, and it belongs on the same line as everything else.

**Fetching and showing are separate, and so are their clocks.**
`bin/flow-consumption.sh` talks to the network and writes JSON; the widget only
reads that JSON. A network call on the render path would make the whole
statusline wait on gateway latency, every repaint.

- The render is invalidated by the JSON's mtime, so a new figure appears the
  moment a fetch finishes rather than when some timer expires.
- The fetch is throttled by a marker file, so the API is not hammered.

A single TTL for both would force a choice between showing stale numbers and
fetching too often.

The marker is written *before* the fetch is launched, not after: two repaints
landing at nearly the same instant must not become two fetches.

**No token, no noise.** The fetcher needs `ANTHROPIC_AUTH_TOKEN` in the
environment. Without it, it records `{"ok": false}` and the widget renders
nothing. A machine with no Flow access sees no error — it sees a statusline
without that piece.

### `command`

Runs an external command and shows its output. This is the escape hatch: any
data source, no bash required.

Instances are named `command:<name>`, so you can have several:

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

| Option | Values | Default |
|---|---|---|
| `cmd` | shell command producing the text | required |
| `refresh` | shell command run detached when the ttl expires | none |
| `ttl` | seconds; `0` disables caching | `60` |
| `timeout` | seconds before the command is killed | `2` |
| `colors` | `true` keeps colour sequences from the output | `false` |
| `label` | text prefixed to the output | none |

**Reading and refreshing are separate on purpose.** `cmd` produces the text and
must be fast. `refresh` is optional, runs detached, and exists to warm whatever
`cmd` reads. A fetcher that talks to the network cannot run synchronously — the
whole statusline would wait on its latency. With both, the widget shows the
previous round's result and kicks off the next one in the background.

**Third-party output is sanitised.** Escape sequences are not decoration: OSC 52
writes to the user's clipboard, OSC 0 and 2 change the window title, and CSI
moves the cursor and can scramble the screen. By default nothing gets through.
`colors: true` opens one narrow exception — SGR, the CSI ending in `m`, which
only changes colour and style — and still strips the rest. Newlines are collapsed
too, since the statusline composes its own lines.

**`cmd` runs through `bash -c`**, so `~` and `$VAR` expand as you would expect
when writing a path into the config. It also means the config file is executable
content: treat it with the same care as your shell rc.

**Timeouts work without coreutils.** macOS ships no `timeout(1)`, and without
Homebrew coreutils there is no `gtimeout` either. When neither exists the widget
falls back to a pure-bash watchdog, so a hung command still cannot freeze the
statusline.

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

### Locating the repository

```bash
raw="$(sl_git_paths)"           # "gitdir<TAB>commondir<TAB>toplevel", or nothing
IFS=$'\t' read -r gitdir common top <<EOF
$raw
EOF
sl_git_is_worktree "$gitdir" "$common" && echo "linked worktree"
```

Resolved once per directory and cached, so several git-aware widgets on the same
line cost one lookup between them. Use it instead of calling `git rev-parse`
yourself — it already handles the two things that are easy to get wrong:
`--git-common-dir` coming back relative, and macOS resolving `/var` through a
symlink, which otherwise makes every main working tree look like a worktree.

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
