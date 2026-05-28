-- Detect which AI agent (if any) is running in a wezterm pane
local M = {}

local CACHE_TTL_MS = 3000
local cache = {} -- pane_id -> { agent, ts }

local function now_ms() return os.time() * 1000 end

local function basename(p)
    if not p or p == '' then return '' end
    local n = p:match('[/\\]([^/\\]+)$') or p
    return (n:gsub('%.exe$', ''))
end

local function match_any(s, patterns)
    if not s or not patterns then return false end
    local low = s:lower()
    for _, p in ipairs(patterns) do
        local ok, hit = pcall(function() return low:find(p:lower()) end)
        if ok and hit then return true end
        if not ok and low:find(p:lower(), 1, true) then return true end
    end
    return false
end

local function is_enabled(agent, cfg)
    if not cfg.enabled_agents then return true end
    for _, a in ipairs(cfg.enabled_agents) do
        if a == agent then return true end
    end
    return false
end

local function check_proc(exe, argv_str, cfg)
    -- Normalize Windows backslashes so the same forward-slash patterns work everywhere
    exe = (exe or ''):gsub('\\', '/')
    argv_str = (argv_str or ''):gsub('\\', '/')
    local exe_name = basename(exe)
    for agent, a in pairs(cfg.agents) do
        if is_enabled(agent, cfg) then
            if match_any(exe, a.executable_patterns)
                or match_any(exe_name, a.executable_patterns)
                or match_any(argv_str, a.argv_patterns) then
                return agent
            end
        end
    end
end

local function check_title(title, cfg)
    if not title or title == '' then return nil end
    for agent, a in pairs(cfg.agents) do
        if is_enabled(agent, cfg) and match_any(title, a.title_patterns) then
            return agent
        end
    end
end

local function walk_process(info, cfg)
    if not info then return nil end
    local exe = info.executable or ''
    local name = info.name or ''
    local argv = info.argv or {}
    local argv_str = table.concat(argv, ' ')

    local agent = check_proc(exe, argv_str, cfg)
        or (name ~= '' and check_proc(name, argv_str, cfg))
    if agent then return agent end

    if info.children then
        for _, child in pairs(info.children) do
            agent = walk_process(child, cfg)
            if agent then return agent end
        end
    end
end

function M.detect_agent(pane, cfg)
    local pane_id = pane:pane_id()
    local entry = cache[pane_id]
    if entry and (now_ms() - entry.ts) < CACHE_TTL_MS then
        return entry.agent
    end

    local agent
    local ok, info = pcall(function() return pane:get_foreground_process_info() end)
    if ok and info then agent = walk_process(info, cfg) end

    if not agent then
        local ok2, pname = pcall(function() return pane:get_foreground_process_name() end)
        if ok2 and pname then agent = check_proc(pname, '', cfg) end
    end

    if not agent then
        local ok3, title = pcall(function() return pane:get_title() end)
        if ok3 then agent = check_title(title, cfg) end
    end

    cache[pane_id] = { agent = agent, ts = now_ms() }
    return agent
end

function M.clear_cache(pane_id)
    if pane_id then cache[pane_id] = nil else cache = {} end
end

-- exposed for tests
M._internal = {
    check_proc = check_proc,
    check_title = check_title,
    basename = basename,
    match_any = match_any,
}

return M
