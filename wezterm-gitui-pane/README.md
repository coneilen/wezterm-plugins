# wezterm-gitui-pane

A [WezTerm](https://wezfurlong.org/wezterm/) plugin that opens
[gitui](https://github.com/gitui-org/gitui) as a **split pane** anchored to
the repo of your current pane — locally, over plain `ssh`, or inside a WezTerm
SSH multiplexing domain. Plus two pure-Lua overlays for fast branch checkout
and commit-diff viewing.

## Features

- **Toggle a gitui side pane** with one keystroke, scoped per tab (or per
  window).
- **Walks up to the repo root** from the active pane's cwd, so it works
  whether you're in `src/foo/` or at the top level.
- **Remote-aware spawning**:
  - **Local panes** — runs `gitui -d <repo>` in a new split.
  - **`ssh`/`mosh` process panes** — re-uses the host parsed from argv and
    runs gitui through `ssh -t`, optionally honouring the OSC 7 cwd.
  - **WezTerm SSH multiplexing domains** — splits inside the same domain and
    runs `gitui` there.
- **Branch picker** overlay — fuzzy `InputSelector` over local/remote
  branches → `git checkout`.
- **Log picker** overlay — last N commits → `git show <hash>` piped to your
  pager in a new split.
- **No shell-history pollution** — gitui is launched as a child process, not
  typed into your shell.

## Keybindings (defaults)

| Binding | Action |
| --- | --- |
| `⌘G` | Toggle gitui split pane |
| `⌘⇧G` | Focus gitui pane (open if missing) |
| `⌘⇧B` | Branch picker → checkout |
| `⌘⇧L` | Log picker → show commit diff in a new pane |

Set any individual binding to `false` to disable it.

## Install

Clone the repo somewhere and point Lua's `package.path` at it in your
`wezterm.lua`:

```lua
local wezterm = require('wezterm')
local config  = wezterm.config_builder()

-- Adjust to wherever you cloned this repo
package.path = package.path
  .. ';/path/to/wezterm-gitui-pane/?.lua'
  .. ';/path/to/wezterm-gitui-pane/?/init.lua'

local gitui_pane = require('plugin.init')
gitui_pane.apply_to_config(config)

return config
```

`apply_to_config` registers the keybindings on the provided `config`.

You need `gitui` available on `PATH` locally (and on each remote host you
want to use the SSH modes with).

## Configuration

Every field is optional; defaults shown below.

```lua
gitui_pane.apply_to_config(config, {
  gitui_path = nil,            -- resolves 'gitui' from PATH if nil
  gitui_args = {},

  -- Remote (SSH) support
  remote_gitui_path        = 'gitui',
  ssh_extra_args           = {},     -- e.g. { '-A' } for agent forwarding
  use_remote_cwd_from_osc7 = true,

  split = {
    direction = 'Right',       -- 'Right' | 'Left' | 'Top' | 'Bottom'
    size      = 0.4,           -- 0..1 fraction, or integer cells
    top_level = false,         -- split the top-level tab vs. the active pane
  },

  scope         = 'tab',       -- 'tab' | 'window'
  cwd_strategy  = 'walk_up',   -- 'walk_up' | 'error' | 'open_anyway'
  close_on_exit = true,        -- send 'q' to gitui on toggle-off

  keys = {
    toggle      = { key = 'g', mods = 'CMD' },
    focus       = { key = 'G', mods = 'CMD|SHIFT' },
    branch_pick = { key = 'B', mods = 'CMD|SHIFT' },
    log_pick    = { key = 'L', mods = 'CMD|SHIFT' },
  },

  branch_picker = {
    include_remotes = true,
    max_entries     = 200,
  },

  log_picker = {
    max_entries      = 50,
    diff_in_new_pane = true,
    pager            = 'less -R',
  },
})
```

### Scope: tab vs. window

- `scope = 'tab'` (default) — each tab tracks its own gitui pane. Toggling in
  one tab does not affect another.
- `scope = 'window'` — one gitui pane per window. Toggling from any tab will
  open, focus, or close that single shared pane.

### Remote modes

The plugin inspects the active pane to decide how to spawn gitui:

1. **`ssh_proc`** — the foreground process is `ssh` or `mosh`. The host (and
   port) are parsed from its argv, and gitui is launched through
   `ssh [extra_args] -t <host> "<remote_gitui_cmd>"`. If
   `use_remote_cwd_from_osc7` is set and the remote shell emits OSC 7, the
   reported cwd is used as `-d`.
2. **`ssh_domain`** — the pane belongs to a WezTerm SSH multiplexing domain.
   The new pane is split inside the same domain and runs `gitui`, with `-d
   <cwd>` if WezTerm knows the cwd.
3. **Local** — the cwd is resolved (walking up to find `.git` per
   `cwd_strategy`) and `gitui -d <repo>` is launched in a new split.

## Public API

```lua
gitui_pane.apply_to_config(config, opts)
gitui_pane.toggle(window, pane)
gitui_pane.focus(window, pane)
gitui_pane.branch_picker(window, pane)
gitui_pane.log_picker(window, pane)
```

You can bind these to your own keys instead of using the built-in `keys`
table.

## Project layout

```
plugin/
  init.lua     entry point: toggle/focus/pickers + key wiring
  config.lua   defaults & deep-merge
  git.lua      cwd / repo-root / branch / log parsing
  remote.lua   ssh argv parsing and remote-launch classification
tests/
  run.lua      harness against stub_wezterm.lua
```

## Tests

```sh
cd wezterm-gitui-pane
lua tests/run.lua
```

Tests stub `wezterm` and exercise the pure-logic helpers in `git.lua` and
`remote.lua`, so they run anywhere Lua 5.1+ is available.

## License

MIT — see [`LICENSE`](./LICENSE).
