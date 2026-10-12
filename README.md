# kizuna.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: kizuna's directory of running AI agents as pane badges, a bar module and a picker to focus or message one.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/kizuna.lua`:

```lua
return { "masshirodev/kizuna.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/kizuna.ranma ~/.config/ranma/pack/plugins/start/kizuna.ranma
```

Then put the module on the bar, in `init.lua`:

```lua
ranma.bar { right = { "kizuna", "clock" } }
```

Needs: [kizuna](https://github.com/masshirodev/kizuna) (`kizuna peers`, `kizuna send`). Without it the plugin says so once and stays quiet.

## What it does

```text
Reads `kizuna peers --json` every few seconds (every agent kizuna launched:
its profile, repo, branch, busy or idle, who launched it, its ranma pane),
and:
  - badges each agent's pane with its profile: ● busy, ○ idle, ? waiting
    on you (a permission prompt), ◇ no state;
    "pro2 +2" for a lead of two workers, "pro⤷max" for a worker that
    a max agent launched;
  - the `kizuna` bar module counts the agents, the idle ones and the ones
    waiting on you, and a click opens the picker (put it on the bar with
    ranma.bar { right = { "kizuna", ... } });
  - the picker (`:kizuna` in the palette, or a click on the module) lists
    every agent; pick one to focus its pane, message it (kizuna send, the
    text typed in a prompt), message its lead instead when it is a worker,
    or copy its id. `:kizuna-send <id>` messages one directly.
To bind a key: ranma.bind("u", function() ranma.emit("kizuna_open") end,
{ desc = "kizuna", exit = true }).

With agents.ranma's badges on, busy and idle are left to it (its ● and ?)
and this badge keeps to who the agent is, plus ? for waiting, a state
agents.ranma does not know (kizuna.badge_state). The two badges sit side by
side, one per plugin. A pane number kizuna reports from another ranma
server is not badged here. Without a `kizuna` binary the plugin says so
once and stays quiet.

ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pane
handles", "Pickers and prompts", "Timers and processes", "The bar").
```

It complements [agents.ranma](https://github.com/masshirodev/agents.ranma), which watches what an agent prints in its pane. This one shows who the agent is in kizuna's directory: its profile, its lead and its workers. Use either or both. With both, agents.ranma's badge says busy or idle and this one's says who.

## Commands and binds

| | |
| --- | --- |
| `:kizuna` | The picker over every agent: focus its pane, message it, message its lead, copy its id. |
| `:kizuna-send <id>` | Message one agent; completes the ids. A worker whose lead runs is refused: message the lead, or send from `:kizuna` with `--worker`. |
| click on the module | The picker. |
| `user:kizuna_open` | The event that opens the picker, for a bind of your own. |

It binds no key. To give it one, in `init.lua`:

```lua
ranma.bind("u", function() ranma.emit("kizuna_open") end, { desc = "kizuna", exit = true })
```

A message is typed in ranma's prompt and handed to `kizuna send` on its standard input, so no text of it is read as a flag or by a shell.

## Options

In ranma's settings panel under `kizuna`, or with hako's `opts` (`{ "masshirodev/kizuna.ranma", opts = { ... } }`), or `ranma.set { kizuna = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `kizuna.poll` | `5` | Seconds between two looks at the agents. |
| `kizuna.badges` | `true` | Mark each agent's pane with its profile, its state and who launched it. |
| `kizuna.badge_state` | `"auto"` | Busy, idle or waiting in the badge's glyph: `auto` leaves busy and idle to agents.ranma when its badges are on; `always`; `never`. |
| `kizuna.command` | `"kizuna"` | The kizuna binary (`ai` is the same program under its older name). |

## License

MIT or Apache-2.0, as ranma.
