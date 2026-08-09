---
description: Install claude-code-statusline into your Claude Code settings
---

Set up this plugin as the user's statusline. Work through the steps in order and
report what you did at the end.

## Step 1: Locate the entrypoint

The entrypoint is `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`. Confirm it exists.
Resolve it to an absolute path — `settings.json` cannot expand plugin variables.

## Step 2: Check dependencies

Run `command -v jq` and `command -v git`.

- Without `jq`, the statusline still renders but shows almost nothing, because
  every field comes from parsing the session JSON. Say so and suggest
  `brew install jq` on macOS or the equivalent package manager elsewhere.
- Without `git`, only the git-aware widgets go quiet.

Neither is fatal. Do not abort setup over a missing dependency.

## Step 3: Back up settings.json

The file lives at `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`. Copy it to
`settings.json.bak.YYYYMMDD-HHMMSS` before touching it.

**This file is often a symlink managed by a dotfiles repository.** When you write
it, use `cat new-file > settings.json` — never `mv`. A `mv` replaces the symlink
with a regular file and silently disconnects the user's dotfiles repo, which they
will not notice until their next machine.

## Step 4: Write the statusLine key

Merge into the existing JSON, preserving every other key:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /absolute/path/to/bin/statusline.sh",
    "refreshInterval": 5
  }
}
```

If a `statusLine` key already exists, show the user its current value and ask
before replacing it — they may have a statusline they want to keep.

## Step 5: Create the default configuration

If `${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-statusline/config.json` does
not exist, create it:

```json
{
  "version": 1,
  "lines": [["model", "git"], ["rate-forecast"]],
  "separator": "|"
}
```

If it already exists, leave it alone.

## Step 6: Verify

Run the entrypoint against the bundled fixture and confirm it prints something:

```bash
bash /absolute/path/to/bin/statusline.sh < /absolute/path/to/tests/fixtures/session.json
```

A `⚠` in the output means the session JSON could not be parsed — usually a
missing `jq`. Report it rather than treating the run as a success.

Finally, ask the user to restart Claude Code.
