-- Notify on agent state transitions
local M = {}

local last_notify = {} -- pane_id -> { status, ts }

local function now_ms() return os.time() * 1000 end

local function should_notify(pane_id, new_status, cfg)
    local n = cfg.notifications
    if not n or not n.enabled then return false end
    if new_status == 'waiting' and not n.on_waiting then return false end
    if new_status == 'idle' and not n.on_finished then return false end
    if new_status == 'working' or new_status == 'inactive' then return false end

    local prev = last_notify[pane_id]
    if prev and prev.status == new_status
        and (now_ms() - prev.ts) < (n.cooldown_ms or 5000) then
        return false
    end
    return true
end

local function send_terminal_notifier(wezterm, title, body, cfg)
    local tn = cfg.notifications.terminal_notifier or {}
    local bin = tn.path or 'terminal-notifier'
    local args = { bin, '-message', body, '-title', title }
    if tn.sound then args[#args + 1] = '-sound'; args[#args + 1] = tn.sound end
    if tn.group then args[#args + 1] = '-group'; args[#args + 1] = tn.group end
    if tn.activate then args[#args + 1] = '-activate'; args[#args + 1] = 'com.github.wez.wezterm' end
    pcall(function() wezterm.background_child_process(args) end)
end

function M.maybe_notify(wezterm, window, pane_id, agent_label, new_status, cfg)
    if not should_notify(pane_id, new_status, cfg) then return end
    last_notify[pane_id] = { status = new_status, ts = now_ms() }

    local title = string.format('Agent Deck: %s', agent_label or 'agent')
    local body
    if new_status == 'waiting' then body = string.format('%s needs your input', agent_label)
    elseif new_status == 'idle' then body = string.format('%s is idle', agent_label)
    else return end

    if (cfg.notifications.backend or 'native') == 'terminal-notifier' then
        send_terminal_notifier(wezterm, title, body, cfg)
    else
        if window and window.toast_notification then
            pcall(function() window:toast_notification(title, body, nil, 4000) end)
        end
    end
end

function M.reset(pane_id)
    if pane_id then last_notify[pane_id] = nil else last_notify = {} end
end

return M
