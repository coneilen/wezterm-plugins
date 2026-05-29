-- Defaults & merge for wezterm-gitui-pane
local M = {}

local default_config = {
    -- Path to gitui binary (auto-resolved from PATH if nil)
    gitui_path = nil,
    -- Extra args passed to gitui
    gitui_args = {},

    -- ── Remote (SSH) support ──────────────────────────────────────────────
    -- Path to gitui on the remote host. Defaults to bare 'gitui' which
    -- assumes it's on the remote $PATH. Set to an absolute path if not.
    remote_gitui_path = 'gitui',
    -- Extra args inserted into the local `ssh ... -t <host>` invocation
    -- when launching gitui through a plain ssh process (mode A). E.g. {'-A'}.
    ssh_extra_args = {},
    -- If true, try to honour the pane's reported cwd (via OSC 7) when sshing.
    -- Disable if your remote shells don't emit OSC 7 cleanly.
    use_remote_cwd_from_osc7 = true,

    -- How the gitui pane is created
    split = {
        direction = 'Right',       -- 'Right' | 'Left' | 'Top' | 'Bottom'
        size = 0.4,                -- 0..1 fraction of parent pane, or integer cells
        top_level = false,         -- split the top-level tab instead of the active pane
    },

    -- Scope: where to track the gitui pane
    --   'tab'    — one gitui pane per tab (default)
    --   'window' — one gitui pane per window (closes/refocuses across tabs)
    scope = 'tab',

    -- If a non-git cwd: 'walk_up' (find nearest .git ancestor) | 'error' | 'open_anyway'
    cwd_strategy = 'walk_up',

    -- Auto-close the gitui pane when gitui exits (kept open by default)
    close_on_exit = true,

    -- Keybindings (set to false to disable any individual binding)
    keys = {
        toggle        = { key = 'g', mods = 'CMD' },         -- toggle gitui pane
        branch_pick   = { key = 'B', mods = 'CMD|SHIFT' },   -- branch picker overlay
        log_pick      = { key = 'L', mods = 'CMD|SHIFT' },   -- recent commit -> show in new pane
        focus         = { key = 'G', mods = 'CMD|SHIFT' },   -- focus gitui pane (no toggle)
        worktree_pick = { key = 'W', mods = 'CMD|SHIFT' },   -- worktree picker overlay
    },

    -- Limits for overlays
    branch_picker = {
        include_remotes = true,
        max_entries = 200,
    },
    log_picker = {
        max_entries = 50,
        diff_in_new_pane = true,
        pager = 'less -R',
    },
    worktree_picker = {
        max_entries = 50,
        -- What to do with the chosen worktree:
        --   'shell' — split a new pane with your $SHELL, cwd set to the worktree
        --   'gitui' — split a new pane running gitui pointed at the worktree
        --   'cd'    — send `cd <path>` to the current pane (no new pane)
        action = 'shell',
        split = {
            direction = 'Right',
            size = 0.4,
            top_level = false,
        },
        -- Hide the main worktree from the picker (useful when you only want
        -- to jump between linked worktrees)
        hide_current = false,
    },
}

local function deep_copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}; for k, v in pairs(t) do r[k] = deep_copy(v) end; return r
end

local function deep_merge(base, over)
    local r = deep_copy(base)
    if type(over) ~= 'table' then return r end
    for k, v in pairs(over) do
        if type(v) == 'table' and type(r[k]) == 'table' then
            r[k] = deep_merge(r[k], v)
        else
            r[k] = deep_copy(v)
        end
    end
    return r
end

local current
function M.set(opts) current = deep_merge(default_config, opts or {}); return current end
function M.get() if not current then current = deep_copy(default_config) end; return current end
function M.get_defaults() return deep_copy(default_config) end

return M
