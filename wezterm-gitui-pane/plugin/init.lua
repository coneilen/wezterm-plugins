-- wezterm-gitui-pane: open & integrate gitui from WezTerm
local wezterm = require('wezterm')
local config_mod = require('plugin.config')
local git = require('plugin.git')
local remote = require('plugin.remote')

local M = {}

-- Tracked gitui panes: scope-key -> pane_id
local tracked = {}

local function scope_key(window, tab, cfg)
    if cfg.scope == 'window' then
        return 'w:' .. tostring(window:window_id())
    end
    return 't:' .. tostring(tab:tab_id())
end

local function find_tracked_pane(window, tab, cfg)
    local key = scope_key(window, tab, cfg)
    local pane_id = tracked[key]
    if not pane_id then return nil end

    local search_tabs
    if cfg.scope == 'window' then
        search_tabs = window:mux_window():tabs()
    else
        search_tabs = { tab }
    end

    for _, t in ipairs(search_tabs) do
        for _, p in ipairs(t:panes()) do
            if p:pane_id() == pane_id then return p end
        end
    end

    -- Stale entry — clean up
    tracked[key] = nil
    return nil
end

local function resolve_cwd(pane, cfg)
    local cwd_obj = pane:get_current_working_dir()
    local cwd = git.cwd_from_url(cwd_obj)
    if not cwd then return nil, 'no_cwd' end

    local function exists(path)
        local f = io.open(path, 'r')
        if f then f:close(); return true end
        -- Directories aren't openable via io.open on all systems; fall back to ls
        local ok = os.execute('test -e ' .. string.format('%q', path) .. ' 2>/dev/null')
        return ok == true or ok == 0
    end

    return git.resolve_repo_root(cwd, exists, cfg.cwd_strategy)
end

-- Inspect a pane and decide how gitui should be launched for it.
local function classify_pane(pane, cfg)
    local domain_name = nil
    pcall(function() domain_name = pane:get_domain_name() end)
    local cwd_url
    pcall(function() cwd_url = pane:get_current_working_dir() end)
    local fg
    pcall(function() fg = pane:get_foreground_process_info() end)

    local local_host = ''
    pcall(function() local_host = wezterm.hostname() end)

    return remote.classify(domain_name, cwd_url, fg, local_host, {
        cwd_from_url = git.cwd_from_url,
        host_from_url = git.host_from_url,
    })
end

local function notify(window, body)
    pcall(function() window:toast_notification('gitui', body, nil, 3000) end)
end

local function spawn_gitui(window, pane, cfg)
    local cls = classify_pane(pane, cfg)

    -- ── Mode A: plain ssh process in a local pane ────────────────────────
    if cls.mode == 'ssh_proc' then
        if not cls.parsed or not cls.parsed.host then
            notify(window, 'Could not determine ssh host')
            return nil
        end
        local remote_cwd = cfg.use_remote_cwd_from_osc7 and cls.cwd or nil
        local rcmd = remote.build_remote_gitui_cmd(cfg.remote_gitui_path, remote_cwd)
        local argv = remote.build_ssh_gitui_argv(cls.parsed, rcmd, cfg.ssh_extra_args)

        local direction = cfg.split.direction or 'Right'
        local ok, new_pane = pcall(function()
            return pane:split({
                direction = direction,
                size = cfg.split.size,
                args = argv,
                top_level = cfg.split.top_level and true or false,
            })
        end)
        if not ok or not new_pane then
            notify(window, 'Failed to spawn remote gitui pane')
            wezterm.log_error('[gitui-pane] ssh split failed: ' .. tostring(new_pane))
            return nil
        end
        return new_pane
    end

    -- ── Mode B: WezTerm SSH multiplexing domain ──────────────────────────
    if cls.mode == 'ssh_domain' then
        local direction = cfg.split.direction or 'Right'
        -- gitui without -d so it uses the pane's cwd. If we got a cwd via
        -- OSC 7 we pass it through; otherwise let gitui run from $HOME.
        local args = { cfg.remote_gitui_path or 'gitui' }
        if cls.cwd and cls.cwd ~= '' then
            args = { cfg.remote_gitui_path or 'gitui', '-d', cls.cwd }
        end

        local split_opts = {
            direction = direction,
            size = cfg.split.size,
            args = args,
            top_level = cfg.split.top_level and true or false,
            domain = { DomainName = cls.domain },
        }
        if cls.cwd and cls.cwd ~= '' then split_opts.cwd = cls.cwd end

        local ok, new_pane = pcall(function() return pane:split(split_opts) end)
        if not ok or not new_pane then
            notify(window, 'Failed to spawn gitui in ' .. cls.domain)
            wezterm.log_error('[gitui-pane] domain split failed: ' .. tostring(new_pane))
            return nil
        end
        return new_pane
    end

    -- ── Mode local: original behaviour ───────────────────────────────────
    local repo, err = resolve_cwd(pane, cfg)
    if not repo then
        notify(window, err == 'not_a_repo' and 'Not a git repository' or 'Cannot determine cwd')
        return nil
    end

    local argv = git.build_gitui_argv(cfg.gitui_path, repo, cfg.gitui_args)

    local direction_map = {
        Right = 'Right', Left = 'Left', Top = 'Top', Bottom = 'Bottom',
    }
    local direction = direction_map[cfg.split.direction] or 'Right'

    local ok, new_pane = pcall(function()
        return pane:split({
            direction = direction,
            size = cfg.split.size,
            cwd = repo,
            args = argv,
            top_level = cfg.split.top_level and true or false,
        })
    end)
    if not ok or not new_pane then
        notify(window, 'Failed to spawn gitui pane')
        wezterm.log_error('[gitui-pane] split failed: ' .. tostring(new_pane))
        return nil
    end
    return new_pane
end

function M.toggle(window, pane)
    local cfg = config_mod.get()
    local tab = pane:tab()
    local existing = find_tracked_pane(window, tab, cfg)
    if existing then
        local key = scope_key(window, tab, cfg)
        if cfg.close_on_exit then
            pcall(function() existing:send_text('q') end) -- gitui quits on 'q'
            -- Also activate the previous pane visually
            pcall(function() pane:activate() end)
        else
            pcall(function() existing:activate() end)
        end
        tracked[key] = nil
        return
    end
    local new_pane = spawn_gitui(window, pane, cfg)
    if new_pane then
        tracked[scope_key(window, tab, cfg)] = new_pane:pane_id()
    end
end

function M.focus(window, pane)
    local cfg = config_mod.get()
    local existing = find_tracked_pane(window, pane:tab(), cfg)
    if existing then
        pcall(function() existing:activate() end)
        return
    end
    M.toggle(window, pane)
end

-- ─── Overlays: branch picker & log picker (Option-C extras) ────────────────

local function run_git(repo, args)
    local cmd = string.format("cd %q && git %s 2>&1", repo, args)
    local f = io.popen(cmd)
    if not f then return nil end
    local out = f:read('*a')
    f:close()
    return out
end

function M.branch_picker(window, pane)
    local cfg = config_mod.get()
    local repo, err = resolve_cwd(pane, cfg)
    if not repo then notify(window, err or 'not a git repo'); return end

    local flag = cfg.branch_picker.include_remotes and '--all' or ''
    local raw = run_git(repo, 'branch ' .. flag .. ' --no-color')
    local branches = git.parse_branches(raw or '')

    local choices = {}
    for i, b in ipairs(branches) do
        if i > (cfg.branch_picker.max_entries or 200) then break end
        local prefix = b.current and '● ' or (b.remote and '↦ ' or '  ')
        choices[#choices + 1] = { id = b.name, label = prefix .. b.name }
    end
    if #choices == 0 then notify(window, 'No branches'); return end

    window:perform_action(
        wezterm.action.InputSelector({
            title = 'Checkout branch',
            choices = choices,
            fuzzy = true,
            action = wezterm.action_callback(function(_win, _pane, id, _label)
                if not id then return end
                local target = id:gsub('^origin/', '')
                run_git(repo, 'checkout ' .. string.format('%q', target))
                notify(window, 'Checked out ' .. target)
            end),
        }),
        pane
    )
end

function M.log_picker(window, pane)
    local cfg = config_mod.get()
    local repo, err = resolve_cwd(pane, cfg)
    if not repo then notify(window, err or 'not a git repo'); return end

    local n = cfg.log_picker.max_entries or 50
    local raw = run_git(repo,
        string.format('log -n %d --no-color --pretty=format:%%h%%x1f%%s%%x1f%%an%%x1f%%ar', n))
    local commits = git.parse_log(raw or '')

    local choices = {}
    for _, c in ipairs(commits) do
        choices[#choices + 1] = {
            id = c.hash,
            label = string.format('%s  %s  (%s, %s)', c.hash, c.subject, c.author, c.age),
        }
    end
    if #choices == 0 then notify(window, 'No commits'); return end

    window:perform_action(
        wezterm.action.InputSelector({
            title = 'Show commit diff',
            choices = choices,
            fuzzy = true,
            action = wezterm.action_callback(function(_win, target_pane, id, _label)
                if not id then return end
                local pager = cfg.log_picker.pager or 'less -R'
                local sh = string.format('git -C %q show --color=always %s | %s', repo, id, pager)
                if cfg.log_picker.diff_in_new_pane then
                    pcall(function()
                        target_pane:split({
                            direction = 'Bottom',
                            cwd = repo,
                            args = { 'sh', '-c', sh },
                        })
                    end)
                else
                    pcall(function() target_pane:send_text(sh .. '\n') end)
                end
            end),
        }),
        pane
    )
end

-- ─── Setup ────────────────────────────────────────────────────────────────

local function bind(config, k, callback)
    if not k then return end
    config.keys = config.keys or {}
    table.insert(config.keys, {
        key = k.key, mods = k.mods,
        action = wezterm.action_callback(callback),
    })
end

function M.apply_to_config(config, opts)
    local cfg = config_mod.set(opts)

    bind(config, cfg.keys.toggle,      function(win, pane) M.toggle(win, pane) end)
    bind(config, cfg.keys.focus,       function(win, pane) M.focus(win, pane) end)
    bind(config, cfg.keys.branch_pick, function(win, pane) M.branch_picker(win, pane) end)
    bind(config, cfg.keys.log_pick,    function(win, pane) M.log_picker(win, pane) end)

    return cfg
end

return M
