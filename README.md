# claude-statusline

(Inspired by AKCodez)

A custom status line for Claude Code. It renders the
current repo, your 5-hour rate-limit usage, and context-window usage as color-graded
bars, plus the active model, reasoning effort, and a token count.

![The status line: repo name, a 5h usage bar at 42%, a context bar at 73%, the model, and a token count](assets/statusline.svg)

The bars use a green → yellow → red gradient. Each block is colored by its *position*
in the bar, and only the leading blocks are lit — so a fuller bar isn't just longer,
it's visibly redder:

![The same bar at 10%, 40%, 70% and 100% fill, shifting from green to red](assets/gradient.svg)

## Requirements

- `bash`
- [`jq`](https://jqlang.github.io/jq/) — parses the JSON that Claude Code pipes in
- `awk` — gradient math and percentage rounding
- A terminal with 24-bit (truecolor) support, for the RGB gradient

## Install

Copy the script somewhere stable and make it executable:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Then point Claude Code at it in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash $HOME/.claude/statusline-command.sh"
  }
}
```

`settings.statusline.json` in this repo is that snippet, ready to merge into your own
settings file. Claude Code runs the command through a shell, so `$HOME` (or `~`) is
expanded for you — no need to hardcode an absolute path.

## How it works

Claude Code invokes the command on each render and pipes a JSON blob to stdin. The
script reads these fields:

| Field | Used for |
| --- | --- |
| `.workspace.repo.name` | Repo name (falls back to `basename` of `.workspace.current_dir`, then `$PWD`) |
| `.model.display_name` | Model label, e.g. `Opus 5` |
| `.effort.level` | Reasoning effort, shown in parens — omitted when absent |
| `.rate_limits.five_hour.used_percentage` | The `5h` bar |
| `.context_window.used_percentage` | The `ctx` bar |
| `.context_window.total_input_tokens` + `.total_output_tokens` | The `tokens` count |

Each segment is skipped entirely if its field is missing, so the line degrades
gracefully rather than printing empty bars — with one exception: `tokens` defaults to
`0` instead of dropping out, so it shows `tokens 0` before the session's first API
response. Segments are joined with a dim gray ` | `
separator, and the whole line is emitted through a single `printf %b` — the script
builds up literal `\033[...m` text and lets that final call interpret the escapes.

### What the token count measures

`tokens` is the sum of `total_input_tokens` and `total_output_tokens`, which the
[status line docs](https://code.claude.com/docs/en/statusline) define as *tokens
currently in the context window, from the most recent API response* — input including
cache reads and writes. It is **not** a cumulative total for the session: it drops
after `/compact`, and it tracks the same underlying number as the `ctx` bar rather than
accumulating alongside it. Claude Code's status line payload exposes no
session-cumulative token field; `cost.total_cost_usd` is the only genuinely cumulative
usage figure available.

Counts are abbreviated by `format_tokens`: `842`, `12.3k`, `1.2M`.

## Testing it

Pipe a sample payload straight into the script:

```bash
echo '{
  "workspace": {"repo": {"name": "claude-statusline"}},
  "model": {"display_name": "Opus 5"},
  "effort": {"level": "high"},
  "rate_limits": {"five_hour": {"used_percentage": 42}},
  "context_window": {"used_percentage": 73}
}' | bash statusline-command.sh
```

## Customizing

- **Bar length** — `BAR_WIDTH` near the top of the script (default `10`).
- **Bar characters** — `█` for lit blocks, `░` for unlit, in `gradient_bar`.
- **Colors** — the gradient is computed in the `awk` block inside `gradient_bar`:
  `t <= 0.5` ramps red up against full green, past that green ramps down. Unlit blocks
  are hardcoded to `rgb(60,60,60)`; separators and labels use 256-color `DIM_GRAY`.
  The previews in `assets/` are hand-maintained — regenerate them if you change the
  gradient or `BAR_WIDTH`.
- **Segment order** — reorder the `parts+=(...)` appends; they're joined in array order.
- **Token thresholds** — the `k`/`M` cutoffs and decimal places live in `format_tokens`.
