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

```bash
agent-progress start <id> --title "Rebuilding CAD parts" --total 12 --unit parts
agent-progress update <id> --current 3 --detail "bracket.step"
agent-progress finish <id>                    # success
agent-progress fail <id> --detail "why"       # failure
```

- `<id>`: lowercase, digits, `.`, `_`, `-`; prefix it with your agent name so
  sessions never collide, e.g. `claude-cad-rebuild`, `codex-theme-render`.
- `--title`: short. The bar slot is narrow and shows the count, not the
  title; the title appears in the tooltip and the Super+P picker.
- Update after each step. High rates are fine (10/s is tested); each increment
  draws one wave on the meter, so don't batch updates artificially.
- Waiting on the user? `agent-progress update <id> --state blocked --detail
  "needs approval"`, then `--state running` when you resume.

## Rules

- **Always end the job**: `finish` or `fail`, including when you are
  interrupted, stop early, or hit an error. A job left `running` stays on the
  bar forever.
- Only touch jobs you started. Other agents share the same directory.
- Records live in `~/.local/state/agent-progress/<id>.json`; finished ones are
  hidden but kept. `agent-progress list` shows what is active.
- The widget is `~/.config/omarchy/plugins/benredrew.progress/`. Do not edit
  it as part of reporting progress.
