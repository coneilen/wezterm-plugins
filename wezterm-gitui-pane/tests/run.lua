package.path = './?.lua;./?/init.lua;' .. package.path
package.loaded['wezterm'] = require('tests.stub_wezterm')

local git = require('plugin.git')
local config_mod = require('plugin.config')

local passed, failed = 0, 0
local function eq(a, e, msg)
    if a == e then passed = passed + 1; print('  ok  - ' .. msg)
    else failed = failed + 1; print(string.format('  FAIL - %s (got=%s want=%s)', msg, tostring(a), tostring(e))) end
end

print('== resolve_repo_root ==')
-- Synthetic filesystem
local fs = {
    ['/home/x/proj/.git'] = true,
    ['/home/x/proj'] = true,
    ['/home/x/proj/src'] = true,
    ['/home/x/proj/src/nested'] = true,
    ['/home/x'] = true,
    ['/elsewhere'] = true,
}
local function exists(p) return fs[p] or false end

eq(git.resolve_repo_root('/home/x/proj', exists, 'walk_up'), '/home/x/proj', 'finds .git at root')
eq(git.resolve_repo_root('/home/x/proj/src/nested', exists, 'walk_up'), '/home/x/proj', 'walks up to find .git')
local nilret, err = git.resolve_repo_root('/elsewhere', exists, 'walk_up')
eq(nilret, nil, 'returns nil when no .git anywhere')
eq(err, 'not_a_repo', 'error tag is not_a_repo')
eq(git.resolve_repo_root('/elsewhere', exists, 'open_anyway'), '/elsewhere', 'open_anyway returns start dir')

print('== cwd_from_url ==')
eq(git.cwd_from_url('file://hostname/home/x/proj'), '/home/x/proj', 'parses file:// URL')
eq(git.cwd_from_url('file:///home/x/proj%20space'), '/home/x/proj space', 'URL-decodes %20')
eq(git.cwd_from_url('/already/a/path'), '/already/a/path', 'passthrough for bare path')
eq(git.cwd_from_url(nil), nil, 'nil returns nil')

print('== build_gitui_argv ==')
local argv = git.build_gitui_argv('/opt/homebrew/bin/gitui', '/repo', { '--theme', 'dark' })
eq(argv[1], '/opt/homebrew/bin/gitui', 'argv[1] is binary')
eq(argv[2], '-d', 'argv[2] -d')
eq(argv[3], '/repo', 'argv[3] repo')
eq(argv[4], '--theme', 'extra arg passed')
eq(argv[5], 'dark', 'extra arg value passed')

print('== parse_branches ==')
local raw = [[
* main
  develop
  remotes/origin/HEAD -> origin/main
  remotes/origin/main
  remotes/origin/feature/x
  (HEAD detached at abc123)
]]
local bs = git.parse_branches(raw)
-- Expected: main(*), develop, origin/main (the HEAD->main line filtered to single entry), origin/main duplicate? Let me recount
-- Actually the lines we keep:
--   "* main" -> main, current
--   "  develop" -> develop
--   "  remotes/origin/HEAD -> origin/main" -> stripped to "origin/HEAD" then arrow stripped -> "origin/HEAD"? 
-- My code does: strip "remotes/" => "origin/HEAD -> origin/main", then strip "%s+%->.*" => "origin/HEAD"
-- Then "remotes/origin/main" => "origin/main"
-- Then "remotes/origin/feature/x" => "origin/feature/x"
-- (HEAD detached) skipped
eq(#bs, 5, '5 branches parsed (detached HEAD skipped)')
eq(bs[1].name, 'main', 'first is main')
eq(bs[1].current, true, 'main is current')
eq(bs[2].name, 'develop', 'second is develop')
eq(bs[3].name, 'origin/HEAD', 'HEAD pointer kept (origin/HEAD)')
eq(bs[3].remote, true, 'HEAD pointer marked remote')
eq(bs[4].name, 'origin/main', 'origin/main parsed')
eq(bs[5].name, 'origin/feature/x', 'origin/feature/x parsed')

print('== parse_log ==')
local US = string.char(31)
local log = "abc123" .. US .. "fix bug" .. US .. "Alice" .. US .. "10 minutes ago\n" ..
            "def456" .. US .. "add feature" .. US .. "Bob" .. US .. "2 hours ago\n"
local cs = git.parse_log(log)
eq(#cs, 2, '2 commits parsed')
eq(cs[1].hash, 'abc123', 'commit 1 hash')
eq(cs[1].subject, 'fix bug', 'commit 1 subject')
eq(cs[2].author, 'Bob', 'commit 2 author')
eq(cs[2].age, '2 hours ago', 'commit 2 age')

print('== config merge ==')
local cfg = config_mod.set({ split = { size = 0.5 }, keys = { toggle = false } })
eq(cfg.split.size, 0.5, 'override split size')
eq(cfg.split.direction, 'Right', 'defaults preserved')
eq(cfg.keys.toggle, false, 'can disable a key')
eq(cfg.keys.branch_pick.key, 'B', 'other keys retained')
eq(cfg.remote_gitui_path, 'gitui', 'remote_gitui_path default')
eq(cfg.use_remote_cwd_from_osc7, true, 'osc7 default on')

print('== host_from_url ==')
eq(git.host_from_url('file://otherhost/home/x'), 'otherhost', 'parses host')
eq(git.host_from_url('file:///home/x'), nil, 'no host returns nil')
eq(git.host_from_url(nil), nil, 'nil input')

print('== remote.parse_ssh_argv ==')
local remote = require('plugin.remote')
local p = remote.parse_ssh_argv({'ssh', 'user@host'})
eq(p.host, 'user@host', 'simple host')
eq(p.port, nil, 'no port')
eq(p.has_command, false, 'no command')

p = remote.parse_ssh_argv({'ssh', '-p', '2222', '-A', 'h', 'ls'})
eq(p.host, 'h', 'host after flags')
eq(p.port, 2222, 'port parsed (separate arg)')
eq(p.has_command, true, 'command detected')
eq(p.extra[1], '-p', 'extra preserves -p')

p = remote.parse_ssh_argv({'ssh', '-p2222', 'h'})
eq(p.port, 2222, 'port parsed (combined form)')

p = remote.parse_ssh_argv({'ssh', '-i', '~/k', '-o', 'StrictHostKeyChecking=no', 'h'})
eq(p.host, 'h', 'host after -i and -o')

eq(remote.parse_ssh_argv({'bash'}), nil, 'non-ssh argv returns nil')
eq(remote.parse_ssh_argv({'/usr/bin/ssh', 'h'}).host, 'h', 'absolute ssh path works')

print('== remote.build_remote_gitui_cmd ==')
eq(remote.build_remote_gitui_cmd(nil, nil), "exec 'gitui'", 'default binary, no cwd')
eq(remote.build_remote_gitui_cmd('/usr/local/bin/gitui', nil),
   "exec '/usr/local/bin/gitui'", 'custom binary, no cwd')
local cmd = remote.build_remote_gitui_cmd('gitui', '/home/me/proj')
eq(cmd, "cd '/home/me/proj' 2>/dev/null; exec 'gitui'", 'cwd-aware command')
-- quoting safety: directories with single quotes shouldn't break the shell
local cmd2 = remote.build_remote_gitui_cmd('gitui', "/tmp/it's me")
eq(cmd2:find("it's me", 1, true) == nil, true, "single-quote escaped (no literal in output)")

print('== remote.build_ssh_gitui_argv ==')
local parsed = { executable = 'ssh', host = 'user@host', port = 2222, extra = {'-A'} }
local argv = remote.build_ssh_gitui_argv(parsed, "exec 'gitui'", {'-A'})
eq(argv[1], 'ssh', 'argv[1] ssh')
eq(argv[2], '-t', 'forces PTY')
eq(argv[3], '-p', 'port flag')
eq(argv[4], '2222', 'port value')
eq(argv[5], '-A', 'extra arg')
eq(argv[6], 'user@host', 'host')
eq(argv[7], "exec 'gitui'", 'remote command')

print('== remote.classify ==')
-- helpers passed to classify
local helpers = {
    cwd_from_url = git.cwd_from_url,
    host_from_url = git.host_from_url,
}

-- Mode local: plain local pane
local c = remote.classify('local', 'file://mybox/home/x', nil, 'mybox', helpers)
eq(c.mode, 'local', 'plain local -> mode=local')
eq(c.cwd, '/home/x', 'local cwd extracted')

-- Mode local: nil domain treated as local
c = remote.classify(nil, 'file://mybox/home/x', nil, 'mybox', helpers)
eq(c.mode, 'local', 'nil domain -> mode=local')

-- Mode ssh_domain: domain_name != local
c = remote.classify('windows-pc', 'file://remote/srv/repo', nil, 'mybox', helpers)
eq(c.mode, 'ssh_domain', 'non-local domain -> mode=ssh_domain')
eq(c.domain, 'windows-pc', 'domain name preserved')
eq(c.cwd, '/srv/repo', 'remote cwd from OSC 7')

-- TermWizTerminal pseudo-domain is local-ish
c = remote.classify('TermWizTerminalDomain', 'file://mybox/home/x', nil, 'mybox', helpers)
eq(c.mode, 'local', 'TermWizTerminal* not treated as remote')

-- Mode ssh_proc: ssh foreground process in local pane
c = remote.classify('local',
    'file://mybox/home/x',                                    -- stale local cwd
    { executable = '/usr/bin/ssh', argv = {'ssh', 'user@h'} },
    'mybox', helpers)
eq(c.mode, 'ssh_proc', 'ssh in fg -> mode=ssh_proc')
eq(c.parsed.host, 'user@h', 'parsed host')
eq(c.cwd, nil, 'cwd ignored when URL host matches local')

-- ssh_proc with remote OSC 7 cwd (different host)
c = remote.classify('local',
    'file://remotebox/srv/repo',
    { executable = 'ssh', argv = {'ssh', 'remotebox'} },
    'mybox', helpers)
eq(c.mode, 'ssh_proc', 'still ssh_proc')
eq(c.cwd, '/srv/repo', 'remote cwd accepted (different host)')

-- mosh is treated like ssh
c = remote.classify('local', nil,
    { executable = '/usr/local/bin/mosh', argv = {'mosh', 'host'} },
    'mybox', helpers)
eq(c.mode, 'ssh_proc', 'mosh treated as ssh_proc')

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
