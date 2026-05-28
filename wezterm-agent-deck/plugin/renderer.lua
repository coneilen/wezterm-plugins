-- Tab title + right status rendering helpers
local M = {}

local STATUS_ORDER = { 'waiting', 'working', 'idle', 'inactive' }

local function priority(status)
    for i, s in ipairs(STATUS_ORDER) do if s == status then return i end end
    return #STATUS_ORDER + 1
end

function M.aggregate_status(states)
    local best, agent
    for _, st in pairs(states) do
        if st.agent and (not best or priority(st.status) < priority(best)) then
            best = st.status
            agent = st.agent
        end
    end
    return best, agent
end

function M.format_tab_title(states_for_tab, cfg, helpers)
    local out = {}
    local best, _ = M.aggregate_status(states_for_tab)
    if not best then return nil end

    local icon = helpers.icon(best)
    local color = helpers.color(best)
    table.insert(out, { Foreground = { Color = color } })
    table.insert(out, { Text = icon })

    if cfg.tab_title.show_label then
        local labels = {}
        local seen = {}
        for _, st in pairs(states_for_tab) do
            if st.agent and not seen[st.agent] then
                seen[st.agent] = true
                labels[#labels + 1] = helpers.label(st.agent)
            end
        end
        if #labels > 0 then
            table.insert(out, { Text = ' ' .. table.concat(labels, ',') })
        end
    end
    table.insert(out, { Text = cfg.tab_title.separator or ' ' })
    return out
end

function M.format_right_status(all_states, cfg, helpers)
    -- group by agent -> { status -> count }
    local by_agent = {}
    for _, st in pairs(all_states) do
        if st.agent then
            by_agent[st.agent] = by_agent[st.agent] or { working = 0, waiting = 0, idle = 0 }
            by_agent[st.agent][st.status] = (by_agent[st.agent][st.status] or 0) + 1
        end
    end

    local segments = {}
    local agent_names = {}
    for a in pairs(by_agent) do agent_names[#agent_names + 1] = a end
    table.sort(agent_names)

    for _, a in ipairs(agent_names) do
        local counts = by_agent[a]
        if cfg.right_status.show_labels then
            table.insert(segments, { Foreground = { Color = helpers.color('inactive') } })
            table.insert(segments, { Text = helpers.label(a) .. ':' })
        end
        for _, s in ipairs({ 'waiting', 'working', 'idle' }) do
            if counts[s] and counts[s] > 0 then
                table.insert(segments, { Foreground = { Color = helpers.color(s) } })
                local txt = helpers.icon(s)
                if cfg.right_status.show_counts then txt = txt .. tostring(counts[s]) end
                table.insert(segments, { Text = txt .. ' ' })
            end
        end
        table.insert(segments, { Text = ' ' })
    end
    return segments
end

return M
