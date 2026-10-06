# Agent Progress (bar meter)

The Omarchy bar has a work-progress meter. The user drives several agents at
once and often cannot see your terminal; the meter is how they see that long
work is moving.

## When to report

Report any task you expect to take **more than about a minute** and that has
steps you can count: files copied, parts rebuilt, images rendered, tests run,
pages processed, items in a plan. Skip quick tasks and single commands.

If there is no honest count, omit `--total`; the meter then shows "working"
or a running count instead of a percentage. Never invent progress.

## How

Pick the mode by how fast the work moves.

**A step every second or slower** (parts, files, plan items):

```bash
agent-progress start <id> --title "Rebuilding CAD parts" --total 12 --unit parts
agent-progress update <id> --current 3 --detail "bracket.step"
agent-progress finish <id>                    # success
agent-progress fail <id> --detail "why"       # failure
```

**Many fast steps**: one `pipe` process instead of an `update` per step
(each `update` costs ~70 ms). Print one line per finished step into it:

```bash
for f in "${files[@]}"; do convert_one "$f"; echo; done \
  | agent-progress pipe <id> --title "Converting files" --total ${#files[@]} >/dev/null
```

**Downloads, uploads, copies, archives**: put `pipe --bytes` in the data path.
It passes data through unchanged and the bar shows MB/GB, speed in the
tooltip, and a stream of particles that follows the throughput:

```bash
curl -sL "$url" | agent-progress pipe <id> --bytes --title "Downloading model" --total "$size" > model.bin
tar c build/ | agent-progress pipe <id> --bytes --title "Uploading build" | ssh host 'tar x'
```

`pipe` starts the job itself and ends it: `finish` when input ends, `fail` if
it ends short of `--total`, the output closes, or it's interrupted. It can't
see whether the command feeding it succeeded; use `set -o pipefail` and run
`agent-progress fail <id>` if the pipeline fails.

- `<id>`: lowercase, digits, `.`, `_`, `-`; prefix it with your agent name so
  sessions never collide, e.g. `claude-cad-rebuild`, `codex-theme-render`.
- `--title`: short. The bar slot is narrow and shows the count, not the
  title; the title appears in the tooltip and the Super+P picker.
- Titles and details describe the work, never the user's data: "Verifying
  photo backup", not a filename, person or place from their files.
- Report every step; don't batch artificially. The bar draws one wave per
  step for slow jobs and switches to a particle stream for fast ones.
- Waiting on the user? `agent-progress update <id> --state blocked --detail
  "needs approval"`, then `--state running` when you resume.

## Rules

- **Always end the job**: `finish` or `fail`, including when you are
  interrupted, stop early, or hit an error. A job left `running` stays on the
  bar forever.
- **Run it in the background.** Work long enough to report here runs as a
  background command, not in your foreground turn: the bar is how the user
  watches it, and the conversation stays free meanwhile. Put `start`,
  `update` and `finish` (or `pipe`) inside the backgrounded script, `fail` on
  error, and act on the job when it completes.
- Only touch jobs you started. Other agents share the same directory.
- Records live in `~/.local/state/agent-progress/<id>.json`; finished ones are
  hidden but kept. `agent-progress list` shows what is active.
- The widget is `~/.config/omarchy/plugins/benredrew.progress/`. Do not edit
  it as part of reporting progress.
