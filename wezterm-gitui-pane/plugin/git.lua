-- Git helpers: cwd resolution + small shell-out wrappers (pure-logic, testable)
local M = {}

-- Normalise backslashes to forward slashes and strip trailing separators,
-- preserving Windows drive roots like "C:/".
local function normalise(path)
    path = path:gsub('\\', '/')
    -- Strip trailing slashes, but keep "C:/" intact
    path = path:gsub('/+$', '')
    if path:match('^[A-Za-z]:$') then path = path .. '/' end
    if path == '' then path = '/' end
    return path
end

-- Return true when `path` is a filesystem root (/ or C:/).
local function is_root(path)
    return path == '/' or path:match('^[A-Za-z]:/$') ~= nil
end

-- Strip a leading slash before a Windows drive letter ("/C:/…" → "C:/…").
-- WezTerm URLs often produce paths in this form.
function M.strip_leading_slash_drive(path)
    if not path then return path end
    return (path:gsub('^/([A-Za-z]:)', '%1'))
end

-- Resolve a cwd from a pane to a git repo root, honouring config.cwd_strategy.
-- Returns (cwd, error). error == 'not_a_repo' if no .git ancestor found.
function M.resolve_repo_root(start_cwd, exists_fn, strategy)
    if not start_cwd or start_cwd == '' then return nil, 'no_cwd' end
    strategy = strategy or 'walk_up'

    if strategy == 'open_anyway' then return start_cwd end

    local cwd = normalise(start_cwd)

    local guard = 0
    while cwd ~= '' do
        guard = guard + 1
        if guard > 64 then break end
        if exists_fn(cwd .. '/.git') then return cwd end
        if is_root(cwd) then break end
        local parent = cwd:match('^(.+)/[^/]+$')
        if not parent or parent == cwd then
            parent = '/'
        end
        -- Preserve drive root: "C:" after stripping becomes "C:/"
        if parent:match('^[A-Za-z]:$') then parent = parent .. '/' end
        cwd = parent
    end

    if strategy == 'walk_up' then
        return nil, 'not_a_repo'
    end
    return start_cwd
end

-- Extract a cwd path from a `file://host/path` URL (pane:get_current_working_dir() form).
function M.cwd_from_url(url_or_string)
    if not url_or_string then return nil end
    -- Newer wezterm: userdata with file_path field
    if type(url_or_string) == 'userdata' or type(url_or_string) == 'table' then
        local ok, fp = pcall(function() return url_or_string.file_path end)
        -- Skip UNC paths (\\host\...) — they are returned when the file URL
        -- contains a hostname and are not usable for local file operations.
        if ok and fp and fp ~= '' and not fp:match('^\\\\') then
            return M.strip_leading_slash_drive(fp)
        end
        local ok2, path = pcall(function() return url_or_string.path end)
        if ok2 and path and path ~= '' then
            -- URL-decode %xx
            path = path:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
            return M.strip_leading_slash_drive(path)
        end
    end
    if type(url_or_string) == 'string' then
        local s = url_or_string
        -- file://host/path
        local p = s:match('^file://[^/]*(/.*)$') or s:match('^file:(/.*)$') or s
        p = p:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
        return M.strip_leading_slash_drive(p)
    end
end

-- Extract the host component of a `file://host/path` URL — used to detect
-- whether the cwd reported by OSC 7 is on a different machine than us.
function M.host_from_url(url_or_string)
    if not url_or_string then return nil end
    if type(url_or_string) == 'userdata' or type(url_or_string) == 'table' then
        local ok, h = pcall(function() return url_or_string.host end)
        if ok and h and h ~= '' then return h end
    end
    if type(url_or_string) == 'string' then
        local h = url_or_string:match('^file://([^/]*)/')
        if h == nil or h == '' then return nil end
        return h
    end
end

-- Build the argv to launch gitui in a given repo path.
function M.build_gitui_argv(gitui_path, repo_path, extra_args)
    local argv = { gitui_path or 'gitui', '-d', repo_path }
    if extra_args then
        for _, a in ipairs(extra_args) do argv[#argv + 1] = a end
    end
    return argv
end

-- Parse `git branch` output (with or without --all). Returns list of {name, current, remote}.
function M.parse_branches(text)
    local out = {}
    if not text then return out end
    for line in text:gmatch('[^\r\n]+') do
        local current = line:sub(1, 1) == '*'
        local name = line:gsub('^%s*%*?%s*', '')
        -- Skip detached HEAD lines like "(HEAD detached at abcd)"
        if not name:match('^%(') then
            -- Strip "remotes/" prefix and " -> " tracking arrows
            local remote = name:match('^remotes/')
            name = name:gsub('^remotes/', '')
            name = name:gsub('%s+%->.*$', '')
            if name ~= '' then
                out[#out + 1] = { name = name, current = current, remote = remote ~= nil }
            end
        end
    end
    return out
end

-- Parse `git worktree list --porcelain` output. Returns list of
-- { path, head, branch, detached, bare, locked, prunable, is_current }.
-- `is_current` requires the caller to pass the active worktree path so we can
-- mark it; pass nil to skip.
function M.parse_worktrees(text, current_path)
    local out = {}
    if not text then return out end

    local cur
    local function flush()
        if cur and cur.path then
            if current_path and cur.path == current_path then
                cur.is_current = true
            end
            out[#out + 1] = cur
        end
        cur = nil
    end

    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        if line == '' then
            flush()
        else
            local key, rest = line:match('^(%S+)%s*(.*)$')
            if key == 'worktree' then
                flush()
                cur = { path = rest }
            elseif cur then
                if key == 'HEAD' then
                    cur.head = rest
                elseif key == 'branch' then
                    -- e.g. refs/heads/feature/x -> feature/x
                    cur.branch = (rest:gsub('^refs/heads/', ''))
                elseif key == 'detached' then
                    cur.detached = true
                elseif key == 'bare' then
                    cur.bare = true
                elseif key == 'locked' then
                    cur.locked = rest ~= '' and rest or true
                elseif key == 'prunable' then
                    cur.prunable = rest ~= '' and rest or true
                end
            end
        end
    end
    flush()
    return out
end

-- Parse `git log --pretty=...` output we control. Format: %h\x1f%s\x1f%an\x1f%ar
function M.parse_log(text)
    local out = {}
    if not text then return out end
    for line in text:gmatch('[^\r\n]+') do
        local hash, subject, author, age = line:match('^([^\31]+)\31([^\31]+)\31([^\31]+)\31(.+)$')
        if hash then
            out[#out + 1] = { hash = hash, subject = subject, author = author, age = age }
        end
    end
    return out
end

return M
