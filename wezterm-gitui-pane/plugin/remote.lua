-- Pure-logic helpers for SSH-aware spawning. Kept side-effect free so the test
-- harness can exercise classification + argv construction without WezTerm.
local M = {}

local function basename(p)
    if not p then return nil end
    p = p:gsub('\\', '/')
    return (p:match('([^/]+)$') or p)
end

local function shell_quote(s)
    -- POSIX-safe single-quote escape: a'b -> 'a'\''b'
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

M.shell_quote = shell_quote
M.basename = basename

-- Parse an ssh argv (e.g. {'ssh', '-p', '2222', '-A', 'user@host', 'remote-cmd'})
-- into { host, port, extra_args, has_command }. Returns nil if argv doesn't
-- look like ssh/mosh.
function M.parse_ssh_argv(argv)
    if type(argv) ~= 'table' or #argv == 0 then return nil end
    local exe = basename(argv[1])
    if exe ~= 'ssh' and exe ~= 'mosh' then return nil end

    -- ssh option flags that take an argument
    local takes_arg = {
        ['-B'] = true, ['-b'] = true, ['-c'] = true, ['-D'] = true,
        ['-E'] = true, ['-e'] = true, ['-F'] = true, ['-I'] = true,
        ['-i'] = true, ['-J'] = true, ['-L'] = true, ['-l'] = true,
        ['-m'] = true, ['-O'] = true, ['-o'] = true, ['-p'] = true,
        ['-Q'] = true, ['-R'] = true, ['-S'] = true, ['-W'] = true,
        ['-w'] = true,
    }

    local host, port, extra = nil, nil, {}
    local i = 2
    while i <= #argv do
        local a = argv[i]
        if a == '--' then
            i = i + 1
            if i <= #argv then host = argv[i]; i = i + 1 end
            break
        elseif a:sub(1, 1) == '-' and #a >= 2 then
            local flag = a:sub(1, 2)
            if takes_arg[flag] then
                if #a > 2 then
                    -- combined form like -p2222
                    if flag == '-p' then port = tonumber(a:sub(3)) end
                    extra[#extra + 1] = a
                    i = i + 1
                else
                    if flag == '-p' and argv[i + 1] then
                        port = tonumber(argv[i + 1])
                    end
                    extra[#extra + 1] = a
                    if argv[i + 1] then extra[#extra + 1] = argv[i + 1] end
                    i = i + 2
                end
            else
                extra[#extra + 1] = a
                i = i + 1
            end
        else
            host = a
            i = i + 1
            break
        end
    end

    local has_command = i <= #argv

    if not host then return nil end
    return {
        executable = exe,
        host = host,
        port = port,
        extra = extra,
        has_command = has_command,
    }
end

-- Build the inner command to run on the remote side of an ssh invocation.
-- We use `exec` so signals (Ctrl-C, etc.) reach gitui directly.
function M.build_remote_gitui_cmd(remote_gitui_path, remote_cwd)
    local bin = remote_gitui_path or 'gitui'
    if remote_cwd and remote_cwd ~= '' then
        -- cd into the repo; if it fails we still try gitui from $HOME so the user
        -- gets _something_ rather than a closed pane.
        return string.format('cd %s 2>/dev/null; exec %s',
            shell_quote(remote_cwd), shell_quote(bin))
    end
    return 'exec ' .. shell_quote(bin)
end

-- Build the local argv that re-invokes ssh to spawn gitui on the remote host.
-- We pass `-t` to force a PTY (gitui is a TUI) on top of whatever the user's
-- original ssh used.
function M.build_ssh_gitui_argv(parsed, remote_cmd, ssh_extra_args)
    local argv = { parsed and parsed.executable or 'ssh', '-t' }
    if parsed and parsed.port then
        argv[#argv + 1] = '-p'
        argv[#argv + 1] = tostring(parsed.port)
    end
    if ssh_extra_args then
        for _, a in ipairs(ssh_extra_args) do argv[#argv + 1] = a end
    end
    if parsed and parsed.host then
        argv[#argv + 1] = parsed.host
    end
    argv[#argv + 1] = remote_cmd
    return argv
end

-- Classify a pane into one of: 'local', 'ssh_domain', 'ssh_proc'.
--
-- Pure: pass in the things WezTerm would normally tell us. This keeps the
-- module trivially testable.
--
-- Args:
--   domain_name    : string, e.g. 'local' / 'windows-pc'
--   cwd_url        : userdata/table/string from pane:get_current_working_dir()
--   fg_proc_info   : table with .executable/.argv (or nil)
--   local_hostname : string
--   url_helpers    : { cwd_from_url = fn, host_from_url = fn }
--
-- Returns a table:
--   { mode = 'local'      , cwd = '/path' }
--   { mode = 'ssh_domain' , domain = name, cwd = '/remote/path' }
--   { mode = 'ssh_proc'   , parsed = {host=..., port=..., extra=...},
--                            cwd = '/remote/path' or nil }
function M.classify(domain_name, cwd_url, fg_proc_info, local_hostname, url_helpers)
    url_helpers = url_helpers or {}
    local cwd_path = url_helpers.cwd_from_url and url_helpers.cwd_from_url(cwd_url) or nil
    local cwd_host = url_helpers.host_from_url and url_helpers.host_from_url(cwd_url) or nil

    -- Mode B: WezTerm SSH multiplexing domain
    if domain_name and domain_name ~= '' and domain_name ~= 'local'
        and not domain_name:match('^TermWizTerminal') then
        return {
            mode = 'ssh_domain',
            domain = domain_name,
            cwd = cwd_path, -- may be nil if remote shell doesn't emit OSC 7
        }
    end

    -- Mode A: local pane whose foreground process is ssh/mosh
    if fg_proc_info then
        local exe = basename(fg_proc_info.executable)
        if exe == 'ssh' or exe == 'mosh' then
            local parsed = M.parse_ssh_argv(fg_proc_info.argv) or { host = nil }
            -- Prefer cwd info from OSC 7 (remote shell told us). Only trust it
            -- if the URL host doesn't look local — otherwise the cwd is stale
            -- from before ssh kicked in.
            local remote_cwd
            if cwd_host and cwd_host ~= '' and cwd_host ~= 'localhost'
                and cwd_host ~= local_hostname then
                remote_cwd = cwd_path
            end
            return {
                mode = 'ssh_proc',
                parsed = parsed,
                cwd = remote_cwd,
            }
        end
    end

    -- Default: local pane
    return { mode = 'local', cwd = cwd_path }
end

return M
