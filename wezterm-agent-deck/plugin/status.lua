-- Infer status (working / waiting / idle) from rendered pane text
local M = {}

local function strip_ansi(s)
    if not s then return '' end
    s = s:gsub('\27%].-\007', '')
    s = s:gsub('\27%].-\27\\', '')
    s = s:gsub('\27%[[%d;%?]*[A-Za-z]', '')
    s = s:gsub('\r', '')
    return s
end

local function last_lines(text, n)
    local lines = {}
    for line in text:gmatch('[^\n]+') do lines[#lines + 1] = line end
    local start = math.max(1, #lines - n + 1)
    local out = {}
    for i = start, #lines do out[#out + 1] = lines[i] end
    return table.concat(out, '\n')
end

local function match_any(text, patterns)
    if not text or not patterns then return false end
    local low = text:lower()
    for _, p in ipairs(patterns) do
        local ok, hit = pcall(function() return low:find(p:lower()) end)
        if ok and hit then return true end
        if not ok and low:find(p:lower(), 1, true) then return true end
    end
    return false
end

local function get_patterns(agent_cfg)
    return (agent_cfg and agent_cfg.status_patterns) or {}
end

function M.detect_status(pane, agent, cfg)
    if not agent then return 'inactive' end
    local ok, text = pcall(function()
        return pane:get_lines_as_text(cfg.max_lines or 120)
    end)
    if not ok or not text or text == '' then return 'inactive' end

    local clean = strip_ansi(text)
    local patt = get_patterns(cfg.agents[agent])

    -- Priority: waiting > working > idle (input prompts beat spinners)
    local recent = last_lines(clean, 30)
    if match_any(recent, patt.waiting) then return 'waiting' end

    local very_recent = last_lines(clean, 10)
    if match_any(very_recent, patt.working) then return 'working' end

    -- Explicit idle prompt detection on the last few lines
    local tail = last_lines(clean, 5)
    for line in tail:gmatch('[^\n]+') do
        local trimmed = (line:match('^%s*(.-)%s*$')) or ''
        if trimmed == '>' or trimmed:match('^>%s') then return 'idle' end
        if match_any(trimmed, patt.idle) then return 'idle' end
    end

    return 'idle'
end

M.strip_ansi = strip_ansi
M._internal = { last_lines = last_lines, match_any = match_any }

return M
