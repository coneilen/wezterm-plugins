# wezterm-agent-deck

A [WezTerm](https://wezfurlong.org/wezterm/) plugin that watches your panes for
running AI coding agents — **Anthropic Claude Code** and **GitHub Copilot CLI**
— and surfaces their state at a glance: coloured dots on tab titles, an
aggregate right-status segment, and OS notifications when an agent is blocked
waiting for your input.

## Features

- **Per-pane agent detection** by executable, argv, and pane title patterns.
- **Status inference** from on-screen text — `working`, `waiting`, `idle`, or
  `inactive`.
- **Tab title prefix** with a coloured dot per active pane (optional label).
- **Right-status summary** with per-agent counts (e.g. `claude:●1 ghcp:◔2`).
- **Notifications** when an agent transitions into `waiting` (and optionally
  when it finishes), either via WezTerm's native toast or `terminal-notifier`
  on macOS, with per-pane de-duplication.
- **Cooldown damping** so brief output gaps don't flap `working → idle`.
- Pluggable icon styles: `unicode`, `nerd`, or `emoji`.

## Status colours

| Colour | Glyph | Meaning |
| --- | --- | --- |
| Green | `●` | working — agent is processing |
| Yellow | `◔` | **waiting — agent needs your input** |
| Blue | `○` | idle — prompt ready |
| Grey | `◌` | inactive — no agent in this pane |

## Install

Clone the repo somewhere and point Lua's `package.path` at it in your
`wezterm.lua`:

```lua
local wezterm = require('wezterm')
local config  = wezterm.config_builder()

-- Adjust to wherever you cloned this repo
package.path = package.path
  .. ';/path/to/wezterm-agent-deck/?.lua'
  .. ';/path/to/wezterm-agent-deck/?/init.lua'

local agent_deck = require('plugin.init')
agent_deck.apply_to_config(config)

return config
```

That single `apply_to_config` call registers the `format-tab-title` and
`update-status` hooks the plugin needs.

## Configuration

`apply_to_config(config, opts)` deep-merges `opts` over the defaults. Every
value is optional; pass only what you want to change.

```lua
agent_deck.apply_to_config(config, {
  update_interval = 750,      -- (informational; WezTerm drives update-status)
  cooldown_ms     = 1500,     -- damp working -> idle flapping
  max_lines       = 120,      -- pane text rows scanned for status patterns
  enabled_agents  = nil,      -- e.g. { 'claude' } to disable copilot_cli

  tab_title = {
    enabled    = true,
    position   = 'left',      -- 'left' | 'right'
    show_label = false,       -- show 'claude'/'ghcp' next to the dot
    separator  = ' ',
  },

  right_status = {
    enabled     = true,
    show_counts = true,
    show_labels = true,       -- "claude:●1 ghcp:◔2"
  },

  colors = {
    working  = '#A6E22E',
    waiting  = '#E6DB74',
    idle     = '#66D9EF',
    inactive = '#888888',
  },

  icons = {
    style = 'unicode',        -- 'unicode' | 'nerd' | 'emoji'
  },

  notifications = {
    enabled     = true,
    on_waiting  = true,
    on_finished = false,
    cooldown_ms = 5000,       -- per-pane dedupe window
    backend     = 'native',   -- 'native' | 'terminal-notifier'
    terminal_notifier = {
      path     = nil,         -- defaults to 'terminal-notifier' on PATH
      sound    = 'default',
      title    = 'Agent Deck',
      group    = 'wezterm-agent-deck',
      activate = true,
    },
  },
})
```

### Customising detection

Each agent in `config.agents` has `executable_patterns`, `argv_patterns`,
`title_patterns`, and `status_patterns.{working,waiting,idle}` — all Lua
patterns matched case-insensitively. To add an agent or extend an existing
one, merge entries in:

```lua
agent_deck.apply_to_config(config, {
  agents = {
    copilot_cli = {
      status_patterns = {
        waiting = { 'my custom prompt' },
      },
    },
  },
})
```

## Public API

```lua
agent_deck.apply_to_config(config, opts)  -- install hooks, returns merged cfg
agent_deck.get_agent_state(pane_id)       -- { agent, status, last_change_ts }
agent_deck.get_all_states()               -- pane_id -> state table
agent_deck.get_status_color(status)
agent_deck.get_status_icon(status)
agent_deck.get_config()                   -- current merged config
```

## Project layout

```
plugin/
  init.lua           main entry point and update loop
  config.lua         defaults, merge, colour/icon helpers
  detector.lua       agent detection from pane process/title
  status.lua         working/waiting/idle inference
  renderer.lua       tab title and right-status formatting
  notifications.lua  WezTerm toast / terminal-notifier backend
tests/
  run.lua            harness against stub_wezterm.lua
```

## Tests

```sh
cd wezterm-agent-deck
lua tests/run.lua
```

The tests stub `wezterm` so they run anywhere Lua 5.1+ is available.

## Acknowledgements

Inspired by
[Eric162/wezterm-agent-deck](https://github.com/Eric162/wezterm-agent-deck)
and [asheshgoplani/agent-deck](https://github.com/asheshgoplani/agent-deck),
rewritten from scratch with first-class GitHub Copilot CLI support.

## License

MIT — see [`LICENSE`](./LICENSE).
