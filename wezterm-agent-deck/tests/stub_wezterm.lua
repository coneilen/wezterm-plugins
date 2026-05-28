-- Stub of the `wezterm` global for offline unit tests
local M = {}
M.events = {}
function M.on(name, handler) M.events[name] = handler end
function M.log_warn(...) end
function M.log_info(...) end
function M.log_error(...) end
function M.format(items)
    local out = {}
    for _, it in ipairs(items) do
        if it.Text then out[#out + 1] = it.Text end
    end
    return table.concat(out, '')
end
function M.background_child_process(_) end
return M
