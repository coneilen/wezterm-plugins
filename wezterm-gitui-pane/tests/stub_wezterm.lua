-- Stub wezterm global for offline tests
local M = {}
M.action = setmetatable({}, { __index = function() return function(...) return { ... } end end })
function M.action_callback(fn) return fn end
function M.on(_, _) end
function M.log_warn(...) end
function M.log_info(...) end
function M.log_error(...) end
function M.format(items)
    local out = {}
    for _, it in ipairs(items) do if it.Text then out[#out + 1] = it.Text end end
    return table.concat(out, '')
end
return M
