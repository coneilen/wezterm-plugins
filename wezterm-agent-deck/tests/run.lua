-- Minimal test runner. Run with:  lua tests/run.lua
package.path = './?.lua;./?/init.lua;' .. package.path

-- Install wezterm stub before plugin modules load
package.loaded['wezterm'] = require('tests.stub_wezterm')

local config_mod = require('plugin.config')
local detector = require('plugin.detector')
local status_mod = require('plugin.status')

local passed, failed = 0, 0
local function assertEq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print('  ok  - ' .. msg)
    else
        failed = failed + 1
        print(string.format('  FAIL - %s (expected=%s actual=%s)',
            msg, tostring(expected), tostring(actual)))
    end
end

local function fake_pane(opts)
    return {
        pane_id = function() return opts.id or 1 end,
        get_foreground_process_info = function() return opts.proc end,
        get_foreground_process_name = function() return opts.proc and opts.proc.executable end,
        get_title = function() return opts.title or '' end,
        get_lines_as_text = function(_) return opts.text or '' end,
    }
end

print('== detector ==')
local cfg = config_mod.set({})

-- Claude
local p_claude = fake_pane({
    id = 10,
    proc = { executable = '/Users/me/.claude/bin/claude', name = 'claude', argv = { 'claude' } },
})
assertEq(detector.detect_agent(p_claude, cfg), 'claude', 'claude detected by .claude/bin path')

local p_claude_npm = fake_pane({
    id = 11,
    proc = { executable = '/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js',
             name = 'node', argv = { 'node', 'cli.js' } },
})
assertEq(detector.detect_agent(p_claude_npm, cfg), 'claude', 'claude detected via npm path')

-- GitHub Copilot CLI
local p_ghcp = fake_pane({
    id = 20,
    proc = { executable = '/Users/colinneilens/.copilot-cli/1.0.48/copilot',
             name = 'copilot', argv = { 'copilot', '--continue' } },
})
assertEq(detector.detect_agent(p_ghcp, cfg), 'copilot_cli', 'ghcp detected by .copilot-cli versioned path')

-- Path variants we want to keep matching across upgrades
local ghcp_variants = {
    '/Users/me/.copilot-cli/1.2.3-beta.4/copilot',
    '/Users/me/.copilot-cli/current/copilot',
    '/Users/me/.copilot-cli/nightly/copilot',
    '/Users/me/.copilot/cli/2.0.0/copilot',
    '/opt/homebrew/Cellar/github-copilot-cli/1.0.0/bin/copilot',
    '/opt/homebrew/bin/copilot',
    '/usr/local/bin/copilot',
}
for _, path in ipairs(ghcp_variants) do
    local p = fake_pane({ id = 25, proc = { executable = path, name = 'copilot', argv = { path } } })
    assertEq(detector.detect_agent(p, cfg), 'copilot_cli', 'ghcp variant: ' .. path)
    detector.clear_cache(25)
end

-- Windows path variants (backslashes, .exe, AppData npm globals)
local ghcp_windows = {
    'C:\\Users\\me\\.copilot-cli\\1.0.54\\copilot.exe',
    'C:\\Users\\me\\.copilot-cli\\current\\copilot.exe',
    'C:\\Users\\me\\AppData\\Roaming\\npm\\node_modules\\@github\\copilot\\bin\\copilot.js',
    'C:\\Program Files\\GitHub CLI\\copilot.exe',
}
for _, path in ipairs(ghcp_windows) do
    local p = fake_pane({ id = 26, proc = { executable = path, name = 'copilot.exe', argv = { path } } })
    assertEq(detector.detect_agent(p, cfg), 'copilot_cli', 'ghcp windows: ' .. path)
    detector.clear_cache(26)
end

-- Windows Claude variants
local claude_windows = {
    'C:\\Users\\me\\.claude\\bin\\claude.exe',
    'C:\\Users\\me\\AppData\\Roaming\\npm\\node_modules\\@anthropic-ai\\claude-code\\cli.js',
}
for _, path in ipairs(claude_windows) do
    local p = fake_pane({ id = 27, proc = { executable = path, name = 'claude.exe', argv = { path } } })
    assertEq(detector.detect_agent(p, cfg), 'claude', 'claude windows: ' .. path)
    detector.clear_cache(27)
end

local p_ghcp_npm = fake_pane({
    id = 21,
    proc = { executable = '/usr/local/lib/node_modules/@github/copilot/bin/copilot.js',
             name = 'node', argv = { 'node', 'copilot.js' } },
})
assertEq(detector.detect_agent(p_ghcp_npm, cfg), 'copilot_cli', 'ghcp detected via npm @github/copilot path')

local p_ghcp_child = fake_pane({
    id = 22,
    proc = { executable = '/bin/bash', name = 'bash', argv = { 'bash' },
             children = { { executable = '/usr/local/bin/copilot', name = 'copilot', argv = { 'copilot' } } } },
})
assertEq(detector.detect_agent(p_ghcp_child, cfg), 'copilot_cli', 'ghcp detected via child process walk')

-- No agent
local p_none = fake_pane({
    id = 30,
    proc = { executable = '/bin/zsh', name = 'zsh', argv = { 'zsh' } },
})
assertEq(detector.detect_agent(p_none, cfg), nil, 'no agent for plain shell')

print('== status ==')

local working_pane = fake_pane({ id = 100, text = 'doing things\nthinking...\n' })
assertEq(status_mod.detect_status(working_pane, 'claude', cfg), 'working', 'claude working from "thinking"')

local waiting_pane = fake_pane({ id = 101, text = 'Allow bash to run `rm -rf /tmp/x`?\n❯ Yes\n  No\n' })
assertEq(status_mod.detect_status(waiting_pane, 'copilot_cli', cfg), 'waiting', 'ghcp waiting on approval prompt')

local idle_pane = fake_pane({ id = 102, text = 'welcome\n\n>\n' })
assertEq(status_mod.detect_status(idle_pane, 'claude', cfg), 'idle', 'claude idle on bare prompt')

local idle_pane2 = fake_pane({ id = 103, text = 'how can I help today?\n> ' })
assertEq(status_mod.detect_status(idle_pane2, 'copilot_cli', cfg), 'idle', 'ghcp idle on prompt')

local inactive = fake_pane({ id = 104, text = '' })
assertEq(status_mod.detect_status(inactive, nil, cfg), 'inactive', 'inactive when no agent')

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
