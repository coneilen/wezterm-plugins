-- Configuration defaults & merge for wezterm-agent-deck (Claude Code + GitHub Copilot CLI focused)
local M = {}

local default_config = {
    update_interval = 750,
    cooldown_ms = 1500,
    max_lines = 120,
    enabled_agents = nil,

    agents = {
        -- Anthropic Claude Code CLI
        claude = {
            label = 'claude',
            executable_patterns = {
                '@anthropic%-ai/claude%-code',
                '%.claude/bin/claude',
                '/claude%-code/',
                '/claude$',
                '^claude$',
            },
            argv_patterns = {
                '@anthropic%-ai/claude%-code',
                'claude%-code',
                '^claude%s',
                '^claude$',
            },
            title_patterns = { 'claude code', 'claude' },
            status_patterns = {
                working = {
                    'esc to interrupt',
                    'thinking',
                    'pondering',
                    'cogitating',
                    'analyzing',
                    'reading',
                    'searching',
                    'editing',
                },
                waiting = {
                    'do you want to proceed',
                    'do you trust',
                    'approve this plan',
                    '%[y/n%]', '%[Y/n%]', '%[y/N%]', '%[Y/N%]',
                    '%(y/n%)', '%(Y/n%)', '%(y/N%)', '%(Y/N%)',
                    'press enter to continue',
                    '❯ Yes', '❯ No',
                },
                idle = { '^>%s*$', '^>%s' },
            },
        },

        -- GitHub Copilot CLI (ghcp / @github/copilot)
        copilot_cli = {
            label = 'ghcp',
            executable_patterns = {
                '@github/copilot',                 -- npm package
                '%.copilot%-cli/.-/copilot',       -- ~/.copilot-cli/<anything>/copilot (version, "current", etc.)
                '%.copilot/.-/copilot',            -- future ~/.copilot/.../copilot layouts
                '/github%-copilot%-cli/',          -- homebrew Cellar / linux pkg dirs
                '/copilot%-cli/',                  -- generic copilot-cli/ segment
                '/copilot$',                       -- bare binary
                '^copilot$',
            },
            argv_patterns = {
                '@github/copilot',
                'github%-copilot%-cli',
                '%.copilot%-cli/.-/copilot',
                '%.copilot/.-/copilot',
                '/copilot%-cli/',
                '^copilot%s',
                '^copilot$',
                'gh%s+copilot',
            },
            title_patterns = {
                'github copilot',
                'copilot cli',
                '^copilot$',
            },
            status_patterns = {
                working = {
                    'esc to interrupt',
                    'esc to cancel',
                    'thinking',
                    'working',
                    'running',
                    'reading',
                    'editing',
                    'planning',
                    'shell',                 -- "Shell" header during command exec
                    'tool',                  -- tool execution
                },
                waiting = {
                    'allow %S+ to run',          -- "Allow bash to run"
                    'allow this command',
                    'approve%?',
                    'continue%?',
                    'proceed%?',
                    '%[y/n%]', '%[Y/n%]', '%[y/N%]', '%[Y/N%]',
                    '%(y/n%)', '%(Y/n%)', '%(y/N%)', '%(Y/N%)',
                    'yes, and approve',
                    'yes, and allow',
                    'no, and tell copilot',
                    'tell copilot what to do',
                    'what would you like',
                    '❯ yes', '❯ no',
                    '> yes', '> no',
                },
                idle = {
                    '^>%s*$',
                    '^>%s',
                    'type your message',
                    'how can i help',
                    'shift%+tab',                -- input footer
                },
            },
        },
    },

    tab_title = {
        enabled = true,
        position = 'left',         -- 'left' | 'right'
        show_label = false,        -- show 'claude'/'ghcp' next to dot
        separator = ' ',
    },

    right_status = {
        enabled = true,
        show_counts = true,
        show_labels = true,        -- per-agent counts e.g. "claude:●1 ghcp:◔2"
    },

    colors = {
        working  = '#A6E22E',  -- green
        waiting  = '#E6DB74',  -- yellow
        idle     = '#66D9EF',  -- blue
        inactive = '#888888',
    },

    icons = {
        style = 'unicode',     -- 'unicode' | 'nerd' | 'emoji'
        unicode  = { working = '●', waiting = '◔', idle = '○', inactive = '◌' },
        nerd     = { working = '\u{f111}', waiting = '\u{f042}', idle = '\u{f10c}', inactive = '\u{eabc}' },
        emoji    = { working = '🟢', waiting = '🟡', idle = '🔵', inactive = '⚪' },
    },

    notifications = {
        enabled = true,
        on_waiting = true,
        on_finished = false,
        cooldown_ms = 5000,         -- per-pane dedupe window
        backend = 'native',         -- 'native' | 'terminal-notifier'
        terminal_notifier = {
            path = nil,
            sound = 'default',
            title = 'Agent Deck',
            group = 'wezterm-agent-deck',
            activate = true,
        },
    },
}

local current

local function deep_copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deep_copy(v) end
    return r
end

local function deep_merge(base, override)
    local r = deep_copy(base)
    if type(override) ~= 'table' then return r end
    for k, v in pairs(override) do
        if type(v) == 'table' and type(r[k]) == 'table' then
            r[k] = deep_merge(r[k], v)
        else
            r[k] = deep_copy(v)
        end
    end
    return r
end

function M.set(opts)
    current = deep_merge(default_config, opts or {})
    return current
end

function M.get()
    if not current then current = deep_copy(default_config) end
    return current
end

function M.get_defaults() return deep_copy(default_config) end

function M.get_status_color(status, config)
    config = config or M.get()
    return config.colors[status] or config.colors.inactive
end

function M.get_status_icon(status, config)
    config = config or M.get()
    local set = config.icons[config.icons.style] or config.icons.unicode
    return set[status] or set.inactive
end

function M.get_agent_label(agent, config)
    config = config or M.get()
    local a = config.agents[agent]
    return (a and a.label) or agent
end

return M
