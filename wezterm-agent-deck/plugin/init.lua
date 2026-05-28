-- wezterm-agent-deck: monitor Claude Code & GitHub Copilot CLI from WezTerm
local wezterm = require('wezterm')
local config_mod = require('plugin.config')
local detector = require('plugin.detector')
local status_mod = require('plugin.status')
local notifications = require('plugin.notifications')
local renderer = require('plugin.renderer')

local M = {}

-- pane_id -> { agent, status, last_change_ts, working_since_ts }
local pane_state = {}

local function now_ms() return os.time() * 1000 end

local function get_helpers(cfg)
    return {
        icon  = function(s) return config_mod.get_status_icon(s, cfg) end,
        color = function(s) return config_mod.get_status_color(s, cfg) end,
        label = function(a) return config_mod.get_agent_label(a, cfg) end,
    }
end

local function update_pane_state(pane, cfg)
    local pane_id = pane:pane_id()
    local agent = detector.detect_agent(pane, cfg)
    local status = status_mod.detect_status(pane, agent, cfg)

    local prev = pane_state[pane_id] or { status = nil, agent = nil }

    -- Cooldown: damp working -> idle flips
    if prev.status == 'working' and status == 'idle' then
        local cd = cfg.cooldown_ms or 0
        if prev.last_change_ts and (now_ms() - prev.last_change_ts) < cd then
            status = 'working'
        end
    end

    if status ~= prev.status or agent ~= prev.agent then
        pane_state[pane_id] = {
            agent = agent,
            status = status,
            last_change_ts = now_ms(),
        }
    else
        pane_state[pane_id] = prev
        pane_state[pane_id].agent = agent
        pane_state[pane_id].status = status
    end

    return pane_state[pane_id], prev
end

local function refresh_all(window, cfg)
    local mux_window = window:mux_window()
    for _, tab in ipairs(mux_window:tabs()) do
        for _, pane in ipairs(tab:panes()) do
            local new_state, prev = update_pane_state(pane, cfg)
            if new_state.status ~= prev.status and new_state.agent then
                local label = config_mod.get_agent_label(new_state.agent, cfg)
                notifications.maybe_notify(wezterm, window, pane:pane_id(),
                    label, new_state.status, cfg)
            end
        end
    end
end

function M.get_agent_state(pane_id) return pane_state[pane_id] end
function M.get_all_states() return pane_state end
function M.get_status_color(s) return config_mod.get_status_color(s) end
function M.get_status_icon(s) return config_mod.get_status_icon(s) end
function M.get_config() return config_mod.get() end

function M.apply_to_config(config, opts)
    local cfg = config_mod.set(opts)

    -- Tab title hook
    if cfg.tab_title.enabled then
        wezterm.on('format-tab-title', function(tab, _tabs, _panes, _conf, _hover, _max_width)
            local states = {}
            for _, p in ipairs(tab.panes or {}) do
                local st = pane_state[p.pane_id]
                if st then states[p.pane_id] = st end
            end
            local prefix = renderer.format_tab_title(states, cfg, get_helpers(cfg))
            local title = tab.tab_title
            if not title or title == '' then
                title = (tab.active_pane and tab.active_pane.title) or 'wezterm'
            end
            if not prefix then return title end
            if cfg.tab_title.position == 'right' then
                table.insert(prefix, 1, { Text = title })
                return wezterm.format(prefix)
            else
                table.insert(prefix, { Text = title })
                return wezterm.format(prefix)
            end
        end)
    end

    -- Status refresh + right status
    wezterm.on('update-status', function(window, _pane)
        refresh_all(window, cfg)
        if cfg.right_status.enabled then
            local segments = renderer.format_right_status(pane_state, cfg, get_helpers(cfg))
            if segments and #segments > 0 then
                window:set_right_status(wezterm.format(segments))
            else
                window:set_right_status('')
            end
        end
    end)

    return cfg
end

return M
