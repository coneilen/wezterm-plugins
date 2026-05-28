# wezterm-plugins

A monorepo of [WezTerm](https://wezfurlong.org/wezterm/) plugins I use to make
my terminal a slightly nicer place to live. Each plugin is self-contained,
plain Lua, MIT-licensed, and has its own README, tests, and config.

## Plugins

| Plugin | What it does |
| --- | --- |
| [**wezterm-agent-deck**](./wezterm-agent-deck) | Watches panes for **Claude Code** and **GitHub Copilot CLI** sessions and surfaces their state via tab-title dots, a right-status summary, and OS notifications when an agent is waiting on you. |
| [**wezterm-gitui-pane**](./wezterm-gitui-pane) | Opens [gitui](https://github.com/gitui-org/gitui) as a toggleable split pane anchored to the current pane's repo — locally, over plain `ssh`, or inside a WezTerm SSH multiplexing domain. Ships with branch-picker and log-picker overlays. |

See each plugin's README for install snippets, configuration, and API.

## Layout

```
wezterm-plugins/
├── wezterm-agent-deck/   # AI-agent status monitor
│   ├── plugin/
│   ├── tests/
│   ├── LICENSE
│   └── README.md
└── wezterm-gitui-pane/   # gitui side-pane integration
    ├── plugin/
    ├── tests/
    ├── LICENSE
    └── README.md
```

Each plugin is independent — you can clone or vendor just the one you want.

## Requirements

- WezTerm (recent nightly recommended for the multiplexing-domain features used
  by `wezterm-gitui-pane`).
- Lua 5.1+ to run the test harnesses locally.
- `gitui` on `PATH` (for `wezterm-gitui-pane`).

## Tests

Each plugin has a self-contained test runner that stubs `wezterm`, so no real
WezTerm process is needed:

```sh
cd wezterm-agent-deck && lua tests/run.lua
cd wezterm-gitui-pane && lua tests/run.lua
```

## License

Each plugin is MIT-licensed; see the `LICENSE` file inside each directory.
